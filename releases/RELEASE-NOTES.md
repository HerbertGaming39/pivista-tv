# PiVista TV 0.3.1 (Cascade)

Build `20261025T191615Z`. A patch release for first-boot input and focus.

PiVista TV is a Linux-based television interface for the Raspberry Pi 5. It is
not Android, it is not a certified streaming device, and this release has not
been booted on a physical Pi by the build host.

## What changed

- **First-boot focus:** the launcher now takes focus when sway maps it and
  moves active focus onto the wizard's visible action list after the window
  becomes active. A cold boot no longer leaves the setup card drawn but
  ignoring the remote or keyboard.
- **Back and OK:** Backspace is accepted as Back, and `KEY_SELECT` (sent by
  some TV remotes) is accepted as OK. Escape, Enter, arrows and the global
  Home key are unchanged.
- **Regression test:** a new offscreen QML test loads the real launcher and
  drives the wizard with synthetic Down/Up/Enter/Escape/Select/Backspace
  events. It is part of the normal launcher test suite.
- **Documentation:** [docs/recovery.md](https://github.com/HerbertGaming39/pivista-tv/blob/main/docs/recovery.md)
  now explains the difference between a USB keyboard/remote, a Bluetooth
  keyboard (no pairing UI yet) and an LG/Samsung TV remote (HDMI-CEC is not
  bridged in this image). It also explains that PiVista has no SSH server.

## What actually works for setup

- Use a **USB keyboard** or a **USB/IR remote** plugged into the **Pi**, not
  into the television. A wireless keyboard with its own USB dongle is fine;
  put the dongle in the Pi.
- A **Bluetooth-only keyboard** cannot be paired yet.
- The **television's own remote** controls the television over HDMI-CEC. This
  image installs `cec-utils` but does not run a CEC-to-keyboard bridge, so the
  TV remote cannot set up the Pi. This is a documented limitation, not a claim
  that CEC hardware is absent.
- PiVista deliberately has **no SSH**. A login that worked on an earlier
  Raspberry Pi OS card is not available after that card is replaced.

## Image

| Field | Value |
|---|---|
| File | `pivista-tv-0.3.1-pi5-arm64.img.xz` |
| Size | `1,233,252,448` bytes (1.23 GB compressed) |
| SHA-256 | `4dc319f11004dff4e8bae11f50b85bda009fad042c73a1ef879d1434228e2ab5` |
| Build ID | `20261025T191615Z` |
| Target | Raspberry Pi 5, 8 GB recommended, arm64 |
| Base | Raspberry Pi OS 2026-10-06 Lite (Debian 13 trixie, Linux 6.18) |
| Packages | 1046 recorded in the artifact manifest |
| Launcher | PiVista TV launcher 0.3.1 |

Verify before flashing:

```bash
sha256sum -c pivista-tv-0.3.1-pi5-arm64.img.xz.sha256
xz -t pivista-tv-0.3.1-pi5-arm64.img.xz
```

Flash with Raspberry Pi Imager or balenaEtcher, or:

```bash
xz -dc pivista-tv-0.3.1-pi5-arm64.img.xz | \
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Do not use Imager's OS customisation. PiVista owns first boot, creates its own
account and runs its own setup wizard. There is no default password and no SSH
server in the image.

## Launcher update bundle

Settings → Updates can install this application bundle on an existing 0.3.0
image without reflashing. The archive contains only the launcher binary, QML,
curated web catalog and version file.

| Field | Value |
|---|---|
| File | `pivista-launcher-0.3.1-arm64.tar.xz` |
| Size | `96,260` bytes |
| SHA-256 | `47e44d818796bdce25b73a94d656cc046d977fb51675bb41b108bd0004cd2529` |
| Manifest | `pivista-update.json` (Ed25519 signature: `pivista-update.json.sig`) |
| Minimum launcher | `0.3.0` |
| Minimum system image | `0.3.0` |

A 0.3.0 device can install this from Settings → Updates. A 0.1.0 or 0.2.0 card
has no updater or public key and must be reflashed once. Installing the bundle
does not touch user settings, favourites, browser profiles or network
configuration, and keeps a rollback copy.

## What was tested

- 69 host Python tests, including discovery, signature failure, corruption,
  interrupted downloads, insufficient space, downgrade and rollback cases.
- 8 launcher/Qt cases, including the new real-QML wizard key test.
- 29 offscreen QML screens at 720p and 1080p (plus 1080p and 4K Home), with no
  QML runtime errors.
- 51/51 checks on the sealed image, including version, QML presence, public-key
  mode, account ownership, SSH absence and arm64 launcher/kernel.
- The published compressed image decompresses to exactly the validated work
  image: both hash to
  `823299a4e6a180492a7f1bc6b0e3fc41f7232b273043b189109d739866665f28`.
- The launcher inside the image reports `PiVista TV launcher 0.3.1`.
- The signed update manifest verifies with the public key installed in the
  image; the bundle SHA-256 matches the signed manifest.

This is **not** a physical-Pi boot test. HDMI output/audio, Wi-Fi association,
a real remote, GPU performance and a live launcher update remain hardware
tests. The build host had no reachable Pi during this build.

## Streaming status

Browser shortcuts open the services' own sites in a dedicated Chromium profile.
Widevine L3 is present; **no protected playback, login, resolution or hardware
acceleration is verified for this image**. Netflix, Disney+, Prime Video and the
Polish services are marked unverified in the product and in
[docs/streaming.md](https://github.com/HerbertGaming39/pivista-tv/blob/main/docs/streaming.md).
No 1080p claim is made. Prime Video is expected to be SD outside Windows/macOS
under Amazon's published rule.

## Known limitations

- No HDMI-CEC bridge, so a television remote alone cannot control the Pi.
- No Bluetooth pairing UI; a Bluetooth-only remote or keyboard cannot be paired
  from the TV yet.
- No Android runtime, Play services or APK installation.
- No A/B image update or automatic package rollback; recovery is reflashing.
- No resume/continue-watching positions.
- Physical Pi 5 validation is still outstanding.

See [`STATUS.md`](https://github.com/HerbertGaming39/pivista-tv/blob/main/STATUS.md)
and [`docs/hardware-test.md`](https://github.com/HerbertGaming39/pivista-tv/blob/main/docs/hardware-test.md)
for the item-by-item status and the checklist to run on real hardware.
