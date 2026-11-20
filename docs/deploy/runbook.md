# ZayPOS production runbook

One Vultr server (Ubuntu 24.04, 4 GB, Singapore; production: `45.32.114.207`). The API is at **https://api.zaypos.app**,
**straight to the server** (Cloudflare DNS only, no proxy), with a Let's Encrypt certificate that Caddy gets and renews
itself.

```
phone ──https :443 / http :80 (→ https)──▶ Caddy (Let's Encrypt) ──▶ API :8080 ──▶ SQL Server
                                     (only Caddy has ports; SQL Server has none)
```

**Why not behind Cloudflare (2026-11-20):** Myanmar networks without a VPN cut TLS connections to Cloudflare-proxied
hosts (`ERR_CONNECTION_CLOSED` in Chrome on a phone on home Wi-Fi, also `www.cloudflare.com`; `www.google.com` worked),
so the app could not sign in. A Mac with a VPN (Outline) does not see this: test with the VPN **off**. The website
`zaypos.app` stays on Cloudflare Pages (docs/deploy/website.md); only the `api` record is DNS only.

Where things live:

| What | Where |
|---|---|
| Deploy files (in git) | `deploy/` in this repo |
| On the server | `/home/deploy/zaypos/`: `docker-compose.prod.yml`, `Caddyfile`, `*.sh`, **`.env`** (secrets), `caddy-data/` (Let's Encrypt account + certificate, 0700), `backups/`, `releases.log` |
| Secrets | only `/home/deploy/zaypos/.env` on the server (chmod 600) and your password manager. Never in git |
| Database | Docker volume `zaypos_mssql-data`. Nightly backup (02:00 Myanmar time) to Cloudflare R2, bucket `zaypos-backups`, kept 30 days; the 7 newest are never deleted, even if backups stopped for a while. Plus one before every deploy |
| Logs | `docker compose logs <service>` (JSON lines; 5 × 10 MB per container, then rotated) |

Commands on the server are run as **deploy** in `~/zaypos` unless it says otherwise. `<ip>` = the server's IP.

---

## 1. First-time setup (once)

### 1.1 Things to prepare by hand first

Do these before touching the server. Keep every secret in your password manager.

1. **TLS certificate:** nothing to prepare. Caddy gets one from Let's Encrypt on its first start once DNS points at the
   server and ports 80/443 are open (§1.2), and renews it itself (about 30 days before it expires).
2. *(removed: the Cloudflare origin certificate and origin-pull CA are no longer used.)*
3. **R2 backup bucket.** Cloudflare → R2 → Create bucket `zaypos-backups` (location hint: Asia-Pacific).
   Then R2 → Manage API tokens → Create **Account API token**: permission **Object Read & Write**, applied to
   **only** `zaypos-backups`. Note the **Access Key ID**, **Secret Access Key** and your **Account ID**.
4. **SMSPoh.** smspoh.com dashboard → Accounts & Security → API Credentials → create a v3 credential and whitelist
   it to the server's IP (the API calls SMSPoh over IPv4 only). Note the key, the secret and the approved **Sender ID**
   if you have one (empty = SMSPoh's default sender).
5. **Server.** Vultr → Deploy → Cloud Compute, Singapore, Ubuntu 24.04 LTS x64, 4 GB, **SSH key** (add your Mac's
   `~/.ssh/id_ed25519.pub`). Vultr's automatic backups are optional (a weekly image on top of the nightly SQL backup).
   Note the IP and the root password Vultr shows: that password is your way in through Vultr's web console if SSH
   ever locks you out.
6. **Docker on your Mac** (Docker Desktop) for building the image.

### 1.2 DNS and Cloudflare settings

Cloudflare → zaypos.app → DNS (the domain's DNS stays at Cloudflare; the website `zaypos.app` stays proxied):

- Record **A**, name `api`, IPv4 `<ip>`, **DNS only (grey cloud)**. Not proxied: see the top of this file.
- No AAAA record for `api` unless the server's IPv6 is also open in the Vultr firewall.
- Cloudflare's SSL/TLS settings (Full strict, Always Use HTTPS, Authenticated Origin Pulls) don't apply to a DNS-only
  record; Caddy does all of it (redirect, TLS 1.2+, HSTS).

Vultr → Network → **Firewall** → Firewall Group `zaypos`, linked to the server (server → Settings → Firewall). Rules
for **IPv4 and IPv6**:

| Protocol | Port | Source |
|---|---|---|
| SSH | 22 | your IP (or "Anywhere" if your IP changes; fail2ban and key-only login still protect it) |
| HTTP | 80 | **Anywhere** (http→https redirect, and Let's Encrypt's HTTP-01 check) |
| HTTPS | 443 | **Anywhere** (phones; Let's Encrypt's TLS-ALPN check) |

Docker opens published ports past ufw, so this group is what really filters; ufw (server-setup.sh) allows 22, 80, 443
too. If 80 and 443 are both closed, Caddy can't renew the certificate (renewal starts ~30 days before expiry).

### 1.3 Harden the server

Two steps, so you cannot lock yourself out. On your Mac, from the repo:

```bash
scp -r deploy root@<ip>:/root/deploy
ssh -t root@<ip> "bash /root/deploy/server-setup.sh '$(cat ~/.ssh/id_ed25519.pub)'"
```

(`$(cat …)` runs on your Mac and passes your public key; `-t` lets the script ask for a sudo password for deploy.
Without a terminal it skips that: daily work needs no sudo.)

Step 1 of the script:
- installs updates, ufw, fail2ban and unattended-upgrades;
- creates the user **deploy** with your SSH key (sudo password: store it in your password manager);
- opens the firewall (ufw) for 22 (rate-limited), 80 and 443 only;
- adds 2 GB swap, installs Docker, copies the deploy files to `/home/deploy/zaypos/`;
- installs the nightly backup timer (02:00 Myanmar time).

SSH is **not** locked down yet. Prove the key login as deploy in a **new** connection:

```bash
ssh deploy@<ip> 'id'   # must print uid=1000(deploy) … docker
```

Then step 2 turns off root login and password login. It refuses to run unless sshd's own log shows that key login
from the last 2 hours:

```bash
ssh root@<ip> 'bash /root/deploy/server-setup.sh --lock-ssh'
ssh deploy@<ip> 'id'    # must still work
ssh root@<ip>           # must say "Permission denied"
```

Locked out anyway? Vultr → the server → **View Console** (a screen, not SSH): log in as root with the password from
the Vultr dashboard, then `rm /etc/ssh/sshd_config.d/00-zaypos.conf && systemctl restart ssh`.

`/root/deploy` holds no secrets (only the files that are in git); it can stay.

### 1.4 Secrets

No certificate files to copy: Caddy gets the certificate itself into `caddy-data/` (release.sh creates it 0700).
On the server:

```bash
cd ~/zaypos
cp .env.example .env && chmod 600 .env
nano .env
```

Fill in every `<…>` value (see the comments in the file). Make each password with
`openssl rand -base64 32 | tr -d '/+=' | cut -c1-32` and the JWT key with `openssl rand -base64 48 | tr -d '\n'`.
Put all of them in your password manager too. For the very first SMS test leave `SMSPOH_TEST=true`.
Set `DEPLOY_UID` / `DEPLOY_GID` to the output of `id -u` / `id -g` (on Vultr usually 1001: the image already has
`linuxuser` as 1000). Leave `API_TAG=` empty: the deploy fills it in. Every script refuses to run while a `<…>` placeholder is left
(it names the keys).

**SMSPoh not ready yet?** Set `SMS_PROVIDER=Console` and `SMSPOH_TOKEN=` (empty). No SMS is sent: the code is in the
API log, `docker compose logs api | grep 'DEV SMS'`, and the API logs a CRITICAL warning at every start. Switch to
`SmsPoh` (§1.6 step 4) before real shops register: anyone who can read the logs could sign in to any shop.

### 1.5 First deploy

On your Mac, from the repo (on the commit you want to ship):

```bash
deploy/deploy.sh deploy@<ip>
```

It builds the API image, uploads it, runs `release.sh` on the server (start SQL Server → apply migrations and
create the API's SQL login → start the API → start Caddy) and finally calls `https://api.zaypos.app/health`.
Success ends with `{"status":"healthy","checks":{"database":"healthy"}}` and `Deployed zaypos-api:<tag>`.
On the very first start Caddy needs a few seconds for the Let's Encrypt certificate (DNS must already point at the
server and 80/443 be open, §1.2): `docker compose logs caddy | grep -i certificate` shows "certificate obtained
successfully".

### 1.6 Check it

1. `curl https://api.zaypos.app/health` → `healthy`. **With the Mac's VPN off**, and from a phone on Myanmar Wi-Fi /
   mobile data without a VPN (Chrome, or `adb shell curl`): that's the path shops use.
2. `curl -I https://api.zaypos.app/swagger/index.html` → **404** (Swagger is off).
3. `curl -I http://api.zaypos.app/health` → **308** to `https://` ; `curl -sI https://api.zaypos.app/health | grep -i strict`
   → `Strict-Transport-Security`.
4. Certificate: `openssl s_client -connect api.zaypos.app:443 -servername api.zaypos.app </dev/null 2>/dev/null |
   openssl x509 -noout -issuer -dates` → issuer Let's Encrypt (R1x / E…, chained to ISRG Root X1, trusted from
   Android 7.1.1).
5. **SMS smoke test** (no real SMS, no credit). In `.env`: `SMS_PROVIDER=SmsPoh`, `SMSPOH_API_KEY=`, `SMSPOH_API_SECRET=`
   (pasted from the SMSPoh dashboard), `SMSPOH_TEST=true`; re-release (`./release.sh <current tag>`). Ask an OTP for
   your own number (counts 1 of the 3 per hour):
   `curl -sS https://api.zaypos.app/api/v1/auth/otp -H 'Content-Type: application/json' -d '{"phone":"+959…","purpose":"register"}'`
   → HTTP 204/200 and, in `docker compose logs api | grep SMSPoh`, `SMS accepted in TEST mode (not delivered) … HTTP 200`.
   A refusal logs `SMSPoh refused SMS to … HTTP <status> <SMSPoh's reply>` (digits masked, never the credential) and the
   app gets 503 `sms_unavailable`: 401 = key/secret wrong, 403 = IP not whitelisted (must be the server's IPv4).
6. Set `SMSPOH_TEST=false` in `.env`, then `./release.sh $(grep ^API_TAG= .env | cut -d= -f2)` (re-deploys the same
   version with the new setting). Register again: the SMS must arrive.
7. Run a backup now and a restore test (§3): `./backup.sh` then `./restore.sh latest`.
8. Build the release app with `--dart-define=API_BASE_URL=https://api.zaypos.app` (docs/mobile/dev-setup.md).

---

## 2. Deploy an update

1. On your Mac: merge to `main`, `git pull`, make sure the tree is clean.
2. Run the suites (`cd backend && dotnet test`).
3. Optional: `deploy/deploy.sh deploy@<ip> --dry-run` changes nothing. It checks the login and shows which deploy
   files would change and which release runs now.
4. `deploy/deploy.sh deploy@<ip>`

All of it goes over **one** SSH connection: the server allows only 6 new SSH connections per 30 s.

What happens on the server, in order (each step stops the deploy on failure):

| Step | On failure |
|---|---|
| 1. Backup to R2 (safety copy before any migration) | nothing changed |
| 2. SQL Server up and healthy | nothing changed |
| 3. `migrate` with the **new** image | `API_TAG` put back, the old API keeps running |
| 4. New API started, waits for `healthy` (DB check) | the old image is started again automatically |
| 5. Caddy | |

Phones keep working through a deploy except for the few seconds while the API container is swapped; their
outbox simply syncs a little later.

Log of what ran when: `cat ~/zaypos/releases.log`.

---

## 3. Restore test (monthly, see §8)

On the server:

```bash
cd ~/zaypos
./restore.sh list                  # backups on R2, newest first
./restore.sh latest                # or: ./restore.sh zaypos-20261201T193000Z.bak.gz
```

It downloads the backup, restores it into a **separate** database `ZayPOS_restoretest` (production is never
touched), runs `DBCC CHECKDB`, and prints the number of shops, devices, products, customers, sales and the last
sale time. Compare with the real numbers:

```bash
source lib.sh && load_env && sql -d ZayPOS -W -Q "SELECT COUNT(*) AS Sales, MAX(CreatedAt) AS LastSaleUtc FROM dbo.Sales"
```

The restored copy should have the same counts up to the backup time. Then clean up:

```bash
./restore.sh drop
```

If `restore.sh` fails, backups are not usable: fix that before anything else.

---

## 4. Rollback

**Code only (no migration in the bad release, the usual case):**

```bash
cd ~/zaypos
./release.sh previous
```

It starts the image that ran before the last deploy (the 5 newest images are kept on the server). Check
`curl https://api.zaypos.app/health`.

**The bad release had a migration:** the old code usually still works on the new schema (migrations only add).
Try `./release.sh previous` first. If the old API refuses to start or misbehaves, restore the database from the
backup taken just before that deploy (§5). Sales made after that backup are on the phones' outboxes only if they
were not synced yet, so a database restore loses synced data: decide carefully, and prefer a forward fix.

---

## 5. Real disaster restore (production database)

Only when the production database is lost or corrupt.

1. Stop the API so nothing writes: `docker compose stop api caddy`.
2. Restore the chosen backup **over** production (the guard needs the exact phrase):
   ```bash
   ZAYPOS_RESTORE_PRODUCTION="I understand" ./restore.sh zaypos-<stamp>.bak.gz ZayPOS
   ```
3. Re-apply migrations and the API login, start everything:
   `./release.sh $(grep ^API_TAG= .env | cut -d= -f2)` (it takes a backup first; `SKIP_BACKUP=1` if the DB is broken).
4. Check `/health`, then one phone: pull works, a test sale syncs.

**Whole server lost:** new Vultr server → §1.3 → §1.4 with the same `.env` (from your password manager) and certs →
first deploy creates an empty database → stop the API (step 1 above) → step 2 → step 3. Update the DNS A record
if the IP changed.

---

## 6. Troubleshooting

| Symptom | Look at |
|---|---|
| App: "အင်တာနက် မရပါ" but other apps work; Chrome on the phone: `ERR_CONNECTION_CLOSED` | the `api` DNS record was switched back to **Proxied**: Myanmar networks cut Cloudflare-proxied connections. Cloudflare → DNS → `api` → **DNS only** |
| TLS error / certificate warning on `api.zaypos.app` | Caddy has no valid certificate: `docker compose logs caddy | grep -iE "certificate|acme|challenge"`. Usual causes: DNS not pointing at the server yet, or 80 **and** 443 closed in the Vultr firewall (§1.2). Let's Encrypt allows 5 failed checks per hour: fix, then `docker compose restart caddy` |
| Connection refused / timeout on 443 | Caddy not running or the Vultr firewall closed: `docker compose ps`, Vultr → Firewall → `zaypos` |
| 502 from Caddy | API not healthy: `docker compose ps`, `docker compose logs --tail 100 api` |
| API log: `pending EF migration(s)` | the migrate step did not run: `docker compose run --rm migrate` |
| API log: `Unsafe production configuration` | the listed `.env` value (SMS provider/token, sa login, HTTPS) |
| `{"status":"unhealthy"…}` | SQL Server down or the API login broken: `docker compose logs mssql`, then `docker compose run --rm migrate` (re-creates the login) |
| OTP never arrives | `docker compose logs api | grep -i sms`: `refused HTTP 401` = token, `unreachable` = network; `SMSPOH_TEST` must be `false` |
| Backup failed | `journalctl -u zaypos-backup --since today`; run `./backup.sh` by hand to see the error |
| `ssh` suddenly says "Connection closed" | ufw allows only 6 new SSH connections per 30 s from one IP (and fail2ban bans for 1 h after 5 failed logins). Wait a minute; for scripts, reuse one connection (`ControlMaster auto` in `~/.ssh/config`) |
| `ssh` hangs: "Connection timed out during banner exchange" | something drops your address in front of the server, and a VPN on your Mac (Outline, WARP, …) hides it: its client accepts every connection itself, so a blocked port looks "connected, then silent". The server sees the VPN's exit address (`curl https://api.ipify.org`). Check the Vultr Firewall group: port 22 must be allowed in the **IPv4** rules (0.0.0.0/0, or that exit address). `/health` (port 443) keeps working meanwhile |
| Disk full | `df -h`, `docker system df`; old images: `docker image prune`; local backups are kept 3 days in `backups/` |

Useful commands:

```bash
docker compose ps                         # what runs, health
docker compose logs -f --tail 50 api      # live API log (JSON)
systemctl list-timers zaypos-backup.timer # next backup
sudo fail2ban-client status sshd          # banned SSH attackers
```

## 7. Secrets rotation

| Secret | How |
|---|---|
| `DB_APP_PASSWORD` | change in `.env`, then `./release.sh <current tag>` (migrate sets the new password, the API restarts) |
| `MSSQL_SA_PASSWORD` | SQL Server only reads it on the very first start. Change it inside first: `source lib.sh && load_env && sql -Q "ALTER LOGIN sa WITH PASSWORD = N'<new>'"`, then put the same value in `.env` and `docker compose up -d mssql` |
| `JWT_SIGNING_KEY` | change in `.env`, re-release. Every phone must sign in again with its PIN on the next sync |
| `SMSPOH_TOKEN`, R2 keys | create the new one, put it in `.env`, re-release (R2 backup keys: no re-release needed), then revoke the old one |
| TLS certificate | nothing to do: Caddy renews it about 30 days before it expires (needs 80 or 443 open, §1.2). Check: `openssl s_client -connect api.zaypos.app:443 -servername api.zaypos.app </dev/null 2>/dev/null \| openssl x509 -noout -dates` |

## 8. Monthly checklist (about 15 minutes)

First Monday of the month, as deploy: `ssh deploy@<ip>`, then `cd ~/zaypos`. Write the date and the results down.

- [ ] **Backups exist.** `./restore.sh list`: the newest is from last night (names are UTC: `T19…Z` = 02:00 Myanmar),
      and there is one per night for about 30 days. A gap means a backup failed: run `./backup.sh` by hand to see why.
- [ ] **The backup timer is on.** `systemctl list-timers zaypos-backup.timer` shows the next run tonight.
- [ ] **Restore test** (§3): `./restore.sh latest`, compare the counts with production, then `./restore.sh drop`.
      If it fails, fixing backups comes before anything else.
- [ ] **Running cleanly.** `docker compose ps`: all `healthy`. Crash loops: `docker inspect -f '{{.Name}} {{.RestartCount}}' $(docker compose ps -q)` shows 0, or the same as last month.
- [ ] **Disk.** `df -h /` has more than 10 GB free. `docker system df`; old images: `docker image prune`.
- [ ] **Reboot pending?** `test -f /var/run/reboot-required && echo yes`. Unattended upgrades reboot at 04:00
      Myanmar time on their own; "yes" for days means that is not happening.
