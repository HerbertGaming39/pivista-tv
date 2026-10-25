#!/bin/bash
# Run the real PiVista launcher on Windows through WSLg, without a Pi.
#
# The Qt/QML application is the production launcher, not a mock.  It is built
# as an x86-64 Linux binary and its window is shown on the Windows desktop by
# WSLg.  Use it to exercise the first-boot wizard, remote/keyboard focus and
# navigation before flashing a card.
#
# This is a UI preview, not a Pi simulation: there is no control daemon in the
# preview, so network, display, audio and package actions report that the
# service is unavailable.  Nothing in the preview can change Windows settings.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$PROJECT/build/launcher-wsl-preview"
PREVIEW_HOME="$PROJECT/build/preview-home"

reset=0
case "${1:-}" in
    --reset) reset=1 ;;
    "") ;;
    *) echo "usage: $0 [--reset]" >&2; exit 2 ;;
esac

if ! command -v cmake >/dev/null 2>&1; then
    echo "preview: cmake is not installed in WSL" >&2
    exit 1
fi
qt_found=0
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists Qt6Core 2>/dev/null; then
    qt_found=1
elif command -v qtpaths6 >/dev/null 2>&1 \
     && [ -f "$(qtpaths6 --query QT_INSTALL_LIBS)/cmake/Qt6/Qt6Config.cmake" ]; then
    qt_found=1
elif find /usr/lib /usr/local/lib -path '*/cmake/Qt6/Qt6Config.cmake' -print -quit 2>/dev/null | grep -q .; then
    qt_found=1
fi
if [ "$qt_found" -eq 0 ]; then
    echo "preview: Qt 6 development packages are not installed in WSL" >&2
    echo "preview: sudo apt install qt6-base-dev qt6-declarative-dev" >&2
    exit 1
fi
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "preview: no WSLg display. Run this from Windows with WSLg enabled." >&2
    exit 1
fi

cmake -S "$PROJECT/launcher" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$BUILD" --parallel "$(nproc)" >/dev/null

if [ "$reset" = 1 ]; then
    rm -rf "$PREVIEW_HOME"
fi
mkdir -p "$PREVIEW_HOME/.config" "$PREVIEW_HOME/.local/share"

# Unix sockets do not work on the /mnt/c 9p share.  Keep the runtime socket in
# the WSL filesystem while settings remain in the isolated preview home.
PREVIEW_RUNTIME="/tmp/pivista-preview-$(id -u)"
mkdir -p "$PREVIEW_RUNTIME"
chmod 700 "$PREVIEW_RUNTIME"

export HOME="$PREVIEW_HOME"
export XDG_CONFIG_HOME="$PREVIEW_HOME/.config"
export XDG_DATA_HOME="$PREVIEW_HOME/.local/share"
export XDG_RUNTIME_DIR="$PREVIEW_RUNTIME"
export PIVISTA_QML_DIR="$PROJECT/launcher/qml"
export PIVISTA_WEBAPP_CATALOG="$PROJECT/applications/web/catalog.json"
export PIVISTA_UI_WIDTH="${PIVISTA_UI_WIDTH:-1280}"
export PIVISTA_UI_HEIGHT="${PIVISTA_UI_HEIGHT:-720}"

# WSLg exposes both an X server and Wayland.  XCB is the most predictable for
# a normal window on older Windows builds; fall back to Wayland when needed.
if [ -z "${QT_QPA_PLATFORM:-}" ]; then
    if [ -n "${DISPLAY:-}" ]; then
        export QT_QPA_PLATFORM=xcb
    else
        export QT_QPA_PLATFORM=wayland
    fi
fi

echo "preview: starting the current source tree at ${PIVISTA_UI_WIDTH}x${PIVISTA_UI_HEIGHT}"
echo "preview: this includes unreleased focus fixes; the window version string may still say 0.3.1"
echo "preview: use the arrow keys, Enter, Escape and Home in the window"
echo "preview: no control service is running; settings actions will report that"
exec "$BUILD/pivista-launcher" --windowed
