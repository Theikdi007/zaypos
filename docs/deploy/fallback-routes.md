# Fallback routes to the API (design, step 2)

Status: **plan only. No cloud resource created.** Evidence: [reachability.md](reachability.md). IPs masked as there.

## Why

Phone R (Redmi Note 13 Pro, Android 16), 2026-11-20, with no VPN:

| Network | Direct (Vultr 45.32.x.x) | Cloudflare (172.67.x.x) | Cloud Run `run.app` | **App Engine `appspot.com`** | Cloud Functions | API Gateway | google.com |
|---|---|---|---|---|---|---|---|
| MBT home Wi-Fi | refused | timeout | refused | **OK** | OK | OK | OK |
| Atom 4.5G | refused | timeout | refused | **OK** | OK | OK | OK |
| MPT 3G | refused | reset | refused | **OK** | OK | OK | OK |

**Gate passed 2026-11-20 22:34:** App Engine reachable without VPN on all three networks. On MPT 3G the TLS handshake to
App Engine took ~3 s, which the 8 s first-try connect timeout covers.

Owner report: the app works on all three with Outline VPN on, and fails on all three with it off. DNS is correct. The block is
by IP: Google's *own* front-end addresses (142.251.x.x, 173.194.x.x, 216.239.x.x) pass, while hosting, CDN and Google Cloud
*customer* ranges are refused. **Shops can't be asked to run a VPN, so a route on Google's own front end is required.**

## Decision

1. **App Engine standard** in `asia-southeast1` runs a ~80-line Go reverse proxy. The app calls
   `https://zaypos-437e5.appspot.com` (the regional `…r.appspot.com` name works too; `gcloud app describe` prints it).
2. Route order in the app: **App Engine → direct → Cloudflare**, remembering the last route that worked.
3. The proxy authenticates itself to the origin with a **secret header**; only then does the API believe the client IP it passes.

Rejected: Cloud Run on its own URL and the global load balancer (refused on MBT and Atom),
API Gateway (works but adds a per-call fee and config, no gain), hard-coding a Google IP (fragile, amounts to domain fronting).
Cloud Functions (`cloudfunctions.net`, also reachable) is the backup if App Engine ever fails a network.

## Route order in the app

```
endpoints = [ https://zaypos-437e5.appspot.com,   // 1. App Engine: the only route that worked without VPN everywhere
              https://api.zaypos.app,             // 2. direct: VPN users, networks abroad, if the block lifts
              https://api2.zaypos.app ]           // 3. Cloudflare: only once api2 exists (it does not today)
```

App Engine is first because direct failed on **every** network tested. Putting direct first would cost every shop a failed
connect each time the app starts, and Cloudflare's failure is a timeout, not a fast refusal.

- `--dart-define=API_BASE_URLS=<comma list>` (the existing `API_BASE_URL` stays as a one-item list). Every entry goes through
  `checkApiBaseUrl` (https only, BUG-55).
- **Sticky:** the last route that worked is saved (shared_preferences) and tried first next time.
- **Switch only on failures where the request never left the phone:** DNS failure, connection refused or reset before the
  request was sent, connect timeout, TLS handshake failure. Never on an HTTP status (4xx/5xx come from our API) and never on a
  receive timeout after sending. A sale POST that may have reached the server must not be replayed on another route. Sync push
  is already idempotent on the server (`SyncPushService`), which covers its normal retry.
- Timeouts: connect **8 s** for the first try (Atom took 4.4 s to connect to Google once), **4 s** for the others.
- Every 6 h, or when the network changes, a background `GET /health` on routes above the current one moves the app back up.
- One place: `dio` gets the base URL from an `ApiRouter` provider instead of the `apiBaseUrl` const (callers:
  `auth_api.dart`, `auth_controller.dart`, `sync_limits.dart`).

## The proxy (App Engine)

- Forwards **only** to `UPSTREAM` = `https://api.zaypos.app` (env var; TLS verified). Not an open proxy: the host and scheme
  are fixed, only the path and query come from the request.
- Passes the method, path, query, body and all end-to-end headers (`Authorization`, `Content-Type`, …) unchanged. Drops
  hop-by-hop headers, any incoming `X-ZayPOS-*` header, and Google's `X-Appengine-*` / `X-Cloud-Trace-*` headers.
