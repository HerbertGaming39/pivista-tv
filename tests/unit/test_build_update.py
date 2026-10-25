"""Tests for tools/build-app-update.py."""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools/build-app-update.py"


def elf() -> bytes:
    value = bytearray(64)
    value[0:4] = b"\x7fELF"
    value[4] = 2
    value[5] = 1
    value[18:20] = (183).to_bytes(2, "little")
    return bytes(value)


class BuildUpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="pivista-build-update-"))
        self.image = self.tmp / "image"
        (self.image / "usr/bin").mkdir(parents=True)
        (self.image / "usr/share/pivista/qml").mkdir(parents=True)
        (self.image / "usr/share/pivista/webapps").mkdir(parents=True)
        (self.image / "usr/bin/pivista-launcher").write_bytes(elf() + b"launcher")
        (self.image / "usr/share/pivista/qml/Main.qml").write_text("import QtQuick\nItem {}\n")
        (self.image / "usr/share/pivista/qml/Theme.qml").write_text("// theme\n")
        (self.image / "usr/share/pivista/webapps/catalog.json").write_text('{"apps": []}\n')
        (self.image / "usr/share/pivista/version.json").write_text(json.dumps({
            "schema": 1, "product": "pivista-tv", "version": "0.3.0",
            "codename": "Cascade", "build_id": "test", "architecture": "arm64",
        }))
        self.key = self.tmp / "key.pem"
        subprocess.run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(self.key)],
                       check=True, capture_output=True)
        self.out = self.tmp / "out"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def build(self):
        return subprocess.run([
            "python3", str(TOOL), "--image-root", str(self.image), "--out", str(self.out),
            "--version", "0.3.0", "--key", str(self.key), "--notes", "Builder test",
        ], capture_output=True, text=True)

    def test_builds_signed_archive_and_manifest(self):
        completed = self.build()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        bundle = self.out / "pivista-launcher-0.3.0-arm64.tar.xz"
        manifest_path = self.out / "pivista-update.json"
        signature = self.out / "pivista-update.json.sig"
        self.assertTrue(bundle.is_file())
        self.assertTrue(manifest_path.is_file())
        self.assertTrue(signature.is_file())
        manifest = json.loads(manifest_path.read_text())
        self.assertEqual(manifest["bundle"]["sha256"], hashlib.sha256(bundle.read_bytes()).hexdigest())
        self.assertEqual(manifest["min_version"], "0.3.0")
        # The public key is derived here to prove the signature is usable by an
        # installed key, not just that an arbitrary signature exists.
        subprocess.run(["openssl", "pkey", "-in", str(self.key), "-pubout",
                        "-out", str(self.tmp / "pub.pem")], check=True, capture_output=True)
        verify = subprocess.run([
            "openssl", "pkeyutl", "-verify", "-pubin", "-inkey", str(self.tmp / "pub.pem"),
            "-rawin", "-in", str(manifest_path), "-sigfile", str(signature),
        ], capture_output=True, text=True)
        self.assertEqual(verify.returncode, 0, verify.stderr)

    def test_archive_contains_only_expected_paths(self):
        completed = self.build()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        bundle = self.out / "pivista-launcher-0.3.0-arm64.tar.xz"
        with tarfile.open(bundle, "r:xz") as archive:
            names = sorted(archive.getnames())
        self.assertEqual(names, [
            "bin/pivista-launcher",
            "share/pivista/qml/Main.qml",
            "share/pivista/qml/Theme.qml",
            "share/pivista/version.json",
            "share/pivista/webapps/catalog.json",
        ])

    def test_build_is_deterministic(self):
        first = self.build()
        self.assertEqual(first.returncode, 0, first.stderr)
        bundle = self.out / "pivista-launcher-0.3.0-arm64.tar.xz"
        digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
        shutil.rmtree(self.out)
        second = self.build()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(hashlib.sha256(bundle.read_bytes()).hexdigest(), digest)


if __name__ == "__main__":
    unittest.main()
