#!/usr/bin/env bash
# BUG-55 release-build check (Android emulator or phone over adb).
#
# 1. Builds a RELEASE APK with an http:// API_BASE_URL, installs and starts it,
#    and requires: the refusal screen ("ZayPOS ကို ဖွင့်လို့ မရပါ") is shown and
#    logcat has "ZayPOS: InsecureApiUrl". While it runs, a listener on the host
#    port records any connection: there must be none.
# 2. With HTTPS_URL set, builds a release APK with that https URL and requires
#    that the refusal screen is NOT shown (the login screen appears).
#
# Usage (from mobile/):
#   tool/release_https_check.sh                       # step 1 only
#   HTTPS_URL=https://api.example.com tool/release_https_check.sh
# Env: ADB_SERIAL (default: the only device), HTTP_URL (default http://10.0.2.2:5076),
#      HOST_PORT (default 5076; must be free, nothing may run on it during step 1).
set -euo pipefail

cd "$(dirname "$0")/.."
PKG=com.zaypos.zaypos_app
HTTP_URL=${HTTP_URL:-http://10.0.2.2:5076}
HOST_PORT=${HOST_PORT:-5076}
ADB=(adb ${ADB_SERIAL:+-s "$ADB_SERIAL"})
APK=build/app/outputs/flutter-apk/app-release.apk
OUT=${OUT:-build/release_https_check}
mkdir -p "$OUT"

fail() { echo "FAIL: $*" >&2; exit 1; }

dump_ui() { # $1 = file
  "${ADB[@]}" shell uiautomator dump /sdcard/rhc.xml >/dev/null
  "${ADB[@]}" exec-out cat /sdcard/rhc.xml >"$1"
}

run_build() { # $1 = url, $2 = tag
  echo "== release build with API_BASE_URL=$1"
  flutter build apk --release --dart-define=API_BASE_URL="$1" | tail -2
  cp "$APK" "$OUT/app-release-$2.apk"
  "${ADB[@]}" uninstall "$PKG" >/dev/null 2>&1 || true
  "${ADB[@]}" install "$OUT/app-release-$2.apk" | tail -1
  "${ADB[@]}" logcat -c
  "${ADB[@]}" shell am start -W -n "$PKG/.MainActivity" | grep -E 'Status|TotalTime' || true
  sleep 5
  dump_ui "$OUT/ui-$2.xml"
  "${ADB[@]}" exec-out screencap -p >"$OUT/screen-$2.png"
  "${ADB[@]}" logcat -d -s flutter >"$OUT/logcat-$2.txt" || true
}

# ---- step 1: http must be refused, nothing may be sent
if lsof -nP -iTCP:"$HOST_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  fail "port $HOST_PORT is in use; stop the API first (step 1 proves nothing is sent to it)"
fi
python3 - "$HOST_PORT" "$OUT/connections.txt" <<'PY' &
import socket, sys
port, out = int(sys.argv[1]), sys.argv[2]
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', port)); s.listen(5); s.settimeout(1)
open(out, 'w').close()
while True:
    try:
        c, a = s.accept()
        with open(out, 'a') as f: f.write(f'connection from {a}\n')
        c.close()
    except socket.timeout:
        pass
PY
LISTENER=$!
trap 'kill $LISTENER 2>/dev/null || true' EXIT

run_build "$HTTP_URL" http
# Let the app try anything it would try (sync timer, limits refresh).
sleep 10
grep -q 'ZayPOS ကို ဖွင့်လို့ မရပါ' "$OUT/ui-http.xml" || fail "refusal screen not shown (see $OUT/ui-http.xml, screen-http.png)"
grep -q 'ZayPOS: InsecureApiUrl' "$OUT/logcat-http.txt" || fail "no InsecureApiUrl line in logcat ($OUT/logcat-http.txt)"
[ ! -s "$OUT/connections.txt" ] || fail "the app connected to the http port: $(cat "$OUT/connections.txt")"
echo "PASS step 1: http release build refused to start; 0 connections to :$HOST_PORT"
kill $LISTENER 2>/dev/null || true

# ---- step 2 (optional): https must start normally
if [ -n "${HTTPS_URL:-}" ]; then
  case "$HTTPS_URL" in https://*) ;; *) fail "HTTPS_URL must start with https://";; esac
  run_build "$HTTPS_URL" https
  if grep -q 'ZayPOS ကို ဖွင့်လို့ မရပါ' "$OUT/ui-https.xml"; then fail "https build was refused"; fi
  grep -q 'ဝင်မယ်' "$OUT/ui-https.xml" || fail "login screen not shown (see $OUT/ui-https.xml)"
  echo "PASS step 2: https release build starts (login shown)"
fi
"${ADB[@]}" uninstall "$PKG" >/dev/null 2>&1 || true
echo "Evidence in $OUT/"
