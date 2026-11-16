# QA round 15: summary (2026-11-16, branch `fix/android` @ 32c7af1, PR #8, first Android round)

> ## No-go for an Android beta: three Medium bugs are open
>
> The app itself works on Android 16. Every main flow passed on the emulator against the live API:
> - register with OTP, PIN, products with barcode, IMEI and batch;
> - cash, debt and KBZPay sales, void, reports;
> - the receipt in the Android share sheet and saved to Pictures without a permission prompt;
> - the debtor's phone icon opens the real dialer with the number; the Viber reminder opens the share sheet;
> - two-way sync with an iPhone in the same shop.
>
> There was no crash, no half sale and no sync error. PR #8's font change works: even the Material date picker draws with the bundled
> fonts.
>
> Three **Medium** bugs block the beta under the owner's rule:
> - **BUG-55:** the **release** APK talks plain HTTP. A sale reached `http://10.0.2.2:5076` and a fresh install signed in, sending the
>   PIN in clear. The docs and TC-SEC-06 say release builds are HTTPS only. The manifest is right, but dio on `dart:io` ignores
>   Android's cleartext policy.
> - **BUG-53:** Add Product saves the template's **sample cost** (phone shop 3,500 Ks, grocery 450 …) as the real cost when it is not
>   overwritten, so profit is wrong. This is on every platform, since phase 1.
> - **BUG-52 (severity is a QA proposal):** a name typed on a **Zawgyi** keyboard is stored, synced and pulled byte for byte as Zawgyi.
>   It is drawn broken (dotted circles) on Android and iOS, and the Unicode spelling does not find it.
>
> All three have a small or well-known fix. BUG-52 can also become Low if the owner confirms that the beta shops type with Unicode
> keyboards. Seven new **Low** bugs, BUG-51 and BUG-54 to BUG-60, are Android back, rotation, largest-size and wording issues.

Scope: the brief's items 1–6 on the Android emulator, the iPhone simulator as the second phone, and the suites. No product code was
changed. Nothing was committed, pushed, merged or tagged.

## Environment

| | |
|---|---|
| Emulator | `emulator-5554`, `ro.product.model` sdk_gphone64_arm64, arm64-v8a, Android **16** (`ro.build.version.release`), **API 36** |
| RAM | `/proc/meminfo` MemTotal **2,017,772 kB** (~2 GB); MemAvailable 0.66–0.72 GB during the round |
| Screen | 1080 × 2424, 420 dpi. At the start: font_scale 1.0, auto-rotate on (accelerometer_rotation 1, user_rotation 0). All restored at the end |
| Apps on the emulator | Google dialer, Photos, DocumentsUI, Chrome, Gmail, YouTube, Maps. **No Viber** |
| Second phone | iPhone 18 Pro simulator (iOS 27.0, 7C1A4352…), fresh install, text size `large` (unchanged), shut down at the end |
| API | `dotnet run --no-launch-profile --urls http://127.0.0.1:5076`, scratch DB **`ZayPOS_QA_20261116_R15`** through the `ConnectionStrings__ZayPOS` override (`dotnet ef dbcontext info` → "Database name: ZayPOS_QA_20261116_R15"), created with `dotnet ef database update` (latest `20261114141058_SyncIssueData`). OTPs were read from the API console |
| Shop | "QA r15 Android", +959790917151, PIN 111111, phone-shop template, Batch switched on. Devices: A = emulator, B = a curl login for the server checks, C = iPhone |
| Builds | debug `flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:5076`; release `flutter build apk --release --dart-define=API_BASE_URL=http://10.0.2.2:5076` (88.8 MB, debug-signed, targetSdk 36) |

How it was driven:
- **The real app with adb.** `m/integration_test/qa/adb_ui.py` reads Flutter's semantics through `uiautomator dump` and taps by label. It
  was used for the system back key, share sheets, the dialer, Photos, rotation, sizes and kills.
- **`flutter drive` steps** through the new `m/integration_test/qa/run_qa_android.sh`, for typing Burmese and Zawgyi and for reading
  the database. The emulator cannot read host files, so the runner writes the acks and a copy of the API log into the app's cache
  with `adb shell run-as`.

