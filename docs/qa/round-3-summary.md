# QA round 3 — summary (2026-11-14, branch `fix/qa-round-1` @ 177dcf0)

Scope: re-test of BUG-12 and BUG-11; the two items noted in round 2 filed and verified (BUG-13 expired batch, BUG-14 cleared low
alert); 12 new cases for the new behaviour (restock per module type, edit-form additions, expired batches, cleared alert, sync of
the new units incl. the server side); full regression of all 120 cases. Docker `zaypos-sql` was up; nothing BLOCKED. Live runs used
a scratch database `ZayPOS_QA_20261114_R3` on API port 5077 (dropped at the end; dev database `ZayPOS` not touched — checked:
0 QA rows in it). The `zaypos-sql` container was not stopped, recreated or changed. Backend QA tests use their own Testcontainers SQL Server.

## Totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 4 | 1 | 0 | 0 |
| 4 PROD (+8 new) | 22 | 3 | 0 | 1 |
| 5 POS (+1 new) | 15 | 0 | 0 | 1 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT | 11 | 0 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC (+3 new) | 21 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX | 0 | 2 | 0 | 4 |
| **Total (120)** | **107** | **6** | **0** | **7** |

For **Both** cases the PASS covers the automated part; the owner still runs the phone steps.

Full suites at the end of the round:

- `cd mobile && flutter analyze` → No issues found.
- `cd mobile && flutter test` → **373 passed, 5 skipped, 10 failed**. All 10 failures are QA bug tests: BUG-15 (2, new), BUG-16 (1, new),
  BUG-17 (1, new), BUG-8 (3, Customers chips), BUG-9 (2), BUG-10 (1). Skipped = the 5 live files (need env vars).
  The 3 BUG-12 tests from round 2 now pass.
- Live (`ZAYPOS_LIVE_API=http://127.0.0.1:5077`, scratch DB): `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_step4_test.dart`,
  `test/qa/live_qa_round2_test.dart`, `test/qa/live_qa_round3_test.dart` → 5/5 passed.
- `cd backend && dotnet test` → Domain.Tests 20/20, Api.Tests 108/108, QA.Tests 24/24 passed.

## Bug verdicts

| Bug | Verdict | Why |
|---|---|---|
| BUG-12 restock of IMEI / batch / size products | **verified** | r2 tests pass; r3: exact IMEIs offered and sold, dup IMEIs refused, default batch = newest unexpired, new batch with the picked date sold first, variant stock = product stock, edit form adds without changing / deleting; outbox = only new rows; server applies + B pulls; live two phones |
| BUG-11 SA password | **repository verified; stays open (owner)** | HEAD has only `<YOUR_DEV_SA_PASSWORD>`; old value in 4 history commits and still the running container's sa password; container on `0.0.0.0:1433`, reachable on the Wi-Fi IP |
| BUG-13 expired batch at POS (filed from r2) | **verified** | expiry day itself auto-picked; past day never auto-picked, red + badge, listed last, explicit confirm, dismiss = cancel; correct after a Drift round trip |
| BUG-14 cleared low alert (filed from r2) | **verified** | 0 saved (also hardware decimal), not "low", empty on reopen; 0 on the wire, server + phone B take it |
| BUG-8, BUG-9, BUG-10 | open (unchanged) | same tests fail as in round 2 |

## Bugs by severity (open)

Medium
- BUG-15 (TC-PROD-NEW-11, new) — pharmacy (Batch on) and size/colour products: the first count of an untracked product is a restock, so
  "sold 1, counted 20" shows 19. Breaks the P1 rule of TC-PROD-05/06 for these shops.
- BUG-17 (TC-PROD-NEW-13, new) — edit form: an IMEI typed / scanned but not "+ ထည့်"-ed is silently dropped on save (phone not in stock).

Low
- BUG-16 (TC-PROD-NEW-12, new) — "+ Batch အသစ်" in restock accepts an existing batch number (two identical "B1" rows).
- BUG-18 (TC-SYNC-NEW-5, new, spec gap) — the same IMEI received on two phones offline = two in-stock rows, no issue raised.
- BUG-8 (TC-UX-04) — Customers filter chips overflow at 320 px.
- BUG-9 (TC-UX-02) — English left (AM/PM, "Report", Settings descriptions).
- BUG-10 (TC-FEAT-NEW-1) — v2 restaurant template selectable at registration.
- BUG-11 (TC-SEC-04) — dev sa password still the one in git history; container reachable on the Wi-Fi (owner action).

No Critical or High bug is open.

## Release recommendation (3–5 shop beta), per shop type

