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
- A **Qt 6 / QML launcher** designed for a ten-foot interface, with an
  Android-TV-style home banner, horizontal app/media rows, app details,
  favourites, recently opened apps, search, a first-boot wizard and a full
  settings app.
- A **narrow privileged service** (`pivistad`) that owns network, audio,
  display, update and power operations. The launcher runs unprivileged.
- A **signed launcher update channel** with Ed25519 manifest verification,
  SHA-256 archive checks, a staged swap and a rollback copy. OS images and apt
  packages remain separate paths.
- A **sway kiosk session** that provides a real global Home key, so a streaming
  window can always be dismissed and the launcher refocused.
- A **build system** that verifies its inputs, assembles the image, produces a
  manifest and checksums, and validates the result.

## What this is not

- **Not Android.** It does not ship an Android runtime and does not require one.
- **Not a Netflix/Disney+ certification.** Protected playback is limited by
  Widevine L3 and the providers' own device policies. See
  [docs/streaming.md](docs/streaming.md); no 1080p claim is made.
- **Not validated on physical hardware for this release.** The image is
  structurally validated and its sealed launcher is rendered under qemu-user;
  the physical Pi was unreachable during the 0.3.1 build. See
  [STATUS.md](STATUS.md).
- **Not a fork of the Linux kernel or Raspberry Pi firmware.** Upstream
  Raspberry Pi OS components are pinned, not patched.

## The 0.3 interface

- **Home** is a television home screen: a large featured banner, a favourites
  row, a streaming row, recently opened applications and installed native apps.
  The banner uses the selected entry's own colour and initials; it does not copy
  provider logos or artwork.
- **Apps** lists installed Linux applications and web shortcuts with a clear
  **INSTALLED APPLICATION** / **WEB SHORTCUT** distinction, category filters and
  a details sheet (open, favourite, hide, launch errors).
- **Games** is the same library filtered to the `Game` category, with an honest
  empty state when nothing is installed.
- **Media** collects streaming shortcuts and installed media applications. It
  labels launch history as **Recently opened**; it does not pretend to know a
  playback position without a real player/provider integration.
- **Settings** is a full TV settings app. Appearance offers theme, wallpaper,
  home-row visibility, start screen and 12/24-hour clock; changes persist in
  `~/.config/PiVista/Launcher.conf`.
- **Focus** is designed for a remote: directional movement across the header and
  rows, Enter/OK, Escape/Back and a global Home key. Focus rings are visible at
  720p, 1080p and 4K.

The interface is original work. It is inspired by the usability of modern TV
operating systems but uses no Google/Android branding or proprietary assets.

## Supported hardware

| Item | Requirement |
|---|---|
| Board | Raspberry Pi 5, 8 GB recommended (4 GB works) |
| Storage | microSD (A2 recommended) or USB SSD |
| Display | HDMI television or monitor, 1080p target |
| Network | Ethernet or Wi-Fi (2.4/5 GHz) |
| Input | USB keyboard, USB/IR remote or game controller; Bluetooth input needs pairing (no pairing UI yet); HDMI-CEC untested |
| Power | Official 27 W USB-C supply recommended |

## Current status

Implemented and covered by automated tests:

- Image pipeline (fetch → verify → expand → chroot → overlay → seal → validate)
- Launcher (Qt 6 C++/QML): featured home banner, Home/Apps/Games/Media/Search/
  Settings sections, application discovery, web shortcuts, favourites, app
  details, recently opened apps and appearance settings
- `pivistad` action API with validation and unit tests
- First-boot wizard, settings, search, screensaver, quick panel
- Signed launcher update client and Settings UI: release discovery,
  Ed25519 manifest verification, SHA-256 archive verification, atomic install,
  rollback and recovery state
- NetworkManager/PipeWire integration code paths
- Image structure validation and package manifest

Automated tests in this build: **69 host Python tests, 8 launcher/Qt cases, 29
offscreen screen renders and 51 image checks**. The image is structurally
validated, its sealed launcher was rendered under qemu-user, and it is not
booted on a Pi.

Not verified, and labelled as such in the product:

