# QA round 1 — summary (2026-11-14, branch `qa/round-1`)

Scope: `docs/qa/test-cases.md` (91 cases) + 8 new cases found during the round. Docker `zaypos-sql` was up; nothing BLOCKED.
Live API runs used a scratch database `ZayPOS_QA_20261114` on port 5077 (dropped at the end; the dev database `ZayPOS` was
not touched). Backend QA tests use their own Testcontainers SQL Server.

## Totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT (+1 new) | 4 | 1 | 0 | 0 |
| 4 PROD (+2 new) | 12 | 2 | 0 | 1 |
| 5 POS (+2 new) | 10 | 2 | 0 | 1 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT (+2 new) | 6 | 2 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC (+1 new) | 16 | 1 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 5 | 1 | 0 | 0 |
| 12 UX | 0 | 2 | 0 | 4 |
| **Total (99)** | **81** | **11** | **0** | **7** |

For **Both** cases the PASS covers the automated part; the owner still runs the phone steps.

Full suites at the end of the round:

- `cd mobile && flutter analyze` → No issues found.
- `cd mobile && flutter test` → **289 passed, 3 skipped, 19 failed**. All 19 failures are the new QA bug tests in
  `mobile/test/qa/` (BUG-1…10); all 241 pre-existing tests pass. Skipped = the 3 `live_*` tests (need env vars).
- Live: `ZAYPOS_LIVE_API=http://127.0.0.1:5077 … flutter test test/live_sync_test.dart / live_api_test.dart / live_step4_test.dart` → 3/3 passed.
- `cd backend && dotnet test` → Domain.Tests 20/20, Api.Tests 108/108 passed.
- `cd backend && dotnet test tests/ZayPOS.QA.Tests/ZayPOS.QA.Tests.csproj` → 18/18 passed (project is not in `ZayPOS.slnx`;
  QA may not edit it — add it there if the owner wants it in the default run).

## Bugs by severity

High
- BUG-1 (TC-PROD-NEW-1) — products cannot be edited after saving (price, cost, name); no edit/delete screen at all.
- BUG-2 (TC-POS-NEW-2) — POS never records the IMEI / size-colour variant / batch sold; IMEIs stay in stock, variant and batch stock never drop.
- BUG-3 (TC-POS-NEW-1) — hardware shop cannot sell a decimal quantity (2.5 ပေ); only whole-unit steppers.

Medium
- BUG-4 (TC-DEBT-NEW-2) — double-tap on the pay-debt button records the payment twice.
- BUG-5 (TC-SYNC-NEW-1) — a phone with its clock ahead keeps its own edit and ignores later edits from other phones.
- BUG-6 (TC-PROD-NEW-2) — Register step 3 promises 300/250/120/200 presets "with barcodes"; server has 20 (grocery, no barcodes) / 0.
- BUG-7 (TC-DEBT-NEW-1) — no credit-limit warning at sale time although Add Customer promises one.

Low
- BUG-8 (TC-UX-04) — overflow at 320 px: Customers filter chips (+12 px), fashion Add Product variants (+11 px).
- BUG-9 (TC-UX-02) — English left: AM/PM times, "Report" tab, Settings/Register descriptions.
- BUG-10 (TC-FEAT-NEW-1) — v2 restaurant template selectable at registration.
- BUG-11 (TC-SEC-04) — dev SQL `sa` password in docs/backend/README.md; container listens on 0.0.0.0:1433.

Not filed (no test evidence yet; for the owner's manual run): photo, barcode-scan, "ကြိုတင်စာရင်း (300) ထဲက ရှာမယ်", KBZ/Wave
screenshot and history date buttons have empty handlers; stock label always says "ခု" (e.g. "2.5 ခု" for feet); sales history
lists today only; release builds default to `API_BASE_URL=http://localhost:5076`.

## Release recommendation: **No-go** for a 3–5 shop beta as built

Reasons
- BUG-1 hits every shop on day one: prices change and typos happen, and there is no way to edit a product.
- BUG-2 makes the phone, fashion and pharmacy templates wrong after the first sale (IMEI / size / batch stock and expiry);
  BUG-3 makes the hardware template unable to sell by length/weight.
- BUG-4 can record one debt payment twice, and the app has no way to correct a ledger entry.

What is solid: auth (OTP, lockout, refresh rotation + grace, replay revocation), tenant isolation, idempotent push,
void/skip rules, pull paging/cursor, offline unlock, receipt numbering (2,500 sales gap-free), ledger math and reports.

**Conditional Go** for a grocery-only beta once BUG-1 and BUG-4 are fixed (and BUG-6's grocery text corrected), with the
owner's MANUAL cases below passing.

## MANUAL cases for the owner, in this order

1. TC-UX-01 — delete the app, airplane mode ON, install and open: Myanmar text renders (fonts bundled; also confirm `google_fonts` fetches nothing).
2. TC-PIN-05 — on the slowest Android available: enter the PIN; no freeze of keypad/dots.
3. TC-UX-03 — iPhone SE / small Android at the largest system font: walk Dashboard, POS, Checkout, Customers, Add Product (expect the BUG-8 overflows).
4. TC-POS-11 — receipt: "Viber ပို့မယ်" opens the share sheet; "ပုံ သိမ်းမယ်" saves an image.
5. TC-PROD-13 — Add Product photo and barcode scan with the camera (QA expects FAIL: empty handlers).
6. TC-UX-05 — start a checkout and kill the app at "အတည်ပြုပြီး ပြေစာထုတ်မယ်"; reopen: full sale or nothing.
7. Then the phone steps of the **Both** cases, two devices on one shop: TC-AUTH-01, 02, 07 → TC-PIN-01, 03 → TC-FEAT-02 →
   TC-PROD-01, 02, 05, 07, 08 (09–11 after BUG-2) → TC-POS-01, 02, 04, 08 → TC-SALE-01, 02, 04 → TC-DEBT-01, 02, 03, 05 →
   TC-RPT-03 → TC-SYNC-01, 02, 03, 05, 15 (06 after BUG-1, 08 after BUG-2) → TC-DEV-01, 02.
8. TC-UX-06 — one hour of normal use at the end.

## New test files

- `mobile/test/qa/qa_app_flows_test.dart` — AUTH-01, AUTH-12, PIN-03, FEAT-02/03/04, PROD-01, FEAT-NEW-1, PROD-NEW-1, PROD-NEW-2
- `mobile/test/qa/qa_pos_ui_test.dart` — POS-01, 04, 07, 08, SALE-04, PROD-02, PROD-12, POS-NEW-1, DEBT-NEW-1, DEBT-NEW-2
- `mobile/test/qa/qa_modules_test.dart` — PROD-11, POS-NEW-2
- `mobile/test/qa/qa_ledger_drift_test.dart` — POS-01/09, POS-10, SALE-01, SALE-03, RPT-01..04, DEBT-01..04, DEBT-06 (in-memory Drift)
- `mobile/test/qa/qa_sync_test.dart` — SYNC-02, SYNC-NEW-1
- `mobile/test/qa/qa_ux_test.dart` — UX-02, UX-04 (320 px)
- `backend/tests/ZayPOS.QA.Tests/` (`ZayPOS.QA.Tests.csproj`, `QaApi.cs`, `QaAuthTests.cs`, `QaSyncSecurityTests.cs`) —
  AUTH-01/03/05/06/09, FEAT-01, DEV-04, POS-10, SEC-01/02/03, SYNC-NEW-1 (server half)
