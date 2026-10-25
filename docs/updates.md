# Updates and upgrades

PiVista TV separates three things that are often bundled together:

| Layer | How it changes | Rollback | Interrupts playback? |
|---|---|---|---|
| Launcher application (binary, QML, curated web catalog, version file) | Signed update from GitHub | Yes: a local copy of the previous launcher is kept | No download/install; restart only after confirmation |
| Debian/Raspberry Pi OS packages | `apt` from the image's pinned sources | No A/B rollback; reflash on failure | No forced reboot; reboot when the user chooses |
| Complete disk image (kernel, bootloader config, partition layout) | Reflash | Previous image file, if kept | Yes, by definition |

This document describes what is actually implemented in 0.3.0 and what is
deliberately not claimed.

## Version model

There are two version numbers:

- **Image version** in `/etc/pivista/build-info.json`. It identifies the
  Raspberry Pi OS base, kernel and installed packages. A launcher update does
  not change it.
- **Launcher version** in `/usr/share/pivista/version.json`. The updater
  replaces this file together with the launcher binary and QML. **Settings →
  About** shows both.

`Settings → Updates` shows the installed launcher version and the latest
release. A release may be newer than the launcher but still require a newer
image; the UI says so and refuses to install it. This prevents a signed update
from running against an incompatible base image.

The privileged updater itself is part of the image (`/usr/lib/pivista/`). A
launcher update cannot replace the daemon, the public key or the service unit.
Fixes to the update service therefore still need an image release and a
one-time reflash; only the launcher application is self-updating.

## The signed launcher update channel

The updater is split in two:

- **Launcher (unprivileged, UID 1000)** only renders the UI and asks the daemon
  for status, checks, downloads and installs.
- **`pivistad` (root)** owns `/var/lib/pivista/updates`, downloads archives,
  verifies them and swaps application files.

No script from GitHub is executed. The updater is a fixed Python module with a
narrow operation set; the downloaded payload is data (a binary and QML files),
not a program that chooses its own install steps.

### Release discovery

1. `GET https://api.github.com/repos/HerbertGaming39/pivista-tv/releases`
   (HTTPS only; redirects are accepted only to known GitHub hosts).
2. Drafts are ignored. Prereleases are ignored unless the user enables
   **Allow prerelease updates** in Settings. That preference is off by default.
3. Releases without `v<major>.<minor>.<patch>` tags, or without exactly one
   `pivista-update.json` and one `pivista-update.json.sig`, are skipped.
4. The signed manifest, not the mutable GitHub release body, supplies the notes,
   version, minimum image version and archive checksum.
5. The signature is checked before the manifest is parsed. The Ed25519 public
   key is installed at `/etc/pivista/update-pubkey.pem`, owned by root and not
   writable by group/other.

### What a valid release contains

| Asset | Purpose |
|---|---|
| `pivista-launcher-<version>-arm64.tar.xz` | Launcher binary, QML, curated catalog and version file |
| `pivista-update.json` | Signed manifest: version, notes, minimums, archive name/size/SHA-256 |
| `pivista-update.json.sig` | Detached Ed25519 signature over the manifest bytes |

The archive is capped at 64 MiB. The updater checks the SHA-256 in the signed
manifest, then extracts only these paths:

```
bin/pivista-launcher
share/pivista/qml/...                 (files and directories only)
share/pivista/webapps/catalog.json
share/pivista/version.json
```

Absolute paths, `..`, symlinks, hard links, device files, duplicate paths,
unexpected files and an ARM64/ELF mismatch are rejected. Archive modes are
ignored; the installer applies fixed `0755`/`0644` modes and root ownership.

### Install transaction

1. Verify the cached manifest signature again and the archive checksum.
2. Extract to `/var/lib/pivista/updates/staging/<version>`, validate the ELF
   machine (`AArch64`), the version file and the JSON catalog.
3. Copy the current binary, QML directory, catalog and version file to
   `/var/lib/pivista/updates/rollback/<old-version>-<timestamp>/`.
4. Replace the binary and version/catalog files atomically; rename the QML
   directory into place. On any error, restore the backup and report failure.
5. Mark the update **installed; restart required**. The running launcher is not
   killed and no video is closed. The user chooses **Restart launcher**, which
   asks for confirmation first.

