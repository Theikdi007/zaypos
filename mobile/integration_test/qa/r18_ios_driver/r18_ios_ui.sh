#!/bin/zsh
# QA round 18: host side of the XCUITest driver (QADriverUITests.swift), the iOS twin of adb_ui.py.
#   r18_ios_ui.sh start <udid>          build (once) and start the driver in the background
#   r18_ios_ui.sh <command…>            send one command (dump / tap <substr> [i] / tapxy x y / type <text> / activate / quit)
#   r18_ios_ui.sh shot <name> <udid>    screenshot into $EVD_DIR (default docs/qa/evidence/round-18)
# Env: QA_IOS_DIR (default $TMPDIR/zaypos_qa_ios), DD (DerivedData dir). dump output has e-mail addresses replaced by
# <google-account>.
set -u
HERE=${0:A:h}
REPO=${HERE:h:h:h:h}
DIR=${QA_IOS_DIR:-${TMPDIR:-/tmp}/zaypos_qa_ios}
DD=${DD:-$DIR/dd}
EVD=${EVD_DIR:-$REPO/docs/qa/evidence/round-18}
mkdir -p $DIR
case ${1:-} in
  start)
    rm -f $DIR/cmd $DIR/out
    cd $HERE
    xcodebuild build-for-testing -project QADriver.xcodeproj -scheme QADriverUITests -destination "id=$2" \
      -derivedDataPath $DD > $DIR/build.log 2>&1 || { tail -20 $DIR/build.log; exit 1; }
    TEST_RUNNER_QA_IOS_DIR=$DIR nohup xcodebuild test-without-building -project QADriver.xcodeproj \
      -scheme QADriverUITests -destination "id=$2" -derivedDataPath $DD > $DIR/driver.log 2>&1 &
    for i in {1..120}; do [[ -f $DIR/out ]] && { cat $DIR/out; exit 0; }; sleep 1; done
    echo "driver did not start"; tail -20 $DIR/driver.log; exit 1 ;;
  shot)
    xcrun simctl io $3 screenshot --type=png "$EVD/$2.png" >/dev/null 2>&1 && echo "shot $EVD/$2.png" ;;
  *)
    rm -f $DIR/out
    print -r -- "$*" > $DIR/cmd.tmp && mv $DIR/cmd.tmp $DIR/cmd
    for i in {1..300}; do
      if [[ -f $DIR/out ]]; then sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+/<google-account>/g' $DIR/out; exit 0; fi
      sleep 0.2
    done
    echo "TIMEOUT (driver not answering)"; exit 1 ;;
esac