- Adds `X-ZayPOS-Edge: <secret>` and `X-ZayPOS-Client-IP: <phone IP>`. The phone IP comes from `X-Appengine-User-IP`, which
  Google sets and the phone can't forge.
- `GET /health` = the upstream's `/health` (the app's probe tests the whole path). `GET /_proxy/health` = the proxy alone.
- Logs: status, path template, duration only. No headers, no bodies, no tokens.
- Limits: App Engine standard caps requests and responses at 32 MB (Caddy also caps bodies at 32 MB). App Engine buffers
  responses, so no streaming; the API has none today.

### Secret-header design

| Where | What |
|---|---|
| Secret Manager | `edge-proxy-secret`: 32 random bytes, base64. Only the App Engine service account can read it (`secretAccessor` on that secret only). |
| Proxy | Reads it once at startup and adds `X-ZayPOS-Edge` to every upstream request. |
| Server `.env` | `EDGE_PROXY_SECRETS=<current>[,<next>]` (two values allowed, for rotation) → compose → `EdgeProxy__Secrets`. Never in git. Empty = no edge proxy. |
| API middleware `UseEdgeProxyClientIp` (`backend/src/ZayPOS.Api/Hosting/EdgeProxy.cs`, right after `UseForwardedHeaders`, before rate limiting) | Compares SHA-256 hashes with `CryptographicOperations.FixedTimeEquals`, checking every configured secret (no early exit), so neither the content nor the length leaks by timing. On a match with exactly one parseable `X-ZayPOS-Client-IP`, it sets `Connection.RemoteIpAddress` to that IP (IPv4-mapped → IPv4) and flags the request. **Either way it removes both headers.** A wrong secret is a plain request from Google's IP: no error, nothing revealed, logged as `edge_secret_mismatch` (peer only, never the value). Secrets under 32 characters: the API refuses to start. |
| Rate limiting | Already per `RemoteIpAddress`, so it now sees phones, not Google. Without this, every shop behind the proxy would share one limit and lock each other out of OTP and login. |
| Rotation | Add a new version to Secret Manager → put old,new in `EDGE_PROXY_SECRETS` and restart the API → redeploy the proxy (reads new) → remove old from `.env`. |
| fail2ban / ufw | Google's egress IPs change: never allow-list or ban them. The sshd jail must ban port 22 only (design item from reachability.md). |

**Origin:** settled by PR #19 (merged 2026-11-20). `deploy/Caddyfile` in git is now the live config: `api.zaypos.app`
directly, Let's Encrypt on 80/443, and Caddy replaces any client `X-Forwarded-For`. The proxy connects there like any client,
and Caddy passes the `X-ZayPOS-*` headers through to the API, which decides. If the origin is ever locked to Cloudflare again,
point `UPSTREAM` at `api2` or keep a direct listener for the proxy.

## Region check (read-only, 2026-11-20)

- Firebase project `zaypos-437e5`: **no default resource location set** (`firebase projects:list`: no `locationId`).
- Firestore API never enabled, so no database pins a region.
- So App Engine can still pick **`asia-southeast1` (Singapore)**: nearest to Myanmar, and next to the origin if the Vultr
  server is in Singapore.
- **Not checked:** whether an App Engine app already exists. The CLI token read was refused here, and `gcloud` isn't installed.
  Run step 0 below. If an app already exists in another region, App Engine's region can't be changed. Then either accept it
  (Tokyo / Taiwan add ~30–80 ms) or use a separate small project `zaypos-edge`.
- ⚠ Creating the App Engine app **permanently** sets this project's default location for Firestore and Cloud Storage too.
  `asia-southeast1` is fine for that.

## gcloud steps (you run them, one at a time, in your own terminal)

Each step says what output to expect. Stop at anything else. The secret value is never printed, never written to a file,
and never passed as a command-line argument (it travels through pipes only).

