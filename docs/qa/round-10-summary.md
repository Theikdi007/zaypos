# QA round 10 — summary (2026-11-14, branch `beta-polish` @ af191a5)

> ## Go for a 3–5 shop beta (no Critical, High or Medium open)
>
> All four fixes do what the owner asked. **BUG-31** is verified on every synced table, through the real edit form and **live** with two
> phones: the real server stores NULL, its pull JSON carries explicit nulls, and phone A shows the cleared fields empty. **BUG-28**, **BUG-29**
> and **BUG-30** are verified too, with wider checks than the developer's tests.
>
> Two new Low bugs: **BUG-32** is a small regression of the BUG-31 fix. A pull can un-void a sale whose void is still waiting to be sent.
> This needs a flaky network and fixes itself at the next good sync. **BUG-33**: the customer screen's edit button does nothing, so a
> customer can never be corrected. There are also two owner decisions (below).

Scope: re-test of 8b513b5 (BUG-31), fb3fd12 (BUG-28), ab92a09 (BUG-29), b04dc07 (BUG-30) and af191a5 (bugs.md statuses), plus 8 new
cases and a full regression. No product code was changed and the developer edited no QA file. No command was blocked by permissions.

## Suite totals (recorded this round)

| Suite | Command | Passed | Failed | Skipped |
|---|---|---|---|---|
| Mobile analyze | `cd mobile && flutter analyze` | No issues found | — | — |
| Mobile, all tests (start of round, before r10 files) | `cd mobile && flutter test` | 531 | 0 | 11 |
| Mobile, all tests (end of round, with r10 files) | `cd mobile && flutter test` | **543** | **3** | **12** |
| Backend Domain | `cd backend && dotnet test` | 20 | 0 | 0 |
| Backend Api | (same run) | 114 | 0 | 0 |
| Backend QA | (same run) | 32 | 0 | 0 |
| Live (scratch DB `ZayPOS_QA_20261114_R10`, API 127.0.0.1:5077) | 12 files, one new phone + OTP each | **12** | **0** | 0 |

- The 3 mobile failures are exactly the new bug tests: `qa_round10_pull_null_test.dart::TC-SYNC-NEW-17 …` ×2 (BUG-32) and
  `qa_round10_customer_edit_test.dart::TC-DEBT-NEW-6 …` (BUG-33). Skipped = the 12 live files without env vars. Every round-9 bug test
  (TC-POS-NEW-16, TC-SYNC-NEW-14, TC-UX-NEW-5/6/7) passes unchanged.
- Live files: `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_step4_test.dart` (it registers its own phone),
  `test/live_clear_fields_test.dart` (developer, new), `test/qa/live_qa_round2..6_test.dart`, `test/qa/live_qa_round8_test.dart`,
  `test/qa/live_qa_round9_test.dart`, `test/qa/live_qa_round10_test.dart` (new). Phones +959790916001 … +959790916012, one per file, from a
  fixed list. QA used its own runner (`run_live_r10.sh` in the session scratchpad). It records flutter's exit code; the developer's
  `run_live_dev.sh` prints the exit code of `grep` instead.
- Scratch DB created with `dotnet ef database update` (latest migration `20261114141058_SyncIssueData`). It was dropped by name afterwards
  (`DROP DATABASE [ZayPOS_QA_20261114_R10]`; it held 12 tenants). Remaining databases: `ZayPOS`, `ZayPOS_SchemaRef`. Dev DB `ZayPOS`:
  `SELECT COUNT(*) FROM Tenants WHERE Name LIKE 'QA%'` → 0. Its 6 developer tenants from 2026-11-12 were left alone. The API on 5077 was
  stopped; Docker `zaypos-sql` was not touched.
- Extra evidence: the new BUG-31 tests were run on a scratch git worktree at e140618 (before the fix). TC-SYNC-NEW-16 fails there 3 of 5
  (the "older row" and "unpushed" tests pass, as they should) and TC-SYNC-NEW-18 fails, so the tests tell the two builds apart.
  TC-SYNC-NEW-17 PASSES there, which is what makes BUG-32 a regression. The worktree is removed.

## Case totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 5 | 0 | 0 | 0 |
| 4 PROD | 46 | 0 | 0 | 2 |
| 5 POS (+1 fixed, +1 new) | 25 | 0 | 0 | 3 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT (+1 new) | 11 | 1 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC (+1 fixed, +4 new) | 34 | 1 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX (+3 fixed, +2 new) | 11 | 0 | 0 | 4 |
| **Total (178)** | **166** | **2** | **0** | **10** |

