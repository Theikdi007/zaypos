# QA round 12 — summary (2026-11-15, branch `beta-polish` @ ee662f3, final round before the beta)

> ## Go for a 3–5 shop beta (no Critical, High or Medium open)
>
> **BUG-34** and **BUG-35** are verified, live included. The duplicate-phone warning, sign-in and PIN reset work with the number
> written in Myanmar digits, with dots, dashes or spaces, and as "+95 9 …". Phone A signs in again while it has an unsent unit
> (same shop, nothing replaced). The 7-day chart is correct for a new shop, for a week with only some days of sales, and for a week
> whose sales were all voided.
>
> Three new **Low** bugs, all in the new "Beta backlog" section of `docs/qa/bugs.md`. None blocks the beta:
> - **BUG-36**: customer search misses a partial number that starts with "959" (e.g. "959123" for "09 777 959 123"). This is a
>   small regression of 205c5d7.
> - **BUG-37**: the server accepts Shan, Arabic-Indic and full-width digits and stores a non-ASCII "+959…". Only a hand-made API call
>   can do this.
> - **BUG-38**: the chart's screen-reader label says "ယနေ့နေ့".
>
> The new Known-limitation bullet is right in substance but says "offline". The double stock count actually shows after the phone
> comes back **online**, for up to 10 minutes or until a manual sync. While it is offline the count is right.

Scope: re-test of d8cb91e (BUG-35), 205c5d7 (BUG-34) and ee662f3 (bugs.md, Known limitation), probes of edge cases, and a full
regression. No product code, no developer test and no earlier-round QA file was changed. Nothing was committed.

## Suite totals (recorded this round)

| Suite | Command | Passed | Failed | Skipped |
|---|---|---|---|---|
| Mobile analyze (start = end) | `cd mobile && flutter analyze` | No issues found | — | — |
| Mobile, all tests (start of round, before r12 files) | `cd mobile && flutter test` | 579 | 0 | 13 |
| Mobile, all tests (end of round, with r12 files) | `cd mobile && flutter test` | **583** | **2** | **14** |
| Backend Domain (start = end) | `cd backend && dotnet test` | 20 | 0 | 0 |
| Backend Api (start = end) | (same run) | 120 | 0 | 0 |
| Backend QA (start → end) | (same run) | 38 → **39** | 0 → **4** | 0 |
| Live (scratch DB `ZayPOS_QA_20261115_R12`, API 127.0.0.1:5077) | 14 files, one new phone each | **14** | **0** | 0 |

- The 2 mobile failures are both new bug tests: `qa_round12_phone_test.dart::TC-DEBT-NEW-9 …` (BUG-36) and
  `qa_round12_report_test.dart::TC-RPT-NEW-4 …` (BUG-38). The 4 backend QA failures are all `QaRound12Tests::TC_AUTH_NEW_2_…`
  (BUG-37, 3 theory cases + the API test). Skipped = the 14 live files without env vars. Both round-11 bug tests now pass
  (TC-DEBT-NEW-8, TC-RPT-NEW-1). The start counts include the developer's 9 new mobile tests (`m/phone_key_test.dart` 7,
  `m/report_empty_week_test.dart` 2) and the 4 new Api cases (AuthRulesTests).
- QA's own mistake, fixed: the first end-of-round `dotnet test` also failed Api `ArchitectureTests.Tenant_filter_is_bypassed_only_in_AuthRepository`.
  QA's new `QaRound12Tests.cs` used `IgnoreQueryFilters()`, and that rule allows it only in `AuthRepository`. QA rewrote its check to
  use the shop's own tenant-filtered view. The re-run gave Domain 20/0/0, Api 120/0/0, QA 39/4/0 (the 4 = BUG-37).
