# ZayPOS production runbook

One DigitalOcean droplet (Ubuntu 24.04, 4 GB, Singapore). The API is at **https://api.zaypos.app** behind Cloudflare
(proxied, SSL/TLS mode **Full (strict)**).

```
phone ──https──▶ Cloudflare ──https :443 (origin cert + Authenticated Origin Pulls)──▶ Caddy ──▶ API :8080 ──▶ SQL Server
                                                                                 (only Caddy has a port; SQL Server has none)
```

Where things live:

| What | Where |
|---|---|
| Deploy files (in git) | `deploy/` in this repo |
| On the server | `/home/deploy/zaypos/`: `docker-compose.prod.yml`, `Caddyfile`, `*.sh`, **`.env`** (secrets), `certs/`, `backups/`, `releases.log` |
| Secrets | only `/home/deploy/zaypos/.env` on the server (chmod 600) and your password manager. Never in git |
| Database | Docker volume `zaypos_mssql-data`. Nightly backup (02:00 Myanmar time) to Cloudflare R2, bucket `zaypos-backups`, kept 30 days; the 7 newest are never deleted, even if backups stopped for a while. Plus one before every deploy |
| Logs | `docker compose logs <service>` (JSON lines; 5 × 10 MB per container, then rotated) |

Commands on the server are run as **deploy** in `~/zaypos` unless it says otherwise. `<ip>` = the droplet's IP.

---

## 1. First-time setup (once)

### 1.1 Things to prepare by hand first

Do these before touching the server. Keep every secret in your password manager.

1. **Cloudflare origin certificate.** Cloudflare dashboard → zaypos.app → SSL/TLS → Origin Server → **Create Certificate**.
   RSA 2048, hostnames `api.zaypos.app` (and `*.zaypos.app` if you like), 15 years. Save the two boxes on your Mac as
   `origin.pem` (certificate) and `origin.key` (private key). The key is shown **only once**.
2. **Cloudflare origin-pull CA.** Download Cloudflare's Authenticated Origin Pulls CA certificate
   (developers.cloudflare.com → SSL/TLS → Origin configuration → Authenticated Origin Pulls → "zone-level" →
   `authenticated_origin_pull_ca.pem`). Save it as `cloudflare-origin-pull-ca.pem`.
3. **R2 backup bucket.** Cloudflare → R2 → Create bucket `zaypos-backups` (location hint: Asia-Pacific).
   Then R2 → Manage API tokens → Create **Account API token**: permission **Object Read & Write**, applied to
   **only** `zaypos-backups`. Note the **Access Key ID**, **Secret Access Key** and your **Account ID**.
4. **SMSPoh.** smspoh.com dashboard → Accounts & Security → API Credentials → create a v3 key. Make the token on
   your Mac: `printf '%s' '<API key>:<API secret>' | base64`. Note the approved **Sender ID** if you have one.
