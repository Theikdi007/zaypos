# Beta release (Android APK through Firebase App Distribution)

`deploy/build-beta-apk.sh` builds the release APK and, only with `--upload`, sends it to the testers.

```sh
deploy/build-beta-apk.sh            # build + checks only; nothing leaves the Mac
deploy/build-beta-apk.sh --upload   # + Crashlytics symbols + App Distribution group "beta-shops"
```

What it does:

1. Checks the gitignored inputs: `mobile/android/key.properties` (release-signing.md),
   `mobile/android/app/google-services.json`, `mobile/google.json` (Google Sign-In ids), a clean git tree,
   and the release notes `deploy/beta-notes/<versionName>.txt` (Burmese).
2. `flutter build apk --release --obfuscate --split-debug-info=… --dart-define-from-file=google.json
   --dart-define=API_BASE_URL=https://api.zaypos.app` (version from `pubspec.yaml`, e.g. 0.5.0+5).
3. Refuses an APK signed with the debug key or with the wrong package / version.
4. `--upload` only: `firebase crashlytics:symbols:upload` (obfuscated stack traces are unreadable
   without them), then `firebase appdistribution:distribute … --groups beta-shops --release-notes-file …`.

The symbols stay in `mobile/build/beta/<version>/symbols`. Keep them until that version is retired
(Crashlytics can re-read crashes once they are uploaded again).

**Server first.** Deploy the API this APK needs before sending it. 0.5.0 needs the `UnknownCostIsNull`
migration, and older apps can't read a product with an unknown (null) cost, so every phone of a shop
moves to 0.5.0 together.

## One-time setup (owner)

Firebase console, project of the app `app.zaypos`:

1. **Crashlytics**: Build → Crashlytics → *Enable Crashlytics* for the Android app `app.zaypos`. The first
   report appears after a release build has started once and been reopened.
2. **App Distribution**: Release & Monitor → App Distribution → *Get started* (accept the terms).
3. **Testers group**: App Distribution → *Testers & Groups* → *Add group* → alias exactly **`beta-shops`**
   → add the testers' Google emails. Each tester gets an email invite and installs through the
   Firebase App Tester app (Android must allow "Install unknown apps" for it).
4. **Release SHA**: the upload key's SHA-1/SHA-256 on the Android app (Project settings), then download
   `google-services.json` again into `mobile/android/app/` (release-signing.md).

On the Mac (once):

```sh
npm install -g firebase-tools     # or: curl -sL https://firebase.tools | bash
firebase login                    # opens the browser: sign in with the Firebase project's owner account
firebase projects:list            # the ZayPOS project must be listed
```

## Crash reports and privacy

`lib/core/crash/crash_reporting.dart`: release builds on Android only. A report holds the error's
type (plus the stable code of the app's own errors, e.g. `ApiError(409, duplicate_barcode)`) and the stack
trace. Never the error's message, never a user id, custom keys or logs, so no phone numbers, customer or
product names, amounts, emails or tokens. Android's own (Java/Kotlin) crash reports are collected by
the Crashlytics SDK as they are. Without `google-services.json` the app builds and runs with crash
reporting off; iOS has none yet.
