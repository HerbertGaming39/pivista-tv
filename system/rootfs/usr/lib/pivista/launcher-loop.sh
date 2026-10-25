#!/bin/bash
# Keep exactly one launcher running inside the sway session.
# A crash is restarted; a deliberate exit (status 0) ends the session so
# systemd can restart it cleanly.
set -u

while true; do
    /usr/bin/pivista-launcher
    code=$?
    if [ "$code" -eq 0 ]; then
        /usr/bin/swaymsg exit >/dev/null 2>&1 || true
        break
    fi
    echo "pivista-launcher exited with status ${code}; restarting in 2s" >&2
    sleep 2
done
