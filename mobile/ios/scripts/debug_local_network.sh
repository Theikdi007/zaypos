#!/bin/sh
# Debug builds only (docs/mobile/phase3-sync.md §8): let the app talk plain
# HTTP to the dev API on the Mac over Wi-Fi (http://<Mac LAN IP>:5076).
#
# Edits the BUILT Info.plist, never ios/Runner/Info.plist, so Release and
# Profile builds keep App Transport Security fully on (HTTPS only).
#
# - NSAllowsLocalNetworking: ATS allows HTTP to local addresses (private IPs, *.local)
# - NSLocalNetworkUsageDescription: text of the iOS "Local Network" permission prompt
set -eu

if [ "${CONFIGURATION}" != "Debug" ]; then
  exit 0
fi

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
BUDDY=/usr/libexec/PlistBuddy

# Idempotent: incremental builds may reuse an already-patched plist.
$BUDDY -c "Delete :NSAppTransportSecurity" "$PLIST" 2>/dev/null || true
$BUDDY -c "Delete :NSLocalNetworkUsageDescription" "$PLIST" 2>/dev/null || true

$BUDDY -c "Add :NSAppTransportSecurity dict" "$PLIST"
$BUDDY -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$PLIST"
$BUDDY -c "Add :NSLocalNetworkUsageDescription string ZayPOS (debug) connects to the development server on your Wi-Fi network." "$PLIST"

echo "ZayPOS: debug local networking enabled in $PLIST"
