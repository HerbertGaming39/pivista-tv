#!/usr/bin/env python3
"""List installed packages and versions from a mounted PiVista root filesystem.

The image is arm64, so running `dpkg-query` inside it needs qemu. This helper
reads /var/lib/dpkg/status directly and needs only the host's Python.

    sudo tools/image-packages.py --root /mnt/pivista > packages.tsv
"""

from __future__ import annotations

import argparse
import pathlib
import sys


def parse_status(path: pathlib.Path) -> list[tuple[str, str, str]]:
    packages: list[tuple[str, str, str]] = []
    for stanza in path.read_text(encoding="utf-8", errors="replace").split("\n\n"):
        fields: dict[str, str] = {}
        key = ""
        for line in stanza.splitlines():
            if line.startswith((" ", "\t")) and key:
                fields[key] += "\n" + line.strip()
            elif ":" in line:
                key, value = line.split(":", 1)
                fields[key.strip()] = value.strip()
        package = fields.get("Package")
        version = fields.get("Version")
        status = fields.get("Status", "")
        if package and version and status.endswith("installed"):
            packages.append((package, version, status))
    return sorted(packages)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True,
                        help="mounted root filesystem (or any path containing var/lib/dpkg)")
    args = parser.parse_args()
    root = pathlib.Path(args.root)
    status = root / "var/lib/dpkg/status"
    if not status.is_file():
        print(f"not a Debian rootfs: {status} is missing", file=sys.stderr)
        return 2
    packages = parse_status(status)
    for package, version, state in packages:
        print(f"{package}\t{version}\t{state}")
    print(f"{len(packages)} installed packages", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