Evidence is in `docs/qa/evidence/round-15/` (73 PNGs) and `logs/`.

## Suite totals

| Suite | Command | Start (developer's numbers reproduced) | End (with QA's round-15 files) |
|---|---|---|---|
| Mobile analyze | `cd mobile && flutter analyze` | No issues found | No issues found |
| Mobile tests | `cd mobile && flutter test` | **643 passed, 14 skipped, 6 failed** | **644 passed, 14 skipped, 10 failed** |
| Backend Domain | `cd backend && dotnet test` | 20 / 0 / 0 | 20 / 0 / 0 |
| Backend Api | (same run) | 120 / 0 / 0 | 120 / 0 / 0 |
| Backend QA | (same run) | 39 passed, 4 failed | 39 passed, 4 failed |

- **Start = the developer's numbers exactly.** The 6 known mobile failures are QA bug tests for BUG-38, 39, 47, 48, 49 and 50. The 4
  backend QA failures are BUG-37. Logs: `logs/suite_start_*.log`.
- **End: +1 passed, +4 failed.** The extra pass is the positive control in `qa_round15_test.dart` (the in-app back arrow). The 4 new
  failures are QA's round-15 bug tests: TC-AUTH-NEW-4 (BUG-51), TC-DEBT-NEW-14 (BUG-52), TC-PROD-NEW-36 (BUG-53) and TC-UX-NEW-16
  (BUG-54). Backend unchanged. Logs: `logs/suite_end_*.log`.
- **Counted device runs:**
  - Android: `r15_A_data`, `r15_A_sales`, `r15_A_zawgyi`, `r15_A_seed2`, `r15_A_timing`, `r15_A_timing2`, `r15_A_timing_profile` and
    `r15_A_pullios`.
  - iPhone: `r15_B_ios_sync`.
  - All passed.
- **Side runs, not counted (QA test mistakes, not the app):**
  - `r15_A_data_SIDE_try1`: QA expected an "addImei" button; Add Product adds an IMEI with the keyboard's "done" key.
  - `r15_A_data_SIDE_try2`: QA tapped the IMEI switch's title, which does not toggle it.
  - `r15_A_zawgyi_SIDE_try1`: QA used the wrong finder for the search box.
  - Leftovers in the shop from these tries: "QA r15 Coke" and "QA r15 Cola" (IMEI products with no stock).
  - Only one of the two IMEIs typed for "QA r15 Phone" was added in that `flutter drive` run. Adding several IMEIs is covered by
    earlier suites, so no bug is claimed. It is on the MANUAL list.

## Results per item

