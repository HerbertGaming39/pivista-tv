#!/usr/bin/env python3
"""PiVista TV control service.

A small privileged daemon that exposes exactly the system operations the
television UI needs, over a Unix socket restricted to the `pivista` session
group. The launcher runs unprivileged; everything that requires root (network
changes, audio routing, updates, power) arrives here as a validated action.

Design rules:
  * no shell execution, ever — every command is an argv list;
  * user-supplied values are validated against the live system, not trusted;
  * request parameters are never logged (they may contain Wi-Fi secrets);
  * unknown actions are rejected;
  * no network listener.
"""

from __future__ import annotations

import argparse
import errno
import glob
import grp
import json
import logging
import os
import platform
import pwd
import re
import secrets
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
import traceback
from dataclasses import dataclass, field
from typing import Any, Callable

from pivista_update import UpdateError, UpdateManager

VERSION = "0.3.2"
MAX_MESSAGE = 64 * 1024
DEFAULT_SOCKET = "/run/pivista/control.sock"
DEFAULT_CONFIG = "/etc/pivista"
DEFAULT_STATE = "/var/lib/pivista"
DEFAULT_LOG_DIR = "/var/log/pivista"
SESSION_UID = 1000
SESSION_GROUP = "pivista"

log = logging.getLogger("pivistad")


class ActionError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


class Runner:
    """Run a command without a shell; injectable for tests."""

    def __init__(self, timeout: int = 20) -> None:
        self.timeout = timeout

    def run(self, argv: list[str], timeout: int | None = None,
            env: dict[str, str] | None = None, check: bool = False,
            input_text: str | None = None) -> subprocess.CompletedProcess:
        if not argv or not all(isinstance(a, str) for a in argv):
            raise ActionError("invalid_command", "command must be a list of strings")
        child_env = None
        if env is not None:
            child_env = dict(os.environ)
            child_env.update(env)
        try:
            completed = subprocess.run(
                argv,
                capture_output=True,
                text=True,
                timeout=timeout or self.timeout,
                env=child_env,
                input=input_text,
                check=False,
            )
        except FileNotFoundError:
            raise ActionError("not_installed", f"{argv[0]} is not installed") from None
        except subprocess.TimeoutExpired:
            raise ActionError("timeout", f"{argv[0]} timed out") from None
        if check and completed.returncode != 0:
            raise ActionError(
                "command_failed",
                (completed.stderr or completed.stdout or f"{argv[0]} failed").strip()[:400],
            )
        return completed


def read_text(path: str, default: str = "") -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().strip()
    except OSError:
        return default


def parse_input_devices(text: str) -> list[dict[str, Any]]:
    """Parse /proc/bus/input/devices into the keyboards and remotes the TV sees.

    A kernel input device is useful to the launcher only when it emits key
    events.  This deliberately reports every such device, including ones the
    compositor may not have focused, so Settings can show a keyboard that was
    hot-plugged after the wizard appeared.
    """
    devices: list[dict[str, Any]] = []
    for block in re.split(r"\n\s*\n", text.strip()):
        if not block.strip():
            continue
        name = ""
        handlers: list[str] = []
        sysfs = ""
        key_bits = False
        for line in block.splitlines():
            if line.startswith("N: Name="):
                match = re.search(r'Name="([^"]*)"', line)
                name = match.group(1) if match else ""
            elif line.startswith("H: Handlers="):
                handlers = line.split("=", 1)[1].split()
            elif line.startswith("S: Sysfs="):
                sysfs = line.split("=", 1)[1].strip()
            elif line.startswith("B: KEY="):
                bits = line.split("=", 1)[1].split()
                key_bits = any(part not in {"0", ""} for part in bits)
        if not handlers:
            continue
        event = next((h for h in handlers if h.startswith("event")), "")
        if not event:
            continue
        lowered = name.lower()
        is_keyboard = "kbd" in handlers or any(
            word in lowered for word in ("keyboard", "remote", "receiver", "consumer control")
        )
        if not is_keyboard and not key_bits:
            continue
        if is_keyboard and "remote" in lowered:
            kind = "remote"
        elif is_keyboard:
            kind = "keyboard"
        elif any(word in lowered for word in ("remote", "receiver", "consumer control")):
            kind = "remote"
        else:
            kind = "input"
        devices.append({
            "name": name or "Unnamed input device",
            "kind": kind,
            "event": "/dev/input/" + event,
            "handlers": handlers,
            "sysfs": sysfs,
        })
    kind_order = {"keyboard": 0, "remote": 1, "input": 2}
    devices.sort(key=lambda device: (kind_order.get(device["kind"], 3), device["name"]))
    return devices


def parse_escaped_colon(line: str) -> list[str]:
    """Split nmcli terse output on unescaped colons."""
    parts: list[str] = []
    current: list[str] = []
    escaped = False
    for ch in line:
        if escaped:
            current.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == ":":
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    parts.append("".join(current))
    return parts


@dataclass
class ServiceContext:
    runner: Runner = field(default_factory=Runner)
    config_dir: str = DEFAULT_CONFIG
    state_dir: str = DEFAULT_STATE
    log_dir: str = DEFAULT_LOG_DIR
    remote_dir: str = "/etc/pivista/remote"
    sshd_path: str = "/usr/sbin/sshd"
    session_uid: int = SESSION_UID
    session_group: str = SESSION_GROUP
    update_public_key: str = "/etc/pivista/update-pubkey.pem"
    clock: Callable[[], float] = time.time


