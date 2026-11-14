# QA round 2 — summary (2026-11-14, branch `fix/qa-round-1`)

Scope: re-test of the round-1 FAILs (BUG-1..7, BUG-11) after the developer's fixes, 9 new cases for the new behaviour, and a full
regression of `docs/qa/test-cases.md` (now 108 cases). Docker `zaypos-sql` was up; nothing BLOCKED. Live API runs used a scratch
database `ZayPOS_QA_20261114_R2` on port 5077 (dropped at the end; the dev database `ZayPOS` was not touched). The `zaypos-sql`
container was not stopped or recreated. Backend QA tests use their own Testcontainers SQL Server.

## Totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 4 | 1 | 0 | 0 |
| 4 PROD (+3 new) | 16 | 1 | 0 | 1 |
| 5 POS (+2 new) | 14 | 0 | 0 | 1 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT (+3 new) | 11 | 0 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC (+1 new) | 18 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 5 | 1 | 0 | 0 |
| 12 UX | 0 | 2 | 0 | 4 |
| **Total (108)** | **96** | **5** | **0** | **7** |

For **Both** cases the PASS covers the automated part; the owner still runs the phone steps.

Full suites at the end of the round:

- `cd mobile && flutter analyze` → No issues found.
- `cd mobile && flutter test` → **345 passed, 4 skipped, 9 failed**. The 9 failures are all QA bug tests:
  BUG-12 (3, new), BUG-8 (3, Customers chips), BUG-9 (2), BUG-10 (1). Skipped = the 4 live tests (need env vars).
- Live (`ZAYPOS_LIVE_API=http://127.0.0.1:5077`): `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_step4_test.dart`,
  `test/qa/live_qa_round2_test.dart` → 4/4 passed.
- `cd backend && dotnet test` → Domain.Tests 20/20, Api.Tests 108/108, QA.Tests 21/21 passed (QA project now in `ZayPOS.slnx`).

## Re-test of round-1 bugs

| Bug | Verdict | Why |
|---|---|---|
| BUG-1 edit product | verified | 7 templates + preset: prefilled form, one upsertProduct, fields/stock/modules kept; server + live B pulls the edit |
| BUG-2 IMEI / variant / batch at POS | verified | chosen IMEI sold / variant / batch drop (UI + Drift + unit rows), FEFO order, void gives them back. Restock gap → BUG-12 |
| BUG-3 decimal qty | verified | "." only with decimalQty, max 3 dp, 2.5 × 600 = 1,500 stored as 2,500 milli; restock 2.5 |
| BUG-4 double pay + reversal | verified | one payment on double-tap; reversal = +adjustment with derived id; two phones offline → one row on server and both phones |
| BUG-5 clock ahead | verified | realistic test (phone clock +1 h, serverTime from the answer): local rows clamped, later edits from B taken; server sends UTC "…Z" |
| BUG-6 presets | verified | step 3 promises 20 (grocery) / nothing; no barcode text; dead button gone |
| BUG-7 credit-limit warning | verified | at limit / no limit: none; 1 Ks over: warning, sale still saved |
| BUG-11 SA password | **reopened** | docs fixed, but the committed password is the running container's and `nc` reaches 1433 on the Mac's Wi-Fi IP |
| BUG-8 | still partly open | fashion form fixed; Customers chips overflow (3 tests) |
| BUG-9, BUG-10 | open (left on purpose) | tests still fail as in round 1 |

Flaky-test claim (TC-DEBT-01..04, `m/qa/qa_ledger_drift_test.dart`): **confirmed — the QA test was wrong, not the product.**
Run alone it failed 10/10 on this branch and 5/5 on the untouched `qa/round-1` commit (`Expected: <52000> Actual: <0>` on the first
read); in the directory run it failed once and passed once. Cause: `customerAccountsProvider` joins three independent Drift streams
(customers, ledger, balances); a single `settled()` right after the write can return the new customer joined with the old balances
map. Fixed in the test only: that step now waits with `until()` like the others and also checks the SQL balance directly. After the fix:
10/10 passes alone. (A one-frame "0" could flash on a real screen; not filed — no user-visible evidence.)

## Bugs by severity (open)

