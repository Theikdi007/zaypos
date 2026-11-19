# zaypos.app website (Cloudflare Pages)

Static pages in `website/`: `index.html`, `privacy.html`, `terms.html`, `404.html`, `style.css`,
the Myanmar font (`fonts/`, Noto Sans Myanmar as woff2, OFL licence alongside), `_headers`
(security headers, font caching) and `robots.txt`. No build step. Pages serves them at
`https://zaypos.app/`, `/privacy` and `/terms` (it redirects `/privacy.html` → `/privacy` itself).

Use `https://zaypos.app/privacy` as the privacy policy URL in Google Play, the App Store and the
Google OAuth consent screen. The deletion instructions are in section 6 of that page.

The website and the API are separate: the website is on Cloudflare Pages, the API stays on the
Vultr server under `api.zaypos.app` (docs/deploy/runbook.md). Adding the website changes only the
`zaypos.app` and `www` DNS records.

## 1. Contact email (before the site goes live)

The pages give `support@zaypos.app`. Cloudflare → zaypos.app → **Email → Email Routing** →
Get started → add the address `support` → forward to your own mailbox → confirm the link
Cloudflare emails you. Cloudflare adds the MX and SPF (TXT) records on `zaypos.app`; they don't
touch `api`. Send a test email to support@zaypos.app.

## 2. Create the Pages project (once)

1. Cloudflare → **Workers & Pages → Create → Pages → Connect to Git** → GitHub → allow the
   `zaypos` repository.
2. Project name `zaypos-site` (it becomes `zaypos-site.pages.dev`). Production branch `main`.
3. Build settings: Framework preset **None**, Build command **empty**, Build output directory
   **`website`**, Root directory empty.
4. **Save and Deploy.**
5. Project → Settings → **Build → Build watch paths**: Include paths `website/*`, so backend and
   app commits don't start a website build.

Every push to `main` that changes `website/` deploys to production. Pushes to other branches get a
preview URL (`<branch>.zaypos-site.pages.dev`), e.g. this PR's `feat-website`. Check that before merging.

## 3. Connect zaypos.app and www.zaypos.app

1. First check Cloudflare → zaypos.app → **DNS → Records**. Note the `api` record (A, proxied, to
   the Vultr server); it must stay exactly as it is. If there is already an A/AAAA/CNAME record for
   `zaypos.app` itself (`@`) or `www`, delete just that one (not `api`).
2. Pages project → **Custom domains → Set up a custom domain** → `zaypos.app` → Activate domain.
   Cloudflare adds a proxied CNAME `zaypos.app → zaypos-site.pages.dev` (CNAME flattening at the root).
3. Again for `www.zaypos.app`.
4. Wait until both show **Active** (certificate issued, usually a few minutes).
5. Send www to the root: **Rules → Redirect Rules → Create rule** (or the template
   "Redirect from WWW to root"):
   - When: Hostname equals `www.zaypos.app`
   - Then: Dynamic, expression `concat("https://zaypos.app", http.request.uri.path)`,
     status **301**, Preserve query string on.

The zone-wide SSL/TLS mode stays **Full (strict)**, which works for both Pages and the API.

## 4. Check

```sh
curl -sI https://zaypos.app/            | head -1   # HTTP/2 200
curl -sI https://zaypos.app/privacy     | head -1   # HTTP/2 200
curl -sI https://www.zaypos.app/terms   | grep -i -E '^(HTTP|location)'   # 301 → https://zaypos.app/terms
curl -s  https://api.zaypos.app/api/v1/sync/limits | head -c 80; echo  # JSON: the API still works
dig +short api.zaypos.app                           # Cloudflare IPs, as before
```

Open https://zaypos.app on a phone: the Burmese text should use Noto Sans Myanmar (the same font
as the app), not the phone's fallback font.

## Updating the pages

Edit the files in `website/`, open a PR (check the preview URL), merge. When the privacy policy or
terms change, update the date at the top of the page in both languages.
