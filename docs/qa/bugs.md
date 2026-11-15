# ZayPOS — QA bug list

Filed by the `qa-engineer` agent and the owner. Newest at the bottom.

Format:

```
## BUG-<n> · <test case id> · <Critical|High|Medium|Low> · <short title>
- Found in: round <n> · <device / test file>
- Steps to reproduce:
- Expected:
- Actual:
- Suspected area: (file / function — no fix)
- Blocks beta: yes / no
- Status: open | fixed in <commit> | verified by QA | verified by owner
```

---

## BUG-1 · TC-PROD-NEW-1 · High · A product cannot be edited after it is saved (price, cost, name, unit, low-alert)
- Found in: round 1 · `mobile/test/qa/qa_app_flows_test.dart` › "TC-PROD-NEW-1 an existing product can be edited (price / cost / name)"
- Steps to reproduce: Products → search "ရေသန့် 1L" → long-press the row, then tap it.
- Expected: an edit form (with "ရောင်းဈေး (Ks)") opens; a new price/cost or a corrected name can be saved (one `upsertProduct` unit).
- Actual: tap only opens "Stock ဖြည့်မယ်"; there is no edit or delete route. Test output:
  `Expected: exactly one matching candidate / Actual: _TextWidgetFinder:<Found 0 widgets with text "ရောင်းဈေး (Ks)": []>`.
  The only price write is `ProductService.setPrice`, reachable only for products whose price is 0 (POS). Consequences: price
  changes (frequent with inflation) and typos cannot be fixed; TC-SYNC-06 cannot be run by the owner; TC-RPT-02 had to change
  the cost at database level.
- Suspected area: `mobile/lib/core/router/app_router.dart` (no `/products/:id` route), `products_screen.dart` `_ProductRow.onRestock`,
  `ProductService` (create / setPrice / importAll only).
