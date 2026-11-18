# QA round 17: summary (2026-11-17, branch `fix/android` @ e5ba3da + uncommitted `mobile/lib/core/api/api_error.dart`)

> ## Go for a 3–5 shop beta: the shop owner's day passes on the real iPhone and on Android
>
> Every automated item of the owner's "Localhost Manual Test Checklist" passes (19 of 19), with the real app against the live API on
> this Mac:
> - **Real iPhone:** the iPhone 15 (iOS 27.2) did the morning half of the day.
> - **Android:** the emulator did the second-phone half.
> - **Numbers agree:** the server DB and both phones show the same figures.
>
> The happy path of today's "0 products on the server" report works. The shop was registered twice with the preset catalog, the second
> time over an existing shop's data on the same iPhone. Both times the server had all 20 preset products.
>
> Three new **Low** bugs: BUG-64, BUG-65 and BUG-66. No Critical, High or Medium bug is open. The uncommitted `api_error.dart` change
> is proven by a new test (TC-SYNC-NEW-31). That test passes with the change and fails without it.

No product code was changed and nothing was committed (as briefed).

## Environment

| | |
|---|---|
| API | `dotnet run --no-launch-profile --no-build --urls http://0.0.0.0:5076`, Development, scratch DB **`ZayPOS_QA_20261117_R17`** via `ConnectionStrings__ZayPOS` (`dotnet ef dbcontext info` → "Database name: ZayPOS_QA_20261117_R17"), `dotnet ef database update` first. The `:5076` instance from the brief was not running at the start. Mac LAN IP 192.168.100.198 |
| iPhone | Owner's iPhone 15, `00008120-0002610901F00032`, iOS 27.2. Connected **over Wi-Fi only**, even after the owner was asked to plug it in: `flutter devices` → "iPhone (wireless)", `devicectl` → "Transport Type: localNetwork", and no iPhone in the USB tree |
| Android | Emulator `Medium_Phone_API_36.1` (`emulator-5554`, Android 16, 1080 × 2400, 420 dpi). Pixel_9a was tried first (same ~390 MB free) and shut down; see "Android storage" |
| Shops | **QA r17 ကုန်စုံ** (+959790917171) and **QA r17b ကုန်စုံ** (+959790917181), PIN 111111, grocery template, "ကြိုတင်စာရင်း". The full day ran on r17b; the r17 runs are kept as side runs |

### How the iPhone was driven (flutter drive does not work over Wi-Fi)

`flutter drive` to the iPhone failed with the stated symptom: "The Dart VM Service was not discovered after 75 seconds … Your debugging
device seems wirelessly connected" (`logs/r17_iphone_probe.log`). QA did not stop there:
- **Build and launch:** the test is built as a **profile** app (`flutter build ios --profile -t integration_test/qa/r17_day_test.dart`),
  installed with `xcrun devicectl device install app` and started with `devicectl device process launch`.
- **No driver:** the integration test runs inside the app on its own.
- **Reporting:** it sends its checks and screenshots over the LAN to a small host helper, `r17_host.py`. The helper also serves the OTP
  lines from the API log.
- **Probe first:** a probe proved the iPhone app reaches the API (`GET /api/v1/sync/pull → 401`, `logs/r17_iphone_host.log`).

So every iPhone item below ran **on the real iPhone**. Nothing was moved to the emulator.

Limits of this way of testing:
- **Typing:** in profile builds, `tester.enterText` does not reach the field, on the iPhone and on Android alike. The test sets the text
  on the field's controller and calls `onChanged`, as the keyboard would. The input formatters are skipped there (noted as `typeR` in
  the logs). Taps, the PIN keypad, the restock / price keypads and the HID "scanner" key events are real.
- **Overflow checks:** profile builds do not report Flutter's debug overflow errors. Item 24 checks positions, hit-testing and cut text
  instead.
- **Screenshots:** iPhone screenshots are the app's own frame (render layer), not the iOS screen. System sheets would not appear in them.

### Android storage