The backup is retained until the user rolls back or installs another update.
User configuration is **not** part of the package and is never overwritten:
`~/.config/PiVista/Launcher.conf`, browser profiles, web shortcuts, favourites,
installed-app metadata and NetworkManager connections stay in place.

If an install is interrupted by power loss, the next `pivistad` start marks the
job as failed rather than showing a permanent spinner. The previous files are
either still present or restored by the install path; the rollback copy can be
applied from Settings if the launcher still starts. A power loss during the QML
directory rename is the narrowest window; the installer uses rename, not a
recursive overwrite, and keeps a verified backup.

### Failure behaviour

| Failure | Result |
|---|---|
| GitHub unreachable / TLS failure | Check fails; installed version remains |
| Bad manifest signature | Release rejected; nothing is downloaded |
| Manifest digest mismatch | Release rejected |
| Archive checksum mismatch | Download deleted; job state `failed`; version unchanged |
| Download interrupted | `.part` file removed; job failed |
| Not enough free space | Rejected before starting the job; at least 128 MiB must remain free after the archive |
| Wrong CPU architecture / malformed archive | Install rejected before any file is replaced |
| Install failure after backup | Backup restored; job failed |
| Downgrade offered by a malicious/withdrawn release | Not offered; only a version newer than installed can install |
| Daemon restart with an active job | Job marked failed; no automatic retry |

A failed download does not touch the installed launcher. A failed package
update is a separate problem and can still require a reflash.

## Checking periodically

The launcher runs a read-only update check 60 seconds after startup and every
six hours. It never downloads or installs in the background. If a release is
available, it shows a toast only when:

- update notifications are enabled,
- the first-run wizard and screensaver are not active,
- no external application/video is active, and
- the release has not been postponed.

The Settings page also has a manual **Check for launcher updates** action.

## User controls

| Action | What happens |
|---|---|
| Check for launcher updates | Network read only; writes last-checked metadata |
| Download | Downloads and verifies the archive; no files installed |
| Install | Stages, backs up and swaps application files; asks for confirmation |
| Postpone | Hides the reminder until the next release/check; does not delete the download |
| Restart launcher | `systemctl restart pivista-session.service`; closes running apps and video, confirmed first |
| Roll back | Restores the saved previous launcher; restart required |
| Allow prerelease updates | Off by default; affects future checks only |

## Upgrade from 0.1.0 (the image already downloaded)

**A 0.1.0 device cannot install this update in place.** The 0.1.0 image does not
contain `pivistad`'s signed-update actions or the public key, so there is nothing
on that device to verify or apply an update. This is not a signature problem and
there is no safe way to inject a privileged updater from the launcher.

The safe migration is a one-time reflash to the 0.3.0 image:

1. Keep the 0.1.0 `.img.xz`; it remains the known-good fallback.
2. Download the 0.3.0 image and verify its published SHA-256.
3. Optionally copy off user data from the card first: `/home/pivista/.config/`
   and `/var/lib/pivista/`.
4. Flash 0.3.0, complete first boot, then restore the two directories if wanted.
5. From 0.3.0 onward, launcher updates work through Settings.

This is a platform migration, not a downgrade/upgrade of the application. Do
not attempt to write an image over the running root filesystem.

## Debian package updates

The existing **System packages** actions still use `apt-get update` and
`apt-get upgrade` with the sources pinned in the image. They are separate from
the signed launcher channel:

- apt verifies Debian/Raspberry Pi archive signatures;
- there is no A/B root filesystem and no automatic package rollback;
- the UI does not accept package names or arbitrary URLs;
- a failed system update is recovered by reflashing; see
  [recovery.md](recovery.md).

The launcher update's rollback copy does **not** roll back apt packages.

## Full-image A/B updates: investigation, not implementation

A complete OS update needs a bootable second copy and a bootloader decision.
The current image uses a 512 MiB FAT32 boot partition and a 7 GiB ext4 root
partition that grows on first boot. That is a single-slot layout.

### What Raspberry Pi 5 supports

