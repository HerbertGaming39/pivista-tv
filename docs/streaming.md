# Streaming and DRM compatibility

**Status of every entry below: untested on this build.** No streaming account,
television or Raspberry Pi 5 was available to the build host. The matrix is a
test plan with honest placeholders, not a result set.

## The six separate questions

"Netflix works" is meaningless without separating:

1. Does the shortcut/browser open? (launcher)
2. Can the user sign in? (service + browser)
3. Is the catalogue visible? (service + region)
4. Does unprotected video play? (codec + browser)
5. Does **protected** video play? (Widevine + provider policy)
6. At what resolution, with what audio and decoder? (provider + hardware)

PiVista TV reports these separately in Settings and never upgrades an entry
because a page loaded.

## Method available per service

| Service | Method | Account needed | Notes |
|---|---|---|---|
| Netflix | Chromium kiosk (`https://www.netflix.com/`) | yes | Widevine L3 path only |
| Disney+ | Chromium kiosk | yes | Provider Linux policy varies |
| YouTube | Chromium kiosk | optional | Mostly unprotected |
| Prime Video | Chromium kiosk | yes | DRM |
| Max | Chromium kiosk | yes | DRM |
| TVP VOD | Chromium kiosk | optional | Polish public broadcaster |
| Player | Chromium kiosk | yes | Polish commercial |
| Canal+ | Chromium kiosk | yes | Polish subscription |
| Polsat Box Go | Chromium kiosk | yes | Polish subscription |
| Apple TV+ | Chromium kiosk | yes | Apple Account |
| Twitch | Chromium kiosk | optional | Unprotected live |

There are **no official native Linux desktop clients** for Netflix or Disney+.
Any "native" Linux client is a web wrapper and does not change the DRM stack.

## Widevine on 64-bit Raspberry Pi OS

- Raspberry Pi OS's Chromium build can load the vendor `libwidevinecdm0` package,
  which is the **software (L3)** CDM. It is not a certification and not L1.
- Widevine L1 requires factory-provisioned, hardware-rooted keys. A Raspberry Pi
  is not a certified Widevine device; installing a CDM does not create L1.
- Providers may cap resolution based on browser identity, device certification,
  codec, account plan and region. A 1080p HDMI mode says nothing about the
  stream's resolution.

Consequence: **do not expect 1080p protected playback**, and do not claim it.
720p is the conservative expectation; 1080p is possible but unverified.

## Raspberry Pi 5 video decode facts

| Codec | Hardware decode on Pi 5 | Result |
|---|---|---|
| HEVC / H.265 | Yes (V4L2 stateless `rpi-hevc-dec`) | Kernel 6.18 + GStreamer support; Chromium integration not established |
| H.264 / AVC | **No** | CPU decode; matters for many web streams |
| AV1 | No | CPU decode; 4K60 is not viable |
| VP9 | No dedicated block | CPU decode |

The absence of an H.264 hardware decoder is the single most important hardware
fact for streaming on this board. Low CPU usage alone is not evidence of
hardware decoding.

## Test protocol (run on a real Pi 5)

For each service, record:

1. Image build ID and Chromium version (`chromium --version`).
2. Shortcut opens; screenshot of the service.
3. Sign-in result (success/failure, error text).
4. Catalogue visible.
5. Play a known title; does video start?
6. Protected playback: does it start, or is there a DRM error code?
7. Observed resolution: use the player's "stats for nerds" and the provider's
   quality indicator, **not** the window size. Record the selected quality.
8. Audio: `pactl list sinks short` while playing; confirm HDMI sink and no
   crackling/dropouts.
9. Decoder: `v4l2-ctl --list-devices`, `top`/`pidstat` CPU during playback, and
   Chromium's `chrome://media-internals` where available.
10. Stability: 10 minutes of playback; note dropped frames and temperature.

Fill this matrix with the observations:

| Service | Method | Launch | Login | Playback | DRM | Resolution | Audio | Acceleration | Status | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| Netflix | Chromium | untested | untested | untested | untested | untested | untested | untested | **untested** | — |
| Disney+ | Chromium | untested | untested | untested | untested | untested | untested | untested | **untested** | — |
| YouTube | Chromium | untested | n/a | untested | n/a | untested | untested | untested | **untested** | — |
| Prime Video | Chromium | untested | untested | untested | untested | untested | untested | untested | **untested** | — |
| Max | Chromium | untested | untested | untested | untested | untested | untested | untested | **untested** | — |
| TVP VOD | Chromium | untested | n/a | untested | untested | untested | untested | untested | **untested** | — |
| Player | Chromium | untested | untested | untested | untested | untested | untested | untested | **untested** | — |
| Canal+ | Chromium | untested | untested | untested | untested | untested | untested | untested | **untested** | — |
| Polsat Box Go | Chromium | untested | untested | untested | untested | untested | untested | untested | **untested** | — |
| Apple TV+ | Chromium | untested | untested | untested | untested | untested | untested | untested | **untested** | — |
| Twitch | Chromium | untested | n/a | untested | n/a | untested | untested | untested | **untested** | — |

## Fallbacks implemented

- Every service opens directly from the launcher into a dedicated Chromium
  profile; no desktop navigation is required.
- `Settings → Privacy and security → Clear browser data` removes all profiles.
- When Chromium is not installed, the launcher reports that instead of showing a
  blank screen.
- A DRM failure is visible in the page itself; the launcher does not fake a
  loading state.

## Sources consulted

- Raspberry Pi OS 64-bit Widevine packaging and Chromium CDM loading:
  <https://github.com/raspberrypi/Raspberry-Pi-OS-64bit/issues/248>
- Mozilla ARM64 Widevine tracking:
  <https://bugzilla.mozilla.org/show_bug.cgi?id=1612995>
- Widevine security levels: <https://developer.bitmovin.com/playback/docs/widevine-security-levels-in-web-video-playback>
- Pi 5 codec/decode analysis: <https://www.jeffgeerling.com/blog/2024/can-raspberry-pi-5-handle-4k/>
- Pi 5 HEVC V4L2 driver status: <https://lwn.net/Articles/1060711/>
- Netflix supported browsers: <https://help.netflix.com/en/node/30081>
