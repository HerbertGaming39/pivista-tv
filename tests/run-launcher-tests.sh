#!/bin/bash
# Build and run the launcher unit tests on the host (x86_64 or arm64).
# Requires Qt 6 development packages; skips with a clear message if absent.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$PROJECT/build/launcher-tests"

qt_config="$(find /usr/lib /usr/local/lib -path '*/cmake/Qt6/Qt6Config.cmake' -print -quit 2>/dev/null || true)"
if ! command -v cmake >/dev/null \
   || { ! pkg-config --exists Qt6Core 2>/dev/null && [[ -z "$qt_config" ]]; }; then
    echo "launcher tests: Qt 6 development packages not installed; skipping" >&2
    exit 0
fi

cmake -S "$PROJECT/launcher" -B "$BUILD" \
      -DCMAKE_BUILD_TYPE=Release -DPIVISTA_BUILD_TESTS=ON >/dev/null
cmake --build "$BUILD" --parallel "$(nproc)" >/dev/null
ctest --test-dir "$BUILD" --output-on-failure
"$PROJECT/tests/ui/render_screens.sh" "$BUILD/pivista-launcher"
