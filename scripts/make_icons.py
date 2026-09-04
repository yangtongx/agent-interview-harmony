"""Generate app icons: orange exam-paper mark, no external fonts."""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * stride : (y + 1) * stride])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def paint(size: int) -> bytes:
    paper = (246, 240, 230, 255)
    accent = (226, 74, 22, 255)
    ink = (28, 20, 16, 255)
    muted = (180, 160, 145, 255)
    out = bytearray(size * size * 4)
    pad = int(size * 0.12)
    radius = int(size * 0.18)
    bar_x0 = pad + int(size * 0.08)
    bar_x1 = bar_x0 + max(6, int(size * 0.07))
    line_left = bar_x1 + int(size * 0.08)
    line_right = size - pad - int(size * 0.1)

    def set_px(x: int, y: int, color: tuple[int, int, int, int]) -> None:
        i = (y * size + x) * 4
        out[i : i + 4] = bytes(color)

    def in_round_rect(x: int, y: int, x0: int, y0: int, x1: int, y1: int, r: int) -> bool:
        if x < x0 or x >= x1 or y < y0 or y >= y1:
            return False
        cx = x0 + r if x < x0 + r else (x1 - r - 1 if x >= x1 - r else x)
        cy = y0 + r if y < y0 + r else (y1 - r - 1 if y >= y1 - r else y)
        if x >= x0 + r and x < x1 - r:
            return True
        if y >= y0 + r and y < y1 - r:
            return True
        dx = x - cx
        dy = y - cy
        return dx * dx + dy * dy <= r * r

    for y in range(size):
        for x in range(size):
            if in_round_rect(x, y, pad, pad, size - pad, size - pad, radius):
                set_px(x, y, paper)
            else:
                t = (x + y) / (2 * size)
                set_px(x, y, (lerp(226, 196, t), lerp(74, 48, t), lerp(22, 18, t), 255))

    for y in range(pad + int(size * 0.16), size - pad - int(size * 0.16)):
        for x in range(bar_x0, bar_x1):
            set_px(x, y, accent)

    lines = 5
    top = pad + int(size * 0.22)
    gap = int(size * 0.11)
    for i in range(lines):
        y0 = top + i * gap
        y1 = y0 + max(3, size // 42)
        width_cut = int((line_right - line_left) * (0.35 if i == lines - 1 else 0.0))
        color = ink if i == 0 else muted
        for y in range(y0, min(y1, size)):
            for x in range(line_left, line_right - width_cut):
                set_px(x, y, color)
    return bytes(out)


def main() -> None:
    big = paint(512)
    small = paint(256)
    write_png(ROOT / "AppScope" / "resources" / "base" / "media" / "app_icon.png", 512, 512, big)
    write_png(ROOT / "entry" / "src" / "main" / "resources" / "base" / "media" / "icon.png", 256, 256, small)
    write_png(ROOT / "entry" / "src" / "main" / "resources" / "base" / "media" / "startIcon.png", 256, 256, small)
    print("icons written")


if __name__ == "__main__":
    main()