| # | Item | Result | Evidence | What was seen |
|---|---|---|---|---|
| 1a | Register (OTP) → PIN → dashboard | **PASS** | `a02…a08_*.png` (adb, real app) | The emulator reached `http://10.0.2.2:5076`. The OTP arrived in the API log. The 4 steps worked and the dashboard showed "Sync ပြီး". Login renders Burmese correctly (`a01_first_launch.png`) |
| 1b | Login / PIN | **PASS** | release fresh install `r15_release_fresh_signed_in.png`; iPhone sign-in `logs/r15_B_ios_sync.log`; unlock about 20× | Sign-in with phone + PIN on a new phone pulls the shop. The PIN screen comes back after every process restart |
| 1c | Products: barcode, IMEI, batch | **PASS** (BUG-53, BUG-54 found) | `logs/r15_A_data.log`, `r15_prod_*.png` | `QA r15 Soda` barcode 8850999150003, 20 pcs; `QA r15 Phone` with IMEI 351500000000011; `QA r15 ဆေး` batch B15, expiry 28 Nov 2026 picked in the date picker (`B15@1795824000000`), 10 pcs. Synced, outbox 0 |
| 1d | Sales: cash, debt, KBZPay; void | **PASS** | `logs/r15_A_sales.log`, `r15_sale_*.png`, `r15_pos_*_sheet.png` | A-0001 cash 3,000 (Soda ×2), then voided. A-0002 debt 2,000 to "QA r15 ဒေါ်လှ" (the only batch, B15, picked automatically; the line reads "Batch B15"). A-0003 KBZPay 450,000 (IMEI sheet). After the void: Soda 20, ဆေး 9, Phone 0. Reports: 452,000 Ks, 2 sales, the voided one excluded (`r15_reports.png`) |
| 1e | Receipt share | **PASS** | `r15_receipt_share_sheet.png` | The Android share sheet (`com.android.intentresolver`) shows "Sharing image" with the receipt preview, plus Quick Share, Photos, Maps, Gmail and Print. Back returns to the receipt |
| 1f | Save to Photos (API 36) | **PASS** | `r15_receipt_saved_snackbar.png`, `r15_photos_saved_ZayPOS-receipt-A-0154.png` | **No permission prompt.** The only runtime permission is CAMERA (not granted). The snackbar shows "သိမ်းပြီးပါပြီ". MediaStore went from 0 to 1 row: `ZayPOS-receipt-A-0154.png, Pictures/, 1080 × 846`. The pulled file is readable. Android ≤ 10 (WRITE_EXTERNAL_STORAGE, maxSdk 29) stays MANUAL |
| 1g | Debtor "ဖုန်းခေါ်ရန်" (tel:, `<queries>` DIAL) | **PASS** | `r15_dialer_opened.png`, logcat `START u0 {act=android.intent.action.VIEW dat=tel:xxxxxxxxxxx … cmp=com.google.android.dialer/…MainActivityDialAlias … from uid 10226 (com.zaypos.zaypos_app)` | The real Google dialer opens with "09790011151" typed in. It does not call. Back returns to the debtor screen |
| 1h | "Viber သတိပေး" | **PASS** (sim) | `r15_viber_share_sheet.png` | Share sheet "Sharing text": `မင်္ဂလာပါ QA r15 ဒေါ်လှ / QA r15 Android မှ အကြွေး သတိပေးစာ ဖြစ်ပါတယ်။ / ၁၆ နိုဝင်ဘာ ၂၀၂၆ နေ့အထိ ပေးရန်ကျန်ငွေ 2,000 Ks ရှိပါတယ်။ / …`. Viber is not installed, so sending through Viber is MANUAL |
| 1i | Sync with the iPhone, both directions | **PASS** (TC-SYNC-NEW-29) | `logs/r15_B_ios_sync.log`, `logs/r15_A_pullios.log`, `r15_ios_*.png`, `r15_android_*_after_ios.png` | **Android → iPhone:** the iPhone got 154 sales (1 voided), 5 products, IMEI 1, batch 1, 2 customers, stock Soda 19 / ဆေး 8 (same as Android). **iPhone → Android:** C-0001 (Soda, cash) and the customer "QA r15 iOS ဦးဘ" arrived on Android; Soda 18. Outbox 0 on both |
| 2a | System back, every main screen | see table below; **FAIL** → BUG-51, BUG-56 | adb on the real debug app | No back press ever created, lost or duplicated a **sale**. Checkout and POS keep the cart. Two problems: the registration wizard (BUG-51), and tabs / after-sale exits that cost a PIN entry (BUG-56) |
| 2b | Kill and reopen, mid-sale too | **PASS** for data, **FAIL** for UX → BUG-57 | `am force-stop` on checkout; `am kill`; a real low-memory kill (`logs/r15_lmk_kill_logcat.log`) | Sales before and after: 152 valid, so no half sale (TC-UX-05 holds). The cart is lost silently and the app opens on the PIN screen. Home and back while the process lives: checkout is kept and no PIN is asked |
| 2c | Rotation | **FAIL** → BUG-58 | `r15_rot_*.png` | Dashboard, checkout and PIN (after scrolling) work in landscape. POS products and quick sale are hidden behind the cart bar. Rotating during checkout keeps the cart and the WavePay choice |
| 2d | Largest font **and** largest display size | **FAIL** → BUG-59 (Low) | `r15_settings_max_font_display.png`, `r15_max_*.png` | Set through Settings → "Display size & text", both sliders at max: `font_scale=2.0`, `Override density: 540`. The PIN keypad fits. POS and checkout are usable by scrolling. Bottom nav: "BOTTOM OVERFLOWED BY 29 PIXELS"; checkout "So/da", "1,50/0"; report tab "ဒီ" |
| 2e | Share sheet / Photos permission on 13+ | **PASS** | 1e, 1f | — |
| 2f | tel: dialer | **PASS** | 1g | — |
| 3 | Load times | measured, see below | `logs/r15_A_timing*.log` | Release cold start 0.5–0.8 s. POS / Reports ≤ 41 ms (profile) |
| 4 | Zawgyi | **FAIL** → BUG-52 (Medium proposal) | see below | — |
| 5 | Suites | see above | `logs/suite_*.log` | — |
| 6 | Release APK | **launch PASS, cleartext FAIL** → BUG-55 (Medium) | `r15_release_*.png` (incl. `r15_release_settings_sync_ok_over_http.png`), `logs/r15_release_cleartext_server_pull.log` | No crash on launch. Not debuggable; no networkSecurityConfig; targetSdk 36. **It does not refuse `http://10.0.2.2`:** sale A-0155 7,777 Ks is on the server, and a fresh install signed in over HTTP. Afterwards the debug build was reinstalled and used |