5. **Droplet.** DigitalOcean → Create Droplet: Ubuntu 24.04 LTS, Singapore, Basic 4 GB, **SSH key** authentication
   (add your Mac's `~/.ssh/id_ed25519.pub`), enable backups if you want DO's weekly image too. Note the IP.
6. **Docker on your Mac** (Docker Desktop) for building the image.

### 1.2 DNS and Cloudflare settings

Cloudflare → zaypos.app:

- DNS → Add record: **A**, name `api`, IPv4 `<ip>`, **Proxied (orange cloud)**.
- SSL/TLS → Overview → **Full (strict)**.
- SSL/TLS → Edge Certificates → **Always Use HTTPS: On**, **Minimum TLS Version: 1.2**.
- SSL/TLS → Origin Server → **Authenticated Origin Pulls: On**.
  Caddy refuses every TLS connection that does not present Cloudflare's client certificate. If this switch is off,
  the site answers Cloudflare error **525/526** instead of the API.

### 1.3 Harden the droplet

First open a **second** terminal with `ssh root@<ip>` and leave it open: if anything locks you out, that session
still works. Then, in the first terminal on your Mac, from the repo:

```bash
scp -r deploy root@<ip>:/root/deploy
ssh -t root@<ip> "bash /root/deploy/server-setup.sh '$(cat ~/.ssh/id_ed25519.pub)'"
```

(`$(cat …)` runs on your Mac and passes your public key; `-t` lets the script ask for a password.)

The script:
- installs updates, ufw, fail2ban and unattended-upgrades;
- creates the user **deploy** with your SSH key and asks you for a **sudo password** (store it: you need it for
  `sudo` and for the DigitalOcean recovery console);
- turns off root login and password login for SSH;
- opens the firewall for 22 (rate-limited) and 443 only;
- adds 2 GB swap, installs Docker, copies the deploy files to `/home/deploy/zaypos/`;
- installs the nightly backup timer (02:00 Myanmar time).

Now, still keeping the second root window open, in a new terminal on your Mac:

```bash
ssh deploy@<ip>        # must work
ssh root@<ip>          # must say "Permission denied"
```

Only then close the root window. (Locked out anyway? DigitalOcean → droplet → Access → Recovery Console, log in as
deploy with the sudo password.) Then remove the copy: `ssh deploy@<ip> 'sudo rm -rf /root/deploy'`.

### 1.4 Certificates and secrets

From your Mac:

```bash
scp origin.pem origin.key cloudflare-origin-pull-ca.pem deploy@<ip>:zaypos/certs/
ssh deploy@<ip> 'chmod 600 zaypos/certs/*'
```

On the server:

```bash
cd ~/zaypos
cp .env.example .env && chmod 600 .env
nano .env
```

Fill in every `<…>` value (see the comments in the file). Make each password with
`openssl rand -base64 32 | tr -d '/+=' | cut -c1-32` and the JWT key with `openssl rand -base64 48 | tr -d '\n'`.
Put all of them in your password manager too. For the very first SMS test leave `SMSPOH_TEST=true`.
Leave `API_TAG=` empty: the deploy fills it in.

### 1.5 First deploy

On your Mac, from the repo (on the commit you want to ship):

```bash
deploy/deploy.sh deploy@<ip>
```

It builds the API image, uploads it, runs `release.sh` on the server (start SQL Server → apply migrations and
create the API's SQL login → start the API → start Caddy) and finally calls `https://api.zaypos.app/health`.
Success ends with `{"status":"healthy","checks":{"database":"healthy"}}` and `Deployed zaypos-api:<tag>`.

### 1.6 Check it

1. `curl https://api.zaypos.app/health` → `healthy`.
2. `curl -I https://api.zaypos.app/swagger/index.html` → **404** (Swagger is off).
3. `curl -k https://<ip>/health` (straight to the server, skipping Cloudflare) → a TLS error (Caddy wants Cloudflare's
   client certificate). That is correct.
4. **SMS smoke test** (`SMSPOH_TEST=true`): on a phone, start registering with your own number. The API log must
   say `SMS sent to +9597…***.. via SMSPoh` (`docker compose logs api | grep SMS`). If it says `SMSPoh refused … HTTP 401`,
   the token is wrong. The token format (Bearer + base64 of `key:secret`) has **not** been tried against the real
   SMSPoh yet: if 401 persists, check SMSPoh's v3 REST docs (dashboard → Developers) for the exact Bearer value,
   put that in `SMSPOH_TOKEN` and re-release; no code change is needed for a different token value.
5. Set `SMSPOH_TEST=false` in `.env`, then `./release.sh $(grep ^API_TAG= .env | cut -d= -f2)` (re-deploys the same
   version with the new setting). Register again: the SMS must arrive.
6. Run a backup now and a restore test (§3): `./backup.sh` then `./restore.sh latest`.
7. Build the release app with `--dart-define=API_BASE_URL=https://api.zaypos.app` (docs/mobile/dev-setup.md).

---

## 2. Deploy an update

1. On your Mac: merge to `main`, `git pull`, make sure the tree is clean.
2. Run the suites (`cd backend && dotnet test`).
3. `deploy/deploy.sh deploy@<ip>`

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

## 3. Restore test (do it once a month)

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

**Whole droplet lost:** new droplet → §1.3 → §1.4 with the same `.env` (from your password manager) and certs →
first deploy creates an empty database → stop the API (step 1 above) → step 2 → step 3. Update the DNS A record
if the IP changed.

---

## 6. Troubleshooting

| Symptom | Look at |
|---|---|
| Cloudflare 525 / 526 | Authenticated Origin Pulls off, or wrong/expired files in `certs/`. `docker compose logs caddy` |
| Cloudflare 521 / 522 | Caddy not running or port 443 closed: `docker compose ps`, `sudo ufw status` |
| 502 from Caddy | API not healthy: `docker compose ps`, `docker compose logs --tail 100 api` |
| API log: `pending EF migration(s)` | the migrate step did not run: `docker compose run --rm migrate` |
| API log: `Unsafe production configuration` | the listed `.env` value (SMS provider/token, sa login, HTTPS) |
| `{"status":"unhealthy"…}` | SQL Server down or the API login broken: `docker compose logs mssql`, then `docker compose run --rm migrate` (re-creates the login) |
| OTP never arrives | `docker compose logs api | grep -i sms`: `refused HTTP 401` = token, `unreachable` = network; `SMSPOH_TEST` must be `false` |
| Backup failed | `journalctl -u zaypos-backup --since today`; run `./backup.sh` by hand to see the error |
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
| Origin certificate | new one in Cloudflare (§1.1), copy to `certs/`, `docker compose restart caddy` |
