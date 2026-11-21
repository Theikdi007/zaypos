# edge-proxy-netlify: route 1 to the API

Without a VPN, Myanmar networks refuse `api.zaypos.app` but reach Netlify's edge (all of MBT Wi-Fi, Atom and MPT,
2026-11-21: [reachability.md](../docs/deploy/reachability.md)). This folder is a Netlify site with one Edge Function that forwards
every request to `https://api.zaypos.app`. Design and the app's route order: [fallback-routes.md](../docs/deploy/fallback-routes.md#plan-b-no-google-cloud-billing).

It is the Netlify version of [`edge-proxy/`](../edge-proxy) (Go, App Engine) with the same rules:

- **Fixed upstream.** `UPSTREAM` in `src/proxy_core.ts`. Path and query are appended, never resolved, so it is not an open proxy.
- **The API trusts two headers only together.** These are `X-ZayPOS-Edge` (the secret) and `X-ZayPOS-Client-IP` (from Netlify's
  `context.ip`). A client's own `X-ZayPOS-*`, `X-Forwarded-*`, `Forwarded`, `X-Real-IP` and `x-nf-*` headers are dropped. The API
  side is `backend/src/ZayPOS.Api/Hosting/EdgeProxy.cs` (PR #20).
- **No secret = no forwarding.** If `EDGE_PROXY_SECRET` is missing or shorter than 32 chars, every proxied path answers
  `503 edge_not_configured`. Otherwise all shops would share one rate-limit bucket on the API.
- **Errors and limits.**
  - Bodies over 32 MB get `413 request_too_large`.
  - Upstream down or slower than 35 s gets `502 edge_upstream_unavailable`, with no details.
  - `GET /_proxy/health` answers locally; `GET /health` is the API's health through the proxy.
- **Logs** hold the method, path, status and duration only. There are no queries, headers, bodies or tokens.
- **No caching.** Responses are never cached at the edge, since the config has no `cache: "manual"`.

The repo is **not** connected to Netlify. Only this folder is uploaded, with the Netlify CLI.

## Test

```bash
cd edge-proxy-netlify
node --test 'test/*.test.ts'        # Node >= 23.6, no dependencies
```

Local run in Netlify's real edge runtime (no account needed; uses a dummy secret, never the real one):

```bash
printf 'EDGE_PROXY_SECRET=local-dummy-not-a-real-secret-0123456789abcdef\n' > .env   # git-ignored
npx netlify-cli@latest dev --offline --port 8899
curl -i localhost:8899/_proxy/health; curl -i localhost:8899/health
rm .env; rm -rf .netlify
```

## One-time setup (the owner does this; ~15 min)

**1. Account.**
1. Go to <https://app.netlify.com/signup> and choose **Email**, not GitHub/GitLab/Bitbucket. The repo must not be connected,
   and email sign-up gives Netlify no access to the GitHub account.
2. Plan: **Free**. Don't enter a card.
3. Turn on **two-factor authentication**: User settings → Security.
4. Team name: anything, e.g. `zaypos`.

**2. Usage alert.** Team → Billing (or Usage), then turn on the credit-usage emails if offered. Check this page weekly during the
pilot. Free has a hard limit of 300 credits a month, and **the site pauses when they run out**. Move to Personal ($9 a month)
before more than ~60 shops depend on it ([request budget](../docs/deploy/fallback-routes.md#request-budget)).

**3. Create the site from this folder, without Git.** In your own terminal:
```bash
cd edge-proxy-netlify
npx netlify-cli@latest login              # opens the browser; approve
npx netlify-cli@latest sites:create       # manual site, no Git. Name: something neutral, e.g. "zp-edge-7k2"
```
This links the folder to the site (`.netlify/state.json`, git-ignored). The site URL is `https://<name>.netlify.app`.

**4. The secret.** The clipboard holds the secret during these steps. **Copying a command from a doc or chat overwrites
it**: so run (or type) each command first, and copy the secret from the password manager only when the command waits for
it.

1. **Make it.** Generate the value to the clipboard only, and print its length and fingerprint, never the value:
   ```bash
   openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-48 | tr -d '\n' | pbcopy && pbpaste | wc -c && pbpaste | shasum -a 256 | cut -c1-8
   ```
   - It must print `48`: letters and digits only. The last `tr -d '\n'` matters because macOS `cut` adds a newline.
   - The second line is the **fingerprint** (first 8 hex characters of SHA-256). Write it next to the entry; it isn't
     secret.
   - Save the value in the password manager as "ZayPOS EDGE_PROXY_SECRET".
2. **Netlify.** Project → **Manage → Keys and secrets** (older UI: Site configuration → Environment variables) →
   **Add a variable**:
   - Key `EDGE_PROXY_SECRET` (singular).
   - Mark it **Secret** if offered.
   - Scopes: at least **Functions** and **Runtime**. Builds does no harm, since this site has no build.
   - Same value for all deploy contexts. Copy the value from the password manager, then paste with ⌘V.
3. **Server.** VPN on from Myanmar; `ssh deploy@<server>`, then `cd ~/zaypos`. Run these in order:
   1. Back up, and check there's no line yet (must print `0`):
      `cp -p .env .env.bak-$(date +%F) && grep -c '^EDGE_PROXY_SECRETS=' .env`
   2. Make sure `.env` ends with a newline, so the new line isn't glued to the last one:
      `[ -n "$(tail -c1 .env)" ] && echo >> .env`
   3. **Type or paste this command first**: `read -rs S && printf 'EDGE_PROXY_SECRETS=%s\n' "$S" >> .env && unset S`.
      Press Enter; it now waits and shows nothing. **Only then** copy the secret from the password manager, ⌘V, Enter.
      `read -s` keeps the value off the screen and out of shell history.
   4. Check its length (must print `48`) and fingerprint (must equal the one from step 1):
      `grep '^EDGE_PROXY_SECRETS=' .env | cut -d= -f2- | tr -d '\n' | wc -c`
      `grep '^EDGE_PROXY_SECRETS=' .env | cut -d= -f2- | tr -d '\n' | sha256sum | cut -c1-8`

   No restart is needed until PR #20 is deployed: before PR #20, the compose file does not read it. **PR #20 must run
   with this value before any app uses the Netlify route.** Otherwise the API sees every shop as Netlify's IP and its
   per-IP rate limit locks shops out of OTP and login.

   **The backup holds every secret.** Delete it (`rm ~/zaypos/.env.bak-<date>`) once PR #20 has been deployed and the
   API is healthy with the new `.env`.
4. Clear the clipboard: `pbcopy </dev/null`.

The proxy trims whitespace from `EDGE_PROXY_SECRET`, so a value pasted with a trailing newline still matches the server's.

Never paste the secret into chat, git, a ticket or a shell command line. The fingerprint is safe to share.

**5. Deploy.** Env var changes take effect on the next deploy.
```bash
npx netlify-cli@latest deploy --prod      # from edge-proxy-netlify/; uploads public/ + the edge function
curl -sS https://<name>.netlify.app/_proxy/health    # {"status":"ok"}
curl -sS https://<name>.netlify.app/health           # the API's health; a 503 edge_not_configured = secret missing
```
Each production deploy costs 15 credits on the credit plans, so deploy only when the code changes.

## Rotating the secret

Same safety rules as step 4: command first, then the secret; length and fingerprint checked on both sides; back up `.env`.

1. Make a new value (step 4.1).
2. Server: `EDGE_PROXY_SECRETS=<old>,<new>`, then restart the API.
3. Netlify: replace `EDGE_PROXY_SECRET`, then `deploy --prod`.
4. Server: `EDGE_PROXY_SECRETS=<new>`, then restart the API.
