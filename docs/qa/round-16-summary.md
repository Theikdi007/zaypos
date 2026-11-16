# QA round 16: summary (2026-11-16, branch `fix/android` @ 3c9e102, PR #8, targeted re-test)

> ## Go for a 3–5 shop Android beta, with one condition
>
> All three round-15 Medium bugs are fixed and verified on the Android emulator with the real app against the live API:
> - **BUG-55:** an http release build refuses to start and makes 0 connections.
> - **BUG-53:** no sample cost or price is ever saved; profit leaves unknown costs out and says so.
> - **BUG-52:** Zawgyi text is stored, synced and pulled as Unicode, from the app and from an "old app" push. Valid Unicode is untouched.
>
> The seven Lows are fixed: BUG-51, BUG-56, BUG-57, BUG-58, BUG-60 and BUG-47 fully; BUG-54 for what it reported; BUG-59 only for the
> bottom navigation.
>
> No Critical, High or Medium bug is open. Three new **Low** bugs were found (BUG-61, BUG-62, BUG-63).
>
> **Condition:** the https half of BUG-55 could not be run here (BLOCKED, see item 1). Before the release APK goes to the shops, the
> owner builds it with the real https `API_BASE_URL` and signs in and syncs once (MANUAL 1).

Scope: the brief's items 1–6 only, not a full regression. No product code was changed.

## Environment

| | |
|---|---|
| Android | `emulator-5554`, sdk_gphone64_arm64, Android 16 / API 36, 1080 × 2424, 420 dpi. Start: font_scale 1.0, density 420, accelerometer_rotation 1, user_rotation 0 (all restored; app uninstalled) |
| Debug build | `flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:5076` from `lib/main.dart` (adb checks); `flutter drive` steps through `run_qa_android.sh` |
| API | `dotnet run --no-launch-profile --no-build --urls http://127.0.0.1:5076`, Development, scratch DB **`ZayPOS_QA_20261116_R16`** via `ConnectionStrings__ZayPOS` (`dotnet ef dbcontext info` → "Database name: ZayPOS_QA_20261116_R16"), `dotnet ef database update` |
| Shop | "QA r16 Android", +95979091716, PIN 111111, pharmacy template, registered on the real app with adb |
| iPhone | iPhone 18 Pro simulator (old ZayPOS uninstalled first), fresh install via `run_qa.sh`; shut down at the end |

## Results per item

