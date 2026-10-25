# Recovery and troubleshooting

PiVista TV has no SSH and no remote shell by design. The `pivista` and `root`
accounts are locked, so there is **no usable interactive login** on the HDMI
text console or the serial console. Those consoles are for watching boot
messages; recovery is offline access to the card or a reflash.

## The system will not boot

1. **Check the obvious.** Official 27 W supply, HDMI in the TV's active input,
   card fully inserted, EEPROM boot order allows the card/USB device.
2. **Watch the boot.** Connect a screen; a Pi 5 with no bootable media shows the
   bootloader diagnostics page. Note the error code.
3. **Try a known-good card.** If Raspberry Pi OS boots, the PiVista media is the
   problem.
4. **Reflash.** This is the supported recovery path:

   ```bash
   xz -dc pivista-tv-0.3.1-pi5-arm64.img.xz | \
     sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   ```

   Then verify the SHA-256 of the `.img.xz` against the `.sha256` file first.

## The UI does not appear (black screen, cursor, or console text)

1. **Do not expect Ctrl+Alt+F2 to give a shell.** It may show the boot console,
   but both accounts are locked. The launcher shows a `swaynag` error banner
   after three rapid failures, pointing at the journal.
2. Mount the card on another Linux computer and read the journal:

   ```bash
   sudo mount /dev/sdX2 /mnt
   sudo journalctl -D /mnt/var/log/journal --no-pager -n 200
   cat /mnt/etc/pivista/build-provenance.txt
   ```

3. Common causes:
   - **No HDMI mode**: edit `config.txt` on the boot partition (FAT32) and add
     `hdmi_force_hotplug=1` or a `hdmi_group`/`hdmi_mode` pair, then reboot.
   - **GPU/driver failure**: add `PIVISTA_SOFTWARE_RENDER=1` to
     `/etc/pivista/session.conf` (needs the root partition mounted) to force the
     software renderer.
   - **sway fails to start**: check `pivista-session.service` in the journal;
     `WLR_RENDERER=pixman` is the fallback.

### Physical emergency shell

If you have the card and a USB keyboard, you can boot a root shell without a
password. This bypasses the appliance's security; revert it afterwards.

1. Mount the FAT32 boot partition on any computer.
2. Append ` init=/bin/bash` to the single line in `cmdline.txt`.
3. Boot the Pi with HDMI and a USB keyboard. You get a root shell before the
   normal services start.
4. `mount -o remount,rw /` before editing files.
5. Remove `init=/bin/bash` from `cmdline.txt` and reboot when finished.

This is an offline/physical-access recovery path, not a supported login.

## The setup wizard is on screen but keys do nothing

This is nearly always an input-path problem, not a frozen launcher.

1. **A television remote alone will not work.** The LG/Samsung/etc. remote
   talks to its own TV over HDMI-CEC. `cec-utils` is present, but this release
   does not run a CEC-to-keyboard bridge, so the Pi never sees those buttons.
   Use a USB keyboard, a USB/IR remote, or a USB receiver.
2. **Plug the keyboard into the Pi, not the television.** A keyboard in the
   TV's USB port controls the TV. A Bluetooth keyboard also cannot be used:
   the image has no Bluetooth pairing screen. A wireless keyboard with its own
   USB dongle is fine; put the dongle in the Pi.
3. **Give a hot-plugged keyboard a moment.** 0.3.1 focuses the wizard
   automatically, but USB enumeration can take a few seconds after the picture
   appears. If keys still do nothing, press **Home** once (the sway binding
   also focuses the launcher), then **Escape** once, then use the arrows and
   Enter. On 0.3.0, Escape is what moves focus from the overlay to the visible
   button list; 0.3.1 also moves it on activation.
4. **Check that the Pi sees the keyboard.** Press **Ctrl+Alt+F2**. A text login
   prompt appearing proves the keyboard reaches the Pi (the accounts are
   locked, so you cannot log in). If nothing appears, try another USB port, a
   wired keyboard, and boot with the keyboard already connected. Prefer a
   direct Pi USB-A port over an unpowered hub.

5. **Blank/black screen instead?** See the previous section; that is a display
   or compositor failure, not input.

