# Remote support: SSH and VNC

PiVista TV ships an SSH server and a VNC server, but **neither is enabled on a
new image**. They are switched on from **Settings → Remote support** when you
need help; turning them off again stops the service and locks the support
account.

This is optional remote support, not a second desktop session. The television
UI remains the only session, and VNC mirrors it.

## Security model

- The kiosk account `pivista` stays locked. It has no SSH login.
- Root stays locked. `PermitRootLogin no`.
- A separate `support` account exists with **no sudo**, no PiVista group
  membership and no access to the browser profile.
- SSH is password-only for `support`. The password is 20 random characters,
  generated on the device when SSH is enabled, shown on the TV, and stored in
  `/etc/pivista/remote/ssh-password` (root-only, `0600`).
- SSH host keys are generated on the device at first enable. They are **not**
  included in the downloadable image, so two PiVista cards do not share them.
- VNC listens only on `127.0.0.1:5900`. It is not reachable from the LAN
  directly; use an SSH local port forward.
- Disabling SSH runs `passwd --lock support` and deletes the password file.
- Do not enable remote access on an untrusted network. The random password is
  visible to anyone who can see the television screen while the page is open.

The previous release deliberately had no SSH server. This build changes that
trade-off: the server is installed but disabled, and only the narrow `support`
account can authenticate.

## Enable SSH

1. Open **Settings → Remote support**.
2. Choose **Enable SSH** and confirm.
3. The page shows the address and a password such as `k7M...`. Use them within
   the same local network:

```bash
ssh support@192.168.1.42
```

On Windows 10/11, `ssh` is part of the OpenSSH Client optional feature. On
macOS and Linux it is already installed. Accept the host-key fingerprint on the
first connection and verify it if you need to.

Use **New SSH password** to replace the password. Existing sessions remain
connected until they close. **Disable SSH** stops the service and locks the
account.

The `support` user has no sudo and cannot modify the image. It can inspect
processes, read its own home and use local port forwarding, which is all the VNC
tunnel needs.

## Enable VNC

VNC requires SSH because it binds to loopback only.

1. Enable and keep SSH enabled.
2. Choose **Enable VNC** on the same page.
3. On your computer, open a tunnel and keep it running:

```bash
ssh -L 5900:127.0.0.1:5900 support@192.168.1.42
```

4. Point a VNC viewer at `127.0.0.1:5900` (not at the Pi's LAN address).

Examples: TigerVNC Viewer, RealVNC Viewer or Remmina. The VNC server has no
separate VNC password because the SSH tunnel already authenticates and encrypts
the connection. If the SSH window closes, VNC disconnects.

**Disable VNC** stops the VNC service but leaves SSH enabled.

## Why VNC is localhost-only

Exposing an unauthenticated VNC port to the LAN would let anyone who can reach
the television control it. `wayvnc`'s direct authentication requires a TLS
certificate and password configuration; the SSH tunnel is simpler, works with
ordinary clients, and reuses the audited SSH account. If you need direct VNC,
run your own server rather than opening this one.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `ssh: connect to host ... port 22: Connection refused` | SSH is not enabled; check Settings → Remote support. Confirm the Pi and computer are on the same network. |
| `Permission denied (publickey,password)` | Use `support`, not `pivista`; copy the password exactly; rotate it if needed. |
| VNC viewer says connection refused | The SSH tunnel is not running, or VNC is disabled. The viewer must connect to `127.0.0.1:5900`. |
| VNC is black or disconnects | The sway session may be restarting. Check the TV, then retry. |
| SSH works but VNC service will not start | `pivista-vnc.service` needs the graphical session. Check **Settings → System → logs**, or journal `pivista-vnc.service`. |
| Host key changed after a reflash | Expected: host keys are generated per device/install. Remove the old entry from `known_hosts` after verifying you reflashed the card. |
| Need to copy a file | SSH/SFTP works as `support`; it cannot read `/home/pivista` or `/etc/shadow`. |

Useful commands on the Pi (from a local console or SSH as `support`):

```bash
systemctl status ssh.service pivista-vnc.service
journalctl -u ssh.service -u pivista-vnc.service -n 80 --no-pager
ss -ltnp | grep -E ':(22|5900)\b'
```

`ss` may hide process names from the unprivileged support account; the listening
addresses are still visible.

## What is still not implemented

- No direct VNC listener on the LAN.
- No VNC audio forwarding.
- No SSH key enrollment UI; the generated password is the supported route.
- No remote power control; use the normal Settings power actions on the TV.
- No support account access to PiVista settings or the browser profile.
- Hardware testing of SSH/VNC on a physical Pi 5 is still required. The services
  are installed and unit-tested in the image, but no claim is made that they have
  been exercised over a real network yet.
