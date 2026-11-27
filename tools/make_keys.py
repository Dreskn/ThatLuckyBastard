"""Draws Media/keys.tga: the farm strip's keys, flat, white on transparent;
the game tints them. Four squares side by side: start (a triangle),
pause (two bars), stop (a square) and close (a cross).

Writes  ThatLuckyBastard/Media/keys.tga  (128x32, what the game loads)
and, given a folder as its argument, a preview there: keys-preview.png,
at the size the strip draws them, on the Modern and Receipt colours.

    python tools/make_keys.py [preview folder]
"""
import os
import sys

from PIL import Image, ImageDraw

K = 8      # drawn at 8x and scaled down, for clean edges
CELL = 32  # each key's square
NAMES = ("start", "pause", "stop", "close")


def glyph(name):
    big = Image.new("L", (CELL * K, CELL * K), 0)
    d = ImageDraw.Draw(big)

    def pts(*xy):
        return [(x * K, y * K) for x, y in xy]

    if name == "start":
        d.polygon(pts((10, 7), (25, 16), (10, 25)), fill=255)
    elif name == "pause":
        d.rounded_rectangle([9 * K, 7 * K, 14 * K, 25 * K], radius=1 * K, fill=255)
        d.rounded_rectangle([18 * K, 7 * K, 23 * K, 25 * K], radius=1 * K, fill=255)
    elif name == "stop":
        d.rounded_rectangle([8 * K, 8 * K, 24 * K, 24 * K], radius=1.5 * K, fill=255)
    elif name == "close":
        d.line(pts((9, 9), (23, 23)), fill=255, width=int(3.5 * K))
        d.line(pts((23, 9), (9, 23)), fill=255, width=int(3.5 * K))
    return big.resize((CELL, CELL), Image.LANCZOS)


def sheet():
    out = Image.new("RGBA", (CELL * len(NAMES), CELL), (255, 255, 255, 0))
    alpha = Image.new("L", (CELL * len(NAMES), CELL), 0)
    for i, name in enumerate(NAMES):
        alpha.paste(glyph(name), (i * CELL, 0))
    out.putalpha(alpha)
    return out


def preview(sprite, folder):
    looks = [((24, 24, 26), (255, 255, 255)), ((243, 239, 228), (42, 39, 36))]
    s = 12
    width = 20 + len(NAMES) * (s + 14)
    img = Image.new("RGB", (width, 2 * 40), (0, 0, 0))
    for row, (bg, ink) in enumerate(looks):
        ImageDraw.Draw(img).rectangle([0, row * 40, width, row * 40 + 40], fill=bg)
        x = 20
        for i in range(len(NAMES)):
            cell = sprite.crop((i * CELL, 0, i * CELL + CELL, CELL)).resize((s, s), Image.LANCZOS)
            tinted = Image.new("RGBA", (s, s), ink + (0,))
            tinted.putalpha(cell.getchannel("A"))
            img.paste(tinted, (x, row * 40 + 14), tinted)
            x += s + 14
    img = img.resize((img.width * 4, img.height * 4), Image.NEAREST)
    img.save(os.path.join(folder, "keys-preview.png"))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    sprite = sheet()
    tga = os.path.join(root, "ThatLuckyBastard", "Media", "keys.tga")
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
