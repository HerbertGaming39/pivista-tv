# PiVista TV

This is the on-device copy of the PiVista TV documentation. The complete release
README, flashing instructions, checksum and current hardware-test checklist are
in the `pivista-tv` release archive; the same documents are installed here under
`/usr/share/doc/pivista/`.

Start with:

- `architecture.md` — how the session, launcher, daemon and image fit together.
- `hardware-test.md` — first-boot checklist for a physical Raspberry Pi 5.
- `streaming.md` — what is and is not verified for Netflix, Disney+, YouTube and
  the Polish services.
- `recovery.md` — the kiosk account is locked; recovery is offline or by
  reflashing.
- `remote-access.md` — optional SSH and localhost-only VNC, off by default.
- `security.md` — locked accounts, the narrow `support` account, cloud-init
  disabled and the privileged socket.

Build information is in `/etc/pivista/build-info.json` and
`/etc/pivista/build-provenance.txt`. This copy is intentionally stable across
image builds; the release checksum lives in the `.sha256` file next to the image.
