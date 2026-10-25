"""Signed application updates for PiVista TV.

This module is deliberately limited to replacing the launcher application
(binary, QML, curated web catalog and version file). It never executes a script
from a release and never writes a full disk image over the running root
filesystem. OS packages stay on apt; full-image updates would need an A/B
partition layout and are documented separately.

Trust model:
  * release metadata comes from the official GitHub repository over HTTPS;
  * the small update manifest is signed with an Ed25519 key whose public half is
    installed in /etc/pivista/update-pubkey.pem;
  * the launcher archive is identified by the GitHub release asset list and
    verified by SHA-256 before it is unpacked;
  * only fixed, named paths are accepted from the archive;
  * installation is staged and swapped with rollback backups.
"""

from __future__ import annotations

import hashlib
import json
import os
import posixpath
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

PRODUCT = "pivista-tv"
REPOSITORY = "HerbertGaming39/pivista-tv"
SCHEMA = 1
API_URL = f"https://api.github.com/repos/{REPOSITORY}/releases"
MANIFEST_ASSET = "pivista-update.json"
SIGNATURE_ASSET = "pivista-update.json.sig"
DEFAULT_PUBLIC_KEY = "/etc/pivista/update-pubkey.pem"
MAX_MANIFEST = 256 * 1024
MAX_SIGNATURE = 8 * 1024
MAX_BUNDLE = 64 * 1024 * 1024
MAX_MEMBERS = 4000
MAX_NOTES = 20000
MIN_FREE_AFTER_DOWNLOAD = 128 * 1024 * 1024
ACTIVE_STATES = {"downloading", "installing"}
ALLOWED_HOSTS = {
    "api.github.com",
    "github.com",
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
}
VERSION_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
ASSET_RE = re.compile(r"^pivista-launcher-([0-9]+\.[0-9]+\.[0-9]+)-arm64\.tar\.xz$")
ALLOWED_DIRS = {"bin", "share", "share/pivista", "share/pivista/qml",
                "share/pivista/webapps"}
REQUIRED_ENTRIES = {
    "bin/pivista-launcher",
    "share/pivista/qml/Main.qml",
    "share/pivista/webapps/catalog.json",
    "share/pivista/version.json",
}


class UpdateError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class CommandRunner:
    """Minimal command runner used for OpenSSL verification."""

    def run(self, argv: list[str], timeout: int = 20, env: dict[str, str] | None = None,
            check: bool = False) -> subprocess.CompletedProcess:
        completed = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                                   env=env, check=False)
        if check and completed.returncode != 0:
            raise UpdateError("command_failed", "the verification command failed")
        return completed


def parse_version(value: Any) -> tuple[int, int, int]:
    if not isinstance(value, str) or not VERSION_RE.fullmatch(value.strip()):
        raise UpdateError("invalid_version", "release version is not a stable semantic version")
    major, minor, patch = value.strip().split(".")
    return int(major), int(minor), int(patch)


def version_text(value: tuple[int, int, int]) -> str:
    return ".".join(str(part) for part in value)


def validate_https_url(value: Any) -> str:
    """Only HTTPS URLs on the official GitHub release hosts are accepted."""
    if not isinstance(value, str) or not value:
        raise UpdateError("invalid_url", "the release metadata contains an invalid URL")
    parsed = urlsplit(value)
    if parsed.scheme != "https":
        raise UpdateError("invalid_url", "release URLs must use HTTPS")
    if parsed.username or parsed.password:
        raise UpdateError("invalid_url", "release URLs must not contain credentials")
    try:
        port = parsed.port
    except ValueError as exc:
        raise UpdateError("invalid_url", "release URL has an invalid port") from exc
    if port not in (None, 443):
        raise UpdateError("invalid_url", "release URLs must use port 443")
    host = (parsed.hostname or "").lower()
    if host not in ALLOWED_HOSTS:
        raise UpdateError("invalid_host", "the release URL is not hosted by GitHub")
    if not parsed.path.startswith("/"):
        raise UpdateError("invalid_url", "release URL has no path")
    return value


def _asset_by_name(release: dict[str, Any], name: str) -> dict[str, Any]:
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise UpdateError("bad_release", "GitHub release has no asset list")
    matches = [asset for asset in assets
               if isinstance(asset, dict) and asset.get("name") == name]
    if len(matches) != 1:
        raise UpdateError("missing_asset", f"the release does not contain exactly one {name}")
    asset = matches[0]
    url = validate_https_url(asset.get("browser_download_url"))
    try:
        size = int(asset.get("size", 0))
    except (TypeError, ValueError) as exc:
        raise UpdateError("bad_asset", "release asset has an invalid size") from exc
    if size < 0 or size > MAX_BUNDLE:
        raise UpdateError("bad_asset", "release asset is too large")
    return {"name": name, "url": url, "size": size,
            "digest": asset.get("digest") if isinstance(asset.get("digest"), str) else None}


