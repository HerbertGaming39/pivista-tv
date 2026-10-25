#!/usr/bin/env python3
"""Generate the artifact manifest that accompanies every PiVista TV image."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import sys


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_packages(path: pathlib.Path) -> dict[str, str]:
    packages: dict[str, str] = {}
    if not path.is_file():
        return packages
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0]:
            packages[parts[0]] = parts[1]
    return packages


def git_value(project: str, *args: str) -> str | None:
    try:
        out = subprocess.run(
            ["git", "-C", project, *args],
            check=True, capture_output=True, text=True, timeout=10,
        )
        return out.stdout.strip() or None
    except (subprocess.SubprocessError, OSError):
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--packages", required=True)
    parser.add_argument("--provenance", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    project = pathlib.Path(__file__).resolve().parents[2]
    image = pathlib.Path(args.image).resolve()
    if not image.is_file():
        print(f"image not found: {image}", file=sys.stderr)
        return 2

    env = os.environ
    packages = read_packages(pathlib.Path(args.packages))
    launcher_version = ""
    prov = pathlib.Path(args.provenance)
    if prov.is_file():
        launcher_version = prov.read_text(encoding="utf-8").strip()

    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    commit = git_value(str(project), "rev-parse", "HEAD")
    dirty = git_value(str(project), "status", "--porcelain")
    manifest = {
        "schema": 1,
        "product": env.get("PIVISTA_NAME", "PiVista TV"),
        "slug": env.get("PIVISTA_SLUG", "pivista-tv"),
        "version": env.get("PIVISTA_VERSION", "0.0.0"),
        "codename": env.get("PIVISTA_CODENAME", ""),
        "build_id": env.get("PIVISTA_BUILD_ID", ""),
        "created_utc": now.isoformat().replace("+00:00", "Z"),
        "target": {
            "model": env.get("PIVISTA_MODEL", "Raspberry Pi 5"),
            "soc": env.get("PIVISTA_SOC", "BCM2712"),
            "architecture": env.get("PIVISTA_ARCH", "arm64"),
        },
        "base": {
            "name": env.get("BASE_IMAGE_NAME", ""),
            "url": env.get("BASE_IMAGE_URL", ""),
            "sha256": env.get("BASE_IMAGE_SHA256", ""),
            "release": env.get("BASE_IMAGE_RELEASE", ""),
            "debian": env.get("BASE_IMAGE_DEBIAN", ""),
            "kernel": env.get("BASE_IMAGE_KERNEL", ""),
        },
        "launcher": launcher_version,
        "image": {
            "file": image.name,
            "size_bytes": image.stat().st_size,
            "sha256": sha256(image),
            "compression": "xz" if image.suffix == ".xz" else "none",
        },
        "software": {
            "package_count": len(packages),
            "packages": dict(sorted(packages.items())),
        },
        "provenance": {
            "builder": "build.sh",
            "host_arch": os.uname().machine,
            "source_commit": commit,
            "source_dirty": bool(dirty) if dirty is not None else None,
            "build_log_sha256": sha256(pathlib.Path(args.log)) if pathlib.Path(args.log).is_file() else None,
            "reproducibility": "pinned inputs and deterministic configuration; not bit-for-bit reproducible",
        },
        "known_limitations": [
            "No physical Raspberry Pi 5 boot test was performed by the build host.",
            "Protected 1080p playback on Netflix/Disney+ is not verified.",
            "Android application compatibility is not included.",
        ],
    }

    out = pathlib.Path(args.manifest)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"manifest: {out}")
    print(f"sha256:   {manifest['image']['sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
