# QA round 8 — summary (2026-11-14, branch `beta-polish` @ 54e9146)

> ## Ready for beta
>
> Owner's exit rule met: **no Critical, High or Medium bug is open.** BUG-25 and BUG-9 are fixed and verified; the scan-lookup decisions
> (duplicate barcode warns + POS picker, in-stock IMEI scan adds that phone) behave as decided on fake repos, on the real local database
> and live across two phones. Two new Low bugs: BUG-26 (server texts in English on "စစ်ရန်") and BUG-27 (one IMEI in stock twice →
> two scans add two phones). Accepted risk: BUG-11. The owner still runs the MANUAL list below on a real phone first.

Scope: re-test of 2c020e8 (BUG-25), fb520d9 (BUG-9 rest, owner's allow-list), e0ea12b (scan lookup) and 54e9146 ("Known limitations"),
review of the developer's edits to QA tests, 6 new cases, full regression. No product code was changed. No command was blocked by
permissions.

## Suite totals (recorded this round)

| Suite | Command | Passed | Failed | Skipped |
|---|---|---|---|---|
| Mobile analyze | `cd mobile && flutter analyze` | No issues found | — | — |
| Mobile, all tests (start of round, before r8 files) | `cd mobile && flutter test` | 491 | 0 | 8 |
| Mobile, all tests (end of round, with r8 files) | `cd mobile && flutter test` | **501** | **2** | **9** |
| Backend Domain | `cd backend && dotnet test` | 20 | 0 | 0 |
| Backend Api | (same run) | 111 | 0 | 0 |
| Backend QA | (same run) | 32 | 0 | 0 |
| Live (scratch DB `ZayPOS_QA_20261114_R8`, API 127.0.0.1:5077) | 9 files, one new phone + OTP each | **9** | **0** | 0 |

- The 2 mobile failures are exactly the new bug tests: `qa_round8_ux_test.dart::TC-UX-NEW-3 …` (BUG-26) and
  `qa_round8_scan_test.dart::TC-POS-NEW-13 … the same IMEI in stock on TWO products …` (BUG-27). Skipped = the 9 live files (no env vars
  in the plain run).
- Live files: `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_step4_test.dart`, `test/qa/live_qa_round2_test.dart` …
  `round6`, `test/qa/live_qa_round8_test.dart` (new; there is no round-7 live file). A first live attempt reused one phone number for
  every file (QA script error: zsh `$RANDOM` in a subshell) and failed with `409 phone_registered`; re-run with distinct numbers → 9/9.
- Scratch DB dropped by name (`DROP DATABASE [ZayPOS_QA_20261114_R8]`, it held 10 tenants); remaining databases `ZayPOS`,
  `ZayPOS_SchemaRef`; dev DB `ZayPOS`: `SELECT COUNT(*) FROM Tenants WHERE Name LIKE 'QA%'` → 0. Docker `zaypos-sql` untouched.

## Case totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 5 | 0 | 0 | 0 |
| 4 PROD (+1 fixed, +1 new) | 46 | 0 | 0 | 2 |
| 5 POS (+2 new) | 20 | 1 | 0 | 3 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT | 11 | 0 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC (+1 new) | 29 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX (+2 fixed, +2 new) | 5 | 1 | 0 | 4 |
| **Total (162)** | **150** | **2** | **0** | **10** |

FAIL rows: TC-POS-NEW-13 (BUG-27, one of its three fake-repo tests; the Drift test passes), TC-UX-NEW-3 (BUG-26). Both Low.

## Verdicts on what changed

| Item | Verdict | Evidence (short) |
|---|---|---|
| BUG-25 photo preview fallback (2c020e8) | **verified** | `qa_round7_photo_test.dart::TC-PROD-NEW-31` c and d PASS unchanged; a, b, e PASS |
| BUG-9 rest (fb520d9) | **verified** for the app's texts | TC-UX-02 (both), TC-UX-NEW-1 PASS with the owner's list; new TC-UX-NEW-4 PASS. Runtime / server English → BUG-26 (new) |
| (a) duplicate barcode warns, not blocks | **as decided** | TC-PROD-NEW-35: deleted product's barcode not counted; Myanmar digits warn; dialog names every other product; cancel saves nothing; edit to a duplicate warns, price-only / clearing do not; Drift: ONE upsertProduct |
| (b) POS picker | **as decided** | TC-POS-NEW-12: both listed with prices, HID bursts under the picker ignored, dismiss = nothing, camera too, no-price product asks the price, IMEI product asks the IMEI, deleted duplicate → no picker |
| (c) in-stock IMEI scan | **as decided, one edge bug** | TC-POS-NEW-13 Drift: real `watchSerialRows`, Myanmar digits, already-in-cart message, deleted product's / sold IMEI → "ပစ္စည်းအသစ်", trade-in picks the new row, checkout sells exactly the scanned rows. BUG-27 for a duplicated in-stock IMEI |
| Two phones (live) | **pass** | TC-SYNC-NEW-13: one `duplicateBarcode` on A and B, B's picker gets both; B finds and sells A's IMEI, A sees it sold, no issue; both selling one IMEI offline → `serialDoubleSold` on both |
| "Known limitations" (54e9146) | **accurate**, 4 additions written under it in bugs.md | warning only knows this phone's products; deleted product's IMEI also → new-product sheet; sold IMEI still offered as a new product (receive trade-ins with "Stock ဖြည့်မယ်"); the server issue text is English (BUG-26); BUG-27 |

## Developer edits to QA tests — reviewed

- `qa_ux_test.dart`, `qa_round7_ux_test.dart` allow-lists (fb520d9): **accepted.** Now exactly the owner's ten words + brand, Ks, units,
  phone placeholders (+ XS/XL/XXL in TC-UX-NEW-1) — stricter than round 7, nothing the owner did not allow.
- Mechanical renames in other QA finders (`Batch`→`အသုတ်`, `Size`→`ဆိုဒ်`, `Serial`→`စီးရီးနံပါတ်`, `Offline`→`လိုင်းမရှိ`, scanner titles):
  **accepted.** Only expected strings changed (they now follow the translated UI); no assertion removed or weakened.
- `qa_round7_scan_test.dart` TC-POS-NEW-11 rewrite (e0ea12b): **accepted with one gap closed by QA.** The tests now assert the decided
  behaviour (warn → save, picker, nothing auto-added; IMEI line with that row). The duplicate test's title says "a picker with both" but
  checked only the first product's key; QA added the check for the second one (passes).
- Disagreement (not with an edit, with a gap): `m/no_english_test.dart` only reads literals that contain a Burmese letter, so it cannot
  see English that arrives at runtime or English-only literals. That is how BUG-26 got through.

## Bugs by severity (open)

Critical — none. High — none. Medium — none.

Low
- **BUG-26** (TC-UX-NEW-3, new) — "စစ်ရန်" and the rejected-unit screen show the server's English detail / reason ("Barcode … is also
  used by: …", "tenantFeatures.featureKey must not be empty.") and the raw feature key ("လုပ်ဆောင်ချက် ပြောင်း · expiryBatch"). With
  duplicate barcodes now allowed, this English line is an everyday sight.
- **BUG-27** (TC-POS-NEW-13, new) — when one IMEI is in stock on two products (a flagged duplicateSerial), scanning the box twice adds
  two phones; "already in the cart" is checked by row id, not by IMEI.

Accepted risk: BUG-11 (TC-SEC-04) — dev sa password in git history; loopback only.

## Release recommendation (3–5 shop beta)

**Go.** Every P1 automated case passes; open bugs are Low and need either a server-side text (BUG-26) or an already-flagged data
conflict (BUG-27). Per shop type: grocery, hardware, pharmacy, fashion, service — Go, as round 7. Phone shops — Go; tell them that
scanning the IMEI at POS now sells that phone, that trade-ins are received with "Stock ဖြည့်မယ်" (scanning a sold IMEI at POS offers
"ပစ္စည်းအသစ်"), and to clear any "IMEI / စီးရီးနံပါတ် တူ …" entry in "စစ်ရန်" promptly (BUG-27).

Conditions (unchanged): owner runs the MANUAL list first; release builds use an https `API_BASE_URL`; rotate the dev sa password
before anyone else uses the Mac; tell shops that photos stay on the phone and that "စစ်ရန်" details are in English for now.

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01 — delete the app, airplane mode ON, install + open: Login/Register Myanmar text renders.
2. TC-UX-05 — kill the app during checkout: after reopening the whole sale exists or nothing.
3. TC-POS-NEW-9 — camera scan at POS (steps in the row). Add for round 8: phone shop, scan the IMEI barcode on an in-stock phone's box
   at POS → that phone is in the cart with that IMEI, no IMEI question; scan it again → "ဒီ IMEI ကို ထည့်ပြီးသားပါ။"; give two products the
   same barcode (Add Product shows "ဒီ Barcode ရှိပြီးသားပါ" → "ဒီအတိုင်း သိမ်းမယ်") → scan → "ဘယ်ပစ္စည်းလဲ?" → pick one.
4. TC-POS-NEW-10 — Bluetooth HID scanner (steps in the row). Add for round 8: with the "ဘယ်ပစ္စည်းလဲ?" picker open, scan again →
   nothing happens; close it, scan → picker again.
5. TC-PROD-NEW-34 — product photo on a real phone (incl. a broken / HEIC picture: the square shows the camera box, never an error).
6. TC-PIN-05 — low-end Android, PIN 3×: no stall.
7. TC-UX-03 — small phone + largest system font: no overflow; check the picker sheet and the duplicate-barcode dialog too.
8. TC-POS-11 — receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်".
9. TC-PROD-13 — mark it from steps 3–5.
10. TC-UX-06 — 1 hour of normal use.

Then the phone halves of the **Both** cases, newest first: TC-SYNC-NEW-13 (two real phones: duplicate barcode on A → B's scan shows the
picker; scan the same phone box on A and B while both are offline → online → "စစ်ရန်" on both), then the round-7 list (TC-PROD-NEW-32,
TC-PROD-NEW-27, -28, TC-SYNC-NEW-12, TC-SYNC-NEW-10, TC-PROD-NEW-25, -24, TC-SYNC-NEW-5, -6, TC-PROD-NEW-16, TC-PROD-NEW-6..9,
TC-POS-NEW-5, TC-SYNC-NEW-3, TC-PROD-NEW-3, -4, TC-POS-NEW-3, -4, TC-DEBT-NEW-3, -4).

## New test files (round 8)

- `mobile/test/qa/qa_round8_scan_test.dart` — TC-PROD-NEW-35 (2 tests), TC-POS-NEW-12 (3 tests), TC-POS-NEW-13 (3 tests; 1 fails → BUG-27).
- `mobile/test/qa/qa_round8_scan_drift_test.dart` — TC-POS-NEW-13 Drift (IMEI lookup on the real database), TC-PROD-NEW-35 Drift.
- `mobile/test/qa/qa_round8_ux_test.dart` — TC-UX-NEW-3 (fails → BUG-26), TC-UX-NEW-4.
- `mobile/test/qa/live_qa_round8_test.dart` — TC-SYNC-NEW-13 (live, two phones).
- Changed: `mobile/test/qa/qa_round7_scan_test.dart` — TC-POS-NEW-11 duplicate test also checks the second product is in the picker.
