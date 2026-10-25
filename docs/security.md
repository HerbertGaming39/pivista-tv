# Security model

PiVista TV is a single-user television appliance. It stores Wi-Fi credentials and
streaming sessions, so the security model is deliberately conservative: few
services, no remote administration, one narrow privileged interface.

## Trust boundaries

| Component | Runs as | Trust | Can do |
|---|---|---|---|
| Linux kernel, systemd, NetworkManager, PipeWire, sway | root/daemons | trusted vendor software | system |
| `pivistad` | root | trusted project code, narrow API | network, audio, display, apt, power |
| `pivista-launcher` | `pivista` (1000) | untrusted UI | read catalog, launch user apps, write own config |
| Chromium | `pivista` | untrusted web content | browser sandbox, own profile |
| Native apps | `pivista` | third-party | same as the user |
| Network | untrusted | — | no inbound services |

## The privileged interface

`/run/pivista/control.sock`:

- directory `0750 root:pivista`, socket `0660 root:pivista`;
- `SO_PEERCRED` must report UID 0 or the configured session UID (1000);
- newline-delimited JSON, 64 KiB maximum request;
- fixed action allowlist (`pivistad.ControlService._handlers`);
- every command is an argv list; `shell=True` is never used;
- SSIDs, timezones, sink names, modes and hostnames are validated against the
  live system (e.g. the requested audio sink must already exist);
- power actions require `confirm: true` and are rate-limited;
- requests are logged by action name only; parameters can contain Wi-Fi
  passwords and are never written to logs;
- malformed JSON, unknown actions and non-object parameters are rejected.

What it deliberately cannot do: read arbitrary files, run arbitrary commands,
open a listening socket, change kernel modules or boot parameters, or return
browser/session data.

## Accounts and passwords

- `pivista` is created with UID/GID 1000, a locked password (`!`) and a normal
  shell for diagnostics on tty2/console.
- The stock `pi` account is removed.
- Root login is not enabled; `openssh-server` is purged from the image and SSH units are masked.
- The WiFi password is handed to NetworkManager, which stores it in
  `/etc/NetworkManager/system-connections/*` with mode 0600 (root only). It is
  passed to `nmcli` as an argv element for the duration of the connection, not
  written by PiVista to disk. This is a known local-process observation window;
  the device is single-user and has no remote login.
- No default password is baked into the image.

## Data at rest

| Data | Location | Permissions |
|---|---|---|
| Launcher settings | `~/.config/PiVista/Launcher.conf` | user |
| Browser profiles (cookies, sessions) | `~/.config/pivista/browser/` | user `0700` |
| User web shortcuts | `~/.config/pivista/webapps.json` | user |
| Diagnostics | `/var/lib/pivista/diagnostics/` | `0644` (local only) |
| Wi-Fi PSK | NetworkManager keyfile | `0600 root` |
| Build provenance | `/etc/pivista/` | `0644` |

`Settings → Privacy and security → Clear browser data` removes all profiles.

## Logging

- journald is bounded (`SystemMaxUse=96M`, 2-week retention) so logs cannot fill
  the card.
- `/var/log/pivista` rotates weekly, 3 copies, compressed.
- Diagnostics are local JSON files; nothing is uploaded. The UI states this.

## Updates

- apt sources are the ones baked into the pinned base image (`deb.debian.org`,
  `archive.raspberrypi.com`), verified by Debian/Raspberry Pi archive keys.
- The update action does not accept package names or URLs from the UI.
- Downloads are verified by apt's signature checks.
- There is **no signed PiVista update channel** and **no rollback**. A compromised
  Debian/Raspberry Pi archive key is outside this project's threat model.
- A failed update is recovered by reflashing; see `recovery.md`.

## What is not protected

- A person with physical access and the SD card can read browser profiles and
  Wi-Fi credentials. Full-disk encryption is not implemented.
- The launcher runs third-party web content; Chromium's sandbox is the boundary.
- Native `.desktop` entries in the user's own directory are executed as that
  user. They are not sandboxed. Only install software you trust.
- HDMI-CEC, if enabled later, would add an input path that must be reviewed.

## Hardening defaults in the image

- No SSH server; no remote shell. `openssh-server` is purged and its units masked.
- Vendor `userconfig.service` and `sshswitch.service` are masked; PiVista's own wizard owns first boot.
- No inbound listening services from PiVista.
- `kernel.dmesg_restrict=1`.
- systemd service sandboxing for `pivistad`: private `/tmp`, read-only home,
  restricted address families, capability bounding set, `NoNewPrivileges`.
- Build-time scan for private keys and cloud tokens; image validation repeats a
  credential scan.
