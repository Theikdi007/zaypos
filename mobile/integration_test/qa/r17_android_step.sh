#!/bin/zsh
# QA round 17: one step of r17_day_test.dart on the Android emulator through run_qa_android.sh.
# The emulator has ~400 MB free: the 209 MB debug APK (141 MB kernel blob) does not install, and every rebuilt APK made
# `flutter drive` fall back to "Uninstalling old version" (INSTALL_FAILED_INSUFFICIENT_STORAGE), which wipes the app data.
# So ONE arm64 profile APK is built (QA_STEP=fromhost) and reused for every step; the step (and QA_EXPECT) is read at start
# from r17_host.py (GET /step → r17_step.txt next to the API log). Same APK = flutter drive does not reinstall it.
#   r17_android_step.sh <serial> <step> <run-name> [expect]
# Env: API_CTL, API_LOG, EVD_DIR (as for run_qa_android.sh), REBUILD=1 to build the APK again, QA_SHOP
set -u
SERIAL=$1; STEP=$2; RUN=$3; EXPECT=${4:-}
PKG=com.zaypos.zaypos_app
APP_QA=/data/user/0/$PKG/cache/qa
cd ${0:A:h:h:h}
APK=build/r17/app-profile.apk
DEFS=(--dart-define=API_BASE_URL=http://10.0.2.2:5076 --dart-define=QA_DIR=$APP_QA --dart-define=QA_API_LOG=$APP_QA/api.log
      --dart-define=QA_RUN=r17_android --dart-define=QA_STEP=fromhost --dart-define=QA_SHOP=${QA_SHOP:-9790917181})
mkdir -p $EVD_DIR/logs build/r17
if [[ ! -f $APK || ${REBUILD:-0} == 1 ]]; then
  flutter build apk --profile --target-platform android-arm64 -t integration_test/qa/r17_day_test.dart $DEFS \
    > $EVD_DIR/logs/r17_android_apk_build.log 2>&1 || { echo "[step] build failed"; exit 4; }
  cp build/app/outputs/flutter-apk/app-profile.apk $APK
fi
print -r -- "$STEP|$EXPECT" > ${API_LOG:h}/r17_step.txt
EXTRA_DEFINES="${DEFS[*]} --profile --use-application-binary=$APK" \
  ./integration_test/qa/run_qa_android.sh $SERIAL integration_test/qa/r17_day_test.dart $RUN
