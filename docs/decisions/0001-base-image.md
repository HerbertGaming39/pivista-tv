# ADR 0001 — Build from a pinned Raspberry Pi OS image

- **Status:** accepted
- **Date:** 2026-10-25
- **Deciders:** PiVista TV maintainers

## Context

PiVista TV needs a Pi 5 boot path, vendor kernel/firmware, Mesa/V3D, Chromium
with Widevine, and Qt 6, while remaining buildable by one maintainer on a normal
machine. The realistic foundations were Raspberry Pi OS (via pi-gen or by
modifying a release image), Buildroot, Yocto, or a hand-assembled Debian.

## Decision

Build the product as a **deterministic derivative of one pinned Raspberry Pi OS
Lite arm64 release**. The build verifies the release SHA-256, grows the root
partition, installs a pinned package set in a qemu-aarch64 chroot, overlays the
PiVista system, and validates the sealed image.

## Why

- The vendor already solves Pi 5 firmware, device tree, kernel and bootloader.
- Chromium, Widevine L3, Qt 6, PipeWire and NetworkManager are packaged for this
  exact Debian release; Buildroot/Yocto would require re-solving all of them.
- A single image hash makes the input reproducible and auditable; pi-gen would
  rebuild thousands of packages for a launcher-only change.
- The product layer stays small and reviewable.

## Consequences

- Package versions drift between builds from live apt sources; the resolved set
  is recorded in the artifact manifest. Bit-for-bit reproducibility is not
  claimed.
- Security updates arrive through Debian/Raspberry Pi archives, not a PiVista
  channel. There is no A/B rollback; recovery is reflashing.
- Upstream breakage in a future Raspberry Pi OS release is handled by changing
  the pin deliberately, rebuilding, and recording the reason in this ADR.

## Pin policy

`manifest/base-image.lock` holds the URL, release date, Debian/kernel versions
and SHA-256. The build refuses to proceed on a checksum mismatch. Changing the
pin requires:

1. a successful `./build.sh image` on the new base;
2. an image validation pass and a hardware smoke test (boot, display, audio,
   network, launcher) if hardware is available;
3. an entry appended to this ADR with the old and new hashes and the reason.
