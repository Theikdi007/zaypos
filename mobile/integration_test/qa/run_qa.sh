#!/bin/zsh
# QA round 12b — runs one integration test (flutter drive: the app stays installed, so its data survives between runs) on an iOS simulator and serves its QA_SHOT / QA_CMD requests.
#   API_CTL=/path/to/api.sh API_LOG=/path/to/api.log run_qa.sh <simulator-udid> <integration_test/qa/x_test.dart> [run-name]
# Screenshots go to docs/qa/evidence/round-12b/<name>.png, the full flutter output to …/logs/<run-name>.log.
# API_CTL must accept "start" and "stop" (the scratch-DB API on http://localhost:5076).
set -u
UDID=$1; TEST=$2; RUN=${3:-$(basename $TEST .dart)}
REPO=${0:A:h:h:h:h}
EVD=${EVD_DIR:-$REPO/docs/qa/evidence/round-12b}
QA_DIR=${QA_DIR:-${TMPDIR:-/tmp}/zaypos_qa_ack}
mkdir -p $EVD/logs $QA_DIR
rm -f $QA_DIR/ack_*(N)
LOG=$EVD/logs/$RUN.log
: > $LOG
cd $REPO/mobile
flutter drive --keep-app-running --driver=test_driver/integration_test.dart --target=$TEST -d $UDID \
  --dart-define=API_BASE_URL=http://localhost:5076 \
  --dart-define=QA_DIR=$QA_DIR \
  --dart-define=QA_API_LOG=$API_LOG \
  --dart-define=QA_RUN=$RUN ${=EXTRA_DEFINES:-} 2>&1 | while IFS= read -r line; do
  print -r -- "$line" >> $LOG
  case $line in
    *QA_SHOT:*)
      name=${line##*QA_SHOT:}
      xcrun simctl io $UDID screenshot --type=png "$EVD/$name.png" >/dev/null 2>&1
      print -r -- "[runner] screenshot $name.png" >> $LOG
      touch "$QA_DIR/ack_shot_$name" ;;
    *QA_CMD:*)
      rest=${line##*QA_CMD:}; cmd=${rest%%:*}; id=${rest#*:}
      print -r -- "[runner] $(date '+%H:%M:%S') cmd $cmd" >> $LOG
      case $cmd in
        api_stop) $API_CTL stop >> $LOG 2>&1 ;;
        api_start) $API_CTL start >> $LOG 2>&1 ;;
        font_xxxl) xcrun simctl ui $UDID content_size extra-extra-extra-large >> $LOG 2>&1 ;;
        font_ax5) xcrun simctl ui $UDID content_size accessibility-extra-extra-extra-large >> $LOG 2>&1 ;;
        font_default) xcrun simctl ui $UDID content_size large >> $LOG 2>&1 ;;
        kill_app) xcrun simctl terminate $UDID com.zaypos.zayposApp >> $LOG 2>&1 ;;
        mem) ps -axo rss=,command= | grep "$UDID" | grep 'Runner.app/Runner ' | grep -v grep | awk '{printf "[runner] app RSS %.1f MB\n", $1/1024}' >> $LOG ;;
        wait_*) sleep ${cmd#wait_} ;;
      esac
      touch "$QA_DIR/ack_cmd_$id" ;;
  esac
done
rc=${pipestatus[1]}
print -r -- "[runner] flutter exit code $rc" >> $LOG
grep -E "^\S*[0-9]+:[0-9]+ \+[0-9]+|All tests passed|Some tests failed|QA_NOTE|EXCEPTION|Expected|Actual|Which" $LOG | tail -40
echo "exit $rc  (log: $LOG)"
exit $rc