### System back on each screen (real debug app, `adb shell input keyevent KEYCODE_BACK`)

| Screen (state) | What back did | Verdict |
|---|---|---|
| Login | Went to the launcher (process kept) | OK (root screen) |
| Register step 1, keyboard open | Closed the keyboard | OK |
| Register step 2 (phone, OTP and shop name entered), keyboard closed | **Went to Login; all entries and the verified code were lost.** The screen's own arrow goes to step 1 with the entries kept | **BUG-51** |
| PIN unlock | Launcher. Reopening shows the PIN again | OK (no bypass) |
| Dashboard | Launcher. Reopening asks for the PIN | OK |
| Products / Customers / Reports tab | **Launcher**, not ပင်မ. The PIN is asked on return | **BUG-56** |
| POS with 2 items | Dashboard. The cart was still there on return to POS | OK |
| Checkout (items, method chosen) | POS, cart kept. No sale written | OK |
| Receipt after a sale | Sale detail #A-0154, then "အရောင်းမှတ်တမ်း", then **left the app** | **BUG-56** |
| Share sheet over the receipt | Closed the sheet, back to the receipt | OK |
| Add Product, filled | 1st back closed the keyboard. 2nd back went to the product list; the form was discarded **without a prompt** (product count stayed 5). The in-app ✕ does the same; the app has no discard prompts anywhere (no `PopScope` in lib/) | Consistent with the app; not filed separately |
| Settings → back | Dashboard | OK |
| Sales list (from the dashboard) | Dashboard | OK |
| Debtor screen | Customer list | OK |
| "ငွေပြန်ဆပ်မယ်" sheet | Closed the sheet, debtor screen | OK |
| Dialer opened from the debtor | 2nd back returned to the debtor screen | OK |

## Load times

How measured:
- **Cold start:** `adb shell am start -W` TotalTime (process force-stopped first) = launch to the first frame.
- **POS and Reports:** inside the app, `router.go(route)` until the screen's anchor widget is in the tree. The anchor is "ငွေရှင်းမယ်" for
  POS and "နောက်ဆုံး ၇ ရက်" for Reports. The clock is a Stopwatch, pumping every 5 ms; each measurement starts from the dashboard.
  This is the app's own build and layout time; touch latency is not included.
- uiautomator polling was too coarse to use (2.5 s per dump).
- "Data" = 5 products, 3 customers and 3 sales at first, then **156 sales** after the seed (150 quick sales through the app's own
  checkout service, then synced).

| Build | Data | Cold start (launch → first frame) | POS: first open / warm | Reports: first open / warm |
|---|---|---|---|---|
| debug (JIT) | 3 sales | 2.0–2.7 s; 5.6–9.8 s right after a `flutter drive` install | 118 ms / 42–66 ms | 80 ms / 18–20 ms |
| debug (JIT) | 153 sales | (same) | 108 ms / 46–63 ms | 78 ms / 18–21 ms |
| **profile (AOT, like release)** | 156 sales | — | **31 ms / 20–25 ms** | **41 ms / 17–18 ms** |
| **release** | 156 sales | **761, 512, 533 ms**; 8,136 ms on the first launch after a fresh install (includes install-time optimisation) | (see profile) | (see profile) |

