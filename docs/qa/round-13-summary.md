# QA round 13: summary (2026-11-15, branch `fix/beta-receipt` @ 71dfd5b, PR #6, focused verification)

> ## Go for a 3–5 shop beta: no Critical, High or Medium bug is open
>
> **BUG-40 (Medium, the blocker) is verified** on the iPhone 17 simulator with the real plugins. "ပုံ သိမ်းမယ်" puts a
> 1080 × 765 PNG into Photos and shows "သိမ်းပြီးပါပြီ". "ပြေစာ ပို့မယ်" opens the iOS share sheet from the receipt screen and from the
> sale screen. A refused permission shows the Burmese message and saves nothing. The first use shows the Burmese
> NSPhotoLibraryAddUsageDescription. **BUG-41, BUG-43 and BUG-44 are verified** on the iPhone 17e simulator. BUG-41 and BUG-43 were
> also checked live against the API.
>
> Two new **Low** bugs:
> - **BUG-45:** a voided sale's shared receipt looks like a valid receipt.
> - **BUG-46:** five other buttons do nothing. They are the same pattern as BUG-40.
>
> QA recommends hiding the BUG-46 buttons before the beta, or telling shops about them. Neither bug blocks the beta under the
> owner's rule.

Scope: the 4 fixes in 71dfd5b (BUG-40, 41, 43, 44) on the iOS simulators, plus the suites. BUG-42 is not fixed and is out of scope.
No product code was changed and nothing was committed.

The simulators were driven by `flutter drive` through `m/integration_test/qa/run_qa.sh`, against the API on localhost:5076. The API
used scratch DB `ZayPOS_QA_20261115_R12B`, which round 12b left behind. Its migrations were up to date and no migration was pending.
Phone A was the iPhone 17 (F48AF54E…) and phone B the iPhone 17e (B0B2B653…, 390×844 pt). Evidence is in
`docs/qa/evidence/round-13/` (screenshots, the saved and shared PNGs) and `logs/`.

## Suite totals (recorded this round)

| Suite | Command | Passed | Failed | Skipped |
|---|---|---|---|---|
| Mobile analyze (start = end) | `cd mobile && flutter analyze` | No issues found | — | — |
| Mobile tests (start of round, before r13 files) | `cd mobile && flutter test` | **615** | **2** | **14** |
| Mobile tests (end of round, with r13 files) | `cd mobile && flutter test` | **615** | **4** | **14** |
| Backend Domain | `cd backend && dotnet test` | 20 | 0 | 0 |
| Backend Api | (same run) | 120 | 0 | 0 |
| Backend QA | (same run) | 39 | **4** | 0 |
| Simulator runs (counted) | `run_qa.sh` | 10 | 0 | — |

- **The start counts match the developer's numbers exactly.** Mobile is 615 / 2 / 14, failing TC-RPT-NEW-4 (BUG-38) and TC-DEBT-NEW-11
  (BUG-39). Backend is Domain 20/0/0, Api 120/0/0 and QA 39/4/0. The 4 QA failures are `QaRound12Tests.TC_AUTH_NEW_2_…`
  (BUG-37): 3 theory cases plus the API test. Against round 12b (587 passed) the mobile suite has +28 passing tests. These are the
  developer's new tests (`receipt_image_test`, `myanmar_digit_input_test`, `pos_large_text_test`, `db_migration_test`).
- **End: 615 / 4 / 14.** The 2 extra failures are QA's two new bug tests: `qa_round13_receipt_test.dart::TC-SALE-NEW-1` (BUG-45)
  and `qa_round13_dead_buttons_test.dart::TC-UX-NEW-10` (BUG-46). The second file was re-run alone after it was renamed from
  TC-UX-NEW-7, which was already taken; it still fails as expected. The backend was not changed and was run once.
- **Counted simulator runs:** `r13_bug40_A_{save,detail,voided,denied,prompt}`, `r13_bug41_B_{login,reset}`,
  `r13_bug43_B_seed_r8` with `r13_bug43_B_upgrade_head`, `r13_bug44_B_xxxl`, and `r13_r12b09_B_xxxl` (the round-12b sweep, re-run).
  All passed.
