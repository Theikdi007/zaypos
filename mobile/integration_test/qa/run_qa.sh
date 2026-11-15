#!/bin/zsh
# QA round 12b (extended in round 13: photos / apptmp commands, EVD_DIR) — runs one integration test (flutter drive: the app stays installed, so its data survives between runs) on an iOS simulator and serves its QA_SHOT / QA_CMD requests.
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
# Round 13: when the test does not compile, `flutter drive` falls back to the LAST built app (another test!) and runs it on the
# device. Refuse to start instead.
if ! flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings $TEST >> $LOG 2>&1; then
  print -r -- "[runner] $TEST does not analyze cleanly; not starting flutter drive" | tee -a $LOG
  exit 3
fi
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
        # QA round 13 (BUG-40): what reached the simulator's Photos library / the app's temp folder.
        photos)
          dcim=~/Library/Developer/CoreSimulator/Devices/$UDID/data/Media/DCIM
          files=($dcim/*/*(N.om))
          print -r -- "[runner] photos count ${#files}" >> $LOG
          if (( ${#files} )); then
            print -r -- "[runner] photos newest ${files[1]:t} $(stat -f '%Sm' ${files[1]}) $(sips -g pixelWidth -g pixelHeight ${files[1]} | awk '/pixel/{printf "%s=%s ", $1, $2}')" >> $LOG
            cp ${files[1]} "$EVD/photos_${RUN}_${id}.${files[1]:e:l}"
          fi ;;
        apptmp)
          tmp=$(xcrun simctl get_app_container $UDID com.zaypos.zayposApp data)/Library/Caches  # path_provider temp dir on iOS
          for f in $tmp/**/ZayPOS-receipt-*.png(N.om); do
            print -r -- "[runner] app tmp ${f#$tmp/} $(stat -f '%Sm' $f) $(sips -g pixelWidth -g pixelHeight $f | awk '/pixel/{printf "%s=%s ", $1, $2}')" >> $LOG
          done
          newest=($tmp/**/ZayPOS-receipt-*.png(N.om[1]))
          (( ${#newest} )) && cp ${newest[1]} "$EVD/apptmp_${RUN}_${id}.png" ;;
        # QA round 14 (BUG-46): what iOS logged about opening a tel: URL in the last 2 minutes.
        syslog_tel)
          xcrun simctl spawn $UDID log show --last 2m --style compact \
            --predicate 'eventMessage CONTAINS[c] "tel:" OR eventMessage CONTAINS[c] "openURL" OR eventMessage CONTAINS[c] "canOpenURL"' 2>&1 \
            | grep -v '^Timestamp' | tail -25 | sed 's/^/[runner] syslog /' >> $LOG ;;
      esac
      touch "$QA_DIR/ack_cmd_$id" ;;
  esac
done
rc=${pipestatus[1]}
print -r -- "[runner] flutter exit code $rc" >> $LOG
grep -E "^\S*[0-9]+:[0-9]+ \+[0-9]+|All tests passed|Some tests failed|QA_NOTE|EXCEPTION|Expected|Actual|Which" $LOG | tail -40
echo "exit $rc  (log: $LOG)"
exit $rc
