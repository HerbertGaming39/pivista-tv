# Testing

Testing has two layers that can run on the build host, and one layer that cannot.

## What runs automatically

### Daemon unit tests (`tests/unit/test_pivistad.py`)

Pure Python, no root, no network, no Raspberry Pi. Covers:

- action allowlist (unknown action rejected), protocol parsing, parameter types;
- nmcli terse-output parsing, escaped colons, SSID deduplication by signal;
- SSID/password validation and argv construction (no shell);
- audio JSON parsing, default sink, volume bounds, unknown sink rejection;
- power confirmation and rate limiting;
- timezone validation against `timedatectl list-timezones`;
- update check parsing and confirmation requirement;
- display mode validation;
- honest Android reporting.

```bash
python3 -m unittest discover -s tests/unit -v
```

### Launcher unit tests (`launcher/tests/test_appcatalog.cpp`)

Qt Test, runs guiless on the host:

- https-only URL validation (rejects http, javascript, file, embedded credentials);
- `.desktop` discovery, hidden entries excluded, icon and category mapping;
- terminal-only and missing-program entries marked invalid with a reason;
- favourites and hidden state persisted across a catalog reload.

```bash
tests/run-launcher-tests.sh        # builds and runs via CTest
```

### QML loading and rendering

The launcher is loaded with `QT_QPA_PLATFORM=offscreen` and rendered to a PNG.
This catches QML syntax errors, missing types, binding errors and layout
regressions without a display:

```bash
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
PIVISTA_UI_DEV=1 PIVISTA_UI_SCREEN=home \
PIVISTA_WEBAPP_CATALOG=applications/web/catalog.json \
PIVISTA_QML_DIR=launcher/qml \
PIVISTA_SCREENSHOT=launcher/build/home.png \
launcher/build/pivista-launcher --windowed
```

`--windowed` keeps the 1920×1080 design size; without it the offscreen platform
falls back to its 800×600 screen. Set `PIVISTA_UI_SCREEN` to `apps`, `search` or
`settings` to capture another page. The web catalog variable is only needed on
the host; the image installs the catalog at `/usr/share/pivista/webapps/`.

`PIVISTA_UI_DEV` is a development-only flag that skips the wizard; it is not set
on a device. Screenshots are for inspection, not assertions.

### Image validation (`tests/image/validate_image.py`)

Mounts the sealed image read-only and checks:

- DOS partition table, 512 MiB FAT32 boot partition, ≥6 GiB ext4 root;
- `config.txt`, `cmdline.txt`, `kernel_2712.img`, Pi 5 DTB and overlays;
- `[pi5]` section in `config.txt`, root `PARTUUID` matches the actual partition;
- required product files (launcher, daemon, QML, web catalog, units, build info);
- `pivista` UID/GID 1000, locked password, no `pi` account;
- units enabled for `graphical.target`/`multi-user.target`;
- empty `machine-id`, no SSH server installed, no credentials in product config or
  user data (`/etc/pivista`, `/etc/NetworkManager/system-connections`,
  `/home`, `/root`);
- aarch64 launcher and kernel (the gzip-compressed `kernel_2712.img` is
  decompressed before `file` inspects it).

The reference build reports **38 passed, 0 failed**.

```bash
sudo python3 tests/image/validate_image.py --image /var/tmp/pivista-build/work.img
```

A passing validation proves the image is structurally sound. It does **not**
prove that it boots.

## What cannot be tested here

| Area | Why | Where it is tracked |
|---|---|---|
| Boot on Pi 5 | no hardware attached | `STATUS.md` → Blocked |
| HDMI output/audio | no Pi/television | `docs/hardware.md` protocol |
| Wi-Fi association | no Pi wireless hardware | `docs/hardware.md` |
| V3D/GL performance | no Pi GPU | `docs/hardware.md` |
| DRM playback | no accounts + no hardware | `docs/streaming.md` |
| H.264/HEVC decode | no Pi, no stream | `docs/streaming.md` |
| HDMI-CEC | no CEC hardware | `STATUS.md` |
| Update rollback | not implemented | `docs/recovery.md` |

## Regression discipline

- A failing test is a bug to fix, not a test to delete.
- New privileged actions in `pivistad` require a validation test and an entry in
  the allowlist documentation (`docs/security.md`).
- Any change to `config/product.env` geometry must be mirrored in
  `manifest/image-config.yaml`; a unit test enforces the two stay consistent.
- Claims in `STATUS.md` must point at a test or a recorded observation.
