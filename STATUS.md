# PiVista TV — status

Updated: 2026-10-26 · Version 0.3.2 "Harbor" · Build `20261026T160333Z`

Build host: x86_64 WSL2 (Ubuntu). The image was validated and its launcher was
rendered from the sealed filesystem under qemu-user. It has **not** been booted
on a Raspberry Pi 5. No physical Pi was reachable during this build; hardware
boot, HDMI/audio, Wi-Fi, remote input and a real launcher update therefore
remain unverified.

The previous 0.1.0, 0.2.0, 0.3.0 and 0.3.1 artifacts remain under
`releases/baseline-*` and as `releases/pivista-tv-0.<minor>.0-pi5-arm64.img.xz`
(0.2.0, 0.3.0, 0.3.1).

Status vocabulary:

| Term | Meaning |
|---|---|
| **Verified** | Exercised by an automated test or an operation recorded in this repo |
| **Implemented** | Code exists and is wired up, but was not exercised end-to-end |
| **Hardware-dependent** | Cannot be verified without a physical Pi 5 / television / account |
| **Experimental** | Enabled but known incomplete |
| **Unsupported** | Deliberately not provided |
| **Blocked** | Attempted, blocked by an external constraint |

## Update system (0.3.2)

| Item | Status | Evidence / note |
|---|---|---|
| Release discovery on GitHub | Verified | Fake-release unit tests; stable/prerelease filtering, drafts ignored |
| Live discovery of published v0.3.0 | Verified | Real GitHub API check on 2026-10-25; `v0.3.0` found, signed manifest verified with the installed public key, no update offered while installed version matches |
| Live discovery of published v0.3.1 | Verified | Real GitHub API check on 2026-10-25; `v0.3.1` found, signed manifest verified with the installed public key; a simulated 0.3.0 install reports `available: true` with bundle SHA-256 `47e44d…` |
| Signed manifest verification | Verified | Ed25519 test key; corrupted signature and malformed manifests rejected |
| Archive integrity | Verified | SHA-256 and exact size checked against the signed manifest; corrupt and interrupted downloads rejected |
| HTTPS / host restriction | Verified | `https://` required; redirects limited to GitHub hosts |
| Prerelease opt-in | Verified | Disabled by default; explicit Settings preference |
| Minimum version / image compatibility | Verified | Incompatible release is displayed but not offered |
| Downgrade prevention | Verified | Only a version newer than the installed one can be downloaded/installed |
| Archive path restriction | Verified | Fixed paths only; traversal, symlinks, devices and unexpected files rejected |
| Atomic staged install | Verified (host) | Local temp filesystem; backup and rename-based swap |
| Rollback | Verified (host) | Previous launcher restored; Settings action |
| Interrupted-job recovery | Verified (host) | Active job becomes failed after daemon restart; no permanent spinner |
| User/network data preservation | Verified (host) | Install test leaves launcher config and NetworkManager keyfile untouched |
| Settings update UI | Verified (offscreen) | Updates page rendered at 720p and 1080p; no QML errors |
| Periodic background check | Implemented | Read-only check at 60 s and every 6 h; never auto-installs |
| Restart without interrupting playback | Implemented | Install does not kill the launcher; restart is confirmed separately |
| Launcher update on a real Pi | **Hardware-dependent** | No physical boot or live network/download test |
| Full-image A/B / RAUC | **Unsupported** | Investigated in [docs/updates.md](docs/updates.md); needs a new partition layout and migration |
| In-place upgrade from 0.1.0 | **Unsupported** | 0.1.0 has no updater/public key; one-time reflash required |
| Automatic package rollback | **Unsupported** | apt path remains single-slot; reflash on failure |

## Operating system

| Item | Status | Evidence / note |
|---|---|---|
| Linux host (not Android) | Verified | Raspberry Pi OS 2026-10-06, Debian 13, kernel 6.18 |
| Pi 5-specific configuration | Implemented | `kernel_2712.img`, `bcm2712-rpi-5-b.dtb`, `[pi5]` config section retained |
| Reproducible dependency pins | Verified | base image SHA-256 verified at build time; 1051 package versions recorded |
| Flashable image produced | Verified | `releases/pivista-tv-0.3.2-pi5-arm64.img.xz`; SHA-256 recorded |
| Compressed image integrity | Verified | `xz -t` passes; decompressed hash equals the validated work image |
| Image structure validated | Verified | `tests/image/validate_image.py`: 61/61 checks |
| Launcher in sealed image | Verified | `pivista-launcher --version` → 0.3.2 in the mounted image under qemu-user |
| Published image matches validated rootfs | Verified | `xz -dc` of the release image hashes to the same work image that passed 61/61 checks |
| Sealed-image UI render | Verified | Home 720p/1080p/4K, Apps, Media, Settings, Updates and Remote support rendered from `/usr/share/pivista/qml` in the mounted image |
| Signed update metadata in image | Verified | `/usr/share/pivista/version.json` and `/etc/pivista/update-pubkey.pem`, mode 0644 |
| First-boot root resize | Verified (unit enabled) | vendor `rpi-resize.service` enabled (`systemd-growfs-root`); not exercised on a flashed card |
| Vendor first-boot helpers disabled | Verified | `userconfig.service` and `sshswitch.service` masked |
| cloud-init cannot recreate `pi` | Verified | cloud-init units masked, `/etc/cloud/cloud-init.disabled` present, seed files removed |
| SSH host-key regeneration disabled | Verified | `regenerate_ssh_host_keys.service` masked; no host keys shipped; keys are generated on device when SSH is first enabled |
| Remote support installed but off | Verified | `openssh-server` and `wayvnc` installed; `ssh.service`, `ssh.socket` and `pivista-vnc.service` disabled in the image; no listener on first boot |
| Bluetooth stack enabled | Verified | `bluetooth.service` enabled and `bluetoothctl` present; pairing UI is exercised only with a mocked daemon |
| Boot on physical Pi 5 | **Blocked** | No hardware reachable during this build |
| Persistent user settings | Verified | `~/.config/PiVista/Launcher.conf` (Qt Settings); update test proves it is untouched |
| Shutdown / reboot | Implemented | `pivistad` → `systemctl poweroff/reboot` |
| Recovery instructions | Verified | [docs/recovery.md](docs/recovery.md) |

