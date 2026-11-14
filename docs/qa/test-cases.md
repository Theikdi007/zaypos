# ZayPOS — Test cases (v0.3.x)

Scope: everything up to tag `v0.3.0-sync` (+ dashboard low-stock link).
Run by the `qa-engineer` agent first; the owner then re-runs the MANUAL cases and any FAIL on a real phone.

**Columns** — Pri: P1 must pass for beta · P2 should pass · P3 nice to have.
Type: **Auto** (QA proves it with a test) · **Manual** (needs a human on a real phone) · **Both**.
QA result: PASS / FAIL / BLOCKED / MANUAL. Owner result: ✅ / ❌ + note.

**Setup for manual runs** (see `docs/mobile/dev-setup.md`): Docker + `zaypos-sql` running, API on
`http://0.0.0.0:5076`, iPhone (device **A**) and iOS Simulator or Android (device **B**) on the same Wi-Fi,
app started with `--dart-define=API_BASE_URL=http://<Mac IP>:5076`. OTP codes appear in the API terminal.

**QA round 1 (2026-11-14)** — results below; summary in `docs/qa/round-1-summary.md`, bugs in `docs/qa/bugs.md`.
Evidence paths: `m/` = `mobile/test/`, `b/` = `backend/tests/`. "live" = `flutter test m/live_*.dart` run against the
API on a scratch database `ZayPOS_QA_20261114` (dropped afterwards). For **Both** cases the QA result covers the
automated part; the owner still runs the phone steps.

---

