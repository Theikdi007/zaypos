# QA round 7 — summary (2026-11-14, branch `beta-polish` @ 00bcea9)

> ## Ready for beta
>
> Owner's exit rule met: **no Critical, High or Medium bug is open.** Open: two Low bugs (BUG-9 remainder, new BUG-25) and one accepted
> risk (BUG-11, dev SA password; owner decision). BUG-8, BUG-10 and BUG-24 are fixed and verified. The new barcode scanning (dba0348) and
> product photos (6e94350) pass every automated case except the photo-preview fallback (BUG-25).
> Before any shop uses it, the owner still has to run the MANUAL list below on a real phone (UX-01 and UX-05 are P1; the new camera,
> Bluetooth-scanner and photo cases come right after) and build releases with an https `API_BASE_URL`.

Scope: re-test of the new barcode scanning (camera + HID / keyboard-mode scanner at POS, Add Product barcode / IMEI scan) and product
photos (take / pick, ≤ 200 KB JPEG, stored on this phone only), re-test of BUG-24, BUG-10, BUG-8, BUG-9, 13 new cases, regression of all
cases. Live runs used the scratch database `ZayPOS_QA_20261114_R7` (API on 127.0.0.1:5077, dropped afterwards by name; dev database
`ZayPOS`: 0 QA tenants). Backend QA tests use their own Testcontainers SQL Server. No product code was changed.

## Totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT (+1 fixed since r6) | 5 | 0 | 0 | 0 |
| 4 PROD (+1 fixed since r6, +5 new) | 44 | 1 | 0 | 2 |
| 5 POS (+6 new) | 19 | 0 | 0 | 3 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT | 11 | 0 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC | 28 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX (+1 fixed since r6, +2 new) | 2 | 2 | 0 | 4 |
| **Total (156)** | **143** | **3** | **0** | **10** |

FAIL rows: TC-PROD-NEW-31 (BUG-25, new — parts c and d), TC-UX-02 (BUG-9, only Settings "စားပွဲ / Order mode" left on the routes),
TC-UX-NEW-1 (BUG-9, new wider scan) — all Low.
For **Both** cases the PASS covers the automated part; the owner still runs the phone steps.

Test runs:

- Round-7 QA files re-confirmed at the end (`cd mobile && flutter test test/qa/qa_round7_scan_test.dart test/qa/qa_round7_photo_test.dart
  test/qa/qa_round7_drift_test.dart test/qa/qa_round7_ux_test.dart test/qa/qa_app_flows_test.dart`) → **34 passed, 3 failed**. The 3
  failures are exactly the recorded bug tests: `qa_round7_photo_test.dart::TC-PROD-NEW-31 … picked file is not an image …` (c) and
  `… broken photo file → Products list, POS tile and the edit form …` (d), both `Expected: null  Actual: _Exception:<Exception: Invalid
  image data>` (BUG-25); `qa_round7_ux_test.dart::TC-UX-NEW-1 …` (BUG-9). TC-FEAT-04 (new finder) and TC-FEAT-NEW-1 pass.
- `cd mobile && flutter analyze` (own command) → No issues found.
- Full `flutter test`, `dotnet test` and the 8 live files were run during the round (see the round-7 header in `test-cases.md`); the
  session was interrupted before their totals were written down, so no counts are given here. Expected failing QA tests in the full
  mobile run: the three above plus `qa_ux_test.dart::TC-UX-02 … signed-in` (BUG-9). Re-run both suites before tagging the beta build and
  record the counts.

## Bug verdicts

| Bug | Verdict | Evidence (short) |
|---|---|---|
| BUG-24 voiding the original sale after the traded-in phone was sold again | **verified** | r6 test now PASS (0 in-stock rows, stock 0, POS offers nothing); Drift edge cases TC-PROD-NEW-33: no inStock / voidReturn for the phone, un-void writes no −1, void sale 2 brings it back once, void sale 1 again still once; live + server round-6 tests still pass |
| BUG-10 v2 restaurant template at registration | **verified** | card dimmed, tap does nothing, step 3 not reached; developer `register_template_test.dart` read and run |
| BUG-8 Customers chips overflow at 320 px | **verified** | TC-UX-04 32/32 PASS; every `FilterChips` use is scrollable; owner still checks the largest font (TC-UX-03) |
| BUG-9 English on Burmese screens | **partly fixed, stays open (Low)** | times ("နံနက် / နေ့လယ် / ညနေ / ည", TC-UX-NEW-2), "အစီရင်ခံစာ" tab, template / Register / login / Settings module texts fixed; left: "Order mode", "Size" in fashion forms and sheets, "ရိုးရှင်း mode", "menu", "data" (TC-UX-NEW-1) |
| BUG-11 dev SA password | **accepted risk (owner)** | unchanged |
| BUG-25 (new) photo preview has no fallback | **open, Low** | broken saved photo / unreadable pick → "Invalid image data" in the 88 px square of the Add/Edit form |

