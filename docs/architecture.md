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
launcher. That behaviour is a core television requirement, so the small extra
configuration is justified.

No desktop environment, panel, file manager or terminal is installed for normal
use. A text console remains available on tty2 for recovery.

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

Launching an app records it in "Continue". Launch failure returns a message; an
app is never marked supported because its icon appeared.

## Data and persistence

| Data | Location | Survives update | Removed by factory reset |
|---|---|---|---|
| Launcher settings, favourites | `~/.config/PiVista/Launcher.conf` | yes | yes (reflash) |
| User web shortcuts | `~/.config/pivista/webapps.json` | yes | yes |
| Browser profiles | `~/.config/pivista/browser/<service>` | yes | yes |
| Diagnostics | `/var/lib/pivista/diagnostics/` | yes | yes |
| Hardware snapshot | `/var/lib/pivista/hardware.json` | yes | no (regenerated) |
| Build provenance | `/etc/pivista/` | replaced by update | yes |
| Logs | journald (bounded 96 MB) + `/var/log/pivista` | rotated | yes |

## Known architectural limitations

- **No A/B updates.** Package updates are transactional at the dpkg level only.
  A broken update requires reflashing. Adding A/B would require a different
  partition scheme and a signed update service; it is out of scope for 0.1.
- **Widevine L3 only.** The CDM is a vendor package, not a certification.
- **Chromium is the streaming path.** No official native Linux clients exist for
  the major services; browser profiles are the legitimate fallback.
- **Pi 5 has no H.264 hardware decoder.** Any H.264 stream is CPU-decoded, which
  matters for 1080p streaming and is documented rather than hidden.
- **HDMI-CEC untested.** `cec-utils` is installed, but no CEC bridge is enabled
  by default because the Pi 5 CEC path was not verified on hardware.