Memory: release PSS 99 MB / RSS 175 MB. Debug PSS 305 MB, which made a background kill easy on 2 GB (BUG-57). The release build would be
killed later, but it can still be killed.

## The Zawgyi check (BUG-52)

Input: the customer name `ေမာင္ေမာင္` = U+1031 U+1019 U+102C U+1004 U+1039 ×2, Zawgyi order for Unicode `မောင်မောင်` (U+1019 U+1031
U+102C U+1004 U+103A ×2). It was typed into "ဖောက်သည်အသစ်" on the emulator with `enterText`, as a keyboard would send it. Phone
"09 790 011 152".

| Question | Answer | Evidence |
|---|---|---|
| What the app stores | Exactly the Zawgyi code points; no detection, no conversion, no warning | `logs/r15_A_data.log`: `customer name=ေမာင္ေမာင္ [U+1031 U+1019 U+102C U+1004 U+1039 U+1031 U+1019 U+102C U+1004 U+1039]` |
| How it renders | Broken on Android: dotted circles before "မ", "င" with a stacked virama mark, avatar initial "ေ◌". Broken the same way on iOS. A Unicode name next to it renders correctly | `r15_zg_customers_all.png`, `r15_ios_customers_all.png` |
| Does the Unicode spelling find it | **No.** "မောင်မောင်" → 0 rows; "မောင်" → 0. The Zawgyi string → 1; phone "011152" → 1 | `logs/r15_A_zawgyi.log`, `r15_zg_search_*.png`; `m/qa/qa_round15_test.dart::TC-DEBT-NEW-14` (`Actual: <0>`) |
| What reaches the server | The same code points (`GET /api/v1/sync/pull`) | `logs/r15_zawgyi_server_pull.log` |
| What the iPhone gets | The same code points | `logs/r15_B_ios_sync.log` |

Severity proposal: **Medium**. Zawgyi keyboards are still common on older Android phones in Myanmar, which are the target shops' phones.
PR #8 now draws every widget with the Unicode font, so a Zawgyi user sees their own typing broken in every field. The other phones of
the shop see the same. Their customers and products cannot be found by name, a debtor can only be found by phone, and receipts and
reminders carry the broken name. No data is lost, and the phone search still works. Low is reasonable only if the owner checks that
every beta shop types with a Unicode keyboard. The usual fix is a Zawgyi detector plus converter on text entry (for example Google's
myanmar-tools and a Zawgyi→Unicode converter); QA did not change anything.

## New bugs (round 15)

- **BUG-51 · Low** · TC-AUTH-NEW-4: Android back on register step 2 drops the registration to Login. The screen's arrow goes back one
  step.
- **BUG-52 · Medium (proposal)** · TC-DEBT-NEW-14: a Zawgyi-typed name is stored, synced, drawn broken and not found by its Unicode
  spelling.
- **BUG-53 · Medium** · TC-PROD-NEW-36: Add Product saves the template's sample cost and price as real values, so profit is wrong.
- **BUG-54 · Low** · TC-UX-NEW-16: the expiry date picker is English ("Select date", "Cancel", "OK", months).
- **BUG-55 · Medium** · TC-SEC-06: the Android release build sends plain HTTP; the "HTTPS only" rule is not enforced.
- **BUG-56 · Low** · TC-UX-NEW-17: back on the Products / Customers / Reports tabs, and three backs after a sale, leave the app; the next
  open asks for the PIN.
- **BUG-57 · Low** · TC-UX-NEW-18: an open cart or checkout is silently lost when Android kills the app in the background.
- **BUG-58 · Low** · TC-UX-NEW-19: in landscape, the POS grid and the keypad are hidden behind the cart bar.
- **BUG-59 · Low** · TC-UX-NEW-20: at the largest font and display size, the bottom nav overflows 29 px and numbers break mid-word.
- **BUG-60 · Low** · TC-UX-NEW-21: the Android launcher label is "zaypos_app".

