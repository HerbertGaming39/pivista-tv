# Stage 25 — compile the Qt Quick launcher for arm64 inside the image chroot.
stage_25_launcher() {
  image_is_mounted || die "image is not mounted; run stage 10 first"

  local src="${PROJECT_DIR}/launcher"
  local digest
  digest=$(hash_tree launcher/src launcher/qml launcher/assets launcher/CMakeLists.txt)
  local marker; marker=$(marker_path 25-launcher)

  if [[ -f "$marker" ]] && grep -q "source_digest=${digest}" "$marker" \
     && [[ -x "$ROOT_MNT/usr/bin/pivista-launcher" ]] && [[ "${PIVISTA_FORCE_LAUNCHER:-0}" != "1" ]]; then
    ok "launcher binary is current (${digest:0:12})"
    return 0
  fi

  step "Copying launcher sources into the image chroot"
  rm -rf "$ROOT_MNT/usr/src/pivista-launcher"
  mkdir -p "$ROOT_MNT/usr/src/pivista-launcher"
  rsync -a --delete "${src}/src/" "$ROOT_MNT/usr/src/pivista-launcher/src/"
  rsync -a --delete "${src}/qml/" "$ROOT_MNT/usr/src/pivista-launcher/qml/"
  [[ -d "${src}/assets" ]] && rsync -a --delete "${src}/assets/" "$ROOT_MNT/usr/src/pivista-launcher/assets/"
  install -m 0644 "${src}/CMakeLists.txt" "$ROOT_MNT/usr/src/pivista-launcher/CMakeLists.txt"

  step "Compiling pivista-launcher for ${PIVISTA_ARCH} (qemu-user, -j${PIVISTA_JOBS})"
  chroot_run bash -lc '
    set -e
    cd /usr/src/pivista-launcher
    rm -rf build
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build build --parallel '"${PIVISTA_JOBS}"'
    install -D -m 0755 build/pivista-launcher /usr/bin/pivista-launcher
  ' 2>&1 | tee -a "$BUILD_LOG" | tail -12

  [[ -x "$ROOT_MNT/usr/bin/pivista-launcher" ]] || die "launcher build did not produce /usr/bin/pivista-launcher"
  chroot_run /usr/bin/pivista-launcher --version 2>&1 | tee -a "$BUILD_LOG" || \
    die "launcher binary is not executable in the image (ABI or dependency problem)"

  rm -rf "$ROOT_MNT/usr/src/pivista-launcher"
  ok "launcher installed: $(chroot_run /usr/bin/pivista-launcher --version)"
  marker_write 25-launcher printf 'source_digest=%s\n' "$digest"
}