The emulators have about 390 MB free.
- **The debug APK does not fit:** the 209 MB debug APK (a 141 MB kernel blob) failed with "not enough space".
- **flutter drive wiped the data:** a 72 MB profile APK installed once. On the next `flutter drive`, the re-install failed with
  INSTALL_FAILED_INSUFFICIENT_STORAGE, and flutter fell back to "Uninstalling old version", which wiped the app data. The first item-9
  attempt was invalid because of this (`logs/r17b_A9_cart_check*.log`; it is not counted).
- **Fix:** Android then used the same driverless approach as the iPhone. One profile APK was installed once, and each step was started
  with `am force-stop` plus the launcher intent (`r17_android_launch.sh`). The step came from the host.
- **Freed space:** a stale 193 MB `/data/local/tmp/app.apk` from June (a leftover flutter staging file) was deleted from the emulator.
- **Failed workaround:** a QA AVD with an 8 GB data partition was created. It crashed at boot ("mprotect failed: Permission denied") and
  was deleted.

The emulator clock is about 13 s behind the Mac. Android note times are emulator time; `[launch]` lines are Mac time.

## Results per checklist item

| # | Item | Device | Result | Evidence (one line) |
|---|---|---|---|---|
| 1 | Register grocery shop with "ကြိုတင်စာရင်း", OTP, PIN → first download, Home, no 500; preset products on the server | iPhone | **PASS** | `logs/r17b_P_register.log`, `r17_P1_register_try3.log`: unlocked, firstSyncDone, route `/`, no notice, no sync error, 20 products, outbox 0. Server: `logs/r17_db_case1_products.txt` (r17: 20), `r17_db_after_iphone_day.txt` (r17b: 20). API log: 0 fail / 5xx lines (`r17_api_log_errors.txt`) |
| 2 | Close and reopen → PIN unlock | iPhone | **PASS** | New process (devicectl `--terminate-existing`) → route `/unlock`, "PIN နံပါတ် ထည့်ပါ" → 111111 → Home with the shop name (`logs/r17b_P_reopen.log`, `r17_P2_reopen_pin_screen.png`) |
| 4 | Restock 3 products | iPhone | **PASS** | ဆား 10 + 5 (opening count, then a tracked restock), ကြက်ဥ 30, သကြား 5 → 15 / 30 / 5 (`logs/r17b_P_day.log`, `r17_P4_*`) |
| 5 | Cash sale, barcode typed (no camera) → stock down, receipt | iPhone | **PASS** | HID key burst "8850999171001" + Enter adds ဆား, a tap adds the 2nd → 1,000 Ks cash, receipt "ရောင်းပြီးပါပြီ", stock 15 → 13 |
| 6 | Product with no selling price → app asks | iPhone | **PASS** | သကြား (preset, price 0) → "ဈေးနှုန်း ထည့်ပါ" → 6500 on the keypad → sale 6,500, price saved on the product |
| 7 | KBZPay → payment method correct | iPhone | **PASS** / new **BUG-64** | Sale `method: kbz` (phone and server), sale detail shows "KBZPay". The receipt itself names no method (BUG-64). New **BUG-65**: the receipt first says "လိုင်းမရှိဘဲ သိမ်းထားသည်" while online |
| 8 | Debt to a new customer → in debts list | iPhone | **PASS** | New customer "QA r17 ဒေါ်မြ" (Customers → ဖောက်သည်အသစ်) → debt sale 2,000 → "အကြွေးရှိသူ" lists her with 2,000 |
| 9 | (Android) item in cart, force-stop, reopen → cart restored | Android | **PASS** | Cart ကြက်ဥ×2 + ဆား×1 (1,100) → `am force-stop` (pid 6130 → gone) → launcher start → same cart, "ပစ္စည်း 3 ခု" (`logs/r17b_A9_cart_add_final.log`, `r17b_A9_cart_check_final.log`, `r17_A9_*.png`) |
| 12 | Half repayment → remaining correct | iPhone | **PASS** | Pay 1,000 → balance 1,000, debt screen "1,000 Ks"; "Viber သတိပေး" still shown |
| 15 | Edit customer (phone, credit limit) → saved, remaining next to limit | iPhone | **PASS** | Edit form "လက်ရှိ အကြွေး 1,000 Ks" beside the limit; saved phone 09790917173, limit 50,000 (phone and server) |
| 16 | Repay fully → "Viber သတိပေး" disappears | iPhone | **PASS** | "အကုန်ဆပ်" → balance 0, the button is gone |
| 17 | Void a sale → stock restored, receipt "ပယ်ဖျက်ပြီး" | iPhone | **PASS** | Void the cash sale → ဆား 9 → 11, receipt shows "ပယ်ဖျက်ပြီး" (`r17_P17_receipt_voided.png`); server `VoidedAt` set |
| 18–19 | (Android) airplane mode, 2 sales, airplane off → synced (DB) | Android | **PASS** | Airplane on (positive control: API GET → SocketException) → D-0001 cash 300, D-0002 debt 500, both "saved offline", outbox 2 → airplane off after 90 s → outbox 0 in 6 s **without a manual sync**. On the server: `logs/r17_db_case18_19.txt` |
| 20 | Sign in to the same shop on Android → all iPhone sales | Android | **PASS** | 4 of 4 iPhone sales (A-0001 voided … A-0004), the voided one marked; stock and prices identical (`logs/r17b_A20_signin_final.log`) |
| 21 | Android: change a price, delete a barcode → on the iPhone after sync | Android → iPhone | **PASS** | Android: ကြက်ဥ 300 → 350, ဆား barcode cleared (server `r17_db_case21.txt`). iPhone: price 350, barcode null, the old barcode typed at POS → "ဒီ Barcode နဲ့ ပစ္စည်း မရှိသေးပါ", POS sells ကြက်ဥ at 350 (`logs/r17b_P_verify_try2.log`) |
| 22 | Totals from the server DB vs Dashboard and Reports, both phones | both | **PASS** | Server (today, Asia/Yangon): sales **10,200 Ks**, **5** sales, profit **700 Ks** (known costs only), **1** unknown-cost line, debt **500**. iPhone and Android Dashboard and Reports ("ဒီနေ့") show exactly 10,200 Ks / 5 ကြိမ် / 700 Ks / "အရင်းမသိ 1 ခု မပါ" / 500 (`logs/r17b_P_verify_try2.log`, `r17b_A22_totals.log`, `r17_P22_*`, `r17_A22_*`) |
| 23 | Wrong PIN 5 times → 15-minute lockout | iPhone | **PASS** | Messages "… ၄ / ၃ / ၂ / ၁ ကြိမ်" then "PIN မှားတာ များသွားလို့ ၁၅ မိနစ် ပိတ်ထားပါတယ်။"; `lockRemaining` 14:57; the correct PIN is then refused (`logs/r17b_P23_pinlock.log`) |
| 24 | (Android) font_scale max → POS buttons not hidden / overflowing | Android | **PASS** / new **BUG-66** | font_scale 2.0 (text scale 2.0 in the app): "ငွေရှင်းမယ်", "ပစ္စည်းများ", "အမြန်ရောင်း" and the checkout confirm button are on screen and hit-testable. Labels cut: "အတည်ပြုပြီး ပြေစာ…", cart total "850 / Ks", names broken mid-word (BUG-66; `r17_A24_*_font_max_screen.png`) |
| – | Uncommitted `api_error.dart` | unit | **PASS** | `m/qa/qa_round17_test.dart` (TC-SYNC-NEW-31): 3/3 with the change. With `api_error.dart` stashed, 2 of 3 fail (`Expected: ဆာဗာမှာ ပြ… Actual: တစ်ခုခု မှ…`); restored afterwards |

