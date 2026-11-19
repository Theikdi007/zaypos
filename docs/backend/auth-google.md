# Google Sign-In (replaces SMS OTP as the default)

Status: design for branch `feat/google-signin`. Supersedes the OTP rows of README §4 while
`Auth:OtpEnabled=false` (the default).

## 1. What changes and what does not

Google answers only **"who is this person"** (a stable Google subject id). Everything after that
is today's code, unchanged: our JWT access token (15 min, `sub`/`tid`/`did`/`role`), rotating
refresh tokens (90 days, device-bound, 2-minute retry grace), device codes A/B/…, tenants and
template features, the server PIN check with 5-wrong → 15-minute lock, the offline PIN
(local PBKDF2 hash), the local-data guard (never wipe an unsent outbox), and sync.

| | Before (OTP) | After (Google) |
|---|---|---|
| Identity proof | phone + SMS code | Google ID token |
| Register | phone → OTP → shop → PIN | Google → shop (name, template, owner phone) → catalog → PIN |
| New phone | phone + PIN | Google → choose the shop → PIN |
| Forgot PIN | phone → OTP → new PIN | Google → (choose the shop) → new PIN |
| Offline unlock | local PIN | unchanged |

## 2. Data model

`Users` gets two nullable columns; `Users.Phone` becomes nullable.

| Column | Type | Meaning |
|---|---|---|
| `GoogleSubject` | varchar(255) null | Google `sub`. The identity key. |
| `GoogleEmail` | nvarchar(320) null | For support only. Never used to find a user, never trusted for login. |
| `Phone` | varchar(20) **null** | A **verified** login phone. Set only by OTP registration. Google users have null. |

- `UX_Users_Google (GoogleSubject, TenantId) UNIQUE WHERE GoogleSubject IS NOT NULL AND DeletedAt IS NULL`:
  one user per Google account per shop; the leading column serves "all shops of this account".
- `UX_Users_Phone` gets `AND Phone IS NOT NULL` in its filter.
- The owner phone typed in shop setup goes to `Tenants.Phone` (contact, **not verified**). It is
  never copied to `Users.Phone`, so an unverified number can never be used to sign in, and can't
  block the real owner of that number from verifying it later.
- One Google account may own several shops (max `AuthRules.GoogleShopsPerAccount` = 10).

## 3. API

All anonymous, under `/api/v1/auth`, ProblemDetails errors as today.

| Endpoint | Body | Result |
|---|---|---|
| `POST /google/shops` | `{ idToken }` | `200 { email, shops: [{ tenantId, name, templateId, role }] }` — "who is this user". |
| `POST /google` | `{ idToken, tenantId, pin, device }` | Sign in to that shop on this phone → `AuthResponse` (same as `/login`). |
| `POST /google` (link) | `{ idToken, phone, pin, device }` | A shop registered by phone before Google: phone + PIN as `/login`, then the Google account is attached to that user → `AuthResponse`. Refused (409 `google_linked_elsewhere`) if the user already has a different Google account. |
| `POST /google/register` | `{ idToken, shopName, templateId, township?, ownerPhone, pin, device }` | Creates tenant + owner user (Google subject) + features + device A → `AuthResponse`. |
| `POST /google/pin/reset` | `{ idToken, tenantId, newPin }` | New PIN, lock cleared, every session of the user ends → `204` (the app then signs in with `/google`, like today's reset + login). |

`/google` is the endpoint that issues tokens for an existing user ("find"); `/google/register` is
"create". A token always needs a tenant and a device, so creating happens only with a shop.

**Token verification** (`IGoogleIdTokenVerifier`, Infrastructure): JWT signed RS256 by a key from
Google's JWKS (`https://www.googleapis.com/oauth2/v3/certs`, through the OpenID configuration,
cached and refreshed on an unknown `kid`); `iss` ∈ {`accounts.google.com`, `https://accounts.google.com`};
`aud` ∈ `Auth:Google:ClientIds` (Android, iOS and web client ids); `exp` in the future and `iat`
not in the future (60 s skew); `sub` present. Any failure → `401 google_token_invalid`.
Verification needs the server to reach `googleapis.com`; if it can't → `503 google_unavailable`.

**Errors (new codes):** `google_token_invalid` 401, `google_unavailable` 503, `shop_not_found` 404
(no shop of this Google account with that tenantId), `google_shop_limit` 409,
`google_linked_elsewhere` 409, `otp_disabled` 403. PIN errors are today's (`invalid_credentials`,
`pin_locked` + Retry-After). `device_conflict` / `device_revoked` unchanged.

**Rate limits as today:** every `/auth/*` call per client IP (120/min). The per-phone partition
(10/min) is extended to a per-account partition: for `/google*` the middleware reads the `sub`
from the ID token's payload **without** verifying it (exactly like the phone today: someone can
spend another person's partition for a minute, but can't skip it). The link call also counts
against the phone. PIN lockout per user is unchanged.

## 4. OTP behind a switch

