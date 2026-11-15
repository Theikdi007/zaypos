# QA round 11 — summary (2026-11-14, branch `beta-polish` @ dbf2b5f)

> ## Go for a 3–5 shop beta (no Critical, High or Medium open)
>
> All three changes do what the owner asked, live with two phones included. **BUG-32** is verified on all 14 synced tables, for
> rejected → fixed → resent units, for several units over one row, across an app restart and in the first download. It also fixes a
> wider problem: when the server keeps the other phone's newer copy, the phone now converges to it. **BUG-33** is verified, and a
> lowered limit is used by the credit warning at sale time. The **duplicate-barcode auto-close** works on the server and on both phones
> (a later duplicate is a new entry; the owner's own resolution is kept).
>
> Two new Low bugs. **BUG-34**: the duplicate-phone warning misses the same number written with spaces or dashes. **BUG-35**: the
> report's 7-day chart breaks (NaN bar heights) when the last 7 days have no sales, which is what a new shop sees on day 1. Fixing
> BUG-35 before the beta is recommended (one line).

Scope: re-test of 17180db (BUG-32), ae22869 (BUG-33), 1420ee8 (duplicate-barcode auto-close), 618cb6d ("Batch · နံပါတ်") and dbf2b5f
(bugs.md), plus a review of the developer's two edits to QA files and a full regression. No product code was changed and nothing was
committed. No command was blocked by permissions.

## Suite totals (recorded this round)

| Suite | Command | Passed | Failed | Skipped |
|---|---|---|---|---|
| Mobile analyze | `cd mobile && flutter analyze` | No issues found | — | — |
| Mobile, all tests (start of round, before r11 files) | `cd mobile && flutter test` | 553 | 0 | 12 |
| Mobile, all tests (end of round, with r11 files) | `cd mobile && flutter test` | **568** | **2** | **13** |
| Backend Domain (start = end) | `cd backend && dotnet test` | 20 | 0 | 0 |
| Backend Api (start = end) | (same run) | 116 | 0 | 0 |
| Backend QA (start → end) | (same run) | 32 → **38** | 0 | 0 |
| Live (scratch DB `ZayPOS_QA_20261114_R11`, API 127.0.0.1:5077) | 13 files, one new phone + OTP each | **13** | **0** | 0 |

- The 2 mobile failures are exactly the new bug tests: `qa_round11_customer_edit_test.dart::TC-DEBT-NEW-8 …` (BUG-34) and
  `qa_round11_sync_history_test.dart::TC-RPT-NEW-1 …` (BUG-35). Skipped = the 13 live files without env vars. All round-10 tests pass,
  including the three that failed in round 10 (TC-SYNC-NEW-17 ×2, TC-DEBT-NEW-6).
- Live files: `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_step4_test.dart` (registers its own phone),
  `test/live_clear_fields_test.dart`, `test/qa/live_qa_round2..6_test.dart`, `test/qa/live_qa_round8..10_test.dart`,
  `test/qa/live_qa_round11_test.dart` (new). Phones +959790917001 … +959790917013, one per file, from a fixed list (two earlier trial runs of
  the new file used +959790917101 and +959790917201). Runner: `run_live_r11.sh` in the session scratchpad; it records flutter's exit code.
- The scratch DB was created with `dotnet ef database update` (latest migration `20261114141058_SyncIssueData`) and dropped by name
  afterwards (`DROP DATABASE [ZayPOS_QA_20261114_R11]`; it held 15 tenants). Remaining databases: `ZayPOS`, `ZayPOS_SchemaRef`. The API on
  5077 was stopped and Docker `zaypos-sql` was not touched. Dev DB `ZayPOS` has 0 QA tenants and 8 tenants in total: 7 from 2026-11-12
  (6 "Live …" plus "တရုတ်ကလေး", one more than the hand-over said) and "ဗမာ" (2026-11-14 02:56). None were touched.
- The round-10 live file now prints `A open=(false), B open=(false)` for the duplicateBarcode entry. The server closes it.

## Case totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 5 | 0 | 0 | 0 |
| 4 PROD | 46 | 0 | 0 | 2 |
| 5 POS | 25 | 0 | 0 | 3 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT (+1 fixed, +2 new) | 13 | 1 | 0 | 0 |
| 8 RPT (+1 new) | 4 | 1 | 0 | 0 |
| 9 SYNC (+1 fixed, +8 new) | 43 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX | 11 | 0 | 0 | 4 |
| **Total (189)** | **177** | **2** | **0** | **10** |

FAIL rows: TC-DEBT-NEW-8 (BUG-34), TC-RPT-NEW-1 (BUG-35).

## Verdicts on what changed

| Item | Verdict | Evidence (short) |
|---|---|---|
| 1. 17180db BUG-32 | **verified** (live) | **Every table:** one pending unit holding a row of each of the 14 synced tables is untouched by a page of changed server copies, and a bystander on the same page is merged. After the send the cursor goes back and all 14 take the server copy (TC-SYNC-NEW-20). **Rejected → fixed → resent:** protected the whole time; another unit's result does not rewind; the rewind goes to the earliest skipped page. **Several units:** one applied and one blocked → no rewind until both are sent (TC-SYNC-NEW-20, -21). **Server kept the other phone's copy:** the phone converges to it, unit level and live (`A=(QA r11 Daw Mya (B), …, 20000) server=(same)`). **Two pages:** one rewind, no duplicates. **Restart:** a file database closed and reopened between the skip and the send keeps the state. **First download:** skip, rewind to "0", one more download, opens once (TC-SYNC-NEW-22). **voidSale "skipped":** B's voidedAt, one return, stock 5 (TC-SYNC-NEW-23). **UI:** dashboard, sales history, sale detail and report correct while the void is unsent and after the send (TC-SYNC-NEW-24). **Live:** void during `voidedAt=… today=0 … repullKeys has sale=true`; A and B equal the server row for row (TC-SYNC-NEW-27) |
| 2. ae22869 BUG-33 | **verified**; gap → BUG-34 | Form prefilled; "96,000 Ks" next to the limit; a limit below the balance is saved; the sale-time warning uses the new limit and goes away when it is cleared; the seeded "09 7xx xxx 102" can be kept; the duplicate warning names the other customer; Myanmar digits → 0-9 and matched; no English (TC-DEBT-NEW-7). Live B → A (TC-SYNC-NEW-27). **Gap:** the same number with spaces or dashes is not warned about (BUG-34) |
| 3. 1420ee8 auto-close | **verified** (live) | Server: barcode changed → closed "fixed", Data kept, UpdatedAt = ResolvedAt; re-duplicate → a new open issue and the old one keeps its resolution; owner-first resolution kept; a stale phone's "resolve" gets the fixed row; another shop untouched; one unit fixing X while creating Y (TC-SYNC-NEW-25, 6 tests). App: latest 30 newest-first, deleted hidden, "ပြင်ပြီးသွားပါပြီ" / "စစ်ပြီးပြီ", old issue → the shorter sentence, a re-pull re-raises nothing, no English (TC-SYNC-NEW-26). Live, two phones: `A=[fixed] B=[fixed]` → `A=[fixed, open] B=[fixed, open]`. Note: closes only after a product change reaches the server (by code) |
| 4. 618cb6d "Batch · နံပါတ်" | **verified** | TC-UX-NEW-9 PASS with the edited label; `m/no_english_test.dart` PASS |
| 5. dbf2b5f bugs.md | **accurate** | The BUG-32, BUG-33 and Known-limitation lines match what the tests show. QA added round-11 verification lines and a round-11 check of the Known limitations (the round-10 additions 1 and 4 are out of date) |

**Developer edits to QA files.** QA accepts both.
- `qa_round10_sync_text_test.dart:221`: only `'Batch · Batch'` → `'Batch · နံပါတ်'` changed. The other 15 labels and every other line are
  unchanged (git diff c48af8f..dbf2b5f). The new label matches the owner's change.
- `qa_round10_customer_edit_test.dart`: the claim is **true**. QA ran it: `uri before=/customers/<id> after=/customers/<id>
  top=/customers/<id>/edit (ImperativeRouteMatch)`. The new check (the title "ဖောက်သည် ပြင်ဆင်ရန်" and a field with the customer's
  name) proves what the case asks for, which is that the edit form opened. QA's new test also asserts that the pushed route is on top.

## Bugs by severity (open)

Critical: none. High: none. Medium: none.

Low
- **BUG-34** (TC-DEBT-NEW-8, new): the duplicate-phone warning compares the exact text, so "09 790 011 002" or "09-790-011-002"
  against "09790011002" gives no warning. The field's own hint ("09 xxx xxx xxx") and the sample customers use spaces.
- **BUG-35** (TC-RPT-NEW-1, new; it was there before this round): with no sales in the last 7 days, the report's chart divides by 0.
  The result is 14 layout errors (`BoxConstraints has NaN values …`, `RenderFlex overflowed by 99868 pixels`). Debug builds show error
  boxes; release builds still need a look.

Verified this round: BUG-32, BUG-33. Accepted risk: BUG-11 (dev sa password in git history; loopback only).

Observations (no bug): (1) if two phones void the same sale and one is offline, that phone shows the stock returned twice until it
syncs (`7 (true: 5)`). This was so before this round and it corrects itself. (2) A history row keeps the present-tense text "…
ရောင်းတဲ့အခါ ဘယ်ပစ္စည်းလဲ ရွေးခိုင်းပါမယ်။" next to "ပြင်ပြီးသွားပါပြီ". (3) A rewind during the first download re-downloads the
shop once.

## Release recommendation (3–5 shop beta)

**Go.** The owner's exit rule ("no Critical, High or Medium open") is met. Every changed area works, live with two phones included, and
the per-shop verdicts from rounds 8–10 stand: grocery, hardware, pharmacy, fashion, service and phone shops are all Go.

Before or with the beta:
1. **BUG-35**: recommended one-line fix (skip the bar height when the week's highest day is 0). Otherwise every new shop opens Reports
   on day 1 with a broken chart.
2. **BUG-34**: optional; compare phone numbers digits-only. Otherwise tell shops to type phone numbers without spaces.
3. Tell shops: an older duplicate-barcode entry whose barcode was fixed before this server version closes the next time any product
   is edited, or by "စစ်ပြီး".

Conditions (unchanged): the owner runs the MANUAL list first; release builds use an https `API_BASE_URL`; rotate the dev sa password;
photos stay on the phone.

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01: delete the app, airplane mode ON, install + open → the Login/Register Myanmar text renders.
2. Upgrade check (part of TC-UX-NEW-6): on a phone with round-8 to round-10 data and an entry in "စစ်ရန်", install this build over it
   (do not delete the app) → it opens, the entry is Burmese, and nothing is lost.
3. **New, TC-RPT-NEW-1 (release build):** a new shop with no sales → Reports → look at the 7-day chart (BUG-35).
4. TC-UX-05: kill the app during checkout → after reopening, either the whole sale exists or nothing does.
5. TC-POS-NEW-9: camera scan at POS (steps in the row; the round-9 and round-10 additions still apply).
6. TC-POS-NEW-10: Bluetooth HID scanner (steps in the row).
7. TC-PROD-NEW-34: product photo on a real phone (including a broken / HEIC picture).
8. TC-PIN-05: low-end Android, PIN 3× → no stall.
9. TC-UX-03: small phone + largest system font → no overflow. Also check the customer edit form with "လက်ရှိ အကြွေး" next to the limit,
   the "ပြီးသွားတဲ့ ကိစ္စများ" list and the duplicate-phone dialog with a long name.
10. TC-POS-11: receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်".
11. TC-PROD-13: mark it from steps 5–7.
12. TC-UX-06: 1 hour of normal use.

Then the phone halves of the **Both** cases, newest first:
- **TC-SYNC-NEW-27 (new):** two phones. On A: airplane mode ON → void a sale → on B sell something and sync → A airplane mode OFF →
  the sale stays voided on A the whole time, and today's total never counts it. Then two products with one barcode (one per phone) →
  sync both → on B change that product's barcode → sync both → on both phones "စစ်ရန်" shows it under "ပြီးသွားတဲ့ ကိစ္စများ" as
  "ပြင်ပြီးသွားပါပြီ".
- **TC-DEBT-NEW-7 (new):** on B edit a customer (phone, address, lower the limit below what they owe) → sync both → A shows the new
  values; sell on credit on A → the warning names the new limit.
- TC-SYNC-NEW-19 / TC-SYNC-NEW-14: two phones; on A edit a product and clear Barcode and the wholesale price, set warranty to "မရှိ" and
  pick "သက်တမ်း မမှတ်ပါ" → sync both → on B the fields are empty, and scanning the old code finds nothing (or only the other product of a
  duplicate).
- TC-SYNC-NEW-15: two phones offline, sell the same IMEI on both and sell the last can of one product on both → online → "စစ်ရန်" on
  both shows Burmese with the IMEI, the product names and "-၁".
- TC-SYNC-NEW-13, then the round-7/8 list: TC-PROD-NEW-32, TC-PROD-NEW-27, -28, TC-SYNC-NEW-12, TC-SYNC-NEW-10, TC-PROD-NEW-25, -24,
  TC-SYNC-NEW-5, -6, TC-PROD-NEW-16, TC-PROD-NEW-6..9, TC-POS-NEW-5, TC-SYNC-NEW-3, TC-PROD-NEW-3, -4, TC-POS-NEW-3, -4,
  TC-DEBT-NEW-3, -4.

## New test files (round 11)

- `mobile/test/qa/qa_round11_pending_pull_test.dart`: TC-SYNC-NEW-20 (2 tests), -21 (3), -22 (2), -23, -24 (screens). All pass.
- `mobile/test/qa/qa_round11_customer_edit_test.dart`: TC-DEBT-NEW-6 review (go_router claim), TC-DEBT-NEW-7 (3 tests), TC-DEBT-NEW-8
  (fails → BUG-34).
- `mobile/test/qa/qa_round11_sync_history_test.dart`: TC-SYNC-NEW-26 (2 tests), TC-RPT-NEW-1 (fails → BUG-35).
- `mobile/test/qa/live_qa_round11_test.dart`: TC-SYNC-NEW-27 live (passes).
- `backend/tests/ZayPOS.QA.Tests/QaRound11Tests.cs`: TC-SYNC-NEW-25 (6 tests, pass).
