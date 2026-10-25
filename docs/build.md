# Building PiVista TV

## Host requirements

| Requirement | Detail |
|---|---|
| OS | Linux x86_64 or aarch64 (WSL2 works; tested on Ubuntu 26.04 under WSL2) |
| Privileges | root for loop mounts and chroot |
| Emulation | `qemu-aarch64` registered in binfmt_misc (Debian: `qemu-user-static`, `binfmt-support`) |
| Tools | `curl xz sha256sum losetup sfdisk parted mount mkfs.ext4 e2fsck resize2fs debugfs rsync python3 git` |
| Disk | 12 GB free in the work directory at minimum; ~18 GB peak with release artifacts |
| RAM | 4 GB is enough; the launcher is compiled with `-j2` by default |
| Network | first build downloads a 525 MB base image |

`./build.sh check` verifies all of the above and prints a clear error for
anything missing.

## Commands

| Command | Effect |
|---|---|
| `./build.sh check` | Host, tools, loop devices, binfmt, disk space, base-image checksum |
| `./build.sh build` | Stages 10–40: base, packages, launcher, overlay, finalize |
| `./build.sh image` | Seal + validate + compress + manifest an assembled root filesystem; runs `build` first if none is marked complete |
| `./build.sh test` | Daemon unit tests, launcher tests (if a host Qt 6 is present), image validation |
| `./build.sh clean` | Removes the work directory (keeps downloads) |
| `./build.sh clean --all` | Also removes release artifacts |
| `./build.sh stage 25-launcher` | Runs a single stage (advanced) |

## Pipeline stages

| Stage | Work | Cache marker |
|---|---|---|
| `10-base` | Download + SHA-256 verify the pinned image, decompress, grow partition 2, `resize2fs`, loop-mount, bind `/dev /proc /sys` | `state/10-base.done` |
| `20-packages` | `apt-get update`, install `[runtime]`, install `[build]` dependencies, record versions | keyed by hash of `packages.lock` |
| `25-launcher` | Copy C++/QML sources into the chroot, CMake build for arm64, install `/usr/bin/pivista-launcher`, run `--version` | keyed by hash of `launcher/` |
| `30-overlay` | Install `system/rootfs`, QML, web catalog, daemon, branding, account, units, boot cmdline, docs; disable cloud-init and remove its seed; mask SSH host-key regeneration | `state/30-overlay.done` |
| `40-finalize` | Purge build deps with a post-purge launcher check, clean apt, reset machine-id, harden journald/logind, scan for credentials | `state/40-finalize.done` |
| `50-image` | Unmount, `e2fsck -fn`, record size | — |
| `60-validate` | `tests/image/validate_image.py` mounts read-only and checks the image | — |
| `70-release` | `xz -T0 -6`, SHA-256, artifact manifest, release notes | — |

Intermediate artifacts live in `/var/tmp/pivista-build` by default. Set
`PIVISTA_WORK_DIR=/path` to relocate. An assembled work image whose stage-10
marker matches the pinned base is reused automatically; set
`PIVISTA_REUSE_ROOTFS=0` to force a clean rebuild. `PIVISTA_FORCE_BUILD=1` makes
`image` run the build stages instead of sealing the existing rootfs,
`PIVISTA_FORCE_LAUNCHER=1` forces a launcher rebuild, and `PIVISTA_JOBS=N`
controls qemu-user parallelism.

## Incremental behaviour

- The 525 MB download is cached and re-verified on every build.
- Package installation is skipped only when `packages.lock` is unchanged.
- The launcher is recompiled only when `launcher/src`, `launcher/qml`,
  `launcher/assets` or `CMakeLists.txt` change. QML-only changes rebuild the
  overlay; CMake still re-links the binary because QML is part of its digest.
- Stage 40 purges the build toolchain. If a later source change needs a launcher
  rebuild, stage 25 restores the build packages first; this is why an incremental
  build after a finalized image still works.
- `image` reuses a root filesystem with a completed `40-finalize` marker. Run
  `./build.sh build` after editing system files, or set `PIVISTA_FORCE_BUILD=1`.
- On the reference WSL2 host, a no-op `build` (reuse + overlay + finalize) took
  4 seconds; validation took under a minute; xz compression dominates a release
  build and depends on the CPU.

## Reproducibility

What is controlled:

- the exact base image by SHA-256 (`manifest/base-image.lock`);
- the exact package *set* (`manifest/packages.lock`);
- all PiVista source in this repository;
- deterministic configuration files, empty `machine-id`, no timestamps inside
  the overlay.

What is not controlled:

- Debian/Raspberry Pi package versions drift between builds because the apt
  sources are live. The resolved versions are recorded in the artifact
  manifest, so a build is *identifiable* but not bit-identical.
- ext4 allocation and file timestamps inside the base image.
- compression output may differ across xz versions.

The project therefore claims **reproducible inputs and configuration**, not
bit-for-bit images. Two builds were not compared byte-for-byte; no such claim is
made.

## Adding a package or changing the product

1. Edit `manifest/packages.lock` (add to `[runtime]`) or
   `config/product.env` (name/version/geometry).
2. Run `./build.sh check` then `./build.sh image`.
3. The manifest, checksum and release notes are regenerated automatically.

Changing the product name in `config/product.env` updates the image filename,
`/etc/pivista/product.env`, build provenance and the installer documentation.
The launcher's visible wordmark is in `launcher/qml/Main.qml`; the wizard's is in
`launcher/qml/WizardScreen.qml`. Both are plain QML text and do not require C++
changes.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `qemu-aarch64 binfmt is not registered` | Install `qemu-user-static` + `binfmt-support`, or `docker run --privileged --rm tonistiigi/binfmt --install arm64` |
| `losetup: failed to set up loop device` | No loop devices in the environment (some containers). Use a VM/WSL2 or `--privileged`. |
| `launcher binary is not executable in the image` | Qt ABI mismatch or missing runtime package; inspect the chroot with `chroot` and `ldd` |
| `image validation failed` | Read the failing check; the validator prints each check with its detail |
| Build killed during `25-launcher` | qemu-user memory pressure; lower `PIVISTA_JOBS` to 1 |
