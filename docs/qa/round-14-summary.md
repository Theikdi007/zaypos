# QA round 14: summary (2026-11-15, branch `fix/beta-buttons` @ 3f89623, PR #7, focused verification)

> ## Go for a 3–5 shop beta: no Critical, High or Medium bug is open
>
> **BUG-46 (Medium, owner) is verified** on the iPhone 17 simulator with the real plugins. "ဖုန်းခေါ်ရန်" launches
> `tel:09790011077` for the debtor's "09 790 011 077". The simulator has no Phone app, so iOS refuses and the app shows
> "ဖုန်းခေါ်လို့ မရပါ။", which is the expected simulator result. Without a phone the button is disabled, with the hint on screen and
> in its semantics. "Viber သတိပေး" opens the share sheet with a Burmese reminder that has the shop, the customer, "45,000 Ks" and
> "၁၅ နိုဝင်ဘာ ၂၀၂၆". The three hidden controls are gone and the screens around them are intact. "ယနေ့" is no longer tappable.
>
> **BUG-45 is verified.** Every image of a voided sale carries the red "ပယ်ဖျက်ပြီး" stamp: the share from the sale screen, and the
> share and the save from the receipt screen. The PNGs were taken off the simulator and checked for the stamp's red: 38,194 red
> pixels in each voided image, 0 in each valid one.
>
> A sweep of every screen on the simulator (30 screens plus the dialogs and sheets they open, 1,186 taps) found **no dead control**
> of the BUG-40/46 kind. Four new **Low** bugs (BUG-47 … BUG-50) are listed below; none blocks the beta.

Scope: BUG-45 and BUG-46 in 3f89623, a dead-control sweep of the whole app, a review of `m/no_dead_handlers_test.dart`, and the
suites. No product code was changed. Nothing was committed or pushed.

