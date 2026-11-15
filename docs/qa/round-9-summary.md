# QA round 9 — summary (2026-11-14, branch `beta-polish` @ 33eaba6)

> ## No-go for beta until BUG-31 is fixed (or the owner accepts it)
>
> The three changes do what the owner asked: "Batch" is back with nothing else reverted, BUG-27 is fixed for scans and the
> "sold IMEI" message works (whole trade-in chains, on Drift and fake repos), and BUG-26 is verified **live**. All 8 issue kinds come
> from the real server with structured data and show in Burmese with the right names and numbers on both phones. Old rows and a
> schema v1 → v2 upgrade work too.
>
> Running the live test turned up an older sync bug, **BUG-31 (Medium)**: a field cleared on one phone (barcode, wholesale price,
> expiry days, credit limit…) is never cleared on the shop's other phones, because pulled NULLs are ignored. The owner's exit rule
> ("no Critical, High or Medium open") is therefore not met. There are also three new Low bugs (BUG-28..30). Shops that use only
> **one** phone are not affected by BUG-31.

Scope: re-test of 7eb11f9 (Batch), 0b3e2d4 (BUG-27 + sold-IMEI message), 7df5f1f (BUG-26), fe1acaa ("Known limitations"), review of
the developer's edits to QA files, 8 new cases, full regression. No product code was changed. No command was blocked by permissions.

## Suite totals (recorded this round)

| Suite | Command | Passed | Failed | Skipped |
|---|---|---|---|---|
| Mobile analyze | `cd mobile && flutter analyze` | No issues found | — | — |
| Mobile, all tests (start of round, before r9 files) | `cd mobile && flutter test` | 513 | 0 | 9 |
| Mobile, all tests (end of round, with r9 files) | `cd mobile && flutter test` | **518** | **5** | **10** |
| Backend Domain | `cd backend && dotnet test` | 20 | 0 | 0 |
| Backend Api | (same run) | 113 | 0 | 0 |
| Backend QA | (same run) | 32 | 0 | 0 |
| Live (scratch DB `ZayPOS_QA_20261114_R9`, API 127.0.0.1:5077) | 10 files, one new phone + OTP each | **9** | **1** | 0 |

- The 5 mobile failures are exactly the new bug tests: `qa_round9_scan_test.dart::TC-POS-NEW-16 …` (BUG-28),
  `qa_round9_sync_text_test.dart::TC-UX-NEW-5 …` and `::TC-UX-NEW-6 …` (BUG-29; every message check in them passes),
  `::TC-UX-NEW-7 …` (BUG-30), `qa_round9_pull_null_test.dart::TC-SYNC-NEW-14 …` (BUG-31). Skipped = the 10 live files without env vars.
- Live files: `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_step4_test.dart`, `test/qa/live_qa_round2..6_test.dart`,
  `test/qa/live_qa_round8_test.dart`, `test/qa/live_qa_round9_test.dart` (new). Phones +959790915001 … +959790915010, one per file
  (fixed list, no `$RANDOM`). The 1 failure is `live_qa_round9_test.dart`. All of its BUG-26 assertions pass; its last assertion
  (TC-SYNC-NEW-14) fails.
- Scratch DB created with `dotnet ef database update` (latest migration `20261114141058_SyncIssueData`, `SyncIssues.Data nvarchar(2000)`
  checked). Dropped by name afterwards (`DROP DATABASE [ZayPOS_QA_20261114_R9]`, it held 14 tenants). Remaining databases: `ZayPOS`,
  `ZayPOS_SchemaRef`. Dev DB `ZayPOS`: `SELECT COUNT(*) FROM Tenants WHERE Name LIKE 'QA%'` → 0. The API on 5077 was stopped;
  Docker `zaypos-sql` was not touched.
- Backend: no QA backend test was added (the server side of BUG-26 is proven live). Backend code did not change after the one
  `dotnet test` run.

## Case totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH | 12 | 0 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 5 | 0 | 0 | 0 |
| 4 PROD | 46 | 0 | 0 | 2 |
| 5 POS (+1 fixed, +3 new) | 23 | 1 | 0 | 3 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT | 11 | 0 | 0 | 0 |
| 8 RPT | 4 | 0 | 0 | 0 |
| 9 SYNC (+2 new) | 30 | 1 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX (+1 fixed, +3 new) | 6 | 3 | 0 | 4 |
| **Total (170)** | **155** | **5** | **0** | **10** |

