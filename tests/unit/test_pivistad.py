"""Unit tests for pivistad. No root, network or Raspberry Pi required."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "daemon"))

import pivistad  # noqa: E402


def completed(argv, stdout="", stderr="", code=0):
    return subprocess.CompletedProcess(argv, code, stdout, stderr)


class StubRunner:
    """Returns canned output per command prefix; records every invocation."""

    def __init__(self, responses=None):
        self.responses = responses or {}
        self.calls = []
        self.inputs = []

    def run(self, argv, timeout=None, env=None, check=False, input_text=None):
        self.calls.append(list(argv))
        self.inputs.append(input_text)
        for prefix, response in self.responses.items():
            if tuple(argv[:len(prefix)]) == tuple(prefix):
                if callable(response):
                    response = response(argv)
                if isinstance(response, str):
                    return completed(argv, stdout=response)
                return completed(argv, stdout=response[0], stderr=response[1], code=response[2])
        return completed(argv)


def service_with(runner, remote_dir=None):
    ctx = pivistad.ServiceContext(runner=runner, state_dir="/tmp/pivista-test",
                                  log_dir="/tmp/pivista-test", config_dir="/tmp/pivista-test",
                                  sshd_path="/bin/sh")
    if remote_dir is not None:
        ctx.remote_dir = remote_dir
    return pivistad.ControlService(ctx)


class DispatchTests(unittest.TestCase):
    def test_unknown_action_rejected(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.dispatch("system.format_everything", {})
        self.assertEqual(ctx.exception.code, "unknown_action")

    def test_params_must_be_object(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.dispatch("ping", ["not", "an", "object"])
        self.assertEqual(ctx.exception.code, "invalid_params")

    def test_ping(self):
        data = service_with(StubRunner()).dispatch("ping", {})
        self.assertEqual(data["service"], "pivistad")

    def test_protocol_bad_json(self):
        server = pivistad.Server("/tmp/does-not-matter.sock", service_with(StubRunner()), "root", {0})
        response = server._process(b"{not json")
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "bad_json")

    def test_protocol_ok(self):
        server = pivistad.Server("/tmp/does-not-matter.sock", service_with(StubRunner()), "root", {0})
        response = server._process(json.dumps({"action": "ping"}).encode())
        self.assertTrue(response["ok"])
        self.assertEqual(response["data"]["service"], "pivistad")

    def test_protocol_echoes_request_id(self):
        """The launcher drops responses that do not carry its request id."""
        server = pivistad.Server("/tmp/does-not-matter.sock", service_with(StubRunner()), "root", {0})
        response = server._process(json.dumps({"id": 42, "action": "ping"}).encode())
        self.assertEqual(response["id"], 42)
        self.assertTrue(response["ok"])

    def test_protocol_echoes_request_id_on_error(self):
        server = pivistad.Server("/tmp/does-not-matter.sock", service_with(StubRunner()), "root", {0})
        response = server._process(json.dumps({"id": "abc", "action": "missing.action"}).encode())
        self.assertEqual(response["id"], "abc")
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "unknown_action")

    def test_protocol_rejects_non_scalar_request_id(self):
        server = pivistad.Server("/tmp/does-not-matter.sock", service_with(StubRunner()), "root", {0})
        response = server._process(json.dumps({"id": {"bad": True}, "action": "ping"}).encode())
        self.assertIsNone(response["id"])
        self.assertTrue(response["ok"])


class NetworkTests(unittest.TestCase):
    def test_scan_parses_escaped_colons_and_deduplicates(self):
        output = (
            "Home\\:Net:70:WPA2\n"
            "Home\\:Net:40:WPA2\n"
            "OpenNet:20:\n"
            ":12:WPA2\n"
        )
        runner = StubRunner({("nmcli",): output})
        svc = service_with(runner)
        networks = svc.network_scan({"rescan": True})["networks"]
        self.assertEqual([n["ssid"] for n in networks], ["Home:Net", "OpenNet"])
        self.assertEqual(networks[0]["signal"], 70)
        self.assertFalse(networks[1]["secure"])

    def test_connect_rejects_leading_dash(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.network_connect({"ssid": "--help", "password": "x"})
        self.assertEqual(ctx.exception.code, "invalid_ssid")

    def test_connect_rejects_empty_ssid(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError):
            svc.network_connect({"ssid": "", "password": ""})

    def test_connect_uses_argv_not_shell(self):
        runner = StubRunner({("nmcli", "device", "wifi", "connect"): ""})
        svc = service_with(runner)
        svc.network_connect({"ssid": "Cafe; rm -rf /", "password": "$(reboot)"})
        argv = next(c for c in runner.calls if c[:4] == ["nmcli", "device", "wifi", "connect"])
        self.assertIn("Cafe; rm -rf /", argv)
        self.assertEqual(argv[-2:], ["password", "$(reboot)"])

    def test_connect_failure_is_reported(self):
        runner = StubRunner({("nmcli", "device", "wifi", "connect"): ("", "Error: Secrets were required", 4)})
        svc = service_with(runner)
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.network_connect({"ssid": "Home", "password": "wrong"})
        self.assertEqual(ctx.exception.code, "connect_failed")

    def test_network_summary_picks_connected_device(self):
        status = (
            "wlan0:wifi:connected:Home\n"
            "eth0:ethernet:unavailable:\n"
            "lo:loopback:unmanaged:\n"
        )
        runner = StubRunner({
            ("nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION"): status,
            ("nmcli", "-g", "IP4.ADDRESS"): "192.168.1.42/24\n",
        })
        summary = service_with(runner)._network_summary()
        self.assertTrue(summary["connected"])
        self.assertEqual(summary["ip"], "192.168.1.42")
        self.assertTrue(summary["wifi_connected"])
        self.assertEqual(len([d for d in summary["devices"] if d["device"] != "lo"]), 2)


class AudioTests(unittest.TestCase):
    def test_sinks_parse_json_and_default(self):
        sinks = json.dumps([
            {"index": 1, "name": "alsa.hdmi", "description": "HDMI", "mute": False,
             "volume": {"front-left": {"value_percent": "65%"}}},
            {"index": 2, "name": "alsa.headphones", "description": "Headphones", "mute": True,
             "volume": {"front-left": {"value_percent": "20%"}}},
        ])
        runner = StubRunner({
            ("pactl", "-f", "json", "list", "sinks"): sinks,
            ("pactl", "get-default-sink"): "alsa.hdmi\n",
        })
        summary = service_with(runner).audio_status({})
        self.assertTrue(summary["available"])
        self.assertEqual(summary["default"], "alsa.hdmi")
        self.assertEqual(summary["volume"], 65)
        self.assertTrue(summary["hdmi"])

    def test_volume_rejects_out_of_range(self):
        svc = service_with(StubRunner())
        for bad in (-1, 101, "loud", None):
            with self.assertRaises(pivistad.ActionError):
                svc.audio_set_volume({"volume": bad})

    def test_volume_sets_percentage_on_default_sink(self):
        runner = StubRunner({("pactl", "get-default-sink"): "alsa.hdmi\n"})
        svc = service_with(runner)
        svc.audio_set_volume({"volume": 40})
        self.assertIn(["pactl", "set-sink-volume", "alsa.hdmi", "40%"], runner.calls)

    def test_unknown_output_rejected(self):
        runner = StubRunner({
            ("pactl", "-f", "json", "list", "sinks"): json.dumps(
                [{"name": "alsa.hdmi", "description": "HDMI", "volume": {}, "mute": False}]),
            ("pactl", "get-default-sink"): "alsa.hdmi\n",
        })
        svc = service_with(runner)
        with self.assertRaises(pivistad.ActionError):
            svc.audio_set_output({"sink": "evil--sink"})


class PowerTests(unittest.TestCase):
    def test_reboot_requires_confirmation(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.reboot({})
        self.assertEqual(ctx.exception.code, "confirmation_required")

    def test_reboot_runs_systemctl(self):
        runner = StubRunner()
        svc = service_with(runner)
        svc.reboot({"confirm": True})
        self.assertEqual(runner.calls[-1][:3], ["systemctl", "reboot", "--no-block"])

    def test_power_actions_are_rate_limited(self):
        svc = service_with(StubRunner())
        svc.reboot({"confirm": True})
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.shutdown({"confirm": True})
        self.assertEqual(ctx.exception.code, "rate_limited")


class TimezoneTests(unittest.TestCase):
    def test_invalid_timezone_rejected(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError):
            svc.set_timezone({"timezone": "Europe/Warsaw; rm -rf /"})

    def test_unknown_timezone_rejected(self):
        runner = StubRunner({("timedatectl", "list-timezones"): "Europe/Warsaw\nUTC\n"})
        svc = service_with(runner)
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.set_timezone({"timezone": "America/Atlantis"})
        self.assertEqual(ctx.exception.code, "unknown_timezone")

    def test_known_timezone_applied(self):
        runner = StubRunner({("timedatectl", "list-timezones"): "Europe/Warsaw\nUTC\n"})
        svc = service_with(runner)
        svc.set_timezone({"timezone": "Europe/Warsaw"})
        self.assertIn(["timedatectl", "set-timezone", "Europe/Warsaw"], runner.calls)


class UpdateTests(unittest.TestCase):
    def test_update_check_lists_packages(self):
        simulate = (
            "NOTE: This is only a simulation!\n"
            "Inst libc6 [2.41] (2.42 Debian:stable-updates [arm64])\n"
            "Inst chromium [156.0] (157.0 Debian:stable [arm64])\n"
        )
        runner = StubRunner({
            ("apt-get", "-o"): "",
        })
        # Apt calls share a prefix ending with options; route by last token.
        def responder(argv):
            return ("", "", 0) if argv[-1] == "update" else (simulate, "", 0)
        runner.responses = {("apt-get",): responder}
        svc = service_with(runner)
        result = svc.update_check({})
        self.assertEqual(result["available"], 2)
        self.assertIn("chromium", result["packages"])

    def test_update_apply_requires_confirmation(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.update_apply({})
        self.assertEqual(ctx.exception.code, "confirmation_required")

    def test_app_update_download_requires_confirmation(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.app_update_download({})
        self.assertEqual(ctx.exception.code, "confirmation_required")

    def test_app_update_install_requires_confirmation(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.app_update_install({})
        self.assertEqual(ctx.exception.code, "confirmation_required")

    def test_app_update_check_forwards_prerelease_flag(self):
        svc = service_with(StubRunner())
        seen = {}

        def check(allow):
            seen["allow"] = allow
            return {"available": False, "installed": "0.3.0", "job": {"state": "idle"}}

        svc._app_updates.check = check
        result = svc.app_update_check({"allow_prerelease": True})
        self.assertTrue(seen["allow"])
        self.assertEqual(result["installed"], "0.3.0")

    def test_app_update_restart_uses_systemctl(self):
        runner = StubRunner()
        svc = service_with(runner)
        with self.assertRaises(pivistad.ActionError):
            svc.app_update_restart({})
        svc.app_update_restart({"confirm": True})
        self.assertEqual(runner.calls[-1][:3], ["systemctl", "restart", "pivista-session.service"])

    def test_app_update_status_is_readable_on_a_non_product_host(self):
        status = service_with(StubRunner()).app_update_status({})
        self.assertIn(status["installed"], {"unknown", "0.3.0"})
        self.assertIn("job", status)


class DisplayTests(unittest.TestCase):
    def test_display_summary_empty_is_safe(self):
        svc = service_with(StubRunner())
        summary = svc._display_summary()
        self.assertFalse(summary["available"])
        self.assertEqual(summary["outputs"], [])

    def test_set_mode_rejects_shell_metacharacters(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError):
            svc.display_set_mode({"output": "HDMI-A-1", "mode": "1920x1080; reboot"})


class AndroidTests(unittest.TestCase):
    def test_android_is_reported_unsupported_without_runtime(self):
        data = service_with(StubRunner()).android_status({})
        self.assertFalse(data["supported"])
        self.assertFalse(data["widevine_l1"])
        self.assertIn(data["state"], {"unsupported", "installed-unverified"})


class RemoteAccessTests(unittest.TestCase):
    def test_status_is_off_and_has_no_password_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            runner = StubRunner({
                ("/usr/bin/systemctl", "is-active"): ("", "", 3),
                ("/usr/bin/systemctl", "is-enabled"): ("", "", 1),
            })
            data = service_with(runner, tmp).remote_status({})
            self.assertFalse(data["ssh_enabled"])
            self.assertFalse(data["vnc_enabled"])
            self.assertEqual(data["ssh_password"], "")
            self.assertEqual(data["vnc_host"], "127.0.0.1")

    def test_ssh_enable_requires_confirmation(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(pivistad.ActionError) as ctx:
                service_with(StubRunner(), tmp).remote_ssh_enable({})
            self.assertEqual(ctx.exception.code, "confirmation_required")

    def test_ssh_enable_generates_password_and_starts_service(self):
        with tempfile.TemporaryDirectory() as tmp:
            runner = StubRunner({
                ("/usr/bin/systemctl", "is-enabled"): "",
                ("/usr/bin/systemctl", "is-active"): "",
                ("/usr/sbin/chpasswd"): "",
                ("/usr/bin/ssh-keygen"): "",
                ("/usr/bin/systemctl", "unmask"): "",
                ("/usr/bin/systemctl", "enable"): "",
            })
            svc = service_with(runner, tmp)
            data = svc.remote_ssh_enable({"confirm": True})
            self.assertTrue(data["ssh_enabled"])
            self.assertEqual(len(data["ssh_password"]), 20)
            self.assertIn(["/usr/bin/ssh-keygen", "-A"], runner.calls)
            self.assertIn(["/usr/bin/systemctl", "enable", "--now", "ssh.service"], runner.calls)

            call = runner.calls.index(["/usr/sbin/chpasswd"])
            self.assertRegex(runner.inputs[call], r"^support:[A-Za-z0-9]{20}\n$")

    def test_ssh_disable_locks_support_and_removes_password(self):
        with tempfile.TemporaryDirectory() as tmp:
            runner = StubRunner({
                ("/usr/bin/systemctl", "is-enabled"): "",
                ("/usr/bin/systemctl", "is-active"): "",
                ("/usr/sbin/chpasswd"): "",
                ("/usr/bin/ssh-keygen"): "",
                ("/usr/bin/systemctl", "unmask"): "",
                ("/usr/bin/systemctl", "enable"): "",
            })
            svc = service_with(runner, tmp)
            svc.remote_ssh_enable({"confirm": True})
            svc.remote_ssh_disable({"confirm": True})
            self.assertIn(["/usr/bin/passwd", "--lock", "support"], runner.calls)
            self.assertFalse((pathlib.Path(tmp) / "ssh-password").exists())

    def test_vnc_requires_ssh(self):
        with tempfile.TemporaryDirectory() as tmp:
            runner = StubRunner({
                ("/usr/bin/systemctl", "is-enabled"): ("", "", 1),
                ("/usr/bin/systemctl", "is-active"): ("", "", 3),
            })
            with self.assertRaises(pivistad.ActionError) as ctx:
                service_with(runner, tmp).remote_vnc_enable({"confirm": True})
            self.assertEqual(ctx.exception.code, "ssh_required")

    def test_vnc_enable_starts_local_service_when_ssh_is_enabled(self):
        with tempfile.TemporaryDirectory() as tmp:
            runner = StubRunner({
                ("/usr/bin/systemctl", "is-enabled"): "",
                ("/usr/bin/systemctl", "is-active"): "",
                ("/usr/bin/systemctl", "enable"): "",
            })
            data = service_with(runner, tmp).remote_vnc_enable({"confirm": True})
            self.assertTrue(data["vnc_enabled"])
            self.assertIn(["/usr/bin/systemctl", "enable", "--now", "pivista-vnc.service"],
                          runner.calls)


class InputTests(unittest.TestCase):
    SAMPLE = """I: Bus=0003 Vendor=046d Product=c52b Version=0111
