# Stage 50 — unmount, check and seal the filesystems.
stage_50_image() {
  step "Unmounting and checking filesystems"
  image_is_mounted || warn "image was not mounted; sealing anyway"
  unmount_image

  [[ -f "$WORK_IMG" ]] || die "no work image to seal"

  local loop
  loop=$(losetup --find --partscan --show "$WORK_IMG")
  e2fsck -fn "${loop}p2" 2>&1 | tee -a "$BUILD_LOG" | tail -4
  local fsck_rc=${PIPESTATUS[0]}
  losetup -d "$loop"
  # e2fsck exit codes 0 (clean) and 1 (fixed) are both acceptable.
  (( fsck_rc <= 1 )) || die "root filesystem check failed (exit ${fsck_rc})"

  local size_bytes size_gib
  size_bytes=$(stat -c %s "$WORK_IMG")
  size_gib=$(awk -v b="$size_bytes" 'BEGIN { printf "%.2f", b/1024/1024/1024 }')
  printf '%s\n' "$size_gib" > "${STATE_DIR}/image-size-gib.txt"
  ok "image sealed (${size_gib} GiB uncompressed)"
}
