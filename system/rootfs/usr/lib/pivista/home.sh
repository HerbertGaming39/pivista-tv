#!/bin/bash
# Global Home action, bound in sway. Closes any streaming window and returns
# focus to the launcher. Uses the compositor IPC socket; no polling.
set -u

if [ -z "${SWAYSOCK:-}" ]; then
    for candidate in /run/user/"$(id -u)"/sway-ipc.*.sock; do
        [ -S "$candidate" ] && SWAYSOCK="$candidate" && break
    done
    export SWAYSOCK
fi

/usr/bin/swaymsg '[app_id="pivista-webapp"] kill' >/dev/null 2>&1 || true
/usr/bin/swaymsg '[app_id="chromium"] kill' >/dev/null 2>&1 || true
/usr/bin/swaymsg '[app_id="pivista-launcher"] focus' >/dev/null 2>&1 || true

# The compositor can consume the Home key before the launcher sees it. Tell the
# launcher explicitly so it resets to the home screen and closes native apps.
HOME_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pivista-home.sock"
if [ -S "$HOME_SOCKET" ]; then
    /usr/bin/python3 - "$HOME_SOCKET" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(1.0)
try:
    sock.connect(sys.argv[1])
    sock.sendall(b"home\n")
except OSError:
    pass
finally:
    sock.close()
PY
fi