N: Name="Logitech USB Receiver"
S: Sysfs=/devices/pci0000:00/usb1/1-1/1-1:1.0/0003:046D:C52B.0001/input/input0
H: Handlers=sysrq kbd leds event0
B: EV=120013
B: KEY=10000 7 ff9f207a c14057ff febeffdf ffefffff ffffffff fffffffe

I: Bus=0003 Vendor=0000 Product=0000 Version=0000
N: Name="HDMI CEC"
S: Sysfs=/devices/virtual/input/input1
H: Handlers=event1
B: EV=3
B: KEY=0

I: Bus=0003 Vendor=1b1c Product=1b3e Version=0100
N: Name="Wireless Remote"
S: Sysfs=/devices/virtual/input/input2
H: Handlers=event2
B: EV=13
B: KEY=1 0 0 0 0 0 0 0 0
"""

    def test_parser_finds_keyboards_and_remotes(self):
        devices = pivistad.parse_input_devices(self.SAMPLE)
        names = [device["name"] for device in devices]
        self.assertIn("Logitech USB Receiver", names)
        self.assertIn("Wireless Remote", names)
        self.assertNotIn("HDMI CEC", names)
        self.assertEqual(devices[0]["name"], "Logitech USB Receiver")
        self.assertEqual(devices[0]["kind"], "keyboard")
        self.assertEqual(devices[0]["event"], "/dev/input/event0")
        self.assertEqual(devices[1]["kind"], "remote")

    def test_status_is_safe_without_devices(self):
        with tempfile.TemporaryDirectory() as tmp:
            original = pivistad.read_text
            try:
                pivistad.read_text = lambda path, default="": ""
                data = service_with(StubRunner(), tmp).input_status({})
            finally:
                pivistad.read_text = original
            self.assertEqual(data["devices"], [])
            self.assertFalse(data["cec"]["enabled"])
            self.assertTrue(data["input_map_present"] in (True, False))


class BluetoothTests(unittest.TestCase):
    SHOW = """Controller 00:1A:7D:DA:71:13 (public)
