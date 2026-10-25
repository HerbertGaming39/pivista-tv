# PiVista TV

A Linux-based smart TV operating system for the **Raspberry Pi 5 (8 GB)**.
It boots straight into a full-screen, remote-controlled television interface —
no desktop, no display manager, no account requirement.

```
Flash → boot → first-time setup → television
```

---

## What this is

- A purpose-built **Raspberry Pi OS (Debian 13 "trixie", arm64) derivative**
  with a pinned base image, a reproducible overlay pipeline and its own
  product identity.
- A **Qt 6 / QML launcher** designed for a ten-foot interface, with directional
  focus, favourites, search, a first-boot wizard and a full settings app.
- A **narrow privileged service** (`pivistad`) that owns network, audio,
  display, update and power operations. The launcher runs unprivileged.
- A **sway kiosk session** that provides a real global Home key, so a streaming
  window can always be dismissed and the launcher refocused.
- A **build system** that verifies its inputs, assembles the image, produces a
  manifest and checksums, and validates the result.

## What this is not

- **Not Android.** It does not ship an Android runtime and does not require one.
- **Not a Netflix/Disney+ certification.** Protected playback is limited by
  Widevine L3 and the providers' own device policies. See
  [docs/streaming.md](docs/streaming.md); no 1080p claim is made.
- **Not validated on physical hardware by this build host.** The image is
  structurally validated only. See [STATUS.md](STATUS.md).
- **Not a fork of the Linux kernel or Raspberry Pi firmware.** Upstream
  Raspberry Pi OS components are pinned, not patched.

## Supported hardware

| Item | Requirement |
|---|---|
| Board | Raspberry Pi 5, 8 GB recommended (4 GB works) |
| Storage | microSD (A2 recommended) or USB SSD |
| Display | HDMI television or monitor, 1080p target |
| Network | Ethernet or Wi-Fi (2.4/5 GHz) |
| Input | USB/Bluetooth keyboard, remote or game controller; HDMI-CEC untested |
| Power | Official 27 W USB-C supply recommended |

## Current status

Implemented and covered by automated tests:

- Image pipeline (fetch → verify → expand → chroot → overlay → seal → validate)
- Launcher (Qt 6 C++/QML), application discovery, web shortcuts, favourites
- `pivistad` action API with validation and unit tests
- First-boot wizard, settings, search, screensaver, quick panel
- NetworkManager/PipeWire integration code paths
- Image structure validation and package manifest

Not verified, and labelled as such in the product:

- Boot on a physical Raspberry Pi 5 (no hardware attached to the build host)
- Protected playback (Netflix, Disney+, Prime Video, etc.)
- HDMI-CEC remote control
- Hardware HEVC decode inside Chromium
- Android compatibility (not shipped; feasibility documented)

The authoritative, item-by-item status is [STATUS.md](STATUS.md).

## Build

The build needs a **Linux host** (native or WSL2), root, loop devices,
`qemu-aarch64` binfmt emulation, ~12 GB free disk and network access for the
first fetch.

```bash
sudo apt install qemu-user-static binfmt-support xz-utils \
                 e2fsprogs util-linux parted dosfstools rsync python3 git
sudo ./build.sh check        # verifies the host and pinned inputs
sudo ./build.sh build        # assembles the root filesystem
sudo ./build.sh image        # seals, validates, compresses, writes manifest
sudo ./build.sh test         # unit tests + image validation
```

On Windows, run the same commands inside WSL2:

```powershell
wsl -d Ubuntu -u root -- bash /mnt/c/path/to/pivista-tv/build.sh image
```

Outputs land in `releases/`:

```
pivista-tv-0.1.0-pi5-arm64.img.xz
pivista-tv-0.1.0-pi5-arm64.img.xz.sha256
pivista-tv-0.1.0-pi5-arm64.manifest.json
RELEASE-NOTES.md
```

Full details, including resource use and incremental builds, are in
[docs/build.md](docs/build.md).

## Flash

```bash
xz -dc pivista-tv-0.1.0-pi5-arm64.img.xz | \
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Or use Raspberry Pi Imager / balenaEtcher. Do **not** apply Raspberry Pi Imager
customisation settings (hostname/user); PiVista TV creates its own account and
runs its own first-boot setup.

The image keeps Raspberry Pi OS's partition layout: a 512 MB FAT32 boot
partition and an ext4 root partition that grows to fill the card on first boot.

## First boot

1. Insert the card, connect HDMI and power.
2. The wizard asks for language/time zone, network, display mode and interface
   scaling, audio output, remote-control notes, and privacy/update preferences.
   Every step can be skipped; the UI works offline.
3. The home screen appears. Use arrows, Enter, Escape/Back and Home.

Settings can be reopened at any time from the top bar. The wizard can be run
again from **Settings → Privacy and security → Run first-time setup**.

## Remote control

| Key | Action |
|---|---|
| Arrows | Move focus |
| Enter / OK | Select |
| Escape / Back | Back; from a top-level screen returns Home |
| Home | Return to launcher from any app (global, handled by sway) |
| Volume keys | PipeWire volume (global) |
| F10 / Menu | Quick settings |
| Ctrl+Alt+F2 | Text console (recovery) |
| Ctrl+Alt+F1 | Back to the TV UI |

USB and Bluetooth keyboards/remotes that emit standard key codes work without
configuration. Unusual IR remotes can be mapped in `/etc/pivista/input.map`.
HDMI-CEC is **not verified** on Pi 5; do not assume the TV remote will work
without a USB/Bluetooth receiver.

## Streaming, honestly

All streaming entries are shortcuts to the services' own websites, opened in a
dedicated Chromium profile. Chromium on 64-bit Raspberry Pi OS can load the
`libwidevinecdm0` Widevine CDM at **L3 (software)**. Netflix/Disney+ may play,
at resolutions the provider chooses; **720p is the realistic expectation and
1080p is not verified**. The Pi 5 has a hardware HEVC decoder but **no H.264
hardware decoder**, and stock Chromium's use of the Pi 5 HEVC path is not
established.

See [docs/streaming.md](docs/streaming.md) for the full matrix and test
protocol. The product never reports an app as verified just because it launched.

## Android applications

Not included. Waydroid on Pi 5 is treated as an **experimental community
configuration**, and generic Android does not obtain Widevine L1 or Play
certification. `pivistad` exposes an honest diagnostic (`android.status`) and
the launcher shows the reasons in Settings. See [docs/android.md](docs/android.md).

## Updates and recovery

Updates use Debian packages from the sources baked into the image. There is no
A/B partition scheme and **no automatic rollback**. A failed update is recovered
by reflashing a known-good image. The procedure is in
[docs/recovery.md](docs/recovery.md).

## Repository layout

```
build.sh                  primary entry point
build/                    pipeline stages, helpers, logs
config/product.env        product identity and image geometry
manifest/                 pinned base image, package set, image config
system/rootfs/            files installed into the image
system/branding/          templated branding
launcher/                 Qt 6 C++ launcher and QML interface
daemon/                   pivistad privileged control service
applications/web/         curated web application catalog
tests/                    unit, image and launcher tests
docs/                     architecture, streaming, build, security, recovery
releases/                 generated images and manifests (not source)
```

## Licence

PiVista TV source is **GPL-3.0-or-later** (see [LICENSE](LICENSE)); Qt 6 is used
under the GPL option. The base image contains software under many licences;
every package's notices remain in `/usr/share/doc` on the device. PiVista TV is
an independent project and is not affiliated with or endorsed by Raspberry Pi
Ltd, Netflix, Disney, Google or any streaming provider.
