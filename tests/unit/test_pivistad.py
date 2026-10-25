"""Unit tests for pivistad. No root, network or Raspberry Pi required."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
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

    def run(self, argv, timeout=None, env=None, check=False):
        self.calls.append(list(argv))
        for prefix, response in self.responses.items():
            if tuple(argv[:len(prefix)]) == tuple(prefix):
                if callable(response):
                    response = response(argv)
                if isinstance(response, str):
                    return completed(argv, stdout=response)
                return completed(argv, stdout=response[0], stderr=response[1], code=response[2])
        return completed(argv)


def service_with(runner):
    ctx = pivistad.ServiceContext(runner=runner, state_dir="/tmp/pivista-test",
                                  log_dir="/tmp/pivista-test", config_dir="/tmp/pivista-test")
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


if __name__ == "__main__":
    unittest.main()
