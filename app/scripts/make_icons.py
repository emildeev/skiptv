#!/usr/bin/env python3
"""Generates the tvOS app icon (layered) and top shelf images.

Pure standard library, so it runs anywhere:  python3 scripts/make_icons.py
Output: SkipTV/Assets.xcassets/App Icon & Top Shelf Image.brandassets
"""
import json
import os
import struct
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SkipTV", "Assets.xcassets")
BRAND = os.path.join(ROOT, "App Icon & Top Shelf Image.brandassets")
INFO = {"author": "xcode", "version": 1}

INK_TOP = (24, 30, 48)
INK_BOTTOM = (6, 8, 14)
AMBER = (255, 181, 71)


def write_png(path, width, height, rows):
    """rows: list of bytes objects, RGBA, width*4 each."""
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def background_rows(width, height):
    rows = []
    for y in range(height):
        t = y / max(1, height - 1)
        r, g, b = (int(INK_TOP[i] + (INK_BOTTOM[i] - INK_TOP[i]) * t) for i in range(3))
        rows.append(bytes((r, g, b, 255)) * width)
    return rows


def glyph_spans(width, height, scale, cx, cy):
    """'Skip forward' glyph: two triangles and a bar. Returns per-row coverage spans."""
    h = height * scale
    w = h * 1.15
    left = cx - w / 2
    tri_w = w * 0.40
    shapes = []
    for i in range(2):
        x0 = left + i * tri_w
        shapes.append(("tri", x0, cy - h / 2, x0 + tri_w, cy, x0, cy + h / 2))
    bar_x = left + 2 * tri_w + w * 0.04
    shapes.append(("rect", bar_x, cy - h / 2, bar_x + w * 0.14, cy + h / 2))
    return shapes


def coverage_row(shapes, y, width):
    """Horizontal coverage (0..1) per pixel for row y, antialiased horizontally and vertically."""
    cov = [0.0] * width
    samples = (0.25, 0.75)
    for sy in samples:
        yy = y + sy
        for s in shapes:
            if s[0] == "tri":
                _, x0, y0, xt, yt, x1, y1 = s
                if yy < y0 or yy > y1:
                    continue
                # Left edge vertical at x0, right edge goes through tip (xt, yt).
                frac = 1 - abs(yy - yt) / (y1 - yt)
                xa, xb = x0, x0 + (xt - x0) * frac
            else:
                _, xa, ya, xb, yb = s
                if yy < ya or yy > yb:
                    continue
            ia, ib = max(0, int(xa)), min(width - 1, int(xb))
            for x in range(ia, ib + 1):
                lo, hi = max(xa, x), min(xb, x + 1)
                if hi > lo:
                    cov[x] = min(1.0, cov[x] + (hi - lo) / len(samples))
    return cov


def glyph_rows(width, height, scale, cx, cy, opaque_background=None):
    shapes = glyph_spans(width, height, scale, cx, cy)
    bg = background_rows(width, height) if opaque_background else None
    rows = []
    for y in range(height):
        cov = coverage_row(shapes, y, width)
        out = bytearray(width * 4)
        for x in range(width):
            a = cov[x]
            if bg:
                br, bgc, bb = bg[y][x * 4], bg[y][x * 4 + 1], bg[y][x * 4 + 2]
                out[x * 4:x * 4 + 4] = bytes((
                    int(br + (AMBER[0] - br) * a),
                    int(bgc + (AMBER[1] - bgc) * a),
                    int(bb + (AMBER[2] - bb) * a),
                    255,
                ))
            else:
                out[x * 4:x * 4 + 4] = bytes((AMBER[0], AMBER[1], AMBER[2], int(255 * a)))
        rows.append(bytes(out))
    return rows


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def imagestack(name, sizes):
    """sizes: list of (scale, width, height)."""
    stack = os.path.join(BRAND, name + ".imagestack")
    write_json(os.path.join(stack, "Contents.json"), {
        "info": INFO,
        "layers": [{"filename": "Front.imagestacklayer"}, {"filename": "Back.imagestacklayer"}],
    })
    for layer in ("Front", "Back"):
        layer_dir = os.path.join(stack, layer + ".imagestacklayer")
        write_json(os.path.join(layer_dir, "Contents.json"), {"info": INFO})
        images = []
        for scale, w, h in sizes:
            filename = f"{layer.lower()}-{w}x{h}.png"
            rows = background_rows(w, h) if layer == "Back" else glyph_rows(w, h, 0.42, w / 2, h / 2)
            write_png(os.path.join(layer_dir, "Content.imageset", filename), w, h, rows)
            images.append({"idiom": "tv", "scale": scale, "filename": filename})
        write_json(os.path.join(layer_dir, "Content.imageset", "Contents.json"), {"images": images, "info": INFO})


def imageset(name, sizes):
    directory = os.path.join(BRAND, name + ".imageset")
    images = []
    for scale, w, h in sizes:
        filename = f"{name.lower().replace(' ', '-')}-{w}x{h}.png"
        rows = glyph_rows(w, h, 0.22, w * 0.5, h / 2, opaque_background=True)
        write_png(os.path.join(directory, filename), w, h, rows)
        images.append({"idiom": "tv", "scale": scale, "filename": filename})
    write_json(os.path.join(directory, "Contents.json"), {"images": images, "info": INFO})


def main():
    write_json(os.path.join(ROOT, "Contents.json"), {"info": INFO})
    write_json(os.path.join(BRAND, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": INFO,
    })
    imagestack("App Icon", [("1x", 400, 240), ("2x", 800, 480)])
    imagestack("App Icon - App Store", [("1x", 1280, 768)])
    imageset("Top Shelf Image", [("1x", 1920, 720), ("2x", 3840, 1440)])
    imageset("Top Shelf Image Wide", [("1x", 2320, 720), ("2x", 4640, 1440)])


if __name__ == "__main__":
    main()
