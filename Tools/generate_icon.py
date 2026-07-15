#!/usr/bin/env python3
"""Quiet Keys app icon generator.

Follows the Quiet Apps icon rules: true n=5 superellipse on a 1024x1024
canvas with a 9% transparent safe-area ring, quiet-blue -> darker-blue
vertical gradient body (the only sanctioned gradient), white mark.

Mark: a keycap grid with one pressed (lit) key — "one key, heard".
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

CANVAS = 1024
SS = 4  # supersample factor
BLUE = (30, 136, 229)      # #1E88E5
BLUE_DARK = (21, 101, 192)  # #1565C0


def superellipse_mask(size, n=5.0):
    """True n=5 superellipse alpha mask."""
    y, x = np.mgrid[0:size, 0:size]
    cx = cy = (size - 1) / 2
    r = size / 2
    v = (np.abs((x - cx) / r) ** n + np.abs((y - cy) / r) ** n)
    return (v <= 1.0).astype(np.uint8) * 255


def rounded_rect(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def build():
    body = int(CANVAS * 0.82)  # 9% ring each side
    s = body * SS

    # gradient body clipped to superellipse
    grad = np.zeros((s, s, 4), dtype=np.uint8)
    t = np.linspace(0, 1, s)[:, None]
    for c in range(3):
        grad[..., c] = ((1 - t) * BLUE[c] + t * BLUE_DARK[c]).astype(np.uint8)
    grad[..., 3] = superellipse_mask(s)
    icon = Image.fromarray(grad, "RGBA")

    # keycap mark: 3 x 2 grid of keys, center-top key "pressed" (solid white)
    draw = ImageDraw.Draw(icon)
    key = int(s * 0.16)
    gap = int(s * 0.045)
    grid_w = 3 * key + 2 * gap
    grid_h = 2 * key + gap
    ox = (s - grid_w) // 2
    oy = (s - grid_h) // 2
    radius = int(key * 0.24)
    stroke = max(2, int(s * 0.016))

    for row in range(2):
        for col in range(3):
            x0 = ox + col * (key + gap)
            y0 = oy + row * (key + gap)
            box = [x0, y0, x0 + key, y0 + key]
            if row == 0 and col == 1:
                draw.rounded_rectangle(box, radius=radius,
                                       fill=(255, 255, 255, 255))
            else:
                draw.rounded_rectangle(box, radius=radius,
                                       outline=(255, 255, 255, 235),
                                       width=stroke)

    icon = icon.resize((body, body), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(icon, ((CANVAS - body) // 2, (CANVAS - body) // 2), icon)
    return canvas


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else \
        "QuietKeys/Resources/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(out_dir, exist_ok=True)
    master = build()
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for px in sizes:
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(out_dir, f"icon_{px}.png"))
    print(f"Icons written to {out_dir}")


if __name__ == "__main__":
    main()