QA-side correction: TC-FEAT-04 and TC-UX-02 contradicted each other (one found the v2 switch by its English title, the other requires
the title to be translated). TC-FEAT-04 now finds the switch by its Burmese description "စားသောက်ဆိုင်၊ ကော်ဖီဆိုင်"; assertions unchanged.

## New cases (13)

| Case | Result | What it proves |
|---|---|---|
| TC-PROD-NEW-30 | PASS | compression: 12 MP, EXIF 6 / 8 / 3, panoramas, PNG, 1×1 → JPEG ≤ 200 KB, longest ≤ 1024, aspect kept, rotated once; broken input never hangs |
| TC-PROD-NEW-31 | **FAIL** (a, b, e PASS; c, d FAIL) | take / pick / replace / remove / save flows correct; preview fallback missing → BUG-25 |
| TC-PROD-NEW-32 | PASS (Both) | photo is local only: ONE upsertProduct unit, no photo on the wire, unit < 4 KB; phone B shows the initial |
| TC-PROD-NEW-33 | PASS | BUG-24 Drift edge cases (void / un-void / void sale 2 / re-void) |
| TC-PROD-NEW-34 | MANUAL | real-phone photo: permission, portrait, HEIC, big screenshot, remove, deny, kill + reopen, phone B |
| TC-POS-NEW-6 | PASS | HID scanner: ≤ 60 ms keys, ≥ 4 chars + Enter = one scan; slow typing ignored; search box cleared; only while POS is on top |
| TC-POS-NEW-7 | PASS | scan = tap: IMEI / size-colour / batch (FEFO) sheets, price question, deleted product not found |
| TC-POS-NEW-8 | PASS | Myanmar digits and spaces normalized like the server; unknown-barcode sheet → Add Product with the exact code; IMEI scan in Add Product once |
| TC-POS-NEW-9 | MANUAL | real-phone camera scan |
| TC-POS-NEW-10 | MANUAL | real Bluetooth HID scanner |
| TC-POS-NEW-11 | PASS | duplicate barcode adds ONE line (the newer product); IMEI scanned at POS → unknown-barcode sheet (recorded behaviour, see risks) |
| TC-UX-NEW-1 | **FAIL** | wider English scan of sheets / template forms / whole Settings list → BUG-9 remainder |
| TC-UX-NEW-2 | PASS | 12-hour Burmese time labels at every boundary, local time, receipt date |

## Bugs by severity (open)

Critical — none. High — none. Medium — none.

Low
- **BUG-25** (TC-PROD-NEW-31, new) — Add/Edit Product photo square raises "Invalid image data" for a corrupt saved photo or an
  undecodable picked file (debug: red box; release: blank square without the camera icon). Product still saves, list and POS tile fall
  back to the initial; the user can remove / replace the photo. Suspected: the preview `Image` in `add_product_screen.dart` has no
  `errorBuilder`.
- **BUG-9** (TC-UX-02, TC-UX-NEW-1) — remainder: Settings "စားပွဲ / Order mode", "ရိုးရှင်း mode", "menu", "data"; "Size" in the fashion
  Add Product, edit form, restock sheet and POS size/colour sheet (Settings already says "အရွယ်အစား / အရောင်").

Accepted risk: BUG-11 (TC-SEC-04) — dev sa password still the one in git history; loopback only.

## Risks / owner decisions

1. **Duplicate barcode (TC-POS-NEW-11 a).** Add Product saves a second product with an existing barcode without a word; a scan then adds
   the newer product only. The server flags it later (`duplicateBarcode`, README §3.4). Decide: warn at save on the phone, or accept and
   train "one barcode = one product".
2. **IMEI scanned at POS (TC-POS-NEW-11 b).** In a phone shop, scanning the IMEI sticker on a box at POS is not looked up; the cashier is
   offered "ပစ္စည်းအသစ် ထည့်မယ်" with the IMEI as a barcode, which would create a junk product. Decide: look up in-stock IMEIs on scan,
   or train "scan the product barcode, then pick the IMEI".
3. **Loanword allow-list for BUG-9.** Decide which of "Size", "mode", "menu", "data", "update", "Copy / paste", "Contacts", "Settings",
   "(FEFO)" are acceptable loanwords. QA then adds the allowed ones to the TC-UX-02 / TC-UX-NEW-1 allow-list; the rest go to the developer.
