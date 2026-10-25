# Testing

Testing has two layers that can run on the build host, and one layer that cannot.

## What runs automatically

### Host Python tests (`tests/unit/`)

Pure Python, no network, no Raspberry Pi. Covers the daemon and product config;

- action allowlist (unknown action rejected), protocol parsing, request-id echo,
  parameter types;
- nmcli terse-output parsing, escaped colons, SSID deduplication by signal;
- SSID/password validation and argv construction (no shell);
- audio JSON parsing, default sink, volume bounds, unknown sink rejection;
- power confirmation and rate limiting;
- timezone validation against `timedatectl list-timezones`;
- update check parsing and confirmation requirement;
- signed launcher updates: release discovery, manifest signature, prerelease
  opt-in, minimum-version refusal, checksum/corrupt/interrupted downloads,
  insufficient space, download preservation across checks, archive traversal,
  wrong architecture, failed swap restoration, rollback, restart recovery and
  preservation of user/network data;
- reproducible app-update archive building and manifest signing;
- display mode validation;
- honest Android reporting;
- the global Home script (`home.sh`) connects to the launcher's user-only socket
  and sends its `home\n` notification.

```bash
python3 -m unittest discover -s tests/unit -v
```

### Launcher unit tests (`launcher/tests/`)

Qt Test, runs guiless on the host:

- https-only URL validation (rejects http, javascript, file, embedded credentials);
- `.desktop` discovery, hidden entries excluded, icon and category mapping;
- terminal-only and missing-program entries rejected rather than shown as dead
  tiles, with a reason available for diagnostics;
- favourites and hidden state persisted across a catalog reload;
- the user-only Home relay accepts a client and emits `homeRequested`, which is
  what makes the global Home key return to the launcher.

```bash
tests/run-launcher-tests.sh        # builds and runs both executables via CTest
```

### QML loading and rendering (`tests/ui/render_screens.sh`)

`tests/run-launcher-tests.sh` renders 29 offscreen screens and fails on QML
runtime errors, a missing/wrongly-sized PNG, or a screen that is blank below the
header. It covers Home (including the featured banner and rows), Apps, Games,
Media, Search and Settings at 1080p and 720p, app details at both sizes, the
appearance and updates pages at both sizes, Home at 4K, plus every first-boot
wizard page at 720p and the welcome page at 1080p. The wizard override is development-only
(`PIVISTA_UI_WIZARD_STEP`); it is not read from device configuration.

The blank-content check exists because the first Media implementation was the
correct PNG size but its rows had been scrolled out of view by focus restored
before layout. `tests/ui/screenshot_content.py` decodes the PNG with the Python
standard library and requires bright pixels below the header, so that class of
regression now fails the smoke test instead of producing a convincing-looking
empty screenshot.

A manual render is still useful when inspecting a design change:

```bash
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
PIVISTA_UI_DEV=1 PIVISTA_UI_SCREEN=home \
PIVISTA_WEBAPP_CATALOG=applications/web/catalog.json \
PIVISTA_QML_DIR=launcher/qml \
PIVISTA_SCREENSHOT=build/ui-tests/home.png \
build/launcher-tests/pivista-launcher --windowed
```

`--windowed` keeps the requested design size; without it the offscreen platform
falls back to its 800×600 screen. Set `PIVISTA_UI_SCREEN` to `apps`, `search` or
`settings`, and `PIVISTA_UI_WIDTH=1280 PIVISTA_UI_HEIGHT=720` for the 720p path.
The web catalog variable is only needed on the host; the image installs the
catalog at `/usr/share/pivista/webapps/`.

The automated check verifies dimensions, visible content and QML errors, not
visual taste; review the PNGs for spacing and contrast. A passing render is still
not evidence of GPU performance or physical-Pi behaviour: the test runs with the
software Qt Quick backend.

### Image validation (`tests/image/validate_image.py`)

Mounts the sealed image read-only and checks:

- DOS partition table, 512 MiB FAT32 boot partition, ≥6 GiB ext4 root;
- `config.txt`, `cmdline.txt`, `kernel_2712.img`, Pi 5 DTB and overlays;
- `[pi5]` section in `config.txt`, root `PARTUUID` matches the actual partition;
- required product files (launcher, daemon, QML, web catalog, units, build info);
- `pivista` UID/GID 1000, locked password, no `pi` account;
- cloud-init masked plus `/etc/cloud/cloud-init.disabled`, seed files removed;
- SSH host-key regeneration masked, no `/etc/ssh` directory;
- units enabled for `graphical.target`/`multi-user.target` and the vendor root
  filesystem resize unit;
- session config directories owned by UID/GID 1000 with no world access;
- empty `machine-id`, no SSH server installed, no credentials in product config or
  user data (`/etc/pivista`, `/etc/NetworkManager/system-connections`,
  `/home`, `/root`);
- aarch64 launcher and kernel (the gzip-compressed `kernel_2712.img` is
  decompressed before `file` inspects it);
- launcher version metadata and the installed Ed25519 update public key (not
  group/other writable).

The reference 0.3.1 build reports **51 passed, 0 failed**.

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
| Physical launcher update | no Pi/network/television | `docs/hardware-test.md` |

## Regression discipline

- A failing test is a bug to fix, not a test to delete.
- New privileged actions in `pivistad` require a validation test and an entry in
  the allowlist documentation (`docs/security.md`).
- Any change to `config/product.env` geometry must be mirrored in
  `manifest/image-config.yaml`; a unit test enforces the two stay consistent.
- Claims in `STATUS.md` must point at a test or a recorded observation.
