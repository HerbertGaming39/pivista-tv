#!/bin/bash
# Keep exactly one launcher running inside the sway session.
# A crash is restarted; a deliberate exit (status 0) ends the session so
# systemd can restart it cleanly.
set -u

failures=0
while true; do
    /usr/bin/pivista-launcher
    code=$?
    if [ "$code" -eq 0 ]; then
        /usr/bin/swaymsg exit >/dev/null 2>&1 || true
        break
    fi
    failures=$((failures + 1))
    echo "pivista-launcher exited with status ${code}; restarting in 2s" >&2
    # Do not leave a black screen when the QML or a Qt plugin is broken.
    # swaynag runs in the compositor and points at the journal for details.
    if [ "$failures" -eq 3 ] && [ -x /usr/bin/swaynag ]; then
        /usr/bin/swaynag -t error \
            -m "PiVista TV could not start. Check: journalctl -u pivista-session -b" \
            >/dev/null 2>&1 &
    fi
    sleep 2
done