class ControlService:
    """Implements the action allowlist."""

    def __init__(self, ctx: ServiceContext | None = None) -> None:
        self.ctx = ctx or ServiceContext()
        self._wifi_cache: tuple[float, list[dict]] | None = None
        self._last_power: float = 0.0
        self._update_lock = threading.Lock()
        self._update_job: dict[str, Any] = {"state": "idle"}
        self._app_updates = UpdateManager(
            root="/",
            state_dir=self.ctx.state_dir,
            config_dir=self.ctx.config_dir,
            public_key=self.ctx.update_public_key,
            runner=self.ctx.runner,
            clock=self.ctx.clock,
        )
        self._handlers: dict[str, Callable[[dict], dict]] = {
            "ping": self.ping,
            "system.info": self.system_info,
            "system.status": self.system_status,
            "system.set_timezone": self.set_timezone,
            "system.set_locale": self.set_locale,
            "system.set_hostname": self.set_hostname,
            "input.status": self.input_status,
            "bluetooth.status": self.bluetooth_status,
            "bluetooth.scan": self.bluetooth_scan,
            "bluetooth.pair": self.bluetooth_pair,
            "bluetooth.disconnect": self.bluetooth_disconnect,
            "bluetooth.forget": self.bluetooth_forget,
            "power.reboot": self.reboot,
            "power.shutdown": self.shutdown,
            "network.status": self.network_status,
            "network.scan": self.network_scan,
            "network.connect": self.network_connect,
            "network.disconnect": self.network_disconnect,
            "network.connectivity": self.network_connectivity,
            "audio.status": self.audio_status,
            "audio.set_volume": self.audio_set_volume,
            "audio.set_mute": self.audio_set_mute,
            "audio.set_output": self.audio_set_output,
            "audio.test": self.audio_test,
            "display.status": self.display_status,
            "display.set_mode": self.display_set_mode,
            "update.status": self.update_status,
            "update.check": self.update_check,
            "update.apply": self.update_apply,
            "update.history": self.update_history,
            "app.update.status": self.app_update_status,
            "app.update.check": self.app_update_check,
            "app.update.download": self.app_update_download,
            "app.update.install": self.app_update_install,
            "app.update.postpone": self.app_update_postpone,
            "app.update.rollback": self.app_update_rollback,
            "app.update.restart": self.app_update_restart,
            "android.status": self.android_status,
            "remote.status": self.remote_status,
            "remote.ssh.enable": self.remote_ssh_enable,
            "remote.ssh.disable": self.remote_ssh_disable,
            "remote.ssh.rotate": self.remote_ssh_rotate,
            "remote.vnc.enable": self.remote_vnc_enable,
            "remote.vnc.disable": self.remote_vnc_disable,
            "diagnostics.export": self.diagnostics_export,
            "logs.tail": self.logs_tail,
            "build.provenance": self.build_provenance,
        }

    # -- protocol ---------------------------------------------------------
    def dispatch(self, action: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        if action not in self._handlers:
            raise ActionError("unknown_action", f"unknown action: {action}")
        if not isinstance(params, dict):
            raise ActionError("invalid_params", "params must be an object")
        started = time.monotonic()
        try:
            result = self._handlers[action](params)
            log.info("action=%s ok (%.0f ms)", action, (time.monotonic() - started) * 1000)
            return result
        except ActionError:
            log.warning("action=%s rejected", action)
            raise
        except Exception:  # pragma: no cover - defensive boundary
            log.error("action=%s failed\n%s", action, traceback.format_exc())
            raise ActionError("internal_error", "the control service failed to complete the action") from None

    # -- helpers ----------------------------------------------------------
    def _sysenv(self) -> dict[str, str]:
        return {"XDG_RUNTIME_DIR": f"/run/user/{self.ctx.session_uid}"}

    def _wayland_env(self) -> dict[str, str] | None:
        runtime = f"/run/user/{self.ctx.session_uid}"
        sockets = sorted(glob.glob(f"{runtime}/wayland-*"))
        sockets = [s for s in sockets if not s.endswith(".lock")]
        if not sockets:
            return None
        return {"XDG_RUNTIME_DIR": runtime, "WAYLAND_DISPLAY": os.path.basename(sockets[0])}

    def _config_value(self, key: str, default: str = "") -> str:
        path = os.path.join(self.ctx.config_dir, "product.env")
        for line in read_text(path).splitlines():
            if line.startswith(key + "="):
                return line.split("=", 1)[1].strip().strip('"')
        return default

    def _build_info(self) -> dict:
        try:
            with open(os.path.join(self.ctx.config_dir, "build-info.json"), encoding="utf-8") as fh:
                return json.load(fh)
        except (OSError, json.JSONDecodeError):
            return {}

    # -- basic ------------------------------------------------------------
    def ping(self, _params: dict) -> dict:
        return {"service": "pivistad", "version": VERSION, "pid": os.getpid()}

    def system_info(self, _params: dict) -> dict:
        info = self._build_info()
        release = {}
        for line in read_text("/etc/os-release").splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                release[k] = v.strip('"')
        mem_total, mem_avail = self._memory()
        try:
            app_version = self._app_updates.installed_version()
        except UpdateError:
            app_version = info.get("version", "unknown")
        return {
            "product": info.get("product", self._config_value("PIVISTA_PRODUCT_NAME", "PiVista TV")),
            "version": info.get("version", self._config_value("PIVISTA_VERSION", "unknown")),
            "app_version": app_version,
            "codename": info.get("codename", ""),
            "build_id": info.get("build_id", ""),
            "model": read_text("/proc/device-tree/model", "") or info.get("model", ""),
            "kernel": platform.release(),
            "architecture": platform.machine(),
            "os": release.get("PRETTY_NAME", ""),
            "debian": release.get("VERSION_CODENAME", ""),
            "hostname": socket.gethostname(),
            "timezone": read_text("/etc/timezone"),
            "locale": self._locale(),
            "serial": self._serial(),
            "memory_total_kb": mem_total,
            "memory_available_kb": mem_avail,
            "cpu_count": os.cpu_count(),
        }

    def _locale(self) -> str:
        for line in read_text("/etc/default/locale").splitlines():
            if line.startswith("LANG="):
                return line.split("=", 1)[1].strip().strip('"')
        return os.environ.get("LANG", "") or "unknown"

    def _serial(self) -> str:
        serial = read_text("/proc/device-tree/serial-number", "")
        return serial or "unknown"

    BT_ADDRESS = re.compile(r"^[0-9A-F]{2}(?::[0-9A-F]{2}){5}$")

    @staticmethod
    def _parse_bluetooth_devices(text: str) -> list[dict]:
        devices: list[dict] = []
        for line in text.splitlines():
            line = re.sub(r"\x1b\[[0-9;]*m", "", line).strip()
            match = re.match(r"(?:\[NEW\]\s*)?Device ([0-9A-Fa-f:]{17}) (.+)$", line)
            if not match:
                continue
            name = match.group(2).strip()
            devices.append({
                "address": match.group(1).upper(),
                "name": name or "Unnamed device",
            })
        return devices

    def _bluetooth_paired(self) -> list[dict]:
        completed = self.ctx.runner.run(
            ["bluetoothctl", "devices", "Paired"], timeout=10)
        if completed.returncode != 0:
            # Older BlueZ releases do not implement the Paired argument. Fall
            # back to the full list rather than failing the whole page.
            completed = self.ctx.runner.run(["bluetoothctl", "devices"], timeout=10)
        return self._parse_bluetooth_devices(completed.stdout)

    def bluetooth_status(self, _params: dict) -> dict:
        try:
            show = self.ctx.runner.run(["bluetoothctl", "show"], timeout=10)
        except ActionError as exc:
            return {
                "available": False, "powered": False, "discovering": False,
                "adapter": "", "paired": [], "error": exc.message,
            }
        text = show.stdout if show.returncode == 0 else ""
        powered = re.search(r"Powered:\s+yes", text) is not None
        discovering = re.search(r"Discovering:\s+yes", text) is not None
        adapter = ""
        match = re.search(r"Controller ([0-9A-Fa-f:]{17})", text)
        if match:
            adapter = match.group(1).upper()
        try:
            paired = self._bluetooth_paired() if show.returncode == 0 else []
        except ActionError:
            paired = []
        return {
            "available": show.returncode == 0,
            "powered": powered,
            "discovering": discovering,
            "adapter": adapter,
            "paired": paired,
            "error": "" if show.returncode == 0
                     else (show.stderr or "The Bluetooth service is not available.").strip()[:300],
        }

    def bluetooth_scan(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "scanning for Bluetooth devices requires confirm=true")
        completed = self.ctx.runner.run(
            ["bluetoothctl", "--timeout", "8", "scan", "on"], timeout=20)
        if completed.returncode != 0:
            raise ActionError(
                "bluetooth_scan_failed",
                (completed.stderr or completed.stdout).strip()[:300]
                or "Bluetooth scanning failed.",
            )
        paired = self._bluetooth_paired()
        paired_addresses = {device["address"] for device in paired}
        discovered = []
        for device in self._parse_bluetooth_devices(completed.stdout):
            device["paired"] = device["address"] in paired_addresses
            discovered.append(device)
        # Some BlueZ versions print discoveries to stderr. Merge both streams.
        for device in self._parse_bluetooth_devices(completed.stderr):
            if not any(item["address"] == device["address"] for item in discovered):
                device["paired"] = device["address"] in paired_addresses
                discovered.append(device)
        return {"devices": discovered, "paired": paired, "scanned": True}

    def bluetooth_pair(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "pairing a Bluetooth device requires confirm=true")
        address = params.get("address")
        if not isinstance(address, str) or not self.BT_ADDRESS.fullmatch(address.upper()):
            raise ActionError("invalid_address", "invalid Bluetooth address")
        address = address.upper()
        paired = self.ctx.runner.run(
            ["bluetoothctl", "--timeout", "30", "pair", address], timeout=45)
        if paired.returncode != 0:
            raise ActionError(
                "bluetooth_pair_failed",
                (paired.stderr or paired.stdout).strip()[:300]
                or "Pairing failed. Some remotes require a PIN and are not supported yet.",
            )
        # Trust is what lets a remote reconnect after it sleeps. Connect is
        # best-effort: some remotes only connect when a button is pressed.
        self.ctx.runner.run(["bluetoothctl", "trust", address], timeout=15)
        self.ctx.runner.run(["bluetoothctl", "connect", address], timeout=20)
        return self.bluetooth_status({})

    def bluetooth_disconnect(self, params: dict) -> dict:
        address = params.get("address")
        if not isinstance(address, str) or not self.BT_ADDRESS.fullmatch(address.upper()):
            raise ActionError("invalid_address", "invalid Bluetooth address")
        self.ctx.runner.run(["bluetoothctl", "disconnect", address.upper()], timeout=20)
        return self.bluetooth_status({})

    def bluetooth_forget(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "forgetting a device requires confirm=true")
        address = params.get("address")
        if not isinstance(address, str) or not self.BT_ADDRESS.fullmatch(address.upper()):
            raise ActionError("invalid_address", "invalid Bluetooth address")
        self.ctx.runner.run(["bluetoothctl", "remove", address.upper()], timeout=20)
        return self.bluetooth_status({})

    def input_status(self, _params: dict) -> dict:
        """What keyboards/remotes the kernel currently has, for Settings > Input."""
        devices = parse_input_devices(read_text("/proc/bus/input/devices"))
        keyboards = [device for device in devices if device["kind"] == "keyboard"]
        remotes = [device for device in devices if device["kind"] == "remote"]
        cec_adapters = sorted(glob.glob("/dev/cec[0-9]*"))
        return {
            "devices": devices,
            "keyboard_count": len(keyboards),
            "remote_count": len(remotes),
            "input_map": "/etc/pivista/input.map",
            "input_map_present": os.path.exists("/etc/pivista/input.map"),
            "cec": {
                "adapter_detected": bool(cec_adapters),
                "adapters": cec_adapters,
                "tool_present": shutil.which("cec-client") is not None,
                # CEC is not enabled by this build. Do not present it as a
                # working remote path until key translation is implemented and
                # tested on hardware.
                "enabled": False,
            },
        }

    def _memory(self) -> tuple[int, int]:
        values: dict[str, int] = {}
        for line in read_text("/proc/meminfo").splitlines():
            match = re.match(r"(\w+):\s+(\d+)", line)
            if match:
                values[match.group(1)] = int(match.group(2))
        return values.get("MemTotal", 0), values.get("MemAvailable", 0)

    def _temperature(self) -> float | None:
        raw = read_text("/sys/class/thermal/thermal_zone0/temp")
        if raw.isdigit():
            return round(int(raw) / 1000.0, 1)
        return None

    def _storage(self) -> dict:
        try:
            stats = os.statvfs("/")
            total = stats.f_blocks * stats.f_frsize
            free = stats.f_bavail * stats.f_frsize
            used = total - stats.f_bfree * stats.f_frsize
            percent = round(used / total * 100, 1) if total else 0.0
            return {"total_bytes": total, "free_bytes": free, "used_percent": percent}
        except OSError:
            return {"total_bytes": 0, "free_bytes": 0, "used_percent": 0.0}

    def _uptime(self) -> int:
        try:
            return int(float(read_text("/proc/uptime").split()[0]))
        except (ValueError, IndexError):
            return 0

    def _throttled(self) -> str | None:
        if not shutil.which("vcgencmd"):
            return None
        completed = self.ctx.runner.run(["vcgencmd", "get_throttled"], timeout=5)
        return completed.stdout.strip() or None

    def system_status(self, _params: dict) -> dict:
        mem_total, mem_avail = self._memory()
        return {
            "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "uptime_s": self._uptime(),
            "memory": {
                "total_kb": mem_total,
                "available_kb": mem_avail,
                "used_percent": round((1 - mem_avail / mem_total) * 100, 1) if mem_total else 0.0,
            },
            "storage": self._storage(),
            "temperature_c": self._temperature(),
            "throttled": self._throttled(),
            "network": self._network_summary(),
            "audio": self._audio_summary(),
            "display": self._display_summary(),
            "update": self.update_status({}),
            "app_update": self.app_update_status({}),
        }

    # -- network ----------------------------------------------------------
    def _nmcli(self, *args: str, timeout: int = 15) -> subprocess.CompletedProcess:
        return self.ctx.runner.run(["nmcli", *args], timeout=timeout)

    def _network_summary(self) -> dict:
        completed = self._nmcli("-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status", timeout=8)
        devices = []
        if completed.returncode == 0:
            for line in completed.stdout.splitlines():
                fields = parse_escaped_colon(line)
                if len(fields) < 4:
                    continue
                device, dtype, state, connection = fields[:4]
                if device == "lo":
                    continue
                entry = {
                    "device": device,
                    "type": dtype,
                    "state": state,
                    "connection": connection if connection and connection != "--" else "",
                    "ip": "",
                }
                if state == "connected":
                    ip = self._nmcli("-g", "IP4.ADDRESS", "device", "show", device, timeout=5)
                    entry["ip"] = ip.stdout.splitlines()[0].split("/")[0] if ip.returncode == 0 and ip.stdout.strip() else ""
                devices.append(entry)
        wifi = next((d for d in devices if d["type"] == "wifi" and d["state"] == "connected"), None)
        eth = next((d for d in devices if d["type"] == "ethernet" and d["state"] == "connected"), None)
        active = eth or wifi
        return {
            "available": completed.returncode == 0,
            "devices": devices,
            "connected": bool(active),
            "connection": active["connection"] if active else "",
            "interface": active["device"] if active else "",
            "ip": active["ip"] if active else "",
            "wifi_connected": bool(wifi),
            "ethernet_connected": bool(eth),
        }

    def network_status(self, _params: dict) -> dict:
        summary = self._network_summary()
        summary["connectivity"] = self._connectivity()
        return summary

    def _connectivity(self) -> str:
        completed = self._nmcli("networking", "connectivity", "check", timeout=8)
        value = completed.stdout.strip()
        return value if value in {"full", "limited", "none", "portal", "unknown"} else "unknown"

    def network_connectivity(self, _params: dict) -> dict:
        state = self._connectivity()
        dns_ok = False
        detail = ""
        try:
            socket.setdefaulttimeout(4)
            socket.getaddrinfo("connectivity-check.ubuntu.com", 443)
            dns_ok = True
        except OSError as exc:
            detail = str(exc)
        return {"nm": state, "dns": dns_ok, "online": state == "full" and dns_ok, "detail": detail}

    def network_scan(self, params: dict) -> dict:
        now = self.ctx.clock()
        force = bool(params.get("rescan", False))
        if not force and self._wifi_cache and now - self._wifi_cache[0] < 20:
            return {"networks": self._wifi_cache[1], "cached": True}
        completed = self._nmcli("-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list",
                                "--rescan", "yes" if force else "auto", timeout=40)
        if completed.returncode != 0:
            raise ActionError("wifi_unavailable", completed.stderr.strip() or "Wi-Fi scan failed")
        networks: dict[str, dict] = {}
        for line in completed.stdout.splitlines():
            fields = parse_escaped_colon(line)
            if len(fields) < 3 or not fields[0]:
                continue
            ssid, signal, security = fields[0], fields[1], fields[2]
            try:
                strength = int(signal)
            except ValueError:
                strength = 0
            secure = security not in {"", "--"}
            if ssid not in networks or strength > networks[ssid]["signal"]:
                networks[ssid] = {"ssid": ssid, "signal": strength, "security": security, "secure": secure}
        result = sorted(networks.values(), key=lambda n: n["signal"], reverse=True)
        self._wifi_cache = (now, result)
        return {"networks": result, "cached": False}

    def network_connect(self, params: dict) -> dict:
        ssid = params.get("ssid")
        password = params.get("password", "")
        if not isinstance(ssid, str) or not 1 <= len(ssid) <= 32:
            raise ActionError("invalid_ssid", "SSID must be 1-32 characters")
        if not isinstance(password, str) or len(password) > 128:
            raise ActionError("invalid_password", "password is too long")
        ssid = ssid.replace("\x00", "")
        if ssid.startswith("-"):
            raise ActionError("invalid_ssid", "SSID may not start with '-'")
        self._wifi_cache = None
        argv = ["nmcli", "device", "wifi", "connect", ssid]
        if password:
            argv += ["password", password]
        completed = self.ctx.runner.run(argv, timeout=60)
        if completed.returncode != 0:
            message = (completed.stderr or completed.stdout).strip()
            raise ActionError("connect_failed", message[:300] or "could not connect")
        return {"connected": True, "ssid": ssid, "network": self._network_summary()}

    def network_disconnect(self, params: dict) -> dict:
        device = params.get("device")
        if not isinstance(device, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{1,32}", device):
            raise ActionError("invalid_device", "invalid network device")
        status = self._network_summary()
        if not any(d["device"] == device for d in status["devices"]):
            raise ActionError("unknown_device", "that network device is not present")
        completed = self._nmcli("device", "disconnect", device, timeout=30)
        if completed.returncode != 0:
            raise ActionError("disconnect_failed", completed.stderr.strip()[:300])
        return {"disconnected": True}

    # -- audio ------------------------------------------------------------
    def _sinks(self) -> list[dict]:
        completed = self.ctx.runner.run(["pactl", "-f", "json", "list", "sinks"], timeout=8)
        if completed.returncode != 0:
            return []
        try:
            raw = json.loads(completed.stdout or "[]")
        except json.JSONDecodeError:
            return []
        sinks = []
        default_name = self._default_sink()
        for item in raw:
            volumes = item.get("volume", {})
            first = next(iter(volumes.values()), {})
            try:
                percent = round(float(str(first.get("value_percent", "0%")).rstrip("%")))
            except (TypeError, ValueError):
                percent = 0
            sinks.append({
                "name": item.get("name", ""),
                "description": item.get("description", "") or item.get("name", ""),
                "index": item.get("index", 0),
                "default": item.get("name", "") == default_name,
                "mute": bool(item.get("mute", False)),
                "volume": percent,
                "hdmi": "hdmi" in (item.get("name", "") + item.get("description", "")).lower(),
            })
        return sinks

    def _default_sink(self) -> str:
        completed = self.ctx.runner.run(["pactl", "get-default-sink"], timeout=5)
        return completed.stdout.strip() if completed.returncode == 0 else ""

    def _audio_summary(self) -> dict:
        sinks = self._sinks()
        default = next((s for s in sinks if s["default"]), sinks[0] if sinks else None)
        return {
            "available": bool(sinks),
            "sinks": sinks,
            "default": default["name"] if default else "",
            "volume": default["volume"] if default else 0,
            "mute": default["mute"] if default else False,
            "hdmi": bool(default and default["hdmi"]),
        }

    def audio_status(self, _params: dict) -> dict:
        return self._audio_summary()

    def _require_default_sink(self) -> str:
        name = self._default_sink()
        if not name:
            raise ActionError("audio_unavailable", "no audio output is available")
        return name

    def audio_set_volume(self, params: dict) -> dict:
        try:
            volume = int(params.get("volume"))
        except (TypeError, ValueError):
            raise ActionError("invalid_volume", "volume must be an integer") from None
        if not 0 <= volume <= 100:
            raise ActionError("invalid_volume", "volume must be between 0 and 100")
        sink = self._require_default_sink()
        self.ctx.runner.run(["pactl", "set-sink-volume", sink, f"{volume}%"], timeout=8, check=True)
        return {"volume": volume}

    def audio_set_mute(self, params: dict) -> dict:
        mute = params.get("mute")
        if not isinstance(mute, bool):
            raise ActionError("invalid_mute", "mute must be true or false")
        sink = self._require_default_sink()
        self.ctx.runner.run(["pactl", "set-sink-mute", sink, "1" if mute else "0"], timeout=8, check=True)
        return {"mute": mute}

    def audio_set_output(self, params: dict) -> dict:
        name = params.get("sink")
        allowed = {s["name"] for s in self._sinks()}
        if not isinstance(name, str) or name not in allowed:
            raise ActionError("unknown_sink", "that audio output is not available")
        self.ctx.runner.run(["pactl", "set-default-sink", name], timeout=8, check=True)
        return {"default": name}

    def audio_test(self, _params: dict) -> dict:
        sink = self._require_default_sink()
        # A one-second 440 Hz tone on the default sink. speaker-test is blocking;
        # the timeout is a guard, not an error path users should normally see.
        completed = self.ctx.runner.run(
            ["speaker-test", "-D", "pulse", "-t", "sine", "-f", "440", "-l", "1", "-p", "1"],
            timeout=6,
        )
        return {"played": completed.returncode == 0, "sink": sink}

    # -- display ----------------------------------------------------------
    def _display_summary(self) -> dict:
        outputs = []
        for status_path in sorted(glob.glob("/sys/class/drm/card*-*/status")):
            name = os.path.basename(os.path.dirname(status_path))
            if "-" not in name:
                continue
            connector = name.split("-", 1)[1]
            status = read_text(status_path)
            modes_path = os.path.join(os.path.dirname(status_path), "modes")
            modes = [m for m in read_text(modes_path).splitlines() if re.fullmatch(r"\d+x\d+", m)]
            outputs.append({"output": connector, "status": status, "modes": modes})
        preferred = next((o for o in outputs if o["status"] == "connected"), None)
        resolution = ""
        current = ""
        if preferred:
            # sysfs mode is empty until the connector has a mode set; report the
            # preferred (first) mode as the panel's native mode.
            resolution = preferred["modes"][0] if preferred["modes"] else ""
            current = preferred["modes"][0] if preferred["modes"] else ""
        return {"outputs": outputs, "resolution": resolution, "current": current,
                "available": bool(preferred)}

    def display_status(self, _params: dict) -> dict:
        summary = self._display_summary()
        env = self._wayland_env()
        if env:
            completed = self.ctx.runner.run(["wlr-randr", "--json"], timeout=8, env=env)
            if completed.returncode == 0:
                try:
                    live = json.loads(completed.stdout)
                    summary["live"] = [
                        {
                            "output": o.get("name", ""),
                            "enabled": o.get("enabled", False),
                            "current": o.get("current_mode", {}),
                            "modes": [{"width": m.get("width"), "height": m.get("height"),
                                       "refresh": m.get("refresh")} for m in o.get("modes", [])],
                        }
                        for o in live
                    ]
                except json.JSONDecodeError:
                    pass
        return summary

    def display_set_mode(self, params: dict) -> dict:
        env = self._wayland_env()
        if not env:
            raise ActionError("no_session", "display changes require the graphical session")
        output = params.get("output")
        mode = params.get("mode")
        if not isinstance(output, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,32}", output):
            raise ActionError("invalid_output", "invalid display output")
        if not isinstance(mode, str) or not re.fullmatch(r"\d{3,4}x\d{3,4}(@[\d.]+)?", mode):
            raise ActionError("invalid_mode", "invalid display mode")
        allowed_outputs = {o["output"] for o in self._display_summary()["outputs"]}
        if output not in allowed_outputs:
            raise ActionError("unknown_output", "that display output is not connected")
        completed = self.ctx.runner.run(["wlr-randr", "--output", output, "--mode", mode],
                                        timeout=15, env=env)
        if completed.returncode != 0:
            raise ActionError("mode_failed", completed.stderr.strip()[:300] or "the display rejected that mode")
        return {"output": output, "mode": mode}

    # -- time / locale ----------------------------------------------------
    def set_timezone(self, params: dict) -> dict:
        zone = params.get("timezone")
        if not isinstance(zone, str) or not re.fullmatch(r"[A-Za-z0-9_+\-/]{1,64}", zone):
            raise ActionError("invalid_timezone", "invalid timezone identifier")
        completed = self.ctx.runner.run(["timedatectl", "list-timezones"], timeout=10)
        if completed.returncode == 0 and zone not in completed.stdout.splitlines():
            raise ActionError("unknown_timezone", "unknown timezone")
        self.ctx.runner.run(["timedatectl", "set-timezone", zone], timeout=15, check=True)
        return {"timezone": zone}

    def set_locale(self, params: dict) -> dict:
        locale = params.get("locale")
        if not isinstance(locale, str) or not re.fullmatch(r"[a-z]{2,3}_[A-Z]{2}\.UTF-8", locale):
            raise ActionError("invalid_locale", "invalid locale identifier")
        available = read_text("/usr/share/i18n/SUPPORTED")
        if available and f"{locale} " not in available + " ":
            raise ActionError("unsupported_locale", "that locale is not available on this image")
        self.ctx.runner.run(["localectl", "set-locale", f"LANG={locale}"], timeout=20, check=True)
        return {"locale": locale}

    def set_hostname(self, params: dict) -> dict:
        hostname = params.get("hostname")
        if not isinstance(hostname, str) or not re.fullmatch(r"[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?", hostname):
            raise ActionError("invalid_hostname", "hostname must be lowercase letters, digits and hyphens")
        self.ctx.runner.run(["hostnamectl", "set-hostname", hostname], timeout=10, check=True)
        return {"hostname": hostname}

    # -- power ------------------------------------------------------------
    def _power_guard(self) -> None:
        now = self.ctx.clock()
        if now - self._last_power < 3:
            raise ActionError("rate_limited", "a power action was just requested")
        self._last_power = now

    def reboot(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "reboot requires confirm=true")
        self._power_guard()
        self.ctx.runner.run(["systemctl", "reboot", "--no-block"], timeout=10, check=True)
        return {"rebooting": True}

    def shutdown(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "shutdown requires confirm=true")
        self._power_guard()
        self.ctx.runner.run(["systemctl", "poweroff", "--no-block"], timeout=10, check=True)
        return {"shutting_down": True}

    # -- updates ----------------------------------------------------------
    def _apt(self, *args: str, timeout: int = 120) -> subprocess.CompletedProcess:
        return self.ctx.runner.run(
            ["apt-get", "-o", "Dpkg::Options::=--force-confdef",
             "-o", "Dpkg::Options::=--force-confold", *args],
            timeout=timeout,
        )

    def update_status(self, _params: dict) -> dict:
        with self._update_lock:
            job = dict(self._update_job)
        job.pop("thread", None)
        return job

    def update_check(self, _params: dict) -> dict:
        with self._update_lock:
            if self._update_job.get("state") == "running":
                raise ActionError("busy", "an update is already running")
        update = self._apt("update", timeout=180)
        if update.returncode != 0:
            raise ActionError("update_failed", (update.stderr or update.stdout).strip()[:300])
        simulate = self._apt("-s", "upgrade", timeout=120)
        if simulate.returncode != 0:
            raise ActionError("update_failed", (simulate.stderr or simulate.stdout).strip()[:300])
        packages = [line.split()[1] for line in simulate.stdout.splitlines()
                    if line.startswith("Inst ")]
        return {"available": len(packages), "packages": packages[:80],
                "checked_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}

    def update_apply(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "installing updates requires confirm=true")
        with self._update_lock:
            if self._update_job.get("state") == "running":
                raise ActionError("busy", "an update is already running")
            self._update_job = {
                "state": "running",
                "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "log": os.path.join(self.ctx.log_dir, "update.log"),
                "reboot_required": False,
            }
        thread = threading.Thread(target=self._run_update, name="pivista-update", daemon=True)
        self._update_job["thread"] = thread
        thread.start()
        return {"started": True}

    def _run_update(self) -> None:
        log_path = self._update_job["log"]
        try:
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write(f"\n=== PiVista update {time.strftime('%Y-%m-%dT%H:%M:%S%z')} ===\n")
                result = self.ctx.runner.run(
                    ["apt-get", "-y", "-o", "Dpkg::Options::=--force-confdef",
                     "-o", "Dpkg::Options::=--force-confold", "upgrade"],
                    timeout=3600,
                )
                fh.write(result.stdout[-200000:])
                fh.write(result.stderr[-50000:])
                fh.write(f"\napt-get exit: {result.returncode}\n")
            reboot_required = os.path.exists("/var/run/reboot-required")
            with self._update_lock:
                self._update_job.update({
                    "state": "finished" if result.returncode == 0 else "failed",
                    "finished_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                    "exit": result.returncode,
                    "reboot_required": reboot_required,
                })
            log.info("update finished exit=%s reboot_required=%s", result.returncode, reboot_required)
        except Exception:
            log.error("update crashed\n%s", traceback.format_exc())
            with self._update_lock:
                self._update_job.update({"state": "failed", "finished_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")})

    def update_history(self, _params: dict) -> dict:
        path = os.path.join(self.ctx.log_dir, "update.log")
        tail = ""
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()[-80:]
            tail = "".join(lines)
        return {"log_tail": tail, "log_path": path}

    # -- signed launcher updates ------------------------------------------
    # These replace only the launcher application. The OS remains on apt, and
    # a complete image still requires reflashing until an A/B layout exists.
    def _app_update(self, call: Callable[[], dict]) -> dict:
        try:
            return call()
        except UpdateError as exc:
            raise ActionError(exc.code, exc.message) from None

    def app_update_status(self, _params: dict) -> dict:
        return self._app_update(self._app_updates.status)

    def app_update_check(self, params: dict) -> dict:
        allow = params.get("allow_prerelease") is True
        return self._app_update(lambda: self._app_updates.check(allow))

    def app_update_download(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "downloading an update requires confirm=true")
        version = params.get("version")
        if version is not None and not isinstance(version, str):
            raise ActionError("invalid_version", "version must be a string")
        allow = params.get("allow_prerelease") is True
        return self._app_update(lambda: self._app_updates.start_download(
            version=version, allow_prerelease=allow))

    def app_update_install(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "installing an update requires confirm=true")
        return self._app_update(self._app_updates.start_install)

    def app_update_postpone(self, params: dict) -> dict:
        version = params.get("version")
        if not isinstance(version, str):
            raise ActionError("invalid_version", "version must be a string")
        return self._app_update(lambda: self._app_updates.postpone(version))

    def app_update_rollback(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "rolling back requires confirm=true")
        return self._app_update(self._app_updates.rollback)

    def app_update_restart(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "restarting the launcher requires confirm=true")
        self.ctx.runner.run(["systemctl", "restart", "pivista-session.service", "--no-block"],
                            timeout=10, check=True)
        return {"restarting": True}

    # -- android ----------------------------------------------------------
    # -- remote support ---------------------------------------------------
    #
    # SSH is off by default and only the dedicated, non-sudo `support` account
    # is allowed.  Its password is generated on the device when SSH is enabled
    # and stored root-only.  VNC is bound to 127.0.0.1 by pivista-vnc.service;
    # it is reached through an SSH local-forward, never exposed directly.
    REMOTE_PASSWORD_ALPHABET = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    def _systemd_active(self, unit: str) -> bool:
        completed = self.ctx.runner.run(
            ["/usr/bin/systemctl", "is-active", "--quiet", unit], timeout=8)
        return completed.returncode == 0

    def _systemd_enabled(self, unit: str) -> bool:
        completed = self.ctx.runner.run(
            ["/usr/bin/systemctl", "is-enabled", "--quiet", unit], timeout=8)
        return completed.returncode == 0

    def _remote_password_path(self) -> str:
        return os.path.join(self.ctx.remote_dir, "ssh-password")

    def _read_remote_password(self) -> str:
        try:
            with open(self._remote_password_path(), encoding="utf-8") as fh:
                return fh.read().strip()
        except OSError:
            return ""

    def _write_remote_password(self, password: str) -> None:
        os.makedirs(self.ctx.remote_dir, mode=0o700, exist_ok=True)
        os.chmod(self.ctx.remote_dir, 0o700)
        path = self._remote_password_path()
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(password + "\n")
        os.chmod(path, 0o600)

    def _new_remote_password(self) -> str:
        return "".join(secrets.choice(self.REMOTE_PASSWORD_ALPHABET) for _ in range(20))

    def _set_support_password(self, password: str) -> None:
        self.ctx.runner.run(
            ["/usr/sbin/chpasswd"],
            timeout=15,
            check=True,
            input_text="support:" + password + "\n",
        )

    def _lock_support(self) -> None:
        self.ctx.runner.run(["/usr/bin/passwd", "--lock", "support"], timeout=10)

    def _remote_ip(self) -> str:
        try:
            return self._network_summary().get("ip", "") or ""
        except Exception:
            return ""

    def remote_status(self, _params: dict) -> dict:
        ssh_enabled = self._systemd_enabled("ssh.service")
        ssh_active = self._systemd_active("ssh.service")
        vnc_enabled = self._systemd_enabled("pivista-vnc.service")
        vnc_active = self._systemd_active("pivista-vnc.service")
        password = self._read_remote_password() if (ssh_enabled or ssh_active) else ""
        return {
            "hostname": socket.gethostname(),
            "ip": self._remote_ip(),
            "ssh_enabled": ssh_enabled,
            "ssh_active": ssh_active,
            "ssh_user": "support",
            "ssh_port": 22,
            "ssh_password": password,
            "vnc_enabled": vnc_enabled,
            "vnc_active": vnc_active,
            "vnc_host": "127.0.0.1",
            "vnc_port": 5900,
        }

    def remote_ssh_enable(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "enabling SSH requires confirm=true")
        if not os.path.exists(self.ctx.sshd_path):
            raise ActionError("not_installed", "The SSH server is not installed on this image.")
        password = self._read_remote_password() or self._new_remote_password()
        self._write_remote_password(password)
        try:
            self._set_support_password(password)
        except Exception:
            try:
                os.unlink(self._remote_password_path())
            except FileNotFoundError:
                pass
            raise
        self.ctx.runner.run(["/usr/bin/ssh-keygen", "-A"], timeout=20, check=True)
        self.ctx.runner.run(
            ["/usr/bin/systemctl", "unmask", "ssh.service"], timeout=10)
        started = self.ctx.runner.run(
            ["/usr/bin/systemctl", "enable", "--now", "ssh.service"], timeout=30)
        if started.returncode != 0:
            raise ActionError(
                "ssh_failed",
                (started.stderr or started.stdout).strip()[:300]
                or "The SSH service could not be started.",
            )
        return self.remote_status({})

    def remote_ssh_disable(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "disabling SSH requires confirm=true")
        self.ctx.runner.run(
            ["/usr/bin/systemctl", "disable", "--now", "ssh.service"], timeout=30)
        self._lock_support()
        try:
            os.unlink(self._remote_password_path())
        except FileNotFoundError:
            pass
        return self.remote_status({})

    def remote_ssh_rotate(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "rotating the SSH password requires confirm=true")
        password = self._new_remote_password()
        self._write_remote_password(password)
        self._set_support_password(password)
        return self.remote_status({})

    def remote_vnc_enable(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "enabling VNC requires confirm=true")
        if not (self._systemd_enabled("ssh.service") or self._systemd_active("ssh.service")):
            raise ActionError(
                "ssh_required",
                "Enable SSH first: VNC listens only on localhost and is reached through an SSH tunnel.",
            )
        started = self.ctx.runner.run(
            ["/usr/bin/systemctl", "enable", "--now", "pivista-vnc.service"], timeout=30)
        if started.returncode != 0:
            raise ActionError(
                "vnc_failed",
                (started.stderr or started.stdout).strip()[:300]
                or "The VNC service could not be started.",
            )
        return self.remote_status({})

    def remote_vnc_disable(self, params: dict) -> dict:
        if params.get("confirm") is not True:
            raise ActionError("confirmation_required", "disabling VNC requires confirm=true")
        self.ctx.runner.run(
            ["/usr/bin/systemctl", "disable", "--now", "pivista-vnc.service"], timeout=30)
        return self.remote_status({})

    def android_status(self, _params: dict) -> dict:
        waydroid = shutil.which("waydroid")
        binder = os.path.exists("/dev/binderfs") or os.path.exists("/dev/binder")
        psi = os.path.exists("/proc/pressure")
        page_size = os.sysconf("SC_PAGE_SIZE")
        reasons = []
        if not waydroid:
            reasons.append("Waydroid is not installed")
        if not binder:
            reasons.append("no Binder device is available")
        if not psi:
            reasons.append("Pressure Stall Information is not enabled")
        return {
            "installed": bool(waydroid),
            "binder": binder,
            "psi": psi,
            "page_size": page_size,
            "supported": False,
            "state": "unsupported" if reasons else "installed-unverified",
            "reasons": reasons or [
                "This build ships no Android runtime; Waydroid on Raspberry Pi 5 is an "
                "unverified community configuration (see docs/android.md)."
            ],
            "widevine_l1": False,
        }

    # -- diagnostics ------------------------------------------------------
    def logs_tail(self, params: dict) -> dict:
        units = {
            "session": "pivista-session.service",
            "daemon": "pivista-daemon.service",
            "firstboot": "pivista-firstboot.service",
            "boot": "-b",
        }
        unit = params.get("unit", "session")
        if unit not in units:
            raise ActionError("invalid_unit", "unknown log unit")
        completed = self.ctx.runner.run(
            ["journalctl", "--no-pager", "-n", "120", "-u", units[unit]],
            timeout=15,
        )
        return {"unit": unit, "text": completed.stdout[-40000:]}

    def diagnostics_export(self, _params: dict) -> dict:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        out_dir = os.path.join(self.ctx.state_dir, "diagnostics")
        os.makedirs(out_dir, exist_ok=True)
        try:
            hardware = json.loads(read_text(os.path.join(self.ctx.state_dir, "hardware.json"), "{}"))
        except json.JSONDecodeError:
            hardware = {}
        report = {
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "product": self._build_info(),
            "system": self.system_info({}),
            "network": self.network_status({}),
            "audio": self._audio_summary(),
            "display": self._display_summary(),
            "hardware": hardware,
            "logs": {
                "session": self.logs_tail({"unit": "session"})["text"][-12000:],
                "daemon": self.logs_tail({"unit": "daemon"})["text"][-12000:],
            },
            "note": "Wi-Fi passwords and browser data are not included.",
        }
        path = os.path.join(out_dir, f"diagnostics-{stamp}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2, sort_keys=True)
            fh.write("\n")
        os.chmod(path, 0o644)
        return {"path": path, "created": True}

    def build_provenance(self, _params: dict) -> dict:
        return {
            "build": self._build_info(),
            "provenance": read_text(os.path.join(self.ctx.config_dir, "build-provenance.txt")),
        }


# ---------------------------------------------------------------------------
# Unix socket server
# ---------------------------------------------------------------------------
class Server:
    def __init__(self, socket_path: str, service: ControlService, group: str,
                 allowed_uids: set[int]) -> None:
        self.socket_path = socket_path
        self.service = service
        self.group = group
        self.allowed_uids = allowed_uids
        self._stop = threading.Event()
        self._sock: socket.socket | None = None

    def _prepare_socket(self) -> socket.socket:
        directory = os.path.dirname(self.socket_path)
        os.makedirs(directory, mode=0o750, exist_ok=True)
        gid: int | None = None
        try:
            gid = grp.getgrnam(self.group).gr_gid
        except KeyError:
            log.warning("group %s does not exist; socket stays root-only", self.group)
        if gid is not None:
            # systemd's RuntimeDirectory is root:root by default. The session
            # user cannot traverse a 0750 root:root directory even when the
            # socket inside is root:pivista, so hand the directory to the group.
            os.chmod(directory, 0o750)
            os.chown(directory, 0, gid)
        with_existing = False
        if os.path.exists(self.socket_path):
            with_existing = True
            os.unlink(self.socket_path)
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(self.socket_path)
        os.chmod(self.socket_path, 0o660)
        if gid is not None:
            os.chown(self.socket_path, 0, gid)
        sock.listen(8)
        sock.settimeout(1.0)
        log.info("listening on %s%s", self.socket_path, " (replaced stale socket)" if with_existing else "")
        return sock

    def _peer_uid(self, conn: socket.socket) -> int:
        creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
        _pid, uid, _gid = struct.unpack("3i", creds)
        return uid

    def _handle(self, conn: socket.socket) -> None:
        try:
            uid = self._peer_uid(conn)
            if uid not in self.allowed_uids:
                log.warning("rejected client uid=%s", uid)
                conn.sendall(b'{"ok":false,"error":{"code":"forbidden","message":"unauthorized client"}}\n')
                return
            conn.settimeout(30)
            buffer = b""
            while not self._stop.is_set():
                chunk = conn.recv(4096)
                if not chunk:
                    break
                buffer += chunk
                if len(buffer) > MAX_MESSAGE:
                    conn.sendall(b'{"ok":false,"error":{"code":"message_too_large","message":"request too large"}}\n')
                    return
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    if not line.strip():
                        continue
                    response = self._process(line)
                    conn.sendall(json.dumps(response, separators=(",", ":")).encode() + b"\n")
        except (socket.timeout, ConnectionResetError, BrokenPipeError):
            pass
        except Exception:
            log.error("connection handler failed\n%s", traceback.format_exc())
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def _process(self, line: bytes) -> dict:
        request_id: int | str | None = None
        try:
            request = json.loads(line.decode("utf-8", errors="strict"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {"id": request_id, "ok": False,
                    "error": {"code": "bad_json", "message": "malformed request"}}
        if not isinstance(request, dict):
            return {"id": request_id, "ok": False,
                    "error": {"code": "bad_request", "message": "request must be an object"}}
        # Echo the request id. The launcher correlates responses with the action
        # that produced them; omitting the id silently drops every callback.
        candidate = request.get("id")
        if isinstance(candidate, (int, str)) and not isinstance(candidate, bool):
            request_id = candidate
        action = request.get("action")
        if not isinstance(action, str):
            return {"id": request_id, "ok": False,
                    "error": {"code": "bad_request", "message": "action is required"}}
        params = request.get("params", {})
        try:
            data = self.service.dispatch(action, params)
            return {"id": request_id, "ok": True, "data": data}
        except ActionError as exc:
            return {"id": request_id, "ok": False,
                    "error": {"code": exc.code, "message": exc.message}}

    def serve_forever(self) -> None:
        self._sock = self._prepare_socket()
        try:
            while not self._stop.is_set():
                try:
                    conn, _addr = self._sock.accept()
                except socket.timeout:
                    continue
                except OSError as exc:
                    if exc.errno == errno.EINTR:
                        continue
                    raise
                threading.Thread(target=self._handle, args=(conn,), daemon=True).start()
        finally:
            self._cleanup()

    def stop(self, *_args: Any) -> None:
        self._stop.set()

    def _cleanup(self) -> None:
        if self._sock is not None:
            self._sock.close()
        try:
            os.unlink(self.socket_path)
        except OSError:
            pass
        log.info("stopped")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PiVista TV control service")
    parser.add_argument("--socket", default=DEFAULT_SOCKET)
    parser.add_argument("--group", default=SESSION_GROUP)
    parser.add_argument("--config-dir", default=DEFAULT_CONFIG)
    parser.add_argument("--state-dir", default=DEFAULT_STATE)
    parser.add_argument("--log-dir", default=DEFAULT_LOG_DIR)
    parser.add_argument("--session-uid", type=int, default=SESSION_UID)
    parser.add_argument("--debug", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        stream=sys.stdout,
    )
    if os.geteuid() != 0:
        log.error("pivistad must run as root")
        return 1
    try:
        pwd.getpwuid(args.session_uid)
    except KeyError:
        log.warning("session uid %s does not exist yet", args.session_uid)

    service = ControlService(ServiceContext(
        config_dir=args.config_dir,
        state_dir=args.state_dir,
        log_dir=args.log_dir,
        session_uid=args.session_uid,
        session_group=args.group,
    ))
    server = Server(args.socket, service, args.group, allowed_uids={0, args.session_uid})
    signal.signal(signal.SIGTERM, server.stop)
    signal.signal(signal.SIGINT, server.stop)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
