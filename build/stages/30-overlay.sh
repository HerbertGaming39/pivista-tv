# Stage 30 — install the PiVista system overlay, account, branding and catalog.
stage_30_overlay() {
  image_is_mounted || die "image is not mounted; run stage 10 first"

  step "Installing system overlay"
  rsync -a --chown=root:root "${PROJECT_DIR}/system/rootfs/" "$ROOT_MNT/"
  chmod 0755 "$ROOT_MNT/usr/lib/pivista/session.sh" \
              "$ROOT_MNT/usr/lib/pivista/firstboot.sh" \
              "$ROOT_MNT/usr/lib/pivista/input-setup.sh" \
              "$ROOT_MNT/usr/lib/pivista/launcher-loop.sh" \
              "$ROOT_MNT/usr/lib/pivista/home.sh"
  chmod 0644 "$ROOT_MNT/etc/pam.d/pivista" \
              "$ROOT_MNT/etc/pivista/session.conf" \
              "$ROOT_MNT/etc/pivista/input.map" \
              "$ROOT_MNT/etc/pivista/sway/config" \
              "$ROOT_MNT/etc/systemd/system/pivista-session.service" \
              "$ROOT_MNT/etc/systemd/system/pivista-daemon.service" \
              "$ROOT_MNT/etc/systemd/logind.conf.d/10-pivista.conf"
  ok "system files installed"

  step "Installing documentation and licences"
  install -d -m 0755 "$ROOT_MNT/usr/share/doc/pivista"
  install -m 0644 "${PROJECT_DIR}/README.md" "$ROOT_MNT/usr/share/doc/pivista/README.md" 2>/dev/null || true
  rsync -a --chown=root:root "${PROJECT_DIR}/docs/" "$ROOT_MNT/usr/share/doc/pivista/"

  step "Installing launcher QML and assets"
  install -d -m 0755 "$ROOT_MNT${PIVISTA_PREFIX}/qml"
  rsync -a --delete --chown=root:root "${PROJECT_DIR}/launcher/qml/" "$ROOT_MNT${PIVISTA_PREFIX}/qml/"
  if [[ -d "${PROJECT_DIR}/launcher/assets" ]]; then
    install -d -m 0755 "$ROOT_MNT${PIVISTA_PREFIX}/assets"
    rsync -a --delete --chown=root:root "${PROJECT_DIR}/launcher/assets/" "$ROOT_MNT${PIVISTA_PREFIX}/assets/"
  fi

  step "Installing web application catalog"
  install -d -m 0755 "$ROOT_MNT${PIVISTA_PREFIX}/webapps"
  rsync -a --delete --chown=root:root "${PROJECT_DIR}/applications/web/" "$ROOT_MNT${PIVISTA_PREFIX}/webapps/"

  step "Installing daemon"
  install -d -m 0755 "$ROOT_MNT/usr/lib/pivista"
  install -m 0755 "${PROJECT_DIR}/daemon/pivistad.py" "$ROOT_MNT${PIVISTA_DAEMON}"

  step "Rendering product configuration"
  install -d -m 0755 "$ROOT_MNT${PIVISTA_CONFIG}" "$ROOT_MNT${PIVISTA_STATE}"
  render_template "${PROJECT_DIR}/system/branding/product.env.in" "$ROOT_MNT${PIVISTA_CONFIG}/product.env"
  chmod 0644 "$ROOT_MNT${PIVISTA_CONFIG}/product.env"

  python3 - "$ROOT_MNT" <<'PY'
import datetime, json, os, sys
root = sys.argv[1]
info = {
    "product": os.environ["PIVISTA_NAME"],
    "slug": os.environ["PIVISTA_SLUG"],
    "version": os.environ["PIVISTA_VERSION"],
    "codename": os.environ["PIVISTA_CODENAME"],
    "vendor": os.environ["PIVISTA_VENDOR"],
    "build_id": os.environ["PIVISTA_BUILD_ID"],
    "architecture": os.environ["PIVISTA_ARCH"],
    "model": os.environ["PIVISTA_MODEL"],
}
path = os.path.join(root, "etc/pivista/build-info.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(info, fh, indent=2, sort_keys=True)
    fh.write("\n")
os.chmod(path, 0o644)
PY

  step "Creating the ${PIVISTA_USER} account"
  for extra_group in video render input audio plugdev netdev; do
    chroot_run groupadd --force "$extra_group" 2>/dev/null || true
  done
  if chroot_run id -u "${PIVISTA_USER}" >/dev/null 2>&1; then
    ok "account already exists"
  else
    # The stock Raspberry Pi OS image ships user/group `pi` at UID/GID 1000.
    # Remove it before claiming 1000 for the product; otherwise groupadd fails.
    if chroot_run id -u pi >/dev/null 2>&1; then
      chroot_run userdel pi 2>/dev/null || true
    fi
    if chroot_run getent group pi >/dev/null 2>&1; then
      chroot_run groupdel pi 2>/dev/null || true
    fi
    rm -rf "$ROOT_MNT/home/pi"

    local occupied
    occupied=$(chroot_run getent group "${PIVISTA_GID}" 2>/dev/null | cut -d: -f1 || true)
    [[ -z "$occupied" ]] \
      || die "GID ${PIVISTA_GID} is already used by group '${occupied}'"
    chroot_run groupadd --gid "${PIVISTA_GID}" "${PIVISTA_GROUP}" \
      || die "could not create group ${PIVISTA_GROUP} with GID ${PIVISTA_GID}"
    chroot_run useradd --create-home --uid "${PIVISTA_UID}" --gid "${PIVISTA_GID}" \
      --groups video,render,input,audio,plugdev,netdev --shell /bin/bash \
      --comment "PiVista TV session" "${PIVISTA_USER}"
    chroot_run passwd --lock "${PIVISTA_USER}" >/dev/null
    ok "created ${PIVISTA_USER} (uid ${PIVISTA_UID})"
  fi

  # install(1) resolves users against the *host*, so create the directories and
  # apply numeric ownership afterwards.
  install -d -m 0750 "$ROOT_MNT${PIVISTA_HOME}" \
    "$ROOT_MNT${PIVISTA_HOME}/.config" \
    "$ROOT_MNT${PIVISTA_HOME}/.local/share" \
    "$ROOT_MNT${PIVISTA_HOME}/.cache"
  chown -R "${PIVISTA_UID}:${PIVISTA_GID}" "$ROOT_MNT${PIVISTA_HOME}"
  install -d -m 0755 "$ROOT_MNT${PIVISTA_RUNTIME}"
  chown 0:"${PIVISTA_GID}" "$ROOT_MNT${PIVISTA_RUNTIME}"
  install -d -m 0755 -o root -g root "$ROOT_MNT${PIVISTA_STATE}" "$ROOT_MNT/var/log/pivista"

  step "Enabling system units"
  enable_unit "$ROOT_MNT" pivista-daemon.service multi-user.target
  enable_unit "$ROOT_MNT" pivista-session.service graphical.target
  enable_unit "$ROOT_MNT" pivista-firstboot.service multi-user.target
  enable_unit "$ROOT_MNT" pivista-input.service multi-user.target
  # systemctl cannot talk to a running manager inside the chroot; set the
  # default target the way systemctl does, by symlink.
  ln -sf /lib/systemd/system/graphical.target "$ROOT_MNT/etc/systemd/system/default.target"
  rm -f "$ROOT_MNT/etc/systemd/system/getty@tty1.service"
  ln -sf /dev/null "$ROOT_MNT/etc/systemd/system/getty@tty1.service"

  step "Applying boot configuration"
  python3 - "$BOOT_MNT" <<'PY'
import os, sys
root = sys.argv[1]
cmdline = os.path.join(root, "cmdline.txt")
with open(cmdline, encoding="utf-8") as fh:
    line = fh.read().strip()
tokens = line.split()
for extra in ("quiet", "loglevel=3", "vt.global_cursor_default=0"):
    if not any(t == extra or t.startswith(extra.split("=")[0] + "=") for t in tokens):
        tokens.append(extra)
tmp = cmdline + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write(" ".join(tokens) + "\n")
os.replace(tmp, cmdline)
PY
  ok "kernel command line updated"

  marker_write 30-overlay printf 'qml_digest=%s\n' "$(hash_tree launcher/qml applications/web)"
}

# enable_unit <root> <unit> <target>
enable_unit() {
  local root=$1 unit=$2 target=$3
  local source="/lib/systemd/system/$unit"
  if [[ -f "$root/etc/systemd/system/$unit" ]]; then
    source="/etc/systemd/system/$unit"
  elif [[ ! -f "$root/lib/systemd/system/$unit" ]]; then
    warn "unit $unit not found; not enabled"
    return 0
  fi
  mkdir -p "$root/etc/systemd/system/${target}.wants"
  ln -sf "$source" "$root/etc/systemd/system/${target}.wants/$unit"
}
