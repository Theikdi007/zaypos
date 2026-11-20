#!/usr/bin/env bash
# Beta APK for the beta shops (docs/mobile/beta-release.md). Run on the Mac from the repo:
#   deploy/build-beta-apk.sh             build + check only: nothing leaves this Mac
#   deploy/build-beta-apk.sh --upload    build + check, upload the Crashlytics symbols, then send the APK to
#                                        Firebase App Distribution group "beta-shops" with the Burmese notes
# The version is pubspec.yaml's (versionName+versionCode); the release notes are
# deploy/beta-notes/<versionName>.txt. The API must already run the server version this APK needs.
set -euo pipefail

mode="${1:-}"
[[ -z "$mode" || "$mode" == --upload ]] || { echo "usage: deploy/build-beta-apk.sh [--upload]" >&2; exit 2; }
upload=0; [[ "$mode" == --upload ]] && upload=1

cd "$(dirname "$0")/.."
repo=$(pwd)
app="$repo/mobile"
api_url="https://api.zaypos.app"
group="beta-shops"

die() { echo "error: $*" >&2; exit 1; }

# --- what this build needs (all gitignored, docs/mobile/beta-release.md) ------------------------------
[[ -f "$app/android/key.properties" ]] || die "mobile/android/key.properties missing (docs/mobile/release-signing.md)"
[[ -f "$app/android/app/google-services.json" ]] || die "mobile/android/app/google-services.json missing (Firebase → Android app app.zaypos)"
[[ -f "$app/google.json" ]] || die "mobile/google.json missing (Google Sign-In client ids, docs/backend/auth-google.md §6)"
if [[ -n "$(git status --porcelain)" && "${ALLOW_DIRTY:-0}" != 1 ]]; then
  git status --short >&2
  die "uncommitted changes: commit first, so the APK matches a commit (ALLOW_DIRTY=1 to override)"
fi

version=$(sed -n 's/^version: *//p' "$app/pubspec.yaml")          # e.g. 0.5.0+5
name=${version%%+*}
notes="$repo/deploy/beta-notes/$name.txt"
[[ -s "$notes" ]] || die "release notes $notes missing"
# Firebase's id of the Android app (not a secret; the same one the App Distribution page shows).
firebase_app=$(python3 -I -c 'import json,sys
d = json.load(open(sys.argv[1]))
ids = [c["client_info"]["mobilesdk_app_id"] for c in d["client"]
       if c["client_info"]["android_client_info"]["package_name"] == "app.zaypos"]
print(ids[0] if ids else "")' "$app/android/app/google-services.json")
[[ -n "$firebase_app" ]] || die "google-services.json has no Android app app.zaypos"

out="$app/build/beta/$version"
symbols="$out/symbols"     # keep: Crashlytics needs them to read obfuscated stack traces
apk="$out/zaypos-$version.apk"
rm -rf "$out" && mkdir -p "$symbols"

# --- build ---------------------------------------------------------------------------------------------
echo "==> Building ZayPOS $version ($(git rev-parse --short HEAD)) for $api_url"
(cd "$app" && flutter build apk --release \
  --obfuscate --split-debug-info="$symbols" \
  --dart-define-from-file=google.json \
  --dart-define=API_BASE_URL="$api_url")
cp "$app/build/app/outputs/flutter-apk/app-release.apk" "$apk"

# --- checks: the upload key, not the debug key; the right version --------------------------------------
build_tools=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/* | sort -V | tail -1)
signer=$("$build_tools/apksigner" verify --print-certs "$apk" | sed -n 's/.*certificate SHA-256 digest: //p' | head -1)
debug=$(keytool -list -v -keystore "$HOME/.android/debug.keystore" -alias androiddebugkey -storepass android 2>/dev/null \
  | sed -n 's/.*SHA256: //p' | tr -d ':' | tr 'A-F' 'a-f')
[[ -n "$signer" ]] || die "apksigner could not read the APK's signature"
[[ "$signer" != "$debug" ]] || die "the APK is signed with the DEBUG key: check mobile/android/key.properties"
badging=$("$build_tools/aapt2" dump badging "$apk" | head -1)
[[ "$badging" == *"name='app.zaypos'"*"versionCode='${version##*+}'"*"versionName='$name'"* ]] \
  || die "unexpected package/version: $badging"
echo "    signed by the upload key (SHA-256 ${signer:0:16}…), $badging"
echo "    APK:     $apk ($(du -h "$apk" | cut -f1))"
echo "    symbols: $symbols"

if ((!upload)); then
  echo "==> Built only. Nothing was uploaded. To send it to \"$group\": deploy/build-beta-apk.sh --upload"
  exit 0
fi

# --- upload: Crashlytics symbols first, then the APK to the testers -------------------------------------
command -v firebase > /dev/null || die "firebase CLI missing: npm install -g firebase-tools, then firebase login"
echo "==> Uploading Crashlytics symbols"
firebase crashlytics:symbols:upload --app="$firebase_app" "$symbols"
echo "==> Sending $apk to App Distribution group \"$group\""
firebase appdistribution:distribute "$apk" --app "$firebase_app" --groups "$group" --release-notes-file "$notes"
echo "==> Sent ZayPOS $version to \"$group\". Keep $symbols (or re-upload it) for this version's crash reports."
