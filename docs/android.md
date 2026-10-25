# Android application compatibility

## Decision

**No Android runtime is shipped in PiVista TV 0.2.** The Linux TV experience is
the product. Android support is an optional, experimental integration point and
is classified as **unsupported** in the UI and status file.

This is not an oversight. It follows from what the platform can actually do.

## What was evaluated

### Waydroid

Waydroid runs an Android userspace in a container on a Linux host. It officially
supports aarch64, but *architecture support is not Raspberry Pi 5 support*, and
there is no vendor endorsement of the Pi 5 configuration.

Requirements and realities:

| Requirement | Pi 5 / Raspberry Pi OS status |
|---|---|
| Wayland compositor | Available (sway in this image) |
| Binder IPC | Present in some Pi OS kernels; a 2025 Trixie report still needed workarounds |
| Binderfs | Present in some builds; must be verified per kernel |
| ashmem **or** memfd | memfd path is used; not a universal guarantee |
| PSI (`/proc/pressure`) | Needs `psi=1` in several community reports |
| 4 KB page size | Pi 5 default is 16 KB; community workaround is the 4 KB kernel |
| Graphics | V3D + Mesa/GBM; compositor-specific black-screen workarounds exist |

Community status in 2025–2026: successful reports exist, but a September 2025
Pi 5 / Trixie / Waydroid 1.5.4 report failed to start Android even with Binderfs,
memfd and Mesa/GBM configured. A later report reached "Android ready" after a
DKMS Binder module and `psi=1`, with system errors remaining. This is an
experimental community configuration, not a reproducible appliance feature.

### Netflix and Disney+ inside Android

Even if Waydroid starts, protected playback is a separate problem:

- Waydroid's own licensing page states that generic platforms are **not eligible
  for Google Play/GMS or Widevine licensing**; a commercial Waydroid licence
  does not add Play or Widevine.
- Android streaming apps require Play Protect certification and, for HD,
  hardware-backed Widevine L1. A generic container is neither certified nor
  L1-capable.
- A 2024 Pi Waydroid report describes Netflix installing via GApps but hanging,
  and Disney+ unavailable.
- KonstaKANG's separate native Pi 5 Android 16 image offers an optional
  **Widevine L3** package, not L1 — and it replaces the host OS, which this
  project forbids.

Conclusion: Android on Pi 5 does not solve the Netflix/Disney+ requirement, and
pursuing it would trade a working Linux product for an unverifiable promise.

### Alternatives

| Option | Why not selected |
|---|---|
| Anbox | Largely unmaintained; same Binder/DRM limits |
| Cuttlefish | Needs KVM; a development target, not a TV runtime |
| Native Pi 5 Android (KonstaKANG) | Replaces the Linux host, violates the core requirement |
| ARM translation layers | Android apps on ARM64 are already ARM; translation does not address DRM |

## What is implemented instead

- `pivistad` action `android.status` returns a factual diagnostic: whether
  Waydroid is installed, whether Binder and PSI exist, page size, and why the
  runtime is unsupported. No fabricated "ready" state.
- `Settings → Privacy and security` shows that diagnostic.
- `manifest/packages.lock` carries an `[optional-android]` section (`waydroid`)
  that is **not installed** by `build.sh`.
- The architecture keeps Android out of the boot path: nothing in the session,
  launcher or daemon depends on it.

## If someone wants to experiment

This is explicitly unsupported and outside the acceptance criteria:

1. Verify the running kernel exposes Binder and Binderfs:
   `grep -E 'ANDROID_BINDER' /boot/config-$(uname -r)`.
2. Verify PSI: `cat /proc/pressure/cpu`; add `psi=1` to `cmdline.txt` if absent.
3. Check page size: `getconf PAGESIZE`. The 4 KB kernel may be required.
4. Install Waydroid from its documented repository on a 64-bit Wayland session.
5. Initialize a vanilla image, then test with an ordinary app before any
   streaming app.
6. Expect no Play certification and no Widevine L1. Do not report success based
   on the Android boot animation alone.

Any such change is a local experiment; PiVista TV will continue to report
Android as unsupported until a documented, reproducible test passes.

## Sources

- Waydroid project and licensing: <https://waydro.id/>,
  <https://waydro.id/licensing.html>
- Waydroid kernel requirements: <https://docs.waydro.id/debugging/getting-essential-information>
- Pi 5 failure report, September 2025: <https://github.com/waydroid/waydroid/issues/2047>
- Pi-Apps Binder/PSI workaround, December 2025: <https://github.com/Botspot/pi-apps/issues/2882>
- Pi Waydroid Netflix/Disney+ report: <https://github.com/waydroid/waydroid/issues/1306>
- KonstaKANG Pi 5 Android 16 image (Widevine L3): <https://konstakang.com/devices/rpi5/LineageOS23/>
- Netflix certified-device help: <https://help.netflix.com/en/node/124156>