## 1. Register & sign in (AUTH)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-AUTH-01 | P1 | Both | Register → enter a new phone → "ကုဒ်ပို့မယ်" | API logs `ZayPOS code: ######`; app moves to the OTP boxes with a resend timer | PASS | b/ZayPOS.QA.Tests/QaAuthTests.cs::TC_AUTH_01_otp_request_sends_a_six_digit_ZayPOS_code; m/qa/qa_app_flows_test.dart::TC-AUTH-01 … resend timer | 6 boxes + "ပြန်ပို့မယ် (1:00)" counting down, resend disabled until 0, then re-sends |
| TC-AUTH-02 | P1 | Both | Enter the correct OTP → choose "ကုန်စုံဆိုင်" → "ကြိုတင်စာရင်း" → set a 6-digit PIN | Shop is created; Dashboard opens; device code is **A** | PASS | b/ZayPOS.Api.Tests/AuthTests.cs::Register_creates_tenant_owner_template_features_and_device_A; m/auth_screens_test.dart::register: send code…; live m/live_step4_test.dart | Dashboard opens after the first download screen |
| TC-AUTH-03 | P1 | Auto | Enter a wrong OTP 5 times | Each wrong try is refused in Burmese; after 5 the code is dead and a new one must be requested | PASS | b/ZayPOS.QA.Tests/QaAuthTests.cs::TC_AUTH_03_five_wrong_otps_kill_the_code_and_a_new_code_works; m/api_client_test.dart::every server auth code has its own Burmese message | `otp_invalid` → "ကုဒ် မှားနေပါတယ် (သို့) သက်တမ်းကုန်သွားပါပြီ။" |
| TC-AUTH-04 | P2 | Auto | Request OTP 4 times within an hour for the same phone | 4th request refused with the rate-limit message (`otp_rate_limited`) | PASS | b/ZayPOS.Api.Tests/AuthTests.cs::Otp_is_limited_to_three_per_phone_per_hour | 429 + Retry-After; only 3 SMS sent |
| TC-AUTH-05 | P2 | Auto | OTP older than 5 minutes | Refused as expired | PASS | b/ZayPOS.QA.Tests/QaAuthTests.cs::TC_AUTH_05_otp_older_than_five_minutes_is_refused | Manual clock: 4:59 accepted, 5:01 → `otp_invalid` |
| TC-AUTH-06 | P1 | Auto | Register again with an already registered phone | Refused with "phone already registered" message; no second shop | PASS | b/ZayPOS.QA.Tests/QaAuthTests.cs::TC_AUTH_06_registered_phone_cannot_register_again_and_no_second_shop | 409 `phone_registered` on /otp and /register; 1 tenant row |
| TC-AUTH-07 | P1 | Both | On device B: Login with the same phone + PIN | Full download screen "ဆိုင်ဒေတာ ဒေါင်းနေသည်…" then Dashboard; device code **B** | PASS | m/auth_screens_test.dart::signed out → Login; a first login downloads the shop…; b/ZayPOS.Api.Tests/AuthTests.cs::Login_on_a_new_phone_gets_the_next_code…; live m/live_sync_test.dart | |
| TC-AUTH-08 | P1 | Auto | Login with the right phone and a wrong PIN 5 times | Refused each time; then locked 15 minutes, even with the right PIN | PASS | b/ZayPOS.Api.Tests/AuthTests.cs::Five_wrong_pins_lock_the_account_for_15_minutes | |
| TC-AUTH-09 | P2 | Auto | Login with an unknown phone | Same error text as a wrong PIN (no hint that the phone isn't registered) | PASS | b/ZayPOS.QA.Tests/QaAuthTests.cs::TC_AUTH_09_unknown_phone_looks_exactly_like_a_wrong_pin | Status, code, title, detail identical |
| TC-AUTH-10 | P1 | Auto | Access token expires while 3 requests run at once | Exactly **one** `/auth/refresh`; all 3 requests succeed | PASS | m/api_client_test.dart::3 parallel 401s cause ONE /auth/refresh… | |
| TC-AUTH-11 | P1 | Auto | Refresh succeeds on the server but the response is lost; app retries with the old refresh token within 2 min | Retry gets a new token; the device is **not** signed out | PASS | b/ZayPOS.Api.Tests/AuthTests.cs::Retry_within_2_minutes_of_rotation_rotates_the_unseen_replacement_instead; m/api_client_test.dart::a network failure during refresh keeps the session | |
| TC-AUTH-12 | P2 | Auto | Reuse an old refresh token after more than 2 minutes | Whole device session revoked; app returns to Login and keeps the outbox | PASS | b/ZayPOS.Api.Tests/AuthTests.cs::Reuse_more_than_2_minutes_after_rotation_revokes_the_device_chain; m/qa/qa_app_flows_test.dart::TC-AUTH-12 … | App: 401 `invalid_refresh_token` → signed out, outbox kept + warning |

## 2. Unlock & PIN (PIN)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-PIN-01 | P1 | Both | Close the app, turn on airplane mode, open the app, enter the PIN | Unlocks offline; data visible | PASS | m/auth_controller_test.dart::a restart opens locked; the right PIN unlocks with no network | Real airplane mode: owner |
| TC-PIN-02 | P1 | Auto | Wrong PIN 5 times on the unlock screen | Locked 15 minutes locally, with a countdown/message in Burmese | PASS | m/auth_controller_test.dart::5 wrong PINs lock for 15 minutes, across restarts… | Message counts down minutes ("၁ မိနစ်") |
| TC-PIN-03 | P1 | Both | Unlock screen → "PIN မေ့နေပါသလား?" → OTP → new PIN | New PIN works offline afterwards; old PIN refused; lockout cleared | PASS | m/qa/qa_app_flows_test.dart::TC-PIN-03 …; m/step4_test.dart::locked out → "PIN မေ့နေပါသလား?" …; live m/live_step4_test.dart | |
| TC-PIN-04 | P2 | Auto | PIN reset while locked out | Reset is reachable and clears the lock | PASS | m/step4_test.dart::locked out: SMS code + new PIN…; ::router: the reset screen is reachable signed out and while locked | |
| TC-PIN-05 | P2 | Manual | Watch the screen while PIN is checked | No visible freeze (hashing runs off the UI thread) | MANUAL | (m/pin_phone_test.dart::default: … on an isolate shows hashing is on an isolate) | Owner: low-end Android, enter PIN 3×, watch the dots/keypad for a stall |

## 3. Shop templates & features (FEAT)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-FEAT-01 | P1 | Auto | Register one shop per template (grocery, pharmacy, phone, fashion, hardware, service, other) | Feature flags equal `mobile/lib/core/features/shop_template.dart` and the server mapping | PASS | b/ZayPOS.QA.Tests/QaAuthTests.cs::TC_FEAT_01_every_template_registers_with_its_feature_flags (7 templates); b/ZayPOS.Domain.Tests/ShopTemplateTests.cs::Mapping_equals_shop_template_dart | |
| TC-FEAT-02 | P1 | Both | Settings → ဆိုင် Features → turn "သက်တမ်းကုန်ရက် / Batch" on | Add Product shows Batch + expiry fields; device B sees the flag after sync | PASS | m/qa/qa_app_flows_test.dart::TC-FEAT-02 …; m/drift_repositories_test.dart::feature toggles are stored and pushed as setFeatures…; m/sync_engine_test.dart::customers and tenant features follow the same rule… | |
| TC-FEAT-03 | P2 | Auto | Turn a feature off after data was entered with it | Data is kept; fields hidden; turning it on again shows the data | PASS | m/qa/qa_app_flows_test.dart::TC-FEAT-03 … | Batch rows kept, form fields hidden/shown. Note: no screen lists a product's batches at all (see BUG-1) |
| TC-FEAT-04 | P2 | Auto | Restaurant (v2) toggle | Not switchable | PASS | m/qa/qa_app_flows_test.dart::TC-FEAT-02 … TC-FEAT-04 restaurant disabled | Toggle disabled in Settings; but Register lets you pick it → TC-FEAT-NEW-1 |
| TC-FEAT-NEW-1 | P3 | Auto | Register step 2 → tap "စားသောက် / ကော်ဖီ" (v2) → ဆက်သွားမယ် | v2 template cannot be chosen | FAIL | m/qa/qa_app_flows_test.dart::TC-FEAT-NEW-1 … | BUG-10: restaurant is selectable at registration |

## 4. Products & stock (PROD)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-PROD-01 | P1 | Both | New grocery shop with presets | 20 products, each "ဈေးနှုန်း ထည့်ရန်" and grey "Stock မမှတ်ရသေး"; Dashboard card "ဈေးနှုန်း မထည့်ရသေးသော ပစ္စည်း 20 ခု" | PASS | m/qa/qa_app_flows_test.dart::TC-PROD-01 …; m/step4_test.dart::register with "ကြိုတင်စာရင်း"…; live m/live_step4_test.dart | Card shows Myanmar digits ("၂၀ ခု") |
| TC-PROD-02 | P1 | Both | Add a product: name, cost 450, price 600, unit ဗူး | Saved; margin shows +150 Ks (33%); appears on device B after sync | PASS | m/qa/qa_pos_ui_test.dart::TC-PROD-02 …; live m/live_sync_test.dart (B sees A's product) | |
| TC-PROD-03 | P1 | Auto | Product name longer than the server limit (`/sync/limits` products.name) | Form refuses with a Burmese message; nothing saved | PASS | m/form_limits_test.dart::add product: a name over 150 characters is refused…; b/ZayPOS.Api.Tests/AccountTests.cs::A_name_one_over_the_published_limit_is_rejected… | |
| TC-PROD-04 | P1 | Auto | Barcode typed with Myanmar digits (၈၈၃…) | Stored as 0-9; other non-ASCII refused | PASS | m/form_limits_test.dart::add product: barcode letters are refused; Myanmar digits are stored as 0-9 | |
| TC-PROD-05 | P1 | Both | Untracked product → tap → "Stock ဖြည့်မယ်" → 20 | Shows exactly 20 (first count is an adjustment), badge becomes normal | PASS | m/untracked_stock_test.dart::"Stock မမှတ်ရသေး" filter: the first count starts tracking… | |
| TC-PROD-06 | P1 | Auto | Untracked product sold once (stock −1), then first count 20 | Shows 20, not 19 | PASS | m/untracked_stock_test.dart::"Stock မမှတ်ရသေး" filter: the first count starts tracking, even after earlier sales; m/drift_repositories_test.dart::tracked = any live restock/adjustment > 0 (SQL)… | Adjustment +21 → 20 |
| TC-PROD-07 | P1 | Both | Tracked product with low-alert 5, sell until 4 left | Counted in Dashboard "Stock နည်းနေသည်" and Products "Stock နည်း" — same number | PASS | m/untracked_stock_test.dart::Dashboard low-stock card and Products "Stock နည်း" filter show the same number… | |
| TC-PROD-08 | P1 | Both | Dashboard "Stock နည်းနေသည်" card → tap | Products opens with "Stock နည်း" filter selected | PASS | m/untracked_stock_test.dart::tapping the Dashboard low-stock card opens Products filtered… | |
| TC-PROD-09 | P2 | Both | Pharmacy: add product with batch B1 exp 2027-06-30 | Saved with batch; stock per batch = sum of its movements | PASS | m/add_product_modules_test.dart::pharmacy: saves a batch…; m/drift_repositories_test.dart::product with batches and serials… | But POS sales never reduce a batch → BUG-2 |
| TC-PROD-10 | P2 | Both | Phone shop: add product with 2 IMEIs | Stock = 2; warranty months saved | PASS | m/add_product_modules_test.dart::phone: saves IMEI serials (inStock), warranty, and stock = IMEI count | But POS sales never mark an IMEI sold → BUG-2 |
| TC-PROD-11 | P2 | Both | Fashion: sizes M,L × colours black,white | 4 variants, each with its own stock | PASS | m/qa/qa_modules_test.dart::TC-PROD-11 … | But POS sales never reduce a variant → BUG-2 |
| TC-PROD-12 | P2 | Auto | Hardware: stock 2.5 ft | Stored as 2500 milli; shown as 2.5 | PASS | m/qa/qa_pos_ui_test.dart::TC-PROD-12 … | Shown "2.5 ခု" (unit ignored, minor) |
| TC-PROD-13 | P3 | Manual | Add product photo, barcode scan with camera | Works on a real phone | MANUAL | — | Owner. QA expects FAIL: photo tile and scan buttons have empty handlers (`onTap: () {}` in add_product_screen.dart / pos_screen.dart) |
| TC-PROD-NEW-1 | P1 | Auto | Products → tap / long-press an existing product → change price | An edit form opens; price/cost/name can be changed | FAIL | m/qa/qa_app_flows_test.dart::TC-PROD-NEW-1 … | BUG-1: no edit screen exists (tap = restock only) |
| TC-PROD-NEW-2 | P2 | Auto | Register step 3 for grocery / pharmacy / phone / hardware | Only offers/promises the presets the server really serves | FAIL | m/qa/qa_app_flows_test.dart::TC-PROD-NEW-2 … (4 tests); b/ZayPOS.Api.Tests/AccountTests.cs::Presets_default_to_the_shops_template… | BUG-6: promises 300/250/120/200 "with barcode"; server has 20 (no barcode) / 0 |

## 5. Selling (POS)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-POS-01 | P1 | Both | POS → tap a product 2× → Checkout → cash, received 10,000 | Change shown correctly; receipt **A-0001**; Dashboard today total updates | PASS | m/qa/qa_pos_ui_test.dart::TC-POS-01 …; m/qa/qa_ledger_drift_test.dart::TC-POS-01 / TC-POS-09 … | Change 8,800; first receipt of a new shop A-0001 |
| TC-POS-02 | P1 | Both | Tap a product with price 0 | Price keypad opens; saved price used for this sale and stored on the product | PASS | m/needs_price_test.dart::POS: the tile shows the badge; tapping asks for the price… | |
| TC-POS-03 | P1 | Auto | Close the price keypad without saving | Nothing added; price stays 0 | PASS | m/needs_price_test.dart::POS: the tile shows the badge… (dismissed part) | |
| TC-POS-04 | P1 | Both | Quick Sale 2,500 "ဆပ်ပြာ" + Quick Sale 1,000 → Checkout | Two lines without product; total 3,500; no stock movement | PASS | m/qa/qa_pos_ui_test.dart::TC-POS-04 … | |
| TC-POS-05 | P1 | Auto | Checkout "ငွေသား" with received < total | Confirm disabled with Burmese hint | PASS | m/screens_smoke_test.dart::cash received below total blocks confirm; enough unblocks | |
| TC-POS-06 | P1 | Auto | Checkout "အကြွေး" without a customer | Confirm disabled with Burmese hint | PASS | m/screens_smoke_test.dart::credit checkout adds a creditSale entry… ; ::debt checkout without a customer cannot be confirmed | |
| TC-POS-07 | P1 | Auto | Double-tap Confirm quickly | One sale only | PASS | m/qa/qa_pos_ui_test.dart::TC-POS-07 … | 300 ms commit, taps 60 ms apart → 1 sale |
| TC-POS-08 | P2 | Both | KBZPay / WavePay sale | Saved with that method; appears in history filter | PASS | m/qa/qa_pos_ui_test.dart::TC-POS-08 / TC-SALE-04 … | |
| TC-POS-09 | P1 | Auto | 2,500 sales on one device | Receipt numbers A-0001 … A-2500, no gaps or repeats | PASS | m/qa/qa_ledger_drift_test.dart::TC-POS-01 / TC-POS-09 … | Drift, ~2 s |
| TC-POS-10 | P1 | Auto | Sale line price 600 × qty 2.5 (hardware) | Line total 1,500 (rounding per `Qty.lineTotal`), server total equal | PASS | m/qa/qa_ledger_drift_test.dart::TC-POS-10 …; b/ZayPOS.QA.Tests/QaSyncSecurityTests.cs::TC_POS_10_server_total_for_600_times_2_5_is_1500 | Math is right, but the cashier cannot enter 2.5 → TC-POS-NEW-1 |
| TC-POS-11 | P2 | Manual | Receipt screen: "Viber ပို့မယ်", "ပုံ သိမ်းမယ်" | Share sheet opens / image saved | MANUAL | — | Owner on a real phone |
| TC-POS-NEW-1 | P1 | Auto | Hardware shop (decimalQty on) → add a product to the cart → Checkout → set qty 2.5 | Quantity 2.5 can be entered | FAIL | m/qa/qa_pos_ui_test.dart::TC-POS-NEW-1 … | BUG-3: only whole-unit −/+ steppers |
| TC-POS-NEW-2 | P1 | Auto | Phone / fashion / pharmacy shop → sell an IMEI / size-colour / batch product in POS | The sale line records which IMEI / variant / batch; that one's stock drops | FAIL | m/qa/qa_modules_test.dart::TC-POS-NEW-2 … (3 tests) | BUG-2: serialId / variantId / batchId always null |

## 6. Void & sales history (SALE)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-SALE-01 | P1 | Both | Void a cash sale | Marked ပယ်ဖျက်ပြီး; stock returned; today total reduced | PASS | m/qa/qa_ledger_drift_test.dart::TC-SALE-01 …; m/qa/qa_pos_ui_test.dart::TC-POS-08 / TC-SALE-04 … | |
| TC-SALE-02 | P1 | Both | Void a debt sale | Customer balance reduced by the sale total | PASS | m/drift_repositories_test.dart::credit checkout records the debt entry…; m/screens_smoke_test.dart::voiding a credit sale reverses it… | |
| TC-SALE-03 | P1 | Auto | Void then un-void | Stock and debt back to the voided-before state, once | PASS | m/qa/qa_ledger_drift_test.dart::TC-SALE-03 … | Second un-void is a no-op (no extra unit) |
| TC-SALE-04 | P2 | Both | History filters (all / cash / KBZ / Wave / debt) | Lists match; voided shown struck through | PASS | m/qa/qa_pos_ui_test.dart::TC-POS-08 / TC-SALE-04 … | History lists today only; the "ယနေ့" date button does nothing (note) |

## 7. Customers & debt (DEBT)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-DEBT-01 | P1 | Both | Add customer with opening debt 52,000 | Balance 52,000; total "ရရန်ကျန်" updated | PASS | m/qa/qa_ledger_drift_test.dart::TC-DEBT-01..04 … | |
| TC-DEBT-02 | P1 | Both | Debt sale 24,000 to that customer | Balance 76,000; history shows "+24,000" | PASS | m/qa/qa_ledger_drift_test.dart::TC-DEBT-01..04 …; m/screens_smoke_test.dart::credit checkout adds a creditSale entry… | Shown as "+ 24,000" |
| TC-DEBT-03 | P1 | Both | Pay debt 20,000 by KBZPay | Balance 56,000; "−20,000" entry; remaining shown before confirming | PASS | m/qa/qa_ledger_drift_test.dart::TC-DEBT-01..04 …; m/screens_smoke_test.dart::pay debt sheet records a payment entry | |
| TC-DEBT-04 | P2 | Auto | Pay more than owed | Sheet shows "ပိုပေးထား …"; balance goes negative only if allowed by spec — record behaviour | PASS | m/qa/qa_ledger_drift_test.dart::TC-DEBT-01..04 …; m/debt_ledger_test.dart::overpayment yields a negative balance | Behaviour: accepted, balance −4,000 |
| TC-DEBT-05 | P2 | Both | Credit limit 100,000 then debt sale to 120,000 | Sale kept; `creditLimitExceeded` issue appears in "စစ်ရန်" | PASS | b/ZayPOS.Api.Tests/SyncTests.cs::Credit_sale_over_the_limit_is_kept_with_creditLimitExceeded; m/sync_engine_test.dart::sales / lines / … issues: insert or replace | No warning at sale time → TC-DEBT-NEW-1 |
| TC-DEBT-06 | P2 | Auto | 1,000 ledger entries | Balance computed in SQL, customers list still fast (< 300 ms query) | PASS | m/qa/qa_ledger_drift_test.dart::TC-DEBT-06 … | Measured on the Mac (in-memory SQLite); re-check on a low-end phone |
| TC-DEBT-NEW-1 | P2 | Auto | Customer with limit 100,000 owing 96,000 → Checkout → အကြွေး → pick customer, cart 24,000 | Checkout warns that the limit is exceeded (add-customer helper: "ဒီထက်ကျော်ရင် ရောင်းတဲ့အချိန် သတိပေးပါမယ်") | FAIL | m/qa/qa_pos_ui_test.dart::TC-DEBT-NEW-1 … | BUG-7 |
| TC-DEBT-NEW-2 | P1 | Auto | Pay-debt sheet → "20,000 Ks လက်ခံမယ်" tapped twice quickly | One payment recorded | FAIL | m/qa/qa_pos_ui_test.dart::TC-DEBT-NEW-2 … | BUG-4: two payments (balance reduced twice) |

## 8. Dashboard & reports (RPT)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-RPT-01 | P1 | Auto | Sales today incl. one voided, one debt | Today total excludes voided; profit = Σ(price − costSnapshot) × qty | PASS | m/qa/qa_ledger_drift_test.dart::TC-RPT-01 … | |
| TC-RPT-02 | P1 | Auto | Change a product's cost after selling it | Past profit unchanged (cost snapshot) | PASS | m/qa/qa_ledger_drift_test.dart::TC-RPT-02 …; m/acceptance_test.dart::changing the product cost after the sale… | Cost changed at DB level: the app has no edit screen (BUG-1) |
| TC-RPT-03 | P2 | Both | Report: today / week / month tabs, payment split, top products | Numbers match the sales list | PASS | m/qa/qa_ledger_drift_test.dart::TC-RPT-03 … | |
| TC-RPT-04 | P2 | Auto | Sales just before/after midnight Myanmar time (UTC+06:30) | Counted on the correct local day | PASS | m/qa/qa_ledger_drift_test.dart::TC-RPT-04 … | Run with the Mac on +06:30 |

## 9. Sync (SYNC) — two devices A and B, one shop

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-SYNC-01 | P1 | Both | A sells; B pulls to refresh | Sale appears on B with number A-xxxx; totals equal | PASS | live m/live_sync_test.dart::two phones of one shop…; m/sync_screens_test.dart::pull-to-refresh on the dashboard runs a sync | |
| TC-SYNC-02 | P1 | Both | A offline: 3 sales; chip shows "3 စောင့်"; back online | All 3 pushed in order; chip "Sync ပြီး"; B sees them | PASS | m/qa/qa_sync_test.dart::TC-SYNC-02 … | Chip text "Offline · sync ၃ ခုစောင့်" |
| TC-SYNC-03 | P1 | Both | A and B both offline, both sell, both online | No lost or duplicated sales; numbers A-… and B-… | PASS | live m/live_sync_test.dart (both sell offline: A-…, B-…, both kept); b/ZayPOS.Api.Tests/SyncTests.cs::Pushing_the_same_unit_twice_applies_it_once | |
| TC-SYNC-04 | P1 | Auto | Same unit pushed twice (lost response) | Applied once | PASS | b/ZayPOS.Api.Tests/SyncTests.cs::Pushing_the_same_unit_twice_applies_it_once; ::The_same_unit_pushed_concurrently_is_still_applied_once | |
| TC-SYNC-05 | P1 | Both | A and B both void the same sale offline, then sync | Stock/debt restored once; second void `skipped`; no orphan reversal rows | PASS | b/ZayPOS.Api.Tests/SyncTests.cs::Void_then_void_again_skips_the_second…; m/sync_engine_test.dart::skipped voidSale: outbox row and its reversal ledger rows go… | |
| TC-SYNC-06 | P1 | Both | A and B edit the same product price offline (A first, B later) | Later edit wins on both devices | PASS | b/ZayPOS.Api.Tests/SyncTests.cs::Products_are_last_writer_wins…; m/sync_engine_test.dart::products: replaced when pulled.updatedAt >= local… | Rules pass. Owner cannot run the steps: no price-edit screen (BUG-1). Fails with a skewed clock (TC-SYNC-NEW-1) |
| TC-SYNC-07 | P1 | Auto | A edits a product offline; a pull brings an older server version | Local unpushed edit is kept | PASS | m/sync_engine_test.dart::a pending local edit is NOT overwritten by a pulled row, even a newer one | |
| TC-SYNC-08 | P1 | Both | Phone shop: A and B sell the same IMEI offline | Both sales kept; `serialDoubleSold` in "စစ်ရန်" | PASS | b/ZayPOS.Api.Tests/SyncTests.cs::Two_devices_selling_the_same_IMEI…; live m/live_sync_test.dart | Proven at service/API level only: the POS screen never sends an IMEI (BUG-2), so the owner cannot reproduce it from the UI |
| TC-SYNC-09 | P1 | Auto | Tracked product sold below zero | Sale kept; one `negativeStock` issue | PASS | b/ZayPOS.Api.Tests/SyncTests.cs::Selling_below_zero_keeps_the_sale_and_raises_negativeStock_once | |
| TC-SYNC-10 | P1 | Auto | Untracked product sold | No `negativeStock` issue | PASS | b/ZayPOS.Api.Tests/SyncTests.cs::Untracked_products_never_raise_negativeStock_until_counted_in | |
| TC-SYNC-11 | P1 | Auto | Server rejects a unit (malformed) | Outbox blocked at that unit; later units wait; pull continues; rejected-unit screen shows reason; no delete button | PASS | m/sync_engine_test.dart::rejected: status + reason saved, later units are NOT sent…; m/sync_screens_test.dart::chip: synced → sync problem… | Reason is the server's English text (by design) |
| TC-SYNC-12 | P2 | Both | Fix a rejected unit in the editor and resend | Gets a new unit id, keeps its order, is applied | PASS | m/sync_engine_test.dart::"ပြင်ပြီး ပြန်ပို့မယ်": edits the local row, rebuilds the unit under a new id…; m/sync_screens_test.dart::chip… fix and resend | |
| TC-SYNC-13 | P1 | Auto | Pull page fails half-way | Nothing from that page saved; cursor unchanged | PASS | m/sync_engine_test.dart::the cursor is saved only after a whole page merged…; ::a network failure on page 2 keeps page 1… | |
| TC-SYNC-14 | P2 | Auto | Device clock 1 hour ahead edits a product | Server clamps time; `clockSkew` issue | PASS | b/ZayPOS.Api.Tests/SyncTests.cs::Products_are_last_writer_wins_and_future_edits_are_clamped_with_clockSkew; b/ZayPOS.QA.Tests/QaSyncSecurityTests.cs::TC_SYNC_NEW_1_server_takes… | Side effect on the phone → TC-SYNC-NEW-1 |
| TC-SYNC-15 | P2 | Both | Mark an issue as checked in "စစ်ရန်" | Resolved on server; disappears on device B too | PASS | b/ZayPOS.Api.Tests/SyncTests.cs::Owner_resolves_a_sync_issue_once_and_every_phone_pulls_it; m/sync_engine_test.dart::resolving an issue calls the server…; live m/live_sync_test.dart | |
| TC-SYNC-16 | P1 | Auto | Sign in to a different shop with a non-empty outbox | Refused with warning; outbox kept | PASS | m/auth_controller_test.dart::another shop while the outbox has units: refused BEFORE any network call… | |
| TC-SYNC-NEW-1 | P2 | Auto | A (clock +1 h) edits a product and syncs; 10 min later B (correct clock) edits it and syncs; A pulls | A shows B's (later) edit, like the server and B | FAIL | m/qa/qa_sync_test.dart::TC-SYNC-NEW-1 …; b/ZayPOS.QA.Tests/QaSyncSecurityTests.cs::TC_SYNC_NEW_1_server_takes_a_later_edit_over_a_clamped_future_edit (server half PASS) | BUG-5: A keeps its own value for up to the skew |

## 10. Devices (DEV)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-DEV-01 | P1 | Both | Settings → ဖုန်းများ on A | Lists A and B; A marked as this phone | PASS | m/step4_test.dart::devices: list with "ဒီဖုန်း"…; live m/live_step4_test.dart | |
| TC-DEV-02 | P1 | Both | A removes B | B is signed out on its next sync; its unpushed outbox is kept and warned about | PASS | live m/live_step4_test.dart (B signed out with `device_revoked` notice); m/auth_controller_test.dart::refresh refused (device_revoked): … outbox kept, warning shown | |
| TC-DEV-03 | P2 | Auto | A tries to remove itself / another shop's device | Refused | PASS | b/ZayPOS.Api.Tests/AccountTests.cs::A_device_cannot_revoke_itself_or_another_shops_device | |
| TC-DEV-04 | P2 | Auto | Reinstall app on B, login again | Registers as a new device code (C); old receipts unaffected | PASS | b/ZayPOS.QA.Tests/QaAuthTests.cs::TC_DEV_04_reinstall_gets_a_new_code_and_old_receipts_are_unaffected; m/auth_controller_test.dart::a fresh install … makes a new device id | Revoked code B is never reused |

## 11. Security & API (SEC)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-SEC-01 | P1 | Auto | Shop X token pulls | Never returns any row of shop Y | PASS | b/ZayPOS.QA.Tests/QaSyncSecurityTests.cs::TC_SEC_01_pull_never_returns_any_row_of_another_shop | All tables incl. sales, debt, issues, devices |
| TC-SEC-02 | P1 | Auto | Shop X pushes a row with shop Y's tenantId or an existing id of shop Y | Rejected; shop Y data unchanged | PASS | b/ZayPOS.QA.Tests/QaSyncSecurityTests.cs::TC_SEC_02_existing_ids_of_another_shop_are_rejected_and_left_untouched; b/ZayPOS.Api.Tests/SyncTests.cs::Rows_of_another_tenant_and_malformed_numbers_are_rejected | Sale / customer / movement ids, voidSale of Y's sale |
| TC-SEC-03 | P1 | Auto | Call /sync, /me, /devices without a token / with a revoked device | 401 / 403 `device_revoked` | PASS | b/ZayPOS.QA.Tests/QaSyncSecurityTests.cs::TC_SEC_03_no_token_is_401_and_a_revoked_device_is_403_device_revoked_everywhere | |
| TC-SEC-04 | P1 | Auto | Search the repo for secrets (passwords, JWT keys, API keys) | None committed; `appsettings.Development.json` git-ignored | FAIL | `git grep -nIiE "(password\|secret\|apikey\|signingkey)…"` → docs/backend/README.md:276 `MSSQL_SA_PASSWORD='Zaypos!Dev2026'`; `git check-ignore -v …appsettings.Development.json` → ignored | BUG-11 (Low): real dev SA password; container listens on 0.0.0.0:1433. No JWT/R2 keys committed (AWS keys in SigV4PresignerTests are AWS doc examples) |
| TC-SEC-05 | P2 | Auto | `/auth/*` rate limits by phone and IP | Limits as in README §4; different phones on one IP not blocked together | PASS | b/ZayPOS.Api.Tests/AuthTests.cs::Auth_endpoints_are_rate_limited_per_client_ip; ::Otp_login_and_pin_reset_are_also_limited_per_normalized_phone; ::Otp_is_limited_to_three_per_phone_per_hour | |
| TC-SEC-06 | P2 | Auto | Release builds: Android manifest + iOS Info.plist | INTERNET present; no cleartext HTTP in release; sample data seeding impossible | PASS | `grep INTERNET android/app/src/main/AndroidManifest.xml` (present); cleartext only in `src/debug/res/xml/network_security_config.xml`; `grep NSAllows ios/Runner/Info.plist` (none; Debug-only build script); m/auth_controller_test.dart::sample data is impossible in release builds (4 tests) | Note: release default `API_BASE_URL` is `http://localhost:5076` — a release build must pass an https URL |

## 12. Language, layout & robustness (UX)

| ID | Pri | Type | Steps | Expected | QA result | QA evidence | Owner result |
|---|---|---|---|---|---|---|---|
| TC-UX-01 | P1 | Manual | Airplane mode, first launch after install | Myanmar text renders correctly (bundled fonts) | MANUAL | — | Owner: delete app, airplane mode ON, install + open; check Login/Register text. Note: `google_fonts` is a dependency — confirm nothing is fetched |
| TC-UX-02 | P1 | Auto | Search all user-facing strings | No English left in Burmese screens except brand/payment names; no broken Unicode | FAIL | m/qa/qa_ux_test.dart::TC-UX-02 … (2 tests) | BUG-9 (Low): AM/PM times, "Report" tab, Settings descriptions. No broken Unicode found |
| TC-UX-03 | P2 | Manual | Small phone (iPhone SE / small Android), largest system font | No overflow; buttons ≥ 44 px | MANUAL | — | Owner; widget tests already overflow at 320 px (BUG-8) |
| TC-UX-04 | P2 | Auto | Widget tests for every screen at 320 px width | No RenderFlex overflow | FAIL | m/qa/qa_ux_test.dart::TC-UX-04 … (32 tests, 4 fail) | BUG-8: Customers filter chips +12 px (/customers, /customers/new, customer detail); fashion Add Product variants +11 px |
| TC-UX-05 | P2 | Manual | Kill the app during checkout | After reopen: either the full sale exists or nothing (never half) | MANUAL | (m/drift_repositories_test.dart::a failing checkout leaves no sale… proves atomicity) | Owner |
| TC-UX-06 | P3 | Manual | 1 hour of normal use | No crash; battery/heat acceptable | MANUAL | — | Owner |