PiVista deliberately has no SSH server. An address that worked for an earlier
Raspberry Pi OS card is not reachable after that card is replaced. If you want
to check focus behaviour before flashing, run the production launcher in the
[Windows/WSLg preview](windows-preview.md).

## The launcher crashes or restarts in a loop

`pivista-session.service` restarts sway if sway itself exits, and
`launcher-loop.sh` retries the launcher indefinitely. After three rapid failures
the loop displays a `swaynag` error banner with the journal command; it keeps
retrying rather than silently giving up. The journal contains the Qt error.
Typical causes: a missing QML module, a corrupted
`~/.config/PiVista/Launcher.conf`, or a full disk.

Reset the launcher configuration by mounting the root partition and removing:

```
/home/pivista/.config/PiVista/Launcher.conf
/home/pivista/.config/pivista/
```

The next boot shows the first-run wizard.

## Wi-Fi will not connect

- Open **Settings → Network → Scan for Wi-Fi networks**.
- A wrong password returns an error in the password dialog; there is no silent
  failure.
- Ethernet always takes precedence when connected.
- Hidden networks are not listed. There is no console account to run `nmcli`;
  add a connection file under `/etc/NetworkManager/system-connections/` while
  the card is mounted, or use the emergency shell described above.
- `pivistad` logs the *action*, not the password.

## No audio

1. **Settings → Audio**: choose the HDMI sink, raise volume, play the test tone.
2. Ensure the TV input is the Pi's HDMI port and the TV volume is up.
3. From the emergency shell or an offline mount, inspect
   `pactl list sinks short` / `wpctl status`; there is no normal console login.
4. Restart the audio stack: `systemctl --user restart pipewire wireplumber`
   requires the graphical user session; the appliance session already owns it.

## Storage full

journald is capped at 96 MB and logs rotate. Browser profiles and diagnostics are
the usual growth. Remove browser data from Settings, delete diagnostics in
`/var/lib/pivista/diagnostics/`, or reflash. The image does not auto-delete user
data.

## A package update failed

There is **no automatic rollback**. The system may be left partially updated.

1. Reboot; if the UI returns, retry the update and read
   `/var/log/pivista/update.log`.
2. If it does not boot, reflash the last known-good image. User data on the root
   partition is lost unless you copy it off first.

To copy data before reflashing, mount the card on a Linux computer and copy
`/home/pivista/.config/` and `/var/lib/pivista/`.

## A launcher update failed

Launcher updates are independent of apt and have their own rollback copy. The
update is only offered after its signed manifest and archive checksum verify.

- **Download failed or was interrupted:** the `.part` file is removed and the
  installed launcher is untouched. Retry from **Settings → Updates**.
- **Install failed:** the updater restores the backup automatically and reports
  the error. If the launcher still starts, open **Settings → Updates** and use
  **Roll back to previous launcher** if a backup is listed.
- **Power was lost during install:** `pivistad` marks the interrupted job as
  failed on next start. Check the displayed launcher version. If it is the old
  version, retry. If it is the new version and the UI starts, no action is
  needed; the previous launcher backup remains available for rollback.
- **The launcher will not start after an update:** use the physical recovery
  path below or mount the card. The backup copy is under
  `/var/lib/pivista/updates/rollback/`; its `backup.json` names the version.
  Restore `launcher`, `qml/`, `catalog.json` and `version.json` to
  `/usr/bin/pivista-launcher`, `/usr/share/pivista/qml`,
  `/usr/share/pivista/webapps/catalog.json` and
  `/usr/share/pivista/version.json`, then reboot. This is a manual root-level
  operation; keep the card offline while doing it.
- **The update is offered but the UI says the image is too old:** the launcher
  update requires a newer system image. Back up user data and reflash the image;
  the updater deliberately refuses to install across an incompatible base.

Do not delete `/var/lib/pivista/updates/rollback/` while diagnosing a failed
launcher update. It is not user data; it is the last known-good application.

## Factory reset

There is no in-place factory reset that preserves the OS. "Reset" means
reflashing the image, which removes the system, settings, browser profiles and
logs. This works offline and does not require an account.

## Reporting a problem

Use **Settings → System → Export diagnostics**. It writes a local JSON file with
build provenance, hardware snapshot, system state and redacted logs. It does not
upload anything; copy it off the device yourself. Review it before sharing: it
contains the device serial and network addresses.
