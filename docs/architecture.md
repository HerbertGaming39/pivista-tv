# Architecture

## Decision summary

PiVista TV is a **derivative image built from a pinned Raspberry Pi OS Lite
(arm64, Debian 13 "trixie") release**, not a from-scratch distribution and not
Android. The build decompresses the official image, grows its root partition,
enters it through `qemu-aarch64` binfmt emulation, installs a pinned package
set, overlays the PiVista system files, compiles the launcher for arm64, seals
the filesystem and validates the result.

That choice was made after comparing the realistic alternatives.

## Foundation comparison

| Option | Pi 5 boot / firmware | Qt 6 + Chromium + Widevine | Build cost | Maintenance | Verdict |
|---|---|---|---|---|---|
| **Raspberry Pi OS image derivative (chosen)** | Guaranteed: vendor image, `kernel_2712.img`, Pi 5 DTBs, EEPROM boot flow | Packages exist in Debian trixie + Raspberry Pi repo | ~15–40 min, one machine, no Docker | Follow the vendor release; pin by SHA-256 | **Selected** |
| pi-gen (Raspberry Pi's image builder) | Guaranteed | Same package availability | Longer: builds every stage from debootstrap; Docker or privileged chroot | Vendor-maintained; rebuilds the world for a launcher change | Viable, but wasteful for this project and harder to make incremental |
| Buildroot | Needs custom kernel/firmware integration | No Chromium/Widevine package; Qt would be cross-built | Days of work; large toolchain | Every security update becomes a rebuild of the world | Rejected |
| Yocto / OpenEmbedded | Needs meta-raspberrypi + board bring-up | Chromium/Widevine recipes are fragile or absent for Pi 5 | Very large (100+ GB, hours) | Heavy; unrealistic for one maintainer | Rejected |
| Custom Debian assembled from debootstrap | Manual kernel/firmware/DTB/bootloader work | Possible | Medium | Must track Pi 5 firmware and kernel packaging | Rejected: re-implements vendor work without benefit |

**Why not pi-gen?** pi-gen is the right tool for producing a *Raspberry Pi OS
release*. PiVista TV needs a *stable base plus a thin product layer*. Rebuilding
the base on every launcher change costs hours and adds failure modes (network
flakiness in debootstrap, Docker requirements) without improving the product.
The pinned-image approach is exactly reproducible in its *inputs* (one SHA-256)
and records every installed package version in the artifact manifest.

**Why not Buildroot/Yocto?** The requirement includes Chromium with Widevine and
a real package ecosystem. Neither offers a maintainable path to that on Pi 5
within this project's resources. Choosing them would trade a working product for
architectural purity.

## Boot and runtime chain

```
Pi 5 EEPROM bootloader (SPI, vendor)
  └─ FAT32 boot partition: config.txt, cmdline.txt, kernel_2712.img,
     bcm2712-rpi-5-b.dtb, overlays/
       └─ Linux 6.18 (vendor kernel, unmodified)
            └─ systemd (multi-user → graphical)
                 ├─ NetworkManager        (Ethernet/Wi-Fi, DHCP, DNS)
                 ├─ PipeWire + WirePlumber (HDMI/analog audio)
                 ├─ pivistad              (root, Unix socket, action allowlist)
                 ├─ pivista-firstboot     (hardware snapshot, one-shot)
                 └─ pivista-session       (UID 1000, PAM session, tty1)
                      └─ sway (kiosk config, no bar, no decorations)
                           ├─ pivista-launcher (Qt 6 / QML, fullscreen)
                           └─ chromium --app=<url> --kiosk (on demand)
```

### Why sway instead of a single-client kiosk compositor

A one-client compositor such as `cage` is simpler, but it cannot implement a
global **Home** key: once Chromium is focused, the remote's Home button goes to
Chromium, which ignores it, and the user is stuck in the browser. sway can bind
Home at the compositor level, close the streaming window and refocus the
launcher. `/usr/lib/pivista/home.sh` also sends a byte to the launcher's
user-only `pivista-home.sock`, so the QML screen resets and a native app is
closed as well. That behaviour is a core television requirement, so the small
extra configuration is justified.

No desktop environment, panel, file manager or terminal is installed for normal
use. A text console exists for boot messages, but the accounts are locked; there
is no interactive login. Recovery is by mounting the card offline or the
physical `init=/bin/bash` procedure in `recovery.md`. Optional remote support
runs two separate services: `ssh.service` for the non-sudo `support` account,
and `pivista-vnc.service`, which attaches `wayvnc` to the existing sway session
on `127.0.0.1:5900`. Both are disabled until the user enables them from
Settings; the launcher never holds a remote-access credential. See
[remote-access.md](remote-access.md).

### Privilege boundary

The launcher runs as `pivista` (UID 1000) and never as root. Everything that
requires privilege goes through `pivistad` over
`/run/pivista/control.sock`:

- socket is `root:pivista`, mode `0660`;
- `SO_PEERCRED` is checked; only UID 0 and UID 1000 may connect;
- a fixed action allowlist, no dynamic dispatch into the shell;
- all commands are argv lists (`subprocess.run([...])`, never `shell=True`);
- user-supplied values are validated against the live system before use;
- request parameters are never logged (they can contain Wi-Fi passwords);
- no network listener.

The UI performs unprivileged work itself: application discovery, launching
Chromium or a native app, favourites, settings persistence.

## Application model

| Kind | Source | Launch | Compatibility shown |
|---|---|---|---|
| Native | `.desktop` files in `/usr/share/applications`, `/usr/local/share/applications`, `~/.local/share/applications` | resolved executable + argv, no shell; `Terminal=true` entries rejected | `native` |
| Web | `/usr/share/pivista/webapps/catalog.json` + `~/.config/pivista/webapps.json` | Chromium `--app`, `--kiosk`, per-service profile, https only | `web` / `browser-drm-unverified` |
| Android | none shipped | — | `android.status` reports why |

Launching an app records it in "Recently opened". This is launch history, not
playback position: PiVista does not claim resume points without a provider or
player integration. Launch failure returns a message; an app is never marked
supported because its icon appeared before it launches.

## Data and persistence

| Data | Location | Survives update | Removed by factory reset |
|---|---|---|---|
| Launcher settings, favourites | `~/.config/PiVista/Launcher.conf` | yes | yes (reflash) |
| User web shortcuts | `~/.config/pivista/webapps.json` | yes | yes |
| Browser profiles | `~/.config/pivista/browser/<service>` | yes | yes |
| Diagnostics | `/var/lib/pivista/diagnostics/` | yes | yes |
| Hardware snapshot | `/var/lib/pivista/hardware.json` | yes | no (regenerated) |
| Build provenance | `/etc/pivista/` | image metadata, not replaced by launcher updates | yes |
| Launcher version | `/usr/share/pivista/version.json` | replaced by signed launcher update | yes |
| Previous launcher backup | `/var/lib/pivista/updates/rollback/` | root-owned, local rollback | yes |
| Logs | journald (bounded 96 MB) + `/var/log/pivista` | rotated | yes |

## Update layers

- **Launcher application** is updated from a signed GitHub release. It replaces
  only the binary, QML, curated catalog and version file, keeps a root-owned
  rollback copy, and never touches user settings or NetworkManager. See
  [updates.md](updates.md).
- **OS packages** remain on apt with their own signatures and no A/B rollback.
- **Full disk image** updates are not implemented: the current single-slot
  partition layout has no inactive root to write. A future A/B design using the
  Pi 5 `tryboot` flow and RAUC is investigated in [updates.md](updates.md), but
  it would require a new partition layout and a one-time migration.

## Known architectural limitations

- **No full-image A/B updates.** Package updates are transactional at the dpkg
  level only; a broken OS update requires reflashing. The signed launcher update
  is a separate, reversible channel and cannot repair a broken kernel or base
  image.
- **Widevine L3 only.** The CDM is a vendor package, not a certification.
- **Chromium is the streaming path.** No official native Linux clients exist for
  the major services; browser profiles are the legitimate fallback.
- **Pi 5 has no H.264 hardware decoder.** Any H.264 stream is CPU-decoded, which
  matters for 1080p streaming and is documented rather than hidden.
- **HDMI-CEC untested.** `cec-utils` is installed, but no CEC bridge is enabled
  by default because the Pi 5 CEC path was not verified on hardware.
- **Remote support is not a second session.** VNC mirrors the television and
  therefore shows whatever is on screen, including account prompts; SSH is a
  narrow support shell without sudo. Neither is a substitute for offline
  recovery.