- Boot on a physical Raspberry Pi 5 (the Pi was unreachable during this build)
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
pivista-tv-0.3.1-pi5-arm64.img.xz
pivista-tv-0.3.1-pi5-arm64.img.xz.sha256
pivista-tv-0.3.1-pi5-arm64.manifest.json
RELEASE-NOTES.md
```

Full details, including resource use and incremental builds, are in
[docs/build.md](docs/build.md).

## Hardware test release

This is the image to test on a physical Raspberry Pi 5. The build host could not
boot it; the checks below are structural and host-side only.

Download it from the [v0.3.1 GitHub release](https://github.com/HerbertGaming39/pivista-tv/releases/tag/v0.3.1).
The 1.23 GB image is a release asset, not a file in the Git tree; `releases/` is
where a local build writes it.

| Field | Value |
|---|---|
| Image | [`pivista-tv-0.3.1-pi5-arm64.img.xz`](https://github.com/HerbertGaming39/pivista-tv/releases/download/v0.3.1/pivista-tv-0.3.1-pi5-arm64.img.xz) |
| Size | 1,233,252,448 bytes (1.23 GB compressed) |
| SHA-256 | `4dc319f11004dff4e8bae11f50b85bda009fad042c73a1ef879d1434228e2ab5` |
| Build ID | `20261025T191615Z` |
| Host tests | 69 host Python tests, 8 launcher/Qt cases, 29 offscreen screen renders, 51 image checks (this build) |
| Hardware test checklist | [docs/hardware-test.md](docs/hardware-test.md) |

Verify the checksum before writing anything:

```powershell
# Windows PowerShell
Get-FileHash .\pivista-tv-0.3.1-pi5-arm64.img.xz -Algorithm SHA256
Get-Content .\pivista-tv-0.3.1-pi5-arm64.img.xz.sha256
```

```bash
# Linux / WSL, from the releases directory
sha256sum -c pivista-tv-0.3.1-pi5-arm64.img.xz.sha256
```

### Windows

1. Install [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or
   [balenaEtcher](https://etcher.balena.io/).
2. Choose **Use custom** / **Flash from file** and select the `.img.xz` directly;
   do not decompress it first.
3. Select the microSD/USB device. Confirm the drive letter twice.
4. Flash, then eject safely.
5. Do **not** use Imager's OS customisation (hostname, user, SSH, Wi-Fi).
   PiVista creates its own account and runs its own first-boot wizard.

### Linux

```bash
lsblk                       # identify the card; never guess /dev/sdX
cd pivista-tv/releases
sha256sum -c pivista-tv-0.3.1-pi5-arm64.img.xz.sha256
xz -dc pivista-tv-0.3.1-pi5-arm64.img.xz | \
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Raspberry Pi Imager and balenaEtcher are equally valid on Linux. The image
keeps Raspberry Pi OS's partition layout: a 512 MB FAT32 boot partition and an
ext4 root partition that grows to fill the card on first boot.

## First boot

1. Insert the card, connect HDMI, a USB keyboard or remote, and power. Ethernet
   is optional; Wi-Fi can be configured in the wizard.
2. The root filesystem grows on first boot. This is slower than later boots;
   the exact time has **not been measured on hardware**.
3. The wizard asks for language/time zone, network, display mode and interface
   scaling, audio output, remote-control notes, and privacy/update preferences.
   Every step can be skipped; the UI works offline.
4. The home screen appears. Use arrows, Enter, Escape/Back and Home.

Settings can be reopened at any time from the top bar. The wizard can be run
again from **Settings → Privacy and security → Run first-time setup**.

### Default login and security

There is **no default password and no usable login**. `root` and `pivista` are
locked, SSH is not installed, cloud-init is disabled, and no `pi` account is
created. The HDMI/serial console is for boot messages, not administration.
Recovery is offline: mount the card on another computer, or append
`init=/bin/bash` to `cmdline.txt` for a physical emergency shell and then revert
it. See [docs/recovery.md](docs/recovery.md).

## Remote control