- **Side runs, not counted. The QA harness caused them, not the app:**
  1. `r13_bug43_B_upgrade_head_SIDE_buildfail.log`: QA's check file did not compile (missing import). `flutter drive` then ran
     the **previously built** app, the r12b_09 font test, on top of the round-8 install, and that consumed the upgrade.
     `run_qa.sh` now runs `flutter analyze` (errors only) first and refuses to start if it fails.
  2. `*_SIDE_try2*`: a clean re-seed and upgrade. QA's assertion "exactly 1 offline product" was wrong because try 1 had
     already sent a product with the same name. All the counts were equal and the unsent unit was sent.
     QA corrected the assertion: the seed now records its own count. The final pair ran from a fresh uninstall.

## Results per bug

| Bug | Result | Evidence (`m/integration_test/qa/…`, logs in `evidence/round-13/logs/`) | What was seen |
|---|---|---|---|
| **BUG-40** (Medium) | **verified** | `r13_bug40_receipt_test.dart`, `r13_bug40_A_*.log`; `m/receipt_image_test.dart` | Label "ပြေစာ ပို့မယ်", no "Viber" text. Save with permission granted: snackbar "သိမ်းပြီးပါပြီ", Photos `count 6 → 7`, `IMG_0007.PNG pixelWidth:=1080 pixelHeight:=765` (`r13_pos11_photos_IMG_0007.png`: shop, receipt no., Myanmar date, line, total, "ကျေးဇူးတင်ပါတယ်", all readable). The share sheet ("PNG · 72 KB" with the receipt preview) opens from the receipt screen and from the sale screen; the shared file `Library/Caches/ZayPOS-receipt-E-0116.png` is 1080 × 765. `simctl privacy revoke photos-add`: the Burmese denied message appears and Photos stays at 7. `reset`: the iOS alert shows "ပြေစာပုံကို ဓာတ်ပုံများထဲ သိမ်းဖို့ ခွင့်ပြုပေးပါ။". No framework error in any run. The "failed" message could not be forced on the simulator; only the developer's fake-outlet test covers it. Viber is not on the simulator |
| **BUG-41** (Low) | **verified** (live) | `r13_bug41_auth_test.dart`, `r13_bug41_B_login.log`, `r13_bug41_B_reset.log`; `m/myanmar_digit_input_test.dart` | Register phone "၀၉ ၇၉၀ ၉၁၇ ၀၆၁" → "09 790 917 061", and the API sends the OTP to +959790917061. OTP "၀၆၁၂၂၆" → "061226". Login "၀၉ ၇၉၀ ၉၁၇ ၀၅၁" / "၂၂၂၂၂၂" → shop "QA r12b ကုန်စုံ". Reset with phone, code, PIN and repeat all in Myanmar digits → `[655354, 222222, 222222]`; the server accepts them and the phone signs in. The server checks the register code only at the last register step, so it was not checked live; the developer's widget test covers it |
| **BUG-43** (Low) | **verified** (device upgrade, live) | `r13_bug43_upgrade_seed_r8_test.dart` (on e7cd138, `user_version=1`) + `r13_bug43_upgrade_check_test.dart` | Before: `cursor=…5615 products=34 customers=6 sales=117 issues=6 outbox=1 moves=124 stockSum=104000 debts=1`. After the upgrade and before unlock: `user_version=2 pullCursor=0`. After 2 syncs the counts are identical, `outbox rows left=0` (the offline product was sent), `issues with data NULL=0`, and "စစ်ရန်" names barcode 8850000099013 and both products. Round 12b's issue for barcode 8850000099003, pulled under v1, now has its data. The full re-pull doubled nothing |
| **BUG-44** (Low) | **verified** | `r13_bug44_large_text_test.dart` (`r13_bug44_B_xxxl.log`), `r12b_09_large_font_test.dart` re-run (`r13_r12b09_B_xxxl.log`); `m/pos_large_text_test.dart` | At ×1.353 on 390×844 with a 34 pt inset: no layout error on either POS tab, and both tabs are on screen. The cart bar is 50 pt above the screen edge. Scrolled to the end, the add button sits at `639..687` and the bar top at `703`; a tap adds 500. In the product grid the lowest tile ends at `687`, below the bar's top at `703`. The full xxxl screen sweep shows `layout problems: none` |

