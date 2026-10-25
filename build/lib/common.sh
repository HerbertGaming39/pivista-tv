# Shared build helpers for PiVista TV.
# Sourced by build.sh; not executable on its own.

set -Eeuo pipefail

PIVISTA_BUILD_ID="${PIVISTA_BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
else
  C_RESET=""; C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""
fi

log()  { printf '%s[pivista]%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()   { printf '%s[pivista]%s %s\n' "$C_OK" "$C_RESET" "$*"; }
warn() { printf '%s[pivista]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
die()  { printf '%s[pivista]%s error: %s\n' "$C_ERR" "$C_RESET" "$*" >&2; exit 1; }

step() {
  printf '\n%s==> %s%s\n' "$C_INFO" "$*" "$C_RESET"
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
load_config() {
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/config/product.env"
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/manifest/base-image.lock"

  : "${PIVISTA_WORKDIR_DEFAULT:=/var/tmp/pivista-build}"
  WORK_DIR="${PIVISTA_WORK_DIR:-$PIVISTA_WORKDIR_DEFAULT}"
  DOWNLOAD_DIR="${WORK_DIR}/downloads"
  ROOT_MNT="${WORK_DIR}/mnt/root"
  BOOT_MNT="${WORK_DIR}/mnt/boot"
  WORK_IMG="${WORK_DIR}/work.img"
  STATE_DIR="${WORK_DIR}/state"
  LOG_DIR="${PROJECT_DIR}/build/logs"
  RELEASE_DIR="${PROJECT_DIR}/releases"
  ARTIFACT_MANIFEST="${RELEASE_DIR}/${PIVISTA_SLUG}-${PIVISTA_VERSION}-pi5-arm64.manifest.json"
  PIVISTA_JOBS="${PIVISTA_JOBS:-$PIVISTA_JOBS_DEFAULT}"

  mkdir -p "$WORK_DIR" "$DOWNLOAD_DIR" "$ROOT_MNT" "$BOOT_MNT" "$STATE_DIR" "$LOG_DIR" "$RELEASE_DIR"
  BUILD_LOG="${LOG_DIR}/build-${PIVISTA_BUILD_ID}.log"
  touch "$BUILD_LOG"
  export PIVISTA_NAME PIVISTA_SLUG PIVISTA_VERSION PIVISTA_CODENAME PIVISTA_VENDOR
  export PIVISTA_USER PIVISTA_GROUP PIVISTA_HOME PIVISTA_UID PIVISTA_GID
  export PIVISTA_PREFIX PIVISTA_LAUNCHER PIVISTA_DAEMON PIVISTA_CONFIG PIVISTA_STATE PIVISTA_RUNTIME
  export PIVISTA_MODEL PIVISTA_SOC PIVISTA_ARCH PIVISTA_BUILD_ID
}

# Run a command and append both streams to the build log while showing output.
run_logged() {
  "$@" 2>&1 | tee -a "$BUILD_LOG"
  return "${PIPESTATUS[0]}"
}

# ---------------------------------------------------------------------------
# Host checks
# ---------------------------------------------------------------------------
need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "the image build must run as root (loop mounts and chroot are required)"
}

need_cmd() {
  local missing=()
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  ((${#missing[@]} == 0)) || die "missing build tools: ${missing[*]}"
}

check_binfmt() {
  local f=/proc/sys/fs/binfmt_misc/qemu-aarch64
  [[ -f "$f" ]] || return 1
  grep -q '^enabled$' "$f" || return 1
  local interp
  interp=$(awk '/^interpreter/ {print $2}' "$f")
  [[ -x "$interp" ]] || return 1
}

check_loop() {
  [[ -c /dev/loop-control ]] || return 1
  losetup -f >/dev/null 2>&1
}

check_space() {
  local need_gb=$1
  local avail_gb
  avail_gb=$(df -BG --output=avail "$WORK_DIR" | tail -1 | tr -dc '0-9')
  (( avail_gb >= need_gb )) || die "need at least ${need_gb} GB free in ${WORK_DIR}, found ${avail_gb} GB"
}

cmd_check() {
  need_root
  step "Build host"
  log "kernel: $(uname -r)  arch: $(uname -m)  cpus: $(nproc)"
  log "work dir: ${WORK_DIR}"
  log "project: ${PIVISTA_NAME} ${PIVISTA_VERSION} (${PIVISTA_CODENAME})"

  step "Required tools"
  need_cmd curl xz sha256sum losetup sfdisk parted mount umount chroot \
           mkfs.ext4 e2fsck resize2fs debugfs rsync tee awk sed truncate \
           tar gzip python3 git
  ok "all required host tools present"

  step "Loop devices"
  check_loop && ok "loop devices available" || die "loop devices are not available"
  step "ARM64 emulation"
  check_binfmt && ok "qemu-aarch64 binfmt registered" \
    || die "qemu-aarch64 binfmt is not registered (install qemu-user-static + binfmt-support)"

  step "Disk space"
  check_space 12
  ok "at least 12 GB available in ${WORK_DIR}"

  step "Pinned base image"
  verify_base_image_downloaded && ok "base image checksum matches ${BASE_IMAGE_SHA256}" \
    || warn "base image not downloaded yet (run ./build.sh build)"

  step "Result"
  ok "build host is ready"
}

# ---------------------------------------------------------------------------
# Base image handling
# ---------------------------------------------------------------------------
base_archive() { printf '%s/%s' "$DOWNLOAD_DIR" "$BASE_IMAGE_FILE"; }

verify_base_image_downloaded() {
  local f; f=$(base_archive)
  [[ -f "$f" ]] || return 1
  printf '%s  %s\n' "$BASE_IMAGE_SHA256" "$f" | sha256sum -c --status -
}

fetch_base_image() {
  local archive; archive=$(base_archive)
  if verify_base_image_downloaded; then
    ok "base image already present and verified"
    return 0
  fi
  rm -f "$archive" "$archive.part"
  step "Downloading ${BASE_IMAGE_NAME}"
  curl --fail --location --retry 3 --retry-delay 5 --progress-bar \
       -o "$archive.part" "$BASE_IMAGE_URL"
  mv "$archive.part" "$archive"
  verify_base_image_downloaded || die "base image checksum verification failed"
  ok "base image verified (${BASE_IMAGE_SHA256})"
}

# ---------------------------------------------------------------------------
# Loop image helpers
# ---------------------------------------------------------------------------
LOOP_DEV=""

image_is_mounted() {
  mountpoint -q "$ROOT_MNT"
}

mount_image() {
  [[ -f "$WORK_IMG" ]] || die "work image missing: $WORK_IMG"
  image_is_mounted && return 0
  LOOP_DEV=$(losetup --find --partscan --show "$WORK_IMG")
  printf '%s\n' "$LOOP_DEV" > "${WORK_DIR}/loopdev"
  mount "${LOOP_DEV}p2" "$ROOT_MNT"
  mount "${LOOP_DEV}p1" "$BOOT_MNT"
  mkdir -p "$ROOT_MNT/dev/pts" "$ROOT_MNT/proc" "$ROOT_MNT/sys" "$ROOT_MNT/run"
  mount --bind /dev "$ROOT_MNT/dev"
  mount --bind /dev/pts "$ROOT_MNT/dev/pts"
  mount --bind /proc "$ROOT_MNT/proc"
  mount --bind /sys "$ROOT_MNT/sys"
  cp -L /etc/resolv.conf "$ROOT_MNT/etc/resolv.conf.pivista" 2>/dev/null || true
  cp -L /etc/resolv.conf "$ROOT_MNT/etc/resolv.conf" 2>/dev/null || true
  ok "mounted ${LOOP_DEV} at ${ROOT_MNT}"
}

unmount_image() {
  if image_is_mounted; then
    for m in "$ROOT_MNT/dev/pts" "$ROOT_MNT/dev" "$ROOT_MNT/proc" "$ROOT_MNT/sys"; do
      mountpoint -q "$m" && umount "$m" || true
    done
    umount "$BOOT_MNT" 2>/dev/null || true
    umount "$ROOT_MNT" 2>/dev/null || true
    ok "unmounted image"
  fi
  if [[ -f "${WORK_DIR}/loopdev" ]]; then
    local dev; dev=$(cat "${WORK_DIR}/loopdev")
    if [[ -n "$dev" ]] && losetup "$dev" >/dev/null 2>&1; then
      losetup -d "$dev" || true
    fi
    rm -f "${WORK_DIR}/loopdev"
  fi
  LOOP_DEV=""
}

cleanup_on_exit() {
  local rc=$?
  unmount_image || true
  if (( rc != 0 )); then
    warn "build failed (exit ${rc}); log: ${BUILD_LOG}"
  fi
  exit $rc
}

# ---------------------------------------------------------------------------
# Chroot helpers
# ---------------------------------------------------------------------------
CHROOT_ENV=(HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 LANG=C.UTF-8)

chroot_run() {
  env -i "${CHROOT_ENV[@]}" chroot "$ROOT_MNT" "$@"
}

install_policy_rc() {
  cat > "$ROOT_MNT/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
# Prevent services from starting inside the image-build chroot.
exit 101
EOF
  chmod +x "$ROOT_MNT/usr/sbin/policy-rc.d"
}

remove_policy_rc() {
  rm -f "$ROOT_MNT/usr/sbin/policy-rc.d"
}

# list_packages <section> — print package names from manifest/packages.lock
list_packages() {
  awk -v want="$1" '
    /^\[/ { sect = $0; gsub(/[\[\]]/, "", sect); next }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    sect == want { gsub(/[[:space:]]/, "", $0); print }
  ' "${PROJECT_DIR}/manifest/packages.lock"
}

# ---------------------------------------------------------------------------
# State markers
# ---------------------------------------------------------------------------
marker_path() { printf '%s/%s.done' "$STATE_DIR" "$1"; }
marker_done() { [[ -f "$(marker_path "$1")" ]]; }

marker_write() {
  local name=$1
  shift
  { printf 'build=%s\ntime=%s\n' "$PIVISTA_BUILD_ID" "$(date -u +%FT%TZ)"; "$@" 2>/dev/null || true; } \
    > "$(marker_path "$name")"
}

hash_tree() {
  ( cd "$PROJECT_DIR" \
      && { find "$@" -type f -print0 2>/dev/null || true; } \
      | sort -z | xargs -0 -r sha256sum ) | sha256sum | cut -d' ' -f1
}

# Render @PLACEHOLDER@ tokens in a file from the environment.
render_template() {
  local src=$1 dst=$2
  local tmp; tmp=$(mktemp)
  cp "$src" "$tmp"
  python3 - "$tmp" <<'PY'
import os, re, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    text = fh.read()
def sub(m):
    key = m.group(1)
    return os.environ.get(key, m.group(0))
text = re.sub(r'@([A-Z0-9_]+)@', sub, text)
with open(path, 'w', encoding='utf-8') as fh:
    fh.write(text)
PY
  install -D -m 0644 "$tmp" "$dst"
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Stage runner
# ---------------------------------------------------------------------------
STAGES=(10-base 20-packages 25-launcher 30-overlay 40-finalize)

run_stage() {
  local stage=$1 script="${PROJECT_DIR}/build/stages/$1.sh"
  [[ -f "$script" ]] || die "unknown stage: $stage"
  step "Stage ${stage}"
  # shellcheck disable=SC1090
  source "$script"
  "stage_${stage//-/_}"
}

cmd_build() {
  need_root
  check_loop || die "loop devices are not available"
  trap cleanup_on_exit EXIT INT TERM
  local start; start=$(date +%s)
  mkdir -p "$LOG_DIR"
  log "build ${PIVISTA_BUILD_ID} — ${PIVISTA_NAME} ${PIVISTA_VERSION}"

  for stage in "${STAGES[@]}"; do
    run_stage "$stage"
  done

  local elapsed=$(( $(date +%s) - start ))
  ok "root filesystem assembled in $((elapsed / 60))m $((elapsed % 60))s"
  ok "next: ./build.sh image"
}

cmd_image() {
  need_root
  trap cleanup_on_exit EXIT INT TERM
  # Seal the root filesystem that `build` already produced instead of rebuilding
  # packages and the launcher. Source changes are applied by running
  # `./build.sh build` first (or by setting PIVISTA_FORCE_BUILD=1).
  if marker_done 40-finalize && [[ -f "$WORK_IMG" ]] && [[ "${PIVISTA_FORCE_BUILD:-0}" != "1" ]]; then
    # Keep release metadata consistent with the build actually sealed in the
    # image, not with the timestamp of this sealing invocation.
    local sealed_build
    sealed_build=$(sed -n 's/^build=//p' "$(marker_path 40-finalize)" | head -1)
    if [[ -n "$sealed_build" ]]; then
      PIVISTA_BUILD_ID="$sealed_build"
      export PIVISTA_BUILD_ID
    fi
    ok "using assembled root filesystem (build ${PIVISTA_BUILD_ID}); run ./build.sh build to apply source changes"
  else
    cmd_build
    trap cleanup_on_exit EXIT INT TERM
  fi
  run_stage 50-image
  run_stage 60-validate
  run_stage 70-release
  trap - EXIT INT TERM
}

cmd_test() {
  local rc=0
  step "Host-side unit tests"
  if [[ -d "${PROJECT_DIR}/tests/unit" ]]; then
    ( cd "$PROJECT_DIR" && python3 -m unittest discover -s tests/unit -v ) || rc=1
  fi
  if [[ -x "${PROJECT_DIR}/tests/run-launcher-tests.sh" ]]; then
    "${PROJECT_DIR}/tests/run-launcher-tests.sh" || rc=1
  fi
  if [[ -f "${WORK_IMG}" ]]; then
    step "Image validation"
    "${PROJECT_DIR}/tests/image/validate_image.py" --image "${WORK_IMG}" || rc=1
  else
    warn "no built image at ${WORK_IMG}; skipping image validation"
  fi
  (( rc == 0 )) && ok "tests passed" || die "tests failed"
}

cmd_clean() {
  local all=0
  [[ "${1:-}" == "--all" ]] && all=1
  unmount_image || true
  rm -rf "$WORK_DIR"
  ok "removed ${WORK_DIR}"
  if (( all )); then
    rm -rf "$RELEASE_DIR"/*.img "$RELEASE_DIR"/*.img.xz "$RELEASE_DIR"/*.manifest.json
    ok "removed release artifacts"
  fi
  rm -rf "${PROJECT_DIR}/launcher/build"
  ok "clean complete"
}
