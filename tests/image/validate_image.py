#!/usr/bin/env python3
"""Validate a PiVista TV Raspberry Pi 5 image without booting it.

The checks are deliberately structural: partition layout, boot firmware files,
filesystem integrity, installed product files, account/security defaults and
build provenance. A passing run does NOT prove the image boots on hardware.

Run as root (loop mounts are required):
    sudo python3 tests/image/validate_image.py --image work.img
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PASS = "PASS"
FAIL = "FAIL"
SKIP = "SKIP"

results: list[tuple[str, str, str]] = []


def record(name: str, ok: bool, detail: str = "") -> bool:
    results.append((PASS if ok else FAIL, name, detail))
    return ok


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


@contextlib.contextmanager
def mounted(image: Path, read_only: bool = True):
    flags = ["losetup", "--find", "--partscan", "--show"]
    if read_only:
        flags.insert(3, "--read-only")
    flags.append(str(image))
    loop = run(flags)
    if loop.returncode != 0:
        raise RuntimeError(loop.stderr.strip())
    loop_dev = loop.stdout.strip().splitlines()[-1].strip()
    root = Path(tempfile.mkdtemp(prefix="pivista-validate-"))
    boot = root / "boot"
    boot.mkdir()
    mounted_any = False
    try:
        opts = ["-o", "ro"] if read_only else []
        p2 = run(["mount", *opts, f"{loop_dev}p2", str(root)])
        if p2.returncode != 0:
            raise RuntimeError(f"mount root failed: {p2.stderr.strip()}")
        mounted_any = True
        p1 = run(["mount", *opts, f"{loop_dev}p1", str(boot)])
        if p1.returncode != 0:
            raise RuntimeError(f"mount boot failed: {p1.stderr.strip()}")
        yield loop_dev, root, boot
    finally:
        run(["umount", str(boot)])
        run(["umount", str(root)])
        if mounted_any:
            run(["losetup", "-d", loop_dev])
        with contextlib.suppress(OSError):
            boot.rmdir()
        with contextlib.suppress(OSError):
            root.rmdir()


def check_partitions(image: Path) -> None:
    out = run(["sfdisk", "--json", str(image)])
    ok = out.returncode == 0
    if not record("partition table readable", ok, out.stderr.strip()):
        return
    try:
        table = json.loads(out.stdout)["partitiontable"]
    except (json.JSONDecodeError, KeyError) as exc:
        record("partition table parses", False, str(exc))
        return
    parts = table.get("partitions", [])
    record("two partitions", len(parts) >= 2, f"found {len(parts)}")
    if len(parts) >= 2:
        boot, root = parts[0], parts[1]
        boot_mb = int(boot["size"]) / 2048
        record("boot partition is 512 MiB FAT32",
               496 <= boot_mb <= 528 and boot.get("type") in {"c", "ef"},
               f"{boot_mb:.0f} MiB, type {boot.get('type')}")
        record("root partition is >= 6 GiB", int(root["size"]) / 2048 / 1024 >= 6,
               f"{int(root['size'])/2048/1024:.1f} GiB")


def check_boot_files(boot: Path, cmdline: str | None, root_uuid: str) -> None:
    required = ["config.txt", "cmdline.txt", "kernel_2712.img", "bcm2712-rpi-5-b.dtb"]
    for name in required:
        record(f"boot file /{name}", (boot / name).is_file())

    overlays = boot / "overlays"
    record("boot overlays directory", overlays.is_dir() and any(overlays.iterdir()))

    config = (boot / "config.txt").read_text(errors="replace") if (boot / "config.txt").is_file() else ""
    record("config.txt has a [pi5] section", "[pi5]" in config)

    if cmdline is None:
        record("cmdline.txt readable", False)
        return
    record("cmdline.txt is a single line", "\n" not in cmdline.strip())
    match = re.search(r"root=PARTUUID=([0-9a-fA-F-]+)", cmdline)
    record("cmdline.txt root=PARTUUID present", bool(match))
    if match and root_uuid:
        record("cmdline PARTUUID matches root partition",
               match.group(1).lower() == root_uuid.lower(),
               f"cmdline {match.group(1)} vs blkid {root_uuid}")


def check_rootfs(root: Path) -> dict:
    required = [
        "etc/pivista/build-info.json",
        "etc/pivista/build-provenance.txt",
        "etc/pivista/product.env",
        "usr/bin/pivista-launcher",
        "usr/lib/pivista/pivistad.py",
        "usr/share/pivista/qml/Main.qml",
        "usr/share/pivista/webapps/catalog.json",
        "etc/systemd/system/pivista-daemon.service",
        "etc/systemd/system/pivista-session.service",
        "etc/systemd/system/pivista-firstboot.service",
        "etc/systemd/system/pivista-input.service",
        "usr/share/pivista/qml/Theme.qml",
    ]
    for rel in required:
        record(f"rootfs /{rel}", (root / rel).exists())

    record("machine-id reset", (root / "etc/machine-id").is_file()
           and (root / "etc/machine-id").read_text().strip() == "")
    record("ssh not enabled",
           not (root / "etc/systemd/system/multi-user.target.wants/ssh.service").exists()
           and not (root / "etc/systemd/system/multi-user.target.wants/sshd.service").exists())
    record("ssh server not installed",
           not (root / "usr/sbin/sshd").exists()
           and not (root / "etc/ssh/sshd_config").exists())
    record("vendor first-boot helpers disabled",
           not (root / "etc/systemd/system/multi-user.target.wants/userconfig.service").exists()
           and not (root / "etc/systemd/system/multi-user.target.wants/sshswitch.service").exists())
    record("no pi account", "pi:" not in (root / "etc/passwd").read_text(errors="replace"))

    passwd = (root / "etc/passwd").read_text(errors="replace") if (root / "etc/passwd").is_file() else ""
    piv = re.search(r"^pivista:x:(\d+):(\d+):", passwd, re.M)
    record("pivista account uid/gid 1000", bool(piv and piv.group(1) == "1000" and piv.group(2) == "1000"))

    shadow = (root / "etc/shadow").read_text(errors="replace") if (root / "etc/shadow").is_file() else ""
    pw = re.search(r"^pivista:([^:]*):", shadow, re.M)
    record("pivista password locked", bool(pw and pw.group(1).startswith(("!", "*"))))

    mode = os.stat(root / "usr/bin/pivista-launcher").st_mode if (root / "usr/bin/pivista-launcher").exists() else 0
    record("launcher is executable", bool(mode & 0o111))

    enabled = [
        root / "etc/systemd/system/graphical.target.wants/pivista-session.service",
        root / "etc/systemd/system/multi-user.target.wants/pivista-daemon.service",
        root / "etc/systemd/system/multi-user.target.wants/pivista-firstboot.service",
    ]
    record("PiVista units enabled", all(p.exists() or p.is_symlink() for p in enabled))

    info = {}
    info_path = root / "etc/pivista/build-info.json"
    if info_path.is_file():
        with contextlib.suppress(json.JSONDecodeError):
            info = json.loads(info_path.read_text())
    record("build-info product is PiVista TV", info.get("product") == "PiVista TV", str(info.get("product")))
    record("build-info version present", bool(info.get("version")))
    return info


def check_secrets(root: Path) -> None:
    patterns = re.compile(
        r"(BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|"
        r"WPA-PSK|psk=)[^\n]{8,}",
        re.IGNORECASE,
    )
    hits = []
    # Scan product configuration and user data, not vendor scripts that merely
    # contain example tokens (e.g. wpa_supplicant's functions.sh mentions psk=).
    bases = [root / "etc/pivista", root / "etc/NetworkManager/system-connections",
             root / "home", root / "root"]
    for base in bases:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.stat().st_size > 512 * 1024:
                continue
            with contextlib.suppress(OSError, UnicodeDecodeError):
                text = path.read_text(errors="ignore")
                if patterns.search(text):
                    hits.append(str(path.relative_to(root)))
    record("no credentials in image", not hits, ", ".join(hits[:5]))


def check_binary_arch(root: Path, boot: Path) -> None:
    launcher = root / "usr/bin/pivista-launcher"
    if launcher.exists():
        out = run(["file", "-b", str(launcher)])
        record("launcher is aarch64 ELF", "ARM aarch64" in out.stdout or "aarch64" in out.stdout,
               out.stdout.strip())
    kernel = boot / "kernel_2712.img"
    if kernel.exists():
        # Raspberry Pi OS ships kernel_2712.img as a gzip-compressed Image.
        raw = kernel.read_bytes()
        if raw[:2] == b"\x1f\x8b":
            unpacked = subprocess.run(["gzip", "-dc", str(kernel)], capture_output=True)
            info = subprocess.run(["file", "-b", "-"], input=unpacked.stdout,
                                  capture_output=True)
            detail = info.stdout.decode(errors="replace").strip()
            ok = unpacked.returncode == 0 and ("ARM64" in detail or "aarch64" in detail.lower())
            record("Pi 5 kernel is aarch64", ok, "gzip-compressed; " + detail)
        else:
            out = run(["file", "-b", str(kernel)])
            record("Pi 5 kernel is aarch64",
                   "ARM aarch64" in out.stdout or "aarch64" in out.stdout,
                   out.stdout.strip())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--json", action="store_true", help="print machine-readable results")
    args = parser.parse_args()

    image = Path(args.image).resolve()
    if not image.is_file():
        print(f"FAIL image not found: {image}", file=sys.stderr)
        return 2
    if os.geteuid() != 0:
        print("FAIL image validation needs root for loop mounts", file=sys.stderr)
        return 2

    boot_probe = Path(tempfile.mkdtemp(prefix="pivista-boot-"))
    try:
        check_partitions(image)
        try:
            with mounted(image) as (loop_dev, root, boot):
                blkid = run(["blkid", "-s", "PARTUUID", "-o", "value", f"{loop_dev}p2"])
                root_uuid = blkid.stdout.strip() if blkid.returncode == 0 else ""
                cmdline = (boot / "cmdline.txt").read_text(errors="replace") if (boot / "cmdline.txt").is_file() else None
                check_boot_files(boot, cmdline, root_uuid)
                check_rootfs(root)
                check_binary_arch(root, boot)
                check_secrets(root)
        except RuntimeError as exc:
            record("image mounts cleanly", False, str(exc))
    finally:
        with contextlib.suppress(OSError):
            boot_probe.rmdir()

    failed = [r for r in results if r[0] == FAIL]
    if args.json:
        print(json.dumps([{"status": s, "check": n, "detail": d} for s, n, d in results], indent=2))
    else:
        for status, name, detail in results:
            line = f"{status}  {name}"
            if detail:
                line += f"  ({detail})"
            print(line)
        print()
        print(f"{len(results) - len(failed)} passed, {len(failed)} failed, {len(results)} total")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