Server cross-check of the iPhone day: `logs/r17_db_after_iphone_day.txt`. It shows:
- sales A-0001 (voided) to A-0004 with methods cash, cash, kbz and debt;
- the customer's phone and limit;
- debt entries creditSale 2,000, payment 1,000 and payment 1,000.

The iPhone's clock is about 33 s ahead of the server (`CreatedAt` > `ReceivedAt`). This did no harm.

### Side runs (QA mistakes, not the app; not counted)

| Run | What happened |
|---|---|
| `r17_P1_register`, `_try2` | QA's typing and screenshot code did not work in profile mode (see the typing limit above; the screenshot came out at double scale). Fixed in QA code |
| `r17_P_day`, `_try2`, `_try3` (shop r17) | Each failure was in QA code, not the app: the HID key events had no physical key; product tiles were below the fold. Try 3 also showed the product working as specified: the open cart of the aborted try 2 was restored (1 + 2 = 3 × ဆား). QA's checks assumed an empty cart and had a fixed "+2" for the void. The full day was then re-run cleanly on shop r17b (`r17b_P_day`) |
| `r17b_P_verify` | QA compared "10,200" against "10,200 Ks" (MoneyText draws one string) |
| `r17b_A20_signin`, `_try2` and `r17b_A9_cart_*` without `_final` | Android storage: install refused, then flutter uninstalled the app (see above) |