| Shop type | Verdict | Reasons | Conditions |
|---|---|---|---|
| Grocery | **Go** | every P1 case passes; Batch / IMEI / Size off by default, so BUG-15/16/17 do not apply | MANUAL list below; release `API_BASE_URL` https; keep "သက်တမ်းကုန်ရက် / Batch" off (turning it on routes every restock through the batch sheet and BUG-15) |
| Hardware | **Go** | decimal sell / restock / low alert (2.5 → 0 → 0.75) pass; no module features | as grocery |
| Phone | **Go, with conditions** | BUG-12 fixed end to end incl. two phones and the server; IMEI products are always tracked, so BUG-15 does not apply | tell the shop to receive phones with "Stock ဖြည့်မယ်" (not by typing in the edit form, BUG-17) — or fix BUG-17 first (recommended, small); one phone receives a delivery (BUG-18) |
| Pharmacy | **No-go as is → Go once BUG-15 is fixed** | BUG-12 and BUG-13 fixed (batches, expiry, expired-batch confirm all pass), but TC-PROD-NEW-11 (P1 rule) fails for every product of the shop | if the owner accepts a workaround instead of the fix: every product is added with its opening stock + batch (never sold while "Stock မမှတ်ရသေး"); note every non-batch item (soap, diapers) also needs a batch number on each delivery (owner decision) |
| Fashion | **No-go as is → Go once BUG-15 is fixed** | variant restock / edit / POS pass; an untracked size product shows the wrong count after the first count (P1 rule) | same workaround as pharmacy (enter size stock when adding the product); BUG-8 is on Customers only |
| Service / other | **Go** | no stock modules (service: quick sale + service items); edit form passes for both templates (TC-PROD-NEW-3) | as grocery |

General conditions for every shop: the owner runs the MANUAL list below on a real phone first (UX-01 and UX-05 are P1); release builds
pass an https `API_BASE_URL` (default is still `http://localhost:5076`); recreate `zaypos-sql` on 127.0.0.1 with a new password before
phones share the Mac's Wi-Fi (BUG-11).

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01 — delete the app, airplane mode ON, install + open: Login/Register Myanmar text renders (bundled fonts, nothing fetched).
2. TC-PIN-05 — low-end Android, enter the PIN 3×: no stall of the dots/keypad.
3. TC-UX-03 — small phone + largest system font: no overflow, buttons ≥ 44 px (expect the Customers chips, BUG-8; also check the new
   restock sheet with its keypad and the edit-form IMEI / batch / size sections).
4. TC-UX-05 — kill the app during checkout: after reopening the whole sale exists or nothing.
5. TC-POS-11 — receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်": share sheet opens / image saved.
6. TC-PROD-13 — product photo and barcode scan (QA expects FAIL: empty handlers).
7. TC-UX-06 — 1 hour of normal use: no crash, battery/heat acceptable.

Then the phone halves of the **Both** cases, new ones first: TC-PROD-NEW-6 (scan 2 IMEIs into "Stock ဖြည့်မယ်" with a real scanner /
keyboard), TC-PROD-NEW-7 (new batch: pick the expiry in the calendar), TC-PROD-NEW-8, TC-PROD-NEW-9 (edit form: add an IMEI with
"+ ထည့်", a batch, a size), TC-POS-NEW-5 (expired batch: red badge readable, confirm dialog), TC-SYNC-NEW-3 (receive 2 phones on A, sell one
on B); then from round 2: TC-PROD-NEW-3, TC-PROD-NEW-4, TC-POS-NEW-3, TC-POS-NEW-4, TC-DEBT-NEW-3, TC-DEBT-NEW-4.

## New test files (round 3)

- `mobile/test/qa/qa_round3_ui_test.dart` — TC-PROD-NEW-6 (2), TC-PROD-NEW-7 (4: 2 PASS, BUG-15, BUG-16), TC-PROD-NEW-8 (2: 1 PASS,
  BUG-15), TC-PROD-NEW-9 (4: 3 PASS, BUG-17), TC-POS-NEW-5 (3), TC-PROD-NEW-10 (1).
- `mobile/test/qa/qa_round3_drift_test.dart` — outbox of receive() and of the edit form's update() (only new rows, nothing deleted,
  lowAlertMilli 0), expiry after the Drift round trip (3 tests).
- `mobile/test/qa/live_qa_round3_test.dart` — live: two phones, restock units with IMEIs / new batch + edit-form unit reach B; B sells a
  received IMEI; A sees it sold.
- `backend/tests/ZayPOS.QA.Tests/QaRound3Tests.cs` — TC_SYNC_NEW_3, TC_SYNC_NEW_4, TC_SYNC_NEW_5 (server halves).

Note on QA's own test: the first run of TC-PROD-NEW-6 failed because the test tapped "+ ထည့်" in the same frame as `enterText`
(button still disabled from the empty field); a real user always gets a frame in between, so a `pump()` was added — not a product bug.
