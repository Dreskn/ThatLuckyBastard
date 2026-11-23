"""Draws Media/lock.tga: the meter's padlock, locked on the left half and
open on the right, flat, white on transparent; the game tints it.

Writes  ThatLuckyBastard/Media/lock.tga  (64x32, what the game loads)
and, given a folder as its argument, a preview there: lock-preview.png,
at the sizes the meter draws it, on the Modern and Receipt colours.

    python tools/make_lock.py [preview folder]
"""
import os
import sys

from PIL import Image, ImageDraw

K = 8           # drawn at 8x and scaled down, for clean edges
CELL = 32       # each padlock's square
CX = 16.0       # the middle of a padlock
BODY = (6.5, 15.0, 25.5, 29.0)  # left, top, right, bottom
RING = 6.0      # the shackle's radius, to the middle of its band
BAND = 3.5      # the shackle's thickness
RAISE = 5.0     # how far the open shackle stands up


def padlock(open_):
    big = Image.new("L", (CELL * K, CELL * K), 0)
    d = ImageDraw.Draw(big)

    def box(x0, y0, x1, y1, fill=255, radius=0):
        rect = [x0 * K, y0 * K, x1 * K, y1 * K]
        if radius:
            d.rounded_rectangle(rect, radius=radius * K, fill=fill)
        else:
            d.rectangle(rect, fill=fill)

    # The shackle: a half ring on two legs that go down into the body; the
    # open one stands higher, its right leg out of the body.
    cy = 11.0 - (RAISE if open_ else 0)
    outer, inner = RING + BAND / 2, RING - BAND / 2
    d.pieslice([(CX - outer) * K, (cy - outer) * K, (CX + outer) * K, (cy + outer) * K], 180, 360, fill=255)
    d.pieslice([(CX - inner) * K, (cy - inner) * K, (CX + inner) * K, (cy + inner) * K], 180, 360, fill=0)
    box(CX - outer, cy, CX - inner, BODY[1] + 1)
    box(CX + inner, cy, CX + outer, (cy + 4) if open_ else BODY[1] + 1)
    # The body, with a keyhole.
    box(*BODY, radius=2.5)
    d.ellipse([(CX - 2) * K, 19.5 * K, (CX + 2) * K, 23.5 * K], fill=0)
    box(CX - 0.9, 22, CX + 0.9, 26, fill=0)
    return big.resize((CELL, CELL), Image.LANCZOS)


def sheet():
    out = Image.new("RGBA", (CELL * 2, CELL), (255, 255, 255, 0))
    alpha = Image.new("L", (CELL * 2, CELL), 0)
    alpha.paste(padlock(False), (0, 0))
    alpha.paste(padlock(True), (CELL, 0))
    out.putalpha(alpha)
    return out


def preview(sprite, folder):
    looks = [((24, 24, 26), (255, 255, 255)), ((243, 239, 228), (42, 39, 36))]
    sizes = (12, 14, 32)
    width = 20 + sum(2 * s + 30 for s in sizes)
    img = Image.new("RGB", (width, 2 * 60), (0, 0, 0))
    for row, (bg, ink) in enumerate(looks):
        ImageDraw.Draw(img).rectangle([0, row * 60, width, row * 60 + 60], fill=bg)
        x = 20
        for s in sizes:
            for half in (0, 1):
                cell = sprite.crop((half * CELL, 0, half * CELL + CELL, CELL)).resize((s, s), Image.LANCZOS)
                tinted = Image.new("RGBA", (s, s), ink + (0,))
                tinted.putalpha(cell.getchannel("A"))
                img.paste(tinted, (x, row * 60 + 14), tinted)
                x += s + 10
            x += 10
    img = img.resize((img.width * 3, img.height * 3), Image.NEAREST)
    img.save(os.path.join(folder, "lock-preview.png"))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    sprite = sheet()
    tga = os.path.join(root, "ThatLuckyBastard", "Media", "lock.tga")
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