- Blocks beta: **yes**
- Status: fixed in 395451f (branch fix/qa-round-1) — tap a product opens the Add Product form in edit mode; the stock badge opens "Stock ဖြည့်မယ်". Awaiting QA verification.
- QA round 2: **verified by QA**. `m/qa/qa_app_flows_test.dart::TC-PROD-NEW-1` PASS; `m/qa/qa_round2_ui_test.dart::TC-PROD-NEW-3 …` 8/8 PASS
  (all 7 templates: prefilled, title "ပစ္စည်း ပြင်မယ်", no stock/IMEI/batch/variant inputs, one upsertProduct, createdAt / warranty /
  expiry-alert / unit / stock / module rows kept; preset with price 0 refused until priced); `TC-PROD-NEW-4` 2/2 (badge = restock,
  row = edit); `b/…/QaRound2Tests.cs::TC_PROD_NEW_3_…` PASS; live `m/qa/live_qa_round2_test.dart` (B pulls A's edit) PASS.
  Side effect found: goods received later for IMEI / batch / variant products → BUG-12.

## BUG-2 · TC-POS-NEW-2 · High · POS never records which IMEI, size/colour variant or batch was sold
- Found in: round 1 · `mobile/test/qa/qa_modules_test.dart` › "TC-POS-NEW-2 …" (phone, fashion, pharmacy — 3 tests)
- Steps to reproduce: phone template → Add product "QA Galaxy A15" with 2 IMEIs → POS → ပစ္စည်းများ → tap it → ငွေရှင်းမယ် →
  အတည်ပြုပြီး ပြေစာထုတ်မယ်. Same with a fashion product (variant M · အနက် stock 3) and a pharmacy product (batch B1, 40).
- Expected: the app asks which IMEI / size-colour / batch (or picks one); the sale line carries `serialId` / `variantId` /
  `batchId`; that IMEI becomes `sold`, that variant's / batch's stock drops.
- Actual: `Expected: not null / Actual: <null>` for `line.serialId`, `line.variantId`, `line.batchId`. Both IMEIs stay `inStock`
  while product stock drops to 1; variant and batch stock never decrease, so expiry/batch and size stock are wrong after the
  first sale. `serialDoubleSold` (TC-SYNC-08) can only happen through the service API, never from the UI.
- Suspected area: `mobile/lib/features/pos/domain/cart.dart` (`CartLine` has no serial/variant/batch; `toDrafts` sends null),
  `pos_screen.dart` `_addProduct`.
- Blocks beta: **yes** for phone, fashion and pharmacy shops; no for a grocery-only beta.
- Status: fixed in 41818b3 (branch fix/qa-round-1) — POS asks which IMEI / size·colour / batch (only batch with stock is auto-picked, FEFO order). Awaiting QA verification.
- QA round 2: **verified by QA** for the sale itself. `m/qa/qa_modules_test.dart::TC-POS-NEW-2 …` 3/3 PASS;
  `m/qa/qa_round2_ui_test.dart::TC-POS-NEW-4 …` 3/3 PASS (picked non-first variant L·အဖြူ drops, M·အနက် unchanged; batches EARLY27 <
  LATE28 < NODATE, empty batch hidden, picked batch drops; sold IMEI not offered again, IMEI → sold with its sale line);
  `m/qa/qa_round2_drift_test.dart::TC-POS-NEW-4 Drift …` PASS (Drift: serial sold, variant/batch stock, checkout unit carries
  serialId/variantId/batchId + productSerials row; void returns them). Live `m/live_sync_test.dart` (serialDoubleSold) PASS.
  Remaining gap filed separately: BUG-12 (stock received later cannot be given IMEIs / batch / variant). Note for the owner:
  an expired batch is offered first (FEFO) and auto-picked if it is the only one with stock, without an "expired" mark.

## BUG-3 · TC-POS-NEW-1 · High · Hardware shop (decimal quantity on) cannot sell 2.5 of anything
- Found in: round 1 · `mobile/test/qa/qa_pos_ui_test.dart` › "TC-POS-NEW-1 hardware (decimalQty on): the cashier can sell 2.5 of a product"
- Steps to reproduce: hardware template → POS → add a product → ငွေရှင်းမယ် → try to set the quantity to 2.5.
- Expected: a quantity entry that accepts decimals when `TenantFeatures.decimalQty` is on (Settings promises "2.5 ပေ · 0.75 ကီလို").
- Actual: only whole-unit −/+ steppers (`CartNotifier.step = 1000`); tapping the quantity opens nothing. Test output
  `Expected: true / Actual: <false>`. The restock sheet ("Stock ဖြည့်မယ်") is whole units too. The money math itself is right
  (TC-POS-10 PASS).
- Suspected area: `checkout_screen.dart` `_LineRow`, `cart.dart` `setQty` callers, `restock_sheet.dart`.
- Blocks beta: **yes** for hardware shops; no otherwise.
- Status: fixed in f8bec92 (branch fix/qa-round-1) — tap the checkout quantity to type it (decimal keypad when decimalQty is on); restock accepts decimals too. Awaiting QA verification.
- QA round 2: **verified by QA**. `m/qa/qa_pos_ui_test.dart::TC-POS-NEW-1` PASS; `m/qa/qa_round2_ui_test.dart::TC-POS-NEW-3 …` 2/2 PASS
  (hardware: "." key, 4th decimal ignored → 0.123, 2.5 → line 1,500, sale line 2,500 milli, stock −2,500; grocery: no "." key, 3 → 3,
  0 cannot be confirmed); `TC-PROD-NEW-4 hardware: 2.5 ပေ received → +2,500 milli` PASS.

## BUG-4 · TC-DEBT-NEW-2 · Medium · Double-tap on "… Ks လက်ခံမယ်" records the debt payment twice
- Found in: round 1 · `mobile/test/qa/qa_pos_ui_test.dart` › "TC-DEBT-NEW-2 double-tap … records ONE payment"
- Steps to reproduce: Customers → ဦးအောင်ကျော် (52,000) → ငွေပြန်ဆပ်မယ် → 20,000 → tap "20,000 Ks လက်ခံမယ်" twice ~100 ms apart
  while the write takes ~150 ms (busy / low-end phone).
- Expected: one payment, balance 32,000 (Checkout has this guard and passes TC-POS-07).
- Actual: two payment entries (`Expected: <3> / Actual: <4>` payment rows), balance reduced twice. There is no UI to delete
  or adjust a ledger entry, so the owner cannot correct it.
- Suspected area: `mobile/lib/features/customers/presentation/pay_debt_sheet.dart` `_confirm` (button stays enabled during the await).
- Blocks beta: no — but money-affecting and cheap to fix; strongly recommended before beta.
- Status: fixed in da97794 (branch fix/qa-round-1) — double-submit guard; a wrong payment is corrected by a reversal entry (tap the payment in the customer history), never deleted. Awaiting QA verification.
- QA round 2: **verified by QA**. `m/qa/qa_pos_ui_test.dart::TC-DEBT-NEW-2` PASS (one payment, 32,000);
  `m/qa/qa_round2_ui_test.dart::TC-DEBT-NEW-3 …` PASS (cancel = nothing; confirm = one payDebt unit, +7,350 adjustment with the derived
  id, payment kept and "ပြန်ပယ်ပြီး", no second reversal); two phones offline: `b/…/QaRound2Tests.cs::TC_DEBT_NEW_4_…` PASS (server keeps
  one reversal, B's unit not rejected, balance once), `m/qa/qa_round2_drift_test.dart::TC-DEBT-NEW-4 …` PASS, live
  `m/qa/live_qa_round2_test.dart` PASS (both phones: one reversal, 52,000, outbox empty).

## BUG-5 · TC-SYNC-NEW-1 · Medium · A phone whose clock is ahead never shows later edits made on other phones
- Found in: round 1 · `mobile/test/qa/qa_sync_test.dart` › "TC-SYNC-NEW-1 …" (server half: `backend/tests/ZayPOS.QA.Tests/QaSyncSecurityTests.cs` › `TC_SYNC_NEW_1_server_takes_a_later_edit_over_a_clamped_future_edit` PASS)
- Steps to reproduce: phone A with its clock 1 h ahead renames a product and syncs (server clamps to T+5 min, `clockSkew`).
  10 minutes later phone B (correct clock) renames it again and syncs (server takes B: T+10 > T+5). Phone A syncs.
- Expected: A shows B's name like the server and B (TC-SYNC-06: "later edit wins on both devices").
- Actual: `Expected: 'B (later, correct clock)' / Actual: 'A (clock +1h)'`. A keeps its local `updatedAt` = T+60 and rejects every
  pulled row older than that (phase3 §5.3), so A diverges from the server for up to the size of the skew. Wrong phone clocks /
  time zones are common.
- Suspected area: design gap between README §3.3 (server clamps) and phase3 §5.3 (phone compares with its unclamped local
  `updatedAt`); `mobile/lib/core/sync/sync_store.dart` `_takes`, and the applied-unit path in `applyResults` (the clamped
  server time is never written back locally).
- Blocks beta: no
- Status: fixed in be0a75f (branch fix/qa-round-1) — after an applied push the phone clamps its own LWW rows to serverTime + 5 min, like the server. Awaiting QA verification.
- QA round 2: **verified by QA**. The round-1 app test now passes, but only through the fallback (its engine clock is real time);
  the realistic case was added: `m/qa/qa_round2_drift_test.dart::TC-SYNC-NEW-2 phone clock +1 h …` PASS (engine clock +1 h,
  serverTime from the answer; customer and product clamped to serverTime + 5 min; B's later edits taken) and `… the real push client
  reads "serverTime" …` PASS; server: `b/…/QaRound2Tests.cs::TC_SYNC_NEW_2_push_answer_carries_the_server_clock_in_utc` PASS
  (`serverTime` ends in "Z", equals the server clock). Limitation (not a bug with the current server): with no serverTime in the answer
  the fallback is the phone's own clock, which does nothing for a phone that is ahead.

## BUG-6 · TC-PROD-NEW-2 · Medium · Register step 3 promises presets the server does not have
- Found in: round 1 · `mobile/test/qa/qa_app_flows_test.dart` › "TC-PROD-NEW-2 register step 3 (…)" (4 tests)
- Steps to reproduce: Register → step 2 choose ကုန်စုံ / ဆေးဆိုင် / ဖုန်း / Hardware → step 3.
- Expected: only the presets `GET /catalog/presets` really serves (grocery: 20, no barcodes; others: 0 — backend
  `AccountTests.Presets_default_to_the_shops_template…`).
- Actual: grocery "အများဆုံးရောင်းတဲ့ ပစ္စည်း 300 မျိုး barcode နဲ့တကွ…"; pharmacy 250, phone 120, hardware 200 — and the preset
  option is pre-selected, so these shops finish registration with an empty product list. Add Product also shows
  "ကြိုတင်စာရင်း (300) ထဲက ရှာမယ်", a button that does nothing.
- Suspected area: `mobile/lib/core/features/shop_template.dart` `presetCount`; `register_screen.dart` `_StepCatalog`, `_defaultStart`;
  `add_product_screen.dart` preset button.
- Blocks beta: no
- Status: fixed in 056ef3e (branch fix/qa-round-1) — step 3 promises only the server presets (grocery 20, no barcodes); option hidden for templates without presets; dead Add Product preset button removed. Awaiting QA verification.
- QA round 2: **verified by QA**. `m/qa/qa_app_flows_test.dart::TC-PROD-NEW-2 …` 4/4 PASS; `grep -rn "barcode နဲ့\|ထဲက ရှာမယ်" mobile/lib`
  → no match; `_defaultStart` falls back to Quick Sale when presetCount is 0; Settings shows "မရှိသေးပါ" for 0-preset templates.

## BUG-7 · TC-DEBT-NEW-1 · Medium · No credit-limit warning at sale time, although Add Customer promises one
- Found in: round 1 · `mobile/test/qa/qa_pos_ui_test.dart` › "TC-DEBT-NEW-1 credit sale over the customer limit: checkout warns …"
- Steps to reproduce: customer ဦးသန်းထွန်း owes 96,000, limit 100,000 → POS 24,000 → ငွေရှင်းမယ် → အကြွေး → pick him.
- Expected: a warning that 120,000 exceeds the limit (Add Customer helper: "ဒီထက်ကျော်ရင် ရောင်းတဲ့အချိန် သတိပေးပါမယ်").
- Actual: only "ယခင်အကြွေး 96,000 Ks"; no warning (`Found 0 widgets with text containing ကန့်သတ်`). The owner learns about it
  only after sync, in "စစ်ရန်" (TC-DEBT-05 PASS).
- Suspected area: `checkout_screen.dart` (customer card / `_blockReason`), `customer.creditLimit` unused in the app.
- Blocks beta: no
- Status: fixed in fa42620 (branch fix/qa-round-1) — checkout warns (does not block) when balance + sale > credit limit. Awaiting QA verification.
- QA round 2: **verified by QA**. `m/qa/qa_pos_ui_test.dart::TC-DEBT-NEW-1` PASS; `m/qa/qa_round2_ui_test.dart::TC-DEBT-NEW-5 …` 3/3 PASS
  (exactly at the limit / no limit: no warning; 1 Ks over: warning names 119,999 and 120,000; the credit sale is still saved).

## BUG-8 · TC-UX-04 · Low · RenderFlex overflow at 320 px width
- Found in: round 1 · `mobile/test/qa/qa_ux_test.dart` › "TC-UX-04 … signed in /customers", "/customers/new", "/customers/<id>",
  "add product, fashion template, scrolled to the end"
- Steps to reproduce: 320×568 logical screen (iPhone SE 1st gen / small Android); open Customers; or Add Product with the fashion template.
- Expected: no overflow.
- Actual: `A RenderFlex overflowed by 12 pixels on the right.` — creator `Row ← FilterChips<_Tab>` (common.dart:216) on the
  Customers screen; `…overflowed by 11 pixels…` in the fashion variants section.
- Suspected area: `mobile/lib/core/widgets/common.dart` `FilterChips` (non-scrollable row) as used by `customers_screen.dart`;
  `products/presentation/sections/feature_sections.dart` `VariantsSection`.
- Blocks beta: no
- Status (rounds 1–6): open (partly: the fashion Add Product overflow was the margin row, fixed in 056ef3e; the Customers filter chips still overflow) — see round 7 below
- QA round 2: confirmed partly fixed. `m/qa/qa_ux_test.dart::TC-UX-04 … add product, fashion template, scrolled to the end` PASS;
  `… /customers`, `… /customers/new`, `… /customers/<id>` still FAIL. Stays open (Low).
- QA round 7 (beta-polish @ 00bcea9, fix 4e3d57a): **verified by QA.** `m/qa/qa_ux_test.dart::TC-UX-04 …` 32/32 PASS (incl. the three
  Customers routes); developer `m/narrow_screen_test.dart` read and run (chips row scrolls, last chip reachable). Every `FilterChips`
  use is now `scrollable: true` (customers, products, sales history, POS). Owner still checks the largest system font (TC-UX-03).
- Status: verified by QA (round 7)

## BUG-9 · TC-UX-02 · Low · English left on Burmese screens
- Found in: round 1 · `mobile/test/qa/qa_ux_test.dart` › "TC-UX-02 …" (2 tests)
- Steps to reproduce: open every screen.
- Expected: no English except brand/payment names (and the loanwords the spec itself uses: Stock, Sync, Quick Sale, PIN, IMEI, Barcode…).
- Actual: times as "3:42 PM" / "10:12 AM" (dashboard, history, sale detail, receipt, customer history); bottom tab "Report";
  Settings/Register descriptions "ရောင်းခြင်း (POS)", "နေ့စဉ် Report", "ဖုန်း၊ Electronics", "Size / အရောင်", "Quotation",
  "ဝန်ဆောင်မှု item", "Order mode", "Hardware / ဆောက်လုပ်ရေး", "service", "Core feature". No broken Unicode found.
- Suspected area: time formatting in `core/utils/myanmar.dart` / `sale_ui.dart`; `app_bottom_nav.dart`; `settings_features_screen.dart`; `shop_template.dart`.
- Blocks beta: no
- Status: open (partly fixed in 00bcea9 — re-opened by QA round 7 for the rest)
- QA round 7 (beta-polish @ 00bcea9):
  - Fixed and verified: times (`m/qa/qa_round7_ux_test.dart::TC-UX-NEW-2 …` PASS — 00:05 "နံနက် 12:05", 12:00 "နေ့လယ် 12:00",
    16:00 "ညနေ 4:00", 19:00 "ည 7:00", 23:59 "ည 11:59", receipt "၁၀ နိုဝင်ဘာ ၂၀၂၆ · ညနေ 4:05"); "အစီရင်ခံစာ" tab; template, Register,
    login and Settings module texts; signed-out screens (`TC-UX-02 signed-out screens` PASS).
  - TC-FEAT-04 / TC-UX-02 contradiction resolved on the QA side: `m/qa/qa_app_flows_test.dart::TC-FEAT-02 … TC-FEAT-04 restaurant
    disabled` now finds the v2 switch by its description "စားသောက်ဆိုင်၊ ကော်ဖီဆိုင်" (title only has to start with "စားပွဲ"); same
    assertions (disabled, off, a tap changes nothing), PASS. The developer may now translate the title.
  - Still English — for the developer:
    1. Settings → "စားပွဲ / Order mode" (`settings_features_screen.dart:111`) — `TC-UX-02 …` signed-in: `Expected: empty, Actual:
       {'/settings/features': ['"စားပွဲ / Order mode" (English: order, mode)']}`.
    2. Found by the wider scan `m/qa/qa_round7_ux_test.dart::TC-UX-NEW-1 …` (sheets and template forms that the round-1 route walk never
       opened; the original report already listed "Size / အရောင်"):
       - "Size" — fashion Add Product "Size နှင့် အရောင်" / "Size" (`feature_sections.dart:373` and the size field), edit form
         "Size / အရောင်", "+ Size / အရောင် ထည့်မယ်", "Size အသစ်", errors "Size နဲ့ အရောင် ထည့်ပါ။", "ဒီ Size / အရောင် ရှိပြီးသားပါ။"
         (`edit_module_sections.dart:132–305`), restock sheet "… ဘယ် Size / အရောင် ဝင်လာလဲ" (`restock_sheet.dart:278`), POS sheet
         "ဘယ် Size / အရောင် လဲ?" (`module_pick_sheet.dart:78`). Settings already says "အရွယ်အစား / အရောင်".
       - Settings: "ရိုးရှင်း mode", "စာလုံးကြီး၊ ခလုတ်ကြီး၊ menu နည်းနည်း", "Feature ပိတ်လိုက်ရင်လည်း … data တွေ မပျက်ပါ။" (lines 211–221).
       - Also seen in source (not on a scanned screen): camera error "… Settings မှာ ကင်မရာ ခွင့်ပြုပါ။" (`barcode_scanner.dart:82`),
         "Contacts ထဲက ရွေးရန်", sync texts "data" / "update" / "Copy … paste", "(FEFO)". Owner may allow some as loanwords; then QA
         adds them to the allow-list.
  - The new scan / photo sheets are clean ("Barcode" / "Scan" / "IMEI" are allowed loanwords).
- Owner decision 2026-11-14: allowed English = KBZPay, WavePay, Viber, Excel, IMEI, Barcode, PIN, OTP, Stock, Sync (plus the brand, Ks /
  units and phone placeholders, which are not words). Everything else translated: Size→ဆိုဒ်, menu→မီနူး, data→ဒေတာ, Order mode→အော်ဒါ
  ပုံစံ, ရိုးရှင်း mode→ရိုးရှင်းသော ပုံစံ (owner's words); developer's choices for the rest — Batch→အသုတ်, Serial→စီးရီးနံပါတ်,
  Server→ဆာဗာ, App→အက်ပ်, Support→အကူအညီဌာန, Demo→စမ်းသပ်, Offline→လိုင်းမရှိ, SMS ကုဒ်→OTP ကုဒ်, feature→လုပ်ဆောင်ချက်,
  template→ဆိုင်ပုံစံ, Quick Sale→အမြန်ရောင်း, scan→ဖတ်မယ် / စကင်ဖတ်, Contacts→ဖုန်းစာအုပ်, screenshot→ငွေလွှဲပြေစာ ပုံ.
- Status: fixed in fb520d9 — QA allow-lists (TC-UX-02, TC-UX-NEW-1) narrowed to the owner's list; new `m/no_english_test.dart` checks
  every Burmese string literal under `lib/`. Owner to read the developer's word choices.
- Owner decision 2026-11-14 (after round 8): **"Batch" is allowed** (printed on medicine boxes) — အသုတ် reverted to Batch in 7eb11f9;
  "batch" added to every allow-list (QA's three and `m/no_english_test.dart`).
- QA round 8 (beta-polish @ 54e9146): **verified by QA** for the app's own texts. `m/qa/qa_ux_test.dart::TC-UX-02 …` (signed-in and
  signed-out) and `m/qa/qa_round7_ux_test.dart::TC-UX-NEW-1 …` PASS with the owner's allow-list; new `m/qa/qa_round8_ux_test.dart::TC-UX-NEW-4 …`
  PASS (duplicate-barcode dialog, POS picker, IMEI snackbar, /settings/devices, products without a price). QA accepts the developer's
  edits to the QA allow-lists (they are the owner's list exactly, plus brand / Ks / units / phone placeholders / size values, i.e.
  stricter than round 7) and the mechanical text renames in the other QA finders (only expected strings changed, no assertion removed or
  weakened). Not covered by `m/no_english_test.dart`: literals without a Burmese letter and texts built at runtime — the remaining
  English found that way comes from the server and raw keys → **BUG-26** (new, Low), not a re-open of BUG-9.
- Status: verified by QA (round 8)

## BUG-10 · TC-FEAT-NEW-1 · Low · The v2 restaurant template can be picked at registration
- Found in: round 1 · `mobile/test/qa/qa_app_flows_test.dart` › "TC-FEAT-NEW-1 register step 2: the v2 restaurant template cannot be chosen"
- Steps to reproduce: Register → step 2 → tap "စားသောက် / ကော်ဖီ" (badge v2) → ဆက်သွားမယ်.
- Expected: not selectable (Settings disables it, TC-FEAT-04).
- Actual: step 3 shows "စားသောက် / ကော်ဖီ အတွက်"; a shop with every feature off can be created.
- Suspected area: `register_screen.dart` `_StepShopType._typeCard` (`onTap` ignores `t.soon`).
- Blocks beta: no
- Status: verified by QA (round 7) — fixed in b9b2b5e. `m/qa/qa_app_flows_test.dart::TC-FEAT-NEW-1 …` PASS (card dimmed, tap does
  nothing, step 3 not reached); developer `m/register_template_test.dart` read and run, PASS.

## BUG-11 · TC-SEC-04 · Low · Dev SQL Server SA password committed — accepted risk (dev only, port bound to 127.0.0.1)
- Found in: round 1 · `git grep`
- Steps to reproduce: `git grep -n "MSSQL_SA_PASSWORD"`
- Expected: no passwords in the repository.
- Actual: `docs/backend/README.md:276: … -e MSSQL_SA_PASSWORD='<redacted in round 2>' -p 1433:1433 …` — the same password the local
  `zaypos-sql` container uses, and that container publishes 1433 on all interfaces (`0.0.0.0:1433`), so anyone on the same
  Wi-Fi can log in as `sa`. `appsettings.Development.json` is correctly git-ignored; no JWT/R2 secrets are committed.
- Suspected area: `docs/backend/README.md` §6 (use a placeholder; bind `-p 127.0.0.1:1433:1433`; rotate the local password).
- Blocks beta: no
- Status: fixed in 167a858 (branch fix/qa-round-1) — docs bind SQL to 127.0.0.1; the SA password stays only in docs/backend/README.md as a labelled dev-only example. The running local `zaypos-sql` container still listens on 0.0.0.0 until it is recreated (README §6). Awaiting QA verification.
- QA round 2: **reopened** (docs part fixed, the risk is not). Evidence (2026-11-14):
  `git grep -n MSSQL_SA_PASSWORD` → `docs/backend/README.md:279` still holds a real value, and it is **the running container's
  password** (`docker inspect zaypos-sql` env compared with the README value → 1 match); `docker ps` → `0.0.0.0:1433->1433/tcp`;
  `nc -z <Mac Wi-Fi IP> 1433` → "succeeded" — so `sa` with a password published in git is reachable from the shop/home Wi-Fi now.
  The expected result ("no passwords in the repository") is not met. `appsettings.Development.example.json` already shows the right
  pattern (`<your-local-sa-password>`). Owner action (QA did not touch the container): recreate `zaypos-sql` on `127.0.0.1:1433`
  with a new password (README §6), and keep only a placeholder in the README. The old value stays in git history, so rotating it
  is the real fix. Also redacted from `docs/qa/bugs.md` and `docs/qa/test-cases.md` (QA's own round-1 text quoted it).
  Blocks beta: no (dev machine only).
- Status (developer): fixed in 177dcf0 — README uses `<YOUR_DEV_SA_PASSWORD>` and says where to set it (appsettings.Development.json /
  user-secrets) and to rotate a password that was ever committed.
- QA round 3: **repository part verified by QA; bug stays open until the owner rotates the password.** Evidence (no secret printed):
  `git grep -n MSSQL_SA_PASSWORD HEAD` → README:278 is the placeholder; `git grep -F -c <old value> HEAD` → 0 files;
  `git log --all -S<old value>` → 4 commits (history); `docker inspect zaypos-sql` env still contains the old committed value
  (match 1) and so does the local `appsettings.Development.json`; `docker port zaypos-sql` → `1433/tcp -> 0.0.0.0:1433` and `[::]:1433`;
  `nc -z <Mac Wi-Fi IP> 1433` → "succeeded". The container was not stopped or changed by QA. Close when `docker ps` shows
  `127.0.0.1:1433->1433/tcp` and the container's password differs from the one in history.
- QA round 4: unchanged, stays open (owner). `docker port zaypos-sql` → `0.0.0.0:1433`, `[::]:1433`; container env and local
  `appsettings.Development.json` still match the value in history (1 / 1, value not printed); `nc -z <Wi-Fi IP> 1433` → reachable.
- QA round 5: **partly fixed, stays open (owner: rotate the password).** Evidence 2026-11-14 (no secret printed, container not stopped or
  changed): container recreated 2026-11-14T08:06Z; `docker port zaypos-sql` → `1433/tcp -> 127.0.0.1:1433` only; `nc -z <Wi-Fi IP> 1433` →
  NOT reachable (loopback reachable) — the Wi-Fi exposure is gone. `git check-ignore -v backend/src/ZayPOS.Api/appsettings.Development.json`
  → ignored (backend/.gitignore:8), `git ls-files --error-unmatch` → untracked; `git grep -F -l <old> HEAD` → 0 files. BUT the password was
  NOT changed: the old value (from commit 9ee93e3 of docs/backend/README.md; `git log --all -S<old>` → 4 commits) is equal to the
  container's `MSSQL_SA_PASSWORD` (string compare → equal) and is found in `appsettings.Development.json` (`grep -F -c` → 1), and
  `sqlcmd -U sa` with the old value **logs in** (`SELECT 'login-…-OK'` returned, databases listed). Close when the sa password differs from
  the one in git history (container env / `ALTER LOGIN sa`, and appsettings.Development.json). Severity stays Low (dev machine, loopback only now).
- **Status (owner, 2026-11-14): accepted risk (dev only, port bound to 127.0.0.1).** The dev SA password is still the one in git
  history; the owner will change it later. Not a beta blocker: the container is reachable only from the Mac itself
  (`127.0.0.1:1433`), no other device on the Wi-Fi can reach it, and no production / shared server uses this password.
- Round 6 (QA): treated as accepted risk (not open for the exit rule). Binding re-confirmed without touching the container:
  `docker port zaypos-sql` → `1433/tcp -> 127.0.0.1:1433`; `nc -z <Wi-Fi IP> 1433` → not reachable; `nc -z 127.0.0.1 1433` → reachable.

## BUG-12 · TC-PROD-NEW-5 · High · Goods received for an IMEI / batch / size-colour product cannot be entered as IMEIs / a batch / a variant
- Found in: round 2 · `mobile/test/qa/qa_round2_ui_test.dart` › "TC-PROD-NEW-5 …" (phone, pharmacy, fashion — 3 tests)
- Steps to reproduce:
  1. Phone template: add "QA Redmi 13" with one IMEI → sell it → Products → tap the stock badge → "Stock ဖြည့်မယ်" 1 → POS → tap it.
  2. Pharmacy template: product with batch B1 (2) → stock badge → 10.
  3. Fashion template: product with variant 30 · အပြာ (1) → stock badge → 3.
- Expected: when goods arrive for a module product the owner enters the new IMEIs / the batch number + expiry / the size-colour
  (the edit form itself says IMEIs, variants and batches "are received through 'Stock ဖြည့်မယ်'", `AddProductScreen` doc and helper
  text), so POS can sell them and IMEI / batch / variant stock equals product stock.
- Actual: the sheet is a bare quantity; `StockService.restock` is called without `variantId` / `batchId` and no serial is created.
  1. Phone: `Expected: (true, false) / Actual: (false, true)` — no IMEI asked, and POS then shows "ရောင်းစရာ IMEI မကျန်တော့ပါ"
     and adds nothing, although stock says 1 phone on hand. After the first delivery the shop cannot sell restocked phones at all;
     the edit form hides IMEIs, so there is no other way to add them (only a new product).
  2. Pharmacy: `Expected: not null / Actual: <null>` for the received movement's `batchId` — the 10 have no batch / expiry; B1 = 2 but
     product stock = 12; once B1 is empty POS offers only B1 ("ကျန် 0") and the sale drives B1 negative.
  3. Fashion: `Expected: not null / Actual: <null>` for `variantId` — POS asks for a variant whose stock never grows.
- Suspected area: `mobile/lib/features/products/presentation/products_screen.dart` `_restock`;
  `mobile/lib/features/inventory/presentation/restock_sheet.dart` (quantity only); `StockService.restock` callers; no UI path to add a
  `ProductSerial` / `ProductBatch` / `ProductVariant` to a saved product (`add_product_screen.dart` edit mode hides them).
- Blocks beta: **yes** for phone, pharmacy and fashion shops (first restock breaks selling / expiry); no for grocery and hardware.
- Status: fixed in e911ee9 (branch fix/qa-round-1) — restock sheet per module type (IMEI list / batch chips or new batch + expiry /
  variant chips), StockService.receive() = one restock unit; edit form lists and adds IMEIs / batches / variants.
- QA round 3: **verified by QA.** The 3 round-2 tests now pass (`m/qa/qa_round2_ui_test.dart::TC-PROD-NEW-5 …` 3/3). Stronger r3 tests:
  `m/qa/qa_round3_ui_test.dart::TC-PROD-NEW-6 …` (2), `TC-PROD-NEW-7 …` (2 of 4), `TC-PROD-NEW-8 …` (1 of 2), `TC-PROD-NEW-9 …` (3 of 4)
  PASS — exact IMEIs offered at POS and sold, default batch = newest unexpired, new batch with the picked date sold first by FEFO,
  variant stock = product stock, edit form changes / deletes no existing row; `m/qa/qa_round3_drift_test.dart` (outbox carries only
  the new rows) PASS; server `b/…/QaRound3Tests.cs::TC_SYNC_NEW_3_…`, `TC_SYNC_NEW_4_…` PASS; live two phones
  `m/qa/live_qa_round3_test.dart` PASS. Gaps found in the new code are filed separately: BUG-15 (untracked first count, Medium),
  BUG-16 (duplicate batch no., Low), BUG-17 (typed IMEI lost in the edit form, Medium), BUG-18 (same IMEI on two phones, Low).

## BUG-13 · TC-POS-NEW-5 · High · An expired batch is offered first and auto-picked at POS, with no "expired" mark
- Found in: round 2 (noted, not filed) · `mobile/test/qa/qa_round2_ui_test.dart` TC-POS-NEW-4 review; filed in round 3 for traceability
- Steps to reproduce (on the round-2 code, 6164ce4): pharmacy, product whose only batch with stock expired yesterday → POS → tap it.
  Or two batches, the expired one first by FEFO.
- Expected: an expired medicine is never sold without the cashier knowing (no auto-pick; marked; explicit confirm).
- Actual (round 2): the only batch with stock is taken silently; in the sheet an expired batch is listed first (FEFO) with no mark.
- Suspected area: `mobile/lib/features/pos/presentation/module_pick_sheet.dart` `pickModuleUnit` (batch branch).
- Blocks beta: yes for pharmacy (round 2)
- Status: fixed in 79a18b3 (branch fix/qa-round-1) — `ProductBatch.isExpired`, only an unexpired batch auto-picked, expired listed last
  in red with "သက်တမ်းကုန်", confirm "သိပြီး ရောင်းမယ်".
- QA round 3: **verified by QA.** `m/qa/qa_round3_ui_test.dart::TC-POS-NEW-5 …` 3/3 PASS (expiry day itself auto-picked without
  confirm; yesterday not auto-picked, red + badge, barrier-dismiss = cancel, confirm sells and the line carries the batch; good batches
  before expired, badge only on the expired one); `m/qa/qa_round3_drift_test.dart::TC-POS-NEW-5 Drift …` PASS (today/yesterday correct
  after the Drift round trip, Mac on +06:30); `m/module_restock_test.dart::expired batches at POS` 3/3 PASS.

## BUG-14 · TC-PROD-NEW-10 · Low · Clearing "နည်းရင် သတိပေး" in the edit form kept the old value
- Found in: round 2 (noted, not filed) · TC-PROD-NEW-3 review; filed in round 3 for traceability
- Steps to reproduce (6164ce4): Products → tap a product with low alert 10 → clear "နည်းရင် သတိပေး" → သိမ်းမယ်.
- Expected: no alert (0); the product is no longer "Stock နည်း".
- Actual (round 2): the old value 10 was saved (`Qty.parse('') ?? editing.lowAlertMilli`); an alert could not be removed.
- Suspected area: `add_product_screen.dart` `_save` (edit branch).
- Blocks beta: no
- Status: fixed in 3c288d7 (branch fix/qa-round-1)
- QA round 3: **verified by QA.** `m/qa/qa_round3_ui_test.dart::TC-PROD-NEW-10 …` PASS (hardware 2.5 → 0, not low, empty on reopen,
  0.75 → 750); `m/module_restock_test.dart::edit form: clearing the low-stock alert …` PASS; wire `lowAlertMilli: 0`
  (`m/qa/qa_round3_drift_test.dart`), accepted by the server and pulled by phone B (`b/…/QaRound3Tests.cs::TC_SYNC_NEW_4_…`, live r3).

## BUG-15 · TC-PROD-NEW-11 · Medium · Batch / size-colour products: the first count of an untracked product is added to the earlier sales (shows 19, not 20)
- Found in: round 3 · `mobile/test/qa/qa_round3_ui_test.dart` › "TC-PROD-NEW-7 … TC-PROD-06 rule for a batch product …" and
  "TC-PROD-NEW-8 … TC-PROD-06 rule for a variant product …"
- Steps to reproduce: pharmacy template → add a product without stock ("Stock မမှတ်ရသေး") → sell 1 → Products → stock badge →
  "+ Batch အသစ်" FIRST → 20 → သိမ်းမယ်. Same with a fashion product with variant M·အဖြူ and no stock (pick M·အဖြူ → 20).
- Expected: 20 — TC-PROD-05/06 (P1): the first count of an untracked product is what was counted (the plain sheet does this with an
  adjustment of count − ledger and says "Stock မမှတ်ရသေးပါ။ လက်ရှိ ရှိနေတဲ့ အရေအတွက် ထည့်လိုက်ရင် စမှတ်ပါမယ်").
- Actual: `Expected: <20000> / Actual: <19000>` for both. The module sheet does not know the product is untracked and always writes a
  +20 restock. With Batch on, this is every product of a pharmacy (the batch sheet is used for all products, also those with no batch).
- Suspected area: `mobile/lib/features/products/presentation/products_screen.dart` `_restockModule` (ignores `p.isUntracked`),
  `StockService.receive` (restock only).
- Blocks beta: yes for pharmacy and fashion unless the shop enters opening stock when adding each product (workaround); no otherwise.
- Status: fixed in f3a7e0f (branch fix/qa-round-1) — first count of an untracked product = what was counted; earlier sales zeroed by
  "opening count" adjustments per (variant, batch); the unit is a stockAdjust.
- QA round 4: **verified by QA.** The 2 r3 tests pass; `m/qa/qa_round4_ui_test.dart::TC-PROD-NEW-11 (BUG-15) …` 3/3 PASS (expiry-tracked
  medicine, sold 1 without batch → new batch FIRST × 20: product 20, FIRST 20, 0 outside batches, one adjustment `(+1000, no batch,
  "opening count")`, ONE stockAdjust unit, tracked afterwards and the next delivery is a normal restock → 25; sale from an empty batch B0 →
  count into B0 → B0 20 = product; fashion M sold → count into L → M 0 / L 20 / product 20). Server: `b/…/QaRound4Tests.cs::TC_SYNC_NEW_6_…`
  PASS (stockAdjust with a new batch, and with new IMEIs, applied, no issue, B pulls it). Live `m/qa/live_qa_round4_test.dart` PASS (B shows 20, FIRST 20).

## BUG-16 · TC-PROD-NEW-12 · Low · "+ Batch အသစ်" in "Stock ဖြည့်မယ်" accepts the number of an existing batch
- Found in: round 3 · `mobile/test/qa/qa_round3_ui_test.dart` › "TC-PROD-NEW-7 … '+ Batch အသစ်' with the number of an existing batch is refused …"
- Steps to reproduce: pharmacy product with batch B1 → stock badge → "+ Batch အသစ်" → batch no. B1 → 5 → သိမ်းမယ်.
- Expected: refused like the edit form does ("ဒီ Batch ရှိပြီးသားပါ။"), or the goods go into the existing B1.
- Actual: `Expected: an object with length of <1> / Actual: … has length of <2>` — a second batch "B1"; POS and the edit form then
  show two identical "B1 · date" rows and the cashier cannot tell them apart.
- Suspected area: `mobile/lib/features/inventory/presentation/restock_sheet.dart` `_save` (batch branch only checks the text limit).
- Blocks beta: no
- Status: fixed in f3a7e0f (branch fix/qa-round-1)
- QA round 4: **verified by QA.** r3 test PASS; `m/qa/qa_round4_ui_test.dart::TC-PROD-NEW-12 (BUG-16) …` PASS ("B1" and " B1 " refused with
  "ဒီ Batch ရှိပြီးသားပါ။" in the sheet, no unit written, sheet stays open; "B2" then saves → B1 + B2, stock 7).

## BUG-17 · TC-PROD-NEW-13 · Medium · Edit form: an IMEI typed but not "+ ထည့်"-ed is silently dropped on save
- Found in: round 3 · `mobile/test/qa/qa_round3_ui_test.dart` › "TC-PROD-NEW-9 … an IMEI typed in the edit form but not '+ ထည့်'-ed …"
- Steps to reproduce: phone template → Products → tap an IMEI product → type a new IMEI in "IMEI အသစ်" (or scan it) → သိမ်းမယ်.
- Expected: the IMEI is saved (the "Stock ဖြည့်မယ်" sheet takes a typed IMEI on save) or the form warns; never silently lost.
- Actual: `Expected: true / Actual: <false>` — the form closes, no IMEI row, stock not +1, no message. The owner believes the phone
  is in stock; POS cannot sell it ("ရောင်းစရာ IMEI မကျန်တော့ပါ" if it was the only one). The same pattern applies to a typed batch
  no. / size-colour not added with their buttons (not separately tested).
- Suspected area: `mobile/lib/features/products/presentation/add_product_screen.dart` `_save` (edit branch) uses only
  `PendingModules`; `sections/edit_module_sections.dart` keeps the typed text in its own controllers.
- Blocks beta: no for most shops; for phone shops recommended before beta (workaround: always use "Stock ဖြည့်မယ်" to receive phones)
- Status: fixed in f3a7e0f (branch fix/qa-round-1) — save adds a typed IMEI / batch / size-colour, or is blocked with the message.
- QA round 4: **verified by QA** for the edit form. r3 test PASS; `m/qa/qa_round4_ui_test.dart::TC-PROD-NEW-13 (BUG-17) …` 3/3 PASS (typed IMEI
  saved in ONE upsertProduct, inStock, stock +1; typed batch no. created; size without colour blocks save with "Size နဲ့ အရောင် ထည့်ပါ။",
  nothing written); developer test `m/duplicate_serial_and_no_expiry_test.dart::edit form: … the typed refused IMEI blocks save` PASS.
  The same gap in **Add Product** (a new product) is not fixed → BUG-19.

## BUG-18 · TC-SYNC-NEW-5 · Low · The same IMEI received on two phones offline becomes two in-stock phones, nothing flagged (spec gap)
- Found in: round 3 · `backend/tests/ZayPOS.QA.Tests/QaRound3Tests.cs` › `TC_SYNC_NEW_5_two_phones_receiving_the_same_imei_offline_record_behaviour`
- Steps to reproduce: phones A and B of one shop, both offline; each receives IMEI 351111111111111 for the same product
  ("Stock ဖြည့်မယ်"); both sync.
- Expected: no spec line. By analogy with `duplicateBarcode` / `serialDoubleSold` (README §3.4) QA expects the duplicate to be visible
  in "စစ်ရန်" (units must still not be rejected — that part passes).
- Actual (recorded): `live rows with the IMEI = 2, stock = 2000, sync issues = 0, B outcome = Applied`. POS offers that IMEI twice
  and stock says 2 phones; nothing tells the owner. The index `IX_ProductSerials_Serial (TenantId, Serial)` is not unique, and the app's
  duplicate check only sees local rows.
- Suspected area: `backend/src/ZayPOS.Application/Sync/UnitApplier.cs` `ApplySerialsAsync`; README §3.4 (no issue kind).
- Blocks beta: no — owner to decide whether a `duplicateSerial` issue is wanted.
- Status: owner decided "flag it". Server fixed in 1ee4e61 (`duplicateSerial`, README §3.4), app in f3a7e0f (known IMEI refused on the
  phone; "စစ်ရန်" title).
- QA round 4: **verified by QA, end to end.** Server `b/…/QaRound4Tests.cs::TC_SYNC_NEW_5_…` PASS (A applied, no issue; B applied with
  `[DuplicateSerial]`; re-push not rejected and still ONE issue, entity = B's row; both phones pull it; resolve → B pulls resolvedAt);
  `TC_SYNC_NEW_7_…` PASS (same IMEI in another shop: no issue, nothing leaks); `TC_SYNC_NEW_8_…` PASS (new sold / deleted row: no issue;
  two twins in one unit: 2 issues, recorded). Live, real API on scratch DB `ZayPOS_QA_20261114_R4`: `m/qa/live_qa_round4_test.dart` PASS —
  two app instances (Drift + real sync engine) receive 357000000000009 offline via `StockService.receive`, sync A, B, A: both outboxes
  empty, ONE `duplicateSerial` in each phone's syncIssues (detail names the IMEI), both keep 2 in-stock rows, stock 3; resolved on A →
  B pulls it resolved. App: `m/duplicate_serial_and_no_expiry_test.dart` 5/5 PASS (restock / edit form / Add Product refuse a known IMEI;
  "စစ်ရန်" lists the pulled issue with 'IMEI / Serial တူ ဖုန်း နှစ်လုံး stock ထဲ ရှိနေ'); `m/qa/qa_round4_ui_test.dart::TC-PROD-NEW-14 …`
  PASS (an IMEI SOLD on another product is refused too). Owner question (not a bug): the app refuses any known IMEI, also a sold one, so a
  traded-in phone cannot be received under its IMEI; the server deliberately accepts that case.

## BUG-19 · TC-PROD-NEW-15 · Medium · Add Product: an IMEI typed but not "+"-ed is silently dropped (same gap as BUG-17, new-product form)
- Found in: round 4 · `mobile/test/qa/qa_round4_ui_test.dart` › "TC-PROD-NEW-15 … type an IMEI in Add Product and tap သိမ်းမယ် without Enter / '+' …"
- Steps to reproduce: phone template → Products → + → name "QA R4 new phone", price 450000 → type (or scan without Enter) IMEI
  351999999999991 in the IMEI field → သိမ်းမယ်.
- Expected: like the edit form (BUG-17 fix) and the restock sheet: the typed IMEI is saved (stock 1), or the save is blocked with a message.
- Actual: `Expected: true / Actual: <false>` — `product saved: true, IMEIs: 0, stock: 0`. The phone is saved as "Stock မမှတ်ရသေး" with no
  IMEI and no message; the owner believes the phone is recorded.
- Suspected area: `mobile/lib/features/products/presentation/add_product_screen.dart` `_save` (create branch uses only `_imeis`);
  `sections/feature_sections.dart` `SerialWarrantySection` keeps the typed text in its own `_imei` controller.
- Blocks beta: no — for phone shops recommended before beta (small); workaround: tap "+"/Enter and check the IMEI list before saving.
- Status: fixed in 2b74d73 (branch fix/qa-round-1) — save adds a typed IMEI; a refused one blocks the save with its message.
- QA round 5: **verified by QA.** `m/qa/qa_round4_ui_test.dart::TC-PROD-NEW-15 …` PASS (typed IMEI saved); `m/qa/qa_round5_ui_test.dart::
  TC-PROD-NEW-22 (BUG-19) …` 2/2 PASS (one Enter-ed + one typed → both inStock, stock 2, ONE upsertProduct; typed duplicate of a listed IMEI →
  save blocked with "ဒီ IMEI ထည့်ပြီးသားပါ။", nothing written, clearing it saves with 1); `m/qa/qa_round4_ui_test.dart::TC-PROD-NEW-14 … Add
  Product …` PASS (typed in-stock IMEI of another product blocks the save with "ဒီ IMEI ရှိပြီးသားပါ။").

## BUG-20 · TC-PROD-NEW-18 · Medium · A product without expiryAlertDays that has (old) batches is still sold by batch at POS
- Found in: round 4 · `mobile/test/qa/qa_round4_ui_test.dart` › "item 5 … TC-PROD-NEW-18 …" (2 tests)
- Steps to reproduce: pharmacy → a product that has batch S1 (0 left) and no expiryAlertDays (e.g. a soap first saved with the default
  "ရက် ၃၀ အလို" and a batch, then switched to "သက်တမ်း မမှတ်ပါ" in the edit form — the developer test shows switching keeps the batches),
  10 received with "Batch မပါ" → POS → tap it. Variant: S1 expired.
- Expected: owner decision (item 5): "products without expiryAlertDays sell and restock like plain products even when the Batch feature
  is on" — no batch sheet, sale line without batch.
- Actual: `sheet offered [ကျန် 0]; after selling it S1 = -1` — the only choice is the empty batch, which goes negative on every sale; with S1
  expired the cashier also gets the "သက်တမ်းကုန်နေပါပြီ" confirm on every sale of the soap (`(asked, confirm) = (true, true)`). This is the
  developer's stated interpretation ("a product without expiryAlertDays that already HAS batches still gets the batch picker"), which QA
  judges does not meet the decision. The reason given (QA's round-2/3 tests expect it) no longer holds: those fixtures are medicines and
  now set `expiryAlertDays: 30` (round 4), and they pass with either behaviour.
- Suspected area: `mobile/lib/features/pos/presentation/module_pick_sheet.dart` `pickModuleUnit` (batch branch ignores
  `p.expiryAlertDays`); `products_screen.dart` `_restockModule` default for such products (newest unexpired batch, not "Batch မပါ").
- Blocks beta: no for pharmacy if the shop is told: choose "သက်တမ်း မမှတ်ပါ" when ADDING a non-medicine, never give it a batch, and never
  switch a product that already has batches. Recommended before beta.
- Status: fixed in 2b74d73 (branch fix/qa-round-1) — no expiryAlertDays = plain product: POS never asks for a batch / expired confirm;
  "Stock ဖြည့်မယ်" shows only "Batch မပါ".
- QA round 5: **verified by QA.** `m/qa/qa_round4_ui_test.dart::… TC-PROD-NEW-18 …` 2/2 PASS (no sheet, line without batch; expired old
  batch: no sheet, no confirm); `m/qa/qa_round5_ui_test.dart::TC-PROD-NEW-23 (BUG-20) …` 2/2 PASS (soap with S1 (3) + expired S0: restock shows
  no old batch and no "+ Batch အသစ်", "Batch မပါ" selected, +5 outside batches in ONE restock unit, no batch created; POS no sheet / no confirm,
  sale line batchId null, stock = all movements 9 → 8, S1 stays 3; untracked soap sold 1 → "Batch မပါ" 20 → 20, ONE stockAdjust, no batch).
  The reverse switch (plain product with stock → expiry tracked) is not covered by the fix → BUG-22.

## BUG-21 · TC-PROD-NEW-19 · Medium · Add Product: an expiry-tracked product is saved with opening stock outside any batch
- Found in: round 4 · `mobile/test/qa/qa_round4_ui_test.dart` › "item 5 … TC-PROD-NEW-19 …"
- Steps to reproduce: pharmacy → Products → + → leave "ကုန်ခါနီးရင် သတိပေးမယ်" at the default "ရက် ၃၀ အလို" → name, price 1500,
  stock 10, Batch နံပါတ် and expiry empty → သိမ်းမယ်.
- Expected: owner decision (item 5): batches are required for products with expiryAlertDays (restock already requires one: no
  "Batch မပါ"). So: refused with a message, or the 10 go into a batch.
- Actual: `Expected: <0> / Actual: <10000>` — saved with expiryAlertDays 30 and 10 units in no batch: no expiry date known for them, and
  once a batch is received POS auto-picks that batch for these units too, so the batch's stock goes negative while the loose 10 never
  decrease.
- Suspected area: `mobile/lib/features/products/presentation/add_product_screen.dart` `_save` (`hasBatchInput` false → plain restock).
- Blocks beta: no for pharmacy if every medicine is added with a batch no. + expiry (or with stock 0 and received by "Stock ဖြည့်မယ်");
  recommended before beta (a validation line).
- Status: fixed in 2b74d73 (batch no. required), extended in f5b6e3b to batch no. AND expiry date (owner decision 2).
- QA round 5: **verified by QA.** `m/qa/qa_round4_ui_test.dart::… TC-PROD-NEW-19 …` PASS (no batch no. → refused, 0 outside batches);
  `… TC-PROD-NEW-21 …` 2/2 PASS (batch R5B1 without expiry → refused, nothing written, still on the form; with the 28th picked → saved,
  expiryAlertDays 30, R5B1 with that date holds 10, 0 outside; stock 0 → saved without batch). Developer test
  `m/duplicate_serial_and_no_expiry_test.dart::BUG-21 …` PASS. Live: a tracked product with batch + expiry reaches phone B unchanged
  (`m/qa/live_qa_round5_test.dart`). Only Add Product is covered; switching an existing product with stock to tracked → BUG-22.

## BUG-22 · TC-PROD-NEW-24 · Medium · Edit form: switching a product WITH stock to expiry tracking leaves that stock outside any batch; POS then sells it from the newest batch, which goes negative
- Found in: round 5 · `mobile/test/qa/qa_round5_ui_test.dart` › "TC-PROD-NEW-24 … plain medicine with 10 in stock (no batch) → edit → 'ရက် ၃၀ အလို' → save …"
- Why it matters now: owner decision 1 made "သက်တမ်း မမှတ်ပါ" the Add Product default, so a medicine added with stock and the default is a
  plain product; the natural correction is the edit form. Item 5: "batches are required only for products with expiryAlertDays set";
  decision 2 refuses exactly this state in Add Product (tracked + stock outside a batch, BUG-21).
- Steps to reproduce: pharmacy → Add Product "QA med" with stock 10, leave "သက်တမ်း မမှတ်ပါ" → save → Products → tap it (edit) → pick
  "ရက် ၃၀ အလို" → သိမ်းမယ်. Then "Stock ဖြည့်မယ်" → "+ Batch အသစ်" B1 (expiry) × 5 → POS → tap it 6 times over 6 sales.
- Expected: a tracked product never keeps stock outside batches unnoticed: the edit form asks for a batch no. + expiry for the stock on
  hand (as decision 2 does in Add Product), or refuses / warns.
- Actual: `saved with expiryAlertDays 30, 10 outside any batch, form closed, no message; after receiving B1 × 5, POS auto-picks → cart batch =
  B1; after 5 sales from B1 (product stock 10) POS offers [ကျန် 0]` — the 10 old units are sold as B1 (auto-pick, no sheet), and once B1 is
  empty the only choice is "B1 ကျန် 0", so B1 goes negative on every later sale while 10 units stay outside batches forever. Batch stock and
  the expiry each batch stands for are wrong (the same consequence as BUG-21). Product total and money are right.
- Suspected area: `mobile/lib/features/products/presentation/add_product_screen.dart` `_save` edit branch (`needsBatch` is `!_isEdit && …`;
  no check when `expiryAlertDays` goes from null to a value while stock outside batches > 0); `module_pick_sheet.dart` batch branch ignores
  stock outside batches.
- Blocks beta: no in general; pharmacy condition: when adding a medicine pick 30/60/90 days (or add it with stock 0 and receive it with
  "Stock ဖြည့်မယ်"); never switch a product that has stock to tracking. Recommended before the pharmacy beta. Owner may decide to accept
  it with that training note (then it can be Low).
- Status: fixed in 667a0e2 — **verified by QA (round 6)**. `m/qa/qa_round5_ui_test.dart::TC-PROD-NEW-24 …` now PASS;
  `m/qa/qa_round6_ui_test.dart::TC-PROD-NEW-27 (BUG-22) …` 5/5 PASS: note + batch fields after "ရက် ၃၀ အလို"; no batch no. → refused with
  "လက်ရှိ Batch မရှိတဲ့ stock 10 ခု အတွက် Batch နံပါတ် နဲ့ သက်တမ်းကုန်ရက် ထည့်ပါ။", batch no. without expiry → refused, nothing written; with
  both → ONE upsertProduct, OPEN6 (the picked date) holds 10, 0 outside, product 10, adjustments −10 / +10 "opening batch"; POS takes OPEN6;
  the next edit asks nothing. Existing batch "B1" / " B1 " → "ဒီ Batch ရှိပြီးသားပါ။"; mixed B1 5 + 3 loose → B2 3, B1 5. Fashion sizes:
  per-size groups, size stock unchanged. Loose ≤ 0 / back to "သက်တမ်း မမှတ်ပါ" → nothing asked. Loose stock arriving later from another
  phone is caught by the next edit (blocked, even a price edit, until it gets a batch — by design). Drift (real edit form):
  `m/qa/qa_round6_drift_test.dart::TC-PROD-NEW-27 Drift …` PASS (ONE outbox unit, wire shape recorded). Server:
  `b/…/QaRound6Tests.cs::TC_SYNC_NEW_11_…` PASS (applied, no issue, B pulls batch + movements). Live two phones:
  `m/qa/live_qa_round6_test.dart` PASS (B: expiryAlertDays 30, OPENL6 2027-11-28, batch 10, loose 0).

## BUG-23 · TC-PROD-NEW-26 · Low · Trade-in, then voiding the ORIGINAL sale puts the same IMEI in stock twice, unflagged (app and server)
- Found in: round 5 · `mobile/test/qa/qa_round5_ui_test.dart` › "TC-PROD-NEW-26 … then the ORIGINAL sale is voided …";
  `backend/tests/ZayPOS.QA.Tests/QaRound5Tests.cs` › `TC_SYNC_NEW_9_void_of_the_original_sale_after_a_trade_in_puts_the_imei_in_stock_twice_and_is_flagged`
- Steps to reproduce: phone shop → sell IMEI 353000000000002 (sale 1) → take the phone back: "Stock ဖြည့်မယ်" → that IMEI (decision 3:
  accepted, new in-stock row) → History → sale 1 → ပယ်ဖျက်မယ်.
- Expected: decision 3 "an IMEI that is 'inStock' is still refused" — the same IMEI is never in stock twice without the owner knowing: the
  void is refused / warned on the phone, or (two phones) the server raises `duplicateSerial` (README §3.4) like BUG-18.
- Actual: app: `void accepted, 2 in-stock rows for the IMEI, stock 2, POS offers it 2×`. Server: the voidSale unit (Drift record: it carries
  the OLD row with status inStock) is applied with `v.Issues {empty}` — `in-stock rows: 2, stock: 2000`; `CheckDuplicateSerialsAsync` only
  checks NEW rows.
- Suspected area: `mobile/lib/features/sales/application/void_sale_service.dart` `setVoided` (sets the serial back to inStock without a
  check); `backend/src/ZayPOS.Application/Sync/UnitApplier.cs` `ApplySerialsAsync` (an existing row turning inStock is not added to
  `_newInStockSerials`).
- Blocks beta: no (needs a void of a sale whose phone was already taken back — a user mistake; spec gap, owner to decide).
- Status: fixed in 667a0e2 — **verified by QA (round 6)**. App: `m/qa/qa_round5_ui_test.dart::TC-PROD-NEW-26 …` now PASS;
  `m/qa/qa_round6_ui_test.dart::TC-PROD-NEW-28 (BUG-23) …` (sale with X + 2 covers: void → covers +2, X line skipped, old row sold with
  sale 1's line, 1 in-stock row, phone stock 1; un-void → covers −2, phone 1; void again same; POS offers X once; normal void/un-void
  unchanged) PASS; Drift `m/qa/qa_round6_drift_test.dart::TC-PROD-NEW-28 Drift …` PASS (voidSale unit without the old row and without a
  phone movement; un-void no −1). Server: `b/…/QaRound5Tests.cs::TC_SYNC_NEW_9_…` now PASS; `b/…/QaRound6Tests.cs::TC_SYNC_NEW_12_…` PASS
  (void pushed before the trade-in → duplicateSerial on the trade-in; fixed app's void → no issue; normal void → no issue). Live two
  phones `m/qa/live_qa_round6_test.dart` PASS (both phones: no issue, X in stock once; crossing offline → duplicateSerial on both).
  Remaining gap (phone already resold before the void) → BUG-24.

## BUG-24 · TC-PROD-NEW-29 · Low · Trade-in resold, then voiding the ORIGINAL sale puts the phone back in stock (phantom IMEI)
- Found in: round 6 · `mobile/test/qa/qa_round6_ui_test.dart` › "TC-PROD-NEW-28 (BUG-23) … trade-in row sold again (sale 2), THEN sale 1 is
  voided → the IMEI must not come back into stock (the phone is with customer 2)"
- Steps to reproduce: phone shop → sell IMEI 357000000000003 (sale 1) → take it back: "Stock ဖြည့်မယ်" → that IMEI (trade-in, new row) →
  POS: sell it to customer 2 (sale 2) → History → sale 1 → ပယ်ဖျက်မယ် → POS tap the product.
- Expected: the phone came back once (trade-in) and is now with customer 2, so voiding sale 1 does not return it a second time — the
  same rule the BUG-23 fix applies (`void_sale_service.dart`: "a phone of this sale that was already taken back … is not returned a
  second time"); decision 3 keeps the IMEI history. 0 in-stock rows, stock 0.
- Actual: `Expected: (0, 0)  Actual: (1, 1000)` — "old row inStock, 1 in-stock rows, stock 1, POS offers it 1×". The void returns the
  OLD row to stock (+1 voidReturn) although that phone is with customer 2; POS offers it for sale. No sync issue on the server either
  (only one in-stock row, README §3.4 is not triggered), so nobody is told.
- Suspected area: `mobile/lib/features/sales/application/void_sale_service.dart` `setVoided` — `alreadyBack` only counts a line whose
  IMEI is IN STOCK as a newer row (`inStock.contains(row.serial)`); a newer row with the same serial that is already sold again is not
  considered.
- Blocks beta: no (phone shops only; needs a void of an old sale after the phone was taken back AND resold — a user mistake; the
  phone is not physically there, so the cashier cannot hand it over; stock count of that model is +1 until corrected).
- Status: verified by QA (round 7) — fixed in 8eab56b ("taken back" = a newer live row with the same IMEI, whatever its status).
  `m/qa/qa_round6_ui_test.dart::TC-PROD-NEW-28 (BUG-23) … trade-in row sold again (sale 2), THEN sale 1 is voided …` PASS (0 in-stock
  rows, stock 0, POS offers nothing); BUG-23 tests in the same group still PASS; new Drift edge cases
  `m/qa/qa_round7_drift_test.dart::TC-PROD-NEW-33 Drift (BUG-24) …` PASS: the voidSale unit has no IMEI row back to inStock and no
  voidReturn for the phone; un-void sale 1 writes no −1; void sale 2 brings the resold row back once (stock 1); void sale 1 again: still 1.
  Live two phones (`m/qa/live_qa_round6_test.dart`) and server `b/ZayPOS.QA.Tests/QaRound6Tests.cs` still PASS.

## BUG-25 · TC-PROD-NEW-31 · Low · Add/Edit Product photo preview raises an image error for a broken or unreadable photo (no fallback)
- Found in: round 7 · `mobile/test/qa/qa_round7_photo_test.dart` › "TC-PROD-NEW-31 … broken photo file → Products list, POS tile and
  the edit form show the initial / camera box, no error" and "… picked file is not an image → the product is still saved …"
- Steps to reproduce: (1) a product whose saved photo file is corrupt (e.g. a half-written `<documents>/product_photos/<id>.jpg`) →
  Products → tap the product (edit form). (2) Add Product → photo square → "ပုံ ရွေးမယ်" → a file Flutter cannot decode.
- Expected: spec 6e94350 "broken file → initial" — the form's photo square falls back like the POS tile and the Products row do
  (camera box / initial), no error.
- Actual: `Expected: null  Actual: _Exception:<Exception: Invalid image data>` (reported by the image resource service while the
  form shows the preview). Debug builds draw a red error box in the 88 px square, release builds a blank square without the camera icon.
  The rest works: the product saves, "ဓာတ်ပုံ သိမ်းလို့ မရပါ" is shown for (2), nothing is stored; the list and POS tile show the
  initial for (1); tapping the square still offers ရိုက်မယ် / ရွေးမယ် / ဖယ်မယ်.
- Suspected area: `mobile/lib/features/products/presentation/add_product_screen.dart` `build` — the `Image(key: productPhotoPreview)`
  has no `errorBuilder` (the tile in `product_tile.dart` and `InitialAvatar` in `common.dart` have one).
- Blocks beta: no (needs a corrupt file or an undecodable pick; the user can remove / replace the photo).
- Status: fixed in 2c020e8 — the preview has an `errorBuilder` showing the camera box; `m/product_photo_test.dart` › "BUG-25 …".
- QA round 8 (beta-polish @ 54e9146): **verified by QA.** `m/qa/qa_round7_photo_test.dart::TC-PROD-NEW-31 … picked file is not an image …`
  (c) and `… broken photo file → Products list, POS tile and the edit form …` (d) now PASS unchanged (no image exception; camera box
  shown); a, b, e still PASS; developer `m/product_photo_test.dart` read and run.
- Status: verified by QA (round 8)

## BUG-26 · TC-UX-NEW-3 · Low · Server texts and raw keys in English on "စစ်ရန်" and the rejected-unit screen
- Found in: round 8 · `mobile/test/qa/qa_round8_ux_test.dart` › "TC-UX-NEW-3 server texts on "စစ်ရန်" and the rejected-unit screen, and a
  rejected setFeatures unit: no English"
- Steps to reproduce: (1) save two products with the same barcode (now allowed with a warning, decision a) → sync → Settings → "စစ်ရန်".
  (2) any unit the server rejects (e.g. a setFeatures unit) → "စစ်ရန်" → tap it.
- Expected: TC-UX-02 "No English left in Burmese screens" (owner's allow-list); docs/mobile/phase3-sync.md "Errors from the server are
  ProblemDetails with a stable `code`; map codes to Burmese messages".
- Actual: the issue subtitle is the server's English `detail`; the rejected unit's reason is the server's English text; a setFeatures
  unit shows the raw feature key. Real server text from the live run (`m/qa/live_qa_round8_test.dart`): `"Barcode 8850000088001 is also
  used by: QA r8 dup one."` Test output:
  ```
  '/settings/sync-review': [
    '"လုပ်ဆောင်ချက် ပြောင်း · expiryBatch" (English: expirybatch)',
    '"tenantFeatures.featureKey must not be empty." (English: tenantfeatures, featurekey, must, not, be, empty)',
    '"Barcode 8850000088001 is also used by: ကိုကာကိုလာ.\nယခုလေးတင်" (English: is, also, used, by)' ],
  'rejected unit': [ '"လုပ်ဆောင်ချက် ပြောင်း · expiryBatch" …', '"tenantFeatures.featureKey must not be empty." …' ]
  ```
  Since e0ea12b allows duplicate barcodes, the duplicateBarcode issue (English detail) is now an everyday entry, not a rare one. Every
  server issue kind has an English detail (`UnitApplier.cs`: negativeStock "… stock is … after this sync. The sale was kept.",
  creditLimitExceeded "… owes … Ks, over the … Ks limit.", duplicateSerial "Serial … is already in stock (…). Both rows were kept.").
- Suspected area: `mobile/lib/features/sync/presentation/sync_review_screen.dart` (subtitle `i.detail`, `o.rejectReason`),
  `rejected_unit_screen.dart` (`AuthMessage(o.rejectReason)`), `sync_labels.dart` `unitSummary` ('setFeatures' joins raw `featureKey`;
  `unitKindLabel` / `issueKindLabel` / `fieldLabel` fall back to the raw English key); server `UnitApplier.cs` `Issue(...)` details.
- Blocks beta: no (the Burmese title above each entry says what happened; the English line is the detail / reason).
- Status: fixed in 7df5f1f — the app builds Burmese messages from structured server fields (SyncIssues.data, reject code + data); unknown kinds / codes → a generic Burmese message; feature keys → Settings names. Tests: `m/no_english_test.dart` (screens with sample server payloads), `m/sync_messages_test.dart`, Api `SyncTests` / `AccountTests`. QA TC-UX-NEW-3 passes unchanged.
- QA round 9: **verified** for what this bug reported. `m/qa/qa_round8_ux_test.dart::TC-UX-NEW-3 …` PASS unchanged; `m/qa/qa_round9_sync_text_test.dart` TC-UX-NEW-5 / -6: every issue kind pulled through the real engine (English user data, 6 "others", unknown kind, old row without data, a schema-v1 install upgraded to v2) shows the Burmese message with the right names / numbers and never the English detail / reason; live `m/qa/live_qa_round9_test.dart` (TC-SYNC-NEW-15): all 8 SyncIssueKinds provoked on the real server arrive WITH data on both phones, the messages are Burmese with barcode / names / IMEI / Ks / receipt numbers / minutes; an issue with Data NULL → the shorter sentence on a new phone; rejected units store code + data (fieldTooLong {products.name, 150}, fieldNotAscii {products.barcode}) → Burmese reasons. Remaining English / internal names on the same screens, not covered by this bug's report: BUG-29 (table name on the rejected-unit field labels) and BUG-30 (exception text in the sync error). Cosmetic, no bug: a number field the app has no label for is called "စာသားတစ်ခု" ("a text"), e.g. `rejectMessage('fieldTooSmall', {field: debtEntries.amount, min: 1})` → "စာသားတစ်ခု က ၁ ထက် ငယ်နေပါတယ်။" (only app bugs reach it).

## BUG-27 · TC-POS-NEW-13 · Low · One IMEI in stock on two products: scanning the box twice adds two phones
- Found in: round 8 · `mobile/test/qa/qa_round8_scan_test.dart` › "TC-POS-NEW-13 IMEI scanned at POS the same IMEI in stock on TWO products
  (duplicateSerial, BUG-18 state): scanning the one box twice adds ONE phone; the 2nd scan gives the "already in the cart" message"
- Steps to reproduce: phone shop with the same IMEI in stock on two products (the state the server flags as `duplicateSerial`, e.g. the
  same box received on two phones offline, TC-SYNC-NEW-5) → POS → scan the IMEI → scan it again (a double read of a HID scanner is enough).
- Expected: decision (c) "a scanned in-stock IMEI adds that phone with that IMEI"; code comment (`pos_screen.dart` `_addScannedSerial`)
  "Already in the cart → a message, nothing added". One box = one phone.
- Actual: `Expected: an object with length of <1>  Actual: [Instance of 'CartLine', Instance of 'CartLine']` — cart
  `[QA R8 twin 1 · IMEI 359800000000701 …, QA R8 twin 2 · IMEI 359800000000701 …]`: the 2nd scan adds the other product's row with the
  same IMEI, no message. Checking out sells two phones for one box (each row sold once, so the server raises no serialDoubleSold).
- Suspected area: `mobile/lib/features/pos/presentation/pos_screen.dart` `_addScannedSerial` — "in the cart" is checked by serial row id
  (`cart.serialIds`), not by the IMEI value.
- Blocks beta: no (needs an already-flagged duplicateSerial state; the cashier sees two lines).
- Status: fixed in 0b3e2d4 — the scanned IMEI value is compared with every cart line ("ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ"); `m/scan_lookup_test.dart` › "BUG-27 …"; QA's TC-POS-NEW-13 twin test passes (message text updated, owner-approved).
- QA round 9: **verified** for the scan path. `m/qa/qa_round8_scan_test.dart::TC-POS-NEW-13 …` 3/3 PASS; `m/qa/qa_round9_scan_test.dart::TC-POS-NEW-14 …` (twin rows, picked by tapping product A, then scanned in ASCII and in Myanmar digits → the message each time, one line) PASS; Drift `m/qa/qa_round9_scan_drift_test.dart` (received a 2nd time → newest row, 2nd scan → message) PASS. The same box can still become two phones through a TAP after the scan → BUG-28.

## BUG-28 · TC-POS-NEW-16 · Low · One IMEI in stock on two products: scan it, then tap the other product → the same IMEI is offered and added again
- Found in: round 9 · `mobile/test/qa/qa_round9_scan_test.dart` › "TC-POS-NEW-16 duplicateSerial: IMEI scanned, then the twin product
  tapped …"
- Steps to reproduce: phone shop with IMEI X in stock on product A and on product B (the flagged `duplicateSerial` state, e.g. one box
  received on two phones offline) → POS → scan X (A's phone goes into the cart) → tap product B → "ဘယ် IMEI လဲ?" lists X → tap it.
- Expected: one box = one phone. Commit 0b3e2d4 (BUG-27): "The scanned IMEI value is compared with every cart line … one box is never
  two phones (duplicateSerial)". The owner's BUG-27 words cover the scan; the tap path is the same box.
- Actual: `Expected: <1> Actual: <2>` — cart `[QA R9 tap A · IMEI 359900000000501 …, QA R9 tap B · IMEI 359900000000501 …]`; checkout
  would sell two phones for one box with no server issue (each row is sold once).
- Suspected area: `mobile/lib/features/pos/presentation/module_pick_sheet.dart` `pickModuleUnit` — `free` excludes `cart.serialIds`
  (row ids), not the IMEI values already in the cart.
- Blocks beta: no (needs an already-flagged duplicateSerial state; the cashier sees two lines with the same IMEI).
- Status: fixed in fb3fd12 — the IMEI picker excludes every IMEI number already in the cart (`cartSerialNumbers`); `m/scan_lookup_test.dart` › "BUG-28 …"; QA TC-POS-NEW-16 passes unchanged.
- QA round 10: **verified.** `m/qa/qa_round9_scan_test.dart::TC-POS-NEW-16 …` PASS unchanged; `m/qa/qa_round10_imei_cart_test.dart` (TC-POS-NEW-17, 3 tests) PASS: tap → tap, scan → tap, tap → scan, trade-in rows (sold row + newer in-stock row, plus the twin on another product; the sold row is never listed), "ရောင်းစရာ IMEI မကျန်တော့ပါ" when the only IMEI is in the cart, an emptied cart offers the IMEI again; on fake repos and on Drift with rows written by checkout + "Stock ဖြည့်မယ်". Status line accurate.

## BUG-29 · TC-UX-NEW-5, TC-UX-NEW-6 · Low · Rejected-unit screen: field labels show the internal table name ("အမည် · customers")
- Found in: round 9 · `mobile/test/qa/qa_round9_sync_text_test.dart` › "TC-UX-NEW-5 …" and "TC-UX-NEW-6 …"
- Steps to reproduce: any unit rejected by the server whose rows have ids (e.g. a new customer or product) → Settings → "စစ်ရန်" → tap
  the rejected unit → "ပြင်ရန်" fields.
- Expected: owner (BUG-26 hand-over): "No internal names on screen"; TC-UX-02 allow-list.
- Actual: field labels `"အမည် · customers"`, `"ဖုန်း · customers"`, `"လိပ်စာ · customers"`, `"မှတ်ချက် · customers"` (customer unit);
  `"အမည် · products"` (product unit, schema-v1 upgrade). Every message check in both tests passes; only these labels fail. The
  developer's `m/no_english_test.dart` sample units have rows without ids, so no field is rendered and this line is never seen.
- Suspected area: `mobile/lib/features/sync/presentation/rejected_unit_screen.dart` line ~166 `label: '${fieldLabel(f.column)} · ${f.table}'`.
- Blocks beta: no (a rejection only happens after an app bug; the Burmese label before the "·" is right).
- Status: fixed in ab92a09 — labels are "<table> · <field>" in Burmese (`tableLabel` / `rowFieldLabel`, e.g. "ဖောက်သည် · အမည်"); unknown field → "အချက်အလက်တစ်ခု" (no longer "စာသားတစ်ခု" for numbers); `m/no_english_test.dart` now shows every editable field (sample rows with ids); QA TC-UX-NEW-5/6 pass unchanged.
- QA round 10: **verified.** TC-UX-NEW-5 / -6 PASS unchanged; `m/qa/qa_round10_sync_text_test.dart::TC-UX-NEW-9 …` PASS: a unit with a row in every `editableColumns` table shows exactly the 16 Burmese labels ("ပစ္စည်း · အမည်" … "အကြွေးစာရင်း · မှတ်ချက်"); a row of an unknown table shows no field and none of its data; the validation errors on the screen are Burmese ("အမည် ထည့်ပါ။", "အမျိုးအစား စာလုံး ၆၀ လုံးထက် မပိုရပါ။", "Barcode မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်ပါ။", "IMEI / စီးရီးနံပါတ် မှာ …"). Status line accurate; note "unknown field → အချက်အလက်တစ်ခု" is the reject MESSAGE; an unknown column's field label would be "စာသား", but no such column can reach the screen (only `editableColumns` are shown). Cosmetic: "Batch · Batch".

## BUG-30 · TC-UX-NEW-7 · Low · Sync error for a row the app cannot read shows the exception text in English ("FormatException: syncIssues.kind …")
- Found in: round 9 · `mobile/test/qa/qa_round9_sync_text_test.dart` › "TC-UX-NEW-7 a pulled row the app cannot read …"
- Steps to reproduce: the server sends a pulled row this app version cannot decode (e.g. a newer server; test: a syncIssues row without
  `kind`) → sync → Settings → ဆိုင် Features (sync card); the first-sync screen shows the same `lastError`.
- Expected: phase3-sync.md "map codes to Burmese messages"; owner: "No internal names on screen". The Burmese sentence alone.
- Actual: `"ဆာဗာက ပို့တဲ့ ဒေတာကို ဖတ်မရပါ။ အက်ပ်ကို အပ်ဒိတ်လုပ်ပါ (သို့) အကူအညီဌာနကို ဆက်သွယ်ပါ။ (FormatException: syncIssues.kind:
  expected String, got Null)"`.
- Suspected area: `mobile/lib/core/sync/sync_engine.dart` `_cycle` — `error = '${SyncMessages.unreadable} ($e)'`.
- Blocks beta: no (only on an app / server version mismatch; the Burmese part says what to do).
- Status: fixed in b04dc07 — Burmese only (`SyncMessages.unreadable` / `.failed`); the raw error and stack go to the log (`dart:developer`, zaypos.sync); `m/sync_engine_test.dart` › BUG-30; QA TC-UX-NEW-7 passes unchanged.
- QA round 10: **verified.** TC-UX-NEW-7 PASS unchanged; `m/qa/qa_round10_sync_text_test.dart::TC-UX-NEW-8 …` (2 tests) PASS: on the Settings sync card a FormatException → `SyncMessages.unreadable`; a TypeError (pulled `deletedAt` as a number) and "SqliteException(13): database or disk is full" → `SyncMessages.failed`; push network (SocketException text) / 500 (SqlException detail) / an unknown English code → the Burmese `apiErrorMessage`; never the raw text; a good cycle clears it. The first-download screen shows the same Burmese messages with "ပြန်ကြိုးစားမယ်". The sync chip has fixed labels only (sync_chip.dart). Status line accurate.

## BUG-31 · TC-SYNC-NEW-14 · Medium · A field cleared on one phone is never cleared on the other phones (pulled NULLs are ignored)
- Found in: round 9 · live `mobile/test/qa/live_qa_round9_test.dart` (scratch DB R9) and `mobile/test/qa/qa_round9_pull_null_test.dart` ›
  "TC-SYNC-NEW-14 pulled NULLs replace local values …"
- Steps to reproduce: two phones of one shop, product with a barcode (or wholesale price, warranty, "ကုန်ခါနီးရင် သတိပေးမယ်" days;
  customer address / note / credit limit …) → on phone B edit the product and clear the barcode → sync B → sync A.
- Expected: phase3-sync.md §5.3 "products, productVariants, productBatches, customers, tenantFeatures, tenants | replace only if
  pulled.updatedAt >= local.updatedAt …"; ledgers and syncIssues "insert or replace by id". The newer row from B replaces A's row,
  so A's barcode is empty too.
- Actual: live: `server: <NULL> · B: null · A: 8850000099101 (A updatedAt 2026-11-14T14:38:32.960Z, B 2026-11-14T14:38:32.960Z)` — A took
  B's newer updatedAt but kept the barcode. Drift test: `Expected: {barcode: null, wholesalePrice: null, issue.data: null}  Actual:
  {barcode: 8850000099500, wholesalePrice: 140, issue.data: {"barcode":"8850000099500"}}`. Every phone that already had the value keeps it
  for good (a later edit does not clear it either); a newly signed-in phone gets the right (empty) value — the shop's phones silently
  disagree. Examples that matter in the beta: removing a duplicate barcode from one product (what shops will do after a
  `duplicateBarcode` issue) — the other phones keep the barcode and keep showing the "ဘယ်ပစ္စည်းလဲ?" picker; switching a medicine back
  to "သက်တမ်း မမှတ်ပါ" — the other phones keep asking for a Batch; removing a customer's credit limit.
- Suspected area: `mobile/lib/core/sync/sync_store.dart` `_merge` — `insertOnConflictUpdate(<data class>)`: Drift writes a data class
  with `nullToAbsent: true`, so NULL columns are left out of the `ON CONFLICT DO UPDATE` and the old values stay. Local edits are not
  affected (`drift_product_repository.dart` `update` uses `replace`).
- Blocks beta: **yes by the owner's exit rule** (Medium) — or the owner accepts it as a known risk for 3–5 shops.
- Status: fixed in 8b513b5 — pulled rows are applied whole (`toCompanion(false)`: NULL columns written) under the same last-writer-wins / pending-outbox rules. Both directions tested: Api `SyncTests` › "A_cleared_field_is_stored_as_null_and_pulled_as_an_explicit_null"; `m/pull_null_test.dart` (5 tests); live two phones `m/live_clear_fields_test.dart` (B clears barcode, wholesale price, expiry days, credit limit → empty on A; a duplicate barcode cleared on B is resolved on A; fails without the fix). QA TC-SYNC-NEW-14 and `live_qa_round9_test.dart` pass unchanged. Note: the app has no customer edit screen yet, so the live test records the upsertCustomer unit such an edit would send.
- QA round 10: **verified**, with one regression found (BUG-32). Evidence: TC-SYNC-NEW-14 (Drift + live) PASS unchanged (live R10: `server: <NULL> · B: null · A: null`); `m/qa/qa_round10_pull_null_test.dart` TC-SYNC-NEW-16 (5 tests: every nullable column of every synced table cleared by a newer pull, deletedAt NULL = live again, equal updatedAt takes the pulled row, an OLDER row clears nothing on any LWW table, own device lastSeq stays max, an unpushed customer is untouched) and TC-SYNC-NEW-18 (the real edit form: Barcode / wholesale price cleared, warranty "မရှိ", "သက်တမ်း မမှတ်ပါ" → 4 explicit nulls in the unit → empty on phone A) PASS; the same tests on a worktree at e140618 fail where BUG-31 predicts. Live `m/qa/live_qa_round10_test.dart` (TC-SYNC-NEW-19) PASS: the real server's pull JSON, read through the app's DioSyncApi, has `barcode`, `wholesalePrice`, `warrantyMonths`, `expiryAlertDays`, `address`, `note`, `creditLimit` present with null; SQL shows NULL; phone A shows all 7 empty; both phones find one product for the old duplicate Barcode. Developer evidence re-run: `m/pull_null_test.dart` 5/5, live `m/live_clear_fields_test.dart` PASS, Api `SyncTests` › A_cleared_field… PASS. Status line: accurate for the LWW tables; but ledger rows (sales) are now applied whole without a pending-outbox check, which undoes an unpushed void → BUG-32. Not checked by QA: the status's "fails without the fix" for the live file (it was not run against an old server/app). For the owner: (1) the app has no customer edit screen (the pencil button does nothing, BUG-33), so a credit limit / address / note can be cleared only by a future edit screen — the sync part is proven at unit level and live; (2) after a duplicate Barcode is cleared, the `duplicateBarcode` issue stays open on every phone (live: `A open=(true), B open=(true)`) until the owner taps "စစ်ပြီး"; that resolution then reaches the other phones (live PASS). The data is consistent; whether the server should close the issue by itself is an owner decision.

## BUG-32 · TC-SYNC-NEW-17 · Low · A pull can un-void a sale whose void has not been pushed yet (regression of 8b513b5)
- Found in: round 10 · `mobile/test/qa/qa_round10_pull_null_test.dart` › "TC-SYNC-NEW-17 a sale voided on this phone …" and
  "TC-SYNC-NEW-17 the same through the real SyncEngine on a flaky network …"
- Steps to reproduce: phone A sells (checkout pushed and applied), the following pull drops (bad network) → the cashier voids the sale
  → the void push fails (network, back-off) → the next automatic sync cycle skips the push (back-off) and pulls → the page contains the
  server copy of that sale (voidedAt NULL — the echo of its own checkout). Any pull that re-sends the sale while its void is pending does
  the same (e.g. the other phone un-voided it).
- Expected: owner (BUG-31 hand-over): full-row apply "under the existing LWW and pending-outbox rules"; phase3-sync.md §5.3 lets ledger
  rows be replaced only because "local copies are identical" — a sale with a pending void is not identical. The sale stays voided on A
  until the void is pushed. Before 8b513b5 it did (NULL columns were skipped).
- Actual: `Expected: not null  Actual: <null>` (sales.voidedAt), with the voidSale unit still pending in the outbox and the stock already
  returned (`stock here is 5`). Sales history / the receipt show the sale as not voided, the day's totals count it again, and the sale
  screen offers "void" a second time. The same two tests PASS on a worktree at e140618.
- Suspected area: `mobile/lib/core/sync/sync_store.dart` `_merge`, `case WireTable.sales` (and the other ledger cases): whole-row
  `insertOnConflictUpdate(...toCompanion(false))` without the `unpushed` check the LWW tables have.
- Self-heals: when the void is pushed, the next pull brings voidedAt back; a second void by the cashier is skipped by the server and its
  local ledger rows are dropped (sync_store.dart applyResults "skipped"), so no stock is lost for good.
- Blocks beta: no (needs a void within one failed sync of the sale on a flaky network; wrong only until the next good sync).
- Status: fixed in 17180db — general rule: a pull never overwrites a row of an unsent or blocked outbox unit, any table (ledgers included); the skipped rows are pulled again (cursor rewound) once their unit is sent; a blocked unit keeps them protected. `m/pending_rows_pull_test.dart` (void fails to send → not undone, day totals stay correct, re-pull after the send; product + stock movement; rejected unit); QA TC-SYNC-NEW-17 passes unchanged.
- QA round 11: **verified**, live included. TC-SYNC-NEW-17 (2 tests) PASS unchanged. `m/qa/qa_round11_pending_pull_test.dart` (9 tests, all PASS): ONE pending unit holding a row of each of the 14 synced tables (tenants, tenantFeatures, devices, products, variants, batches, serials, customers, sales, saleLines, payments, stockMovements, debtEntries, syncIssues) is untouched by a page of changed server copies, while a bystander row on the same page is merged; all 14 keys are remembered with the page start; after the send the cursor goes back and the server copies are taken (TC-SYNC-NEW-20). Rejected → protected; another unit's result does not rewind; "resend" keeps it protected; applied → rewind to the EARLIEST skipped page (TC-SYNC-NEW-20). Two units over one row, one applied and one rejected → no rewind until the second is sent (TC-SYNC-NEW-21). **The server kept the other phone's newer copy (last-writer-wins lost):** without the rewind the phone would keep its own copy for good; with it, it converges (TC-SYNC-NEW-21, and live). A row skipped on two pages of one pull and again in a later cycle gives one rewind to the earliest start and no duplicates (TC-SYNC-NEW-21). A file database closed and reopened between the skip and the send keeps the state (TC-SYNC-NEW-22). First download with a unit recorded meanwhile: the row is skipped, the push afterwards rewinds to "0", the next cycle downloads again; nothing is duplicated and the app opens once (TC-SYNC-NEW-22). voidSale "skipped" (the other phone voided first): A's own return rows are dropped, the re-pull gives B's voidedAt, one return, stock 5, today 0 (TC-SYNC-NEW-23). The screens while the void is unsent and after the send: dashboard 150 Ks / "1 ကြိမ်", sales history 150 Ks, sale detail "ပယ်ဖျက်ပြီး" (not "ပယ်ဖျက်မယ်"), report 150 Ks (TC-SYNC-NEW-24). Live `m/qa/live_qa_round11_test.dart` (TC-SYNC-NEW-27) PASS on the real server: `A while its edit is unsent: name=QA r11 Daw Mya (A) repullKeys=["customers:…"]` → `after A sent: A=(QA r11 Daw Mya (B), 09790011102, null, 20000) server=(same)`; void: `during: voidedAt=2026-11-14 16:31:06.966Z today=0 outbox=(voidSale) repullKeys has sale=true`; the end state on A and on B equals the server row for row (`sales: 1, saleLines: 1, payments: 1, stockMovements: 3, customers: 1, products: 3, syncIssues: 2`). Status line: accurate. Two notes, neither from this fix: (1) if both phones void the same sale and A's void is not sent yet, A shows the stock returned twice (`stock … 7 (true: 5)`) until A's push is answered "skipped". B's return row is not part of A's unit, so the rule does not cover it. This was already so before 17180db (by code reading) and it corrects itself. (2) A rewind on the first download re-downloads the whole shop once (correct, only slower).

## BUG-33 · TC-DEBT-NEW-6 · Low · Customer screen: the "ပြင်ဆင်ရန်" (edit) button does nothing — a customer can never be corrected
- Found in: round 10 · `mobile/test/qa/qa_round10_customer_edit_test.dart` › "TC-DEBT-NEW-6 customer screen: the "ပြင်ဆင်ရန်" (edit)
  button opens an edit form …"
- Steps to reproduce: Customers → any customer ("အကြွေးစာရင်း") → tap the pencil button at the top right.
- Expected: the button (semantics "ပြင်ဆင်ရန်" = edit) opens an edit form, so a wrong phone number / address or the credit limit can be
  changed or removed. The owner's BUG-31 check itself asks to "clear … credit limit on phone B"; Add Customer promises a credit-limit
  warning (BUG-7) that a shop cannot later relax.
- Actual: `Expected: (true, true)  Actual: (false, false)` — no navigation, no field with the customer's name. `debt_screen.dart`:
  `AppIconButton(icon: AppIcons.edit, size: 20, semanticLabel: 'ပြင်ဆင်ရန်', onPressed: () {})`, unchanged since d99efb7 (Phase 1). The
  developer confirms "the app has NO customer edit screen" (round-10 hand-over); the sync side (upsertCustomer with nulls) works live.
- Suspected area: `mobile/lib/features/customers/presentation/debt_screen.dart` (header trailing button); no customer edit route.
- Blocks beta: no (workaround: add the customer again; the old debt history stays on the old entry). Owner decision: add a small edit
  form (name, phone, address, credit limit, note) or hide the button for the beta.
- Status: fixed in ae22869 — "ပြင်ဆင်ရန်" opens the Add Customer form in edit mode (name, phone, address, credit limit, note; current balance next to the limit; a lower limit is allowed; no opening balance). Same rules as Add plus a duplicate-phone warning (new on Add too). One upsertCustomer unit, whole row. `m/customer_edit_test.dart`; QA test check changed from "route changed" to "edit form opened" (owner approved, see commit).
- QA round 11: **verified**, with one new Low gap (BUG-34). TC-DEBT-NEW-6 PASS with the developer's edited check. QA reviewed that edit and accepts it. The claim is true: `uri before=/customers/<id> after=/customers/<id> top=/customers/<id>/edit (ImperativeRouteMatch)` (`m/qa/qa_round11_customer_edit_test.dart` › "TC-DEBT-NEW-6 review …" now asserts the pushed route is on top). `m/qa/qa_round11_customer_edit_test.dart` TC-DEBT-NEW-7 (3 tests, PASS): ဦးသန်းထွန်း (owes 96,000) shows "96,000 Ks" next to the limit; a limit of 50,000 is saved; at checkout on credit the warning shows the new limit and "96,600"; clearing it removes the warning. The seeded placeholder phone "09 7xx xxx 102" can be kept unchanged (no error, no warning); typing it for another customer warns with "“ဒေါ်ခင်မာ”"; a Myanmar-digit phone is stored as 0-9 and matched. No English on the form, its errors or the dialog. Live (TC-SYNC-NEW-27): B's edit (name, phone, address cleared, limit 50,000 → 20,000) reaches A. Developer evidence re-run: `m/customer_edit_test.dart` 3/3. Gap: the duplicate-phone check compares the exact text, so "09 790 011 002" or "09-790-011-002" against "09790011002" gives no warning → BUG-34.

## BUG-34 · TC-DEBT-NEW-8 · Low · Duplicate-phone warning misses the same number typed with spaces or dashes
- Found in: round 11 · `mobile/test/qa/qa_round11_customer_edit_test.dart` › "TC-DEBT-NEW-8 the same number typed with spaces …"
- Steps to reproduce: customer ဒေါ်မြ has phone "09790011002" → edit another customer (or Add Customer) → type "09 790 011 002"
  (the field's own hint is "09 xxx xxx xxx"; the sample customers are stored with spaces) or "09-790-011-002" → "သိမ်းမယ်".
- Expected: owner: "Same validation as add (duplicate phone warning)". It is the same phone number, so "ဒီ ဖုန်းနံပါတ် ရှိပြီးသားပါ"
  should show (warn, don't block).
- Actual: `Expected: (true, true)  Actual: (false, false)`. No dialog on Edit or on Add; both numbers are saved and the shop now has two
  customers with one number.
- Suspected area: `mobile/lib/features/customers/presentation/add_customer_screen.dart` `_confirmDuplicatePhone`: compares
  `limits.normalize('customers.phone', …)`, which only trims, maps Myanmar digits and drops non-ASCII. Spaces, dashes and a "+95"
  prefix stay.
- Blocks beta: no (a warning only; nothing is lost).
- Status: fixed (developer, 2026-11-15) — one normalizer `phoneKey` (`mobile/lib/core/utils/phone.dart`): Myanmar digits → 0-9,
  spaces/dashes/dots/brackets dropped, +959 / 959 → 09. Used by the duplicate-phone warning (Add and Edit, incl. "own number
  re-written with spaces is not a change"), customer search, the sign-in same-shop check, and `normalizeMmPhone` (OTP) is built on it.
  The server's `PhoneNumbers.Normalize` now maps Myanmar digits too (before, .NET's `\d` let them through unconverted). Stored phones
  are unchanged (kept as typed). Tests: `m/phone_key_test.dart` (7), `b/…/AuthRulesTests.cs` (+4 cases); QA's TC-DEBT-NEW-8 passes.
- QA round 12: **verified**, with two new Low gaps (backlog BUG-36, BUG-37). TC-DEBT-NEW-8 PASS. `m/qa/qa_round12_phone_test.dart` › TC-DEBT-NEW-10 PASS: the warning also shows when the OTHER customer is stored as "+95 9 790 011 002" or "09 (790) 011-003" and the new one is typed "09790011002", "၀၉၇၉၀၀၁၁၀၀၂" or "959.790.011.003"; the own number re-typed as "+95 …" gives no warning. Search (TC-DEBT-NEW-9): 11 of 14 partial queries find the customer ("0979001", "+95 9 790", "၀၉၇၉၀ ၀၁၁", "011002", "+95 9 420 123 456", "၄၅၆" …); the 3 that start with "959" do not → BUG-36 (a regression: 2 of them worked at 16aaa33). Sign-in, live on the real API (`m/qa/live_qa_round12_test.dart`, TC-AUTH-NEW-3, PASS): OTP asked in Myanmar digits, register typed "09.790.917.041", phone B signs in with "+95 9 790 917 041", phone A signs in again in Myanmar digits while it has an UNSENT unit (same shop → allowed, both products kept), PIN reset asked "959-790-917-041" and done in Myanmar digits, phone C signs in dotted with the new PIN (old PIN refused); owner phone stored "+959790917041"; a raw register-OTP in Myanmar digits → `409 phone_registered`. Server (`b/ZayPOS.QA.Tests/QaRound12Tests.cs` › TC_AUTH_NEW_1, PASS): one account and one 3-per-hour OTP limit across Myanmar-digit, dotted, spaced and dashed forms; Users.Phone ASCII. Gap: other-script digits (Shan ႐-႙, Arabic-Indic, full-width) still pass .NET's `\d` and become a non-ASCII "+959…" → BUG-37. Developer evidence re-run: `m/phone_key_test.dart` 7/7, `b/…/AuthRulesTests.cs` PASS.

## BUG-35 · TC-RPT-NEW-1 · Low · Report screen: the 7-day chart breaks when the last 7 days have no sales (NaN bar heights)
- Found in: round 11 (while checking day totals for BUG-32) · `mobile/test/qa/qa_round11_sync_history_test.dart` › "TC-RPT-NEW-1 …"
- Steps to reproduce: a new shop (or one whose sales of the last 7 days are all voided) → Reports ("အစီရင်ခံစာ").
- Expected: the chart shows 7 empty bars with "0", like any other day without sales.
- Actual: 14 layout errors: `BoxConstraints has NaN values in minHeight and maxHeight` (thrown building the bar Container) and
  `A RenderFlex overflowed by 99868 pixels on the bottom` (report_screen.dart:221). A debug build shows error boxes in the chart.
  The release-build look is not known (asserts are off); the owner should check it on a phone (MANUAL list).
- Suspected area: `mobile/lib/features/reports/presentation/report_screen.dart` `_WeekChart.build`:
  `height: (days[i].amount / max * 120)` with `max == 0` → 0/0. This was there before this round; no earlier test opened the report
  with an empty week.
- Blocks beta: no (data and totals are correct; only the chart). New shops see this screen on day 1, so it is worth fixing before
  the beta.
- Status: fixed (developer, 2026-11-15) — `_WeekChart` never divides by a zero week: bars are flat (height 0) and
  "ရောင်းအား မရှိသေးပါ" shows over the chart; the semantics label says the same. Tests: `m/report_empty_week_test.dart` (2; the
  empty-week test fails without the fix); QA's TC-RPT-NEW-1 passes.
- QA round 12: **verified**. TC-RPT-NEW-1 PASS. `m/qa/qa_round12_report_test.dart`: a week where only some days have sales (3 days ago 20,000; 2 days ago 60,000 voided; today 40,000) → no layout error, no empty message, bars `[0, 0, 0, 60, 0, 0, 120]`, labels `[0, 0, 0, 20, 0, 0, 40]`, the voided day flat, total 60,000 Ks / "2 ကြိမ်" (TC-RPT-NEW-2). A week whose sales were all voided, plus one sale 8 days ago → "ရောင်းအား မရှိသေးပါ", 7 flat bars labelled "0", the semantics label says so, on the "ဒီနေ့", "ဒီလ" and "ဒီအပတ်" tabs; 0 Ks / "0 ကြိမ်"; the first new sale removes the message and gives `[0, 0, 0, 0, 0, 0, 120]` (TC-RPT-NEW-3). Developer evidence re-run: `m/report_empty_week_test.dart` 2/2. Found next to it (it was already there before the fix): the screen-reader label says "ယနေ့နေ့" → backlog BUG-38.

---

## Beta backlog (Low, found in round 12; do not block the beta)

## BUG-36 · TC-DEBT-NEW-9 · Low · Customer search: a number typed from its middle that starts with "959" finds nothing (regression of 205c5d7)
- Found in: round 12 · `mobile/test/qa/qa_round12_phone_test.dart` › "TC-DEBT-NEW-9 customer search with partial numbers …"
- Steps to reproduce: customer ကိုစိုး with phone "09 777 959 123" → Customers → "အားလုံး" → search "959123" (or "959 123", "၉၅၉၁၂၃").
- Expected: the customer is found; "959123" is part of the number (phone.dart: "a partial number typed into search is returned with
  only those steps applied"). At 16aaa33 (before the fix) "959123" and "959 123" found him.
- Actual: `TC-DEBT-NEW-9 queries that do not find the customer: [959123, 959 123, ၉၅၉၁၂၃]` (the other 11 queries work). The same test
  run on an export of 16aaa33 misses `[၉၅၉၁၂၃, 0979001, ၀၉၇၉၀ ၀၁၁, 0942012, +95 9 420 123 456]`, so 205c5d7 fixed five and broke two.
  Also, the query "959" alone becomes "09" and lists every customer.
- Suspected area: `mobile/lib/features/customers/presentation/customers_screen.dart` `_phoneMatches` runs the QUERY through
  `phoneKey`, which rewrites a leading "959" as "09" (international prefix) even when the query is a partial number.
- Blocks beta: no (search by name or by other digits still works).
- Status: open (beta backlog)

## BUG-37 · TC-AUTH-NEW-2 · Low · Server accepts phone numbers in other scripts' digits and stores a non-ASCII "+959…"
- Found in: round 12 · `backend/tests/ZayPOS.QA.Tests/QaRound12Tests.cs` › `TC_AUTH_NEW_2_…` (4 tests)
- Steps to reproduce: `POST /api/v1/auth/otp {"phone":"09႗႙႐႐႑႑႐႐႒","purpose":"register"}` (Shan digits U+1090–1099, which are in the
  Myanmar Unicode block), or "+959" + Arabic-Indic digits, or "09" + full-width digits.
- Expected: the same rule as the app (the doc comment says "the same rules as the app's phoneKey/normalizeMmPhone"): the app's Dart
  `\d` is 0-9 only and refuses these, so the server should refuse them (400) or map them to 0-9.
- Actual: `Normalize("09႗႙႐႐႑႑႐႐႒") returned "+959႗႙႐႐႑႑႐႐႒"`, same for Arabic-Indic and full-width; the API answers 202 and "sends"
  an SMS to `+959႗႙႐႐႑႑႐႐႒`; a shop could be registered under that number.
- Suspected area: `backend/src/ZayPOS.Application/Auth/AuthRules.cs` `PhoneNumbers.Subscriber()` — `^\d{7,9}$` without
  `RegexOptions.ECMAScript` matches every Unicode decimal digit; `ToAsciiDigits` maps only ၀-၉. Already so before 205c5d7.
- Blocks beta: no (the app never sends such a number; only a hand-made API call).
- Status: open (beta backlog)

## BUG-38 · TC-RPT-NEW-4 · Low · Report chart screen-reader label: "အမြင့်ဆုံးက ယနေ့နေ့ 40K" and short weekday names
- Found in: round 12 · `mobile/test/qa/qa_round12_report_test.dart` › "TC-RPT-NEW-4 …"
- Steps to reproduce: a sale today only → Reports → TalkBack / VoiceOver on the 7-day chart.
- Expected: "… အမြင့်ဆုံးက ယနေ့ 40K" (ယနေ့ = today); on other days the full weekday name ("သောကြာနေ့").
- Actual: `today peak="… အမြင့်ဆုံးက ယနေ့နေ့ 40K"`, `other peak="… အမြင့်ဆုံးက သောနေ့ 90K"`. The label adds "နေ့" to the chart's short
  axis names. Already so before d8cb91e.
- Suspected area: `mobile/lib/features/reports/presentation/report_screen.dart` `_WeekChart` semantics label (`${peak.day}နေ့`).
- Blocks beta: no (screen readers only).
- Status: open (beta backlog)

---

## Known limitations for the beta (owner, 2026-11-14)

- **Product photos stay on the phone where they were taken.** They are not synced: another phone of the same shop, a reinstall or a
  new phone shows the product's initial instead. By design for the beta (6e94350 "stored locally only"; TC-PROD-NEW-32 checks that no
  photo bytes go into the outbox). Tell beta shops; photo sync is a later feature.
- **Duplicate barcodes are allowed** (decision, implemented in e0ea12b): Add/Edit Product warns, POS asks which product. The server
  still flags `duplicateBarcode` in the sync review, and closes it itself once no other live product has the barcode (1420ee8:
  resolved "ပြင်ပြီးသွားပါပြီ", kept in the history on every phone). A duplicate that exists only on one phone (offline) is not known to
  the server until that phone syncs.
- **IMEI scan at POS** (decision, e0ea12b; updated 0b3e2d4): an in-stock IMEI adds that phone; an IMEI already in the cart (by its
  number, any product) → "ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ"; an IMEI whose latest row is **sold** → "ဒီ IMEI က ရောင်းပြီးသားပါ —
  ပြန်ဝယ်ရင် 'Stock ဖြည့်မယ်' ကနေ လက်ခံပါ" (no "ပစ္စည်းအသစ်" offer; a product barcode with the same code still wins); a trade-in is
  received only with "Stock ဖြည့်မယ်". Unknown IMEIs and IMEIs of deleted products still go to "ပစ္စည်းအသစ် ထည့်မယ်". Only in shops
  with IMEI tracking on.
- **Two phones voiding the same sale while one is offline** (owner, 2026-11-15): the offline phone shows the stock returned twice
  (e.g. 1 sold, voided on both → +2 instead of +1) until its next sync. The server applies the void once, and after the sync the phone
  takes the server's copy and shows the right stock (TC-SYNC-NEW-23). Nothing is lost; tell shops that only one phone should void a sale.
- **Sync issue texts** (BUG-26, 7df5f1f): the app builds them in Burmese from the server's structured fields. Issues raised before
  this server version have no fields and show a shorter Burmese sentence (e.g. "ဒီ Barcode ကို ပစ္စည်းတွေမှာ သုံးထားပါတယ်…" without
  the names).

QA round 8 check of this section: **accurate**, with four additions the owner should tell shops (all proven by round-8 tests):
1. Photos: correct (TC-PROD-NEW-32 PASS: one upsertProduct unit without photo bytes; phone B shows the initial).
2. Duplicate barcodes: the warning only knows the products on THIS phone. Two phones adding the same barcode offline get no warning; the
   server flags it after sync (TC-SYNC-NEW-13 live: one `duplicateBarcode` on both phones; phone B's POS picker lists both). A deleted
   product's barcode is not a duplicate (TC-PROD-NEW-35). The issue text on "စစ်ရန်" is English (BUG-26).
3. IMEI scan: only in shops with IMEI tracking on; an IMEI of a deleted product also goes to "ပစ္စည်းအသစ် ထည့်မယ်"; a SOLD IMEI being
   offered as a new product's barcode is still the round-7 risk — trade-ins must be received with "Stock ဖြည့်မယ်", not by scanning at POS
   (TC-POS-NEW-13).
4. If one IMEI is in stock twice (a flagged duplicateSerial), two scans add two phones (BUG-27).

Developer note (after round 8): points 2 (English issue text) and 4 are fixed by BUG-26 / BUG-27; point 3's sold-IMEI risk is replaced by
the owner's "sold" message (see the IMEI bullet above).

QA round 9 check of this section (fe1acaa): **accurate, with one correction and three additions** (all proven by round-9 tests):
1. Photos, duplicate barcodes: unchanged and correct. Addition: clearing a duplicate barcode on one phone does not reach the other phones
   (BUG-31, Medium) — they keep the barcode and keep showing the picker.
2. IMEI scan: correct for the in-cart message (by number, any product, Myanmar digits too — TC-POS-NEW-14), the sold message (latest
   row by createdAt, whole trade-in chains, a product barcode wins, only with IMEI tracking on — TC-POS-NEW-15) and "unknown IMEIs →
   ပစ္စည်းအသစ်". **Correction:** "IMEIs of deleted products still go to ပစ္စည်းအသစ်" is true only for an in-stock IMEI; a deleted
   product's IMEI whose latest row is sold gets the sold message (`qa_round9_scan_test.dart` TC-POS-NEW-15, 3rd test). Addition: the "in
   the cart" check is for scans only — tapping the twin product after a scan still offers the same IMEI (BUG-28).
3. Sync issue texts: correct — old issues without fields show the shorter Burmese sentence (live: phone C; TC-UX-NEW-6 after a v1 → v2
   upgrade). Addition: a phone that already has an issue keeps its old copy of the fields (BUG-31); the rejected-unit screen still shows
   the table name (BUG-29) and the Settings sync card can show an English exception for an unreadable row (BUG-30).
4. QA round-8 points 2 ("issue text is English") and 4 (BUG-27) are out of date as the developer note says.

QA round 10 check of this section (af191a5; bullets unchanged since round 9): **accurate**; the round-9 additions are out of date and
two things are new (all proven by round-10 tests):
1. Duplicate barcodes: clearing the Barcode on one phone now reaches every phone (BUG-31 fixed; live TC-SYNC-NEW-19). **New:** the
   `duplicateBarcode` entry stays in "စစ်ရန်" on every phone until the owner taps "စစ်ပြီး" (the server does not close it when the
   duplicate is gone); tell shops to fix the barcode first, then mark the entry.
2. IMEI: "the in-cart check is for scans only" is out of date — taps are covered too (BUG-28 fixed; TC-POS-NEW-17).
3. Sync texts: the rejected-unit labels and the sync error texts are Burmese now (BUG-29, BUG-30 fixed; TC-UX-NEW-8, -9).
4. **New:** customers cannot be edited after they are saved (BUG-33): a wrong phone number or credit limit means adding the customer
   again.

QA round 11 check of this section (dbf2b5f): **accurate**. The round-10 additions 1 and 4 are out of date, and there are three
additions (all proven by round-11 tests unless marked):
1. Duplicate barcodes: correct. The server closes the issue after the barcode is cleared, changed or deleted, on every phone, and keeps
   it in "ပြီးသွားတဲ့ ကိစ္စများ" (TC-SYNC-NEW-25..27, live). A later duplicate is a new entry. Addition (by code reading): it closes only
   when a product change reaches the server, so an entry whose duplicate was fixed before this server version stays open until any
   product in that shop is edited and synced, or until "စစ်ပြီး" is tapped.
2. Customers can be edited now (BUG-33 fixed). Addition: the duplicate-phone warning does not see the same number written with spaces
   or dashes (BUG-34).
3. Addition: if two phones void the same sale and one of them is offline, that phone shows the stock returned twice until it syncs
   (TC-SYNC-NEW-23; it corrects itself).

QA round 12 check of this section (ee662f3): **accurate**; the round-11 addition 2 (BUG-34) is out of date. One correction to the new
"two phones voiding" bullet (proven by `m/qa/qa_round12_void_twice_test.dart`, TC-SYNC-NEW-28):
1. **While the phone is offline its stock is right** (1 sold of 5, voided: 5). The double count starts when it comes back **online**:
   its earlier failed sends put it in a push back-off (5 s … 10 min) and the automatic sync (back online, the timer) only downloads,
   which brings the other phone's return: 6. It stays 6 for automatic syncs until the back-off ends (still 6 nine minutes later),
   then the void is sent, answered "skipped" and the phone shows 5 with one return. A manual sync ("ယခု sync လုပ်မယ်" in Settings, or pull-to-refresh on the dashboard / sales list) fixes it at
   once. Suggested wording: "after it comes back online, for up to 10 minutes or until a manual sync". Today's total is right (0)
   the whole time. The example "+2 instead of +1" is right for 1 sold.
2. Customers: the duplicate-phone warning now sees spaces, dashes, dots, "+95 9 …" and Myanmar digits (BUG-34 fixed). Customer
   search misses partial numbers that start with "959" (BUG-36, backlog).

---

## Owner decisions 2026-11-14 — resolved in round 5

Implemented in f5b6e3b; QA's acceptance tests (written at 2b74d73, failing then by design) now pass. Developer-owned tests were updated
to the decisions (read in round 5: same purpose, new expected result, nothing removed).

- **Decision 1 — verified.** `m/qa/qa_app_flows_test.dart::TC-FEAT-02 …` PASS, `m/qa/qa_round4_ui_test.dart::… TC-PROD-NEW-20 …` PASS (starts
  at "သက်တမ်း မမှတ်ပါ", no batch fields until 30/60/90, hidden again, default saves a plain product with 12 outside batches); edit form keeps
  saved days (TC-PROD-NEW-16 PASS). Live: the default product reaches phone B with expiryAlertDays null (`m/qa/live_qa_round5_test.dart`).
  Side effect found: BUG-22.
- **Decision 2 — verified.** TC-PROD-NEW-21 2/2 PASS, TC-PROD-NEW-19 PASS (see BUG-21).
- **Decision 3 — verified** for receiving (Add Product, edit form, "Stock ဖြည့်မယ်") and two phones: `m/qa/qa_round3_ui_test.dart::TC-PROD-NEW-6 …`,
  `::TC-PROD-NEW-9 … phone …`, `m/qa/qa_round4_ui_test.dart::TC-PROD-NEW-14 …` 2/2, `m/qa/qa_round5_ui_test.dart::TC-PROD-NEW-25 … sells the
  NEW row …`, `m/qa/qa_round5_drift_test.dart::TC-PROD-NEW-25 Drift …` (SQL in-stock set excludes sold and deleted; trade-in = ONE restock unit
  with only the new row), server `b/…/QaRound5Tests.cs::TC_SYNC_NEW_10_…` and developer `b/…/SyncTests.cs::Trade_in_a_sold_IMEI_received_again…`
  PASS, live two phones `m/qa/live_qa_round5_test.dart` PASS (A sells X, B takes it back, A sells it again: no issue, both phones 2 rows with
  their own sale lines, stock 0). Gap found: void of the original sale afterwards → BUG-23 (Low).

Original text of the pending section (round 4 → 2b74d73), kept for history:

- **Decision 1** — Add Product starts at "သက်တမ်း မမှတ်ပါ"; batch fields only after 30/60/90 is picked.
  `m/qa/qa_app_flows_test.dart::TC-FEAT-02 …`, `m/qa/qa_round4_ui_test.dart::… TC-PROD-NEW-20 …`.
  Today: `Found 0 widgets with text "သက်တမ်း မမှတ်ပါ"` under `expiryWarn` (default is ရက် ၃၀).
- **Decision 2** — tracked opening stock needs batch no. AND expiry date. `m/qa/qa_round4_ui_test.dart::… TC-PROD-NEW-21 … batch no.
  without expiry date refused …`. Today: saved with batch R5B1 and no expiry (`Expected: empty, Actual: [Product]`). Suspected area:
  `add_product_screen.dart` `_save` (`needsBatch` checks only `_batchNo`).
- **Decision 3** — a SOLD IMEI can be received again (new inStock row, sold row kept); in-stock still refused.
  `m/qa/qa_round3_ui_test.dart::TC-PROD-NEW-6 … keypad …`, `::TC-PROD-NEW-9 … phone: …`, `m/qa/qa_round4_ui_test.dart::TC-PROD-NEW-14 …`
  (2 tests). Today: "ဒီ IMEI ရှိပြီးသားပါ။" for the sold IMEI. Suspected area: `knownSerialsProvider` (contains sold serials) used by
  `add_product_screen.dart` `_addImei`, `edit_module_sections.dart` `_addImei`, `products_screen.dart` → restock sheet `knownSerials`.
- Developer-owned tests that encode the old behaviour (QA did not touch them): `m/duplicate_serial_and_no_expiry_test.dart` › item 5
  "Add Product: … hides batch fields …" (expects `batchNo` at the default) and BUG-21 "stock without batch no. → refused …; with batch
  no. → saved into that batch" (saves without expiry); `m/add_product_modules_test.dart` (types `batchNo` at the default, ~line 41).
