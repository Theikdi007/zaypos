# QA round 4 — summary (2026-11-14, branch `fix/qa-round-1` @ f3a7e0f)

Scope: re-test of BUG-15, BUG-16, BUG-17, BUG-18 (server 1ee4e61 + app f3a7e0f) and the owner's pharmacy decision (item 5); 9 new
cases; full regression of all 129 cases. Docker `zaypos-sql` was up (not stopped, recreated or changed; state below). Live runs used a
scratch database `ZayPOS_QA_20261114_R4` (created with `dotnet ef database update --connection …`, API on 127.0.0.1:5077, dropped at the
end; dev database `ZayPOS` checked: 0 round-4 tenants). Backend QA tests use their own Testcontainers SQL Server.

## Totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 4 | 1 | 0 | 0 |
| 4 PROD (+6 new) | 28 | 3 | 0 | 1 |
| 5 POS | 15 | 0 | 0 | 1 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT | 11 | 0 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC (+3 new) | 24 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX | 0 | 2 | 0 | 4 |
| **Total (129)** | **116** | **6** | **0** | **7** |

For **Both** cases the PASS covers the automated part; the owner still runs the phone steps.

Full suites at the end of the round:

- `cd mobile && flutter analyze` → No issues found.
- `cd mobile && flutter test` → **397 passed, 6 skipped, 10 failed**. All 10 failures are QA bug tests: BUG-19 (1, new), BUG-20 (2, new),
  BUG-21 (1, new), BUG-8 (3), BUG-9 (2), BUG-10 (1). Skipped = the 6 live files (need env vars). The 4 round-3 tests of BUG-15/16/17 now pass.
- Live (`ZAYPOS_LIVE_API=http://127.0.0.1:5077`, scratch DB): `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_step4_test.dart`,
  `test/qa/live_qa_round2_test.dart`, `test/qa/live_qa_round3_test.dart`, `test/qa/live_qa_round4_test.dart` → 6/6 passed.
- `cd backend && dotnet test` → Domain.Tests 20/20, Api.Tests 110/110, QA.Tests 28/28 passed.

## Bug verdicts

| Bug | Verdict | Evidence (short) |
|---|---|---|
| BUG-15 first count of untracked batch / size product | **verified** | 20 in the counted batch / size, 0 elsewhere, one "opening count" adjustment, ONE stockAdjust unit; server applies it, phone B shows 20 (live) |
| BUG-16 duplicate batch no. in restock | **verified** | "B1" and " B1 " refused with the message, nothing written, sheet stays; "B2" saves |
| BUG-17 typed IMEI lost in the edit form | **verified (edit form)** | typed IMEI / batch no. saved; size without colour or a known IMEI blocks save with the message. Same gap in Add Product → BUG-19 |
| BUG-18 same IMEI on two phones | **verified end to end** | server: one `duplicateSerial` on the later row, re-push adds none, per shop only; live: two app instances offline → sync → ONE issue on both phones, both rows kept, resolve on A reaches B; app refuses an IMEI it knows (also a sold one) |
| BUG-11 SA password | open (owner) | unchanged: container on `0.0.0.0:1433` / `[::]:1433`, password still the one in history, reachable on the Wi-Fi IP |
| BUG-8, BUG-9, BUG-10 | open (unchanged) | same tests fail |

## Item 5 (owner's pharmacy decision) — QA judgement

Decision: "batches are required only for products with expiryAlertDays set; products without it (soap etc.) sell and restock like plain
products even when the Batch feature is on; Add/Edit form text explains this."

- **Met:** "သက်တမ်း မမှတ်ပါ" option, batch fields hidden, help text, null saved and round-tripped in the edit form (TC-PROD-NEW-16);
  a product without expiryAlertDays and without batches restocks "Batch မပါ" by default and sells without a batch sheet — also in a
  grocery that turned Batch on (TC-PROD-NEW-17); expiry-tracked products get no "Batch မပါ" and need a batch at restock.
