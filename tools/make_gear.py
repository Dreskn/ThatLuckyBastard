"""Draws Media/gear.tga: the cogwheel that opens the options in the Modern
and Receipt themes. A flat gear, eight teeth and a hole, white on
transparent; the game tints it (white in Modern, ink on Receipt's key).
Classic keeps the game's own gear icon.

Writes  ThatLuckyBastard/Media/gear.tga  (64x64, what the game loads)
and, given a folder as its argument, a preview there: gear-preview.png,
at the sizes the window draws it, on each theme's colours.

    python tools/make_gear.py [preview folder]
"""
import math
import os
import sys

from PIL import Image, ImageDraw

K = 8              # drawn at 8x and scaled down, for clean edges
SIZE = 64          # the texture
C = SIZE / 2       # its middle
TEETH = 8
TIP = 30.5         # radius at the tips of the teeth
BODY = 23.0        # radius of the wheel between them
HOLE = 9.5         # radius of the hole
TIP_HALF = 0.17    # half a tooth's width at its tip, in radians
BASE_HALF = 0.25   # and at its foot


def outline():
    """The gear's edge, as points: each tooth a trapezoid, the wheel's rim
    an arc between them."""
    pts = []
    step = 2 * math.pi / TEETH
    for i in range(TEETH):
        a = i * step - math.pi / 2
        for angle, r in ((a - BASE_HALF, BODY), (a - TIP_HALF, TIP), (a + TIP_HALF, TIP), (a + BASE_HALF, BODY)):
            pts.append((C + r * math.cos(angle), C + r * math.sin(angle)))
        # the rim to the next tooth
        start, end = a + BASE_HALF, a + step - BASE_HALF
        for j in range(1, 8):
            t = start + (end - start) * j / 8
            pts.append((C + BODY * math.cos(t), C + BODY * math.sin(t)))
    return [(x * K, y * K) for x, y in pts]


def gear():
    big = Image.new("L", (SIZE * K, SIZE * K), 0)
    d = ImageDraw.Draw(big)
    d.polygon(outline(), fill=255)
    d.ellipse([(C - HOLE) * K, (C - HOLE) * K, (C + HOLE) * K, (C + HOLE) * K], fill=0)
    alpha = big.resize((SIZE, SIZE), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def preview(sprite, folder):
    # Modern: white on the dark window; Receipt: ink on a pale till key.
    looks = [((24, 24, 26), (255, 255, 255), None), ((38, 33, 30), (42, 38, 34), (232, 225, 208))]
    sizes = (14, 18, 22, 48)
    sheet = Image.new("RGB", (40 + sum(s + 24 for s in sizes), 40 + 2 * 72), (0, 0, 0))
    y = 20
    for bg, ink, key in looks:
        ImageDraw.Draw(sheet).rectangle([0, y - 20, sheet.width, y + 52], fill=bg)
        x = 20
        for s in sizes:
            if key:
                ImageDraw.Draw(sheet).rectangle([x - 3, y - 3, x + s + 3, y + s + 3], fill=key)
            tinted = Image.new("RGBA", (s, s), ink + (0,))
            tinted.putalpha(sprite.resize((s, s), Image.LANCZOS).getchannel("A"))
            sheet.paste(tinted, (x, y), tinted)
            x += s + 24
        y += 72
    sheet = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    sheet.save(os.path.join(folder, "gear-preview.png"))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    sprite = gear()
    tga = os.path.join(root, "ThatLuckyBastard", "Media", "gear.tga")
    # The game wants an uncompressed 32-bit TGA with sides that are powers of two.
    sprite.save(tga)
    with open(tga, "rb") as f:
        header = f.read(18)
    assert header[2] == 2 and header[16] == 32, "not an uncompressed 32-bit TGA"
    print("wrote", os.path.normpath(tga))
    if len(sys.argv) > 1:
        preview(sprite, sys.argv[1])
        print("preview in", sys.argv[1])


if __name__ == "__main__":
    main()