- Live files: `test/live_sync_test.dart`, `test/live_api_test.dart`, `test/live_clear_fields_test.dart`,
  `test/qa/live_qa_round2..6_test.dart`, `test/qa/live_qa_round8..11_test.dart` (phones +959790917021 … +959790917032, one per file),
  `test/live_step4_test.dart` (registers its own random phone) and `test/qa/live_qa_round12_test.dart` (new, +959790917041, asks for
  its own OTPs from the API log). Runner: `run_live_r12.sh` in the session scratchpad; it records flutter's exit code. The **first**
  run had 12 failures. The cause was QA's runner: its grep for the OTP found nothing, so every file started with an empty code. The
  runner was fixed and all 14 files were re-run with the same phones (the second OTP for each). All passed. An earlier trial of the
  new file used +959790917140, and its first full-run copy used +959790917040. Both passed.
- The round-11 live file still shows its round-11 results:
  `A=[fixed] B=[fixed]` → `A=[fixed, open] B=[fixed, open]`; `A=(QA r11 Daw Mya (B), 09790011102, null, 20000) server=(same)`;
  void during `today=0 … repullKeys has sale=true`. At the end, A and B equal the server row for row.
- The scratch DB was created with `dotnet ef database update` (all migrations, latest `20261114141058_SyncIssueData`). Afterwards it
  was dropped with `dotnet ef database drop --force`, pointed by connection string at `ZayPOS_QA_20261115_R12` only: the dry run said
  "would drop the database 'ZayPOS_QA_20261115_R12'", then `DROP DATABASE [ZayPOS_QA_20261115_R12]` ran. The API on 5077 was stopped
  (nothing listens on 5077). Docker `zaypos-sql` was not restarted or changed.
- **Not verified this round:** the dev DB check ("0 QA tenants in `ZayPOS`") and the list of remaining databases. The sqlcmd query
  needed the sa password from `appsettings.Development.json`, and the permission system refused it. QA never connected to `ZayPOS`.
  Every live run used the scratch connection string only. Also seen: `dotnet ef migrations list` against the default (dev) connection
  shows `20261114141058_SyncIssueData (Pending)`. The developer's dev DB is one migration behind, so an API started on it as-is would
  lack the SyncIssue Data column. QA did not change this.

## Case totals

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1 AUTH (+3 new) | 14 | 1 | 0 | 0 |
| 2 PIN | 4 | 0 | 0 | 1 |
| 3 FEAT | 5 | 0 | 0 | 0 |
| 4 PROD | 46 | 0 | 0 | 2 |
| 5 POS | 25 | 0 | 0 | 3 |
| 6 SALE | 4 | 0 | 0 | 0 |
| 7 DEBT (+1 fixed, +2 new) | 15 | 1 | 0 | 0 |
| 8 RPT (+1 fixed, +3 new) | 7 | 1 | 0 | 0 |
| 9 SYNC (+1 new) | 44 | 0 | 0 | 0 |
| 10 DEV | 4 | 0 | 0 | 0 |
| 11 SEC | 6 | 0 | 0 | 0 |
| 12 UX | 11 | 0 | 0 | 4 |
| **Total (198)** | **185** | **3** | **0** | **10** |

FAIL rows (all Low, beta backlog): TC-AUTH-NEW-2 (BUG-37), TC-DEBT-NEW-9 (BUG-36), TC-RPT-NEW-4 (BUG-38). Every other row was re-run
green in the suites above with its existing evidence.

## Verdicts on what changed

