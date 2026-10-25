"""Tests for the signed launcher updater, using local fake GitHub releases."""

from __future__ import annotations

import hashlib
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from collections import namedtuple
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "daemon"))

import pivista_update  # noqa: E402
import pivistad  # noqa: E402

Usage = namedtuple("Usage", "total used free")
REPO = "HerbertGaming39/pivista-tv"


def elf(machine: int = 183) -> bytes:
    value = bytearray(64)
    value[0:4] = b"\x7fELF"
    value[4] = 2  # 64-bit
    value[5] = 1  # little endian
    value[6] = 1
    value[16:18] = (2).to_bytes(2, "little")  # ET_EXEC
    value[18:20] = machine.to_bytes(2, "little")
    return bytes(value)


def make_tar(path: pathlib.Path, files: dict[str, bytes]) -> None:
    with tarfile.open(path, "w:xz") as archive:
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o755 if name == "bin/pivista-launcher" else 0o644
            archive.addfile(info, io.BytesIO(data))


def payload(version: str, machine: int = 183, marker: bytes = b"new") -> dict[str, bytes]:
    return {
        "bin/pivista-launcher": elf(machine) + marker,
        "share/pivista/qml/Main.qml": b"import QtQuick\nItem { property string version: \"%s\" }\n" % version.encode(),
        "share/pivista/qml/Theme.qml": b"// " + marker + b"\n",
        "share/pivista/webapps/catalog.json": json.dumps({"apps": [], "version": version}).encode(),
        "share/pivista/version.json": json.dumps({
            "schema": 1, "product": "pivista-tv", "version": version,
            "codename": "Test", "build_id": "test", "architecture": "arm64",
        }).encode(),
    }


class FakeSource:
    def __init__(self, releases, files, download_override=None):
        self.releases = releases
        self.files = files
        self.download_override = download_override
        self.downloads = []

    def list_releases(self):
        return self.releases

    def fetch(self, url, limit):
        data = self.files.get(url)
        if data is None:
            raise pivista_update.UpdateError("network", "missing fake URL")
        if len(data) > limit:
            raise pivista_update.UpdateError("too_large", "fake response too large")
        return data

    def download(self, url, dest, limit, progress=None):
        self.downloads.append(url)
        if self.download_override:
            return self.download_override(url, dest, limit, progress)
        data = self.files[url]
        with open(dest, "wb") as handle:
            handle.write(data)
        if progress:
            progress(len(data), len(data))
        return len(data), hashlib.sha256(data).hexdigest()


