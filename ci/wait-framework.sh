#!/usr/bin/env bash
set -euo pipefail
: "${ANDROID_SERIAL:?Exact owned emulator serial required}"
deadline=$((SECONDS+600))
while :; do
  if [[ "$(timeout 10 adb -s "$ANDROID_SERIAL" shell getprop sys.boot_completed | tr -d '\r')" = 1 ]] &&
     timeout 10 adb -s "$ANDROID_SERIAL" shell pm path android | grep -q '^package:' &&
     timeout 10 adb -s "$ANDROID_SERIAL" shell service check activity | tr -d '\r' | grep -qx 'Service activity: found' &&
     timeout 10 adb -s "$ANDROID_SERIAL" shell service check package | tr -d '\r' | grep -qx 'Service package: found'; then exit 0; fi
  [[ ${1:-} != --check-once ]] || { echo 'FAIL: Android framework is not currently healthy'; exit 1; }
  (( SECONDS < deadline )) || { echo 'FAIL: Android framework readiness timeout'; exit 124; }
  sleep 2
done
