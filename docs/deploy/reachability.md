# API reachability from Myanmar networks

Goal: the app reaches the API on **any** Myanmar network (any Wi-Fi, MPT / Atom / U9 / Mytel mobile data, VPN on or off), on
Android and iOS. This page is the test matrix and how to fill it. IPs are masked everywhere (`45.32.x.x` = the API server).

## Hosts tested

| Column | URL | Route | Expected when reachable |
|---|---|---|---|
| **Direct** | `https://api.zaypos.app/health` | DNS only → server 45.32.x.x, Caddy, Let's Encrypt | page shows `Healthy` (or JSON with status) |
| **Cloudflare** | `https://zaypos.app/` (today) → `https://api2.zaypos.app/health` (after the fallback PR) | Cloudflare proxy | the website / `Healthy` |

Today no API host goes through Cloudflare, so the Cloudflare column uses the website `zaypos.app` (Cloudflare Pages) as a stand-in:
it tells us whether Cloudflare's edge is reachable on that network. After the fallback PR the column is re-tested with `api2`.

## How to test one network (phone side)

1. Put the phone on that network only:
   - **Wi-Fi rows:** Wi-Fi on, mobile data off, VPN app disconnected.
   - **Mobile-data rows:** Wi-Fi **off**, mobile data on with the SIM of that operator as the data SIM, VPN off. Toggle airplane mode on → off
     once first (new connection).
   - **VPN row:** home Wi-Fi + VPN connected.
2. Open a **new incognito / private tab** (Chrome: ⋮ → New incognito tab; Safari: Tabs → Private) so no cached page or HSTS
   shortcut hides the result.
3. Type the Direct URL, wait up to 30 s, write down what you see: `OK` or the exact error code under the sad face
   (`ERR_CONNECTION_REFUSED`, `ERR_CONNECTION_CLOSED`, `ERR_CONNECTION_TIMED_OUT`, `ERR_CONNECTION_RESET`, `ERR_NAME_NOT_RESOLVED`,
   `ERR_SSL_PROTOCOL_ERROR`, …; Safari: the sentence it shows).
4. Same for the Cloudflare URL.
5. Optional but useful: search "what is my ip" in the same tab and keep the address **for yourself** (needed for the server
   capture below; never paste it into chat or this file).

## How to test one network (server side, you run it in your own terminal)

While the phone retries, this shows whether its packets reach the server at all (replace `PHONE_IP` with the address from step 5;
it prints nothing else):

```bash
ssh -t deploy@45.32.114.207 'sudo timeout 60 tcpdump -ni enp1s0 -c 30 host PHONE_IP'
```

Tap Reload on the phone 2–3 times within the 60 s. Report only one of:
- **nothing** → the packets never arrive: blocked on the way (operator / national firewall), not by our server;
- **`Flags [S]` in, `Flags [R.]` out** (or `ICMP … unreachable` out) → our server refuses: firewall / fail2ban on the server;
- **`Flags [S]` in, `Flags [S.]` out** → TCP works, the problem is later (TLS / HTTP).

fail2ban check (bans are per IP for 1 h; the ban action is `ufw`, i.e. a reject on all ports):

```bash
ssh -t deploy@45.32.114.207 'sudo fail2ban-client status sshd; sudo ufw status numbered | head -20'
```

Report only "my phone's IP is / is not in the banned list".

## Matrix

Cell format: `OK` or the error code, plus date/time. `X` = Xiaomi MIX (Android 8, Chrome), `i` = iPhone 15 (iOS, Safari),
`R` = Redmi Note 13 Pro (2312DRA50C, Android 16, Chrome, dual SIM Atom + MPT; several VPN apps installed incl. Outline — check
none is connected or set as always-on before a non-VPN row).
"Server saw" = result of the tcpdump above (`nothing` / `SYN→RST` / `SYN→SYN-ACK` / not run); prefix with the phone letter.