## New bugs (round 13)

- **BUG-45 · Low** · TC-SALE-NEW-1 (new) · The receipt image of a **voided** sale has no "ပယ်ဖျက်" mark: its PNG is
  byte-identical to the valid receipt (`identical=true`). The same was seen on the simulator (E-0116, voided, shared as a normal
  receipt). This is new with 71dfd5b; before it, the button did nothing. Beta backlog.
- **BUG-46 · Low** · TC-UX-NEW-10 (new) · Five more buttons do nothing. They are the debtor's "ဖုန်းခေါ်ရန်" and "Viber သတိပေး",
  Add Customer's contact picker (already named in BUG-40), Reports "Excel", and Checkout KBZPay/Wave "ငွေလွှဲပြေစာ ပုံ". The fixed
  receipt button serves as the positive control, and it reacts. QA rated this Low because each is a secondary action with a manual
  workaround. It is the same pattern BUG-40 was rated Medium for. **Owner's call.** QA recommends hiding them, or telling shops,
  before the beta.

## Case totals after round 13 (201 cases)

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 14 | 1 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 5 | 0 | 0 | 0 |
| 4 PROD | 46 | 0 | 0 | 2 |
| 5 POS | 26 | 0 | 0 | 2 |
| 6 SALE (+1 new) | 4 | 1 | 0 | 0 |
| 7 DEBT | 16 | 1 | 0 | 0 |
| 8 RPT | 7 | 1 | 0 | 0 |
| 9 SYNC | 44 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX (+1 new) | 14 | 2 | 0 | 0 |
| **Total** | **190** | **6** | **0** | **5** |

Changed: TC-POS-11 FAIL → PASS (sim), TC-AUTH-NEW-3 FAIL → PASS, TC-UX-NEW-6 FAIL → PASS. TC-UX-03 stays FAIL, now only for BUG-42.
FAIL rows, all Low: TC-AUTH-NEW-2 (BUG-37), TC-DEBT-NEW-11 (BUG-39), TC-RPT-NEW-4 (BUG-38), TC-UX-03 (BUG-42),
TC-SALE-NEW-1 (BUG-45), TC-UX-NEW-10 (BUG-46). The other rows were not re-executed this round. Their evidence is from round 12/12b;
the suites above are green for them.

## Bugs by severity (open)

Critical: none. High: none. Medium: none.

Low, beta backlog:
- BUG-37: the server accepts Shan, Arabic-Indic and full-width digits in phone numbers.
- BUG-38: the chart's screen-reader label says "ယနေ့နေ့".
- BUG-39: a full "959…" number typed without "+" is not found.
- BUG-42: with accessibility text sizes, POS and the PIN keypad cannot be used.
- **BUG-45 (new)**: a voided sale's receipt is not marked as voided.
- **BUG-46 (new)**: five other buttons do nothing.

Verified this round: BUG-40, BUG-41, BUG-43, BUG-44.

## Release recommendation (3–5 shop beta)

**Go.** The owner's exit rule is met: no Critical, High or Medium bug is open. The beta blocker BUG-40 works end to end on the
simulator. This includes the Photos permission paths and the Burmese permission text. The three Low fixes hold, live and through a real
device upgrade. A full re-pull after the upgrade loses and doubles nothing.

Before or with the beta:
1. **BUG-46:** hide the five dead buttons, or tell shops which actions are "coming later". If the owner rates "Viber သတိပေး" like
   BUG-40, this becomes Medium and the verdict becomes "No-go until BUG-46".
