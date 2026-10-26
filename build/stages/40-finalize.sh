# Stage 40 — purge build dependencies, reset identity and seal the rootfs.
stage_40_finalize() {
  image_is_mounted || die "image is not mounted; run stage 10 first"

  step "Verifying the launcher before removing build dependencies"
  chroot_run /usr/bin/pivista-launcher --version | tee -a "$BUILD_LOG"
  local launcher_version; launcher_version=$(chroot_run /usr/bin/pivista-launcher --version)
  printf '%s\n' "$launcher_version" > "${STATE_DIR}/launcher-version.txt"

  step "Purging launcher build dependencies"
  local build_pkgs installed_pkgs=""
  build_pkgs=$(list_packages build)
  # Only purge packages that are still installed. Stage 40 can run again after
  # apt lists were cleared, and apt-get purge fails on an unknown package even
  # when it was already removed.
  for pkg in $build_pkgs; do
    if chroot_run dpkg -s "$pkg" >/dev/null 2>&1; then
      installed_pkgs+=" $pkg"
    fi
  done
  if [[ -n "$installed_pkgs" ]]; then
    # shellcheck disable=SC2086
    chroot_run apt-get purge -y $installed_pkgs 2>&1 | tee -a "$BUILD_LOG" | tail -3
  else
    ok "build dependencies already purged"
  fi
  # Deliberately no autoremove: Qt runtime libraries pulled in as dependencies of
  # the build packages are needed by the compiled launcher, which dpkg cannot
  # know about. The post-purge launcher check below is the guard.

  step "Re-verifying launcher after purge"
  chroot_run /usr/bin/pivista-launcher --version >/dev/null \
    || die "launcher no longer runs after build dependencies were removed"

  step "Cleaning package state and caches"
  chroot_run apt-get clean
  rm -rf "$ROOT_MNT/var/cache/apt/archives/"*.deb
  rm -rf "$ROOT_MNT/var/lib/apt/lists/"*
  rm -rf "$ROOT_MNT/usr/src/pivista-launcher"
  remove_policy_rc
  rm -f "$ROOT_MNT/etc/resolv.conf.pivista"

  step "Hardening defaults"
  # SSH and VNC are optional remote-support features, both disabled until the
  # user enables them in Settings.  The server stays installed so enabling is
  # offline and deterministic; the service is not enabled in the image.  Use
  # the standalone ssh.service rather than socket activation so one toggle
  # controls the listener.  Host keys are generated on the device at first
  # enable, never shipped in the image.
  chroot_run dpkg -s openssh-server >/dev/null 2>&1 \
    || die "openssh-server is missing from the image"
  chroot_run dpkg -s wayvnc >/dev/null 2>&1 \
    || die "wayvnc is missing from the image"
  chroot_run systemctl disable ssh.service ssh.socket pivista-vnc.service >/dev/null 2>&1 || true
  chroot_run systemctl mask ssh.socket >/dev/null 2>&1 || true
  rm -f "$ROOT_MNT"/etc/ssh/ssh_host_*_key "$ROOT_MNT"/etc/ssh/ssh_host_*_key.pub
  install -d -m 0700 -o root -g root "$ROOT_MNT/etc/pivista/remote"

  step "Recording installed package versions"
  # Record after purges so the artifact manifest describes the shipped image,
  # not the temporary build dependencies.
  chroot_run dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' \
    > "${STATE_DIR}/packages-installed.tsv" 2>/dev/null || true
  local pkg_count; pkg_count=$(wc -l < "${STATE_DIR}/packages-installed.tsv")
  ok "recorded ${pkg_count} packages"

  # Journald bounded so the appliance cannot fill its own storage with logs.
  install -d -m 0755 "$ROOT_MNT/etc/systemd/journald.conf.d"
  cat > "$ROOT_MNT/etc/systemd/journald.conf.d/10-pivista.conf" <<'EOF'
[Journal]
SystemMaxUse=96M
SystemMaxFileSize=16M
RuntimeMaxUse=24M
MaxRetentionSec=2week
Compress=yes
EOF

  # Deterministic first-boot identity.
  : > "$ROOT_MNT/etc/machine-id"
  rm -f "$ROOT_MNT/var/lib/dbus/machine-id"
  ln -sf /etc/machine-id "$ROOT_MNT/var/lib/dbus/machine-id"
  rm -f "$ROOT_MNT/var/lib/systemd/random-seed"
  rm -f "$ROOT_MNT/var/lib/systemd/credential.secret"
  rm -f "$ROOT_MNT/root/.bash_history" "$ROOT_MNT/home/${PIVISTA_USER}/.bash_history"
  rm -rf "$ROOT_MNT/tmp/"* "$ROOT_MNT/var/tmp/"*
  : > "$ROOT_MNT/etc/udev/hwdb.bin" 2>/dev/null || true

  install -d -m 0755 "$ROOT_MNT/etc/tmpfiles.d"
  cat > "$ROOT_MNT/etc/tmpfiles.d/pivista.conf" <<'EOF'
d /run/pivista 0750 root pivista -
d /var/lib/pivista 0755 root root -
d /var/log/pivista 0755 root root -
EOF

  cat > "$ROOT_MNT/etc/sysctl.d/90-pivista.conf" <<'EOF'
# Television appliance: keep the UI responsive and the network quiet.
vm.swappiness = 60
kernel.dmesg_restrict = 1
net.ipv4.tcp_fastopen = 3
EOF

  install -d -m 0755 "$ROOT_MNT/etc/logrotate.d"
  cat > "$ROOT_MNT/etc/logrotate.d/pivista" <<'EOF'
/var/log/pivista/*.log {
    weekly
    rotate 3
    compress
    missingok
    notifempty
    create 0640 root root
}
EOF

  step "Writing build provenance"
  cat > "$ROOT_MNT/etc/pivista/build-provenance.txt" <<EOF
product=${PIVISTA_NAME}
version=${PIVISTA_VERSION}
codename=${PIVISTA_CODENAME}
build_id=${PIVISTA_BUILD_ID}
base_image=${BASE_IMAGE_NAME}
base_sha256=${BASE_IMAGE_SHA256}
base_release=${BASE_IMAGE_RELEASE}
base_debian=${BASE_IMAGE_DEBIAN}
base_kernel=${BASE_IMAGE_KERNEL}
architecture=${PIVISTA_ARCH}
launcher=${launcher_version}
built_by=pivista-tv build.sh
EOF
  chmod 0644 "$ROOT_MNT/etc/pivista/build-provenance.txt"

  step "Checking for accidental secrets"
  local secrets
  # Only product-owned paths: the base image legitimately ships the Debian
  # snakeoil TLS key under /etc/ssl/private, which is not a PiVista credential.
  secrets=$(grep -rIlE '(BEGIN [A-Z0-9 ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,})' \
    "$ROOT_MNT/etc/pivista" "$ROOT_MNT/home" "$ROOT_MNT/root" 2>/dev/null || true)
  [[ -z "$secrets" ]] || die "possible credentials found in image: ${secrets}"

  sync
  ok "root filesystem sealed"
  marker_write 40-finalize printf 'build=%s\n' "$PIVISTA_BUILD_ID"
}