FAIL rows: TC-SYNC-NEW-17 (BUG-32), TC-DEBT-NEW-6 (BUG-33).

## Verdicts on what changed

| Item | Verdict | Evidence (short) |
|---|---|---|
| 1. 8b513b5 BUG-31 | **verified**; regression → BUG-32 | **Pull:** every nullable column of every synced table is cleared by a newer pull. That covers products (incl. warrantyMonths), customers, batches.expiryDate, serials.saleLineId, sales.customerId/voidedAt, devices.name, tenants.township/plan, issues data/resolvedAt and the ledgers; deletedAt NULL makes a row live again. **LWW:** an equal updatedAt takes the pulled row (spec ">="), an older row clears nothing, a pending customer is untouched, and the own device's lastSeq stays at the max (TC-SYNC-NEW-16). **Real UI:** the edit form clears Barcode and wholesale price, sets warranty to "မရှိ" and picks "သက်တမ်း မမှတ်ပါ" → 4 explicit nulls → empty on A (TC-SYNC-NEW-18). **Server:** live raw pull JSON `products.barcode: (true, null) … customers.creditLimit: (true, null)`, SQL `<NULL>` (TC-SYNC-NEW-19). **Gap:** ledger rows skip the pending-outbox check → BUG-32 |
| 1a. Credit limit only at unit level | **gap → BUG-33** | There is no customer edit screen, and the pencil button "ပြင်ဆင်ရန်" on the customer screen does nothing. The sync part works (unit level + live), but no shop can change or remove a credit limit, phone number or address |
| 1b. "Resolves it on all phones" | **data yes, issue no** — owner decision | Live: after B cleared the duplicate Barcode, both phones find one product for the code. The `duplicateBarcode` entry stays **open** on both phones (`A open=(true), B open=(true)`) until the owner taps "စစ်ပြီး"; that resolution then reaches A (live PASS). Recommendation: acceptable for the beta if shops are told; nicer later is for the server to close a duplicateBarcode issue once no live product shares the code |
| 2. fb3fd12 BUG-28 | **verified** | TC-POS-NEW-16 unchanged PASS. TC-POS-NEW-17 covers tap → tap, scan → tap, tap → scan and trade-in rows, and checks that the sold row is never listed, that "ရောင်းစရာ IMEI မကျန်တော့ပါ" shows and that an emptied cart offers the IMEI again. Run on fake repos and on Drift (checkout + receive) |
| 3. ab92a09 BUG-29 | **verified** | TC-UX-NEW-5/6 unchanged PASS. TC-UX-NEW-9: the exact 16 Burmese labels for every `editableColumns` table; an unknown table shows no field and no data; the validation errors are Burmese. Cosmetic: "Batch · Batch" |
| 4. b04dc07 BUG-30 | **verified** | TC-UX-NEW-7 unchanged PASS. TC-UX-NEW-8 covers FormatException, TypeError, a storage error, a push network error, a push 500 and an unknown English code. The card and the first-download screen show only the Burmese message, and a good cycle clears it. The sync chip has fixed labels. A wrong-type row says "try later" instead of "update the app"; it is still Burmese, so this is acceptable |
| 5. af191a5 bugs.md statuses | **accurate**, one omission | The BUG-28/29/30 lines are accurate. The BUG-31 line ("under the same LWW / pending-outbox rules") is true for the LWW tables, but ledgers (sales.voidedAt) have no pending check → BUG-32. QA did not re-check the claim that the live file "fails without the fix". The "Known limitations" round-9 additions are out of date; QA added a round-10 check |

## Bugs by severity (open)

Critical: none. High: none. Medium: none.

