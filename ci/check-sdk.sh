#!/usr/bin/env bash
set -euo pipefail
root=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
mkdir -p artifacts
cat "$root/system-images/android-35/google_apis/x86_64/source.properties" > artifacts/selected-image.txt
cat "$root/emulator/source.properties" > artifacts/selected-emulator.txt
grep -Eq '^Pkg.Revision[[:space:]]*=[[:space:]]*9[[:space:]]*$' artifacts/selected-image.txt
grep -Eq '^Pkg.Revision[[:space:]]*=[[:space:]]*37\.2\.13[[:space:]]*$' artifacts/selected-emulator.txt
timeout 20 "$root/emulator/emulator" -accel-check > artifacts/acceleration.txt
bash ci/ensure-job-kvm-access.sh artifacts/kvm-prelaunch
# GitHub's native RAM backing is measured, not replaced by the Celesto fix.
# All Android readiness, source identity and 38-case assertions remain intact.