## New bugs (all Low)

- **BUG-64 · TC-POS-NEW-18:** the receipt does not say how the sale was paid. A KBZPay customer's receipt has no "KBZPay"; the sale
  detail does show it. Owner decision.
- **BUG-65 · TC-SALE-NEW-2:** an ONLINE sale's receipt first says "လိုင်းမရှိဘဲ သိမ်းထားသည် · လိုင်းရရင် Sync လုပ်ပါမယ်" until the
  2-s push has run (gone after 1.3 s). The cashier may think the phone is offline.
- **BUG-66 · TC-UX-NEW-24:** Android font 2.0 at the default display size cuts some labels:
  - the checkout button: "အတည်ပြုပြီး ပြေစာ…";
  - the cart total: "850 / Ks";
  - product names, mid-word.

  Buttons stay usable (BUG-59 family).

Still open from earlier rounds (unchanged): BUG-37, 38, 39, 42, 48, 49, 50, 59 (part), 61, 62, 63.

## Suite totals

| Suite | Command | Result |
|---|---|---|
| Mobile analyze | `cd mobile && flutter analyze` | No issues found (`logs/r17_suite_analyze.log`) |
| Mobile tests | `cd mobile && flutter test` | **750 passed, 14 skipped, 7 failed** (`logs/r17_suite_flutter_test.log`). These are the 7 known QA bug tests: `qa_round12_report_test` (BUG-38), `qa_round12b_bug36_test` (BUG-39), `qa_round14_debt_test` (BUG-48), `qa_round14_lookalike_test` ×2 (BUG-49, BUG-50), `qa_round16_test` ×2 (BUG-61, BUG-62). Same as round 16. The run was before `qa_round17_test.dart` existed; that file is 3/3 on its own |
| Backend | `cd backend && dotnet test` | Domain 20 / 0, Api 276 / 0, QA 39 passed / 4 failed (BUG-37, TC-AUTH-NEW-2, unchanged) (`logs/r17_suite_dotnet_test.log`) |

## Release recommendation: **Go** for a 3–5 shop beta

Why:
- No Critical / High / Medium bug is open.
- The full owner's day passed on a real iPhone and on Android:
  - no sale lost or doubled;
  - offline sales sync by themselves;
  - the two phones and the server agree to the kyat;
  - the preset catalog reaches the server.

Conditions (carried over): MANUAL 1 of round 16 (release APK over **https**), the dev sa password rotated, and the MANUAL list below.

## MANUAL cases for the owner (real phones, in this order)

1. **iPhone: reinstall the normal app.** The iPhone now has the round-17 *profile test build* of ZayPOS. It is signed in to "QA r17b
   ကုန်စုံ" and PIN-locked until about 22:41. Reinstall from Xcode / `flutter run` with
   `--dart-define=API_BASE_URL=http://<Mac IP>:5076`. Before the first sign-in, iOS may ask for "Local Network": answer Allow.