| # | Item | Result | Evidence (one line) |
|---|---|---|---|
| 1a | BUG-55 http release build refused | **PASS** | `tool/release_https_check.sh` → "PASS step 1: http release build refused to start; 0 connections to :5076"; screen "ZayPOS ကို ဖွင့်လို့ မရပါ", logcat `ZayPOS: InsecureApiUrl: …` (`release/`, `logs/r16_release_https_check_step1.log`); listener positive control `logs/r16_listener_positive_control.txt` |
| 1b | BUG-55 release build works over https | **BLOCKED** | See "Why the https half is BLOCKED" below |
| 1c | TC-SEC-06 | **PASS** (http half) | Item 1a, plus `aapt2`: INTERNET, targetSdk 36, and `m/release_https_test.dart` (10 tests) in the suite |
| 2 | BUG-53 / TC-PROD-NEW-36 | **PASS** | `r16_android_verify_test.dart` QA_STEP=products / sales: FAILURES 0 (`logs/r16_A_products.log`, `r16_A_sales.log`, `r16_bug53_*.png`). Details below |
| 3 | BUG-52 / TC-DEBT-NEW-14 | **PASS** | QA_STEP=zawgyi: FAILURES 0 (`logs/r16_A_zawgyi.log`); server pull `logs/r16_bug52_server_pull.log`; curl push `logs/r16_bug52_server_push_zawgyi.log`; strengthened widget test passes now and fails on the pre-fix commit |
| 4a | BUG-57 cart after a kill | **PASS** | `am kill` (pid 29656 → none) → reopen → POS "ပစ္စည်း 4 ခု" 3,500 Ks; after checkout + force-stop → "ပစ္စည်း 0 ခု" (`r16_bug57_*.png`) |
| 4b | BUG-51 / TC-AUTH-NEW-4 | **PASS** | Step 2 → BACK → "အဆင့် 1 / 4" with phone and code kept → forward: shop name and template kept; step 3 → BACK → step 2 (`r16_bug51_*.png`) |
| 4c | BUG-56 / TC-UX-NEW-17 | **PASS** | ပစ္စည်း / အကြွေး / အစီရင်ခံစာ / POS → BACK → ပင်မ; ပင်မ → "ZayPOS က ထွက်မလား" (မထွက်ပါ stays, ထွက်မယ် → launcher); after a sale, BACK goes receipt → sale → list → ပင်မ → question |
| 4d | BUG-60 / TC-UX-NEW-21 | **PASS** | `aapt2 dump badging` → `application-label:'ZayPOS'` (release and debug); launcher drawer "ZayPOS" (`r16_bug60_launcher_drawer.png`) |
| 4e | BUG-54 / TC-UX-NEW-16 | **PASS** (calendar) / new **BUG-62** | QA_STEP=pickers: Add Product, "Stock ဖြည့်မယ်" and the edit form show no English, with "ရွေးမယ်" / "မလုပ်တော့" and Myanmar digits. Keyboard-entry mode rejects "28/11/2030" with "ဖော်မက် မမှန်ကန်ပါ။" |
| 4f | BUG-58 / TC-UX-NEW-19 | **PASS** | POS with user_rotation 1 (auto-rotate off and on): `cur=1080x2424`. Control: the Settings app turns to `cur=2424x1080` |
| 4g | BUG-59 / TC-UX-NEW-20 | **FAIL** (partly fixed) / new **BUG-63** | Bottom nav fixed: readable, no overflow. Still broken: dashboard hero "RIGHT OVERFLOWED BY 83 PIXELS", POS cart bar "ပစ္စ/ည်း" "0/Ks", Reports tab "ဒီ" (`r16_bug59_max_*.png`) |
| 4h | BUG-47 / TC-DEBT-NEW-12 | **PASS** | 0 Ks → no "Viber သတိပေး"; 3,500 Ks → shown; −6,500 Ks (overpaid) → hidden (`r16_bug47_*.png`) |
| 5 | iOS smoke | **PASS** | `r16_ios_smoke_test.dart` (`logs/r16_B_ios_smoke.log`), then Android QA_STEP=pull (`logs/r16_A_pull.log`). Details below |
| 6 | Suites | see below | Developer's numbers reproduced |

Raw adb outputs for items 4a–4h: `logs/r16_adb_manual.log`.

### Details: item 2 (BUG-53)

- **Forms:** pharmacy, grocery and phone open with cost "" and price "", with hints "ဥပမာ 1200 / 1500", "ဥပမာ 450 / 600" and "ဥပမာ 3500 /
  6000". Grocery and phone were opened by switching the template with the same call the register wizard makes, then switching back.
- **Name only:** saved with price 0 and cost 0. POS asks "ဈေးနှုန်း ထည့်ပါ"; 800 was saved at the sale.
- **Price only:** saved with cost 0. The product row shows "အရင်းမသိ · ရောင်းဈေး 1,000".
- **Profit:** a sale of NoCost + WithCost (700 → 1,000) shows "300 Ks" and "အရင်းမသိ 1 ခု မပါ" on the dashboard and Reports. After the
  name-only sale it shows "300 Ks" and "… 2 ခု မပါ".

### Details: item 3 (BUG-52)

- **Typed on the emulator:** Zawgyi "ေမာင္ေမာင္", address "ရန္ကုန္", note "ေၾကြးက်န္" and product "ေဆးလံုး". They are stored as
  U+1019 U+1031 U+102C U+1004 U+103A ×2, "ရန်ကုန်", "ကြွေးကျန်" and "ဆေးလုံး". The rows draw correctly.
- **Search:** the Unicode, Zawgyi and partial queries each find exactly 1 row. Products are found by Unicode and by Zawgyi.
- **Valid Unicode is unchanged:** "ယခု မိုးရွာနေပါသလား" and "ကျွန်ုပ်".
- **Old-app push:** curl pushed Zawgyi "ေက်ာ္ေက်ာ္" / "ရန္ကုန္" / "ေၾကြးက်န္" and product "ၾကက္ဥ". The server answered `applied`, and the
  pull returns "ကျော်ကျော်" / "ရန်ကုန်" / "ကြွေးကျန်" / "ကြက်ဥ". The Android phone and the iPhone show them in Unicode.