| Key | Action |
|---|---|
| Arrows | Move focus |
| Enter / OK | Select |
| Escape / Backspace / remote Back | Back; from a top-level screen returns Home |
| Home | Return to launcher from any app (global, handled by sway) |
| Volume keys | PipeWire volume (global) |
| F10 / Menu | Quick settings |
| Ctrl+Alt+F2 | Switch VT (boot console; accounts are locked, no shell) |
| Ctrl+Alt+F1 | Back to the TV UI |

USB keyboards and remotes that emit standard key codes work without
configuration. Unusual IR remotes can be mapped in `/etc/pivista/input.map`.
The image contains BlueZ and the Bluetooth service is enabled, but this release
has **no Bluetooth pairing screen**; a Bluetooth-only remote cannot be paired
from the TV yet. Use USB for the first boot, or pair a device from a debug
context before connecting it. HDMI-CEC is **not verified** on Pi 5; do not
assume the TV remote will work without a USB receiver.

## Streaming, honestly

All streaming entries are shortcuts to the services' own websites, opened in a
dedicated Chromium profile. Chromium on 64-bit Raspberry Pi OS can load the
`libwidevinecdm0` Widevine CDM at **L3 (software)**. Netflix/Disney+ may play,
at resolutions the provider chooses; **no resolution is guaranteed or verified**,
and 1080p is not claimed. The Pi 5 has a hardware HEVC decoder but **no H.264
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

There are two separate update paths:

- **Launcher application** (binary, QML, app catalog): signed GitHub releases,
  verified with an Ed25519 public key, downloaded and installed from
  **Settings → Updates**, with a root-owned rollback copy. This is the path that
  avoids reflashing for application changes. User settings, favourites, web
  shortcuts, browser profiles and network configuration are not touched.
- **Debian/Raspberry Pi OS packages**: the existing apt path. There is no A/B
  partition scheme and **no automatic package rollback**; a failed OS update is
  recovered by reflashing a known-good image.

A **0.1.0 or 0.2.0 card cannot install this updater in place** because those
images have no update service or public key. They need one reflash to 0.3.1;
from then on the
launcher updater works. Full-image A/B updates (RAUC/`tryboot`) are investigated
but not implemented, because they need a different partition layout and a
one-time migration. Read [docs/updates.md](docs/updates.md) for the trust model,
release procedure and migration path, and [docs/recovery.md](docs/recovery.md)
for recovery.

## Troubleshooting

| Symptom | First thing to try |
|---|---|
| No picture | Confirm the TV input, try another HDMI port/cable, add `hdmi_force_hotplug=1` to `config.txt` on the boot partition |
| Black screen after the boot logo | The launcher shows a `swaynag` banner after three failures; read the journal offline (`journalctl -D /mnt/var/log/journal -b`) |
| Wizard does not reappear after a reset | Remove `~/.config/PiVista/Launcher.conf` while the card is mounted; see [docs/recovery.md](docs/recovery.md) |
| Wi-Fi will not join | Check the password dialog error; try Ethernet; hidden networks need a NetworkManager keyfile |
| No audio | Settings → Audio → choose the HDMI sink → Play test sound |
| Wrong time zone/locale | Settings → Network/Display; the wizard can be re-run from Privacy and security |
| Launcher update fails | Check the error in Settings → Updates; retry, or use **Roll back to previous launcher** if offered |
| System package update fails | Do not power off; if it does not recover, reflash; there is no package rollback |

Before reporting a problem, use **Settings → System → Export diagnostics**. It
writes a local JSON file (device serial and network addresses included) and
uploads nothing.

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
docs/                     architecture, streaming, build, security, updates, recovery
tools/                    release helpers, including the signed app-update builder
releases/                 generated images and manifests (not source)
```

## Licence

PiVista TV source is **GPL-3.0** (see [LICENSE](LICENSE)); Qt 6 is used
under the GPL option. The base image contains software under many licences;
every package's notices remain in `/usr/share/doc` on the device. PiVista TV is
an independent project and is not affiliated with or endorsed by Raspberry Pi
Ltd, Netflix, Disney, Google or any streaming provider.
