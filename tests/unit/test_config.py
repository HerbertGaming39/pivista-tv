"""Consistency checks between config/product.env, the manifest and the docs."""

from __future__ import annotations

import pathlib
import re
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

    def test_no_placeholder_credentials_in_tree(self) -> None:
        patterns = re.compile(
            r"(BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,})"
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
