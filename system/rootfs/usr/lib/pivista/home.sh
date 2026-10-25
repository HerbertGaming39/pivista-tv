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
