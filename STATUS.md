# PiVista TV — status

Updated: 2026-10-25 · Version 0.2.0 "Borealis" · Build `20261025T153658Z`
Build host: x86_64 WSL2 (Ubuntu). The image was validated and its launcher was
rendered from the sealed filesystem under qemu-user. It has **not** been booted
on a Raspberry Pi 5: the physical Pi previously used for the streaming probe was
unreachable over SSH (`No route to host`) during this build.

The previous 0.1.0 artifacts remain under `releases/baseline-0.1.0-*/`.

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
| Reproducible dependency pins | Verified | base image SHA-256 verified at build time; 1046 package versions recorded |
| Flashable image produced | Verified | `releases/pivista-tv-0.2.0-pi5-arm64.img.xz`, 1.23 GB, SHA-256 recorded |
| Image structure validated | Verified | `tests/image/validate_image.py`: 46/46 checks |
| Launcher in sealed image | Verified | `pivista-launcher --version` → 0.2.0 in the mounted image under qemu-user |
| Sealed-image UI render | Verified | Home 720p/1080p, Apps, Media and Settings rendered from `/usr/share/pivista/qml` in the mounted image |
| First-boot root resize | Verified (unit enabled) | vendor `rpi-resize.service` enabled (`systemd-growfs-root`); not exercised on a flashed card |
| Vendor first-boot helpers disabled | Verified | `userconfig.service` and `sshswitch.service` masked |
| cloud-init cannot recreate `pi` | Verified | cloud-init units masked, `/etc/cloud/cloud-init.disabled` present, seed files removed |
| SSH host-key regeneration disabled | Verified | `regenerate_ssh_host_keys.service` masked; `/etc/ssh` absent |
| Boot on physical Pi 5 | **Blocked** | No hardware reachable during this build |
| Persistent user settings | Verified | `~/.config/PiVista/Launcher.conf` (Qt Settings) |
| Shutdown / reboot | Implemented | `pivistad` → `systemctl poweroff/reboot` |
| Recovery instructions | Verified | [docs/recovery.md](docs/recovery.md) |

## Interface (0.2.0)

| Item | Status | Evidence / note |
|---|---|---|
| Featured home banner | Verified | Offscreen Home renders at 720p, 1080p and 4K; sealed-image render shows the banner |
| Horizontal app/media rows | Verified | Five visible rows with real catalog data in the sealed image |
| Home / Apps / Games / Media / Search / Settings sections | Verified | Each screen has a smoke render; Games has a tested empty state |
| Favourites row | Verified | App details toggles the persisted favourite list; Home binds it |
| Recently opened row | Implemented | Launch history is persisted; labelled "Recently opened", not a resume position |
| App details sheet | Verified | 720p and 1080p renders; favourite, hide, launch and close actions |
| Installed vs web shortcut separation | Verified | Catalog carries `kind`, `installed` and `web`; tests cover both maps |
| Appearance settings | Verified | Theme, wallpaper, row visibility, start screen and 12/24-hour clock persisted and rendered |
| Clock, network and system status | Implemented | Header clock/status; daemon status path has unit tests, no live network in the test host |
| Remote-style navigation | Implemented | Qt focus chain, arrows/Enter/Back/Escape/Home; no physical remote test |
| Blank-screen regression guard | Verified | `tests/ui/screenshot_content.py` fails a correctly-sized but blank content area |
| 720p / 1080p / 4K scaling | Verified (offscreen) | 1280×720, 1920×1080 and 3840×2160 renders; not a GPU measurement |
| First-boot wizard | Verified | 8 wizard steps rendered at 720p, welcome at 1080p |
| Bluetooth input | **Unsupported** | BlueZ/service present, but no pairing UI; documented limitation |
| Global Home return | Implemented | sway binding + user-only launcher socket; no hardware test |
| HDMI-CEC | **Unverified** | No CEC test or bridge enabled |

## Applications and media

| Item | Status | Evidence / note |
|---|---|---|
| Native application discovery | Verified | `.desktop` unit tests, category inference, terminal/missing entries rejected |
| Native application launching | Verified | Unit test launches an allowed app and records it in recent history |
| Web application launching | Implemented | Chromium kiosk + dedicated profile; no live playback test |
| App launch error handling | Verified | Invalid/missing programs return a reason; no dead tiles are listed |
| Games section | Verified | Category detection test and empty-state render |
| Media section | Verified | Streaming/installed rows render with the real image catalog |
| Recently opened ordering | Verified | Launch test records and returns the launched entry |
| Continue Watching / resume points | **Unsupported** | No provider or player integration; the product does not claim resume position |
| Local USB/network media browsing | Hardware-dependent | Provided by an installed player; PiVista does not index or bundle one |
| Android compatibility | Unsupported | Not shipped; see [docs/android.md](docs/android.md) |
| Widevine EME platform probe | Hardware probe | Headless Chromium on the vendor Pi OS granted `cenc`/H.264/AAC access; not the sealed image and no playback |
| Netflix / Disney+ / Prime / TVP / Player / Canal+ | Hardware-dependent | Shortcuts work; DRM playback unverified |
| 1080p protected playback | **Not claimed** | No provider-side evidence |

## Build and maintenance

| Item | Status |
|---|---|
| Clean build instructions | Verified — `build.sh check` |
| Dependency pinning | Verified — [manifest/base-image.lock](manifest/base-image.lock) |
| Build logs | Implemented — `build/logs/build-<id>.log` |
| Automated tests | Verified — 38 host Python tests, 6 launcher/Qt cases, 27 offscreen renders and 46 image checks |
| Image integrity | Verified — SHA-256 matches; `xz -t` passes |
| Software licence notices | Implemented — `/usr/share/doc` retained in image |
| Update and recovery documentation | Verified — [docs/recovery.md](docs/recovery.md) |
| Known limitations listed | Verified — this file and README |
| No credentials in release artifact | Verified — build-time scan + image validation |

## Release artifact

| Field | Value |
|---|---|
| Image | `releases/pivista-tv-0.2.0-pi5-arm64.img.xz` |
| Size | 1,230,308,476 bytes (1.23 GB / 1.15 GiB compressed) |
| SHA-256 | `02445ff9d2056941a77b02694fccc5f9f7979056fb2bfca8e043347f3ba5f1b4` |
| Build ID | `20261025T153658Z` |
| Packages | 1046 installed (versions in the manifest) |
| Source state | Built from source commit `f4ea16b`; only generated release metadata changed after sealing |
| Hardware test checklist | [docs/hardware-test.md](docs/hardware-test.md) |

## What is deliberately absent

- A signed update channel and rollback (would need infrastructure).
- Widevine L1 / provider certification.
- Google Play services, Android runtime, APK installation.
- Bluetooth pairing UI.
- Telemetry, cloud accounts, remote administration.

## Next verification steps (in order)

1. Follow `docs/hardware-test.md` on a real Pi 5: checksum, flash, first boot,
   wizard, Home/Apps/Games/Media/Settings, HDMI audio and mode switching.
2. Measure cold boot to launcher, launcher start time, idle CPU and memory;
   record in `docs/hardware.md`.
3. Test Netflix/Disney+/YouTube/Polish service sign-in and playback with a real
   account, recording the observed resolution and decoder.
4. Test Wi-Fi association with a remote-only setup, including a wrong password.
5. Test the global Home key while Chromium and a native app are running.
6. Test a USB/IR remote and record which buttons emit which key codes.
