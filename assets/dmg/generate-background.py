#!/usr/bin/env python3
"""
Generates a DMG installer background image with a chevron arrow (>)
between the app icon position (left) and Applications folder position (right).

Usage: python3 generate-background.py
Output: dmg-background.png and dmg-background@2x.png
"""

import struct
import zlib
import math
import os

# DMG window dimensions
WIDTH = 660
HEIGHT = 400

# Colors
BG = (238, 238, 238)     # Light background — ensures dark icon label text
ARROW = (80, 80, 88)     # Dark gray chevron


def create_png(width, height, pixels):
    """Create a PNG file from raw pixel data (list of (r, g, b) tuples)."""
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    raw = b''
    for y in range(height):
        raw += b'\x00'
        for x in range(width):
            raw += struct.pack('BBB', *pixels[y * width + x])

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9))
            + chunk(b'IEND', b''))


def draw_thick_line(pixels, w, h, x0, y0, x1, y1, thickness, color):
    """Draw an anti-aliased thick line on the pixel buffer."""
    dx = x1 - x0
    dy = y1 - y0
    length = math.sqrt(dx * dx + dy * dy)
    if length == 0:
        return

    # Normal vector (perpendicular to line direction)
    nx = -dy / length
    ny = dx / length

    # Rasterize: iterate over bounding box and check distance to line
    pad = int(thickness) + 2
    min_x = max(0, int(min(x0, x1)) - pad)
    max_x = min(w - 1, int(max(x0, x1)) + pad)
    min_y = max(0, int(min(y0, y1)) - pad)
    max_y = min(h - 1, int(max(y0, y1)) + pad)

    half_t = thickness / 2.0

    for py in range(min_y, max_y + 1):
        for px in range(min_x, max_x + 1):
            # Vector from line start to this pixel
            vx = px - x0
            vy = py - y0

            # Project onto line direction (parametric t)
            t = (vx * dx + vy * dy) / (length * length)
            if t < -0.02 or t > 1.02:
                continue

            # Distance from pixel to line
            dist = abs(vx * nx + vy * ny)

            if dist <= half_t:
                pixels[py * w + px] = color
            elif dist <= half_t + 1.0:
                # Anti-alias edge
                alpha = 1.0 - (dist - half_t)
                bg = pixels[py * w + px]
                r = int(bg[0] * (1 - alpha) + color[0] * alpha)
                g = int(bg[1] * (1 - alpha) + color[1] * alpha)
                b = int(bg[2] * (1 - alpha) + color[2] * alpha)
                pixels[py * w + px] = (r, g, b)


def draw_background(width, height, scale=1):
    """Generate the DMG background with a chevron arrow."""
    w = width * scale
    h = height * scale
    pixels = [BG] * (w * h)

    # Chevron center — between the two icon positions
    cx = w // 2
    cy = int(h * 0.475)

    # Chevron ">" dimensions
    half_w = int(16 * scale)   # Horizontal extent from center
    half_h = int(24 * scale)   # Vertical extent from center
    thickness = 4.5 * scale    # Line thickness

    # Three points of the chevron: top-left, tip (right), bottom-left
    tip_x = cx + half_w
    tip_y = cy
    top_x = cx - half_w
    top_y = cy - half_h
    bot_x = cx - half_w
    bot_y = cy + half_h

    # Draw the two arms
    draw_thick_line(pixels, w, h, top_x, top_y, tip_x, tip_y, thickness, ARROW)
    draw_thick_line(pixels, w, h, tip_x, tip_y, bot_x, bot_y, thickness, ARROW)

    return create_png(w, h, pixels)


if __name__ == '__main__':
    out_dir = os.path.dirname(os.path.abspath(__file__))

    png_1x = draw_background(WIDTH, HEIGHT, scale=1)
    path_1x = os.path.join(out_dir, 'dmg-background.png')
    with open(path_1x, 'wb') as f:
        f.write(png_1x)
    print(f"Created {path_1x} ({WIDTH}x{HEIGHT})")

    png_2x = draw_background(WIDTH, HEIGHT, scale=2)
    path_2x = os.path.join(out_dir, 'dmg-background@2x.png')
    with open(path_2x, 'wb') as f:
        f.write(png_2x)
    print(f"Created {path_2x} ({WIDTH*2}x{HEIGHT*2})")