- **Not met — the developer's interpretation:** a product without expiryAlertDays that HAS batches is still sold by batch (TC-PROD-NEW-18,
  BUG-20): the only choice can be an empty batch that goes negative, and an expired old batch brings the "expired" confirm on every sale of a
  soap. That contradicts "sell … like plain products". The products concerned are exactly those the owner is likely to correct: Add Product
  defaults to "ရက် ၃၀ အလို", so a soap saved with the default and a batch, then switched to "သက်တမ်း မမှတ်ပါ", keeps the batch picker. The
  stated reason (QA's round-2/3 tests expect it) is not a product reason; those fixtures were medicines and now set `expiryAlertDays: 30`, so
  the developer can implement the decision literally without breaking QA tests.
- **Also not met:** "required" for expiry-tracked products is enforced at restock but not in Add Product — opening stock of a tracked
  product is saved outside any batch (TC-PROD-NEW-19, BUG-21).

Verdict: the interpretation meets the decision for new, correctly classified products only; it does not fully meet it. Recommended
fix: POS sells a product without expiryAlertDays as plain (or offers its batches with stock plus "Batch မပါ"), its restock defaults to
"Batch မပါ", and Add Product requires a batch no. when a tracked product gets opening stock. The owner should confirm this reading.

## Bugs by severity (open)

Medium
- BUG-19 (TC-PROD-NEW-15, new) — Add Product: an IMEI typed / scanned but not "+"-ed is dropped; the phone is saved with no IMEI, stock 0.
- BUG-20 (TC-PROD-NEW-18, new) — a no-expiry product that has batches is still sold by batch (empty batch goes negative; expired-batch
  confirm on soap). Item-5 interpretation.
- BUG-21 (TC-PROD-NEW-19, new) — Add Product saves an expiry-tracked product's opening stock outside any batch.

Low
- BUG-8 (TC-UX-04) — Customers filter chips overflow at 320 px.
- BUG-9 (TC-UX-02) — English left (AM/PM, "Report", Settings descriptions).
- BUG-10 (TC-FEAT-NEW-1) — v2 restaurant template selectable at registration.
- BUG-11 (TC-SEC-04) — dev sa password is the one in git history; container reachable on the Wi-Fi (owner action).

No Critical or High bug is open. Notes (not bugs): two new rows with one IMEI in a single unit give 2 `duplicateSerial` issues (the app
never sends that); the app refuses a SOLD IMEI as new, so a traded-in phone cannot be re-received under its IMEI although the server
accepts it — owner to decide.

## Release recommendation (3–5 shop beta), per shop type

| Shop type | Verdict | Reasons | Conditions |
|---|---|---|---|
| Grocery | **Go** | every P1 case passes; with Batch turned on, products without batches now restock / sell plain (TC-PROD-NEW-17) | MANUAL list below; release `API_BASE_URL` https. If Batch is turned on, add non-expiring items with "သက်တမ်း မမှတ်ပါ" (BUG-20/21) |
| Hardware | **Go** | decimal sell / restock / low alert pass; no module features | as grocery |
| Phone | **Go, with conditions** | IMEI receive / sell / two-phone sync incl. duplicateSerial verified end to end; BUG-17 fixed | BUG-19: in Add Product always tap "+" / Enter and check the IMEI list before saving (or fix first — small, recommended); decide on trade-in IMEIs |
| Pharmacy | **Go, with conditions** (was No-go) | BUG-15 fixed; batches, expiry, expired-batch confirm, opening count pass; two medium gaps in item 5 (BUG-20, BUG-21) affect only mis-classified products and stock entered without a batch | train the shop: (1) medicines: add with batch no. + expiry, or with stock 0 and receive by "Stock ဖြည့်မယ်"; (2) non-medicines: choose "သက်တမ်း မမှတ်ပါ" when adding, never give them a batch, never switch a product that already has batches. Fixing BUG-20 and BUG-21 before the pharmacy beta is recommended |
| Fashion | **Go** (was No-go) | BUG-15 fixed: untracked size products count correctly; variant restock / edit / POS pass | BUG-8 is Customers only (Low) |
| Service / other | **Go** | no stock modules; edit form passes for both templates | as grocery |

General conditions: the owner runs the MANUAL list below on a real phone first (UX-01 and UX-05 are P1); release builds pass an https
`API_BASE_URL` (default is still `http://localhost:5076`); recreate `zaypos-sql` on 127.0.0.1 with a new password before phones share the
Mac's Wi-Fi (BUG-11).

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01 — delete the app, airplane mode ON, install + open: Login/Register Myanmar text renders (bundled fonts, nothing fetched).
2. TC-PIN-05 — low-end Android, enter the PIN 3×: no stall of the dots/keypad.
3. TC-UX-03 — small phone + largest system font: no overflow, buttons ≥ 44 px (expect the Customers chips, BUG-8; also the restock sheet
   with "Batch မပါ" and the long pharmacy help text under "ကုန်ခါနီးရင် သတိပေးမယ်").
4. TC-UX-05 — kill the app during checkout: after reopening the whole sale exists or nothing.
5. TC-POS-11 — receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်": share sheet opens / image saved.
6. TC-PROD-13 — product photo and barcode scan (QA expects FAIL: empty handlers).
7. TC-UX-06 — 1 hour of normal use: no crash, battery/heat acceptable.

Then the phone halves of the **Both** cases, new ones first: TC-SYNC-NEW-5 (two phones in airplane mode receive one IMEI → online →
"စစ်ရန်" on both shows 'IMEI / Serial တူ ဖုန်း နှစ်လုံး stock ထဲ ရှိနေ'; mark it checked on A, it goes on B), TC-SYNC-NEW-6 (pharmacy: sell an
unrecorded medicine, then count 20 into a new batch on A; B shows 20), TC-PROD-NEW-16 (read the pharmacy help text); then from round 3:
TC-PROD-NEW-6, -7, -8, -9, TC-POS-NEW-5, TC-SYNC-NEW-3; from round 2: TC-PROD-NEW-3, -4, TC-POS-NEW-3, -4, TC-DEBT-NEW-3, -4.

## Docker / dev database state (report only)

`zaypos-sql` Up; `docker port` → `1433/tcp -> 0.0.0.0:1433`, `[::]:1433`. Databases after the round: `ZayPOS`, `ZayPOS_SchemaRef`
(scratch `ZayPOS_QA_20261114_R4` dropped). Nothing in the container was changed.

## New / changed test files (round 4)

- `mobile/test/qa/qa_round4_ui_test.dart` — TC-PROD-NEW-11 (3), -12 (1), -13 (3), -14 (1), -15 (1, BUG-19), -16 (1), -17 (1),
  -18 (2, BUG-20), -19 (1, BUG-21).
- `mobile/test/qa/live_qa_round4_test.dart` — live: same IMEI received offline on two phones → one duplicateSerial on both, resolve
  reaches B; opening count into a new batch reaches B.
- `backend/tests/ZayPOS.QA.Tests/QaRound4Tests.cs` — TC_SYNC_NEW_5 (duplicateSerial, both phones pull, resolve), TC_SYNC_NEW_6
  (stockAdjust opening count with batch / IMEIs), TC_SYNC_NEW_7 (per shop, no leak), TC_SYNC_NEW_8 (sold / deleted / twins).
- Fixture change, no assertion changed: `mobile/test/qa/qa_round2_ui_test.dart` (2) and `mobile/test/qa/qa_round3_ui_test.dart` (8) medicine
  products set `expiryAlertDays: 30` (owner item 5). All pass.

Note on QA's own test: the first run of TC-PROD-NEW-12 failed because the test tapped "သိမ်းမယ်" in the same frame as `enterText` (save
button still disabled); a real user always gets a frame in between, so a `pump()` was added — not a product bug (same as round 3).
