# PiVista TV — status

Updated: 2026-10-25 · Version 0.1.0 "Aurora" · Build 20261025T133307Z ·
Build host: x86_64 WSL2 (Ubuntu). A physical Pi 5 was used for a headless
Widevine/codec platform probe, but this image has not been booted on it.
The previous working image (build 20261025T123536Z) is preserved in
`releases/baseline-0.1.0-20261025T133211Z/`; earlier builds are under their own
`releases/baseline-*` directories.

Status vocabulary:

| Term | Meaning |
|---|---|
| **Verified** | Exercised by an automated test or observed operation recorded in this repo |
| **Implemented** | Code exists and is wired up, but was not exercised end-to-end |
| **Hardware-dependent** | Cannot be verified without a physical Pi 5 / television / account |
| **Experimental** | Enabled but known incomplete |
| **Unsupported** | Deliberately not provided |
| **Blocked** | Attempted, blocked by an external constraint |

## Operating system

| Item | Status | Evidence / note |
|---|---|---|
| Linux host (not Android) | Verified | Raspberry Pi OS 2026-10-06, Debian 13, kernel 6.18 |
| Pi 5-specific configuration | Implemented | `kernel_2712.img`, `bcm2712-rpi-5-b.dtb`, `[pi5]` config section retained |
| Reproducible dependency pins | Verified | base image SHA-256 verified at build time; package versions recorded |
| Flashable image produced | Verified | `releases/pivista-tv-0.1.0-pi5-arm64.img.xz`, 1.20 GiB, SHA-256 recorded |
| Image structure validated | Verified | `tests/image/validate_image.py`: 46/46 checks |
| First-boot root resize | Verified (unit enabled) | vendor `rpi-resize.service` enabled (`systemd-growfs-root`); not exercised on a flashed card |
| Vendor first-boot helpers disabled | Verified | `userconfig.service` and `sshswitch.service` masked |
| cloud-init cannot recreate `pi` | Verified | cloud-init units masked, `/etc/cloud/cloud-init.disabled` present, seed files removed |
| SSH host-key regeneration disabled | Verified | `regenerate_ssh_host_keys.service` masked; `/etc/ssh` absent |
| Boot on physical Pi 5 | **Blocked** | No hardware attached to the build host |
| Persistent user settings | Implemented | `~/.config/PiVista/Launcher.conf` |
| Shutdown / reboot | Implemented | `pivistad` → `systemctl poweroff/reboot` |
| Recovery instructions | Verified | [docs/recovery.md](docs/recovery.md) |

## Interface

| Item | Status | Evidence / note |
|---|---|---|
| Full-screen TV launcher | Verified | Offscreen 1920×1080 and 1280×720 renders; no QML binding errors |
| Remote-style navigation | Implemented | Qt focus chain, arrow/Enter/Back/Home; no hardware remote test |
| Bluetooth input | **Unsupported** | BlueZ and `bluetooth.service` are in the image, but there is no pairing UI; a Bluetooth-only remote cannot be added from the TV |
| Global Home return | Implemented | sway binding + user-only launcher socket; socket emission unit-tested; no hardware test |
| Physical keyboard text entry | Implemented | Printable keys and Backspace handled by the on-screen keyboard dialog; no hardware test |
| Application discovery | Verified | Unit tests over `.desktop` parsing rules (catalog smoke test via launcher run) |
| Favourites and shortcuts | Verified | Unit tests + persistence via QSettings |
| First-boot wizard | Implemented | 8 screens: welcome, region, network, display+scaling, audio, remote, privacy/updates, summary; all 8 rendered offscreen at 720p, welcome at 1080p |
| Network settings | Implemented | NetworkManager via `pivistad`; response IDs and Wi-Fi-only disconnect fixed; no Wi-Fi hardware test |
| Display settings | Implemented | `wlr-randr` via `pivistad`; no HDMI test |
| Audio settings | Implemented | PipeWire/PulseAudio via `pivistad`; no HDMI audio test |
| System information | Implemented | `/proc`, `/sys`, build provenance |
| Error reporting | Verified | Launch failures, service errors, wizard display/audio failures and a `swaynag` launcher banner |

