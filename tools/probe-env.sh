#!/bin/bash
# Probe the WSL build host for capabilities the PiVista TV image pipeline needs.
set -u
echo "== identity =="; id
echo "== loop devices =="
ls -l /dev/loop-control /dev/loop0 2>&1 | head -3
losetup -f 2>&1 || true
echo "== binfmt_misc =="
if [ -d /proc/sys/fs/binfmt_misc ]; then
  echo "dir present"; ls /proc/sys/fs/binfmt_misc 2>&1 | head -5
else
  echo "absent"
fi
mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>&1 && echo "BINFMT_MOUNT_OK" || echo "BINFMT_MOUNT_FAILED"
ls /proc/sys/fs/binfmt_misc 2>&1 | head -5
echo "== mount test (tmpfs) =="
mkdir -p /tmp/probe-mnt
mount -t tmpfs -o size=1M tmpfs /tmp/probe-mnt 2>&1 && { echo "MOUNT_OK"; umount /tmp/probe-mnt; } || echo "MOUNT_FAILED"
echo "== tools =="
for t in debootstrap mmdebstrap losetup sfdisk sgdisk parted mkfs.ext4 mkfs.vfat mcopy mdir rsync qemu-aarch64-static qemu-system-aarch64 unshare fakeroot python3 git curl xz zstd e2fsck debugfs apt-get; do
  if command -v "$t" >/dev/null 2>&1; then echo "OK   $t"; else echo "MISS $t"; fi
done
echo "== apt =="
apt-get -v 2>&1 | head -1
echo "== sources =="
grep -rhs '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | head -5
echo "== disk =="
df -h / /mnt/c | tail -2
echo "== proxy/network =="
curl -sS -o /dev/null -w "raspberrypi.com=%{http_code} " --max-time 20 https://downloads.raspberrypi.com/ 2>&1
curl -sS -o /dev/null -w "deb.debian.org=%{http_code}\n" --max-time 20 https://deb.debian.org/debian/ 2>&1