2. **BUG-45:** tell shops not to send the receipt of a voided sale. Or mark the image as voided, which is a small change.
3. Drop the scratch DB `ZayPOS_QA_20261115_R12B` (see Cleanup).

Conditions (unchanged): the owner runs the MANUAL list first; release builds use an https `API_BASE_URL`; the dev sa password is
rotated; photos stay on the phone.

## MANUAL cases for the owner (real phone, in this order)

1. **TC-POS-11:** sell once.
   - On the receipt, tap "ပြေစာ ပို့မယ်", choose Viber and send it to yourself. The image must arrive readable.
   - Tap "ပုံ သိမ်းမယ်" and Allow. "သိမ်းပြီးပါပြီ" must show, and the receipt must be in Photos.
   - Settings → ZayPOS → Photos → None, then tap again. The Burmese "ခွင့် မရပါ" message must show.
   - Sales → the sale → "ပြေစာ ပို့မယ်". The share sheet must open.
   - On Android, also check one phone on Android 10 or lower (WRITE_EXTERNAL_STORAGE).
2. **TC-AUTH-NEW-3:** with the real Myanmar keyboard, type the phone, OTP and PIN in Myanmar digits on Login and on
   "PIN မေ့နေပါသလား?". The fields must show 0-9 and sign-in must work.
3. **TC-UX-03:** use a real small phone at the largest standard text size. Open POS "အမြန်ရောင်း" and "ပစ္စည်းများ" and scroll to the
   end. Nothing may be hidden under the dark cart bar or the home bar.
4. Upgrade check (TC-UX-NEW-6): on a phone with an older build and an entry in "စစ်ရန်", install this build over it. Unlock, then run
   "ယခု sync လုပ်မယ်". The entry must name the barcode and the products, and nothing may be lost.
5. TC-UX-01: delete the app, turn airplane mode ON, install, and open the app. The Myanmar text must render.
6. TC-RPT-NEW-1 in a release build.
7. TC-POS-NEW-9 (camera scan), TC-POS-NEW-10 (Bluetooth scanner), TC-PROD-NEW-34 (camera / HEIC photo), TC-PIN-05 (low-end
   Android), TC-UX-06 (one hour: battery and heat), TC-UX-05 once, TC-SYNC-NEW-28 with two phones. Steps are in the round-12b list.

## New test files (round 13, uncommitted)

- `mobile/integration_test/qa/r13_bug40_receipt_test.dart` (QA_STEP = save | detail | voided | denied | prompt)
- `mobile/integration_test/qa/r13_bug41_auth_test.dart` (QA_STEP = login | reset)
- `mobile/integration_test/qa/r13_bug43_upgrade_seed_r8_test.dart` (runs on an export of e7cd138) and `r13_bug43_upgrade_check_test.dart`
- `mobile/integration_test/qa/r13_bug44_large_text_test.dart`
- `mobile/test/qa/qa_round13_receipt_test.dart`: TC-SALE-NEW-1 (fails → BUG-45)
- `mobile/test/qa/qa_round13_dead_buttons_test.dart`: TC-UX-NEW-10 (fails → BUG-46)
- `mobile/integration_test/qa/run_qa.sh` (extended):
  - new `photos` and `apptmp` host commands;
  - `EVD_DIR` is honoured;
  - `flutter analyze` must pass before `flutter drive` starts.

## Cleanup

- The API on 5076 was stopped; nothing listens on 5076.
- **The scratch DB `ZayPOS_QA_20261115_R12B` was NOT dropped.** The dry run with the scratch connection string said "would drop
  the database 'ZayPOS_QA_20261115_R12B'", but the permission system refused the real `dotnet ef database drop --force`, as in
  round 12b. The owner must drop it by name. The dev DB `ZayPOS` was never connected to.
- Simulator A: the Photos permission for ZayPOS is reset to "not asked", and the voided sale E-0116 stays in shop A's QA data.
- Simulator B: the text size is back to default (`large`), and the app is this build, signed in to shop A.
- The e7cd138 export is in the session scratchpad only.