## Interface (0.3.2)

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
| Updates settings and signed-update controls | Verified | Updates page renders at both sizes; check/download/install/postpone/rollback/restart actions wired |
| Clock, network and system status | Implemented | Header clock/status; daemon status path has unit tests, no live network in the test host |
| Remote-style navigation | Implemented | Qt focus chain, arrows/Enter/Back/Escape/Home; no physical remote test |
| Settings reachability | Verified (offscreen) | Test drives Home → header → Settings → Network → Input with key events; Home/Media row focus regression covered |
| Input settings | Implemented (offscreen) | Kernel device list, key probe and wizard probe; no physical keyboard/remote test |
| Time zone and clock settings | Implemented | Settings page writes `timedatectl` through the daemon; 12/24-hour and seconds options persisted |
| Sleep timer | Implemented (offscreen) | Quick settings cycles 30/60/90/off; expiry shows the screensaver, never powers off storage |
| Section transitions | Implemented (offscreen) | Fade on screen change, focus lift in navigation and action rows; reduced-motion setting still honoured. Motion is CSS/QML animation, not a GPU frame-rate claim |
| Streaming category focus | Verified (offscreen) | Media chips are reachable with Left/Right and focus is visible; test drives the production Home/Media QML |
| First-boot wizard key handling | Verified (offscreen) | Synthetic Down/Up/Enter/Escape/Select/Backspace test; activation and sway map refocus the launcher; the network step no longer collapses Down onto **Do this later** |
| Blank-screen regression guard | Verified | `tests/ui/screenshot_content.py` fails a correctly-sized but blank content area |
| 720p / 1080p / 4K scaling | Verified (offscreen) | 1280×720, 1920×1080 and 3840×2160 renders; not a GPU measurement |
| First-boot wizard | Verified | 8 wizard steps rendered at 720p, welcome at 1080p |
| Bluetooth input | Implemented (hardware unverified) | Settings → Bluetooth scans, pairs, trusts and forgets devices; mocked control-service tests only |
| Input key test | Implemented (offscreen) | Settings → Input opens a local key probe showing the exact keys the launcher receives; no physical-device test |
| SSH remote support | Implemented (hardware unverified) | Disabled by default; `support` account with generated password, no sudo, `AllowUsers support`; daemon unit tests, no live network test |
| VNC remote support | Implemented (hardware unverified) | Disabled by default; `wayvnc` on `127.0.0.1:5900`, reached only through an SSH tunnel; unit tests, no live viewer test |
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
| Automated tests | Verified — 82 host Python tests, 15 launcher/Qt cases, 37 offscreen renders, 61 image checks |
| App-update archive reproducibility | Verified — deterministic tar metadata/xz; builder test compares two builds |
| Image integrity | Verified — SHA-256 matches; `xz -t` passes |
| Software licence notices | Implemented — `/usr/share/doc` retained in image |
| Update and recovery documentation | Verified — [docs/updates.md](docs/updates.md), [docs/recovery.md](docs/recovery.md) |
| Known limitations listed | Verified — this file and README |
| No credentials in release artifact | Verified — build-time scan + image validation |

## Release artifact

| Field | Value |
|---|---|
| Image | `releases/pivista-tv-0.3.2-pi5-arm64.img.xz` |
| Size | `1,240,441,036 bytes (1.24 GB / 1.16 GiB compressed)` |
| SHA-256 | `0145c6d4711e7d781750b7cca844029c55086e0a0b0fae967e7177a084c68a45` |
| Build ID | `20261026T160333Z` |
| Packages | 1051 installed (versions in the manifest) |
| Source state | Commit `45ec6f1`; the manifest records `source_dirty: true` only because the tracked release checksum is rewritten during packaging |
| Hardware test checklist | [docs/hardware-test.md](docs/hardware-test.md) |

## What is deliberately absent

- Full-image A/B updates and automatic rollback for OS packages. The signed
  launcher channel is separate and implemented; the base image is not.
- Widevine L1 / provider certification.
- Google Play services, Android runtime, APK installation.
- HDMI-CEC key translation. The adapter can be detected, but no CEC remote path is enabled.
- Telemetry and cloud accounts. Remote administration exists only as the
  optional, off-by-default SSH/VNC support path described in
  [docs/remote-access.md](docs/remote-access.md); it is not a management plane.

## Next verification steps (in order)

1. Follow `docs/hardware-test.md` on a real Pi 5: checksum, flash, first boot,
   wizard, Home/Apps/Games/Media/Settings, HDMI audio and mode switching.
2. Test the signed launcher update on hardware: check, download, install,
   restart, rollback, network loss, corrupted archive and power loss during
   install. Record the exact versions.
3. Measure cold boot to launcher, launcher start time, idle CPU and memory;
   record in `docs/hardware.md`.
4. Test Netflix/Disney+/YouTube/Polish service sign-in and playback with a real
   account, recording the observed resolution and decoder.
5. Test Wi-Fi association with a remote-only setup, including a wrong password.
6. Test the global Home key while Chromium and a native app are running.
7. Test a USB/IR remote and record which buttons emit which key codes.
8. Test optional SSH and VNC from another computer: refused when off, password
   login, no sudo, tunnel-only VNC, and both disabled again after a reboot.
