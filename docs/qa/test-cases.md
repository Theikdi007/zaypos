# ZayPOS — Test cases (v0.3.x)

Scope: everything up to tag `v0.3.0-sync` (+ dashboard low-stock link).
Run by the `qa-engineer` agent first; the owner then re-runs the MANUAL cases and any FAIL on a real phone.

**Columns** — Pri: P1 must pass for beta · P2 should pass · P3 nice to have.
Type: **Auto** (QA proves it with a test) · **Manual** (needs a human on a real phone) · **Both**.
QA result: PASS / FAIL / BLOCKED / MANUAL. Owner result: ✅ / ❌ + note.

**Setup for manual runs** (see `docs/mobile/dev-setup.md`): Docker + `zaypos-sql` running, API on
`http://0.0.0.0:5076`, iPhone (device **A**) and iOS Simulator or Android (device **B**) on the same Wi-Fi,
app started with `--dart-define=API_BASE_URL=http://<Mac IP>:5076`. OTP codes appear in the API terminal.

---

## 1. Register & sign in (AUTH)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-AUTH-01 | P1 | Both | Register → enter a new phone → "ကုဒ်ပို့မယ်" | API logs `ZayPOS code: ######`; app moves to the OTP boxes with a resend timer | | | |
| TC-AUTH-02 | P1 | Both | Enter the correct OTP → choose "ကုန်စုံဆိုင်" → "ကြိုတင်စာရင်း" → set a 6-digit PIN | Shop is created; Dashboard opens; device code is **A** | | | |
| TC-AUTH-03 | P1 | Auto | Enter a wrong OTP 5 times | Each wrong try is refused in Burmese; after 5 the code is dead and a new one must be requested | | | |
| TC-AUTH-04 | P2 | Auto | Request OTP 4 times within an hour for the same phone | 4th request refused with the rate-limit message (`otp_rate_limited`) | | | |
| TC-AUTH-05 | P2 | Auto | OTP older than 5 minutes | Refused as expired | | | |
| TC-AUTH-06 | P1 | Auto | Register again with an already registered phone | Refused with "phone already registered" message; no second shop | | | |
| TC-AUTH-07 | P1 | Both | On device B: Login with the same phone + PIN | Full download screen "ဆိုင်ဒေတာ ဒေါင်းနေသည်…" then Dashboard; device code **B** | | | |
| TC-AUTH-08 | P1 | Auto | Login with the right phone and a wrong PIN 5 times | Refused each time; then locked 15 minutes, even with the right PIN | | | |
| TC-AUTH-09 | P2 | Auto | Login with an unknown phone | Same error text as a wrong PIN (no hint that the phone isn't registered) | | | |
| TC-AUTH-10 | P1 | Auto | Access token expires while 3 requests run at once | Exactly **one** `/auth/refresh`; all 3 requests succeed | | | |
| TC-AUTH-11 | P1 | Auto | Refresh succeeds on the server but the response is lost; app retries with the old refresh token within 2 min | Retry gets a new token; the device is **not** signed out | | | |
| TC-AUTH-12 | P2 | Auto | Reuse an old refresh token after more than 2 minutes | Whole device session revoked; app returns to Login and keeps the outbox | | | |

## 2. Unlock & PIN (PIN)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-PIN-01 | P1 | Both | Close the app, turn on airplane mode, open the app, enter the PIN | Unlocks offline; data visible | | | |
| TC-PIN-02 | P1 | Auto | Wrong PIN 5 times on the unlock screen | Locked 15 minutes locally, with a countdown/message in Burmese | | | |
| TC-PIN-03 | P1 | Both | Unlock screen → "PIN မေ့နေပါသလား?" → OTP → new PIN | New PIN works offline afterwards; old PIN refused; lockout cleared | | | |
| TC-PIN-04 | P2 | Auto | PIN reset while locked out | Reset is reachable and clears the lock | | | |
| TC-PIN-05 | P2 | Manual | Watch the screen while PIN is checked | No visible freeze (hashing runs off the UI thread) | | | |

## 3. Shop templates & features (FEAT)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-FEAT-01 | P1 | Auto | Register one shop per template (grocery, pharmacy, phone, fashion, hardware, service, other) | Feature flags equal `mobile/lib/core/features/shop_template.dart` and the server mapping | | | |
| TC-FEAT-02 | P1 | Both | Settings → ဆိုင် Features → turn "သက်တမ်းကုန်ရက် / Batch" on | Add Product shows Batch + expiry fields; device B sees the flag after sync | | | |
| TC-FEAT-03 | P2 | Auto | Turn a feature off after data was entered with it | Data is kept; fields hidden; turning it on again shows the data | | | |
| TC-FEAT-04 | P2 | Auto | Restaurant (v2) toggle | Not switchable | | | |

## 4. Products & stock (PROD)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-PROD-01 | P1 | Both | New grocery shop with presets | 20 products, each "ဈေးနှုန်း ထည့်ရန်" and grey "Stock မမှတ်ရသေး"; Dashboard card "ဈေးနှုန်း မထည့်ရသေးသော ပစ္စည်း 20 ခု" | | | |
| TC-PROD-02 | P1 | Both | Add a product: name, cost 450, price 600, unit ဗူး | Saved; margin shows +150 Ks (33%); appears on device B after sync | | | |
| TC-PROD-03 | P1 | Auto | Product name longer than the server limit (`/sync/limits` products.name) | Form refuses with a Burmese message; nothing saved | | | |
| TC-PROD-04 | P1 | Auto | Barcode typed with Myanmar digits (၈၈၃…) | Stored as 0-9; other non-ASCII refused | | | |
| TC-PROD-05 | P1 | Both | Untracked product → tap → "Stock ဖြည့်မယ်" → 20 | Shows exactly 20 (first count is an adjustment), badge becomes normal | | | |
| TC-PROD-06 | P1 | Auto | Untracked product sold once (stock −1), then first count 20 | Shows 20, not 19 | | | |
| TC-PROD-07 | P1 | Both | Tracked product with low-alert 5, sell until 4 left | Counted in Dashboard "Stock နည်းနေသည်" and Products "Stock နည်း" — same number | | | |
| TC-PROD-08 | P1 | Both | Dashboard "Stock နည်းနေသည်" card → tap | Products opens with "Stock နည်း" filter selected | | | |
| TC-PROD-09 | P2 | Both | Pharmacy: add product with batch B1 exp 2027-06-30 | Saved with batch; stock per batch = sum of its movements | | | |
| TC-PROD-10 | P2 | Both | Phone shop: add product with 2 IMEIs | Stock = 2; warranty months saved | | | |
| TC-PROD-11 | P2 | Both | Fashion: sizes M,L × colours black,white | 4 variants, each with its own stock | | | |
| TC-PROD-12 | P2 | Auto | Hardware: stock 2.5 ft | Stored as 2500 milli; shown as 2.5 | | | |
| TC-PROD-13 | P3 | Manual | Add product photo, barcode scan with camera | Works on a real phone | | | |

## 5. Selling (POS)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-POS-01 | P1 | Both | POS → tap a product 2× → Checkout → cash, received 10,000 | Change shown correctly; receipt **A-0001**; Dashboard today total updates | | | |
| TC-POS-02 | P1 | Both | Tap a product with price 0 | Price keypad opens; saved price used for this sale and stored on the product | | | |
| TC-POS-03 | P1 | Auto | Close the price keypad without saving | Nothing added; price stays 0 | | | |
| TC-POS-04 | P1 | Both | Quick Sale 2,500 "ဆပ်ပြာ" + Quick Sale 1,000 → Checkout | Two lines without product; total 3,500; no stock movement | | | |
| TC-POS-05 | P1 | Auto | Checkout "ငွေသား" with received < total | Confirm disabled with Burmese hint | | | |
| TC-POS-06 | P1 | Auto | Checkout "အကြွေး" without a customer | Confirm disabled with Burmese hint | | | |
| TC-POS-07 | P1 | Auto | Double-tap Confirm quickly | One sale only | | | |
| TC-POS-08 | P2 | Both | KBZPay / WavePay sale | Saved with that method; appears in history filter | | | |
| TC-POS-09 | P1 | Auto | 2,500 sales on one device | Receipt numbers A-0001 … A-2500, no gaps or repeats | | | |
| TC-POS-10 | P1 | Auto | Sale line price 600 × qty 2.5 (hardware) | Line total 1,500 (rounding per `Qty.lineTotal`), server total equal | | | |
| TC-POS-11 | P2 | Manual | Receipt screen: "Viber ပို့မယ်", "ပုံ သိမ်းမယ်" | Share sheet opens / image saved | | | |

## 6. Void & sales history (SALE)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-SALE-01 | P1 | Both | Void a cash sale | Marked ပယ်ဖျက်ပြီး; stock returned; today total reduced | | | |
| TC-SALE-02 | P1 | Both | Void a debt sale | Customer balance reduced by the sale total | | | |
| TC-SALE-03 | P1 | Auto | Void then un-void | Stock and debt back to the voided-before state, once | | | |
| TC-SALE-04 | P2 | Both | History filters (all / cash / KBZ / Wave / debt) | Lists match; voided shown struck through | | | |

## 7. Customers & debt (DEBT)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-DEBT-01 | P1 | Both | Add customer with opening debt 52,000 | Balance 52,000; total "ရရန်ကျန်" updated | | | |
| TC-DEBT-02 | P1 | Both | Debt sale 24,000 to that customer | Balance 76,000; history shows "+24,000" | | | |
| TC-DEBT-03 | P1 | Both | Pay debt 20,000 by KBZPay | Balance 56,000; "−20,000" entry; remaining shown before confirming | | | |
| TC-DEBT-04 | P2 | Auto | Pay more than owed | Sheet shows "ပိုပေးထား …"; balance goes negative only if allowed by spec — record behaviour | | | |
| TC-DEBT-05 | P2 | Both | Credit limit 100,000 then debt sale to 120,000 | Sale kept; `creditLimitExceeded` issue appears in "စစ်ရန်" | | | |
| TC-DEBT-06 | P2 | Auto | 1,000 ledger entries | Balance computed in SQL, customers list still fast (< 300 ms query) | | | |

## 8. Dashboard & reports (RPT)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-RPT-01 | P1 | Auto | Sales today incl. one voided, one debt | Today total excludes voided; profit = Σ(price − costSnapshot) × qty | | | |
| TC-RPT-02 | P1 | Auto | Change a product's cost after selling it | Past profit unchanged (cost snapshot) | | | |
| TC-RPT-03 | P2 | Both | Report: today / week / month tabs, payment split, top products | Numbers match the sales list | | | |
| TC-RPT-04 | P2 | Auto | Sales just before/after midnight Myanmar time (UTC+06:30) | Counted on the correct local day | | | |

## 9. Sync (SYNC) — two devices A and B, one shop

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-SYNC-01 | P1 | Both | A sells; B pulls to refresh | Sale appears on B with number A-xxxx; totals equal | | | |
| TC-SYNC-02 | P1 | Both | A offline: 3 sales; chip shows "3 စောင့်"; back online | All 3 pushed in order; chip "Sync ပြီး"; B sees them | | | |
| TC-SYNC-03 | P1 | Both | A and B both offline, both sell, both online | No lost or duplicated sales; numbers A-… and B-… | | | |
| TC-SYNC-04 | P1 | Auto | Same unit pushed twice (lost response) | Applied once | | | |
| TC-SYNC-05 | P1 | Both | A and B both void the same sale offline, then sync | Stock/debt restored once; second void `skipped`; no orphan reversal rows | | | |
| TC-SYNC-06 | P1 | Both | A and B edit the same product price offline (A first, B later) | Later edit wins on both devices | | | |
| TC-SYNC-07 | P1 | Auto | A edits a product offline; a pull brings an older server version | Local unpushed edit is kept | | | |
| TC-SYNC-08 | P1 | Both | Phone shop: A and B sell the same IMEI offline | Both sales kept; `serialDoubleSold` in "စစ်ရန်" | | | |
| TC-SYNC-09 | P1 | Auto | Tracked product sold below zero | Sale kept; one `negativeStock` issue | | | |
| TC-SYNC-10 | P1 | Auto | Untracked product sold | No `negativeStock` issue | | | |
| TC-SYNC-11 | P1 | Auto | Server rejects a unit (malformed) | Outbox blocked at that unit; later units wait; pull continues; rejected-unit screen shows reason; no delete button | | | |
| TC-SYNC-12 | P2 | Both | Fix a rejected unit in the editor and resend | Gets a new unit id, keeps its order, is applied | | | |
| TC-SYNC-13 | P1 | Auto | Pull page fails half-way | Nothing from that page saved; cursor unchanged | | | |
| TC-SYNC-14 | P2 | Auto | Device clock 1 hour ahead edits a product | Server clamps time; `clockSkew` issue | | | |
| TC-SYNC-15 | P2 | Both | Mark an issue as checked in "စစ်ရန်" | Resolved on server; disappears on device B too | | | |
| TC-SYNC-16 | P1 | Auto | Sign in to a different shop with a non-empty outbox | Refused with warning; outbox kept | | | |

## 10. Devices (DEV)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-DEV-01 | P1 | Both | Settings → ဖုန်းများ on A | Lists A and B; A marked as this phone | | | |
| TC-DEV-02 | P1 | Both | A removes B | B is signed out on its next sync; its unpushed outbox is kept and warned about | | | |
| TC-DEV-03 | P2 | Auto | A tries to remove itself / another shop's device | Refused | | | |
| TC-DEV-04 | P2 | Auto | Reinstall app on B, login again | Registers as a new device code (C); old receipts unaffected | | | |

## 11. Security & API (SEC)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-SEC-01 | P1 | Auto | Shop X token pulls | Never returns any row of shop Y | | | |
| TC-SEC-02 | P1 | Auto | Shop X pushes a row with shop Y's tenantId or an existing id of shop Y | Rejected; shop Y data unchanged | | | |
| TC-SEC-03 | P1 | Auto | Call /sync, /me, /devices without a token / with a revoked device | 401 / 403 `device_revoked` | | | |
| TC-SEC-04 | P1 | Auto | Search the repo for secrets (passwords, JWT keys, API keys) | None committed; `appsettings.Development.json` git-ignored | | | |
| TC-SEC-05 | P2 | Auto | `/auth/*` rate limits by phone and IP | Limits as in README §4; different phones on one IP not blocked together | | | |
| TC-SEC-06 | P2 | Auto | Release builds: Android manifest + iOS Info.plist | INTERNET present; no cleartext HTTP in release; sample data seeding impossible | | | |

## 12. Language, layout & robustness (UX)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-UX-01 | P1 | Manual | Airplane mode, first launch after install | Myanmar text renders correctly (bundled fonts) | | | |
| TC-UX-02 | P1 | Auto | Search all user-facing strings | No English left in Burmese screens except brand/payment names; no broken Unicode | | | |
| TC-UX-03 | P2 | Manual | Small phone (iPhone SE / small Android), largest system font | No overflow; buttons ≥ 44 px | | | |
| TC-UX-04 | P2 | Auto | Widget tests for every screen at 320 px width | No RenderFlex overflow | | | |
| TC-UX-05 | P2 | Manual | Kill the app during checkout | After reopen: either the full sale exists or nothing (never half) | | | |
| TC-UX-06 | P3 | Manual | 1 hour of normal use | No crash; battery/heat acceptable | | | |
