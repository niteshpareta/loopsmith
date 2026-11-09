#!/usr/bin/env python3
"""Draws the app icon (two hooked rings on the bench) at every size the
Android, iOS and web projects need.

    pip install pillow
    python3 tool/make_icons.py
"""
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
BENCH = (24, 18, 31)
GLOW = (52, 38, 72)
BRASS = (224, 173, 74)
TEAL = (53, 191, 174)
SS = 2  # supersampling


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def tint(c, t):
    return tuple(int(v + (255 - v) * t) for v in c)


def background(size):
    img = Image.new("RGB", (size, size), BENCH)
    px = img.load()
    cx, cy, radius = size * 0.5, size * 0.42, size * 0.75
    for y in range(size):
        for x in range(size):
            t = min(1.0, math.hypot(x - cx, y - cy) / radius)
            t = t * t * (3 - 2 * t)
            px[x, y] = tuple(int(GLOW[i] + (BENCH[i] - GLOW[i]) * t) for i in range(3))
    return img


def ring(draw, cx, cy, r, w, color, start, end, caps, shine=(190, 300)):
    """One tube: dark edge, body, lit core and a highlight, like the game."""
    def arc(radius_shift, width, fill, dx=0, dy=0, a=start, b=end):
        rr = r + radius_shift
        box = [cx - rr + dx, cy - rr + dy, cx + rr + dx, cy + rr + dy]
        draw.arc(box, a, b, fill=fill, width=int(width))

    def cap(angle, width, fill, dx=0, dy=0):
        a = math.radians(angle)
        x, y = cx + r * math.cos(a) + dx, cy + r * math.sin(a) + dy
        draw.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=fill)

    edge = w * 0.2
    lift = (-w * 0.1, -w * 0.13)
    layers = [
        (w + edge, shade(color, 0.22), 0, 0),
        (w, shade(color, 0.72), 0, 0),
        (w * 0.58, tint(color, 0.08), lift[0], lift[1]),
    ]
    for width, fill, dx, dy in layers:
        arc(width / 2, width, fill, dx, dy)
        if caps:
            cap(start, width, fill, dx, dy)
            cap(end, width, fill, dx, dy)
    # Highlight on the side facing the light (upper left).
    if shine is not None:
        arc(w * 0.09, w * 0.17, tint(color, 0.55), lift[0] * 2.2, lift[1] * 2.2, shine[0], shine[1])


def emblem(size, scale=1.0):
    """Transparent layer with the two rings, centred."""
    s = size * SS
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = s * 0.215 * scale
    w = s * 0.074 * scale
    gap = r * 0.98
    cy = s * 0.5
    ax, bx = s * 0.5 - gap / 2, s * 0.5 + gap / 2
    # Soft shadow under the rings.
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([s * 0.5 - r * 1.9, cy + r * 1.05, s * 0.5 + r * 1.9, cy + r * 1.5], fill=(5, 3, 8, 150))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(s * 0.03)))
    d = ImageDraw.Draw(layer)
    ring(d, ax, cy, r, w, BRASS, 152, 478, caps=True)   # opening at lower left
    ring(d, bx, cy, r, w, TEAL, 0, 360, caps=False)
    # Brass passes over teal at the upper crossing, so the rings read as hooked.
    cross = math.degrees(math.atan2(-math.sqrt(max(0, r * r - (gap / 2) ** 2)), gap / 2)) % 360
    ring(d, ax, cy, r, w, BRASS, cross - 36, cross + 36, caps=False, shine=(cross - 36, 300))
    return layer.resize((size, size), Image.LANCZOS)


def full_icon(size, scale=1.0):
    img = background(size).convert("RGBA")
    img.alpha_composite(emblem(size, scale))
    return img


def rounded(img, radius_ratio):
    size = img.size[0]
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * radius_ratio), fill=255)
    out = img.copy()
    out.putalpha(ImageChops.multiply(img.getchannel("A"), mask.resize((size, size), Image.LANCZOS)))
    return out


def save(img, path, size, alpha=True):
    out = img.resize((size, size), Image.LANCZOS)
    if not alpha:
        out = out.convert("RGB")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)


if __name__ == "__main__":
    master = full_icon(1024)
    legacy = rounded(master, 0.22)
    foreground = emblem(1024, scale=0.62)      # inside Android's adaptive safe zone
    maskable = full_icon(1024, scale=0.78)     # inside the web maskable safe zone

    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    for name, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(legacy, os.path.join(res, f"mipmap-{name}", "ic_launcher.png"), px)
        save(foreground, os.path.join(res, f"mipmap-{name}", "ic_launcher_foreground.png"), int(px * 2.25))

    ios = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for entry in json.load(open(os.path.join(ios, "Contents.json")))["images"]:
        points = float(entry["size"].split("x")[0])
        px = int(round(points * int(entry["scale"][0])))
        save(master, os.path.join(ios, entry["filename"]), px, alpha=False)

    web = os.path.join(ROOT, "web")
    save(master, os.path.join(web, "icons", "Icon-192.png"), 192)
    save(master, os.path.join(web, "icons", "Icon-512.png"), 512)
    save(maskable, os.path.join(web, "icons", "Icon-maskable-192.png"), 192)
    save(maskable, os.path.join(web, "icons", "Icon-maskable-512.png"), 512)
    save(legacy, os.path.join(web, "favicon.png"), 48)
    save(master, os.path.join(ROOT, "assets", "icon.png"), 1024, alpha=False)
    print("icons written")
