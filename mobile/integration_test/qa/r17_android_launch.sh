#!/bin/zsh
# QA round 17: one step of r17_day_test.dart on the Android emulator WITHOUT flutter drive (like the real iPhone).
# Why: the emulator has ~400 MB free, and every `flutter drive` re-install of the 72 MB APK failed with
# INSTALL_FAILED_INSUFFICIENT_STORAGE and fell back to "Uninstalling old version" (= the app data wiped between steps).
# So ONE profile APK (QA_STEP=fromhost, QA_HOST=http://10.0.2.2:8765) is installed once and only launched per step; the step,
# QA_EXPECT and the run name come from r17_host.py (GET /step ← r17_step.txt next to the API log); notes and screenshots go
# to the host. Host actions (airplane mode window, font scale) run through GET /cmd on r17_host.py.
#   r17_android_launch.sh <step> <run-name> [expect]
# Env: SERIAL (emulator-5554), API_LOG (its folder holds r17_step.txt), EVD_DIR, REBUILD=1, QA_SHOP, TIMEOUT
set -u
STEP=$1; RUN=$2; EXPECT=${3:-}
SERIAL=${SERIAL:-emulator-5554}
PKG=com.zaypos.zaypos_app
A=(adb -s $SERIAL)
cd ${0:A:h:h:h}
APK=build/r17/app-profile-host.apk
LOG=$EVD_DIR/logs/$RUN.log
mkdir -p $EVD_DIR/logs build/r17
if [[ ! -f $APK || ${REBUILD:-0} == 1 ]]; then
  flutter build apk --profile --target-platform android-arm64 -t integration_test/qa/r17_day_test.dart \
    --dart-define=API_BASE_URL=http://10.0.2.2:5076 --dart-define=QA_HOST=http://10.0.2.2:8765 \
    --dart-define=QA_STEP=fromhost --dart-define=QA_RUN=r17_android --dart-define=QA_SHOP=${QA_SHOP:-9790917181} \
    > $EVD_DIR/logs/r17_android_apk_build.log 2>&1 || { echo "[launch] build failed"; exit 4; }
  cp build/app/outputs/flutter-apk/app-profile.apk $APK
  $A install -r $APK >> $EVD_DIR/logs/r17_android_apk_build.log 2>&1 || { echo "[launch] install failed"; exit 5; }
fi
print -r -- "$STEP|$EXPECT|$RUN" > ${API_LOG:h}/r17_step.txt
: > $LOG
print -r -- "[launch] $(date '+%H:%M:%S') step=$STEP run=$RUN serial=$SERIAL (profile APK, no driver); pid before: '$($A shell pidof $PKG)'" >> $LOG
$A shell am force-stop $PKG
$A shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
end=$(( $(date +%s) + ${TIMEOUT:-900} ))
while (( $(date +%s) < end )); do grep -q "QA_DONE" $LOG && break; sleep 3; done
grep -q "QA_DONE" $LOG || print -r -- "[launch] $(date '+%H:%M:%S') TIMEOUT: no QA_DONE" >> $LOG
grep -E "QA_RESULT|FAILED:|CHECK FAIL|EXCEPTION|TIMEOUT" $LOG
grep -q "QA_RESULT $STEP: PASS" $LOG
