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
- Status: open

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
- Status: open

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