`Auth:OtpEnabled` (env `AUTH_OTP_ENABLED`, default **false**).

- false: `POST /otp`, `POST /register`, `POST /pin/reset` → `403 otp_disabled`. No SMS is sent;
  the SMS provider is not required in Production. `POST /login` (phone + PIN, no SMS) keeps
  working, so shops registered by phone (and old app builds) can still sign in.
- true: everything exactly as today. Turn it on when the SMSPoh Sender ID is approved.

The app has the same switch (`--dart-define=AUTH_OTP_ENABLED=true`, default false). Off: the
OTP screens are not in any flow. The code and its tests stay (the tests run with the switch on).

Production config gate: `Auth:Google:ClientIds` must be set; the SMSPoh credential is required
only when `Auth:OtpEnabled=true`.

## 5. App

`GoogleAuth` (wraps `google_sign_in`) returns `{ idToken, email }` or throws an `AuthFailure`:

| Code | When | Burmese message |
|---|---|---|
| `google_cancelled` | the user closed the account picker | Google နဲ့ ဝင်တာကို ရပ်လိုက်ပါတယ်။ |
| `google_no_account` | no Google account on the phone | ဒီဖုန်းမှာ Google အကောင့် မရှိသေးပါ။ ဖုန်းရဲ့ Settings မှာ Google အကောင့် ထည့်ပြီးမှ ပြန်ကြိုးစားပါ။ |
| `google_play_services` | Play services missing/outdated (Android) | ဒီဖုန်းမှာ Google Play services မရှိ (သို့) အဟောင်းဖြစ်နေပါတယ်။ Play Store ကနေ update လုပ်ပြီးမှ ပြန်ကြိုးစားပါ။ |
| `network` | offline | အင်တာနက် မရပါ။ လိုင်းရမှ ပြန်ကြိုးစားပါ။ |
| `google_failed` | anything else | Google နဲ့ ဝင်လို့ မရပါ။ ခဏနေ ပြန်ကြိုးစားပါ။ |

Flows (screens):

- **Login** (signed out): "Google နဲ့ ဝင်မယ်" → `/google/shops` →
  0 shops: "ဆိုင်အသစ် ဖွင့်မယ်" (→ Register, Google step already done) or
  "ဖုန်းနံပါတ်နဲ့ ဖွင့်ထားတဲ့ ဆိုင်" (phone + PIN → link);
  1+ shops: choose the shop → PIN → `/google`. "ဆိုင်အသစ် စာရင်းသွင်းမယ်" → Register.
- **Register:** step 1 Google account · step 2 shop name, owner phone (contact), template ·
  step 3 catalog start · step 4 PIN → `/google/register`.
- **Forgot PIN** (Login or the unlock screen): Google → choose the shop (skipped when the phone is
  locked to a known shop, or the account has one shop) → new PIN → `/google/pin/reset` → `/google`.
- The local-data guard now compares the **tenant id** (known before the call) instead of the
  phone; the link path still compares the phone.
- Session storage is unchanged: `phone` stays (empty for Google users). The ID token is held in
  memory only for the calls of one flow and dropped after sign-in; signing out also signs out of
  Google, so the next sign-in shows the account picker.
- An ID token the server refuses (`google_token_invalid`, e.g. it expired while the user waited)
  drops the flow and the screen asks for the Google step again.

## 6. Config

App identity registered with Firebase / Google Cloud: Android package **`app.zaypos`** (with the
SHA-1/SHA-256 of the debug and release keystores), iOS bundle id **`app.zaypos`**. Changing either
breaks Google Sign-In until the OAuth clients are updated.

| Where | Key | Value |
|---|---|---|
| API | `Auth:Google:ClientIds` (env `Auth__Google__ClientIds`, comma-separated) | web, Android (debug + release), iOS client ids |
| API | `Auth:OtpEnabled` (env `AUTH_OTP_ENABLED` → `Auth__OtpEnabled`) | false |
| App | `--dart-define=GOOGLE_SERVER_CLIENT_ID` | the **web** client id (Android puts it in the ID token's `aud`) |
| App | `--dart-define=GOOGLE_IOS_CLIENT_ID` | the iOS client id |
| iOS | `Info.plist` `CFBundleURLTypes` | the iOS client id reversed (`com.googleusercontent.apps.…`) |

## 7. Tests

- Backend unit: verifier (signature, wrong key, `iss`, `aud`, expired, future `iat`, no `sub`,
  `alg=none`, HS256 confusion) against a local RSA key.
- Backend API (fake verifier): shops list, register, sign in on a 2nd phone (device B),
  wrong PIN ×5 → lock, unknown tenant, other account's tenant, reset → old PIN refused,
  link a phone shop, link conflict, shop limit, `otp_disabled` with the switch off, OTP tests
  unchanged with it on, per-account rate limit, `Users.Phone` null for Google users.
- App: `GoogleAuth` error mapping, controller flows (register, choose shop, reset, link, guard
  by tenant id), screens (Login, choose shop, Register steps, Reset), no-English check on the
  new screens.
