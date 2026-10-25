# Streaming and DRM compatibility

**Status: no protected playback has been tested on this image.** The build host
had no Raspberry Pi 5, television, streaming account or DRM licence server. The
matrix below separates what is present in the image from what a provider may
actually allow. Nothing here is a promise of playback or resolution.

## What is actually in the image

These facts were read from the sealed image, not inferred:

| Component | Version / path | What it proves |
|---|---|---|
| Chromium | `1:155.0.8059.79-1~deb13u1+rpt1` | The browser and its codec stack are installed |
| Widevine CDM | `libwidevinecdm0 4.10.2662.3+1`, `/opt/WidevineCdm/gmp-widevinecdm/latest/libwidevinecdm.so` | A software CDM is present on disk |
| Kernel | Raspberry Pi OS 6.18 arm64 | Pi 5 platform support, including its V4L2 HEVC block |
| FFmpeg | Debian Trixie build with `h264`, `hevc`, `vp9`, `av1`, `*_v4l2m2m` decoders | Software decoders exist; V4L2 wrappers exist |
| Launcher | Chromium kiosk per service, dedicated profile | The shortcut path works without a desktop |

Having a CDM file is **not** evidence that Chromium loads it, that a provider
accepts it, or that a stream decrypts. Those require a real playback test with an
account. No such test was performed.

## Real Pi 5 platform probe (2026-10-25)

A physical **Raspberry Pi 5 Model B Rev 1.1, 8 GB**, running Raspberry Pi OS
(Debian 13, kernel 6.18.34, Chromium 149.0.7827.114 + `libwidevinecdm0
4.10.2662.3`), was probed over SSH. This was the vendor OS used for the probe,
**not** the sealed PiVista image (which carries Chromium 155), and it was
headless: no HDMI cable, television or streaming account was attached.

Headless Chromium was run with its own throwaway profile and a local page that
called `HTMLMediaElement.canPlayType` and `navigator.requestMediaKeySystemAccess`:

| Probe | Result |
|---|---|
| `com.widevine.alpha`, `cenc`, H.264 + AAC | **OK** — media key system access granted |
| `com.microsoft.playready` | `NotSupportedError` (expected) |
| H.264 (`avc1.42E01E`) | `probably` |
| HEVC (`hvc1.1.6.L93.B0`) | empty string (not playable through this Chromium build) |
| AV1 (`av01.0.05M.08`) | `probably` |
| VP9 (WebM) | `probably` |
| AAC (`mp4a.40.2`), Opus | `probably` |
| `/dev/video19` | `rpi-hevc-dec` V4L2 device present |

What this **does** establish: on real Pi 5 hardware the installed Chromium build
can load the Widevine CDM and grant a basic `cenc`/H.264/AAC key-system access.
That is stronger than "a CDM file exists on disk".

What it **does not** establish: a Netflix/Disney+/Prime licence exchange, a
decrypted frame, HDMI output, audio output, resolution, bitrate, hardware
decoding of a real stream, or 1080p. Provider acceptance and playback remain
**unverified**. The image itself has still not been booted on hardware.

## The six separate questions

"Netflix works" is meaningless without separating:

1. Does the shortcut/browser open? (launcher)
2. Can the user sign in? (service + browser)
3. Is the catalogue visible? (service + region)
4. Does unprotected video play? (codec + browser)
5. Does **protected** video play? (Widevine + provider policy)
6. At what resolution, with what audio and decoder? (provider + hardware)

PiVista TV does not upgrade an entry because a page loaded. The catalog labels
every DRM service `browser-drm-unverified`.

## Realistic expectations, by service

These are expectations from the platform and provider documentation, **not test
results on this image**.

