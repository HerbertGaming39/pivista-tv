# Stage 10 — fetch, verify, expand and mount the pinned Raspberry Pi OS base.
stage_10_base() {
  need_cmd curl xz sfdisk parted losetup mkfs.ext4 e2fsck resize2fs

  fetch_base_image

  step "Preparing work image"
  # Reuse an already-assembled root filesystem so `image` does not throw away
  # installed packages and the compiled launcher. A work image is only trusted
  # when stage 10 recorded the same pinned base; otherwise it is rebuilt from
  # scratch and every downstream stage marker is invalidated.
  local base_marker; base_marker=$(marker_path 10-base)
  local reuse=0
  if [[ -f "$WORK_IMG" && "${PIVISTA_REUSE_ROOTFS:-1}" != "0" ]] \
     && grep -q "base=${BASE_IMAGE_SHA256}" "$base_marker" 2>/dev/null; then
    reuse=1
  fi
  if (( ! reuse )); then
    unmount_image
    rm -f "$WORK_IMG"
    rm -f "$(marker_path 20-packages)" "$(marker_path 25-launcher)" \
          "$(marker_path 30-overlay)" "$(marker_path 40-finalize)"
  fi

  if [[ ! -f "$WORK_IMG" ]]; then
    log "decompressing base image (this takes a minute)"
    xz -dc "$(base_archive)" > "$WORK_IMG.part"
    mv "$WORK_IMG.part" "$WORK_IMG"
    ok "decompressed $(du -h "$WORK_IMG" | cut -f1) base image"
  else
    ok "reusing assembled work image (PIVISTA_REUSE_ROOTFS=1)"
  fi

  umount "$ROOT_MNT" 2>/dev/null || true
  umount "$BOOT_MNT" 2>/dev/null || true

  step "Expanding root partition to ${PIVISTA_ROOT_PART_GB} GiB"
  local target_bytes=$(( (PIVISTA_BOOT_PART_MB + PIVISTA_ROOT_PART_GB * 1024) * 1024 * 1024 + 16 * 1024 * 1024 ))
  local current_bytes; current_bytes=$(stat -c %s "$WORK_IMG")
  if (( current_bytes < target_bytes )); then
    truncate -s "$target_bytes" "$WORK_IMG"
  fi
  parted -s "$WORK_IMG" resizepart 2 100%
  ok "partition table grown"

  mount_image
  resize2fs "$LOOP_DEV"p2 >/dev/null
  ok "ext4 root filesystem expanded to $(df -h "$ROOT_MNT" | tail -1 | awk '{print $2}')"

  install_policy_rc

  # Reproducible-build hygiene: stable hostname until first boot, no stale state.
  printf '%s\n' "${PIVISTA_SLUG}" > "$ROOT_MNT/etc/hostname"
  if ! grep -q "127.0.1.1.*${PIVISTA_SLUG}" "$ROOT_MNT/etc/hosts"; then
    printf '127.0.1.1\t%s\n' "${PIVISTA_SLUG}" >> "$ROOT_MNT/etc/hosts"
  fi

  marker_write 10-base printf 'base=%s\n' "$BASE_IMAGE_SHA256"
}
