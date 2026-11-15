"""Draws the mark of That Lucky Bastard: a gold die showing five, with one lucky pip.

Five pips for the five players of a dungeon group; the one in the middle,
in the addon's accent colour, is the one who got lucky.

Writes  ThatLuckyBastard/Media/logo.tga  (64x64, what the game loads)
        media/logo.png            (512x512, for the README and listings)
        media/logo-sizes.png      (the mark at the sizes the game shows it)
        media/social-preview.png  (1280x640: the mark, the name and a line
                                   about it, for the repository's social
                                   preview, which the WowUp Hub uses as icon)

    python tools/make_logo.py

Needs Pillow. The teal is the addon's accent colour; change it here and in
ThatLuckyBastard/Core.lua (ns.ACCENT, ns.ACCENT_HEX) together.
"""
import os

from PIL import Image, ImageDraw, ImageFont

GOLD, RIM, LIGHT, SHADE = (255, 209, 0), (170, 118, 0), (255, 236, 140), (120, 80, 0)
TEAL, TEAL_DARK = (64, 199, 184), (20, 120, 110)
INK = (60, 40, 0)

TILT = 13       # degrees, counter-clockwise
MARGIN = 0.155  # around the die before it is tilted, as a fraction of the image
K = 8           # drawn at 8x and scaled down, for clean edges at small sizes


def draw(size):
    S = size * K
    die = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(die)

    def dot(x, y, r, fill):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    a, corner = S * MARGIN, S * 0.14
    d.rounded_rectangle([a, a + S * 0.022, S - a, S - a + S * 0.022], corner, fill=SHADE)  # a hint of thickness
    d.rounded_rectangle([a, a, S - a, S - a], corner, fill=RIM)
    b = a + S * 0.038
    d.rounded_rectangle([b, b, S - b, S - b], corner * 0.78, fill=GOLD)
    # a highlight along the top-left corner
    d.arc([b + S * 0.025, b + S * 0.025, b + S * 0.25, b + S * 0.25], 180, 270, fill=LIGHT, width=int(S * 0.032))

    off, r = S * 0.175, S * 0.066
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        dot(S / 2 + dx * off, S / 2 + dy * off, r, INK)
    dot(S / 2, S / 2, r * 1.38, TEAL_DARK)
    dot(S / 2, S / 2, r * 1.08, TEAL)

    die = die.rotate(TILT, resample=Image.BICUBIC)
    return die.resize((size, size), Image.LANCZOS)


PANEL = (19, 22, 27)  # the dark background of the Modern theme


def font(size, bold=False):
    """A plain sans-serif at `size`: Segoe UI or Arial where they exist."""
    for name in (("segoeuib.ttf", "arialbd.ttf") if bold else ("segoeui.ttf", "arial.ttf")):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def social():
    """The mark, the name in its two tones, and what the addon is.

    Everything sits in the middle 640 pixels, so that a site which crops
    the image to a square for an icon still shows all of it."""
    W, H = 1280, 640
    img = Image.new("RGBA", (W, H), PANEL + (255,))
    d = ImageDraw.Draw(img)
    d.rectangle([0, H - 10, W, H], fill=TEAL)

    mark = 300
    img.alpha_composite(draw(mark), ((W - mark) // 2, 40))

    # The name, as large as the middle 640 pixels allow, "Lucky" in the accent.
    words = (("That ", (255, 255, 255)), ("Lucky", TEAL), (" Bastard", (255, 255, 255)))
    size = 104
    while True:
        name = font(size, bold=True)
        widths = [d.textlength(word, font=name) for word, _ in words]
        if sum(widths) <= 600 or size <= 20:
            break
        size -= 2
    x = (W - sum(widths)) / 2
    for (word, fill), width in zip(words, widths):
        d.text((x, 362), word, font=name, fill=fill)
        x += width

    for text, size, y, fill in (("Who got what, and who got lucky", 38, 468, (200, 204, 210)),
                                ("A loot addon for WoW Forever", 28, 530, (140, 146, 154))):
        f = font(size)
        d.text(((W - d.textlength(text, font=f)) / 2, y), text, font=f, fill=fill)
    return img


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    game = os.path.join(root, "ThatLuckyBastard", "Media")
    docs = os.path.join(root, "media")
    os.makedirs(game, exist_ok=True)
    os.makedirs(docs, exist_ok=True)

    # The game wants an uncompressed 32-bit TGA with sides that are powers of two.
    tga = os.path.join(game, "logo.tga")
    draw(64).save(tga)
    with open(tga, "rb") as f:
        header = f.read(18)
    assert header[2] == 2 and header[16] == 32, "not an uncompressed 32-bit TGA"
    assert header[12] | header[13] << 8 == 64 and header[14] | header[15] << 8 == 64

    draw(512).save(os.path.join(docs, "logo.png"))
    social().save(os.path.join(docs, "social-preview.png"))

    # What it looks like at the sizes the game shows it, on a dark panel.
    sheet = Image.new("RGBA", (420, 150), (19, 22, 27, 255))
    x = 16
    small = draw(64)
    for shown in (128, 64, 32, 19, 16):
        mark = draw(shown) if shown >= 64 else small.resize((shown, shown), Image.LANCZOS)
        sheet.alpha_composite(mark, (x, (150 - shown) // 2))
        x += shown + 22
    sheet.save(os.path.join(docs, "logo-sizes.png"))
    print("wrote", tga, "and", docs)


if __name__ == "__main__":
    main()
