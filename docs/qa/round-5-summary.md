# QA round 5 — summary (2026-11-14, branch `fix/qa-round-1` @ f5b6e3b)

> **Owner's beta exit rule NOT met.** One Medium bug is open: **BUG-22** (edit form: switching a product with stock to expiry tracking
> leaves that stock outside any batch; POS then sells it from the newest batch, which goes negative). No Critical or High bug is open.
> The owner's exit rule allows Low bugs only. Two ways to clear it: the developer fixes BUG-22 (small validation in the edit form, like
> decision 2 in Add Product), or the owner accepts the pharmacy training rule below and downgrades BUG-22 to Low.

Scope: re-test of BUG-11, BUG-19, BUG-20, BUG-21 (2b74d73) and the owner's three decisions (f5b6e3b: expiry opt-in, batch + expiry for
tracked opening stock, trade-in IMEIs), app and server, incl. two phones against the real API; 7 new cases; full regression of all
138 cases. Docker `zaypos-sql` was up and was not stopped, recreated or changed. Live runs used the scratch database
`ZayPOS_QA_20261114_R5` (migrations via `dotnet ef database update --connection …`, API on 127.0.0.1:5077, dropped at the end; dev
database `ZayPOS`: 0 QA tenants). Backend QA tests use their own Testcontainers SQL Server.

## Totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 4 | 1 | 0 | 0 |
| 4 PROD (+2 since r4, +5 new) | 36 | 2 | 0 | 1 |
| 5 POS | 15 | 0 | 0 | 1 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT | 11 | 0 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC (+2 new) | 25 | 1 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX | 0 | 2 | 0 | 4 |
| **Total (138)** | **125** | **6** | **0** | **7** |

For **Both** cases the PASS covers the automated part; the owner still runs the phone steps.

Full suites at the end of the round:

- `cd mobile && flutter analyze` (own command) → No issues found.
- `cd mobile && flutter test` → **417 passed, 7 skipped, 8 failed**. All 8 failures are QA bug tests: BUG-22 (1, new), BUG-23 (1, new),
  BUG-8 (3), BUG-9 (2), BUG-10 (1). Skipped = the 7 live files (need env vars). The previously failing BUG-19/20 tests and all "pending
  decision" tests pass.
- Live (`ZAYPOS_LIVE_API=http://127.0.0.1:5077`, scratch DB): `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_step4_test.dart`,
  `test/qa/live_qa_round2_test.dart`, `…round3…`, `…round4…`, `test/qa/live_qa_round5_test.dart` → 7/7 passed.