## Applications and media

| Item | Status | Evidence / note |
|---|---|---|
| Native application launching | Implemented | Validated `.desktop` exec, no shell |
| Web application launching | Implemented | Chromium kiosk + dedicated profile |
| Browser management | Implemented | Per-service profiles; clear-data action |
| Compatibility reporting | Implemented | Native/Web/Android + DRM notes shown in UI |
| Optional Android integration | Unsupported | Not shipped; see [docs/android.md](docs/android.md) |
| Local media playback | Hardware-dependent | FFmpeg/GStreamer present; no playback test performed |
| Audio output | Hardware-dependent | No audio device in build host |
| Decoder diagnostics | Implemented | `v4l2-ctl`, `ffmpeg`, sysfs exposed; no Pi 5 measurement |
| Hardware video acceleration | **Unverified** | Pi 5 HEVC V4L2 path exists upstream; not confirmed in Chromium |
| Widevine EME on physical Pi 5 | Verified platform probe | Headless Chromium 149 on vendor Pi OS granted `cenc`/H.264/AAC access; not the sealed image, no playback |
| Netflix compatibility | Hardware-dependent | Shortcut works; DRM playback unverified |
| Disney+ compatibility | Hardware-dependent | Shortcut works; DRM playback unverified |
| 1080p protected playback | **Not claimed** | Would require provider-side evidence |

## Build and maintenance

| Item | Status |
|---|---|
| Clean build instructions | Verified — `build.sh check` |
| Dependency pinning | Verified — [manifest/base-image.lock](manifest/base-image.lock) |
| Build logs | Implemented — `build/logs/build-<id>.log` |
| Automated tests | Verified — 38 host Python tests, 6 launcher/Qt cases, 19 offscreen screen renders and 46 image checks, all passing |
| Image checksums | Verified — `.sha256` matches; `xz -t` passes |
| Software licence notices | Implemented — `/usr/share/doc` retained in image |
| Update and recovery documentation | Verified — [docs/recovery.md](docs/recovery.md) |
| Known limitations listed | Verified — this file and README |
| No credentials in release artifact | Verified — build-time scan + image validation |

## Release artifact

| Field | Value |
|---|---|
| Image | `releases/pivista-tv-0.1.0-pi5-arm64.img.xz` |
| Size | 1,290,377,464 bytes (1.20 GiB compressed) |
| SHA-256 | `576f4a056fb405cae2f800bf581ba91099726b9a8a43d93659f78d8f8cc1be82` |
| Build ID | `20261025T133307Z` |
| Packages | 1046 installed (versions in the manifest) |
| Source state | Working tree had uncommitted audit changes when sealed (`source_dirty: true` in the manifest); the prior source snapshot is in `releases/baseline-0.1.0-20261025T115926Z/source.tar.gz` |

## What is deliberately absent

- A signed update channel and rollback (would need infrastructure).
- Widevine L1 / provider certification.
- Google Play services, Android runtime, APK installation.
- Telemetry, cloud accounts, remote administration.

## Next verification steps (in order)

1. Follow `docs/hardware-test.md` on a real Pi 5: checksum, flash, first boot,
   wizard, Home/Apps/Settings, HDMI audio and display mode switching.
2. Measure cold boot to launcher, launcher start time, idle CPU and memory;
   record in `docs/hardware.md`.
3. Test Netflix/Disney+ sign-in and playback with a real account, recording the
   observed resolution and decoder (see `docs/streaming.md` protocol).
4. Test Wi-Fi association with a remote-only setup, including a wrong password.
5. Test the global Home key while Chromium is fullscreen and while a native app
   is running; confirm the launcher returns to Home both times.
