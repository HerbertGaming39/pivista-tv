# Raspberry Pi 5 hardware test checklist

Use this for the first boot of the release image on a **Raspberry Pi 5 (8 GB)**
with a television. Record what you actually see; do not mark an item passed
because the screen looked plausible once.

## Before flashing

- [ ] Image: `pivista-tv-0.2.0-pi5-arm64.img.xz` from the v0.2.0 GitHub
      release or `releases/` after a local build.
- [ ] Compare the SHA-256 with the adjacent `.img.xz.sha256` file and the value
      published in the release notes (Windows `Get-FileHash`, Linux
      `sha256sum -c`). Do not flash if they differ.
- [ ] Use a known-good microSD (A2 recommended) or USB SSD, at least 8 GB.
- [ ] Official 27 W USB-C supply, HDMI cable, USB keyboard or remote.
- [ ] Flash with Raspberry Pi Imager or balenaEtcher. Do **not** apply Imager OS
      customisation (hostname, user, SSH, Wi-Fi); PiVista owns first boot.
- [ ] Eject safely and insert the card with the Pi powered off.

## First boot

- [ ] Power on. Record the time until the PiVista wizard appears.
      First boot grows the root filesystem, so it is slower than later boots.
- [ ] No `pi` login prompt, SSH banner or account dialog appears.
- [ ] The 1920×1080 wizard is fully visible; no overscan clipping at the edges.
- [ ] Arrow keys / D-pad move focus; Enter/OK selects; Escape/Back returns.
- [ ] Complete the wizard: language/time zone, network (or skip), display,
      audio, remote notes, privacy, summary.
- [ ] The home screen appears after **Start using PiVista TV**.
- [ ] Reboot. The wizard does not reappear; the home screen returns.

## Display and audio

- [ ] HDMI output is stable at 1080p; no flicker or blank mode switch.
- [ ] Settings → Display lists the detected output and modes.
- [ ] Switch to 720p and back; the interface scales instead of clipping.
- [ ] Set interface size 125%; Settings rows remain reachable.
- [ ] Settings → Audio → Play test sound is audible from the TV.
- [ ] HDMI sink is selected; volume up/down and mute work from the remote.

## Network

- [ ] Ethernet: IP address appears; connectivity test succeeds.
- [ ] Wi-Fi: scan lists networks; join a WPA2 network using only the remote.
- [ ] Wrong Wi-Fi password: an error is shown and the dialog stays open.
- [ ] Reboot: the network reconnects and the clock is correct (NTP).

## Input and Home

- [ ] USB keyboard: arrows, Enter, Escape and Home work.
- [ ] USB or IR remote with standard key codes works without mapping.
- [ ] A game controller appears in `evtest`; record unmapped buttons.
- [ ] Bluetooth: record that this release has no pairing UI. If a device was
      paired by hand, confirm it reconnects and its keys work.
- [ ] Launch a web app; press **Home** while Chromium is fullscreen.
      The streaming window closes and the launcher returns to Home.
- [ ] Launch a native app; press **Home**. The app closes and Home returns.
- [ ] Press Home twice quickly; the UI does not get stuck or double-launch.

## 0.2 interface

- [ ] Home shows the featured banner, **Your apps**, **Streaming** and
      **Installed applications** rows without overlapping or blank content.
- [ ] **Games** opens and shows a clear empty state when no game is installed.
- [ ] **Media** opens with the streaming row visible (not a blank page); a
      launch of a shortcut adds it to **Recently opened** on Home and Media.
- [ ] Pressing Down from the top navigation lands on the featured banner; Enter
      opens it; Down again reaches the first row.
- [ ] **Apps → I** opens details; favourite/hide changes are reflected on Home.
- [ ] Settings → Appearance changes theme, wallpaper, row visibility, start
      screen and 12/24-hour clock; each change applies without a restart.
- [ ] Back/Backspace and Escape both return to the previous screen or Home.

## Settings and power

- [ ] Settings → Network / Display / Audio / Applications / System all open.
- [ ] Settings → System shows model, kernel, uptime, temperature, memory and
      storage; **Export diagnostics** writes a local JSON file.
- [ ] Settings → Privacy and security shows Android as unsupported and clears
      browser data only after confirmation.
- [ ] Quick panel (F10/Menu) opens; volume and mute update.
- [ ] Shutdown powers the board off cleanly; power button does the same.
- [ ] Reboot returns to the home screen without a wizard.

## Streaming (record, do not assume)

For each service you can test:

- [ ] Shortcut opens the service in Chromium.
- [ ] Sign-in result and any error text.
- [ ] Catalogue visible.
- [ ] Unprotected playback starts.
- [ ] Protected playback starts, or the DRM error code is recorded.
- [ ] Player-reported resolution (not the HDMI mode).
- [ ] Audio sink and sync.
- [ ] Decoder/CPU evidence: `v4l2-ctl --list-devices`,
      `chrome://media-internals`, `pidstat -p $(pidof chromium) 1 60`.
- [ ] 10-minute stability; temperature and `vcgencmd get_throttled`.

Prime Video on Linux is expected to be SD under Amazon's published rule.
Do not claim 1080p protected playback without a real player readout.

## Recovery checks

- [ ] Read the journal by mounting the card on another Linux computer:
      `journalctl -D /mnt/var/log/journal -b`.
- [ ] Confirm `/etc/pivista/build-provenance.txt` contains the build ID.
- [ ] Confirm there is no `/etc/ssh` directory and no `pi` account.
- [ ] Reflash once; confirm the wizard runs again and old settings are gone.

## Report

Copy the output of:

```bash
cat /etc/pivista/build-provenance.txt
uname -a
vcgencmd version
vcgencmd measure_temp
vcgencmd get_throttled
```

Attach the diagnostics JSON from Settings → System. Include the television
model, HDMI mode, remote/keyboard model and every failed item. Update
`STATUS.md` only with observations you actually made.
