#!/usr/bin/env python3
"""Renders the Festr app icon (opaque 1024x1024 RGB): a soft gradient with a minimal set-times timeline."""
import pathlib
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Festr" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 1024


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(top, bottom, glow, bar, accent, path):
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            t = min(1, max(0, (0.65 * y + 0.35 * x) / SIZE))
            pixels[x, y] = lerp(top, bottom, t)
    halo = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    ImageDraw.Draw(halo).ellipse((420, -160, 1240, 660), fill=glow)
    halo = halo.filter(ImageFilter.GaussianBlur(170))
    image = Image.blend(image, Image.composite(halo, image, halo.convert("L")), 0.55)

    draw = ImageDraw.Draw(image)
    rail_x = 209
    rows = [(330, 560, bar), (512, 470, accent), (694, 380, bar)]
    draw.rounded_rectangle((rail_x - 9, 300, rail_x + 9, 724), radius=9, fill=lerp(bar, bottom, 0.55))
    for y, length, colour in rows:
        draw.ellipse((rail_x - 34, y - 34, rail_x + 34, y + 34), fill=colour)
        draw.rounded_rectangle((rail_x + 80, y - 44, rail_x + 80 + length, y + 44), radius=44, fill=colour)
    image.save(path, "PNG")
    print(f"Wrote {path.relative_to(ROOT)}")


render((255, 122, 112), (92, 38, 168), (255, 214, 170), (255, 250, 246), (255, 214, 120), OUT / "AppIcon.png")
render((40, 22, 66), (8, 8, 18), (180, 70, 160), (236, 230, 255), (255, 120, 132), OUT / "AppIcon-Dark.png")