```bash
# 0. Tools + read-only checks (creates nothing)
brew install --cask google-cloud-sdk
gcloud auth login
gcloud config set project zaypos-437e5
gcloud app describe --format="value(locationId,servingStatus)"
#   "does not contain an App Engine application" → region free, continue with asia-southeast1
#   a region other than asia-southeast1 → STOP: use the Cloud Functions option instead
gcloud billing projects describe zaypos-437e5 --format="value(billingEnabled)"     # must print True

# 1. APIs + App Engine app (region is PERMANENT for this project, also for Firestore/Storage)
gcloud services enable appengine.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com billingbudgets.googleapis.com
gcloud app create --region=asia-southeast1

# 2. Secret: 32 random bytes, created straight into Secret Manager
openssl rand -base64 32 | tr -d '\n' | gcloud secrets create edge-proxy-secret \
  --replication-policy=user-managed --locations=asia-southeast1 --data-file=-
gcloud secrets add-iam-policy-binding edge-proxy-secret \
  --member=serviceAccount:zaypos-437e5@appspot.gserviceaccount.com --role=roles/secretmanager.secretAccessor
#   Copy it into the server's .env through a pipe (ssh stdin), never on screen:
gcloud secrets versions access latest --secret=edge-proxy-secret | ssh deploy@45.32.114.207 \
  'read -r s; umask 077; sed -i "/^EDGE_PROXY_SECRETS=/d" ~/zaypos/.env; printf "EDGE_PROXY_SECRETS=%s\n" "$s" >> ~/zaypos/.env; echo "set (${#s} chars)"'
#   expect: set (44 chars)

# 3. Deploy the API that contains the edge middleware (normal release.sh), so it picks up EDGE_PROXY_SECRETS.
#    Then the proxy (from the repo root):
gcloud app deploy edge-proxy/app.yaml --quiet
curl -s https://zaypos-437e5.appspot.com/_proxy/health     # {"status":"ok"}
curl -s https://zaypos-437e5.appspot.com/health            # the API's {"status":"healthy",...} through the proxy

# 4. Budget alert: email at 50 / 90 / 100 % of $10 per month (an alert, not a hard cap)
gcloud billing budgets create \
  --billing-account="$(gcloud billing projects describe zaypos-437e5 --format='value(billingAccountName)' | cut -d/ -f2)" \
  --display-name="zaypos-437e5 monthly" --budget-amount=10USD --filter-projects=projects/zaypos-437e5 \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
```

If `gcloud app deploy` says the `go123` runtime is not supported, set `runtime:` in `edge-proxy/app.yaml` to the newest
`go1xx` the error lists (the code builds with any Go ≥ 1.23). The proxy is in `edge-proxy/` (`main.go`, `app.yaml`).
`app.yaml` holds only the secret's *name*.

**Rotation (later):** `openssl rand -base64 32 | tr -d '\n' | gcloud secrets versions add edge-proxy-secret --data-file=-` →
on the server set `EDGE_PROXY_SECRETS=<old>,<new>` (same pipe trick, two `versions access` calls) and restart the API →
`gcloud app deploy edge-proxy/app.yaml` (new instances read `latest`) → remove `<old>` from `.env`, restart the API →
`gcloud secrets versions disable <old-version> --secret=edge-proxy-secret`.

## Monthly cost (asia-southeast1)

List prices from memory: **check them in the GCP pricing calculator before step 1.** App Engine standard: 28 F1
instance-hours/day free, then ~$0.06/h. Outgoing traffic ~1 GB/day free, then ~$0.12/GB (both the request to the origin and the
response to the phone count). Secret Manager is read once per instance start, so cents.

With App Engine **first**, essentially all traffic goes through it. Assumption: ~1,500 calls per shop per day, ~5 KB per call.

| Shops | Calls / month | Traffic / month | Instance hours | **Estimate / month** |
|---|---|---|---|---|
| 20 (beta) | ~0.9 M | ~4.5 GB (0.15 GB/day, free) | one F1 during shop hours, free | **≈ $0–1** |
| 100 | ~4.5 M | ~23 GB (0.75 GB/day, free) | ~1 F1 all day, free | **≈ $0–3** |
| 500 | ~22.5 M | ~110 GB | 1–2 F1 | **≈ $10–45**: the $10 alert fires; revisit then |

Plus billing must be on for the project (Cloud Build for deploys). `max_instances: 2` and the budget alert keep a runaway app
loop from running up a bill.

## Build order (after approval)

1. ✅ API: edge-secret middleware plus tests (spoofed header ignored, right secret sets the IP, headers stripped).
2. ✅ `edge-proxy/` Go service plus tests (upstream fixed, `X-ZayPOS-*` from the client dropped, `/health` passthrough).
3. Step 0–4 above, by you.
4. App: `ApiRouter` with the order and sticky/failover rules above, plus unit tests for "switch only before send".
5. Re-run the probe on MBT, Atom and MPT against the real proxy (`/health` = `Healthy`), then QA round 21.
