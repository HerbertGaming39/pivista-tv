#!/usr/bin/env bash
# PiVista TV build entry point.
#
# Usage:
#   ./build.sh check          Verify the build host and pinned inputs
#   ./build.sh build          Assemble the root filesystem (all stages)
#   ./build.sh image          Build, seal the image and validate it
#   ./build.sh test           Run unit tests and validate an existing image
#   ./build.sh clean          Remove build work directories (keeps downloads)
#   ./build.sh clean --all    Also remove downloaded base images and artifacts
#   ./build.sh help           Show this help
#
# The build must run as root on a Linux host with loop devices, ext4 tools,
# e2fsprogs, util-linux, xz and qemu-aarch64 binfmt emulation registered.
# See docs/build.md for the full prerequisite list.

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR

# shellcheck source=build/lib/common.sh
source "${PROJECT_DIR}/build/lib/common.sh"

usage() {
  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    help|-h|--help) usage ;;
    check)          load_config; cmd_check ;;
    build)          load_config; cmd_build "$@" ;;
    image)          load_config; cmd_image "$@" ;;
    test)           load_config; cmd_test "$@" ;;
    clean)          load_config; cmd_clean "$@" ;;
    stage)          load_config; run_stage "$1" ;;
    *)              die "unknown command: ${cmd} (try ./build.sh help)" ;;
  esac
}

main "$@"