- `cd backend && dotnet test` → Domain.Tests 20/20, Api.Tests 111/111 (incl. the developer's `Trade_in_a_sold_IMEI_received_again…`),
  QA.Tests 29/30 — the 1 failure is BUG-23's server half (`TC_SYNC_NEW_9_…`).
- Note (test, not product): the developer test `m/screens_smoke_test.dart::pay debt sheet records a payment entry` failed once in the first
  full run (14:58 local) and passes alone and in the final run: the fake seed has a payment at `todayAt(14, 58)`, so between 14:57 and
  14:59 two rows read "ယခုလေးတင်". Time-of-day dependent test; sample data only.

## Bug verdicts

| Bug | Verdict | Evidence (short) |
|---|---|---|
| BUG-19 typed IMEI lost in Add Product | **verified** | typed IMEI saved; with a listed one both saved (stock 2, ONE unit); a refused typed IMEI (duplicate / in stock elsewhere) blocks the save with its message, nothing written |
| BUG-20 no-expiry product with batches sold by batch | **verified** | POS: no batch sheet, no expired confirm, line without batch; restock: only "Batch မပါ", no old batches, no new batch; stock = all movements; untracked soap first count = 20 |
| BUG-21 tracked opening stock outside a batch | **verified** | no batch no. → refused; batch no. without expiry → refused (decision 2); both → saved into that batch; stock 0 → no batch needed |
| BUG-11 SA password | **open (owner), partly fixed** | container now on `127.0.0.1:1433` only, not reachable on the Wi-Fi IP, appsettings git-ignored and untracked, 0 copies in HEAD — but the sa password still equals the value in git history (container env equal, appsettings 1 match, `sqlcmd -U sa` with it logs in) |
| Decision 1 expiry opt-in | **verified** | Add Product starts at "သက်တမ်း မမှတ်ပါ", batch fields only after 30/60/90, default saves a plain product; reaches phone B (live) |
| Decision 2 batch + expiry | **verified** | see BUG-21; tracked product with batch + expiry reaches phone B (live) |
| Decision 3 trade-in | **verified** | sold IMEI accepted in Add Product / edit form / "Stock ဖြည့်မယ်" (new inStock row, sold row unchanged), in-stock refused; POS offers it once and sells the new row; server: no issue, history kept; live two phones (A sells, B takes back, A sells again) → no issue, both phones consistent |
| BUG-8, BUG-9, BUG-10 | open (unchanged) | same tests fail |

"Pending owner decisions" in `docs/qa/bugs.md` is resolved (all three verified; the developer's updated tests were read: same purpose,
nothing removed).

## Bugs by severity (open)

Critical — none. High — none.

Medium
- **BUG-22** (TC-PROD-NEW-24, new) — edit form: a product with stock switched to expiry tracking keeps that stock outside batches, no message;
  POS auto-picks the next batch for the old units, and with that batch empty offers only "ကျန် 0" (negative). Decision 1 (default "no expiry")
  makes this the natural way a pharmacy corrects a medicine added without days.

Low
- **BUG-23** (TC-PROD-NEW-26 / TC-SYNC-NEW-9, new) — after a trade-in, voiding the ORIGINAL sale puts the IMEI in stock twice; no check on the
  phone, no `duplicateSerial` on the server. Spec gap, needs a user mistake.
- BUG-8 (TC-UX-04) — Customers filter chips overflow at 320 px.
- BUG-9 (TC-UX-02) — English left (AM/PM, "Report", Settings descriptions).
- BUG-10 (TC-FEAT-NEW-1) — v2 restaurant template selectable at registration.
- BUG-11 (TC-SEC-04) — dev sa password is still the one in git history (now loopback only).

## Release recommendation (3–5 shop beta), per shop type

Exit rule not met (BUG-22, Medium, open), so the release line is not given. Per shop type, with the conditions that keep the beta safe:

| Shop type | Verdict | Reasons | Conditions |
|---|---|---|---|
| Grocery | **Go** | every P1 case passes; no expiry tracking by default | MANUAL list; release `API_BASE_URL` https. If Batch is turned on: do not switch a product that has stock to 30/60/90 days (BUG-22) |
| Hardware | **Go** | decimal sell / restock / low alert pass | as grocery |
| Phone | **Go** | BUG-19 fixed; IMEI receive / sell / trade-in / two-phone sync incl. duplicateSerial verified end to end | do not void a sale whose phone was already taken back (BUG-23, Low) |
| Pharmacy | **Go, with conditions** | BUG-20 / BUG-21 fixed; batches, expiry, expired confirm, opening count, batch + expiry rule pass | BUG-22: when ADDING a medicine pick 30/60/90 days (default is now "သက်တမ်း မမှတ်ပါ"), or add it with stock 0 and receive it by "Stock ဖြည့်မယ်"; never switch a product that has stock to tracking. Fixing BUG-22 first is recommended |
| Fashion | **Go** | variant restock / edit / POS / first count pass | BUG-8 is Customers only (Low) |
| Service / other | **Go** | no stock modules; edit form passes | as grocery |

General conditions: the owner runs the MANUAL list below on a real phone first (UX-01 and UX-05 are P1); release builds pass an https
`API_BASE_URL` (default is still `http://localhost:5076`); rotate the dev sa password (BUG-11) before anyone else uses the Mac.

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01 — delete the app, airplane mode ON, install + open: Login/Register Myanmar text renders (bundled fonts, nothing fetched).
2. TC-PIN-05 — low-end Android, enter the PIN 3×: no stall of the dots/keypad.
3. TC-UX-03 — small phone + largest system font: no overflow, buttons ≥ 44 px (expect the Customers chips, BUG-8; check the restock sheet
   "Batch မပါ" help text and the "ကုန်ခါနီးရင် သတိပေးမယ်" help text).
4. TC-UX-05 — kill the app during checkout: after reopening the whole sale exists or nothing.
5. TC-POS-11 — receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်": share sheet opens / image saved.
6. TC-PROD-13 — product photo and barcode scan (QA expects FAIL: empty handlers, also the IMEI scan button).
7. TC-UX-06 — 1 hour of normal use: no crash, battery/heat acceptable.

Then the phone halves of the **Both** cases, new ones first: TC-SYNC-NEW-10 (sell a phone on A, take it back on B with "Stock ဖြည့်မယ်",
sell it again on A; "စစ်ရန်" stays empty on both), TC-PROD-NEW-25 (take back a sold phone, POS lists its IMEI once), TC-PROD-NEW-24 (after the
BUG-22 fix: pharmacy medicine with stock switched to ရက် ၃၀); from round 4: TC-SYNC-NEW-5, TC-SYNC-NEW-6, TC-PROD-NEW-16; from round 3:
TC-PROD-NEW-6, -7, -8, -9, TC-POS-NEW-5, TC-SYNC-NEW-3; from round 2: TC-PROD-NEW-3, -4, TC-POS-NEW-3, -4, TC-DEBT-NEW-3, -4.

## Docker / dev database state (report only)

`zaypos-sql` Up (created 2026-11-14T08:06Z); `docker port` → `1433/tcp -> 127.0.0.1:1433`. Databases after the round: `ZayPOS`,
`ZayPOS_SchemaRef` (scratch `ZayPOS_QA_20261114_R5` dropped). Nothing in the container was changed. Password comparisons were done by
string compare in the shell; no value was printed or written.

## New test files (round 5)

- `mobile/test/qa/qa_round5_ui_test.dart` — TC-PROD-NEW-22 (2, BUG-19), -23 (2, BUG-20), -24 (1, BUG-22), -25 (1, trade-in at POS),
  -26 (1, BUG-23).
- `mobile/test/qa/qa_round5_drift_test.dart` — TC-PROD-NEW-25 Drift (in-stock IMEI set in SQL; trade-in restock unit carries only the new
  row; records the void unit for TC-PROD-NEW-26 without asserting it).
- `mobile/test/qa/live_qa_round5_test.dart` — live two phones: trade-in on B, sold again on A, no issue, history on both; decisions 1/2
  products reach B.
- `backend/tests/ZayPOS.QA.Tests/QaRound5Tests.cs` — TC_SYNC_NEW_10 (trade-in on B, sold on A: no issue, history kept), TC_SYNC_NEW_9
  (void of the original sale after a trade-in → expected duplicateSerial; FAILS, BUG-23).
