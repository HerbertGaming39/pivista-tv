#!/bin/bash
# Check that every package named in manifest/packages.lock resolves in the
# pinned base image's apt sources. Runs inside the base image chroot.
set -euo pipefail

PROJECT=/mnt/c/Users/marcel/Downloads/pivista-tv
WORK=/var/tmp/pivista-build
IMG="$WORK/downloads/base.img"
ROOT="$WORK/pkgcheck-root"

cleanup() {
    mountpoint -q "$ROOT/dev/pts" && umount "$ROOT/dev/pts" || true
    mountpoint -q "$ROOT/dev" && umount "$ROOT/dev" || true
    mountpoint -q "$ROOT/proc" && umount "$ROOT/proc" || true
    mountpoint -q "$ROOT/sys" && umount "$ROOT/sys" || true
    mountpoint -q "$ROOT" && umount "$ROOT" || true
    [ -n "${LOOP:-}" ] && losetup "$LOOP" >/dev/null 2>&1 && losetup -d "$LOOP" || true
}
trap cleanup EXIT

mkdir -p "$ROOT"
LOOP=$(losetup --find --partscan --show "$IMG")
mount "${LOOP}p2" "$ROOT"
mkdir -p "$ROOT/dev/pts" "$ROOT/proc" "$ROOT/sys"
mount --bind /dev "$ROOT/dev"
mount --bind /dev/pts "$ROOT/dev/pts"
mount --bind /proc "$ROOT/proc"
mount --bind /sys "$ROOT/sys"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"

echo "== apt update =="
chroot "$ROOT" apt-get update -qq 2>&1 | tail -3

echo "== candidates =="
awk '/^\[/ {s=$0; gsub(/[\[\]]/,"",s); next} /^\s*#/ {next} /^\s*$/ {next} {print s" "$1}' \
    "$PROJECT/manifest/packages.lock" | while read -r section pkg; do
    candidate=$(chroot "$ROOT" apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}')
    printf '%-28s %-28s %s\n' "$section" "$pkg" "${candidate:-MISSING}"
done
