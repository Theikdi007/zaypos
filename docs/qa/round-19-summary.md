# QA round 19: summary (2026-11-20, branch `feat/google-signin` @ 3a0db0e + uncommitted working tree, PR #15)

Scope: the round-18 iOS cases left BLOCKED/FAIL, the four changes since round 18 (BUG-67 bundle name, BUG-69 reachability probe,
wrong-PIN text with `attemptsLeft`, `/auth/login` removed), and a short Android regression. Local API http://127.0.0.1:5076
(built from the working tree, started 10:25), iPhone 18 Pro simulator (debug build, fresh install), Android emulator-5554
(profile build, arm64 split APK: the full 118 MB APK did not fit on the emulator's /data). No credentials were typed into Google:
the iPhone simulator now shows an **account chooser with an existing session**, so the account was tapped and Google's
"Continue" accepted.

## Totals (cases run this round)

| Section | PASS | FAIL | BLOCKED | MANUAL |
|---|---|---|---|---|
| 1. Auth (TC-AUTH-07, -09) | 2 | 0 | 0 | 0 |
| 1b. Google Sign-In (TC-GAUTH-01, -02, -04, -05, -06, -07, -09, -14, -NEW-1, -NEW-3) | 10 | 0 | 0 | 0 (NEW-3 live iOS check → owner) |
| 2. Unlock & PIN (TC-PIN-02, -03) | 2 | 0 | 0 | 0 |
| Android regression (one quick sale synced: B-0001, 200 Ks, on the server 3 s later) | 1 | 0 | 0 | 0 |

The exact wrong-PIN text seen live: **"PIN မှားနေပါတယ်။ နောက်ထပ် ၄ ကြိမ် ကြိုးစားလို့ရပါတယ်။"** then **"…နောက်ထပ် ၃ ကြိမ်…"** (Android,
new phone, Google + shop + PIN), the same wording on the iOS sign-in (…၃…, …၂… because Shop A already had one failure on the
server) and on the offline unlock (…၄… to …၁…, then "PIN မှားတာ များသွားလို့ ၁၅ မိနစ် ပိတ်ထားပါတယ်။"). No phone number anywhere.

The iOS alert now reads **"“ZayPOS” Wants to Use “accounts.google.com” to Sign In"**.

Full suites:
- `flutter analyze`: No issues found.
- `flutter test`: +774 ~14 −8. Failing: the 7 known `test/qa` failures (qa_round12_report, qa_round12b_bug36, qa_round14_debt,
  qa_round14_lookalike ×2, qa_round16 ×2) and `drift_repositories_test.dart::credit checkout records the debt entry…` (Expected
  52000, Actual 53200 after the void; **passes on its own**, failed once under full-suite load: a timing flake in a test outside
  this change; watch it).
- `dotnet test`: Domain 20/20, Api 352/352, QA 39/43 (the 4 known `QaRound12Tests.TC_AUTH_NEW_2_*` non-ASCII digit failures).
- Targeted: 4 Flutter auth files 39/39; `ZayPOS.Api.Tests --filter GoogleAuth` 22/22 (attemptsLeft 4,3,2,1 asserted).

## Bugs

- **BUG-67 (Low)**: app half fixed-verified (alert says ZayPOS). Still open for the Google Cloud consent-screen name: Google's page
  says "to continue to project-&lt;number&gt;" / "You're signing back in to project-&lt;number&gt;" (config, not code).
- **BUG-69 (Low)**: fixed, verified at unit level (developer test + new QA test for the "canceled while offline" path) and live on
  Android; the live iPhone airplane-mode check is the owner's.
- No new bugs.

## Release recommendation: **Go** for a 3–5 shop beta

The Google path now works end to end on iOS as well as Android (register, sign-in on a new phone, shop choice, wrong PIN with
attempts left, forgot PIN from Login and from the locked unlock screen, same phone keeps its code). The only open items are
cosmetic (BUG-67 consent-screen name, fix in Google Cloud before an iPhone shop joins) and BUG-68 (stale device codes, known).

## MANUAL cases for the owner (real phones, in this order)

1. TC-GAUTH-NEW-3 / TC-GAUTH-09 iOS: real iPhone, airplane mode → Login → "Google နဲ့ ဝင်မယ်" → expect "အင်တာနက် မရပါ။ လိုင်းရမှ
   ပြန်ကြိုးစားပါ။" with **no** Google sheet; airplane off → it works.
2. BUG-67 after the consent-screen change: real iPhone → Google page should say "to continue to ZayPOS".
3. TC-GAUTH-09: a phone without a Google account, and an Android without / with old Play services (messages from r18 list).
4. TC-GAUTH-04 with two real phones: device A keeps selling while B signs in.

## New / changed QA test files

- `mobile/test/qa/qa_round19_bug69_test.dart` (2 tests: canceled-while-offline → network message; canceled-while-online → cancelled)
- `mobile/integration_test/qa/r18_ios_driver/QADriverUITests/QADriverUITests.swift`: new driver commands `auto off|on` (read the
  system alert before "Continue") and `swipeup|swipedown`
- Evidence: `docs/qa/evidence/round-19/` (screenshots with the Google e-mail blanked; logs with e-mails and names replaced)

Test data left on the local DB (API's `ZayPOS` database): new shop "QA R19 iOS Shop" (owner phone +959790917041, PIN 564738 after
the Android reset; devices A = iPhone, B = Android, one sale B-0001); Shop A PIN is now 246802 (iPhone = device E).