2. **#9, iPhone half.** Put 2 items in the cart → swipe the app away in the app switcher → reopen → PIN → POS: the cart must still be there.
3. **#18–19, iPhone half.** Control Centre → airplane mode ON → 2 sales (receipts say "လိုင်းမရှိဘဲ သိမ်းထားသည်") → airplane mode OFF →
   wait 30 s without touching sync → Settings: "Sync ပြီး", and the other phone sees both sales.
4. **#24, iPhone half.** Settings → Accessibility → Display & Text Size → Larger Text, max slider → POS with 2 items → checkout. All
   buttons must be visible and tappable. Note any cut label (BUG-66 on Android).
5. **#3 Camera barcode scan.** POS → barcode button → allow the camera the first time → scan a product: it lands in the cart. Deny once
   and check the message.
6. **#10 Viber send and receipt clarity.** Receipt → "ပြေစာ ပို့မယ်" → Viber → the customer receives a sharp, readable image. Also check
   whether the payment method is missing (BUG-64).
7. **#11 Save to Photos.** Receipt → "ပုံ သိမ်းမယ်" → first time: allow Photos → the image is in Photos.
8. **#13 Dialer.** A debtor with a phone → phone icon → the dialer opens with the number.
9. **#14 Real Viber reminder.** A debtor → "Viber သတိပေး" → Viber → the Burmese text arrives complete.
10. Carried over from round 16: MANUAL 1 (https release APK) and its list (Zawgyi phone, ≤ 2 GB phone, rotation, IMEIs).

## New test files (round 17)

- `mobile/integration_test/qa/r17_day_test.dart`: the checklist as steps (QA_STEP = register, reopen, day, signin, cart_add,
  cart_check, offline, edit, verify, totals, font, pinlock). It starts the app exactly like `lib/main.dart`, including the open-cart
  restore that `qa_harness.launchApp` leaves out.
- `mobile/integration_test/qa/r17_io.dart`: notes, screenshots, OTP and host commands through the host helper; the check collector;
  the `typeR` typing fallback.
- `mobile/integration_test/qa/r17_host.py`: the LAN host helper. It serves OTP lines only, notes, screenshots, `/step`, an adb
  airplane-mode window, font scale and screencap.
- `mobile/integration_test/qa/r17_ios_device.sh`: build profile → devicectl install / launch → wait for QA_DONE.
- `mobile/integration_test/qa/r17_android_launch.sh`: driverless Android steps (one APK, force-stop plus a launcher start).
- `mobile/integration_test/qa/r17_android_step.sh`: the `flutter drive` variant. It was used for the first Android sign-in; not usable
  at low storage.
- `mobile/integration_test/qa/r17_probe_test.dart`: the iPhone ↔ API reachability probe.
- `mobile/integration_test/qa/run_qa_android.sh`: + `airplane_on` / `airplane_off` commands (additions only).
- `mobile/test/qa/qa_round17_test.dart`: TC-SYNC-NEW-31 (api_error.dart 5xx mapping, 3 tests).
- Docs: `docs/qa/test-cases.md` (round note; 6 new rows: TC-AUTH-NEW-5, TC-POS-NEW-18, TC-SALE-NEW-2, TC-SYNC-NEW-31, TC-SYNC-NEW-32,
  TC-UX-NEW-24), `docs/qa/bugs.md` (BUG-64 … 66), this file, and `docs/qa/evidence/round-17/` (58 screenshots, `logs/`).

## Cleanup (`logs/r17_cleanup.log`)

- **Servers:** the API and the host helper are stopped; port 5076 is free.
- **Scratch DB:** `ZayPOS_QA_20261117_R17` was dropped. `ZayPOS`, `ZayPOS_SchemaRef` and the old `ZayPOS_QA_20261115_R12B` were not
  touched.
- **Emulator:** ZayPOS is uninstalled. font_scale 1.0, airplane mode disabled, density 420. `Medium_Phone_API_36.1` is still running.
  Also on the emulator: the stale `/data/local/tmp/app.apk` was deleted, and the QA AVD `ZayPOS_QA_r17` was deleted.
- **iPhone:** see MANUAL 1.
- **Evidence:** OTP codes are masked in the logs; no tokens or passwords (grep).