FAIL rows: TC-POS-NEW-16 (BUG-28), TC-SYNC-NEW-14 (BUG-31, Medium), TC-UX-NEW-5 and TC-UX-NEW-6 (BUG-29), TC-UX-NEW-7 (BUG-30).

## Verdicts on what changed

| Item | Verdict | Evidence (short) |
|---|---|---|
| 1. 7eb11f9 "Batch" | **verified** | `grep -rn အသုတ် mobile/lib backend/src mobile/assets` → nothing (it is left only in the QA history docs). Every line 7eb11f9 removed contains "အသုတ်" and maps 1:1 to an added "Batch" line. `git diff fb520d9^ 33eaba6 -- mobile/lib` shows no Batch line changed except the FEFO removal (kept) and the new `featureLabel`. The other fb520d9 translations were not reverted. TC-UX-02, TC-UX-NEW-1 and TC-UX-NEW-4 pass with 'batch' allowed |
| 2a. BUG-27 cart check by IMEI number | **verified for scans**, gap on tap → BUG-28 | TC-POS-NEW-14 covers twin rows picked by tap and then scanned, Myanmar digits, and a received-again IMEI on Drift. TC-POS-NEW-13 passes 3/3. A scan followed by a tap on the twin product still adds a 2nd phone (TC-POS-NEW-16) |
| 2b. Sold IMEI message | **as decided** | TC-POS-NEW-15, fake and Drift (through checkout + receive): sold → received → sold again → message; received → new row; Myanmar digits; latest = max createdAt, not list order; a product barcode wins; tracking off → "ပစ္စည်းအသစ်". The message text is exactly the owner's |
| 2c. Developer choices | **accepted** | "last status" = latest createdAt is consistent with the trade-in rule. A product barcode winning is reasonable. A deleted product's in-stock IMEI → "ပစ္စည်းအသစ်" behaves as stated, and a deleted product's SOLD IMEI → the sold message (see the limitations correction). Risk noted: createdAt comes from the phone clock, so a phone whose clock is behind could order rows wrongly. That only matters if the latest row is in stock on a deleted product |
| 3. BUG-26 | **verified** (live, both phones). Two remaining texts → BUG-29, BUG-30 | Live TC-SYNC-NEW-15: 8/8 kinds with data, Burmese messages (excerpt below). Rejected units have code + data → Burmese. Data NULL → shorter sentence on phone C. App TC-UX-NEW-5/6: pull path, English user data, 6 "others", unknown kind, v1 → v2 upgrade, then a re-pull with data. The sync chip ("Sync ပြဿနာ (n)") and snackbars are clean |
| 4. fe1acaa "Known limitations" | **accurate, one correction** | "IMEIs of deleted products → ပစ္စည်းအသစ်" holds only for in-stock ones. Additions written in bugs.md: BUG-28, BUG-29/30, BUG-31 |

Real messages from the live server (phone B; phone A is identical):

- duplicateBarcode — "Barcode 8850000099101 ကို “QA r9 Pepsi can” နဲ့ “QA r9 Coke can” ပစ္စည်းတွေမှာ သုံးထားပါတယ်။ ရောင်းတဲ့အခါ ဘယ်ပစ္စည်းလဲ ရွေးခိုင်းပါမယ်။"
- duplicateSerial — "IMEI 359930000000001 (“QA r9 iPhone 13 Pro”) က “QA r9 iPhone 13” မှာလည်း stock ထဲ ရှိနေပါတယ်။ နှစ်ခုလုံး သိမ်းထားပါတယ် — တစ်ခုကို စစ်ပြီး ပြင်ပါ။"
- serialDoubleSold — "IMEI 359930000000002 (“QA r9 Galaxy A15”) ကို ဖုန်းနှစ်လုံးက ရောင်းလိုက်ပါတယ်။ …"; negativeStock — "“QA r9 Tiger beer” ရဲ့ Stock က -၁ ဖြစ်နေပါတယ်။ …"
- creditLimitExceeded — "“QA r9 Ma Ma” ရဲ့ အကြွေး 75,500 Ks ဖြစ်နေပြီး ကန့်သတ်ချက် 50,000 Ks ကို ကျော်နေပါတယ်။"; totalMismatch — "ပြေစာ A-0004 ရဲ့ စုစုပေါင်း မကိုက်ပါ။ ဆာဗာက 1,500 Ks လို့ တွက်ထားပါတယ်။"
- duplicateReceiptNo — "ပြေစာနံပါတ် A-0001 ရှိပြီးသားမို့ A-0001*2 အဖြစ် သိမ်းထားပါတယ်။"; clockSkew — "ဒီဖုန်းရဲ့ နာရီက ၃၁ မိနစ် စောနေပါတယ်။ …"
- rejected — "“အမည်” က စာလုံး ၁၅၀ လုံးထက် ရှည်နေပါတယ်။", "“Barcode” မှာ ဂဏန်းနဲ့ အင်္ဂလိပ်စာလုံးပဲ ထည့်လို့ရပါတယ်။"