| Item | Verdict | Evidence (short) |
|---|---|---|
| 1. d8cb91e BUG-35 | **verified** | TC-RPT-NEW-1 PASS. **Some days with sales:** bars `[0,0,0,60,0,0,120]`, labels `[0,0,0,20,0,0,40]`, the voided day flat, 60,000 Ks / "2 ကြိမ်", no empty message (TC-RPT-NEW-2). **All voided, plus one sale 8 days ago:** "ရောင်းအား မရှိသေးပါ", 7 flat bars "0", semantics says so, on the today, month and week tabs; 0 Ks / "0 ကြိမ်"; the first new sale removes the message (TC-RPT-NEW-3). Developer `m/report_empty_week_test.dart` 2/2. Found next to it: BUG-38 (label "ယနေ့နေ့", already there before) |
| 2. 205c5d7 BUG-34, app | **verified**; one regression → BUG-36 | TC-DEBT-NEW-8 PASS. The warning names the other customer when that customer is stored as "+95 9 790 011 002" or "09 (790) 011-003" and the new number is typed in ASCII, Myanmar digits or "959.…". The own number re-typed as "+95 …" gives no warning (TC-DEBT-NEW-10). Search: 11 of 14 partial queries work ("0979001", "+95 9 790", "၀၉၇၉၀ ၀၁၁", "011002", "၄၅၆" …). The three that start with "959" miss (BUG-36); at 16aaa33 two of them worked (the same test run on an export of 16aaa33 in the scratchpad) |
| 3. 205c5d7 BUG-34, sign-in and server | **verified** (live); one gap → BUG-37 | Live TC-AUTH-NEW-3: an OTP asked in Myanmar digits, register "09.790.917.041", B signs in "+95 9 790 917 041", A signs in again in Myanmar digits with an unsent unit (same shop, `products={QA r12 soap, QA r12 unsent}`), PIN reset "959-…" → Myanmar digits, C signs in with the new PIN, the old PIN is refused, owner phone "+959790917041", raw register OTP in Myanmar digits `409 phone_registered`. API TC-AUTH-NEW-1: one account and one OTP limit across all forms, Users.Phone ASCII. Gap: other scripts' digits pass `\d` (BUG-37) |
| 4. ee662f3 Known limitation | **accurate in substance; wording imprecise** | TC-SYNC-NEW-28: `offline 5, back online 6 (today 0), +9 min 6, after the back-off 5 (returns: 1)`. The double count needs a pull, so it shows only after the phone is back online. It lasts until the push back-off ends (up to 10 min) or a manual sync. Suggested text in bugs.md ("QA round 12 check") |
| 5. ee662f3 BUG-34/35 statuses | **accurate** | The test names and counts in both "fixed" lines match what was run (`m/phone_key_test.dart` 7 tests, `m/report_empty_week_test.dart` 2, AuthRulesTests +4) |

## Bugs by severity (open)

Critical: none. High: none. Medium: none.

Low (all in "Beta backlog", none blocks the beta)
- **BUG-36** (TC-DEBT-NEW-9, new, a regression of 205c5d7): customer search for a partial number that starts with "959" (e.g.
  "959123") finds nothing, because the query's "959" is rewritten to "09". The query "959" alone lists everyone.
- **BUG-37** (TC-AUTH-NEW-2, new, already there before): `PhoneNumbers.Normalize` lets Shan, Arabic-Indic and full-width digits
  through and the API "sends" an OTP to a non-ASCII "+959…". The app cannot send these.
- **BUG-38** (TC-RPT-NEW-4, new, already there before): the chart's screen-reader label reads "အမြင့်ဆုံးက ယနေ့နေ့ 40K" and uses the
  short weekday names ("သောနေ့").

Verified this round: BUG-34, BUG-35. Accepted risk: BUG-11 (dev sa password in git history; loopback only).

## Release recommendation (3–5 shop beta)

**Go.** The owner's exit rule is met: no Critical, High or Medium bug is open. Every change of this round works, live included. The
three new bugs are Low and only affect search with a "959…" fragment, a hand-made API call, and the screen-reader text. The
per-shop verdicts from rounds 8–11 stand: grocery, hardware, pharmacy, fashion, service and phone shops are all Go.

Before or with the beta:
1. Correct the Known-limitation wording (two phones voiding one sale) as suggested in bugs.md. Tell shops that only one phone
   should void a sale, and that a manual sync ("ယခု sync လုပ်မယ်") corrects the stock at once.
2. Optional: BUG-36. Treat a search query as a partial number and do not rewrite its leading "959".
3. The dev DB `ZayPOS` is one migration behind (`SyncIssueData` pending). Run `dotnet ef database update` before the owner's phone
   tests on 5076.

Conditions (unchanged): the owner runs the MANUAL list first; release builds use an https `API_BASE_URL`; rotate the dev sa password;
photos stay on the phone.

## MANUAL cases for the owner (real phone, in this order)