| Network | Direct — X | Direct — i | Direct — R | Cloudflare — X | Cloudflare — i | Cloudflare — R | Server saw (direct) | Notes |
|---|---|---|---|---|---|---|---|---|
| Home Wi-Fi (MBT), VPN off | **ERR_CONNECTION_REFUSED** (11-20 20:52; also `curl` from the phone: 443 and 80 refused, ping no reply) | | **refused** (11-20, adb curl: 443 refused in ~100 ms, 80 in ~20 ms, ping 100 % loss) | ERR_CONNECTION_CLOSED (before #19, PR #19 notes; re-test) | | **timed out** (11-20, adb curl, 8 s and 15 s) | R: not run (owner accepted the adb result) | Google works on the same Wi-Fi. DNS correct for every host (no poisoning). Google Cloud: see below |
| MPT mobile data (3G HSPA+) | | | **refused** (11-20 22:34, adb curl; ping 100 % loss) | | | **reset** (11-20 22:34, adb curl: `Connection reset by peer`) | R: not run | Wi-Fi off, default network CELLULAR only, no tun. Google 204. Owner: the app fails with VPN off |
| Atom mobile data (4.5G) | | | **refused** (11-20 21:50, adb curl: 443 in 83 ms, 80 in 21 ms, ping 100 % loss) | | | **timed out** (11-20, adb curl, 8 s) | R: not run | Wi-Fi off, no tun/VPN interface. Google 204. App (release, api.zaypos.app): login screen shows "အင်တာနက် မရပါ" at 21:54 (screenshot); logcat could not tie it to a new tap |
| U9 mobile data | | | | | | | | |
| Mytel mobile data | | | | | | | | |
| VPN on (Outline) over MBT Wi-Fi, Atom or MPT | | | OK (owner report) | | | | | Mac via Outline: Direct OK (11-20). **Owner report, R, 11-20: the app works with Outline ON on MBT Wi-Fi, Atom and MPT, and fails with it OFF on all three.** Not probed over adb |

### Google Cloud entry points (phone R, adb curl)

None of these hosts is ours yet except by name. An unused name still proves reachability: a `*.run.app`, `*.appspot.com`,
`*.cloudfunctions.net` or `*.gateway.dev` name resolves to Google's front end, and Google answers `404` once TLS has succeeded.
`OK` = HTTP answer (404/400/204), `refused` = TCP refused at once, `timeout` = no answer.

| Network | google.com (142.251.x.x) | googleapis.com (74.125.x.x) | appspot.com (App Engine, 142.251.x.x) | cloudfunctions.net (216.239.x.x) | gateway.dev (API Gateway, 216.239.x.x) | run.app (Cloud Run, 34.143.x.x) | web.app / firebaseapp.com (199.36.x.x) | GCP LB anycast (34.107.x.x) |
|---|---|---|---|---|---|---|---|---|
| Home Wi-Fi (MBT), VPN off (11-20) | OK | OK | OK | OK | OK | **refused** | **refused** | **refused** |
| Atom mobile data (11-20) | OK | OK (142.250.x.x, slow connect 4.4 s) | OK (173.194.x.x) | OK | OK | **refused** | **refused** (firebaseapp after 4.3 s) | **refused** |
| MPT mobile data, 3G (11-20 22:34) | OK | — | **OK** (74.125.x.x, TLS 2.8–3.1 s) | OK (216.239.x.x) | OK | **refused** | — | — |
| Home Wi-Fi, VPN on | | | | | | | | |

**Conclusion (11-20):** every Myanmar network tested (MBT Wi-Fi, Atom, MPT) blocks both the direct route and Cloudflare
without a VPN. Shops can't be asked to run a VPN, so the App Engine route ([fallback-routes.md](fallback-routes.md)) is
required, not optional.

The block is **by IP, not by name**: the same `run.app` name sent to a Google IP that works (`curl --resolve`) gets its 404.
What's blocked on MBT so far: Vultr (45.32.x.x), Cloudflare (172.67.x.x), and Google Cloud's *customer* address ranges (Cloud Run's
own URL, Firebase Hosting, load-balancer anycast). What works: Google's own front-end ranges, which also serve App Engine, Cloud
Functions and API Gateway URLs.

How R is probed (Wi-Fi/data switched by hand, everything else over adb; output IPs masked to two octets): the scripts push to
`/data/local/tmp` and run `curl -m 10–12 --connect-timeout 7–8` against each host, plus `ping -c2` to the API.

### Proxy-host candidates without Google Cloud billing (phone R, adb curl, 2026-11-21)

Why: App Engine and Cloud Functions need billing on `zaypos-437e5`, and Google Cloud's billing country list has no Myanmar.
We will **not** pick another country (a card/country mismatch could suspend the project that holds Google Sign-In). So Plan B
is a host outside Google Cloud.

Setup: VPN off and checked over adb (no `VPN` network agent, no always-on VPN). MBT = Wi-Fi only (09:28). Atom = LTE only,
APN `ATOM` (09:31). MPT = HSPA only, APN `mptnet` (09:33). Script: `probe4.sh` in `/data/local/tmp`. It sends 3 requests to
each host that answers and retries a failing host once. Connect timeout is 8 s, total timeout 12 s.

Cells: `OK` + median **TCP connect / TLS done** in seconds, or the failure.
- **Made-up name:** a made-up subdomain on the provider's shared domain, so the provider's own edge answers 404/500. This
  stands for any site we would deploy there.
- **3rd-party site:** a public site on that platform (random names don't resolve there). It proves the address range is
  reachable, not the exact range our site would get.

| Host (what was probed) | Test name | MBT Wi-Fi | Atom 4.5G | MPT 3G | All 3? |
|---|---|---|---|---|---|
| control: google.com | | OK 0.08 / 0.15 | OK 0.36 / 0.44 | OK 0.11 / 0.26 (one 5 s connect) | ✅ |
| control: api.zaypos.app (Vultr) | | **refused** | **refused** | **refused** | ❌ |
| Apps Script `script.google.com` | real | OK 0.07 / 0.15 (302) | OK 0.06 / 0.16 | OK 0.19 / 0.31 | ✅ |
| Apps Script `script.googleusercontent.com` | real | OK 0.05 / 0.12 | OK 0.07 / 0.50 (one 3.2 s TLS) | OK 0.09 / 0.46 | ✅ |
| Vercel `*.vercel.app` (216.198 / 64.29) | made-up name | OK 0.05 / 0.12 | OK 0.05 / 0.17 | OK 0.09 / 0.32 | ✅ |
| Netlify `*.netlify.app` (13.215, AWS Singapore) | made-up name | OK 0.05 / 0.13 | OK 0.28 / 0.38 (one 3.3 s) | OK 0.16 / 0.27 | ✅ |
| Deno Deploy `*.deno.dev` | 3rd-party site | OK 0.28 / 0.65 | OK 0.22 / 1.51 | OK 0.27 / 0.58 | ✅ (slow TLS) |
| Cloudflare Pages `pages.dev` | apex | **reset** | **reset** | **reset** | ❌ |
| Cloudflare Workers `workers.dev` | apex | **reset** | **reset** | **reset** | ❌ |
| AWS CloudFront `*.cloudfront.net` | 3rd-party site | **refused** | OK 0.48 / 0.59 (one 5 s) | OK 0.07 / 0.17 | ❌ |
| Azure App Service `*.azurewebsites.net` (US West) | 3rd-party site | OK 0.39 / 0.95, 1 of 3 TLS error | OK 0.80 / 1.32, 1 of 3 TLS error | OK 0.25 / 0.83 | ⚠️ flaky |
| Azure Front Door `*.azurefd.net` | made-up name | OK 0.27 / 1.35, total ~4 s | OK 0.44 / 0.61 | OK 0.17 / 0.38, total ~4.4 s | ✅ (slow) |
| Fastly Compute `*.edgecompute.app` | made-up name | OK 0.06 / 0.13 | OK 0.04 / 0.15 | OK 0.20 / 0.41 | ✅ |
| Fastly CDN (`pypi.org`) | 3rd-party site | OK 0.06 / 0.14 | OK 0.06 / 0.14 | OK 0.10 / 0.22 | ✅ |
| bunny.net `*.b-cdn.net` | made-up name | **timeout** | **timeout** | **timeout** | ❌ |
| Render `*.onrender.com` | made-up name | OK 0.05 / 0.11 | OK 0.04 / 0.12 | OK 0.24 / 0.40 | ✅ |
| Fly.io `*.fly.dev` | 3rd-party site | OK 0.05 / 0.11 | OK 0.12 / 0.21 | **reset**, then OK 0.13 / 0.25 | ⚠️ |
| Railway `*.up.railway.app` | made-up name | OK 0.11 / 0.18 | OK 0.06 / 0.14 | OK 0.19 / 0.31 | ✅ |
| Hugging Face `*.hf.space` | made-up name | OK 0.26 / 0.58 | OK 0.29 / 0.64 | OK 0.29 / 0.62 | ✅ |
| GitHub Pages `*.github.io` | made-up name | OK 0.06 / 0.12 (one 4 s) | OK 0.07 / 0.13 | **timeout** | ❌ |
| AWS Singapore (`lambda.ap-southeast-1.amazonaws.com`) | AWS endpoint | OK 0.05 / 0.12 | OK 0.06 / 0.21 | OK 0.09 / 0.22 | ✅ |

**Reading (11-21):** the block is per provider, not "all hosting".
- **Blocked on all three:** Vultr, Cloudflare, bunny.net, and (11-20) Google Cloud's customer ranges.
- **Blocked on one network:** CloudFront (MBT) and GitHub Pages (MPT). Fly got one reset on MPT.
- **The lists differ per operator and change between days,** so the app needs **two routes on different providers** in its
  list, and the probe should be re-run before each beta.

Not covered yet: U9, Mytel, phones X and i, and a VPN-on row for these hosts. The proposal is in
[fallback-routes.md](fallback-routes.md#plan-b-no-google-cloud-billing).

A row is **covered** when at least one column works on every phone. QA round 21 starts only when every row is covered with the
app build that has the fallback.

## Findings so far (2026-11-20)

- **Server (read-only check):** runs only `zaypos-caddy`, `zaypos-api`, `zaypos-mssql`. Listening: 22, 80, 443 (+ local DNS 53).
  No Outline / Shadowsocks / WireGuard / OpenVPN process, container, interface or directory. **The API server does not run a VPN.**
  (The 0.4 ms "ping" from the Mac was answered by the Outline client on the Mac itself, not by the server.)
- Certificate chain OK (Let's Encrypt YE2 → ISRG Root X1, trusted from Android 7.1.1). Internet scanners and Let's Encrypt reach
  80/443, so the server is not closed to the world.
- From the Xiaomi on home Wi-Fi: DNS right (45.32.x.x, no IPv6 record), Google OK, our server **refused instantly** on 443 and 80,
  ping no reply.
- Two explanations, the tcpdump above decides:
  1. **Blocked upstream** (operator or national firewall answering with resets for this IP / provider range). Then the server sees
     **nothing**, and the fix is more than one route (clean IP + Cloudflare + fallback in the app).
  2. **fail2ban on our server**: jail `sshd` with `banaction = ufw` rejects a banned IP on *every* port for 1 h. Many Myanmar
     networks put many customers behind one shared address (CGNAT), so one infected neighbour guessing SSH passwords could lock a
     whole shop network out. Caveat: Caddy's 80/443 are Docker-published and normally bypass ufw's input rules, so this explains the
     ping and SSH but should not refuse 443 — the capture shows which.
- **Update 11-20 (phone R, MBT Wi-Fi):** Cloudflare is blocked too (timeout), and so are Google Cloud's customer ranges, while
  Google's own front end works. That rules out "one IP got caught" or fail2ban as the whole story: the network blocks hosting and
  CDN ranges. The design for the fallback routes is in [fallback-routes.md](fallback-routes.md).
- Independent of the answer: the sshd jail should ban **port 22 only** (Debian's default `nftables` multiport action), never all
  ports. Part of the design step.
