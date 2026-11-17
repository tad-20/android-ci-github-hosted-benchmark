#!/usr/bin/env bash
# Runs on one disposable benchmark runner, with ONE fresh owned emulator already started.
# The outer supervisor owns the guest/AVD lifetime, deadline and cleanup, including on timeout.
set -euo pipefail
workload=${1:?espresso or todo}
api=${2:?35 or 36}
case "$workload:$api" in espresso:35|espresso:36|todo:35|todo:36) ;; *) exit 64;; esac
bundle=$(cd -- "$(dirname -- "$0")" && pwd)
project=$(cd "$bundle/.." && pwd)
result=${CI_RESULT_DIR:?Set CI_RESULT_DIR to a fresh absolute artifact directory}
[[ "$result" = /* && ! -e "$result" ]] || { echo 'Fresh absolute CI_RESULT_DIR required' >&2; exit 64; }
mkdir -p "$result"
workers=${CI_GRADLE_WORKERS:-2}
case "$workers" in 2|4) ;; *) echo 'Expected Gradle worker count 2 or 4' >&2; exit 64;; esac
printf '%s\n' "$workers" > "$result/gradle-worker-limit.txt"
exec > >(tee "$result/workload.log") 2>&1
metrics=${CI_METRICS_FILE:-$result/phase-metrics.jsonl}
measure() { local phase=$1; shift; python3 "$bundle/phase-metrics.py" --output "$metrics" "$phase" -- "$@"; }
date -u +%FT%TZ > "$result/started.txt"
collect() {
  local rc=$?
  trap - EXIT
  touch "$result/sampling.stop"
  wait "$resource_sampler" || { echo 'FAIL: guest resource sampler failed'; rc=1; }
  test -s "$result/guest-resources.jsonl" || { echo 'FAIL: guest resource samples missing'; rc=1; }
  measure collect-logcat timeout 10 adb -s "$ANDROID_SERIAL" logcat -d -v threadtime > "$result/logcat.txt" 2>&1 || true
  for d in outputs/apk outputs/androidTest-results reports/androidTests; do
    if [[ -d "$project/app/build/$d" ]]; then
      mkdir -p "$result/app/build/$(dirname "$d")"
      measure collect-artifacts cp -a "$project/app/build/$d" "$result/app/build/$d"
    fi
  done
  if [[ -d "$project/build/reports/profile" ]]; then
    measure collect-gradle-profile cp -a "$project/build/reports/profile" "$result/gradle-profile"
  fi
  printf '%s\n' "$rc" > "$result/exit-code.txt"
  date -u +%FT%TZ > "$result/finished.txt"
  exit "$rc"
}
: "${ANDROID_SERIAL:?Set the exact owned emulator serial}"
[[ "$ANDROID_SERIAL" = emulator-* ]] || exit 64
trap collect EXIT
sudo -n timeout 1800 python3 "$bundle/sample-resources.py" "$result" > "$result/resource-sampler.log" 2>&1 &
resource_sampler=$!
bash "$bundle/ensure-job-kvm-access.sh" "$result/kvm-workload"
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo 'FAIL: runner user cannot access /dev/kvm'; exit 1; }
[[ $(id -u) != 0 ]] || { echo 'FAIL: run as the unprivileged job user'; exit 1; }
: "${ANDROID_SDK_ROOT:=${ANDROID_HOME:?Android SDK path required}}"
emulator_binary="$ANDROID_SDK_ROOT/emulator/emulator"
measure runner-acceleration-preflight timeout 15 "$emulator_binary" -accel-check
measure emulator-memory-backing sudo -n python3 "$bundle/record-emulator-memory.py" | tee "$result/emulator-memory.json"
java -version
"$emulator_binary" -version
id
free -h
df -h "$project"
test "$(timeout 10 adb devices | awk 'NR>1 && NF {n++} END {print n+0}')" = 1
timeout 10 adb -s "$ANDROID_SERIAL" get-state
test "$(timeout 10 adb -s "$ANDROID_SERIAL" shell getprop ro.build.version.sdk | tr -d '\r')" = "$api"
test "$(timeout 10 adb -s "$ANDROID_SERIAL" shell getprop ro.product.cpu.abi | tr -d '\r')" = x86_64
measure android-framework-readiness timeout 610 bash "$bundle/wait-framework.sh"
framework_pid=$(timeout 10 adb -s "$ANDROID_SERIAL" shell pidof system_server | tr -d '\r')
[[ "$framework_pid" =~ ^[0-9]+$ ]] || { echo 'FAIL: system_server identity unavailable'; exit 1; }
printf '%s\n' "$framework_pid" > "$result/framework-initial-pid.txt"
date -u +%FT%TZ > "$result/framework-ready.txt"
timeout 10 adb -s "$ANDROID_SERIAL" shell getprop > "$result/android-properties.txt"
timeout 10 adb -s "$ANDROID_SERIAL" shell dumpsys SurfaceFlinger > "$result/surfaceflinger.txt"
if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
  python3 "$bundle/sdk-inventory.py" "$ANDROID_SDK_ROOT" > "$result/sdk-revisions.txt"
fi
cd "$project"
# Avoid stale results and unreviewed sharing of Gradle state between attempts.
[[ ! -e app/build/outputs/androidTest-results ]] || { echo 'FAIL: fixture already has test results'; exit 1; }
: "${GRADLE_USER_HOME:?Set a private per-attempt Gradle home}"
date -u +%FT%TZ > "$result/build-started.txt"
measure apk-build timeout 900 bash ./gradlew --no-daemon --max-workers="$workers" :app:assembleDebug :app:assembleDebugAndroidTest --stacktrace --profile
date -u +%FT%TZ > "$result/build-finished.txt"
mapfile -t apks < <(find app/build/outputs/apk/debug -name '*.apk')
mapfile -t test_apks < <(find app/build/outputs/apk/androidTest/debug -name '*.apk')
[[ ${#apks[@]} = 1 && ${#test_apks[@]} = 1 ]] || { echo 'FAIL: APK identity ambiguous'; exit 1; }
sha256sum "${apks[0]}" "${test_apks[0]}" > "$result/apk-sha256.txt"
measure framework-health-before-install timeout 45 bash "$bundle/wait-framework.sh" --check-once
test "$(timeout 10 adb -s "$ANDROID_SERIAL" shell pidof system_server | tr -d '\r')" = "$framework_pid" || { echo 'FAIL: Android system_server restarted during APK build'; exit 1; }
measure app-install timeout 120 adb -s "$ANDROID_SERIAL" install -r -t "${apks[0]}"
measure test-apk-install timeout 120 adb -s "$ANDROID_SERIAL" install -r -t "${test_apks[0]}"
if [[ "$workload" = espresso ]]; then
  activity=com.example.android.testing.espresso.BasicSample/.MainActivity
else
  activity=com.example.android.architecture.blueprints.main/com.example.android.architecture.blueprints.todoapp.TodoActivity
fi
measure activity-start timeout 30 adb -s "$ANDROID_SERIAL" shell am start -W -n "$activity" > "$result/activity-start.txt"
grep -q '^Status: ok' "$result/activity-start.txt"
measure gradle-connected-tests timeout 600 bash ./gradlew --no-daemon --max-workers="$workers" :app:connectedDebugAndroidTest --stacktrace --profile
measure verify-test-results python3 "$bundle/validate-results.py" "$workload" app/build/outputs/androidTest-results/connected | tee "$result/tests.json"