1. TC-UX-01: delete the app, airplane mode ON, install + open → the Login/Register Myanmar text renders.
2. Upgrade check (part of TC-UX-NEW-6): on a phone with round-8 to round-11 data and an entry in "စစ်ရန်", install this build over it
   (do not delete the app) → it opens, the entry is Burmese, and nothing is lost.
3. **TC-RPT-NEW-1 (release build):** a new shop with no sales → Reports → the 7-day chart shows 7 flat bars, "0" above each, and
   "ရောင်းအား မရှိသေးပါ" in the middle. Nothing is cut off, even with the largest system font. Then sell once and check that today's
   bar appears.
4. **New, TC-AUTH-NEW-3:** on a second phone, sign in typing the number with spaces ("09 7xx xxx xxx"). Then use "PIN မေ့နေပါသလား?"
   typing it with the Myanmar keyboard → the same shop opens both times.
5. TC-UX-05: kill the app during checkout → after reopening, either the whole sale exists or nothing does.
6. TC-POS-NEW-9: camera scan at POS (steps in the row; the round-9 and round-10 additions still apply).
7. TC-POS-NEW-10: Bluetooth HID scanner (steps in the row).
8. TC-PROD-NEW-34: product photo on a real phone (including a broken / HEIC picture).
9. TC-PIN-05: low-end Android, PIN 3× → no stall.
10. TC-UX-03: small phone + largest system font → no overflow. Also check the customer edit form with "လက်ရှိ အကြွေး" next to the
    limit, the "ပြီးသွားတဲ့ ကိစ္စများ" list and the duplicate-phone dialog with a long name.
11. TC-POS-11: receipt "Viber ပို့မယ်" / "ပုံ သိမ်းမယ်".
12. TC-PROD-13: mark it from steps 6–8.
13. TC-UX-06: 1 hour of normal use.

Then the phone halves of the **Both** cases, newest first:
- **TC-SYNC-NEW-28 (new):** two phones. Sell 1 on A and sync both. A airplane mode ON → void the sale → wait 2–3 minutes. On B void the
  same sale. A airplane mode OFF → A's stock shows 1 too many for a few minutes (accepted). Tap "ယခု sync လုပ်မယ်" → the stock is
  right, and the sale is voided on both phones.
- **TC-DEBT-NEW-10 / TC-DEBT-NEW-8:** add a customer "09 790 011 002"; add another typing "09790011002" → the "ဒီ ဖုန်းနံပါတ်
  ရှိပြီးသားပါ" dialog names the first one. Search "790 011" → found.
- TC-SYNC-NEW-27, TC-DEBT-NEW-7, TC-SYNC-NEW-19 / -14, TC-SYNC-NEW-15, TC-SYNC-NEW-13, then the round-7/8 list: TC-PROD-NEW-32,
  TC-PROD-NEW-27, -28, TC-SYNC-NEW-12, TC-SYNC-NEW-10, TC-PROD-NEW-25, -24, TC-SYNC-NEW-5, -6, TC-PROD-NEW-16, TC-PROD-NEW-6..9,
  TC-POS-NEW-5, TC-SYNC-NEW-3, TC-PROD-NEW-3, -4, TC-POS-NEW-3, -4, TC-DEBT-NEW-3, -4 (steps as in the round-11 summary).

## New test files (round 12)

- `mobile/test/qa/qa_round12_phone_test.dart`: TC-DEBT-NEW-9 (fails → BUG-36), TC-DEBT-NEW-10 (passes).
- `mobile/test/qa/qa_round12_report_test.dart`: TC-RPT-NEW-2, TC-RPT-NEW-3 (pass), TC-RPT-NEW-4 (fails → BUG-38).
- `mobile/test/qa/qa_round12_void_twice_test.dart`: TC-SYNC-NEW-28 (passes; documents the Known limitation).
- `mobile/test/qa/live_qa_round12_test.dart`: TC-AUTH-NEW-3 live (passes).
- `backend/tests/ZayPOS.QA.Tests/QaRound12Tests.cs`: TC_AUTH_NEW_1 (passes), TC_AUTH_NEW_2 ×4 (fail → BUG-37).
