#!/bin/bash
# PiVista TV first-boot preparation.
# Records a hardware snapshot used by Settings > System and by diagnostics.
# The interactive wizard itself runs inside the launcher on first start.
set -euo pipefail

STATE=/var/lib/pivista
mkdir -p "$STATE"

/usr/bin/python3 - "$STATE" <<'PY'
import glob, json, os, platform, sys, time

state = sys.argv[1]
def read(path, default=""):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().strip()
    except OSError:
        return default

model = read("/proc/device-tree/model") or read("/sys/firmware/devicetree/base/model")
snapshot = {
    "captured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "model": model,
    "kernel": platform.release(),
    "architecture": platform.machine(),
    "python": platform.python_version(),
    "audio_cards": [line for line in read("/proc/asound/cards").splitlines() if line.strip()],
    "hdmi_outputs": [
        {"connector": os.path.basename(os.path.dirname(p)), "status": read(p)}
        for p in sorted(glob.glob("/sys/class/drm/card*-HDMI*/status"))
    ],
    "video_devices": sorted(glob.glob("/dev/video*")),
    "thermal_zones": sorted(glob.glob("/sys/class/thermal/thermal_zone*")),
}
path = os.path.join(state, "hardware.json")
with open(path, "w", encoding="utf-8") as fh:
    json.dump(snapshot, fh, indent=2, sort_keys=True)
    fh.write("\n")
os.chmod(path, 0o644)
print(f"hardware snapshot: {model or 'unknown model'}, kernel {snapshot['kernel']}")
PY

# Browser profiles live in the session user's home and must exist before first
# launch so Chromium never creates them as root.
install -d -m 0750 -o pivista -g pivista /home/pivista/.config/pivista/browser
install -d -m 0750 -o pivista -g pivista /home/pivista/.local/share/pivista

touch "$STATE/firstboot.done"
chmod 0644 "$STATE/firstboot.done"