### Details: item 5 (iOS smoke)

- The iPhone signed in and pulled 3 sales and 5 customers, all in Unicode.
- It sold C-0001 (1,000 Ks, cash). The receipt screen showed, and "ပြေစာ ပို့မယ်" opened the iOS share sheet with "PNG · 70 KB" (`r16_ios_receipt_share_sheet.png`).
- Outbox 0 on the iPhone. Android then pulled C-0001; outbox 0 there too.

### Why the https half of item 1 is BLOCKED

`dart:io` on Android trusts only the system CA store. Three ways to get a trusted https endpoint were tried or checked:
- **A local self-signed endpoint:** this emulator is a production image ("adbd cannot run as root in production builds"), so a test CA
  cannot be added to the system store.
- **A rootable image:** `system-images;android-36;google_apis` is only an empty directory on this Mac (not installed).
- **A public trusted-cert tunnel:** `cloudflared` was refused by the permission system.

Nothing was faked. The developer's unit tests (`release_https_test.dart`: "release: https requests go through") cover the code path. A
real release build over https is MANUAL 1.

### Review of `tool/release_https_check.sh` (read before running)

- It refuses to run if the port is in use.
- It records any TCP connection to the host port and checks the refusal screen in the uiautomator dump.
- It checks the logcat line. Note: logcat is saved about 5 s after launch, but the connection check covers about 15 s.
- It has no positive control for its listener. QA added one: a `nc` from the emulator to 10.0.2.2:5076 is recorded.
- Step 2 only checks that the login screen appears, not that a request succeeds over https.

## Developer's edits to QA test files (not weakened)

| File | Change | Verdict |
|---|---|---|
| `qa_form_helpers.dart`, `qa_round3_ui_test.dart`, `module_restock_test.dart` | Date-picker finders: `'28'` → `mmDigits(28)`, `'OK'` → `datePickerConfirmText` | Plumbing only. The same day is picked and the same assertions follow (e.g. the expiry `…-28` check) |
| `qa_pos_ui_test.dart` (TC-PROD-02) | The cost field is found by `ValueKey('cost')` instead of by its pre-filled sample text | The assertion `'+150 Ks (33%)'` is unchanged; the key is the cost field (`add_product_screen.dart:683`). Not weaker |
| `integration_test/qa/r15_android_flow_test.dart` | The same picker finders | Plumbing only |

## QA test change this round: TC-DEBT-NEW-14 strengthened (QA's own file)

The round-15 version did not prove the case well enough:
- it created the customer through the service;
- it tapped "အားလုံး" while the chip was off-screen, so the tap missed ("would not hit test");
- it counted texts minus 1 for the search box.

The new version:
- types the Zawgyi name into the real Add Customer form;
- checks the stored code points;
- scrolls the chip into view;
- counts only `CustomerRow` widgets, for Unicode, Zawgyi and partial queries.

It passes on 3c9e102 and fails on the pre-fix commit 0754175 (`Expected: [4121, 4145, …] Actual: [4145, 4121, …]`), so it proves the
case.

## Suite totals

| Suite | Command | Result |
|---|---|---|
| Mobile analyze | `cd mobile && flutter analyze` | No issues found (`logs/r16_suite_analyze.log`) |
| Mobile tests | `cd mobile && flutter test` | **750 passed, 14 skipped, 7 failed** (`logs/r16_suite_flutter_test_full.log`) |
| Backend Domain | `cd backend && dotnet test` | 20 / 0 |
| Backend Api | (same run) | 276 / 0 |
| Backend QA | (same run) | 39 passed, 4 failed (BUG-37, TC-AUTH-NEW-2) (`logs/r16_suite_dotnet_test.log`) |

How the mobile numbers break down:
- **The developer's numbers are reproduced:** 730 / 14 / 5. The 5 failures are the open QA bug tests for BUG-38 (TC-RPT-NEW-4), BUG-39
  (TC-DEBT-NEW-11), BUG-48 (TC-UX-NEW-13), BUG-49 (TC-UX-NEW-14) and BUG-50 (TC-UX-NEW-15).
