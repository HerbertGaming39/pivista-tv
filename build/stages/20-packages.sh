# Stage 20 — install runtime and launcher build dependencies inside the image.
stage_20_packages() {
  image_is_mounted || die "image is not mounted; run stage 10 first"

  local runtime build_pkgs
  runtime=$(list_packages runtime)
  build_pkgs=$(list_packages build)

  [[ -n "$runtime" ]] || die "runtime package list is empty"

  local marker; marker=$(marker_path 20-packages)
  local digest
  digest=$(sha256sum "${PROJECT_DIR}/manifest/packages.lock" | cut -d' ' -f1)
  if [[ -f "$marker" ]] && grep -q "packages_lock=${digest}" "$marker" && [[ "${PIVISTA_FORCE_PACKAGES:-0}" != "1" ]]; then
    ok "packages already installed for this manifest (${digest:0:12})"
    return 0
  fi

  step "apt update"
  chroot_run apt-get update -qq
  ok "package indexes updated"

  step "Installing runtime packages"
  # shellcheck disable=SC2086
  chroot_run apt-get install -y --no-install-recommends \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
      $runtime 2>&1 | tee -a "$BUILD_LOG" | tail -5
  ok "runtime packages installed"

  step "Installing launcher build dependencies"
  # shellcheck disable=SC2086
  chroot_run apt-get install -y --no-install-recommends \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
      $build_pkgs 2>&1 | tee -a "$BUILD_LOG" | tail -5
  ok "build dependencies installed"

  if ! chroot_run dpkg -s libwidevinecdm0 >/dev/null 2>&1; then
    warn "libwidevinecdm0 is not available in this base image; DRM playback will be unavailable"
  fi

  marker_write 20-packages printf 'packages_lock=%s\n' "$digest"
}
