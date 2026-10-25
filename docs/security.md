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

- `pivista` is created with UID/GID 1000 and a locked password (`!`). Its shell
  field is `/bin/bash`, but a locked password means there is **no interactive
  login** on tty2, the serial console or any other terminal. The shell field is
  only used by the systemd session and by offline recovery.
- Root is locked (`*`) and has no login.
- The stock `pi` account is removed. **cloud-init is disabled** and its seed
  files are removed; otherwise the Raspberry Pi OS cloud-init default would
  recreate `pi` with passwordless sudo on first boot, after the image build had
  removed it. The cloud-init units are masked and `/etc/cloud/cloud-init.disabled`
  is present. This is checked by image validation.
- `regenerate_ssh_host_keys.service` is masked so a first boot cannot recreate
  `/etc/ssh` host keys. `openssh-server` is purged and SSH units are masked.
- The WiFi password is handed to NetworkManager, which stores it in
  `/etc/NetworkManager/system-connections/*` with mode 0600 (root only). It is
  passed to `nmcli` as an argv element for the duration of the connection, not
  written by PiVista to disk. This is a known local-process observation window;
  the device is single-user and has no remote login.
- No default password is baked into the image. Do not expect a login prompt to
  be usable; recovery is an offline operation (see `recovery.md`).

## Data at rest

| Data | Location | Permissions |
|---|---|---|
| Launcher settings | `~/.config/PiVista/Launcher.conf` | user |
| Update state and rollback copies | `/var/lib/pivista/updates/` | root `0700` |
| Update public key | `/etc/pivista/update-pubkey.pem` | root `0644`, not group/other writable |
| Browser profiles (cookies, sessions) | `~/.config/pivista/browser/` | user `0700` |
| User web shortcuts | `~/.config/pivista/webapps.json` | user |
| Diagnostics | `/var/lib/pivista/diagnostics/` | directory `0755`; JSON file `0644` (local only; contains device serial and network addresses) |
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
- The package update action does not accept package names or URLs from the UI.
  Package downloads are verified by apt's signature checks. There is **no
  automatic package rollback**; a failed package update is recovered by
  reflashing. See `recovery.md`.
- Launcher updates are a separate signed channel. The manifest must verify with
  the root-owned Ed25519 public key at `/etc/pivista/update-pubkey.pem`; the
  archive must match the SHA-256 in that signed manifest. HTTPS is enforced and
  redirects are limited to GitHub hosts.
- The privileged daemon owns the update directory and performs the swap. The
  unprivileged launcher cannot supply a URL, script, archive path or destination.
- The downloaded archive is data, not an installer. Only fixed paths are
  accepted from it; scripts are never executed.
- The previous launcher binary, QML, catalog and version file are copied to a
  root-owned rollback directory before the swap. **Launcher** rollback is
  implemented. **Full OS image** A/B updates and automatic package rollback are
  not.
- A compromised Debian/Raspberry Pi archive key, or a compromised GitHub account
  plus the offline signing key, is outside this project's threat model. See
  [updates.md](updates.md) for the complete release and verification procedure.

## What is not protected

- A person with physical access and the SD card can read browser profiles and
  Wi-Fi credentials. Full-disk encryption is not implemented.
- The launcher runs third-party web content; Chromium's sandbox is the boundary.
- Native `.desktop` entries in the user's own directory are executed as that
  user. They are not sandboxed. Only install software you trust.
- HDMI-CEC, if enabled later, would add an input path that must be reviewed.

## Hardening defaults in the image

- No SSH server; no remote shell. `openssh-server` is purged and its units masked.
- Vendor `userconfig.service`, `sshswitch.service` and the whole cloud-init
  stack are masked; PiVista's own wizard owns first boot. Cloud-init seed files
  are removed from the boot partition.
- `regenerate_ssh_host_keys.service` is masked; `/etc/ssh` stays absent.
- No inbound listening services from PiVista.
- `kernel.dmesg_restrict=1`.
- systemd service sandboxing for `pivistad`: private `/tmp`, read-only home,
  restricted address families, capability bounding set, `NoNewPrivileges`.
- Build-time scan for private keys and cloud tokens; image validation repeats a
  credential scan and checks the cloud-init/SSH masks.

## Local recovery boundary

The locked accounts are a deliberate trade-off: a television does not need an
interactive shell, and a passwordless one would be a local privilege path. An
owner with physical access can still recover by mounting the card on another
computer or by appending `init=/bin/bash` to `cmdline.txt` on the FAT32 boot
partition, then reverting that change. That is a physical-access boundary; full
disk encryption is not implemented.