\tName: pivista
\tPowered: yes
\tDiscovering: no
"""

    def test_status_parses_adapter_and_paired_devices(self):
        runner = StubRunner({
            ("bluetoothctl", "show"): self.SHOW,
            ("bluetoothctl", "devices", "Paired"):
                "Device AA:BB:CC:DD:EE:FF TV Remote\n",
        })
        data = service_with(runner).bluetooth_status({})
        self.assertTrue(data["available"])
        self.assertTrue(data["powered"])
        self.assertEqual(data["adapter"], "00:1A:7D:DA:71:13")
        self.assertEqual(data["paired"][0]["name"], "TV Remote")

    def test_status_is_unavailable_when_tool_is_missing(self):
        def missing(argv, **kwargs):
            raise pivistad.ActionError("not_installed", "bluetoothctl is not installed")

        runner = StubRunner()
        runner.run = missing
        data = service_with(runner).bluetooth_status({})
        self.assertFalse(data["available"])
        self.assertEqual(data["paired"], [])

    def test_pair_requires_confirmation_and_valid_address(self):
        svc = service_with(StubRunner())
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.bluetooth_pair({"address": "AA:BB:CC:DD:EE:FF"})
        self.assertEqual(ctx.exception.code, "confirmation_required")
        with self.assertRaises(pivistad.ActionError) as ctx:
            svc.bluetooth_pair({"confirm": True, "address": "--help"})
        self.assertEqual(ctx.exception.code, "invalid_address")

    def test_pair_trusts_and_connects(self):
        runner = StubRunner({
            ("bluetoothctl", "--timeout", "30", "pair"): "Pairing successful\n",
            ("bluetoothctl", "trust"): "",
            ("bluetoothctl", "connect"): "",
            ("bluetoothctl", "show"): self.SHOW,
            ("bluetoothctl", "devices", "Paired"):
                "Device AA:BB:CC:DD:EE:FF TV Remote\n",
        })
        svc = service_with(runner)
        svc.bluetooth_pair({"confirm": True, "address": "aa:bb:cc:dd:ee:ff"})
        self.assertIn(["bluetoothctl", "--timeout", "30", "pair", "AA:BB:CC:DD:EE:FF"],
                      runner.calls)
        self.assertIn(["bluetoothctl", "trust", "AA:BB:CC:DD:EE:FF"], runner.calls)
        self.assertIn(["bluetoothctl", "connect", "AA:BB:CC:DD:EE:FF"], runner.calls)

    def test_scan_marks_paired_devices(self):
        runner = StubRunner({
            ("bluetoothctl", "--timeout", "8", "scan", "on"):
                "[NEW] Device AA:BB:CC:DD:EE:FF Remote\n[NEW] Device 11:22:33:44:55:66 Speaker\n",
            ("bluetoothctl", "devices", "Paired"):
                "Device AA:BB:CC:DD:EE:FF Remote\n",
        })
        data = service_with(runner).bluetooth_scan({"confirm": True})
        self.assertEqual(len(data["devices"]), 2)
        self.assertTrue(data["devices"][0]["paired"])
        self.assertFalse(data["devices"][1]["paired"])


if __name__ == "__main__":
    unittest.main()