class UpdateHarness:
    def __init__(self, tmp: pathlib.Path, base_version: str = "0.3.0"):
        self.tmp = tmp
        self.root = tmp / "root"
        self.state = tmp / "state"
        self.config = tmp / "config"
        for directory in (self.root, self.state, self.config):
            directory.mkdir(parents=True, exist_ok=True)
        (self.root / "usr/bin").mkdir(parents=True)
        (self.root / "usr/share/pivista/qml").mkdir(parents=True)
        (self.root / "usr/share/pivista/webapps").mkdir(parents=True)
        (self.root / "usr/bin/pivista-launcher").write_bytes(elf() + b"old")
        (self.root / "usr/share/pivista/qml/Main.qml").write_text("// old main\n")
        (self.root / "usr/share/pivista/qml/Old.qml").write_text("// old only\n")
        (self.root / "usr/share/pivista/webapps/catalog.json").write_text('{"apps": []}')
        self.write_version(base_version)
        (self.config / "build-info.json").write_text(json.dumps({"version": base_version}))
        self.key = tmp / "update-key.pem"
        self.public = tmp / "update-pubkey.pem"
        subprocess.run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(self.key)],
                       check=True, capture_output=True)
        subprocess.run(["openssl", "pkey", "-in", str(self.key), "-pubout", "-out", str(self.public)],
                       check=True, capture_output=True)
        os.chmod(self.public, 0o644)
        self.files: dict[str, bytes] = {}
        self.releases: list[dict] = []
        self.source = FakeSource(self.releases, self.files)
        self.manager = self.new_manager()

    def new_manager(self, **kwargs):
        options = {
            "root": str(self.root),
            "state_dir": str(self.state),
            "config_dir": str(self.config),
            "public_key": str(self.public),
            "source": self.source,
            "runner": pivistad.Runner(),
        }
        options.update(kwargs)
        return pivista_update.UpdateManager(**options)

    def write_version(self, version: str) -> None:
        (self.root / "usr/share/pivista/version.json").write_text(json.dumps({
            "schema": 1, "product": "pivista-tv", "version": version,
            "codename": "Test", "build_id": "test", "architecture": "arm64",
        }))

    def publish(self, version: str, *, prerelease: bool = False, min_version: str = "0.3.0",
                machine: int = 183, corrupt_signature: bool = False,
                marker: bytes = b"new", notes: str = "Test release notes") -> dict:
        bundle_name = f"pivista-launcher-{version}-arm64.tar.xz"
        bundle_path = self.tmp / bundle_name
        make_tar(bundle_path, payload(version, machine=machine, marker=marker))
        bundle = bundle_path.read_bytes()
        manifest = {
            "schema": 1,
            "product": "pivista-tv",
            "version": version,
            "notes": notes,
            "min_version": min_version,
            "min_system": "0.3.0",
            "components": ["launcher", "qml", "catalog", "version"],
            "bundle": {
                "name": bundle_name,
                "size": len(bundle),
                "sha256": hashlib.sha256(bundle).hexdigest(),
            },
        }
        manifest_bytes = json.dumps(manifest, sort_keys=True).encode()
        manifest_path = self.tmp / f"manifest-{version}.json"
        signature_path = self.tmp / f"signature-{version}.sig"
        manifest_path.write_bytes(manifest_bytes)
        subprocess.run(["openssl", "pkeyutl", "-sign", "-inkey", str(self.key), "-rawin",
                        "-in", str(manifest_path), "-out", str(signature_path)],
                       check=True, capture_output=True)
        signature = signature_path.read_bytes()
        if corrupt_signature:
            signature = bytes([signature[0] ^ 0xFF]) + signature[1:]
        base = f"https://github.com/{REPO}/releases/download/v{version}"
        manifest_url = f"{base}/pivista-update.json"
        signature_url = f"{base}/pivista-update.json.sig"
        bundle_url = f"{base}/{bundle_name}"
        self.files[manifest_url] = manifest_bytes
        self.files[signature_url] = signature
        self.files[bundle_url] = bundle
        release = {
            "tag_name": f"v{version}",
            "draft": False,
            "prerelease": prerelease,
            "html_url": f"https://github.com/{REPO}/releases/tag/v{version}",
            "assets": [
                {"name": "pivista-update.json", "browser_download_url": manifest_url,
                 "size": len(manifest_bytes), "digest": "sha256:" + hashlib.sha256(manifest_bytes).hexdigest()},
                {"name": "pivista-update.json.sig", "browser_download_url": signature_url,
                 "size": len(signature)},
                {"name": bundle_name, "browser_download_url": bundle_url, "size": len(bundle)},
            ],
        }
        self.releases.append(release)
        return release


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="pivista-update-test-"))
        self.harness = UpdateHarness(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_check_discovers_signed_release(self):
        self.harness.publish("0.3.1")
        status = self.harness.manager.check()
        self.assertEqual(status["installed"], "0.3.0")
        self.assertEqual(status["latest"], "0.3.1")
        self.assertTrue(status["available"])
        self.assertIn("Test release", status["notes"])
        self.assertEqual(status["size"], len(self.harness.files[
            "https://github.com/%s/releases/download/v0.3.1/pivista-launcher-0.3.1-arm64.tar.xz" % REPO]))

    def test_check_rejects_bad_signature(self):
        self.harness.publish("0.3.1", corrupt_signature=True)
        with self.assertRaises(pivista_update.UpdateError) as caught:
            self.harness.manager.check()
        self.assertEqual(caught.exception.code, "no_release")
        self.assertIn("signature", caught.exception.message)

    def test_prerelease_is_opt_in(self):
        self.harness.publish("0.3.1")
        self.harness.publish("0.4.0", prerelease=True)
        status = self.harness.manager.check(allow_prerelease=False)
        self.assertEqual(status["latest"], "0.3.1")
        status = self.harness.manager.check(allow_prerelease=True)
        self.assertEqual(status["latest"], "0.4.0")
        self.assertTrue(status["prerelease"])

    def test_incompatible_minimum_version_is_not_offered(self):
        self.harness.publish("0.4.0", min_version="0.4.0")
        status = self.harness.manager.check()
        self.assertEqual(status["latest"], "0.4.0")
        self.assertFalse(status["available"])
        self.assertIn("reflashed", status["reason"])

    def test_download_and_install_then_rollback(self):
        self.harness.publish("0.3.1", marker=b"new")
        self.assertTrue(self.harness.manager.check()["available"])
        downloaded = self.harness.manager.download()
        self.assertEqual(downloaded["job"]["state"], "downloaded")
        installed = self.harness.manager.install()
        self.assertEqual(installed["installed"], "0.3.1")
        self.assertTrue(installed["job"]["restart_required"])
        self.assertEqual((self.harness.root / "usr/share/pivista/qml/Theme.qml").read_bytes(), b"// new\n")
        self.assertFalse((self.harness.root / "usr/share/pivista/qml/Old.qml").exists())
        self.assertTrue(installed["rollback_available"])
        rolled = self.harness.manager.rollback()
        self.assertEqual(rolled["installed"], "0.3.0")
        self.assertEqual((self.harness.root / "usr/share/pivista/qml/Main.qml").read_text(), "// old main\n")
        self.assertTrue((self.harness.root / "usr/share/pivista/qml/Old.qml").exists())
        self.assertFalse(rolled["rollback_available"])

    def test_check_after_install_keeps_the_rollback_copy(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()
        self.harness.manager.download()
        self.harness.manager.install()
        self.harness.publish("0.3.2")
        status = self.harness.manager.check()
        self.assertTrue(status["available"])
        self.assertEqual(status["latest"], "0.3.2")
        self.assertTrue(status["rollback_available"])
        self.assertEqual(status["rollback_version"], "0.3.0")

    def test_only_the_immediately_previous_launcher_is_kept(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()
        self.harness.manager.download()
        self.harness.manager.install()
        self.harness.publish("0.3.2")
        self.harness.manager.check()
        self.harness.manager.download()
        self.harness.manager.install()
        rollbacks = list((self.harness.state / "updates/rollback").iterdir())
        self.assertEqual(len(rollbacks), 1, rollbacks)
        status = self.harness.manager.status()
        self.assertEqual(status["rollback_version"], "0.3.1")
        self.harness.manager.rollback()
        self.assertEqual(self.harness.manager.installed_version(), "0.3.1")
        self.assertEqual(list((self.harness.state / "updates/rollback").iterdir()), [])

    def test_install_preserves_user_data_and_network_configuration(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()
        self.harness.manager.download()
        user_file = self.harness.root / "home/pivista/.config/PiVista/Launcher.conf"
        user_file.parent.mkdir(parents=True)
        user_file.write_text("favourites=netflix,youtube\n")
        connection = self.harness.root / "etc/NetworkManager/system-connections/Home.nmconnection"
        connection.parent.mkdir(parents=True)
        connection.write_text("[connection]\nid=Home\n")
        self.harness.manager.install()
        self.assertEqual(user_file.read_text(), "favourites=netflix,youtube\n")
        self.assertEqual(connection.read_text(), "[connection]\nid=Home\n")

    def test_corrupt_download_is_rejected_and_cleaned(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()

        def corrupt(url, dest, limit, progress):
            with open(dest, "wb") as handle:
                handle.write(b"not the release")
            return len(b"not the release"), hashlib.sha256(b"not the release").hexdigest()

        self.harness.source.download_override = corrupt
        with self.assertRaises(pivista_update.UpdateError) as caught:
            self.harness.manager.download()
        self.assertEqual(caught.exception.code, "checksum")
        self.assertEqual(self.harness.manager.status()["job"]["state"], "failed")
        self.assertFalse(any(self.harness.state.glob("updates/downloads/*.part")))

    def test_interrupted_download_is_rejected(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()

        def interrupted(url, dest, limit, progress):
            with open(dest, "wb") as handle:
                handle.write(b"partial")
            raise pivista_update.UpdateError("network", "connection dropped")

        self.harness.source.download_override = interrupted
        with self.assertRaises(pivista_update.UpdateError):
            self.harness.manager.download()
        self.assertEqual(self.harness.manager.status()["job"]["state"], "failed")
        self.assertIn("connection dropped", self.harness.manager.status()["job"]["error"])

    def test_insufficient_space_is_rejected_before_download(self):
        self.harness.publish("0.3.1")
        manager = self.harness.new_manager(disk_usage=lambda path: Usage(1, 0, 10))
        manager.check()
        with self.assertRaises(pivista_update.UpdateError) as caught:
            manager.download()
        self.assertEqual(caught.exception.code, "insufficient_space")
        self.assertEqual(manager.status()["job"]["state"], "idle")
        self.assertEqual(manager.status()["installed"], "0.3.0")

    def test_tampered_download_is_rejected_at_install(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()
        self.harness.manager.download()
        archive = pathlib.Path(self.harness.state / "updates/downloads/pivista-launcher-0.3.1-arm64.tar.xz")
        with open(archive, "ab") as handle:
            handle.write(b"tamper")
        with self.assertRaises(pivista_update.UpdateError) as caught:
            self.harness.manager.install()
        self.assertEqual(caught.exception.code, "checksum")
        self.assertEqual(self.harness.manager.installed_version(), "0.3.0")

    def test_wrong_architecture_is_rejected(self):
        self.harness.publish("0.3.1", machine=62)
        self.harness.manager.check()
        self.harness.manager.download()
        with self.assertRaises(pivista_update.UpdateError) as caught:
            self.harness.manager.install()
        self.assertEqual(caught.exception.code, "wrong_architecture")
        self.assertEqual(self.harness.manager.installed_version(), "0.3.0")

    def test_failed_swap_restores_previous_installation(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()
        self.harness.manager.download()
        with mock.patch.object(self.harness.manager, "_install_payload",
                               side_effect=pivista_update.UpdateError("install_failed", "injected failure")):
            with self.assertRaises(pivista_update.UpdateError):
                self.harness.manager.install()
        self.assertEqual(self.harness.manager.installed_version(), "0.3.0")
        self.assertEqual((self.harness.root / "usr/share/pivista/qml/Main.qml").read_text(), "// old main\n")
        self.assertEqual(self.harness.manager.status()["job"]["state"], "failed")

    def test_archive_traversal_is_rejected(self):
        archive = self.tmp / "evil.tar.xz"
        with tarfile.open(archive, "w:xz") as bundle:
            info = tarfile.TarInfo("../escape")
            info.size = 3
            bundle.addfile(info, io.BytesIO(b"bad"))
        with self.assertRaises(pivista_update.UpdateError) as caught:
            self.harness.manager._extract_bundle(str(archive), str(self.tmp / "stage"), "0.3.1")
        self.assertEqual(caught.exception.code, "bad_archive")

    def test_periodic_check_keeps_a_verified_download(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()
        self.harness.manager.download()
        checked = self.harness.manager.check()
        self.assertEqual(checked["job"]["state"], "downloaded")
        installed = self.harness.manager.install()
        self.assertEqual(installed["installed"], "0.3.1")

    def test_postpone_marks_the_release(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()
        status = self.harness.manager.postpone("0.3.1")
        self.assertTrue(status["postponed"])
        reloaded = self.harness.new_manager().status()
        self.assertTrue(reloaded["postponed"])

    def test_downgrade_is_not_offered(self):
        self.harness.write_version("0.3.1")
        self.harness.publish("0.3.0")
        status = self.harness.manager.check()
        self.assertEqual(status["latest"], "0.3.0")
        self.assertFalse(status["available"])
        with self.assertRaises(pivista_update.UpdateError) as caught:
            self.harness.manager.download()
        self.assertEqual(caught.exception.code, "no_update")

    def test_https_is_required(self):
        with self.assertRaises(pivista_update.UpdateError):
            pivista_update.validate_https_url("http://github.com/release")
        with self.assertRaises(pivista_update.UpdateError):
            pivista_update.validate_https_url("https://evil.example/release")

    def test_running_job_is_reset_after_daemon_restart(self):
        job_path = self.harness.state / "update-job.json"
        job_path.write_text(json.dumps({"state": "downloading", "progress": 50}))
        manager = self.harness.new_manager()
        self.assertEqual(manager.status()["job"]["state"], "failed")
        self.assertIn("interrupted", manager.status()["job"]["error"])

    def wait_for_job(self, manager, states, timeout=5.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            status = manager.status()
            if status["job"].get("state") in states:
                return status
            time.sleep(0.01)
        self.fail(f"job did not reach {states}: {manager.status()['job']}")

    def test_start_download_publishes_a_job_immediately(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()
        self.harness.manager.start_download()
        # The launcher polls only while a job is active. Returning before the
        # worker thread updates the job would leave progress frozen at idle.
        self.assertIn(self.harness.manager.status()["job"]["state"],
                      {"downloading", "downloaded"})
        status = self.wait_for_job(self.harness.manager, {"downloaded", "failed"})
        self.assertEqual(status["job"]["state"], "downloaded")

    def test_start_install_publishes_a_job_immediately(self):
        self.harness.publish("0.3.1")
        self.harness.manager.check()
        self.harness.manager.download()
        self.harness.manager.start_install()
        self.assertIn(self.harness.manager.status()["job"]["state"],
                      {"installing", "installed"})
        status = self.wait_for_job(self.harness.manager, {"installed", "failed"})
        self.assertEqual(status["job"]["state"], "installed")
        self.assertEqual(status["installed"], "0.3.1")

    def test_malformed_manifest_fields_are_rejected_cleanly(self):
        version = (0, 3, 1)
        release = {"assets": []}
        for components, name in (([{"launcher": True}], "bundle"),
                                  (["launcher"], 7)):
            manifest = {
                "schema": 1, "product": "pivista-tv", "version": "0.3.1",
                "components": components,
                "bundle": {"name": name, "size": 10, "sha256": "0" * 64},
            }
            with self.assertRaises(pivista_update.UpdateError) as caught:
                self.harness.manager._parse_manifest(json.dumps(manifest).encode(), version, release)
            self.assertIn(caught.exception.code, {"bad_manifest", "missing_asset"})


if __name__ == "__main__":
    unittest.main()
