#!/bin/zsh
# QA round 17: runs one step of r17_day_test.dart on the REAL iPhone without a driver connection.
# `flutter drive` cannot use the iPhone over Wi-Fi ("The Dart VM Service was not discovered"), so the test is built as a
# PROFILE app (integration_test target), installed and launched with devicectl, and reports to r17_host.py over the LAN.
# The run ends when the test posts "QA_DONE" (or after the timeout / when the app process is gone).
#
#   r17_ios_device.sh <step> <run-name> [extra --dart-define=… …]
# Env: DEVICE (udid), MAC_IP, EVD_DIR (docs/qa/evidence/round-17), TIMEOUT (s, default 900)
set -u
STEP=$1; RUN=$2; shift 2
DEVICE=${DEVICE:-00008120-0002610901F00032}
MAC_IP=${MAC_IP:-$(ipconfig getifaddr en0)}
REPO=${0:A:h:h:h:h}
EVD=${EVD_DIR:-$REPO/docs/qa/evidence/round-17}
LOG=$EVD/logs/$RUN.log
BLOG=$EVD/logs/${RUN}_build.log
mkdir -p $EVD/logs
: > $LOG
cd $REPO/mobile
if ! flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings integration_test/qa/r17_day_test.dart > $BLOG 2>&1; then
  echo "[runner] does not analyze cleanly"; exit 3
fi
flutter build ios --profile -t integration_test/qa/r17_day_test.dart \
  --dart-define=API_BASE_URL=http://$MAC_IP:5076 --dart-define=QA_HOST=http://$MAC_IP:8765 \
  --dart-define=QA_STEP=$STEP --dart-define=QA_RUN=$RUN "$@" >> $BLOG 2>&1 || { echo "[runner] build failed (see $BLOG)"; exit 4; }
xcrun devicectl device install app --device $DEVICE build/ios/iphoneos/Runner.app >> $BLOG 2>&1 || { echo "[runner] install failed"; exit 5; }
print -r -- "[runner] $(date '+%H:%M:%S') launch step=$STEP run=$RUN on $DEVICE (profile build, API http://$MAC_IP:5076)" >> $LOG
xcrun devicectl device process launch --terminate-existing --device $DEVICE app.zaypos >> $BLOG 2>&1 || { echo "[runner] launch failed"; exit 6; }
end=$(( $(date +%s) + ${TIMEOUT:-900} ))
while (( $(date +%s) < end )); do
  grep -q "QA_DONE" $LOG && break
  sleep 3
done
grep -q "QA_DONE" $LOG || print -r -- "[runner] $(date '+%H:%M:%S') TIMEOUT: no QA_DONE" >> $LOG
grep -E "QA_RESULT|FAILED:|CHECK FAIL|EXCEPTION|TIMEOUT" $LOG
grep -q "QA_RESULT $STEP: PASS" $LOG