Low
- **BUG-32** (TC-SYNC-NEW-17, new, regression of 8b513b5): a pull can un-void a sale whose void is not pushed yet. This needs a flaky
  network; the sale shows as not voided (and counts in the day's totals) until the next good sync. `sync_store.dart` `_merge` sales case,
  no `unpushed` check.
- **BUG-33** (TC-DEBT-NEW-6, new): the customer screen's "ပြင်ဆင်ရန်" button does nothing (`onPressed: () {}` since Phase 1). No customer
  can be edited, so a credit limit can never be changed or removed.

Verified this round: BUG-28, BUG-29, BUG-30, BUG-31. Accepted risk: BUG-11 (dev sa password in git history; loopback only).

## Release recommendation (3–5 shop beta)

**Go.** The owner's exit rule ("no Critical, High or Medium open") is met. Every changed area works, live included, and the per-shop
verdicts from rounds 8–9 stand: grocery, hardware, pharmacy, fashion, service and phone shops are all Go. Multi-phone shops are now safe
for cleared fields.

Before or with the beta, the owner decides:
1. **BUG-33**: add a small customer edit form (name, phone, address, credit limit, note), or hide the pencil button. Otherwise tell shops
   that a mistyped customer has to be added again.
2. **duplicateBarcode entries**: keep them open until "စစ်ပြီး" (tell shops: fix the barcode, then mark the entry), or have the server
   close them when the duplicate is gone.
3. **BUG-32**: recommended small fix (apply the pending-outbox check to pulled sales rows). It is not blocking.

Conditions (unchanged): the owner runs the MANUAL list first; release builds use an https `API_BASE_URL`; rotate the dev sa password;
photos stay on the phone.

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01 — delete the app, airplane mode ON, install + open: the Login/Register Myanmar text renders.
2. Upgrade check (part of TC-UX-NEW-6): on a phone with round-8/9 data and an entry in "စစ်ရန်", install this build over it (do not
   delete the app) → it opens, the entry is Burmese, and nothing is lost.
3. TC-UX-05 — kill the app during checkout: after reopening, either the whole sale exists or nothing does.
4. TC-POS-NEW-9 — camera scan at POS (steps in the row; round-9 sold-IMEI additions still apply). Add for round 10, in a phone shop with
   one IMEI in stock on two products: scan it → tap the other product → the IMEI is not in the list.
5. TC-POS-NEW-10 — Bluetooth HID scanner (steps in the row).
6. TC-PROD-NEW-34 — product photo on a real phone (including a broken / HEIC picture).
7. TC-PIN-05 — low-end Android, PIN 3×: no stall.
8. TC-UX-03 — small phone + largest system font: no overflow. Also check "စစ်ရန်" with a long duplicateSerial message, the sold-IMEI
   snackbar and the Settings sync card with "Sync လုပ်လို့ မရသေးပါ…".
9. TC-POS-11 — receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်".
10. TC-PROD-13 — mark it from steps 4–6.
11. TC-UX-06 — 1 hour of normal use.

Then the phone halves of the **Both** cases, newest first:
- TC-SYNC-NEW-19 / TC-SYNC-NEW-14: two phones; on A edit a product and clear Barcode and the wholesale price, set warranty to "မရှိ" and
  pick "သက်တမ်း မမှတ်ပါ" → sync both → on B the fields are empty, and scanning the old code finds nothing (or only the other product of a
  duplicate) → on B "စစ်ရန်" still lists the duplicateBarcode entry until "စစ်ပြီး" is tapped, and then it disappears on A as well.
- TC-SYNC-NEW-15: two phones offline, sell the same IMEI on both and sell the last can of one product on both → online → "စစ်ရန်" on
  both shows Burmese with the IMEI, the product names and "-၁".
- TC-SYNC-NEW-13, then the round-7/8 list: TC-PROD-NEW-32, TC-PROD-NEW-27, -28, TC-SYNC-NEW-12, TC-SYNC-NEW-10, TC-PROD-NEW-25, -24,
  TC-SYNC-NEW-5, -6, TC-PROD-NEW-16, TC-PROD-NEW-6..9, TC-POS-NEW-5, TC-SYNC-NEW-3, TC-PROD-NEW-3, -4, TC-POS-NEW-3, -4,
  TC-DEBT-NEW-3, -4.

## New test files (round 10)

- `mobile/test/qa/qa_round10_imei_cart_test.dart`: TC-POS-NEW-17 (2 fake-repo tests + 1 Drift test).
- `mobile/test/qa/qa_round10_pull_null_test.dart`: TC-SYNC-NEW-16 (5 tests), TC-SYNC-NEW-17 (2 tests, fail → BUG-32), TC-SYNC-NEW-18
  (edit form, Drift).
- `mobile/test/qa/qa_round10_sync_text_test.dart`: TC-UX-NEW-8 (2 tests), TC-UX-NEW-9. It reuses `badStrings` from the round-9 file.
- `mobile/test/qa/qa_round10_customer_edit_test.dart`: TC-DEBT-NEW-6 (fails → BUG-33).
- `mobile/test/qa/live_qa_round10_test.dart`: TC-SYNC-NEW-19 live (passes).
