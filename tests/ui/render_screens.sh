#!/bin/bash
# Render the launcher offscreen and fail on QML runtime errors or missing /
# wrongly-sized screenshots. This is a smoke test, not a pixel comparison.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="${1:-$PROJECT/build/launcher-tests/pivista-launcher}"
OUT="$PROJECT/build/ui-tests"
QML_DIR="$PROJECT/launcher/qml"
CATALOG="$PROJECT/applications/web/catalog.json"

if [[ ! -x "$LAUNCHER" ]]; then
    echo "UI smoke test: launcher binary not built; skipping" >&2
    exit 0
fi
if ! command -v python3 >/dev/null; then
    echo "UI smoke test: python3 not available; skipping" >&2
    exit 0
fi

rm -rf "$OUT"
mkdir -p "$OUT"

COUNT=0
render() {
    local name="$1" screen="$2" width="$3" height="$4" wizard="$5"
    local step="${6:-}" settings_page="${7:-}" details_app="${8:-}"
    local log="$OUT/${name}.log"
    local shot="$OUT/${name}.png"
    local -a env_args=(
        "QT_QPA_PLATFORM=offscreen"
        "QT_QUICK_BACKEND=software"
        "PIVISTA_QML_DIR=$QML_DIR"
        "PIVISTA_UI_SCREEN=$screen"
        "PIVISTA_UI_WIDTH=$width"
        "PIVISTA_UI_HEIGHT=$height"
        "PIVISTA_WEBAPP_CATALOG=$CATALOG"
        "PIVISTA_SCREENSHOT=$shot"
    )
    local home=""
    if [[ "$wizard" == "wizard" ]]; then
        home="$(mktemp -d)"
        env_args+=("HOME=$home" "XDG_CONFIG_HOME=$home/.config")
    else
        env_args+=("PIVISTA_UI_DEV=1")
    fi
    if [[ -n "$step" ]]; then
        env_args+=("PIVISTA_UI_WIZARD_STEP=$step")
    fi
    if [[ -n "$settings_page" ]]; then
        env_args+=("PIVISTA_UI_SETTINGS_PAGE=$settings_page")
    fi
    if [[ -n "$details_app" ]]; then
        env_args+=("PIVISTA_UI_APP_DETAILS=$details_app")
    fi

    if ! timeout 45s env "${env_args[@]}" "$LAUNCHER" --windowed >"$log" 2>&1; then
        echo "FAIL ${name}: launcher did not exit cleanly" >&2
        sed -n '1,120p' "$log" >&2 || true
        [[ -n "$home" ]] && rm -rf "$home"
        return 1
    fi
    [[ -n "$home" ]] && rm -rf "$home"

    if grep -Eq 'TypeError|ReferenceError|Unable to assign|Cannot assign|is not defined|Cannot read property|Failed to load component|module ".*" is not installed' "$log"; then
        echo "FAIL ${name}: QML runtime error" >&2
        grep -E 'TypeError|ReferenceError|Unable to assign|Cannot assign|is not defined|Cannot read property|Failed to load component|module ".*" is not installed' "$log" >&2
        return 1
    fi

    if [[ ! -f "$shot" ]]; then
        echo "FAIL ${name}: screenshot was not written" >&2
        sed -n '1,120p' "$log" >&2 || true
        return 1
    fi

    python3 - "$shot" "$width" "$height" <<'PY'
import struct
import sys

path, want_w, want_h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, "rb") as handle:
    head = handle.read(24)
if head[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit(f"FAIL {path}: not a PNG")
width, height = struct.unpack(">II", head[16:24])
if (width, height) != (want_w, want_h):
    raise SystemExit(f"FAIL {path}: {width}x{height}, expected {want_w}x{want_h}")
PY
    if ! python3 "$PROJECT/tests/ui/screenshot_content.py" "$shot"; then
        echo "FAIL ${name}: screenshot has no visible content" >&2
        return 1
    fi
    COUNT=$((COUNT + 1))
    echo "PASS ${name} (${width}x${height})"
}

render home-1080p home 1920 1080 dev
render home-720p home 1280 720 dev
render home-4k home 3840 2160 dev
render apps-1080p apps 1920 1080 dev
render apps-720p apps 1280 720 dev
render apps-details-1080p apps 1920 1080 dev "" "" web.netflix
render apps-details-720p apps 1280 720 dev "" "" web.netflix
render games-1080p games 1920 1080 dev
render games-720p games 1280 720 dev
render media-1080p media 1920 1080 dev
render media-720p media 1280 720 dev
render search-1080p search 1920 1080 dev
render search-720p search 1280 720 dev
render settings-1080p settings 1920 1080 dev
render settings-720p settings 1280 720 dev
render settings-appearance-1080p settings 1920 1080 dev "" appearance
render settings-appearance-720p settings 1280 720 dev "" appearance
render wizard-1080p home 1920 1080 wizard 0
render wizard-1080p-step1 home 1920 1080 wizard 1
for step in 0 1 2 3 4 5 6 7; do
    render "wizard-720p-step${step}" home 1280 720 wizard "$step"
done

echo "UI smoke test: $COUNT screens passed"
