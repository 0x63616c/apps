#!/usr/bin/env python3
"""Renders the Festr icon: a white monoline lowercase f on a near-black tile, matching Tendr and Shotr.
Monochrome only. Run from anywhere: python3 apps/festr/scripts/render-icon.py
Writes the AppIcon set (any, dark, tinted; opaque 1024 RGB) and the site icons."""
import pathlib
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = ROOT.parent.parent
ICONSET = ROOT / "Festr" / "Assets.xcassets" / "AppIcon.appiconset"
SITE = REPO / "site" / "festr" / "assets"
SIZE, SS = 1024, 4
STROKE = 46  # same stroke as Tendr's mark
STEM_X, TOP, BOTTOM = 470, 330, 694
HOOK_R = 92  # radius of the top hook
BAR_Y, BAR_L, BAR_R = 450, 370, 600


def render(tile, glyph, pixels):
    s = SS
    img = Image.new("RGB", (SIZE * s, SIZE * s), tile)
    d = ImageDraw.Draw(img)
    w = STROKE * s
    r = w / 2

    def cap(x, y):
        d.ellipse(((x - STROKE / 2) * s, (y - STROKE / 2) * s, (x + STROKE / 2) * s, (y + STROKE / 2) * s), fill=glyph)

    def line(x1, y1, x2, y2):
        d.line((x1 * s, y1 * s, x2 * s, y2 * s), fill=glyph, width=w)
        cap(x1, y1); cap(x2, y2)

    # stem from bottom up to where the hook starts
    cy = TOP + HOOK_R
    line(STEM_X, BOTTOM, STEM_X, cy)
    # hook: quarter-ish arc from the stem curving right
    cx = STEM_X + HOOK_R
    box = ((cx - HOOK_R - STROKE / 2) * s, (cy - HOOK_R - STROKE / 2) * s,
           (cx + HOOK_R + STROKE / 2) * s, (cy + HOOK_R + STROKE / 2) * s)
    d.arc(box, 180, 300, fill=glyph, width=w)
    import math
    a = math.radians(300)
    cap(cx + HOOK_R * math.cos(a), cy + HOOK_R * math.sin(a))
    line(BAR_L, BAR_Y, BAR_R, BAR_Y)
    return img.resize((pixels, pixels), Image.LANCZOS)


DARK = ((14, 14, 14), (242, 242, 242))
TINTED = ((0, 0, 0), (255, 255, 255))
outputs = [
    (DARK, 1024, ICONSET / "AppIcon.png"),
    (DARK, 1024, ICONSET / "AppIcon-Dark.png"),
    (TINTED, 1024, ICONSET / "AppIcon-Tinted.png"),
    (DARK, 256, SITE / "icon-256.png"),
    (DARK, 180, SITE / "apple-touch-icon.png"),
    (DARK, 64, SITE / "favicon-64.png"),
]
for (tile, glyph), px, path in outputs:
    render(tile, glyph, px).save(path, "PNG")
    print(f"Wrote {path.relative_to(REPO)}")