The Pi 5 bootloader supports `tryboot`: a one-shot alternate boot configuration
can be selected for the next boot and automatically falls back to the normal
configuration after a reboot. RAUC documents a Raspberry Pi `tryboot` setup that
keeps a shared boot partition, writes a full image to an inactive root slot,
marks it for `tryboot`, and confirms or rolls back after a successful boot. This
is the right direction for a future A/B design, but it is not present in this
image.

### Why it is not implemented here

1. **Partition layout.** Two root slots plus boot metadata need roughly
   `2 × root + boot + working space`. The shipped 7 GiB root on a 32 GB card
   leaves too little headroom for a second 7 GiB slot and updates. A smaller
   fixed root (or a larger card) is a new image design, not a runtime feature.
2. **Existing cards.** Repartitioning a card in place would destroy user data
   and could leave the device unbootable. It must be a documented migration with
   a backup and a reflash, not a silent operation.
3. **Boot files and firmware.** `config.txt`, `cmdline.txt`, kernel, DTBs and
   overlays must be generated per slot or shared consistently; the bootloader
   EEPROM and `tryboot` flag need validation on the actual board.
4. **Verification.** No physical Pi 5 was reachable for this build. Claiming an
   atomic update or automatic rollback without a boot test would be false.

Until that work is done, the full-image update path is: back up data, verify the
download, reflash the new image. The launcher application update above is the
supported in-place path and is independent of the OS image.

### Migration outline if A/B is added later

1. Publish a slot-aware image with two root partitions, a shared FAT boot
   partition, and RAUC-compatible bootloader integration.
2. Require a one-time backup and reflash for existing single-slot devices; do
   not attempt online repartitioning.
3. Bundle the update public key and a revocation/rotation procedure.
4. Test on hardware: write inactive slot, `tryboot`, power loss, boot failure,
   rollback, and confirming a good slot.
5. Only then describe the scheme as atomic with rollback.

## Signing and release procedure

The private signing key is **not** in this repository and must never be
committed. A release signer should keep it offline, back it up securely, and
record its public fingerprint in the release notes.

```bash
# On the build host, with the image mounted at /mnt/pivista:
sudo tools/build-app-update.py \
  --image-root /mnt/pivista \
  --version 0.3.0 \
  --key /secure/offline/update-signing-key.pem \
  --notes-file build/logs/update-notes-0.3.0.md \
  --out releases/update-0.3.0
```

The tool writes the deterministic `tar.xz`, signed manifest, signature,
SHA-256 file and `app-update-info.json`. Upload **all** of these as release
assets. The updater looks for the exact asset names shown above; a manifest that
is uploaded without its `.sig` is rejected.

Verify before publishing:

```bash
openssl pkeyutl -verify -pubin \
  -inkey system/rootfs/etc/pivista/update-pubkey.pem \
  -rawin -in releases/update-0.3.0/pivista-update.json \
  -sigfile releases/update-0.3.0/pivista-update.json.sig
```

Rotation: publish a new launcher build containing the new public key first,
then sign subsequent updates with the new private key. Do not rotate by
replacing the key in an update signed only by the old key without documenting
the trust transition.

## Reproducibility and verification

The app archive is deterministic for the same input files (fixed tar metadata
and xz preset). The signed manifest binds the exact archive size and SHA-256, so
a republished archive with different bytes is rejected even if it came from the
same source tree. Image builds remain structurally reproducible but not
bit-for-bit; see [build.md](build.md).

Automated tests cover discovery, signature rejection, prerelease opt-in,
minimum-version incompatibility, checksum corruption, interrupted downloads,
insufficient space, downgrade refusal, archive traversal, wrong architecture,
failed swaps with restore, rollback, and restart recovery. These are host tests
using a local fake GitHub source; they do **not** prove physical Pi 5 boot,
HDMI, network or DRM behaviour.

## Known limitations

- No physical Pi 5 was available for this release; hardware boot and update
  recovery remain untested.
- No automatic full-image A/B updates, no RAUC integration, no automatic
  rollback for OS packages. The updater daemon and trust key are image content
  and are not self-updating.
- The app updater checks GitHub's API; an offline device can only use the
  installed version.
- Prereleases are identified by GitHub's `prerelease` flag. A stable-looking tag
  without that flag is treated as stable.
- The release notes shown in Settings are capped at 20,000 characters and the
  page shows a short preview rather than the full Markdown.