High
- BUG-12 (TC-PROD-NEW-5, new) — goods received for IMEI / batch / size-colour products are a bare quantity: a restocked phone cannot
  be sold at all ("ရောင်းစရာ IMEI မကျန်တော့ပါ"), received medicine has no batch / expiry, received clothes belong to no size.

Low
- BUG-8 (TC-UX-04) — Customers filter chips overflow at 320 px.
- BUG-9 (TC-UX-02) — English left (AM/PM, "Report", Settings descriptions).
- BUG-10 (TC-FEAT-NEW-1) — v2 restaurant template selectable at registration.
- BUG-11 (TC-SEC-04, reopened) — committed dev `sa` password = live container password, container reachable on the Wi-Fi.

Not filed (no spec line; owner to decide): an expired batch is offered first and auto-picked when it is the only one with stock,
without an "expired" mark; clearing "နည်းရင် သတိပေး" in the edit form keeps the old value; release builds still default to
`API_BASE_URL=http://localhost:5076` (round-1 note).

## Release recommendation

**Grocery + hardware beta (3–5 shops): Go**, with conditions.
- Every P1 case for these templates passes (selling, decimal quantities, debt incl. reversal, sync incl. clock skew, edit, restock).
- Open bugs that touch them are Low (BUG-8/9/10). BUG-12 does not apply as long as these shops keep "သက်တမ်းကုန်ရက် / Batch",
  "IMEI / Serial" and "Size / အရောင်" **off** in Settings (a grocery shop that turns Batch on hits BUG-12).
- Conditions: the owner runs the MANUAL list below on a real phone first (UX-01 and UX-05 are P1); release builds use an https
  `API_BASE_URL`; fix BUG-11 on the Mac before phones share its Wi-Fi.

**Pharmacy, phone and fashion beta: No-go.**
- BUG-12 (High, P1): the first delivery after setup breaks selling (phone), batch/expiry tracking (pharmacy) or size stock (fashion).
  BUG-2 itself is fixed, so these shops are blocked only by BUG-12 (plus the expired-batch question for pharmacy).

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01 — delete the app, airplane mode ON, install + open: Login/Register Myanmar text renders (bundled fonts, nothing fetched).
2. TC-PIN-05 — low-end Android, enter the PIN 3×: no stall of the dots/keypad.
3. TC-UX-03 — small phone + largest system font: no overflow, buttons ≥ 44 px (expect the Customers chips, BUG-8).
4. TC-UX-05 — kill the app during checkout: after reopening the whole sale exists or nothing.
5. TC-POS-11 — receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်": share sheet opens / image saved.
6. TC-PROD-13 — product photo and barcode scan (QA expects FAIL: empty handlers).
7. TC-UX-06 — 1 hour of normal use: no crash, battery/heat acceptable.

Then the phone halves of the new **Both** cases: TC-PROD-NEW-3 (edit a price on A, sync, B shows it = TC-SYNC-06), TC-PROD-NEW-4
(stock badge is easy to hit), TC-POS-NEW-3 (hardware: sell 2.5 ပေ), TC-POS-NEW-4 (pick a size / batch / IMEI), TC-DEBT-NEW-3 (reverse a
payment), TC-DEBT-NEW-4 (both phones in airplane mode reverse the same payment, then online: one reversal).

## New test files (round 2)

- `mobile/test/qa/qa_round2_ui_test.dart` — TC-PROD-NEW-3 (8), TC-PROD-NEW-4 (2), TC-PROD-NEW-5 (3, FAIL = BUG-12), TC-POS-NEW-4 (3),
  TC-POS-NEW-3 (2), TC-DEBT-NEW-3 (1), TC-DEBT-NEW-5 (3).
- `mobile/test/qa/qa_round2_drift_test.dart` — TC-POS-NEW-4 Drift, TC-DEBT-NEW-4 (two phones), TC-SYNC-NEW-2 (2).
- `mobile/test/qa/live_qa_round2_test.dart` — live: two phones reverse one payment offline; product edit reaches B.
- `backend/tests/ZayPOS.QA.Tests/QaRound2Tests.cs` — TC_DEBT_NEW_4, TC_SYNC_NEW_2, TC_PROD_NEW_3 (server halves).
- Changed: `mobile/test/qa/qa_ledger_drift_test.dart` (TC-DEBT-01..04 timing fix, see above).
