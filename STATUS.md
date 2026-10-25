# PiVista TV — status

Updated: 2026-10-25 · Version 0.1.0 "Aurora" · Build 20261025T102425Z ·
Build host: x86_64 WSL2 (Ubuntu), no Raspberry Pi 5 attached.

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
| Flashable image produced | Verified | `releases/pivista-tv-0.1.0-pi5-arm64.img.xz`, 1.29 GiB, SHA-256 recorded |
| Image structure validated | Verified | `tests/image/validate_image.py`: 38/38 checks |
| Boot on physical Pi 5 | **Blocked** | No hardware attached to the build host |
| Persistent user settings | Implemented | `~/.config/PiVista/Launcher.conf` |
| Shutdown / reboot | Implemented | `pivistad` → `systemctl poweroff/reboot` |
| Recovery instructions | Verified | [docs/recovery.md](docs/recovery.md) |

## Interface

| Item | Status | Evidence / note |
|---|---|---|
| Full-screen TV launcher | Verified | Offscreen 1920×1080 renders of Home/Apps/Settings and wizard steps 0/3/6; no QML binding errors |
| Remote-style navigation | Implemented | Qt focus chain, arrow/Enter/Back/Home; no hardware remote test |
| Application discovery | Verified | Unit tests over `.desktop` parsing rules (catalog smoke test via launcher run) |
| Favourites and shortcuts | Verified | Unit tests + persistence via QSettings |
| First-boot wizard | Implemented | 8 screens: welcome, region, network, display+scaling, audio, remote, privacy/updates, summary; three screens rendered offscreen |
| Network settings | Implemented | NetworkManager via `pivistad`; no Wi-Fi hardware test |
| Display settings | Implemented | `wlr-randr` via `pivistad`; no HDMI test |
| Audio settings | Implemented | PipeWire/PulseAudio via `pivistad`; no HDMI audio test |
| System information | Implemented | `/proc`, `/sys`, build provenance |
| Error reporting | Verified | Launch failures and service errors surface as toasts |

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
| Netflix compatibility | Hardware-dependent | Shortcut works; DRM playback unverified |
| Disney+ compatibility | Hardware-dependent | Shortcut works; DRM playback unverified |
| 1080p protected playback | **Not claimed** | Would require provider-side evidence |

## Build and maintenance

| Item | Status |
|---|---|
| Clean build instructions | Verified — `build.sh check` |
| Dependency pinning | Verified — [manifest/base-image.lock](manifest/base-image.lock) |
| Build logs | Implemented — `build/logs/build-<id>.log` |
| Automated tests | Verified — 33 daemon + 7 launcher + 38 image checks, all passing |
| Image checksums | Verified — `.sha256` matches; `xz -t` passes |
| Software licence notices | Implemented — `/usr/share/doc` retained in image |
| Update and recovery documentation | Verified — [docs/recovery.md](docs/recovery.md) |
| Known limitations listed | Verified — this file and README |
| No credentials in release artifact | Verified — build-time scan + image validation |

## Release artifact

| Field | Value |
|---|---|
| Image | `releases/pivista-tv-0.1.0-pi5-arm64.img.xz` |
| Size | 1,382,782,192 bytes (1.29 GiB compressed) |
| SHA-256 | `ce2e64f9d1e4da1750d2faf2d97f9f6e19f851c7f21ebe9f3a7c4f63f95ee02e` |
| Build ID | `20261025T102425Z` |
| Packages | 1046 installed (versions in the manifest) |

## What is deliberately absent

- A signed update channel and rollback (would need infrastructure).
- Widevine L1 / provider certification.
- Google Play services, Android runtime, APK installation.
- Telemetry, cloud accounts, remote administration.

## Next verification steps (in order)

1. Boot the image on a real Pi 5 and capture the serial console + first-boot
   wizard, then Home/Apps/Settings navigation with a USB keyboard.
2. Confirm HDMI audio and display mode switching on a television.
3. Measure launcher start time, idle CPU and memory; record in `docs/hardware.md`.
4. Test Netflix/Disney+ sign-in and playback with a real account, recording the
   observed resolution and decoder (see `docs/streaming.md` protocol).
5. Test Wi-Fi association with a remote-only setup, including a wrong password.