4. Photos are stored on this phone only (by design): a second phone or a re-install shows the initial, not the photo. Tell the shops.

## Release recommendation (3–5 shop beta), per shop type

**Go** for the beta under the owner's exit rule. Per shop type:

| Shop type | Verdict | Reasons | Conditions |
|---|---|---|---|
| Grocery | **Go** | every P1 case passes; barcode scan (camera + HID) passes all automated cases | MANUAL list incl. TC-POS-NEW-9 / -10 with the shop's real cans and scanner; release `API_BASE_URL` https; decision 1 |
| Hardware | **Go** | decimal sell / restock / low alert pass | as grocery |
| Pharmacy | **Go** | batches, expiry, FEFO scan sheet, single batch auto-pick pass | small strip barcodes in TC-POS-NEW-9 |
| Phone | **Go** | IMEI receive / sell / trade-in / void incl. BUG-24 fix verified | train "scan the product, then pick the IMEI" until decision 2 |
| Fashion | **Go** | variant scan sheet, restock, edit pass; Customers chips fixed | "Size" stays English (BUG-9, Low) |
| Service / other | **Go** | no stock modules; edit form passes | as grocery |

General conditions: the owner runs the MANUAL list below on a real phone first; release builds pass an https `API_BASE_URL` (default is
still `http://localhost:5076`); rotate the dev sa password (BUG-11) before anyone else uses the Mac; re-run and record both full suites
on the build that goes to the shops.

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01 — delete the app, airplane mode ON, install + open: Login/Register Myanmar text renders (bundled fonts, nothing fetched).
2. TC-UX-05 — kill the app during checkout: after reopening the whole sale exists or nothing.
3. TC-POS-NEW-9 — camera scan at POS: allow camera, real can, unknown barcode → add → scan again, medicine strip, crumpled bag, dim
   light, ✕, camera denied; phone shop: IMEI scan on a box in Add Product.
4. TC-POS-NEW-10 — Bluetooth HID scanner: 3× a known can, with the search box focused, with the keyboard open, slow hand typing,
   under Checkout, on Products, unknown code.
5. TC-PROD-NEW-34 — product photo: permission, portrait photo, HEIC and big screenshot from the gallery, remove, camera denied,
   kill + reopen, phone B shows the initial.
6. TC-PIN-05 — low-end Android, enter the PIN 3×: no stall of the dots/keypad.
7. TC-UX-03 — small phone + largest system font: no overflow, buttons ≥ 44 px; check the Customers chips scroll sideways, the POS scan
   button and the Add Product photo square + barcode button still fit.
8. TC-POS-11 — receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်": share sheet opens / image saved.
9. TC-PROD-13 — covered by 3–5 above (the handlers exist now); mark it from their results.
10. TC-UX-06 — 1 hour of normal use: no crash, battery/heat acceptable.

Then the phone halves of the **Both** cases, new first: TC-PROD-NEW-32 (photo on A, phone B shows the initial — done in step 5); from
round 6: TC-PROD-NEW-27, TC-PROD-NEW-28, TC-SYNC-NEW-12; round 5: TC-SYNC-NEW-10, TC-PROD-NEW-25, TC-PROD-NEW-24; round 4:
TC-SYNC-NEW-5, TC-SYNC-NEW-6, TC-PROD-NEW-16; round 3: TC-PROD-NEW-6, -7, -8, -9, TC-POS-NEW-5, TC-SYNC-NEW-3; round 2: TC-PROD-NEW-3,
-4, TC-POS-NEW-3, -4, TC-DEBT-NEW-3, -4.

## New test files (round 7)

- `mobile/test/qa/qa_round7_scan_test.dart` — TC-POS-NEW-6 (HID scanner, 3 tests), TC-POS-NEW-7 (scan = tap, 4 tests), TC-POS-NEW-8
  (normalization, unknown-barcode flow, Add Product scan, 3 tests), TC-POS-NEW-11 (duplicate barcode, IMEI at POS, 2 tests).
- `mobile/test/qa/qa_round7_photo_test.dart` — TC-PROD-NEW-30 (compression, 4 tests), TC-PROD-NEW-31 (form flows a–e, 5 tests; c and d
  fail → BUG-25).
- `mobile/test/qa/qa_round7_drift_test.dart` — TC-PROD-NEW-32 Drift (photo not synced), TC-PROD-NEW-33 Drift (BUG-24 edge cases).
- `mobile/test/qa/qa_round7_ux_test.dart` — TC-UX-NEW-1 (wider English scan — fails → BUG-9), TC-UX-NEW-2 (time labels).
- Changed: `mobile/test/qa/qa_app_flows_test.dart` — TC-FEAT-04 finds the v2 switch by its Burmese description (same assertions).