class GitHubReleaseSource:
    """HTTPS client for GitHub releases. Network and TLS come from urllib."""

    def __init__(self, api_url: str = API_URL, timeout: int = 20,
                 opener: Callable[..., Any] = urlopen, user_agent: str = "PiVista-TV/0.3") -> None:
        self.api_url = validate_https_url(api_url)
        self.timeout = timeout
        self.opener = opener
        self.user_agent = user_agent

    def _open(self, url: str) -> Any:
        url = validate_https_url(url)
        request = Request(url, headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": self.user_agent,
            "X-GitHub-Api-Version": "2022-11-28",
        })
        try:
            response = self.opener(request, timeout=self.timeout)
        except HTTPError as exc:
            raise UpdateError("network", f"GitHub returned HTTP {exc.code}") from None
        except (URLError, TimeoutError, OSError):
            raise UpdateError("network", "the update server could not be reached") from None
        final = response.geturl() if hasattr(response, "geturl") else url
        if (urlsplit(final).hostname or "").lower() not in ALLOWED_HOSTS:
            response.close()
            raise UpdateError("invalid_host", "the update server redirected outside GitHub")
        return response

    def _read(self, url: str, limit: int) -> bytes:
        with self._open(url) as response:
            declared = response.headers.get("Content-Length") if hasattr(response, "headers") else None
            if declared and declared.isdigit() and int(declared) > limit:
                raise UpdateError("too_large", "the release metadata is too large")
            body = response.read(limit + 1)
        if len(body) > limit:
            raise UpdateError("too_large", "the release metadata is too large")
        return body

    def list_releases(self) -> list[dict[str, Any]]:
        data = self._read(self.api_url, 1024 * 1024)
        try:
            releases = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise UpdateError("bad_release", "GitHub returned invalid release metadata") from None
        if not isinstance(releases, list):
            raise UpdateError("bad_release", "GitHub returned an unexpected release list")
        return [release for release in releases if isinstance(release, dict)]

    def fetch(self, url: str, limit: int) -> bytes:
        return self._read(url, limit)

    def download(self, url: str, dest: str, limit: int,
                 progress: Callable[[int, int], None] | None = None) -> tuple[int, str]:
        url = validate_https_url(url)
        digest = hashlib.sha256()
        written = 0
        with self._open(url) as response:
            declared = response.headers.get("Content-Length") if hasattr(response, "headers") else None
            total = int(declared) if declared and declared.isdigit() else 0
            if total > limit:
                raise UpdateError("too_large", "the update archive is too large")
            with open(dest, "wb") as handle:
                while True:
                    chunk = response.read(64 * 1024)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > limit:
                        raise UpdateError("too_large", "the update archive is too large")
                    handle.write(chunk)
                    digest.update(chunk)
                    if progress:
                        progress(written, total)
                handle.flush()
                os.fsync(handle.fileno())
        return written, digest.hexdigest()


