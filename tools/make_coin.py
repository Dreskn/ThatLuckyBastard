"""Draws the coin the end-of-run race piles up: our own drawing, seen a
little from above, with a reeded rim and a star struck on its face.

Writes  ThatLuckyBastard/Media/coin.tga  (64x32, what the game loads)
and, given a folder as its argument, a preview there: coin-preview.png,
stacks and an overflowing pile as the race leaves them.

    python tools/make_coin.py [preview folder]
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

K = 8                 # drawn at 8x and scaled down, for clean edges
W, H = 64, 32         # the texture
CX, CY = 32.0, 11.5   # the middle of the face
RX, RY = 30.0, 10.5   # the face's half width and half height
THICK = 6.0           # the rim, from the face down

HIGHLIGHT = (255, 243, 176)
GOLD = (243, 196, 79)
DEEP = (196, 134, 24)
RIM_DARK = (132, 84, 10)
RIM_LIGHT = (231, 172, 52)
STAR_SHADE = (150, 94, 8)
LINE = (88, 56, 6)


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def ellipse_box(cx, cy, rx, ry):
    return [(cx - rx) * K, (cy - ry) * K, (cx + rx) * K, (cy + ry) * K]


def mask(draw_fn):
    m = Image.new("L", (W * K, H * K), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def coin():
    S = (W * K, H * K)
    out = Image.new("RGBA", S, (0, 0, 0, 0))

    # The whole silhouette: the face, the rim under it, and what joins them.
    def silhouette(d, grow=0.0):
        d.ellipse(ellipse_box(CX, CY, RX + grow, RY + grow), fill=255)
        d.ellipse(ellipse_box(CX, CY + THICK, RX + grow, RY + grow), fill=255)
        d.rectangle([(CX - RX - grow) * K, CY * K, (CX + RX + grow) * K, (CY + THICK) * K], fill=255)
    outline = mask(lambda d: silhouette(d, 0.6))
    out.paste(Image.new("RGBA", S, LINE + (255,)), (0, 0), outline)

    # The rim: darker at the sides, where it turns away, with its reeding
    # closer together there for the same reason.
    rim = Image.new("RGBA", S, (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    for x in range(int((CX - RX) * K), int((CX + RX) * K) + 1):
        u = (x / K - CX) / RX
        rd.line([(x, 0), (x, S[1])], fill=lerp(RIM_DARK, RIM_LIGHT, (1 - abs(u)) ** 0.6) + (255,))
    for i in range(1, 48):
        theta = math.pi * i / 48
        x = (CX - RX * math.cos(theta)) * K
        rd.line([(x, 0), (x, S[1])], fill=RIM_DARK + (150,), width=max(1, int(K * 0.6 * math.sin(theta))))
    rim_mask = mask(lambda d: silhouette(d))
    out.paste(rim, (0, 0), rim_mask)

    # The face: light from the top left, deeper towards the edge.
    face = Image.new("RGBA", S, (0, 0, 0, 0))
    px = face.load()
    for y in range(int((CY - RY) * K), int((CY + RY) * K) + 1):
        for x in range(int((CX - RX) * K), int((CX + RX) * K) + 1):
            u, v = (x / K - CX) / RX, (y / K - CY) / RY
            r = math.hypot(u, v)
            if r > 1:
                continue
            light = math.hypot(u + 0.4, v + 0.55) / 1.6
            col = lerp(HIGHLIGHT, GOLD, light ** 0.8)
            if r > 0.78:
                col = lerp(col, DEEP, (r - 0.78) / 0.22 * 0.9)
            px[x, y] = col + (255,)
    face_mask = mask(lambda d: d.ellipse(ellipse_box(CX, CY, RX, RY), fill=255))
    out.paste(face, (0, 0), face_mask)

    d = ImageDraw.Draw(out)
    # A raised border: a groove inside it, and its edge catching the light.
    d.ellipse(ellipse_box(CX, CY, RX * 0.80, RY * 0.80), outline=DEEP + (210,), width=int(K * 0.9))
    d.arc(ellipse_box(CX, CY, RX * 0.88, RY * 0.88), 160, 300, fill=HIGHLIGHT + (200,), width=int(K * 0.7))
    # The front edge of the face, where it meets the rim, catches the light too.
    d.arc(ellipse_box(CX, CY, RX - 0.3, RY - 0.3), 15, 165, fill=(255, 226, 138, 230), width=int(K * 0.6))

    # A five-pointed star struck in the middle, raised: its shadow below
    # and to the right, its face lit.
    def star(dx, dy):
        points = []
        for i in range(10):
            a = -math.pi / 2 + i * math.pi / 5
            r = 1.0 if i % 2 == 0 else 0.42
            points.append(((CX + dx + r * RX * 0.40 * math.cos(a)) * K, (CY + dy + r * RY * 0.62 * math.sin(a)) * K))
        return points
    d.polygon(star(0.5, 0.45), fill=STAR_SHADE + (255,))
    d.polygon(star(0, 0), fill=(255, 210, 84, 255))
    d.polygon(star(-0.15, -0.12), fill=(255, 236, 150, 110))

    # A soft sheen on the upper left of the face.
    sheen = Image.new("L", S, 0)
    ImageDraw.Draw(sheen).ellipse(ellipse_box(CX - RX * 0.42, CY - RY * 0.48, RX * 0.32, RY * 0.30), fill=120)
    sheen = sheen.filter(ImageFilter.GaussianBlur(K * 2.2))
    sheen = ImageChops.multiply(sheen, face_mask)
    out.paste(Image.new("RGBA", S, (255, 255, 255, 255)), (0, 0), sheen)

    # Edges as clean as the outline, at the size the game shows it.
    alpha = out.split()[3]
    out.putalpha(ImageChops.multiply(alpha, outline))
    return out.resize((W, H), Image.LANCZOS)


def preview(sprite, folder):
    """Stacks of 20, 14, 9 and 4 coins, and a winner's overflowing pile, as
    the race leaves them, twice the size the game shows them."""
    scale, step, coin_w, coin_h = 2, 5, 30, 15
    big = sprite.resize((coin_w * scale, coin_h * scale), Image.LANCZOS)
    cols, col_w, floor = 5, 142, 240
    sheet = Image.new("RGBA", (cols * col_w * scale, 300 * scale), (20, 23, 28, 255))
    rnd = random.Random(7)

    def put(x, y):  # x, y: the coin's middle, in game pixels
        sheet.alpha_composite(big, (int((x - coin_w / 2) * scale), int((y - coin_h / 2) * scale)))
    for col, n in enumerate((14, 20, 9, 4, 1)):
        cx = col * col_w + col_w / 2
        for k in range(n):
            put(cx + rnd.uniform(-1.5, 1.5), floor - coin_h / 2 - k * step)
    # The winner, in the middle: their stack full, the rest pours down its
    # sides into a heap, the coins lying anyhow (flatter or rounder: tilted).
    cx = 1 * col_w + col_w / 2
    heights = {s: 0 for s in range(-5, 6)}
    heights[0] = 20
    for j in range(36):
        s, side = 0, -1 if j % 2 else 1
        while True:
            for nxt in (s + side, s - side):
                if nxt in heights and heights[nxt] <= heights[s] - 2:
                    s = nxt
                    break
            else:
                break
        squash = rnd.uniform(0.65, 1.0)
        tilted = sprite.resize((coin_w * scale, max(2, int(coin_h * scale * squash))), Image.LANCZOS)
        x, y = cx + s * 10 + rnd.uniform(-3.5, 3.5), floor - coin_h * squash / 2 - heights[s] * 4.5 + rnd.uniform(-1.5, 1.5)
        sheet.alpha_composite(tilted, (int((x - coin_w / 2) * scale), int((y - coin_h * squash / 2) * scale)))
        heights[s] += 1
    sheet.save(os.path.join(folder, "coin-preview.png"))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    sprite = coin()
    tga = os.path.join(root, "ThatLuckyBastard", "Media", "coin.tga")
    # The game wants an uncompressed 32-bit TGA with sides that are powers of two.
    sprite.save(tga)
    with open(tga, "rb") as f:
        header = f.read(18)
    assert header[2] == 2 and header[16] == 32, "not an uncompressed 32-bit TGA"
    print("wrote", tga)
    if len(sys.argv) > 1:
        preview(sprite, sys.argv[1])
        print("wrote", os.path.join(sys.argv[1], "coin-preview.png"))


if __name__ == "__main__":
    main()
