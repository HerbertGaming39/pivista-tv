"""Consistency checks between config/product.env, the manifest and the docs."""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read_env(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"')
    return values


class ProductConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.product = read_env(ROOT / "config/product.env")
        self.base = read_env(ROOT / "manifest/base-image.lock")
        self.image = (ROOT / "manifest/image-config.yaml").read_text(encoding="utf-8")

    def test_identity_is_complete(self) -> None:
        for key in ("PIVISTA_NAME", "PIVISTA_SLUG", "PIVISTA_VERSION", "PIVISTA_CODENAME"):
            self.assertTrue(self.product.get(key), key)

    def test_base_image_is_pinned_by_sha256(self) -> None:
        self.assertRegex(self.base["BASE_IMAGE_SHA256"], r"^[0-9a-f]{64}$")
        self.assertIn(self.base["BASE_IMAGE_SHA256"], self.image)
        self.assertNotIn("latest", self.base["BASE_IMAGE_URL"])
        self.assertTrue(self.base["BASE_IMAGE_URL"].endswith(".img.xz"))

    def test_architecture_matches_target(self) -> None:
        self.assertEqual(self.product["PIVISTA_ARCH"], "arm64")
        self.assertEqual(self.base["BASE_IMAGE_ARCH"], "arm64")
        self.assertIn("architecture: arm64", self.image)

    def test_partition_geometry_matches_documentation(self) -> None:
        self.assertIn(f"size_gb: {self.product['PIVISTA_ROOT_PART_GB']}", self.image)
        self.assertIn(f"size_mb: {self.product['PIVISTA_BOOT_PART_MB']}", self.image)

    def test_session_user_and_uid(self) -> None:
        self.assertEqual(self.product["PIVISTA_USER"], "pivista")
        self.assertEqual(self.product["PIVISTA_UID"], "1000")
        self.assertIn("user: pivista", self.image)

    def test_package_sections_are_well_formed(self) -> None:
        text = (ROOT / "manifest/packages.lock").read_text(encoding="utf-8")
        sections = re.findall(r"^\[([a-z-]+)\]$", text, re.M)
        self.assertIn("runtime", sections)
        self.assertIn("build", sections)
        self.assertIn("purge", sections)
        # The optional Android section must never be installed by default.
        build_sh = (ROOT / "build.sh").read_text(encoding="utf-8")
        self.assertNotIn("optional-android", build_sh)
        common = (ROOT / "build/lib/common.sh").read_text(encoding="utf-8")
        self.assertNotIn("optional-android", common)

    def test_base_metadata_is_exported_for_artifact_manifest(self) -> None:
        """The manifest generator is a child process and needs BASE_* in env.

        Regression: load_config() sourced manifest/base-image.lock but did not
        export it, so every release manifest had an empty "base" object.
        """
        keys = (
            "BASE_IMAGE_NAME", "BASE_IMAGE_URL", "BASE_IMAGE_SHA256",
            "BASE_IMAGE_RELEASE", "BASE_IMAGE_DEBIAN", "BASE_IMAGE_KERNEL",
        )
        with tempfile.TemporaryDirectory() as work:
            env = dict(os.environ)
            env["PIVISTA_WORK_DIR"] = work
            env["PIVISTA_BUILD_ID"] = "test-manifest-base"
            script = (
                'set -euo pipefail\n'
                f'PROJECT_DIR={str(ROOT)!r}\n'
                'source "$PROJECT_DIR/build/lib/common.sh"\n'
                'load_config\n'
                + "\n".join(f'printf "%s\\n" "${key}"' for key in keys)
                + "\n"
            )
            completed = subprocess.run(
                ["bash", "-c", script], env=env, capture_output=True, text=True,
                timeout=20,
            )
            log = ROOT / "build/logs/build-test-manifest-base.log"
            log.unlink(missing_ok=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            values = completed.stdout.splitlines()
            self.assertEqual(len(values), len(keys), completed.stdout)
            for key, value in zip(keys, values):
                self.assertTrue(value, f"{key} was not exported")
                self.assertEqual(value, self.base[key], key)

    def test_no_placeholder_credentials_in_tree(self) -> None:
        patterns = re.compile(
            r"(BEGIN [A-Z0-9 ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,})"
        )
        offenders = []
        for path in (ROOT / "system").rglob("*"):
            if path.is_file():
                with path.open(encoding="utf-8", errors="ignore") as fh:
                    if patterns.search(fh.read()):
                        offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