## Case totals after round 15 (219 cases)

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH (+1 new) | 14 | 2 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 5 | 0 | 0 | 0 |
| 4 PROD (+1 new) | 46 | 1 | 0 | 2 |
| 5 POS | 26 | 0 | 0 | 2 |
| 6 SALE | 5 | 0 | 0 | 0 |
| 7 DEBT (+1 new) | 17 | 3 | 0 | 0 |
| 8 RPT | 7 | 1 | 0 | 0 |
| 9 SYNC (+1 new) | 45 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 5 | 1 | 0 | 0 |
| 12 UX (+7 new) | 18 | 10 | 0 | 0 |
| **Total** | **196** | **18** | **0** | **5** |

Changed this round: TC-SEC-06 went from PASS to FAIL (BUG-55).

New this round:
- PASS: TC-UX-NEW-22 (Android main flows) and TC-SYNC-NEW-29 (Android ↔ iPhone).
- FAIL: TC-AUTH-NEW-4, TC-DEBT-NEW-14, TC-PROD-NEW-36, TC-UX-NEW-16 … TC-UX-NEW-21.

The other rows were not re-executed this round; the suites above are green for them.

## Bugs by severity (open)

Critical: none. High: none.

**Medium (block the beta under the owner's rule):**
- **BUG-55:** the release build does not enforce HTTPS. The fix is small: refuse a non-https `API_BASE_URL` in release, or document the
  rule as procedure only.
- **BUG-53:** sample cost and price are saved as real values. The fix is small: show them as hints.
- **BUG-52 (proposal):** Zawgyi input. Either add detection and conversion, or the owner decides Low after checking the shops'
  keyboards.

Low (beta backlog):
- BUG-37, BUG-38, BUG-39, BUG-42, BUG-47, BUG-48, BUG-49 and BUG-50 (unchanged).
- New: BUG-51, BUG-54, BUG-56, BUG-57, BUG-58, BUG-59 and BUG-60.

## Release recommendation (Android beta)

**No-go** until BUG-55, BUG-53 and BUG-52 are fixed, or the owner downgrades them. The rule is "Go only if no Critical, High or
Medium bug is open".

Apart from these, the Android build is in good shape:
- every main flow, the system sheets, the dialer and two-way sync work;
- a kill never leaves a half sale;
- the release build starts in about 0.5 s, and POS and Reports open in tens of milliseconds with 156 sales on a 2 GB device;
- PR #8 does what it says: Burmese renders with the bundled fonts everywhere QA looked, including the date picker, chips, dialogs and
  the share-sheet preview.

To reach Go:
1. **BUG-55:** fix it and re-run item 6. A release build with an http URL must fail, and one with an https URL must work. Until then,
   build release APKs only with an https `API_BASE_URL`.
2. **BUG-53:** fix it (hints instead of values) and re-run TC-PROD-NEW-36.
3. **BUG-52:** the owner decides. If the decision is Medium, add Zawgyi detection and conversion and re-run TC-DEBT-NEW-14. If it is
   Low, add it to the Known limitations and tell the shops to use a Unicode keyboard.
4. Recommended with it, all Low:
   - BUG-56: back on tabs goes to ပင်မ;
   - BUG-51: system back follows the register wizard's steps;
   - BUG-58: lock portrait;
   - BUG-60: launcher name "ZayPOS".

Conditions (unchanged):
- The owner runs the MANUAL list first.
- The dev sa password is rotated.
- Photos stay on the phone.

## MANUAL cases for the owner (real Android phone, in this order)

1. **Zawgyi (BUG-52, decides its severity).** On each beta shop's phone, check which keyboard and system font it uses (Settings →
   Keyboard; a Zawgyi phone shows "ျမန္မာ" readably). On a Zawgyi phone: install the build, add a customer by typing a Burmese name, then
   look at the list and search the name. Also check that the app's own screens render correctly on that phone, which is the point of
   PR #8. The emulator has a Unicode system font, so this was proven only indirectly.
2. **BUG-55 after the fix:** build a release APK with `http://<Mac IP>:5076` → sign-in must fail. Build with the real https URL → sign-in
   and sync must work.