| Service | Realistic expectation | Why |
|---|---|---|
| **YouTube** | Best chance of ordinary playback. 720p is plausible; 1080p is not verified. | Unprotected video; H.264 is CPU-decoded on Pi 5. Playback depends on the selected codec and load. |
| **Netflix** | May work through Widevine L3. Resolution is chosen by Netflix and is unverified. Do not expect 4K; do not claim 1080p. | Widevine L3 software CDM; no Pi certification. Netflix applies its own browser/device rules. |
| **Disney+** | Uncertain. Sign-in and playback are unverified. | Provider browser/device policy; a CDM on disk does not establish acceptance. |
| **Prime Video** | If it plays, expect **SD only** under Amazon's published rule. | Amazon states that browser playback on an OS other than Windows or macOS is restricted to standard definition. |
| **Max** | Unverified. | DRM service; provider policy not tested. |
| **Apple TV+** | Unverified. | Requires an Apple Account; provider policy not tested. |
| **TVP VOD** | Browser playback is plausible but unverified. | Catalog marks it unprotected; no playback test was run. |
| **Player** | Unverified. | DRM service; no playback test. |
| **Canal+** | Treat HD as unlikely and playback as unverified. | A search-indexed Canal+ help page reportedly requires Widevine L1 for HD; the page could not be fetched for confirmation. Do not rely on this as a confirmed rule. |
| **Polsat Box Go** | Browser playback is plausible but unverified. | Its help page names current browsers and Widevine Modular, but does not establish this Pi/browser will receive HD renditions. |
| **Twitch** | Unprotected live video; playback unverified. | No DRM, but codec/performance still matters. |

There are **no official native Linux desktop clients** for Netflix or Disney+.
Any "native" Linux client is a web wrapper and does not change the DRM stack.

## Widevine on 64-bit Raspberry Pi OS

- Raspberry Pi OS's Chromium build can use the vendor `libwidevinecdm0` package.
  This image contains version `4.10.2662.3`; the package is a **software (L3)**
  CDM, not a certification and not L1.
- Widevine L1 requires factory-provisioned, hardware-rooted keys through an
  OEMCrypto integration. A Raspberry Pi is not a certified Widevine device;
  installing a CDM does not create L1.
- Providers may cap resolution based on browser identity, device certification,
  codec, account plan and region. A 1080p HDMI mode says nothing about the
  stream's resolution.
- L3 does not mean one universal maximum resolution. Each provider decides what
  to offer. The conservative expectation is SD/720p, and 1080p is not verified.

## Raspberry Pi 5 video decode facts

| Codec | Hardware decode on Pi 5 | Consequence for this image |
|---|---|---|
| HEVC / H.265 | Yes, V4L2 stateless decoder (up to 4Kp60) | Available to software that drives the Pi V4L2 path; Chromium's use is **not established** |
| H.264 / AVC | **No** dedicated hardware decoder | CPU decode; many web streams use H.264, so load matters |
| AV1 | No | CPU decode; 4K is not viable |
| VP9 | No dedicated block | CPU decode |

The absence of an H.264 hardware decoder is the most important hardware fact
for streaming on this board. Low CPU usage alone is not evidence of hardware
decoding; verify with `v4l2-ctl --list-devices`, `chrome://media-internals` and
CPU measurements while a stream plays.

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
9. Decoder: `v4l2-ctl --list-devices`, `pidstat -p $(pidof chromium) 1 60`, and
   Chromium's `chrome://media-internals` where available.
10. Stability: 10 minutes of playback; note dropped frames, temperature and
    `vcgencmd get_throttled`.

Fill this matrix with observations:

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
- The global Home key closes the streaming window and returns to the launcher;
  the launcher itself also listens on a user-only socket, so a native app is
  closed even when the compositor handles the key first.

## Sources consulted

- Raspberry Pi processor documentation (Pi 5 HEVC, no H.264 block):
  <https://www.raspberrypi.com/documentation/computers/processors.html>
- Raspberry Pi 5 launch (4Kp60 HEVC):
  <https://www.raspberrypi.com/news/introducing-raspberry-pi-5/>
- Mozilla Pi 5 HEVC/V4L2 integration notes:
  <https://bugzilla.mozilla.org/show_bug.cgi?id=1969297>
- Raspberry Pi OS 64-bit Widevine packaging history:
  <https://github.com/raspberrypi/Raspberry-Pi-OS-64bit/issues/248>
- Widevine overview and access requirements:
  <https://developers.google.com/widevine/drm/overview>,
  <https://developers.google.com/widevine/access>
- Netflix supported browsers: <https://help.netflix.com/en/node/30081>
- Prime Video computer requirements (SD outside Windows/macOS):
  <https://www.amazon.com/gp/help/customer/display.html?nodeId=GUVGB3QMQRYRERYW>
- Polsat Box Go technical requirements:
  <https://pomoc.polsatboxgo.pl/pytanie/wymagania-techniczne/>
- CANAL+ technical requirements (page returned 403 during research; treat as a
  lead, not a confirmed rule): <https://pl.canalplus.com/pomoc/wymagania-techniczne>