Setup: phone A = iPhone 17 (F48AF54E…, shop A's real on-disk data, PIN 222222); phone B = iPhone 17e (B0B2B653…, 390 × 844 pt).
Every run went through `m/integration_test/qa/run_qa.sh` with `EVD_DIR=docs/qa/evidence/round-14`. **No API and no database were
used:** the checks need no server, so nothing was synced and no scratch database was created (nothing to drop). Evidence (screenshots,
the receipt PNGs and `logs/`) is in `docs/qa/evidence/round-14/`.

## Suite totals

| Suite | Command | Start (developer's numbers reproduced) | End (with QA's round-14 files) |
|---|---|---|---|
| Mobile analyze | `cd mobile && flutter analyze` | No issues found | No issues found |
| Mobile tests | `cd mobile && flutter test` | **635 passed, 14 skipped, 3 failed** | **638 passed, 14 skipped, 6 failed** |
| Backend Domain | `cd backend && dotnet test` | 20 / 0 / 0 | 20 / 0 / 0 |
| Backend Api | (same run) | 120 / 0 / 0 | 120 / 0 / 0 |
| Backend QA | (same run) | 39 passed, 4 failed | 39 passed, 4 failed |

- **Start = the developer's numbers exactly.** The 3 mobile failures were TC-RPT-NEW-4 (BUG-38), TC-DEBT-NEW-11 (BUG-39) and
  `qa_round13_dead_buttons_test.dart::TC-UX-NEW-10`. The 4 backend QA failures are `QaRound12Tests.TC_AUTH_NEW_2_…` (BUG-37: 3 theory
  cases plus the API test).
- **End: +3 passed, +3 failed.**
  - Newly passing: TC-UX-NEW-10, after QA updated its own test, and the 2 tests of `qa_round14_handlers_test.dart`.
  - Still failing: BUG-38 and BUG-39.
  - New failures: QA's 4 new bug tests. They are TC-DEBT-NEW-12 (BUG-47), TC-UX-NEW-13 (BUG-48), TC-UX-NEW-14 (BUG-49) and
    TC-UX-NEW-15 (BUG-50).
  - Backend: unchanged.
- **Counted simulator runs:**
  - `r14_debt_A`: PASS.
  - `r14_bug45_A_{valid,void_detail,void_receipt}`: PASS.
  - `r14_sweep_B_part{1,2,3,4_checkout}`: these exit 1 because they list every NOTHING. Each one was classified (see below).
- **Side runs, not counted (QA harness problems, not the app):**
  1. `r14_debt_A_SIDE_try1`: an `expect` failed while `FlutterError.onError` was replaced, which hangs `flutter drive`. The
     simulator tests now collect their checks and assert only after restoring the handler.
  2. `r14_bug45_A_void_receipt_SIDE_hang`: QA read a StreamProvider's `.future` without a listener, so the test hung.
  3. `r14_bug45_A_valid_try1_png_overwritten`: the copied PNG names restarted with every run and overwrote each other. `run_qa.sh`
     now puts the run name into them.
  4. `r14_sweep_B_SIDE_trial`.
  5. Sweep part 1's checkout screens: the harness opened Checkout with `go`, so "back" had nothing to pop. Part 4 re-ran them, pushed
     from POS as the app does, and "back" reacts.

## Results per item

| # | Item | Result | Evidence | What was seen |
|---|---|---|---|---|
| 1 | Debtor "ဖုန်းခေါ်ရန်" | **PASS** (sim) | `r14_debt_actions_test.dart`, `logs/r14_debt_A.log`, `r14_debt_call_*.png`, `r14_debt_nophone*.png` | **With a phone:** `outlet.call(tel:09790011077) → false (real url_launcher)`, then the snackbar "ဖုန်းခေါ်လို့ မရပါ။". The iOS log for that window (`syslog_tel`) has no openURL or tel: entry from the system; the simulator has no Phone app. **No phone:** "ဖုန်းနံပါတ် မရှိလို့ ခေါ်လို့ မရပါ" shows under the name and the icon is grey. Semantics are `label="ဖုန်းခေါ်ရန်" hint="ဖုန်းနံပါတ် မရှိလို့ ခေါ်လို့ မရပါ" isButton=true enabled=isFalse tap=false`. A tap calls nothing and shows nothing; a long press shows the hint as a tooltip. VoiceOver does not run on the simulator, so what it reads aloud is MANUAL. One side finding: the ENABLED button has no semantics tap action (BUG-48) |
| 2 | "Viber သတိပေး" | **PASS** (sim) | same run, `r14_debt_viber_share_sheet.png` | The iOS share sheet opens with the text preview and the targets Reminders, Copy and Save to Files (Viber is not installed). Text: `မင်္ဂလာပါ QA r12b ဒေါ်ခင်မြင့်မြင့်သန်း (…)` / `QA r12b ကုန်စုံ မှ အကြွေး သတိပေးစာ ဖြစ်ပါတယ်။` / `၁၅ နိုဝင်ဘာ ၂၀၂၆ နေ့အထိ ပေးရန်ကျန်ငွေ 45,000 Ks ရှိပါတယ်။` / `အဆင်ပြေတဲ့အချိန် ပေးချေပေးပါ။ ကျေးဇူးတင်ပါတယ်။`. Shop, customer, balance and date are all present. No failure message. Side finding: the button is also offered at 0 Ks (BUG-47) |
| 3 | Hidden controls | **PASS** | `m/qa/qa_round13_dead_buttons_test.dart` (updated); sweep screenshots `r14_sweep_screen_{add_customer,reports,checkout_KBZPay,checkout_WavePay,sales}.png` | None of the contact picker, Reports "Excel" or the KBZPay / WavePay screenshot box is on screen or among the sweep's tappables. The Add Customer phone field spans the name field's width (36..354). The Reports header holds the title alone. Checkout under KBZPay / WavePay ends after the method tiles, with no gap artefact and no layout exception. "ယနေ့" has no tap handler and is not a semantics button, but it is still drawn like the old button (BUG-49). No overflow on any of the 30 swept screens (`SWEEP_ERRORS none`) |
| 4 | BUG-45 stamp | **PASS** | `r14_bug45_voided_test.dart`, `logs/r14_bug45_A_*.log`, PNGs `r14_bug45_*_{shared,saved}_*.png` | `valid_saved_E-0118 red=0`, `valid_shared_E-0118 red=0`, `void_detail_shared_E-0117 red=38194 (4.62%)`, `void_receipt_shared_E-0117 red=38194`, `void_receipt_saved_IMG_0010 red=38194` (Photos 9 → 10), all 1080 × 765. On screen, the voided receipt shows 1 stamp and the valid receipt 0. The stamp is readable and the receipt stays legible around it |
| 5 | `no_dead_handlers_test.dart` | **adequate today, too narrow** | `m/qa/qa_round14_handlers_test.dart` (TC-UX-NEW-12, PASS) | It checks only Flutter's own callback names, but the app passes taps as `onBack` (13×), `onKey` (7×), `onPick`, `onScan`, `onEdit`, `onRestock`, `onResend`, `onReverse` and Switch / tab `onChanged`. It also misses `onTap: _noop` and log-only bodies: **7 of 7** such snippets pass it. QA's wider scan (every `on<Name>:`, empty tear-offs, log-only) finds nothing in lib/ today. No static scan can see a control with no handler at all (BUG-49, BUG-50); only the sweep does |
| — | Sweep (TC-UX-NEW-11) | **PASS** (no dead control) | `r14_sweep_test.dart`, `logs/r14_sweep_B_part*.log`, `r14_sweep_screen_*.png`, `r14_sweep_DEAD_*.png` | 30 screens, scrolled to the end, plus one level into every dialog and sheet: 1,186 taps. Platform actions were recorded rather than launched (items 1, 2 and 4 covered the real plugins). The NOTHING results are either by design or BUG-50. By design: the already-selected tab or chip, "0" / "00" / "⌫" on an empty amount (POS, restock sheets), and the quantity sheet's "1" over a prefilled 1. BUG-50: quick sale "+ ခြင်းထဲထည့်မယ်" at 0 Ks, and checkout "−" at quantity 1. Not reached: chips scrolled off screen sideways (sales "အကြွေး"), Settings "ယခု sync လုပ်မယ်" (sync is off on the fake repos) and the sync-review / rejected-unit screens with data. Earlier rounds cover these |

## New bugs (round 14), all Low

- **BUG-47 · Low** · TC-DEBT-NEW-12: "Viber သတိပေး" sends a debt reminder of "0 Ks" to a customer who owes nothing. After an
  overpayment, the amount would be negative.
- **BUG-48 · Low** · TC-UX-NEW-13: with a screen reader, enabled icon buttons cannot be activated. This covers the bottom nav, the
  PIN and amount keypads, back / close, the debtor's phone icon, "Barcode ဖတ်မယ်", restock and the checkout qty buttons: they have no
  semantics tap action. PrimaryButtons are not announced as buttons. Real-phone TalkBack check needed; if TalkBack cannot unlock or
  switch tabs, rate it Medium.
- **BUG-49 · Low** · TC-UX-NEW-14: these look like their tappable twins but do nothing:
  - the dashboard "အကြွေးရရန်" card;
  - the dashboard recent-sale rows;
  - sales "ယနေ့", still drawn as a button.
- **BUG-50 · Low** · TC-UX-NEW-15: these buttons silently do nothing in their "not yet" state:
  - POS "ငွေရှင်းမယ်" with an empty cart is disabled but drawn in full colour;
  - quick sale "+ ခြင်းထဲထည့်မယ်" at 0 Ks;
  - checkout "−" at quantity 1.

## Case totals after round 14 (208 cases)

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 14 | 1 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 5 | 0 | 0 | 0 |
| 4 PROD | 46 | 0 | 0 | 2 |
| 5 POS | 26 | 0 | 0 | 2 |
| 6 SALE | 5 | 0 | 0 | 0 |
| 7 DEBT (+2 new) | 17 | 2 | 0 | 0 |
| 8 RPT | 7 | 1 | 0 | 0 |
| 9 SYNC | 44 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX (+5 new) | 17 | 4 | 0 | 0 |
| **Total** | **195** | **8** | **0** | **5** |

Changed this round:
- TC-SALE-NEW-1: FAIL → PASS.
- TC-UX-NEW-10: FAIL → PASS.

New this round:
- TC-DEBT-NEW-12: FAIL.
- TC-DEBT-NEW-13: PASS (sim).
- TC-UX-NEW-11: PASS.
- TC-UX-NEW-12: PASS.
- TC-UX-NEW-13, TC-UX-NEW-14 and TC-UX-NEW-15: FAIL.

All 8 FAIL rows are Low:
- TC-AUTH-NEW-2 (BUG-37)
- TC-DEBT-NEW-11 (BUG-39)
- TC-RPT-NEW-4 (BUG-38)
- TC-UX-03 (BUG-42)
- TC-DEBT-NEW-12 (BUG-47)
- TC-UX-NEW-13 (BUG-48)
- TC-UX-NEW-14 (BUG-49)
- TC-UX-NEW-15 (BUG-50)

The other rows were not re-executed this round. The suites above are green for them.

## Bugs by severity (open)

Critical: none. High: none. **Medium: none.** BUG-46 is verified.

Low, beta backlog:
- BUG-37: the server accepts Shan, Arabic-Indic and full-width digits in phone numbers.
- BUG-38: the chart's screen-reader label says "ယနေ့နေ့".
- BUG-39: a full "959…" number typed without "+" is not found.
- BUG-42: with accessibility text sizes, POS and the PIN keypad cannot be used.
- **BUG-47 (new)**: a debt reminder is sent for 0 Ks.
- **BUG-48 (new)**: enabled buttons cannot be activated with a screen reader.
- **BUG-49 (new)**: the dashboard debt card and recent sales, and the sales "ယနေ့" label, look tappable but do nothing.
- **BUG-50 (new)**: buttons in a "not yet" state silently do nothing; the empty-cart "ငွေရှင်းမယ်" is not dimmed.

Verified this round: BUG-45, BUG-46.

## Release recommendation (3–5 shop beta)

**Go.** The owner's exit rule is met: no Critical, High or Medium bug is open.
- The beta blocker BUG-46 works on the simulator with the real url_launcher and share_plus.
- BUG-45 holds on every share and save path.
- The whole-app sweep found no other control of the BUG-40/46 kind.
- The four new bugs are Low:
  - BUG-49 and BUG-50 are display or boundary states, not actions that never work.
  - BUG-47 is visible to the shop in the share sheet before it is sent.
  - BUG-48 matters only to screen-reader users.

Before or with the beta:
1. The owner runs MANUAL items 1–3 below on a real phone. If TalkBack cannot unlock the app or switch tabs (BUG-48), the verdict
   becomes "No-go until BUG-48" for any shop whose staff use TalkBack.
2. Optional and small: hide "Viber သတိပေး" at a balance of 0 or less (BUG-47), and dim disabled PrimaryButtons (BUG-50).

Conditions (unchanged):
- The owner runs the MANUAL list first.
- Release builds use an https `API_BASE_URL`.
- The dev sa password is rotated.
- Photos stay on the phone.

## MANUAL cases for the owner (real phone, in this order)

1. **TC-DEBT-NEW-13** (BUG-46), on an iPhone and on an Android phone:
   - Customers → a debtor with a phone → tap the green phone icon. The dialer must open with that number (on Android 11+, this
     also checks the new `<queries>` entry).
   - Tap "Viber သတိပေး" → choose Viber → send it to yourself. The Burmese text must arrive with the shop, the name, the balance in
     Ks and today's date.
   - Open a customer without a phone. The icon must be grey.
   - With VoiceOver (iPhone) or TalkBack (Android) on, swipe to the icon. It must read "ဖုန်းခေါ်ရန်", dimmed / disabled, and
     "ဖုန်းနံပါတ် မရှိလို့ ခေါ်လို့ မရပါ".
2. **TC-SALE-NEW-1** (BUG-45): sell once, void the sale on its screen, then "ပြေစာ ပို့မယ်" → Viber → yourself. The image must show the
   large red "ပယ်ဖျက်ပြီး". On the receipt screen of a valid sale, "ပုံ သိမ်းမယ်" must save an image without the stamp.
3. **TC-UX-NEW-13** (BUG-48): with TalkBack on an Android phone, then VoiceOver on an iPhone:
   - unlock with the PIN keypad;
   - switch the bottom tabs;
   - open a debtor and double-tap the phone icon;
   - on POS, use the amount keypad.

   Note what does not respond. If TalkBack cannot unlock or switch tabs, report it: BUG-48 becomes Medium.
4. Carried over from round 13, unchanged (steps in `round-13-summary.md`):
   - TC-POS-11 (receipt share and save; also Android 10 or lower);
   - TC-AUTH-NEW-3 (Myanmar keyboard);
   - TC-UX-03 (small phone, largest text);
   - the upgrade check (TC-UX-NEW-6);
   - TC-UX-01 (airplane mode, first launch);
   - TC-RPT-NEW-1 in a release build;
   - TC-POS-NEW-9, TC-POS-NEW-10, TC-PROD-NEW-34, TC-PIN-05, TC-UX-06, TC-UX-05 and TC-SYNC-NEW-28.

## New and changed test files (round 14, uncommitted)

- `mobile/integration_test/qa/r14_debt_actions_test.dart`: BUG-46 on the simulator, real plugins, recording wrapper.
- `mobile/integration_test/qa/r14_bug45_voided_test.dart`: QA_STEP = valid | void_detail | void_receipt.
- `mobile/integration_test/qa/r14_sweep_test.dart`: TC-UX-NEW-11, QA_PHASE = screen names; includes the semantics audit.
- `mobile/test/qa/qa_round14_handlers_test.dart`: TC-UX-NEW-12 (passes).
- `mobile/test/qa/qa_round14_debt_test.dart`: TC-DEBT-NEW-12 (fails → BUG-47) and TC-UX-NEW-13 (fails → BUG-48).
- `mobile/test/qa/qa_round14_lookalike_test.dart`: TC-UX-NEW-14 (fails → BUG-49) and TC-UX-NEW-15 (fails → BUG-50).
- Changed `mobile/test/qa/qa_round13_dead_buttons_test.dart` (QA's own test):
  - The three hidden controls are now checked as absent (the case's expected result is "reacts … or is hidden").
  - The call and Viber probes use the real outlet and wait in real time (`runAsync`).
  - It checks that the phone field is full width and that "ယနေ့" is not tappable.
  - The positive control is kept, and nothing was weakened: every probe must still react, and absent controls are asserted.
- Changed `mobile/integration_test/qa/run_qa.sh`:
  - new `syslog_tel` host command;
  - the copied `photos_*` / `apptmp_*` file names now include the run name.

## Cleanup

- No API was started and no scratch database was created this round, so there is nothing to drop. **Round 13's scratch DB
  `ZayPOS_QA_20261115_R12B` still exists.** The owner must drop it by name, as noted in round 13.
- **Simulator A, shop A** now has QA data that is not yet synced. It will go to the R12B database the next time the app runs against
  the API:
  - the customer "QA r14 ဖုန်းမရှိ";
  - sale E-0117 (voided);
  - sale E-0118.
  - Photos also gained IMG_0009–0011 (receipts). The Photos permission for ZayPOS is reset to "not asked".
- **Simulator B** runs the sweep test build. The sweep used in-memory data and an in-memory key store, so B's stored shop data and
  Keychain were not touched. The text size is unchanged.
