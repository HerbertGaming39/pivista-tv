#!/bin/bash
# PiVista TV graphical session.
#
# sway is used instead of a single-client kiosk compositor because it gives the
# appliance a real global Home key: the compositor can close a streaming app
# and refocus the launcher even when Chromium has keyboard focus. systemd-logind
# grants the seat; there is no display manager and no desktop environment.
set -u

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=PiVista
export QT_QPA_PLATFORM=wayland
export QT_QUICK_CONTROLS_STYLE=Basic
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-qt.qpa.*=false}"
export MOZ_ENABLE_WAYLAND=1
export SDL_VIDEODRIVER=wayland

# Optional local overrides, e.g. software rendering for debugging.
if [ -r /etc/pivista/session.conf ]; then
    # shellcheck disable=SC1091
    . /etc/pivista/session.conf
fi

if [ "${PIVISTA_SOFTWARE_RENDER:-0}" = "1" ]; then
    export LIBGL_ALWAYS_SOFTWARE=1
    export QT_QUICK_BACKEND=software
    export WLR_RENDERER=pixman
fi

exec /usr/bin/sway --config /etc/pivista/sway/config