- **QA's new `qa_round16_test.dart` adds +20 passed and +2 failed:** the 2 failures are TC-PROD-NEW-37 (BUG-61) and TC-UX-NEW-23 Latin
  digits (BUG-62).
- All 5 tests in `qa_round15_test.dart` pass, and TC-DEBT-NEW-12 (BUG-47) passes.

Device runs counted:
- Android: `r16_A_products`, `r16_A_sales`, `r16_A_zawgyi`, `r16_A_pickers` (2 expected FAILs = BUG-62) and `r16_A_pull`.
- iPhone: `r16_B_ios_smoke`.

Side runs, not counted (QA mistakes, not the app):
- `r16_A_products_SIDE_try1`: QA expected 3 "အရင်းမသိ" rows. The name-only product correctly shows "ဈေးနှုန်း ထည့်ရန်" instead.
- `r16_A_products_SIDE_try2_hung_splash`: `flutter drive` hung on the splash screen ("Driver extension is taking a long time"). It was
  killed and re-run.
- `r16_A_pickers_try1`: the edit form's batch field is built lazily below the fold, so QA had to scroll to it.

## Case totals after round 16 (223 cases)

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 15 | 1 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 5 | 0 | 0 | 0 |
| 4 PROD (+1 new) | 47 | 1 | 0 | 2 |
| 5 POS | 26 | 0 | 0 | 2 |
| 6 SALE | 5 | 0 | 0 | 0 |
| 7 DEBT (+1 new) | 20 | 1 | 0 | 0 |
| 8 RPT | 7 | 1 | 0 | 0 |
| 9 SYNC (+1 new) | 46 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX (+1 new) | 23 | 6 | 0 | 0 |
| **Total** | **208** | **10** | **0** | **5** |

What changed this round:
- **FAIL → PASS:** TC-SEC-06 (its https half is BLOCKED, noted in the row), TC-AUTH-NEW-4, TC-PROD-NEW-36, TC-DEBT-NEW-12,
  TC-DEBT-NEW-14, TC-UX-NEW-16 … 19 and TC-UX-NEW-21.
- **Still FAIL:** TC-UX-NEW-20.
- **New PASS:** TC-DEBT-NEW-15 (Zawgyi converter on 19 realistic strings) and TC-SYNC-NEW-30 (old-app Zawgyi push).
- **New FAIL:** TC-PROD-NEW-37 and TC-UX-NEW-23.

The other rows were not re-executed; the suites cover them.

## Bugs by severity (open after round 16)

- **Critical:** none. **High:** none. **Medium:** none.
- **Verified fixed this round:** BUG-47, BUG-51, BUG-52, BUG-53, BUG-55 (the refusal), BUG-56, BUG-57, BUG-58 and BUG-60. BUG-54 is fixed
  for the calendar.

New this round, all **Low**:
- **BUG-61 · TC-PROD-NEW-37:** a cost typed as 0 counts as "unknown", so a service-only shop never sees a profit. This needs an owner
  decision.
- **BUG-62 · TC-UX-NEW-23:** in the date picker's keyboard-entry mode, a date typed with the phone keyboard's digits is rejected
  ("ဖော်မက် မမှန်ကန်ပါ။"). The empty hint is "dd-mm-yyyy".
- **BUG-63 · TC-UX-NEW-20:** at the largest font and display size, the dashboard hero row overflows by 83 px.

Low, still open (beta backlog):
- BUG-37, BUG-38, BUG-39, BUG-42, BUG-48, BUG-49 and BUG-50 (unchanged).
- BUG-59: partly fixed (the cart bar, the Reports tab and the shop name still break mid-word).

## Release recommendation: **Go** for a 3–5 shop Android beta

The owner's rule ("Go only if no Critical/High/Medium bug is open") is met.

Reasons:
- Every round-15 Medium is fixed and was proven on the device with the real app and the live API, not only in unit tests.
- No sale was lost or doubled in any kill, back or sync step.
- Android and the iPhone stay in sync.

Conditions:
1. **MANUAL 1 first.** Build the release APK with the real **https** `API_BASE_URL`, then install it, sign in, sell once and sync. This
   is the half of BUG-55 QA could not run. A release build must never use an http URL; the app now refuses it anyway.
2. Carried over: the owner runs the MANUAL list, the dev sa password is rotated, and photos stay on the phone.