class UpdateManager:
    """Stateful, root-owned updater for the launcher application."""

    def __init__(self, *, root: str = "/", state_dir: str = "/var/lib/pivista",
                 config_dir: str = "/etc/pivista",
                 public_key: str = DEFAULT_PUBLIC_KEY,
                 source: Any = None, runner: Any = None,
                 disk_usage: Callable[[str], Any] = shutil.disk_usage,
                 clock: Callable[[], float] = time.time) -> None:
        self.root = os.path.abspath(root)
        self.state_dir = os.path.abspath(state_dir)
        self.config_dir = os.path.abspath(config_dir)
        self.public_key = os.path.abspath(public_key)
        self.source = source or GitHubReleaseSource()
        self.runner = runner or CommandRunner()
        self.disk_usage = disk_usage
        self.clock = clock
        self._lock = threading.RLock()
        self._job_path = os.path.join(self.state_dir, "update-job.json")
        self._state_path = os.path.join(self.state_dir, "app-update.json")
        self._job = self._load_job()

    # -- paths ------------------------------------------------------------
    def _root_path(self, relative: str) -> str:
        return os.path.join(self.root, relative.lstrip("/")) if self.root != "/" \
            else os.path.join("/", relative.lstrip("/"))

    @property
    def version_path(self) -> str:
        return self._root_path("usr/share/pivista/version.json")

    @property
    def launcher_path(self) -> str:
        return self._root_path("usr/bin/pivista-launcher")

    @property
    def qml_path(self) -> str:
        return self._root_path("usr/share/pivista/qml")

    @property
    def catalog_path(self) -> str:
        return self._root_path("usr/share/pivista/webapps/catalog.json")

    @property
    def build_info_path(self) -> str:
        return os.path.join(self.config_dir, "build-info.json")

    @property
    def cache_dir(self) -> str:
        return os.path.join(self.state_dir, "updates", "cache")

    @property
    def download_dir(self) -> str:
        return os.path.join(self.state_dir, "updates", "downloads")

    @property
    def staging_dir(self) -> str:
        return os.path.join(self.state_dir, "updates", "staging")

    @property
    def rollback_root(self) -> str:
        return os.path.join(self.state_dir, "updates", "rollback")

    # -- version ----------------------------------------------------------
    def _read_json(self, path: str) -> dict[str, Any]:
        try:
            with open(path, encoding="utf-8") as handle:
                value = json.load(handle)
        except (OSError, json.JSONDecodeError):
            return {}
        return value if isinstance(value, dict) else {}

    def installed_version(self) -> str:
        info = self._read_json(self.version_path)
        if not info:
            info = self._read_json(self.build_info_path)
        value = info.get("version")
        parse_version(value)
        return str(value)

    def system_version(self) -> str:
        value = self._read_json(self.build_info_path).get("version")
        parse_version(value)
        return str(value)

    # -- job state --------------------------------------------------------
    def _load_job(self) -> dict[str, Any]:
        try:
            with open(self._job_path, encoding="utf-8") as handle:
                value = json.load(handle)
            job = value if isinstance(value, dict) else {}
        except (OSError, json.JSONDecodeError):
            job = {}
        if not job:
            job = {"state": "idle"}
        if job.get("state") in ACTIVE_STATES:
            # The thread that owned this job died with a previous daemon
            # process. Never leave the UI showing a permanent spinner.
            job.update({"state": "failed", "error": "the previous update was interrupted"})
        job.setdefault("progress", 0)
        return job

    def _write_json(self, path: str, value: dict[str, Any], mode: int = 0o600) -> None:
        os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
        temporary = path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)

    def _set_job(self, **changes: Any) -> None:
        with self._lock:
            self._job.update(changes)
            self._job.setdefault("progress", 0)
            self._write_json(self._job_path, self._job)

    def _load_state(self) -> dict[str, Any]:
        return self._read_json(self._state_path)

    def _save_state(self, value: dict[str, Any]) -> None:
        self._write_json(self._state_path, value)

    # -- signature / manifest --------------------------------------------
    def _verify_signature(self, manifest: bytes, signature: bytes) -> None:
        if not signature or len(signature) > MAX_SIGNATURE:
            raise UpdateError("unsigned", "the update manifest has no valid signature")
        try:
            info = os.lstat(self.public_key)
        except OSError:
            raise UpdateError("trust_unavailable", "the PiVista update public key is missing") from None
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            raise UpdateError("trust_unavailable", "the PiVista update public key is not a regular file")
        if info.st_mode & 0o022:
            raise UpdateError("trust_unavailable", "the PiVista update public key is writable by non-owners")
        if os.geteuid() == 0 and info.st_uid != 0:
            raise UpdateError("trust_unavailable", "the PiVista update public key is not owned by root")
        temporary_dir = tempfile.mkdtemp(prefix="update-sig-", dir=self._ensure_state())
        manifest_path = os.path.join(temporary_dir, "manifest.json")
        signature_path = os.path.join(temporary_dir, "manifest.sig")
        try:
            for path, data in ((manifest_path, manifest), (signature_path, signature)):
                with open(path, "wb") as handle:
                    handle.write(data)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.chmod(path, 0o600)
            try:
                completed = self.runner.run([
                    "openssl", "pkeyutl", "-verify", "-pubin", "-inkey", self.public_key,
                    "-rawin", "-in", manifest_path, "-sigfile", signature_path,
                ], timeout=10)
            except Exception:
                raise UpdateError("trust_unavailable", "OpenSSL could not verify the update manifest") from None
            if completed.returncode != 0:
                raise UpdateError("bad_signature", "the update manifest signature is not valid")
        finally:
            shutil.rmtree(temporary_dir, ignore_errors=True)

    def _ensure_state(self) -> str:
        os.makedirs(self.state_dir, mode=0o700, exist_ok=True)
        return self.state_dir

    def _parse_manifest(self, manifest: bytes, release_version: tuple[int, int, int],
                        release: dict[str, Any]) -> dict[str, Any]:
        try:
            value = json.loads(manifest.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise UpdateError("bad_manifest", "the update manifest is not valid JSON") from None
        if not isinstance(value, dict):
            raise UpdateError("bad_manifest", "the update manifest is not an object")
        if value.get("schema") != SCHEMA or value.get("product") != PRODUCT:
            raise UpdateError("incompatible", "this update belongs to a different product")
        version = parse_version(value.get("version"))
        if version != release_version:
            raise UpdateError("incompatible", "the manifest version does not match the release tag")
        notes = value.get("notes", "")
        if not isinstance(notes, str):
            notes = ""
        notes = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", notes).strip()
        if len(notes) > MAX_NOTES:
            raise UpdateError("bad_manifest", "the release notes are too long")
        bundle = value.get("bundle")
        if not isinstance(bundle, dict):
            raise UpdateError("bad_manifest", "the update manifest has no bundle")
        name = bundle.get("name")
        if not isinstance(name, str):
            raise UpdateError("bad_manifest", "the update archive name is not valid")
        match = ASSET_RE.fullmatch(name)
        if not match or parse_version(match.group(1)) != version:
            raise UpdateError("bad_manifest", "the update archive name is not valid")
        try:
            size = int(bundle.get("size"))
        except (TypeError, ValueError):
            raise UpdateError("bad_manifest", "the update archive size is not valid") from None
        if size <= 0 or size > MAX_BUNDLE:
            raise UpdateError("bad_manifest", "the update archive size is not valid")
        sha = bundle.get("sha256")
        if not isinstance(sha, str) or not SHA_RE.fullmatch(sha):
            raise UpdateError("bad_manifest", "the update archive checksum is not valid")
        min_version = value.get("min_version")
        if min_version is not None:
            parse_version(min_version)
        min_system = value.get("min_system")
        if min_system is not None:
            parse_version(min_system)
        components = value.get("components")
        if (not isinstance(components, list)
                or not all(isinstance(component, str) for component in components)
                or set(components) != {"launcher", "qml", "catalog", "version"}):
            raise UpdateError("bad_manifest", "the update component list is not supported")
        bundle_asset = _asset_by_name(release, name)
        if bundle_asset["size"] and bundle_asset["size"] != size:
            raise UpdateError("bad_manifest", "the manifest size does not match the GitHub asset")
        return {
            "version": version_text(version),
            "version_tuple": version,
            "notes": notes,
            "bundle": {
                "name": name,
                "size": size,
                "sha256": sha,
                "url": bundle_asset["url"],
                "asset_size": bundle_asset["size"],
            },
            "min_version": version_text(parse_version(min_version)) if min_version else "0.0.0",
            "min_system": version_text(parse_version(min_system)) if min_system else "0.0.0",
            "components": sorted(components),
            "prerelease": bool(release.get("prerelease")),
            "release_url": str(release.get("html_url") or ""),
            "release_tag": str(release.get("tag_name") or ""),
        }

    def _fetch_manifest(self, release: dict[str, Any], version: tuple[int, int, int]) -> tuple[bytes, bytes, dict[str, Any]]:
        manifest_asset = _asset_by_name(release, MANIFEST_ASSET)
        signature_asset = _asset_by_name(release, SIGNATURE_ASSET)
        manifest = self.source.fetch(manifest_asset["url"], MAX_MANIFEST)
        signature = self.source.fetch(signature_asset["url"], MAX_SIGNATURE)
        digest = manifest_asset.get("digest")
        if digest:
            expected = digest[7:] if digest.startswith("sha256:") else ""
            if expected and hashlib.sha256(manifest).hexdigest() != expected:
                raise UpdateError("checksum", "the GitHub manifest digest does not match")
        self._verify_signature(manifest, signature)
        parsed = self._parse_manifest(manifest, version, release)
        return manifest, signature, parsed

    # -- check -------------------------------------------------------------
    def check(self, allow_prerelease: bool = False) -> dict[str, Any]:
        installed = self.installed_version()
        system = self.system_version()
        try:
            releases = self.source.list_releases()
        except UpdateError:
            raise
        except Exception:
            raise UpdateError("network", "the update server could not be reached") from None
        candidates: list[tuple[tuple[int, int, int], dict[str, Any]]] = []
        for release in releases:
            if release.get("draft") is True:
                continue
            if release.get("prerelease") is True and not allow_prerelease:
                continue
            tag = release.get("tag_name")
            if not isinstance(tag, str) or not tag.startswith("v"):
                continue
            try:
                version = parse_version(tag[1:])
            except UpdateError:
                continue
            candidates.append((version, release))
        candidates.sort(key=lambda item: item[0], reverse=True)

        errors: list[str] = []
        for version, release in candidates:
            try:
                manifest, signature, parsed = self._fetch_manifest(release, version)
            except UpdateError as exc:
                errors.append(f"{version_text(version)}: {exc.message}")
                continue
            installed_tuple = parse_version(installed)
            system_tuple = parse_version(system)
            reason = ""
            compatible = True
            if installed_tuple < parse_version(parsed["min_version"]):
                compatible = False
                reason = (f"version {parsed['version']} needs PiVista {parsed['min_version']} "
                          "or newer; this image must be reflashed once")
            elif system_tuple < parse_version(parsed["min_system"]):
                compatible = False
                reason = (f"version {parsed['version']} needs system image {parsed['min_system']} "
                          "or newer; reflash the image")
            available = compatible and version > installed_tuple
            self._store_check(installed, parsed, manifest, signature, available, reason)
            return self.status()

        if candidates:
            detail = "; ".join(errors[:3]) if errors else "no release contains a valid signed manifest"
            raise UpdateError("no_release", detail)
        raise UpdateError("no_release", "no stable PiVista release was found")

    def _store_check(self, installed: str, parsed: dict[str, Any], manifest: bytes,
                     signature: bytes, available: bool, reason: str) -> None:
        version = parsed["version"]
        previous = self._load_state()
        cache = os.path.join(self.cache_dir, version)
        os.makedirs(cache, mode=0o700, exist_ok=True)
        manifest_path = os.path.join(cache, MANIFEST_ASSET)
        signature_path = os.path.join(cache, SIGNATURE_ASSET)
        for path, data in ((manifest_path, manifest), (signature_path, signature)):
            with open(path, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(path, 0o600)
        state = {
            "schema": SCHEMA,
            "installed": installed,
            "latest": version,
            "available": available,
            "prerelease": parsed["prerelease"],
            "reason": reason,
            "notes": parsed["notes"],
            "size": parsed["bundle"]["size"],
            "sha256": parsed["bundle"]["sha256"],
            "bundle_name": parsed["bundle"]["name"],
            "bundle_url": parsed["bundle"]["url"],
            "release_tag": parsed["release_tag"],
            "release_url": parsed["release_url"],
            "min_version": parsed["min_version"],
            "min_system": parsed["min_system"],
            "checked_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "manifest_path": manifest_path,
            "signature_path": signature_path,
            "manifest": parsed,
        }
        # A periodic check must not make an already downloaded archive look
        # missing. Carry it forward only when it is the same release and its
        # bytes still match the signed manifest.
        if (previous.get("latest") == version
                and previous.get("sha256") == parsed["bundle"]["sha256"]):
            old_download = previous.get("download_path")
            if isinstance(old_download, str) and os.path.isfile(old_download) \
                    and os.path.getsize(old_download) == parsed["bundle"]["size"] \
                    and _sha256_file(old_download) == parsed["bundle"]["sha256"]:
                state["download_path"] = old_download
                state["downloaded_at"] = previous.get("downloaded_at", "")
            if previous.get("postponed_version") == version:
                state["postponed_version"] = version
                state["postponed_at"] = previous.get("postponed_at", "")
        old_rollback = previous.get("rollback_path")
        if isinstance(old_rollback, str) and os.path.isdir(old_rollback):
            state["rollback_path"] = old_rollback
            state["rollback_version"] = previous.get("rollback_version", "")
        self._save_state(state)

    def _cached(self) -> dict[str, Any]:
        state = self._load_state()
        if not state:
            raise UpdateError("not_checked", "check for updates first")
        return state

    def _verify_cached(self, state: dict[str, Any]) -> dict[str, Any]:
        manifest_path = state.get("manifest_path")
        signature_path = state.get("signature_path")
        if not isinstance(manifest_path, str) or not isinstance(signature_path, str):
            raise UpdateError("not_checked", "the cached update metadata is incomplete")
        try:
            with open(manifest_path, "rb") as handle:
                manifest = handle.read(MAX_MANIFEST + 1)
            with open(signature_path, "rb") as handle:
                signature = handle.read(MAX_SIGNATURE + 1)
        except OSError:
            raise UpdateError("not_checked", "the cached update metadata is missing") from None
        if len(manifest) > MAX_MANIFEST:
            raise UpdateError("bad_manifest", "the cached manifest is too large")
        version = parse_version(state.get("latest"))
        self._verify_signature(manifest, signature)
        release = {
            "prerelease": bool(state.get("prerelease")),
            "html_url": state.get("release_url", ""),
            "tag_name": state.get("release_tag", ""),
            "assets": [{
                "name": state.get("bundle_name"),
                "browser_download_url": state.get("bundle_url"),
                "size": state.get("size", 0),
            }],
        }
        parsed = self._parse_manifest(manifest, version, release)
        return parsed

    # -- status ------------------------------------------------------------
    def status(self) -> dict[str, Any]:
        try:
            installed = self.installed_version()
        except UpdateError:
            installed = "unknown"
        state = self._load_state()
        latest = state.get("latest") if isinstance(state.get("latest"), str) else ""
        available = False
        if latest and installed != "unknown" and state.get("available") is True:
            try:
                available = parse_version(latest) > parse_version(installed)
            except UpdateError:
                available = False
        postponed = bool(available and state.get("postponed_version") == latest)
        rollback = state.get("rollback_path")
        rollback_available = bool(rollback and os.path.isdir(rollback))
        job = dict(self._job)
        job.pop("thread", None)
        return {
            "installed": installed,
            "latest": latest or installed,
            "available": available,
            "prerelease": bool(state.get("prerelease")),
            "notes": state.get("notes", "") if available else "",
            "size": int(state.get("size", 0) or 0),
            "sha256": state.get("sha256", ""),
            "release_url": state.get("release_url", ""),
            "release_tag": state.get("release_tag", ""),
            "checked_at": state.get("checked_at", ""),
            "reason": state.get("reason", ""),
            "postponed": postponed,
            "postponed_version": state.get("postponed_version", ""),
            "job": job,
            "rollback_available": rollback_available,
            "rollback_version": state.get("rollback_version", ""),
        }

    # -- download ----------------------------------------------------------
    def _job_active(self) -> bool:
        with self._lock:
            return self._job.get("state") in ACTIVE_STATES

    def _check_download_preconditions(self, allow_prerelease: bool) -> tuple[dict[str, Any], dict[str, Any]]:
        state = self._cached()
        parsed = self._verify_cached(state)
        if state.get("prerelease") and not allow_prerelease:
            raise UpdateError("prerelease_disabled", "enable prerelease updates before downloading this build")
        installed = parse_version(self.installed_version())
        if parse_version(parsed["version"]) <= installed:
            raise UpdateError("no_update", "this PiVista version is already installed")
        if installed < parse_version(parsed["min_version"]):
            raise UpdateError("incompatible", f"this update requires PiVista {parsed['min_version']}")
        if parse_version(self.system_version()) < parse_version(parsed["min_system"]):
            raise UpdateError("incompatible", f"this update requires system image {parsed['min_system']}")
        return state, parsed

    def download(self, *, version: str | None = None, allow_prerelease: bool = False,
                 progress: Callable[[int, int], None] | None = None,
                 claimed: bool = False) -> dict[str, Any]:
        # `claimed` is used by start_download(), which has already published a
        # running job so the UI starts polling immediately. A direct call still
        # refuses to race an active job.
        with self._lock:
            if not claimed and self._job.get("state") in ACTIVE_STATES:
                raise UpdateError("busy", "another update is already running")
        state = self._cached()
        if version is not None and version != state.get("latest"):
            self.check(allow_prerelease)
            state = self._cached()
        state, parsed = self._check_download_preconditions(allow_prerelease)
        os.makedirs(self.download_dir, mode=0o700, exist_ok=True)
        archive = os.path.join(self.download_dir, parsed["bundle"]["name"])
        expected_sha = parsed["bundle"]["sha256"]
        if os.path.isfile(archive) and _sha256_file(archive) == expected_sha \
                and os.path.getsize(archive) == parsed["bundle"]["size"]:
            state["download_path"] = archive
            state["downloaded_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            self._save_state(state)
            self._set_job(state="downloaded", version=parsed["version"], progress=100,
                          downloaded=parsed["bundle"]["size"], total=parsed["bundle"]["size"],
                          message="ready to install", error="", restart_required=False)
            return self.status()

        usage = self.disk_usage(self.state_dir)
        free = int(getattr(usage, "free", 0))
        if free < parsed["bundle"]["size"] + MIN_FREE_AFTER_DOWNLOAD:
            raise UpdateError("insufficient_space",
                              "not enough free disk space to download this update safely")

        partial = archive + ".part"
        try:
            os.unlink(partial)
        except OSError:
            pass
        self._set_job(state="downloading", version=parsed["version"], progress=0,
                      downloaded=0, total=parsed["bundle"]["size"],
                      message="downloading from GitHub", error="", restart_required=False)
        last = [0.0]

        def report(done: int, total: int) -> None:
            now = self.clock()
            if now - last[0] < 0.25 and done != parsed["bundle"]["size"]:
                return
            last[0] = now
            percent = int(done * 100 / total) if total else 0
            self._set_job(state="downloading", downloaded=done,
                          total=total or parsed["bundle"]["size"],
                          progress=max(0, min(99, percent)))
            if progress:
                progress(done, total)

        try:
            written, digest = self.source.download(parsed["bundle"]["url"], partial,
                                                   MAX_BUNDLE, report)
            if written != parsed["bundle"]["size"]:
                raise UpdateError("checksum", "downloaded update size does not match the manifest")
            if digest != expected_sha:
                raise UpdateError("checksum", "downloaded update checksum does not match the manifest")
            os.chmod(partial, 0o600)
            os.replace(partial, archive)
        except UpdateError as exc:
            try:
                os.unlink(partial)
            except OSError:
                pass
            self._set_job(state="failed", error=exc.message, message="download failed",
                          finished_at=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
            raise
        except Exception:
            try:
                os.unlink(partial)
            except OSError:
                pass
            self._set_job(state="failed", error="download interrupted", message="download failed",
                          finished_at=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
            raise UpdateError("download_failed", "the download was interrupted") from None
        state["download_path"] = archive
        state["downloaded_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        self._save_state(state)
        self._set_job(state="downloaded", version=parsed["version"], progress=100,
                      downloaded=parsed["bundle"]["size"], total=parsed["bundle"]["size"],
                      message="ready to install", error="", restart_required=False,
                      finished_at=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
        return self.status()

    def start_download(self, **kwargs: Any) -> dict[str, Any]:
        with self._lock:
            if self._job.get("state") in ACTIVE_STATES:
                raise UpdateError("busy", "another update is already running")
            # Publish the job before returning. The launcher polls only while
            # the job is active, so leaving it idle here would hide progress
            # until the thread happened to finish.
            self._set_job(state="downloading", progress=0, downloaded=0,
                          message="starting download", error="", restart_required=False)
        try:
            thread = threading.Thread(target=self._download_worker, kwargs=kwargs,
                                      name="pivista-update-download", daemon=True)
            thread.start()
        except Exception:
            self._set_job(state="failed", error="the download could not be started",
                          message="download failed")
            raise UpdateError("download_failed", "the download could not be started") from None
        return {"started": True}

    def _download_worker(self, **kwargs: Any) -> None:
        try:
            self.download(claimed=True, **kwargs)
        except UpdateError as exc:
            self._set_job(state="failed", error=exc.message, message="download failed")
        except Exception:
            self._set_job(state="failed", error="download failed unexpectedly", message="download failed")

    # -- install -----------------------------------------------------------
    def install(self, *, claimed: bool = False) -> dict[str, Any]:
        with self._lock:
            if not claimed and self._job.get("state") in ACTIVE_STATES:
                raise UpdateError("busy", "another update is already running")
        state = self._cached()
        parsed = self._verify_cached(state)
        archive = state.get("download_path")
        if not isinstance(archive, str) or not os.path.isfile(archive):
            raise UpdateError("not_downloaded", "download the update before installing it")
        if _sha256_file(archive) != parsed["bundle"]["sha256"] \
                or os.path.getsize(archive) != parsed["bundle"]["size"]:
            raise UpdateError("checksum", "the downloaded update no longer matches its checksum")
        installed = parse_version(self.installed_version())
        if parse_version(parsed["version"]) <= installed:
            raise UpdateError("no_update", "this PiVista version is already installed")
        if installed < parse_version(parsed["min_version"]):
            raise UpdateError("incompatible", f"this update requires PiVista {parsed['min_version']}")
        if parse_version(self.system_version()) < parse_version(parsed["min_system"]):
            raise UpdateError("incompatible", f"this update requires system image {parsed['min_system']}")

        self._set_job(state="installing", version=parsed["version"], progress=0,
                      message="verifying update package", error="", restart_required=False)
        staging = os.path.join(self.staging_dir, parsed["version"])
        shutil.rmtree(staging, ignore_errors=True)
        backup = ""
        try:
            os.makedirs(staging, mode=0o700, exist_ok=True)
            self._extract_bundle(archive, staging, parsed["version"])
            self._set_job(progress=35, message="backing up current launcher")
            backup = self._backup_current(parsed["version"])
            rollback_version = self._state_version(backup)
            # Persist the backup before touching live files. If power is lost
            # during the swap, the next daemon start still knows which copy can
            # be restored manually or from Settings.
            state.update({
                "rollback_path": backup,
                "rollback_version": rollback_version,
                "installed_at": "",
            })
            self._save_state(state)
            self._set_job(progress=70, message="installing launcher")
            self._install_payload(staging)
            new_version = self.installed_version()
            if new_version != parsed["version"]:
                raise UpdateError("install_failed", "the installed version did not match the update")
            state["installed_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            self._save_state(state)
            self._set_job(state="installed", progress=100, message="installed; restart required",
                          restart_required=True, finished_at=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
            shutil.rmtree(staging, ignore_errors=True)
            # Only the immediately previous launcher is a useful rollback.
            # Keeping every historical copy would fill /var on small cards.
            self._prune_rollbacks(keep=backup)
            return self.status()
        except Exception as exc:
            if backup:
                try:
                    self._restore_backup(backup)
                except Exception:
                    self._set_job(state="failed", error="installation failed and rollback failed",
                                  message="rollback failed")
                    raise UpdateError("rollback_failed",
                                      "the update failed and the previous launcher could not be restored") from exc
                # The live files are back to the old version; do not leave a
                # stale rollback entry pointing at a backup that is no longer
                # needed.
                state["rollback_path"] = ""
                state["rollback_version"] = ""
                self._save_state(state)
            shutil.rmtree(staging, ignore_errors=True)
            message = exc.message if isinstance(exc, UpdateError) else "the update could not be installed"
            self._set_job(state="failed", error=message, message="installation failed",
                          finished_at=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
            if isinstance(exc, UpdateError):
                raise
            raise UpdateError("install_failed", message) from None

    def start_install(self) -> dict[str, Any]:
        with self._lock:
            if self._job.get("state") in ACTIVE_STATES:
                raise UpdateError("busy", "another update is already running")
            self._set_job(state="installing", progress=0,
                          message="verifying update package", error="", restart_required=False)
        try:
            thread = threading.Thread(target=self._install_worker, name="pivista-update-install", daemon=True)
            thread.start()
        except Exception:
            self._set_job(state="failed", error="the installation could not be started",
                          message="installation failed")
            raise UpdateError("install_failed", "the installation could not be started") from None
        return {"started": True}

    def _install_worker(self) -> None:
        try:
            self.install(claimed=True)
        except UpdateError as exc:
            self._set_job(state="failed", error=exc.message, message="installation failed")
        except Exception:
            self._set_job(state="failed", error="installation failed unexpectedly",
                          message="installation failed")

    def _prune_rollbacks(self, keep: str = "") -> None:
        keep_abs = os.path.abspath(keep) if keep else ""
        try:
            entries = os.listdir(self.rollback_root)
        except OSError:
            return
        for name in entries:
            path = os.path.join(self.rollback_root, name)
            if keep_abs and os.path.abspath(path) == keep_abs:
                continue
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path, ignore_errors=True)

    def _state_version(self, backup: str) -> str:
        try:
            with open(os.path.join(backup, "backup.json"), encoding="utf-8") as handle:
                data = json.load(handle)
            return str(data.get("version", ""))
        except (OSError, json.JSONDecodeError):
            return ""

    def _backup_current(self, new_version: str) -> str:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        backup = os.path.join(self.rollback_root,
                              f"{self.installed_version()}-{stamp}-{os.getpid()}")
        if os.path.exists(backup):
            raise UpdateError("install_failed", "a rollback directory already exists for this attempt")
        os.makedirs(backup, mode=0o700)
        if (not os.path.isfile(self.launcher_path) or os.path.islink(self.launcher_path)
                or not os.path.isdir(self.qml_path) or os.path.islink(self.qml_path)):
            raise UpdateError("install_failed", "the current launcher installation is incomplete")
        shutil.copy2(self.launcher_path, os.path.join(backup, "launcher"))
        shutil.copytree(self.qml_path, os.path.join(backup, "qml"))
        shutil.copy2(self.catalog_path, os.path.join(backup, "catalog.json"))
        shutil.copy2(self.version_path, os.path.join(backup, "version.json"))
        self._write_json(os.path.join(backup, "backup.json"), {
            "version": self.installed_version(),
            "new_version": new_version,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        })
        os.chmod(backup, 0o700)
        return backup

    def _install_payload(self, staging: str) -> None:
        binary = os.path.join(staging, "bin", "pivista-launcher")
        qml = os.path.join(staging, "share", "pivista", "qml")
        catalog = os.path.join(staging, "share", "pivista", "webapps", "catalog.json")
        version = os.path.join(staging, "share", "pivista", "version.json")
        self._replace_file(binary, self.launcher_path, 0o755)
        if os.path.islink(self.qml_path):
            raise UpdateError("install_failed", "the QML directory is a symbolic link")
        qml_old = self.qml_path + ".old"
        if os.path.lexists(qml_old):
            if os.path.isdir(qml_old) and not os.path.islink(qml_old):
                shutil.rmtree(qml_old)
            else:
                os.unlink(qml_old)
        os.rename(self.qml_path, qml_old)
        try:
            os.rename(qml, self.qml_path)
        except OSError:
            os.rename(qml_old, self.qml_path)
            raise
        shutil.rmtree(qml_old, ignore_errors=True)
        self._replace_file(catalog, self.catalog_path, 0o644)
        self._replace_file(version, self.version_path, 0o644)

    def _replace_file(self, source: str, destination: str, mode: int) -> None:
        if os.path.islink(destination) or os.path.isdir(destination):
            raise UpdateError("install_failed", f"{destination} is not a regular file")
        parent = os.path.dirname(destination)
        os.makedirs(parent, mode=0o755, exist_ok=True)
        temporary = destination + ".new"
        try:
            shutil.copyfile(source, temporary)
            os.chmod(temporary, mode)
            try:
                os.chown(temporary, 0, 0)
            except PermissionError:
                if os.geteuid() == 0:
                    raise
            with open(temporary, "rb") as handle:
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
        finally:
            try:
                os.unlink(temporary)
            except OSError:
                pass

    def _restore_backup(self, backup: str) -> None:
        launcher = os.path.join(backup, "launcher")
        qml = os.path.join(backup, "qml")
        catalog = os.path.join(backup, "catalog.json")
        version = os.path.join(backup, "version.json")
        if not all(os.path.exists(path) for path in (launcher, qml, catalog, version)):
            raise UpdateError("rollback_failed", "the rollback backup is incomplete")
        self._replace_file(launcher, self.launcher_path, 0o755)
        failed = self.qml_path + ".failed"
        if os.path.lexists(failed):
            shutil.rmtree(failed, ignore_errors=True)
        if os.path.lexists(self.qml_path):
            os.rename(self.qml_path, failed)
        try:
            shutil.copytree(qml, self.qml_path)
        finally:
            shutil.rmtree(failed, ignore_errors=True)
        self._replace_file(catalog, self.catalog_path, 0o644)
        self._replace_file(version, self.version_path, 0o644)

    # -- archive validation ------------------------------------------------
    def _extract_bundle(self, archive: str, destination: str, expected_version: str) -> None:
        try:
            with tarfile.open(archive, "r:xz") as bundle:
                members = bundle.getmembers()
                if len(members) > MAX_MEMBERS:
                    raise UpdateError("bad_archive", "the update archive has too many files")
                total = 0
                seen: set[str] = set()
                prepared: list[tuple[tarfile.TarInfo, str]] = []
                for member in members:
                    name = _member_name(member)
                    if name in seen:
                        raise UpdateError("bad_archive", "the update archive contains duplicate paths")
                    seen.add(name)
                    if member.isdir():
                        if name not in ALLOWED_DIRS and not name.startswith("share/pivista/qml/"):
                            raise UpdateError("bad_archive", "the update archive contains an unexpected directory")
                    elif member.isfile():
                        if name not in REQUIRED_ENTRIES and not name.startswith("share/pivista/qml/"):
                            raise UpdateError("bad_archive", "the update archive contains an unexpected file")
                        if member.size < 0 or member.size > MAX_BUNDLE:
                            raise UpdateError("bad_archive", "the update archive contains an oversized file")
                        total += member.size
                        if total > MAX_BUNDLE:
                            raise UpdateError("bad_archive", "the update archive is too large")
                    else:
                        raise UpdateError("bad_archive", "the update archive contains a link or special file")
                    prepared.append((member, name))
                missing = REQUIRED_ENTRIES - seen
                if missing:
                    raise UpdateError("bad_archive", "the update archive is missing required files")
                os.makedirs(destination, mode=0o700, exist_ok=True)
                for member, name in prepared:
                    target = os.path.join(destination, *name.split("/"))
                    if member.isdir():
                        os.makedirs(target, mode=0o755, exist_ok=True)
                        continue
                    os.makedirs(os.path.dirname(target), mode=0o755, exist_ok=True)
                    source = bundle.extractfile(member)
                    if source is None:
                        raise UpdateError("bad_archive", "the update archive entry could not be read")
                    with source, open(target, "wb") as handle:
                        shutil.copyfileobj(source, handle, 1024 * 1024)
                    os.chmod(target, 0o755 if name == "bin/pivista-launcher" else 0o644)
        except UpdateError:
            raise
        except (tarfile.TarError, OSError, EOFError, lzma_error()):
            raise UpdateError("bad_archive", "the update archive is corrupted") from None
        self._validate_payload(destination, expected_version)

    def _validate_payload(self, root: str, expected_version: str) -> None:
        binary = os.path.join(root, "bin", "pivista-launcher")
        version_path = os.path.join(root, "share", "pivista", "version.json")
        qml = os.path.join(root, "share", "pivista", "qml")
        catalog = os.path.join(root, "share", "pivista", "webapps", "catalog.json")
        try:
            with open(binary, "rb") as handle:
                head = handle.read(20)
        except OSError:
            raise UpdateError("bad_archive", "the update has no launcher binary") from None
        if len(head) < 20 or head[:4] != b"\x7fELF" or head[4] != 2:
            raise UpdateError("wrong_architecture", "the update launcher is not a 64-bit ELF binary")
        machine = int.from_bytes(head[18:20], "little")
        if machine != 183:
            raise UpdateError("wrong_architecture", "the update launcher is not an ARM64 binary")
        try:
            with open(version_path, encoding="utf-8") as handle:
                info = json.load(handle)
        except (OSError, json.JSONDecodeError):
            raise UpdateError("bad_archive", "the update version file is invalid") from None
        if info.get("product") != "pivista-tv" or info.get("version") != expected_version:
            raise UpdateError("incompatible", "the update version file does not match the manifest")
        if not os.path.isfile(os.path.join(qml, "Main.qml")):
            raise UpdateError("bad_archive", "the update QML is incomplete")
        try:
            with open(catalog, encoding="utf-8") as handle:
                if not isinstance(json.load(handle), dict):
                    raise ValueError
        except (OSError, json.JSONDecodeError, ValueError):
            raise UpdateError("bad_archive", "the update catalog is invalid") from None

    # -- rollback / postpone ----------------------------------------------
    def rollback(self) -> dict[str, Any]:
        with self._lock:
            if self._job.get("state") in ACTIVE_STATES:
                raise UpdateError("busy", "another update is already running")
        state = self._load_state()
        backup = state.get("rollback_path")
        if not isinstance(backup, str) or not os.path.isdir(backup):
            raise UpdateError("no_rollback", "there is no previous launcher to restore")
        self._restore_backup(backup)
        restored = parse_version(self.installed_version())
        state["rollback_path"] = ""
        state["rollback_version"] = ""
        state["installed_at"] = ""
        state["latest"] = version_text(restored)
        state["available"] = False
        self._save_state(state)
        self._set_job(state="idle", progress=0, message="previous launcher restored",
                      restart_required=True, error="")
        shutil.rmtree(backup, ignore_errors=True)
        self._prune_rollbacks()
        return self.status()

    def postpone(self, version: str) -> dict[str, Any]:
        state = self._load_state()
        if not state:
            raise UpdateError("not_checked", "check for updates first")
        if version != state.get("latest"):
            raise UpdateError("invalid_version", "that version is not the available update")
        state["postponed_version"] = version
        state["postponed_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        self._save_state(state)
        return self.status()


def _member_name(member: tarfile.TarInfo) -> str:
    name = member.name.replace("\\", "/")
    if not name or name.startswith("/"):
        raise UpdateError("bad_archive", "the update archive contains an absolute path")
    parts = [part for part in name.split("/") if part not in ("", ".")]
    if any(part == ".." for part in parts):
        raise UpdateError("bad_archive", "the update archive contains a traversal path")
    normalized = posixpath.normpath("/".join(parts))
    if normalized in (".", "") or normalized.startswith("../"):
        raise UpdateError("bad_archive", "the update archive contains an invalid path")
    return normalized


def _sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def lzma_error() -> type[Exception]:
    try:
        import lzma
        return lzma.LZMAError
    except ImportError:  # pragma: no cover
        return OSError
