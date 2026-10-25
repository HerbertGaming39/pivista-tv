#!/usr/bin/env python3
"""Build and sign a PiVista launcher update from a mounted image.

The archive is intentionally small and contains only the launcher application:
binary, QML, curated web catalog and app version file. It is not a disk image
and cannot replace the OS. Use tools/build.sh for a complete image.

Example:
  sudo tools/build-app-update.py \
      --image-root /mnt/pivista \
      --version 0.3.0 \
      --key build/logs/update-signing-key.pem \
      --notes-file build/logs/update-notes-0.3.0.md
"""

from __future__ import annotations

import argparse
import hashlib
import json
import lzma
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

PRODUCT = "pivista-tv"
REPOSITORY = "HerbertGaming39/pivista-tv"
SCHEMA = 1
REQUIRED = {
    "bin/pivista-launcher",
    "share/pivista/qml/Main.qml",
    "share/pivista/webapps/catalog.json",
    "share/pivista/version.json",
}


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(image_root: pathlib.Path) -> dict[str, pathlib.Path]:
    values: dict[str, pathlib.Path] = {}
    values["bin/pivista-launcher"] = image_root / "usr/bin/pivista-launcher"
    values["share/pivista/version.json"] = image_root / "usr/share/pivista/version.json"
    values["share/pivista/webapps/catalog.json"] = image_root / "usr/share/pivista/webapps/catalog.json"
    qml = image_root / "usr/share/pivista/qml"
    if not qml.is_dir():
        raise SystemExit(f"error: QML directory is missing: {qml}")
    for path in sorted(qml.rglob("*")):
        if path.is_symlink():
            raise SystemExit(f"error: refusing symlink in QML: {path}")
        if path.is_file():
            values["share/pivista/qml/" + path.relative_to(qml).as_posix()] = path
    for name, path in values.items():
        if not path.is_file():
            raise SystemExit(f"error: required artifact is missing: {path} ({name})")
    missing = REQUIRED - set(values)
    if missing:
        raise SystemExit(f"error: package is missing {sorted(missing)}")
    return values


def build_archive(files: dict[str, pathlib.Path], output: pathlib.Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, "w:xz", preset=9 | lzma.PRESET_EXTREME) as archive:
        for name in sorted(files):
            path = files[name]
            info = tarfile.TarInfo(name)
            info.size = path.stat().st_size
            info.mode = 0o755 if name == "bin/pivista-launcher" else 0o644
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            info.mtime = 0
            with open(path, "rb") as handle:
                archive.addfile(info, handle)


def sign_manifest(manifest: pathlib.Path, key: pathlib.Path, output: pathlib.Path) -> None:
    subprocess.run([
        "openssl", "pkeyutl", "-sign", "-inkey", str(key), "-rawin",
        "-in", str(manifest), "-out", str(output),
    ], check=True, capture_output=True)
    if output.stat().st_size == 0:
        raise SystemExit("error: OpenSSL produced an empty signature")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build and sign a PiVista launcher update")
    parser.add_argument("--image-root", required=True, type=pathlib.Path,
                        help="mounted PiVista root filesystem")
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("releases"),
                        help="directory for the archive and signed manifest")
    parser.add_argument("--version", required=True,
                        help="launcher version being packaged, e.g. 0.3.0")
    parser.add_argument("--key", type=pathlib.Path,
                        default=pathlib.Path(os.environ.get("PIVISTA_UPDATE_KEY", "")))
    parser.add_argument("--notes", default="")
    parser.add_argument("--notes-file", type=pathlib.Path)
    parser.add_argument("--min-version", default=None,
                        help="oldest launcher that may install this update")
    parser.add_argument("--min-system", default=None,
                        help="oldest system image that may install this update")
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--release-tag", default=None)
    args = parser.parse_args()

    if not args.key or not args.key.is_file():
        raise SystemExit("error: --key is required (or set PIVISTA_UPDATE_KEY)")
    image_root = args.image_root.resolve()
    if not image_root.is_dir():
        raise SystemExit(f"error: image root does not exist: {image_root}")
    files = collect(image_root)
    try:
        version_info = json.loads(files["share/pivista/version.json"].read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: invalid version.json: {exc}") from None
    if version_info.get("product") != PRODUCT or version_info.get("version") != args.version:
        raise SystemExit("error: image version.json does not match --version")
    notes = args.notes
    if args.notes_file:
        notes = args.notes_file.read_text(encoding="utf-8")
    release_tag = args.release_tag or f"v{args.version}"
    args.out.mkdir(parents=True, exist_ok=True)
    bundle_name = f"pivista-launcher-{args.version}-arm64.tar.xz"
    bundle = args.out / bundle_name
    build_archive(files, bundle)
    digest = sha256(bundle)
    manifest = {
        "schema": SCHEMA,
        "product": PRODUCT,
        "version": args.version,
        "min_version": args.min_version or args.version,
        "min_system": args.min_system or args.version,
        "components": ["launcher", "qml", "catalog", "version"],
        "notes": notes.strip(),
        "bundle": {
            "name": bundle_name,
            "size": bundle.stat().st_size,
            "sha256": digest,
        },
    }
    manifest_path = args.out / "pivista-update.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    signature_path = args.out / "pivista-update.json.sig"
    sign_manifest(manifest_path, args.key, signature_path)
    checksum_path = args.out / f"{bundle_name}.sha256"
    checksum_path.write_text(f"{digest}  {bundle_name}\n", encoding="utf-8")
    info = {
        "repository": args.repository,
        "release_tag": release_tag,
        "version": args.version,
        "bundle": bundle_name,
        "size": bundle.stat().st_size,
        "sha256": digest,
        "manifest": manifest_path.name,
        "manifest_sha256": sha256(manifest_path),
        "signature": signature_path.name,
        "min_version": manifest["min_version"],
        "min_system": manifest["min_system"],
        "asset_urls": {
            bundle_name: f"https://github.com/{args.repository}/releases/download/{release_tag}/{bundle_name}",
            "pivista-update.json": f"https://github.com/{args.repository}/releases/download/{release_tag}/pivista-update.json",
            "pivista-update.json.sig": f"https://github.com/{args.repository}/releases/download/{release_tag}/pivista-update.json.sig",
        },
    }
    (args.out / "app-update-info.json").write_text(json.dumps(info, indent=2, sort_keys=True) + "\n",
                                                  encoding="utf-8")
    print(json.dumps(info, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
