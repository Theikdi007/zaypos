#!/bin/zsh
# QA round 15 — Android variant of run_qa.sh. Runs one integration test with `flutter drive` on an Android emulator
# (the app keeps its on-disk data between runs: same package, `adb install -r`) and serves its QA_SHOT / QA_CMD lines.
#
#   API_CTL=/path/api.sh API_LOG=/path/api.log EVD_DIR=docs/qa/evidence/round-15 \
#     run_qa_android.sh <serial> <integration_test/qa/x_test.dart> [run-name]
#
# Differences from the iOS runner:
#  * The emulator cannot read host files, so acks (and a copy of the API log for OTP codes) are written INTO the app's
#    cache dir with `adb shell run-as` (works because the drive build is debuggable). The test gets
#    QA_DIR=/data/user/0/<pkg>/cache/qa and QA_API_LOG=$QA_DIR/api.log. Every QA_CMD refreshes api.log first.
#  * API_BASE_URL is http://10.0.2.2:5076 (the emulator's alias for the Mac's loopback).
#  * Screenshots: adb exec-out screencap -p.
set -u
SERIAL=$1; TEST=$2; RUN=${3:-$(basename $TEST .dart)}
PKG=com.zaypos.zaypos_app
REPO=${0:A:h:h:h:h}
EVD=${EVD_DIR:-$REPO/docs/qa/evidence/round-15}
APP_QA=/data/user/0/$PKG/cache/qa
API_LOG=${API_LOG:-/dev/null}
mkdir -p $EVD/logs
LOG=$EVD/logs/$RUN.log
: > $LOG
A=(adb -s $SERIAL)
push_log() { $A shell "run-as $PKG sh -c 'mkdir -p cache/qa'" </dev/null >>$LOG 2>&1; $A exec-in "run-as $PKG sh -c 'cat > cache/qa/api.log'" < $API_LOG 2>>$LOG; }
ack() { $A shell "run-as $PKG sh -c 'mkdir -p cache/qa && touch cache/qa/ack_$1'" </dev/null >>$LOG 2>&1; }
cd $REPO/mobile
if ! flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings $TEST >> $LOG 2>&1; then
  print -r -- "[runner] $TEST does not analyze cleanly; not starting flutter drive" | tee -a $LOG
  exit 3
fi
# The previous run's acks would satisfy this run's handshakes: clear them (ignored if the app is not installed yet).
$A shell "run-as $PKG sh -c 'rm -rf cache/qa'" >/dev/null 2>&1
flutter drive --keep-app-running --driver=test_driver/integration_test.dart --target=$TEST -d $SERIAL \
  --dart-define=API_BASE_URL=http://10.0.2.2:5076 \
  --dart-define=QA_DIR=$APP_QA \
  --dart-define=QA_API_LOG=$APP_QA/api.log \
  --dart-define=QA_RUN=$RUN ${=EXTRA_DEFINES:-} 2>&1 | while IFS= read -r line; do
  print -r -- "$line" >> $LOG
  case $line in
    *QA_SHOT:*)
      name=${line##*QA_SHOT:}
      $A exec-out screencap -p </dev/null > "$EVD/$name.png" 2>>$LOG
      print -r -- "[runner] screenshot $name.png" >> $LOG
      ack "shot_$name" ;;
    *QA_CMD:*)
      rest=${line##*QA_CMD:}; cmd=${rest%%:*}; id=${rest#*:}
      print -r -- "[runner] $(date '+%H:%M:%S') cmd $cmd" >> $LOG
      push_log
      case $cmd in
        api_stop) $API_CTL stop >> $LOG 2>&1 ;;
        api_start) $API_CTL start >> $LOG 2>&1 ;;
        sync_log) ;;  # api.log already refreshed above
        back) $A shell input keyevent KEYCODE_BACK </dev/null >> $LOG 2>&1 ;;
        rotate_land) $A shell settings put system accelerometer_rotation 0 </dev/null; $A shell settings put system user_rotation 1 </dev/null ;;
        rotate_port) $A shell settings put system user_rotation 0 </dev/null ;;
        font_max) $A shell settings put system font_scale 2.0 </dev/null >> $LOG 2>&1 ;;
        font_default) $A shell settings put system font_scale 1.0 </dev/null >> $LOG 2>&1 ;;
        density_max) $A shell wm density 540 </dev/null >> $LOG 2>&1 ;;   # largest "Display size" step on this 1080-px, 420-dpi device (smallest width 320 dp)
        density_reset) $A shell wm density reset </dev/null >> $LOG 2>&1 ;;
        # QA round 17: airplane mode (checklist 18-19); the adb link to the emulator is not affected.
        airplane_on) $A shell cmd connectivity airplane-mode enable </dev/null >> $LOG 2>&1; print -r -- "[runner] airplane-mode now $($A shell cmd connectivity airplane-mode </dev/null)" >> $LOG ;;
        airplane_off) $A shell cmd connectivity airplane-mode disable </dev/null >> $LOG 2>&1; print -r -- "[runner] airplane-mode now $($A shell cmd connectivity airplane-mode </dev/null)" >> $LOG ;;
        mem) $A shell dumpsys meminfo $PKG </dev/null | grep -E "TOTAL PSS|TOTAL RSS" | head -2 | sed 's/^/[runner] /' >> $LOG ;;
        wait_*) sleep ${cmd#wait_} ;;
      esac
      ack "cmd_$id" ;;
  esac
done
rc=${pipestatus[1]}
print -r -- "[runner] flutter exit code $rc" >> $LOG
grep -E "^\S*[0-9]+:[0-9]+ \+[0-9]+|All tests passed|Some tests failed|QA_NOTE|EXCEPTION|Expected|Actual|Which" $LOG | tail -60
echo "exit $rc  (log: $LOG)"
exit $rc