## MANUAL cases for the owner (real Android phone, in this order)

1. **BUG-55 https half.** `flutter build apk --release --dart-define=API_BASE_URL=https://<real API host>` → install → register or sign
   in → one sale → Settings shows "Sync ပြီး" and the sale is on the server. Optionally also build with `http://<Mac IP>:5076`: it must show
   "ZayPOS ကို ဖွင့်လို့ မရပါ".
2. **Zawgyi on a real Zawgyi phone** (decides whether BUG-52 is closed for the shops). Type a customer name and a product name with the
   phone's Zawgyi keyboard. Then:
   - check the rows look right and the names are found by search;
   - check that the other phone shows the same name;
   - note any Zawgyi word that stays unconverted (by design, words like "ကေလး" that are also valid Unicode are kept as typed).
3. **TC-DEBT-NEW-13 on Android:** the debtor's phone icon opens the dialer. With Viber installed, "Viber သတိပေး" (only for a debtor)
   sends the whole Burmese text.
4. **TC-POS-11 / TC-SALE-NEW-1:** receipt → "ပြေစာ ပို့မယ်" → Viber; "ပုံ သိမ်းမယ်" puts the image in the Gallery. Also on Android ≤ 10:
   the storage permission prompt.
5. **TC-UX-NEW-18 on a ≤ 2 GB phone:** checkout with 3 items → switch to KBZPay / Wave → come back. The cart must still be in POS.
6. **TC-POS-NEW-9:** camera scan at POS: the first-use permission prompt, and denying it once.
7. **TC-UX-NEW-20:** a small phone at the largest font and display size: PIN, POS, checkout and Reports (BUG-59 rest, BUG-63).
8. **TC-UX-NEW-19:** auto-rotate on, turn the phone on POS. It must stay in portrait.
9. Add a phone product with two or more IMEIs, using "done" after each.
10. Carried over (steps in the round-13/14/15 summaries): TC-UX-01, TC-PIN-05, TC-UX-05, TC-UX-06, TC-AUTH-NEW-3, TC-POS-NEW-10,
    TC-PROD-NEW-34, TC-RPT-NEW-1 and TC-SYNC-NEW-28.

## New test files (round 16)

- `mobile/integration_test/qa/r16_android_verify_test.dart`: QA_STEP = products | sales | zawgyi | pickers | pull.
- `mobile/integration_test/qa/r16_ios_smoke_test.dart`: iPhone as the second phone (pull, sale, receipt, share sheet, push).
- `mobile/integration_test/qa/r16_server_zawgyi.py`: server pull and the Zawgyi "old app" push (curl).
- `mobile/test/qa/qa_round16_test.dart`: TC-PROD-NEW-37, TC-UX-NEW-23 (×2) and TC-DEBT-NEW-15 (19 tests).
- `mobile/test/qa/qa_round15_test.dart`: TC-DEBT-NEW-14 strengthened, and unused imports removed.
- Docs: `docs/qa/test-cases.md` (round note, 12 rows updated, 4 new), `docs/qa/bugs.md` (statuses for BUG-47 and BUG-51 … 60; BUG-61 …
  63), this file, and `docs/qa/evidence/round-16/`.

## Cleanup

- **API:** stopped; port 5076 is free.
- **Scratch DB:** dropped. The dry run said "This would drop the database 'ZayPOS_QA_20261116_R16'", then "Successfully dropped
  database 'ZayPOS_QA_20261116_R16'".
  - `ZayPOS` and `ZayPOS_SchemaRef` were never touched.
  - `ZayPOS_QA_20261115_R12B` (from round 12b) is still on the server; it is not from this round.
- **Emulator:** `adb uninstall com.zaypos.zaypos_app` → Success. Settings checked after restore: font_scale 1.0, Physical density 420,
  accelerometer_rotation 1, user_rotation 0.
- **iPhone 18 Pro simulator:** ZayPOS uninstalled (the old round-15 install too), simulator shut down. The iPhone 17 simulator, which
  was already booted, was not used.
- **Throwaway files:** the throwaway CA, the release APKs and the scratch worktree stayed in the session scratchpad and are not in the
  repo. No AVD was created; the create attempt failed because the image is missing.
- **Evidence:** contains no tokens or passwords (checked with grep).
