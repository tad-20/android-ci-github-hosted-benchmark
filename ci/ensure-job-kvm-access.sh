#!/usr/bin/env bash
set -euo pipefail
out=${1:?diagnostic output path required}
test "$(id -u)" != 0
test -c /dev/kvm && test ! -L /dev/kvm
{
  date -u +%FT%TZ
  id
  stat -Lc 'device=%n inode=%i mode=%a owner=%U group=%G' /dev/kvm
  getfacl -p /dev/kvm
} > "$out.before.txt"
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  sudo -n setfacl -m "u:$(id -un):rw" /dev/kvm
fi
{
  date -u +%FT%TZ
  id
  stat -Lc 'device=%n inode=%i mode=%a owner=%U group=%G' /dev/kvm
  getfacl -p /dev/kvm
} > "$out.after.txt"
[[ -r /dev/kvm && -w /dev/kvm ]]
python3 - <<'PY'
import fcntl
import os
fd = os.open('/dev/kvm', os.O_RDWR | os.O_CLOEXEC)
try:
    version = fcntl.ioctl(fd, 0xAE00)
    assert version == 12, version
    print('Unprivileged KVM open and GET_API_VERSION=12 passed')
finally:
    os.close(fd)
PY
