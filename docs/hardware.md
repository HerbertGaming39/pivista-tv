# Raspberry Pi 5 hardware notes and validation protocol

For the first-boot checklist, use [hardware-test.md](hardware-test.md). This
file records platform facts and the deeper measurement protocol.

## Platform facts relevant to this product

| Item | Fact | Consequence |
|---|---|---|
| SoC | Broadcom BCM2712, 4× Cortex-A76 | amd64 image build requires qemu-user for arm64 packages |
| GPU | VideoCore VII / V3D 7.1, Mesa | sway + Qt Quick use GLES via Mesa; `WLR_RENDERER=pixman` is the fallback |
| Video decode | HEVC/H.265 hardware block via V4L2 stateless; **no H.264 block** | H.264 web streams are CPU-decoded; do not claim hardware acceleration |
| Audio | HDMI audio via vc4-hdmi; no analog jack | PipeWire exposes HDMI sinks; test tone verifies routing |
| Boot | EEPROM/SPI bootloader, FAT32 boot partition, `kernel_2712.img` | the image keeps the vendor boot layout; a plain flash boots |
| Storage | microSD or USB (PCIe) SSD | root partition grows on first boot; USB SSD is faster and recommended |
| Network | Gigabit Ethernet, dual-band Wi-Fi | Ethernet takes precedence in the UI |
| CEC | present in the platform, **not verified here** | no CEC bridge is enabled by default |
| Power | USB-C PD, 5 A supply recommended | under-voltage is reported by `vcgencmd get_throttled` |

## Baseline measurements (to be filled on hardware)

No physical Pi 5 was available to the build host, so this table is intentionally
empty. Do not replace it with estimates.

| Metric | How to measure | Result |
|---|---|---|
| Cold boot to launcher | stopwatch / `systemd-analyze` + journal timestamps | — |
| Launcher start time | `systemd-analyze` / `pivistad` log timestamps | — |
| Idle CPU | `top -b -n 60`, 1-minute average | — |
| Idle memory | `free -m` after 10 min idle | — |
| Navigation latency | keypress-to-focus, visual + `QT_LOGGING_RULES` | — |
| Playback CPU (1080p H.264) | `pidstat -p $(pidof chromium) 1 60` | — |
| Playback CPU (1080p HEVC) | same, note V4L2 device in use | — |
| Temperature under playback | `cat /sys/class/thermal/thermal_zone0/temp` | — |
| Throttling | `vcgencmd get_throttled` | — |
| Wi-Fi reconnect after AP reboot | manual, note time | — |
| 10 reboot loop | scripted power cycle | — |

## Validation protocol

### 1. Boot and first run

1. Flash the image, insert, connect HDMI and a USB keyboard.
2. Capture the serial console or photograph the screen at boot.
3. Confirm the wizard appears; complete it with keyboard only (no mouse).
4. Reboot; confirm the wizard does not reappear and the home screen loads.
5. Re-run the wizard from Settings and cancel; confirm settings are unchanged.

### 2. Display

1. At 1080p, confirm the UI is fully visible with margins intact.
2. Switch to 720p in Settings → Display; confirm the UI rescales and focus is
   still reachable.
3. Switch back to 1080p. Confirm a wrong/unsupported mode is rejected with a
   message rather than a black screen.
4. Set interface size to 125%; confirm no clipping of Settings rows.

### 3. Audio

1. Settings → Audio → Play test sound; confirm it comes from the TV speakers.
2. Change output between HDMI sinks (if more than one); confirm routing.
3. Play a video with audio; confirm no crackle and correct sync.
4. Mute/unmute from the remote; confirm the quick panel reflects the state.

### 4. Network

1. Ethernet: confirm IP, DNS and a connectivity test.
2. Wi-Fi: scan, join a WPA2 network using only the remote and on-screen keyboard.
3. Enter a wrong password; confirm an error is shown and the dialog stays open.
   There is no console login; use the emergency shell in `recovery.md` if you
   need to inspect NetworkManager directly.
4. Disconnect; confirm the UI reports offline and does not hang.
5. Reboot; confirm reconnection and correct time via NTP.

### 5. Input

1. Arrow/Enter/Back/Home on a USB keyboard.
2. A USB IR remote: confirm standard key codes work. Bluetooth hardware is
   present and BlueZ runs, but there is no pairing UI in this release; record it
   as a limitation rather than treating a USB dongle as Bluetooth input.
3. A game controller: confirm it appears in `evtest`; document unmapped buttons.
4. Home while Chromium is fullscreen: confirm it closes the web app and returns
   to the launcher (sway binding).
5. Volume keys while Chromium is focused: confirm they change PipeWire volume.
6. HDMI-CEC (only if testing it): enable `cec-utils`, confirm whether the TV
   remote reaches the Pi; record the result honestly.

### 6. Media and decode

1. Play a local H.264 1080p file with `ffplay`/GStreamer and record CPU.
2. Play a local HEVC 1080p file; check `v4l2-ctl --list-devices` and whether a
   hardware decoder is selected (`ffmpeg -hwaccel drm` on the Pi build).
3. Record dropped frames and temperature. Do not equate low CPU with hardware
   decode.

### 7. Reliability

1. Ten consecutive boots.
2. Kill the launcher (`systemctl restart pivista-session`); confirm recovery.
3. Fill the storage to <200 MB; confirm the UI reports it and logs do not grow.
4. Interrupt an update (pull power during download) and document the state.
5. Power loss during playback; confirm the filesystem recovers (`fsck`).

## Reporting

Record the image build ID (`/etc/pivista/build-provenance.txt`), kernel, firmware
version (`vcgencmd version`), display model, and every observation with a date.
Attach diagnostics from Settings → System → Export diagnostics. Update
`STATUS.md` only with results you actually observed.
