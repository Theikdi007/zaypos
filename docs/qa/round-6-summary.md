# QA round 6 — summary (2026-11-14, branch `fix/qa-round-1` @ 667a0e2)

> ## Ready for beta
>
> Owner's exit rule met: **no Critical, High or Medium bug is open.** Open: four Low bugs (BUG-8, BUG-9, BUG-10, and the new BUG-24) and
> one accepted risk (BUG-11, dev SA password; owner decision). BUG-22 (Medium) and BUG-23 (Low) are fixed and verified on the app, the
> local database, the server and two phones against the real API.
> Before any shop uses it, the owner still has to run the MANUAL list below on a real phone (UX-01 and UX-05 are P1) and build releases
> with an https `API_BASE_URL`.

Scope: re-test of BUG-22 and BUG-23 (667a0e2) with edge cases, BUG-11 binding re-confirmed (accepted risk), 5 new cases, full regression
of all 143 cases. Docker `zaypos-sql` was up and was not stopped, recreated or changed. Live runs used the scratch database
`ZayPOS_QA_20261114_R6` (migrations via `dotnet ef database update --connection …`, API on 127.0.0.1:5077, dropped at the end by name;
remaining databases `ZayPOS`, `ZayPOS_SchemaRef`; dev database `ZayPOS`: 0 QA tenants). Backend QA tests use their own Testcontainers
SQL Server. No product code was changed.

## Totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 4 | 1 | 0 | 0 |
| 4 PROD (+2 fixed since r5, +3 new) | 40 | 1 | 0 | 1 |
| 5 POS | 15 | 0 | 0 | 1 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT | 11 | 0 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC (+1 fixed since r5, +2 new) | 28 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX | 0 | 2 | 0 | 4 |
| **Total (143)** | **132** | **4** | **0** | **7** |

FAIL rows: TC-FEAT-NEW-1 (BUG-10), TC-PROD-NEW-29 (BUG-24, new), TC-UX-02 (BUG-9), TC-UX-04 (BUG-8) — all Low.
For **Both** cases the PASS covers the automated part; the owner still runs the phone steps.

Full suites at the end of the round:

- `cd mobile && flutter analyze` (own command) → No issues found.
- `cd mobile && flutter test` → **432 passed, 8 skipped, 7 failed**. All 7 failures are QA bug tests: BUG-24 (1, new), BUG-8 (3), BUG-9 (2),
  BUG-10 (1). Skipped = the 8 live files (need env vars). The round-5 BUG-22 / BUG-23 tests now pass.
- Live (`ZAYPOS_LIVE_API=http://127.0.0.1:5077`, scratch DB): `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_step4_test.dart`,
  `test/qa/live_qa_round2_test.dart` … `round5`, `test/qa/live_qa_round6_test.dart` → 8/8 passed. (The round-4 file was first started with
  the OTP of another phone by QA — operator error, "otp" refused; re-run with its own code → passed.)
- `cd backend && dotnet test` → Domain.Tests 20/20, Api.Tests 111/111, QA.Tests 32/32 (incl. `TC_SYNC_NEW_9_…`, failing in round 5).

## Bug verdicts

| Bug | Verdict | Evidence (short) |
|---|---|---|
| BUG-22 edit form: stock outside batches after switching to tracking | **verified** | refused without batch no. or expiry (exact message), existing batch no. refused (also with spaces); with both: ONE upsertProduct, opening batch holds the loose stock, 0 loose, product stock unchanged, per size for fashion; POS takes the opening batch; Drift outbox unit and server (no issue) and phone B (live) agree |
| BUG-23 void of the original sale after a trade-in | **verified** | old row stays sold with its line, traded-in line not returned, other lines are; un-void / re-void mirror it; POS offers the IMEI once; server: void pushed before the trade-in → duplicateSerial (both orders), normal void not flagged; live two phones consistent |
| BUG-11 dev SA password | **accepted risk (owner)** | re-confirmed: `127.0.0.1:1433` only, Wi-Fi IP not reachable; container untouched; password not printed |
| BUG-8, BUG-9, BUG-10 | open (unchanged, Low) | same tests fail |
| BUG-24 (new) | **open, Low** | trade-in resold, then sale 1 voided → phantom IMEI in stock |

## Bugs by severity (open)

Critical — none. High — none. Medium — none.

Low
- **BUG-24** (TC-PROD-NEW-29, new) — phone taken back (trade-in) and sold again, then the ORIGINAL sale is voided: the old IMEI row goes back
  in stock (+1), POS offers a phone that is with customer 2; the server raises nothing. Needs a user mistake; phone shops only.
