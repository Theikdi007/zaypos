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
- Status: open (partly: the fashion Add Product overflow was the margin row, fixed in 056ef3e; the Customers filter chips still overflow)
- QA round 2: confirmed partly fixed. `m/qa/qa_ux_test.dart::TC-UX-04 … add product, fashion template, scrolled to the end` PASS;
  `… /customers`, `… /customers/new`, `… /customers/<id>` still FAIL. Stays open (Low).

## BUG-9 · TC-UX-02 · Low · English left on Burmese screens
- Found in: round 1 · `mobile/test/qa/qa_ux_test.dart` › "TC-UX-02 …" (2 tests)
- Steps to reproduce: open every screen.
- Expected: no English except brand/payment names (and the loanwords the spec itself uses: Stock, Sync, Quick Sale, PIN, IMEI, Barcode…).
- Actual: times as "3:42 PM" / "10:12 AM" (dashboard, history, sale detail, receipt, customer history); bottom tab "Report";
  Settings/Register descriptions "ရောင်းခြင်း (POS)", "နေ့စဉ် Report", "ဖုန်း၊ Electronics", "Size / အရောင်", "Quotation",
  "ဝန်ဆောင်မှု item", "Order mode", "Hardware / ဆောက်လုပ်ရေး", "service", "Core feature". No broken Unicode found.
- Suspected area: time formatting in `core/utils/myanmar.dart` / `sale_ui.dart`; `app_bottom_nav.dart`; `settings_features_screen.dart`; `shop_template.dart`.
- Blocks beta: no
- Status: open

## BUG-10 · TC-FEAT-NEW-1 · Low · The v2 restaurant template can be picked at registration
- Found in: round 1 · `mobile/test/qa/qa_app_flows_test.dart` › "TC-FEAT-NEW-1 register step 2: the v2 restaurant template cannot be chosen"
- Steps to reproduce: Register → step 2 → tap "စားသောက် / ကော်ဖီ" (badge v2) → ဆက်သွားမယ်.
- Expected: not selectable (Settings disables it, TC-FEAT-04).
- Actual: step 3 shows "စားသောက် / ကော်ဖီ အတွက်"; a shop with every feature off can be created.
- Suspected area: `register_screen.dart` `_StepShopType._typeCard` (`onTap` ignores `t.soon`).
- Blocks beta: no
- Status: open

## BUG-11 · TC-SEC-04 · Low · Dev SQL Server SA password committed
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
- Status: open
