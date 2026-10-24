#!/usr/bin/env python3
"""Draws the app icon and the in-app logo: a lit Korry pushbutton on the overhead's grey face.

    python3 tools/make_icon.py

Writes A320Overhead/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024 px, opaque, square:
iOS rounds the corners) and Logo.imageset/Logo.png (same art with rounded corners and
transparency, for the sidebar). Needs Pillow.
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "A320Overhead", "Assets.xcassets")
SIZE = 1024
SCALE = 2                      # supersampling
S = SIZE * SCALE
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def px(value):
    return int(value * SCALE)


def vertical_gradient(size, top, bottom):
    image = Image.new("RGB", size, top)
    draw = ImageDraw.Draw(image)
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        draw.line([(0, y), (size[0], y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return image


def screw(draw, cx, cy, r):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(150, 156, 164), outline=(60, 64, 70), width=px(3))
    draw.line([cx - r * 0.6, cy - r * 0.6, cx + r * 0.6, cy + r * 0.6], fill=(70, 74, 80), width=px(5))


def glow_text(base, text, font, centre, colour, blur):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    box = draw.textbbox((0, 0), text, font=font)
    x = centre[0] - (box[2] - box[0]) / 2 - box[0]
    y = centre[1] - (box[3] - box[1]) / 2 - box[1]
    draw.text((x, y), text, font=font, fill=colour + (255,))
    halo = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(halo)
    base.alpha_composite(halo)
    base.alpha_composite(layer)


def draw_icon():
    # Overhead panel face: the Airbus grey-blue, lighter at the top as under the dome light.
    image = vertical_gradient((S, S), (104, 116, 132), (62, 70, 82)).convert("RGBA")
    draw = ImageDraw.Draw(image)

    # Engraved white synoptic line behind the button, as on the panel.
    draw.line([px(120), px(512), px(904), px(512)], fill=(214, 220, 226), width=px(10))
    for cx in (px(120), px(904)):
        draw.ellipse([cx - px(16), px(496), cx + px(16), px(528)], fill=(214, 220, 226))

    for cx, cy in ((px(92), px(92)), (px(932), px(92)), (px(92), px(932)), (px(932), px(932))):
        screw(draw, cx, cy, px(26))

    # Bezel, with a soft shadow under it.
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([px(232), px(252), px(808), px(828)], radius=px(70), fill=(0, 0, 0, 150))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(px(30))))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle([px(222), px(222), px(802), px(802)], radius=px(68), fill=(118, 124, 132))
    draw.rounded_rectangle([px(236), px(236), px(788), px(788)], radius=px(58), fill=(86, 92, 100))

    # Black lens.
    draw.rounded_rectangle([px(268), px(268), px(756), px(756)], radius=px(40), fill=(14, 15, 18))
    draw.rounded_rectangle([px(268), px(268), px(756), px(512)], radius=px(40), fill=(22, 24, 28))
    draw.line([px(300), px(512), px(724), px(512)], fill=(40, 42, 48), width=px(4))

    # Top legend "A320" in backlit white; bottom: the green ON bar of a lit pushbutton.
    font = ImageFont.truetype(FONT, px(128))
    glow_text(image, "A320", font, (px(512), px(398)), (246, 240, 226), px(10))
    bar = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(bar).rounded_rectangle([px(352), px(604), px(672), px(660)], radius=px(14), fill=(64, 232, 104, 255))
    image.alpha_composite(bar.filter(ImageFilter.GaussianBlur(px(22))))
    image.alpha_composite(bar)

    # Glass sheen along the top edge of the lens.
    sheen = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(sheen).rounded_rectangle([px(276), px(276), px(748), px(300)], radius=px(12), fill=(255, 255, 255, 26))
    image.alpha_composite(sheen.filter(ImageFilter.GaussianBlur(px(6))))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def rounded(image, radius):
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, image.size[0] - 1, image.size[1] - 1], radius=radius, fill=255)
    result = image.copy()
    result.putalpha(mask)
    return result


def write(path, image):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, optimize=True)
    print("escrito", os.path.relpath(path))


def main():
    icon = draw_icon()
    write(os.path.join(ROOT, "AppIcon.appiconset", "AppIcon.png"), icon.convert("RGB"))
    logo = rounded(icon, 225).resize((512, 512), Image.LANCZOS)
    write(os.path.join(ROOT, "Logo.imageset", "Logo.png"), logo)


if __name__ == "__main__":
    main()
