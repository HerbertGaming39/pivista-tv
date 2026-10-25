#!/bin/bash
# Apply optional remote-control scancode mappings at boot.
# Format: <scancode> <keycode> [# comment]
# Example: 0x1c0 172   # KEY_HOMEPAGE
set -u

MAP=/etc/pivista/input.map
[ -r "$MAP" ] || exit 0

applied=0
while IFS= read -r line; do
    line="${line%%#*}"
    set -- $line
    [ $# -eq 2 ] || continue
    case "$1" in 0x*|[0-9]*) ;; *) continue ;; esac
    if setkeycodes "$1" "$2" 2>/dev/null; then
        applied=$((applied + 1))
    else
        echo "pivista-input: could not map scancode $1 to keycode $2" >&2
    fi
done < "$MAP"

echo "pivista-input: applied ${applied} scancode mapping(s)"