Cosmetic, no bug: an unlabelled numeric field is called "စာသားတစ်ခု" ("a text"), e.g. "စာသားတစ်ခု က ၁ ထက် ငယ်နေပါတယ်။" for a debt
amount. Only app bugs reach it.

## Developer edits to QA files — reviewed

- `qa_form_helpers`, `qa_app_flows`, `qa_round2..6_ui`, `qa_round7_scan` (Batch finders restored): **accepted.**
  `git diff 07a08a2 33eaba6` on these files shows no Batch line changed, which confirms the developer's claim.
- `qa_ux_test`, `qa_round7_ux_test`, `qa_round8_ux_test` (+'batch' in the allow-lists): **accepted.** Only that one word was added, and
  it is exactly the owner's decision.
- `qa_round8_scan_test.dart:277, :310` and `qa_round8_scan_drift_test.dart:155` (cart message text): **accepted.** These are the owner's
  exact words; the assertions are unchanged.
- `qa_round8_scan_drift_test.dart` TC-POS-NEW-13 last step (sold IMEI → sold message): **accepted.** It follows owner item 4 and is
  stronger than before (it also asserts that no sheet opens and the cart stays empty). QA fixed a stale title fragment ("sold IMEI,
  deleted product's IMEI → sheet" → "deleted product's IMEI → sheet"); no assertion was changed.
- `test/fake_sync_api.dart` `rejectCode` / `rejectData`: **accepted.** Note: `rejectData` defaults to `const {}`, not null. That is
  equivalent, because `UnitResult.data` is non-nullable and empty means an old server. Existing tests behave as before.
- Normalized diff of all 13 QA files (e7cd138 → 33eaba6): every removed line is a word swap or one of the edits above. No assertion was
  removed.
- Not a QA file, observation only: the developer's `m/no_english_test.dart` sample rejected units have rows without ids, so the
  "ပြင်ရန်" fields are never rendered. That is why BUG-29 got through.

## Bugs by severity (open)

Critical — none. High — none.

Medium
- **BUG-31** (TC-SYNC-NEW-14, new) — pulled NULLs are ignored (`sync_store.dart` `_merge`, `insertOnConflictUpdate` with a data class).
  A barcode / wholesale price / expiry days / credit limit cleared on one phone stays on the shop's other phones for good. Proven live:
  `server: <NULL> · B: null · A: 8850000099101`.

Low
- **BUG-28** (TC-POS-NEW-16, new) — duplicateSerial: scan IMEI X, then tap the twin product → X is offered and added again (two phones
  for one box).
- **BUG-29** (TC-UX-NEW-5/6, new) — the rejected-unit screen's field labels show the table name ("အမည် · customers").
- **BUG-30** (TC-UX-NEW-7, new) — an unreadable pulled row shows "(FormatException: syncIssues.kind: …)" on the Settings sync card /
  first-sync screen.

Verified this round: BUG-26, BUG-27. Accepted risk: BUG-11 (dev sa password in git history; loopback only).

## Release recommendation (3–5 shop beta)

**No-go as it stands, by the owner's exit rule (BUG-31 is Medium).** Everything that changed in this round works. BUG-31 is older than
this round, but it silently makes phones of one shop disagree. It also undoes the advice shops will be given for duplicate barcodes:
"remove the barcode from one product" fixes only the phone where it was done. Options:
1. Fix BUG-31: the pull merge must write NULL columns, e.g. write the companion with nulls kept, or `replace` after the updatedAt
   check. QA re-runs TC-SYNC-NEW-14 and the live file. This is the preferred option.
2. Or the owner accepts BUG-31 as a known risk. Then: single-phone shops are Go. Multi-phone shops are Go only if they are told that
   clearing a field must be done on every phone, or that a phone must sign out and in again to pick it up.

If BUG-31 is fixed or accepted, the per-shop-type verdicts are as in round 8: grocery, hardware, pharmacy (Batch wording restored),
fashion and service are Go. Phone shops are Go; tell them a scanned sold IMEI says to take it back with "Stock ဖြည့်မယ်", and to clear
"IMEI / စီးရီးနံပါတ် တူ …" entries promptly (BUG-28). Conditions (unchanged): the owner runs the MANUAL list first; release builds use
an https `API_BASE_URL`; rotate the dev sa password; photos stay on the phone.

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01 — delete the app, airplane mode ON, install + open: the Login/Register Myanmar text renders.
2. **Upgrade check (new r9, part of TC-UX-NEW-6):** on a phone that has round-8 data with an entry in "စစ်ရန်", install this build
   over it (do not delete the app) → the app opens, the old entry shows "ဒီ Barcode ကို ပစ္စည်းတွေမှာ…" in Burmese, and nothing is lost.
3. TC-UX-05 — kill the app during checkout: after reopening, the whole sale exists or nothing.
4. TC-POS-NEW-9 — camera scan at POS (steps in the row). Add for round 9, in a phone shop: sell a phone, then scan its IMEI box at POS
   → "ဒီ IMEI က ရောင်းပြီးသားပါ — ပြန်ဝယ်ရင် 'Stock ဖြည့်မယ်' ကနေ လက်ခံပါ" and nothing is added. Receive it with "Stock ဖြည့်မယ်"
   → scan → it is in the cart. Scan again → "ဒီ IMEI ခြင်းထဲမှာ ရှိပြီးသားပါ".
5. TC-POS-NEW-10 — Bluetooth HID scanner (steps in the row; round-8 additions still apply).
6. TC-PROD-NEW-34 — product photo on a real phone (including a broken / HEIC picture).
7. TC-PIN-05 — low-end Android, PIN 3×: no stall.
8. TC-UX-03 — small phone + largest system font: no overflow. Also check "စစ်ရန်" with a long duplicateSerial message and the sold
   IMEI snackbar.
9. TC-POS-11 — receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်".
10. TC-PROD-13 — mark it from steps 4–6.
11. TC-UX-06 — 1 hour of normal use.

Then the phone halves of the **Both** cases, newest first:
- TC-SYNC-NEW-15: two phones offline, sell the same IMEI on both and sell the last can of one product on both → online →
  "စစ်ရန်" on both shows Burmese with the IMEI, the product names and "-၁".
- TC-SYNC-NEW-14 (after the BUG-31 fix): clear a product's barcode on A → sync both → scanning that code on B must no longer find the
  product.
- TC-SYNC-NEW-13, then the round-7/8 list: TC-PROD-NEW-32, TC-PROD-NEW-27, -28, TC-SYNC-NEW-12, TC-SYNC-NEW-10, TC-PROD-NEW-25, -24,
  TC-SYNC-NEW-5, -6, TC-PROD-NEW-16, TC-PROD-NEW-6..9, TC-POS-NEW-5, TC-SYNC-NEW-3, TC-PROD-NEW-3, -4, TC-POS-NEW-3, -4,
  TC-DEBT-NEW-3, -4.

## New test files (round 9)

- `mobile/test/qa/qa_round9_scan_test.dart`: TC-POS-NEW-14 (1 test), TC-POS-NEW-15 (3 tests), TC-POS-NEW-16 (1 test, fails → BUG-28).
- `mobile/test/qa/qa_round9_scan_drift_test.dart`: TC-POS-NEW-15 Drift (trade-in chain through checkout + receive; also covers
  TC-POS-NEW-14 on Drift).
- `mobile/test/qa/qa_round9_sync_text_test.dart`: TC-UX-NEW-5, TC-UX-NEW-6 (fail only on BUG-29), TC-UX-NEW-7 (fails → BUG-30).
- `mobile/test/qa/qa_round9_pull_null_test.dart`: TC-SYNC-NEW-14 (fails → BUG-31).
- `mobile/test/qa/live_qa_round9_test.dart`: TC-SYNC-NEW-15 live (passes) + TC-SYNC-NEW-14 live (last assertion, fails → BUG-31).
  The optional env `ZAYPOS_LIVE_SQL_DB` (scratch DB name) lets it blank one issue's Data with sqlcmd in `zaypos-sql`.
- Changed: `mobile/test/qa/qa_round8_scan_drift_test.dart` — TC-POS-NEW-13 title fragment only.
