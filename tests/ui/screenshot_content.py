#!/usr/bin/env python3
"""Fail when a rendered launcher screen has no bright content.

The offscreen smoke test used to check only that a PNG of the right size was
written.  A screen can be the correct size while its content is scrolled out of
view (the Media section had exactly that bug), so this check decodes the PNG,
ignores the header band, and requires a small amount of bright text/pixels in
the content area.  It uses only the Python standard library.
"""
from __future__ import annotations

import struct
import sys
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}


def paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode(path: str) -> tuple[int, int, bytes]:
    with open(path, "rb") as handle:
        data = handle.read()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG")
    pos = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = None
    compressed = bytearray()
    while pos + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        payload = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", payload[:10])
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
    if width is None or height is None or bit_depth != 8 or color_type not in CHANNELS:
        raise ValueError(f"unsupported PNG (depth={bit_depth}, colour={color_type})")
    stride = width * CHANNELS[color_type]
    raw = zlib.decompress(bytes(compressed))
    if len(raw) != (stride + 1) * height:
        raise ValueError("unexpected PNG data length")
    out = bytearray(stride * height)
    previous = bytearray(stride)
    offset = 0
    for row in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        offset += stride
        if filter_type == 1:
            for i in range(CHANNELS[color_type], stride):
                line[i] = (line[i] + line[i - CHANNELS[color_type]]) & 0xFF
        elif filter_type == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = line[i - CHANNELS[color_type]] if i >= CHANNELS[color_type] else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                left = line[i - CHANNELS[color_type]] if i >= CHANNELS[color_type] else 0
                upper_left = previous[i - CHANNELS[color_type]] if i >= CHANNELS[color_type] else 0
                line[i] = (line[i] + paeth(left, previous[i], upper_left)) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"unsupported PNG filter {filter_type}")
        out[row * stride:(row + 1) * stride] = line
        previous = line
    return width, height, bytes(out)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: screenshot_content.py IMAGE.png", file=sys.stderr)
        return 2
    path = sys.argv[1]
    width, height, pixels = decode(path)
    channels = 3 if len(pixels) == width * height * 3 else 4
    step_x = max(1, width // 320)
    step_y = max(1, height // 180)
    start_y = int(height * 0.15)
    bright = 0
    sampled = 0
    for y in range(start_y, height, step_y):
        row = y * width * channels
        for x in range(0, width, step_x):
            base = row + x * channels
            alpha = 255 if channels == 3 else pixels[base + 3]
            if alpha < 128:
                continue
            sampled += 1
            if max(pixels[base], pixels[base + 1], pixels[base + 2]) >= 140:
                bright += 1
    if sampled == 0 or bright < 12:
        print(f"FAIL {path}: blank content area ({bright} bright samples of {sampled})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
