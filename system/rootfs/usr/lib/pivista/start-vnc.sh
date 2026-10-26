#!/bin/bash
# Start the local-only VNC server inside the running PiVista sway session.
#
# It binds to 127.0.0.1 on purpose.  The supported way to reach it is an SSH
# local port forward:
#   ssh -L 5900:127.0.0.1:5900 support@<pi-address>
# then point a VNC viewer at 127.0.0.1:5900.  No unauthenticated VNC port is
# exposed to the network.
set -u

runtime="${XDG_RUNTIME_DIR:-/run/user/1000}"
display=""

for candidate in "$runtime"/wayland-*; do
    [ -S "$candidate" ] || continue
    display="${candidate##*/}"
    break
done

if [ -z "$display" ]; then
    echo "pivista-vnc: no Wayland socket in $runtime" >&2
    exit 1
fi

export WAYLAND_DISPLAY="$display"
exec /usr/bin/wayvnc 127.0.0.1 5900