- BUG-8 (TC-UX-04) — Customers filter chips overflow at 320 px.
- BUG-9 (TC-UX-02) — English left (AM/PM, "Report", Settings descriptions).
- BUG-10 (TC-FEAT-NEW-1) — v2 restaurant template selectable at registration.

Accepted risk: BUG-11 (TC-SEC-04) — dev sa password still the one in git history; loopback only.

## Release recommendation (3–5 shop beta), per shop type

**Go** for the beta under the owner's exit rule. Per shop type:

| Shop type | Verdict | Reasons | Conditions |
|---|---|---|---|
| Grocery | **Go** | every P1 case passes; expiry tracking is opt-in | MANUAL list; release `API_BASE_URL` https |
| Hardware | **Go** | decimal sell / restock / low alert pass | as grocery |
| Pharmacy | **Go** | BUG-20/21/22 fixed: batches, expiry, expired confirm, opening count, batch + expiry for opening stock in Add Product and in the edit form | train: a tracked medicine with stock outside batches cannot be saved (even a price change) until that stock gets a batch no. + expiry — this is the fix working, not an error |
| Phone | **Go** | IMEI receive / sell / trade-in / void / two-phone sync incl. duplicateSerial verified end to end | BUG-24 (Low): do not void an old sale after the phone was taken back and sold again; if it happens, count the phone out with a stock adjustment |
| Fashion | **Go** | variant restock / edit / POS / first count pass; opening batch keeps size stock | BUG-8 is the Customers screen on 320 px phones only |
| Service / other | **Go** | no stock modules; edit form passes | as grocery |

General conditions: the owner runs the MANUAL list below on a real phone first; release builds pass an https `API_BASE_URL` (default is
still `http://localhost:5076`); rotate the dev sa password (BUG-11) before anyone else uses the Mac.

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01 — delete the app, airplane mode ON, install + open: Login/Register Myanmar text renders (bundled fonts, nothing fetched).
2. TC-UX-05 — kill the app during checkout: after reopening the whole sale exists or nothing.
3. TC-PIN-05 — low-end Android, enter the PIN 3×: no stall of the dots/keypad.
4. TC-UX-03 — small phone + largest system font: no overflow, buttons ≥ 44 px (expect the Customers chips, BUG-8; check the new
   opening-batch note in the edit form wraps).
5. TC-POS-11 — receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်": share sheet opens / image saved.
6. TC-PROD-13 — product photo and barcode scan (QA expects FAIL: empty handlers, also the IMEI scan button).
7. TC-UX-06 — 1 hour of normal use: no crash, battery/heat acceptable.

Then the phone halves of the **Both** cases, new ones first: TC-PROD-NEW-27 (pharmacy: medicine with stock → edit → "ရက် ၃၀ အလို" → save
empty, then batch no. + expiry → phone B shows the batch), TC-PROD-NEW-28 (sell a phone + a cover, take the phone back, void the sale),
TC-SYNC-NEW-12 (two phones in airplane mode: A voids a phone sale while B takes the phone back, then online → "စစ်ရန်" on both);
from round 5: TC-SYNC-NEW-10, TC-PROD-NEW-25, TC-PROD-NEW-24; round 4: TC-SYNC-NEW-5, TC-SYNC-NEW-6, TC-PROD-NEW-16; round 3:
TC-PROD-NEW-6, -7, -8, -9, TC-POS-NEW-5, TC-SYNC-NEW-3; round 2: TC-PROD-NEW-3, -4, TC-POS-NEW-3, -4, TC-DEBT-NEW-3, -4.

## New test files (round 6)

- `mobile/test/qa/qa_round6_ui_test.dart` — TC-PROD-NEW-27 (5 tests, BUG-22 edge cases), TC-PROD-NEW-28 (2 tests, BUG-23 edge cases),
  TC-PROD-NEW-29 (1 test, BUG-24 — fails).
- `mobile/test/qa/qa_round6_drift_test.dart` — TC-PROD-NEW-27 Drift (the real edit form on Drift; ONE outbox unit, wire shape recorded),
  TC-PROD-NEW-28 Drift (void / un-void units after a trade-in).
- `mobile/test/qa/live_qa_round6_test.dart` — live two phones: opening batch reaches B; void after a trade-in; void and trade-in crossing
  offline → duplicateSerial on both.
- `backend/tests/ZayPOS.QA.Tests/QaRound6Tests.cs` — TC_SYNC_NEW_11 (opening-batch unit), TC_SYNC_NEW_12 (void / trade-in both orders,
  normal void not flagged).