3. **TC-DEBT-NEW-13 on Android:**
   - the phone icon opens the dialer with the number;
   - with Viber installed, "Viber သတိပေး" → Viber → send to yourself; the Burmese text must arrive whole;
   - with TalkBack on (BUG-48), unlock with the PIN keypad and switch tabs.
4. **TC-POS-11 / TC-SALE-NEW-1:** receipt → "ပြေစာ ပို့မယ်" → Viber; "ပုံ သိမ်းမယ်" → the image is in Gallery. On an **Android 10 or
   lower** phone the storage permission prompt must appear and work.
5. **TC-UX-NEW-18:** on a ≤ 2 GB phone, open checkout with 3 items → switch to KBZPay or Wave to check a transfer → come back. Note
   whether the cart survives.
6. **TC-POS-NEW-9 on Android:** camera scan at POS. The first use must ask for the camera permission (not granted on the emulator).
   Also deny it once.
7. **TC-UX-NEW-20 / TC-UX-03:** a small real Android phone with Font size and Display size both at max: PIN, POS, checkout, reports.
8. **TC-UX-NEW-19:** a phone with auto-rotate on: turn it sideways on POS.
9. Add a phone product with **two or more IMEIs** typed one after another ("done" after each). Both must be listed before saving (see
   the note under Suite totals).
10. Carried over (steps in round-13/14 summaries): TC-UX-01 (airplane mode, first launch), TC-PIN-05 (low-end Android, PIN 3×),
    TC-UX-05, TC-UX-06 (1 hour; battery and heat), TC-AUTH-NEW-3 (Myanmar keyboard), TC-POS-NEW-10, TC-PROD-NEW-34, TC-RPT-NEW-1
    (release), TC-SYNC-NEW-28.

## New test files (round 15, uncommitted)

- `mobile/integration_test/qa/run_qa_android.sh`: Android runner (`flutter drive`, acks and the API log through `adb shell run-as`,
  screenshots through `adb exec-out screencap`, rotation, font and density commands).
- `mobile/integration_test/qa/adb_ui.py`: drives the real app with adb and uiautomator (dump, has, tap, wait, shot, back, fg).
- `mobile/integration_test/qa/r15_android_flow_test.dart`: QA_STEP = data | sales | zawgyi | seed | timing | pullios.
- `mobile/integration_test/qa/r15_ios_sync_test.dart`: the iPhone as the second phone of the Android shop.
- `mobile/test/qa/qa_round15_test.dart`:
  - TC-AUTH-NEW-4: the control passes; system back fails → BUG-51.
  - TC-DEBT-NEW-14: fails → BUG-52.
  - TC-PROD-NEW-36: fails → BUG-53.
  - TC-UX-NEW-16: fails → BUG-54.
- Docs: `docs/qa/test-cases.md` (round note, TC-SEC-06, 11 new rows), `docs/qa/bugs.md` (BUG-51 … BUG-60) and this file.

## Cleanup

- **API stopped**; nothing listens on 5076.
- **Scratch DB dropped.** The dry run said "This would drop the database 'ZayPOS_QA_20261116_R15' on server 'localhost,1433'". Then:
  `DROP DATABASE [ZayPOS_QA_20261116_R15]; Successfully dropped database 'ZayPOS_QA_20261116_R15'`.
  - The scratch connection string was used throughout.
  - `ZayPOS` and `ZayPOS_SchemaRef` were never touched.
  - Docker `zaypos-sql` was not restarted.
- **Emulator:** `adb uninstall com.zaypos.zaypos_app` (Success). Restored: font_scale 1.0, `wm density reset` (Physical density 420),
  accelerometer_rotation 1, user_rotation 0. The saved receipt PNG was deleted from Pictures.
  - Side effect left in place: when the font slider was used, Android added a "Font size" Quick Settings tile.
  - Chrome, Photos and YouTube were opened once.
- **iPhone 18 Pro simulator:** shut down. ZayPOS is still installed on it, signed in to the dropped scratch shop, so it will show sync
  errors if opened. Text size was never changed (`large`). No simulator is booted.
- The API console log was filtered to `logs/api_console_filtered.log`; the full 2 MB, mostly SQL, was not kept. No tokens or passwords
  are in the evidence logs.
