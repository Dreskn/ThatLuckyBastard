"""Draws Media/receipt-edge.tga: the torn bottom edge of a receipt in the
Receipt theme. One tooth, 16 x 8 pixels, white on transparent, pointing
down; the game tiles it along the bottom of each receipt and tints it the
colour of the paper. Needs nothing beyond Python.

    python tools/make_receipt_edge.py
"""
import os
import struct

W, H = 16, 8
SAMPLES = 4  # per pixel side, to smooth the slopes


def covered(x, y):
    # The tooth is full width at the top and comes to a point at the
    # bottom, in the middle.
    half = (W / 2) * (1 - y / H)
    return abs(x - W / 2) <= half


pixels = bytearray()
for row in range(H):  # top row first (the header says so)
    for col in range(W):
        hits = 0
        for sy in range(SAMPLES):
            for sx in range(SAMPLES):
                if covered(col + (sx + 0.5) / SAMPLES, row + (sy + 0.5) / SAMPLES):
                    hits += 1
        alpha = round(255 * hits / (SAMPLES * SAMPLES))
        pixels += bytes((255, 255, 255, alpha))  # BGRA

# Uncompressed true-colour TGA, 32 bits, 8 alpha bits, top-left origin.
header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 0x28)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ThatLuckyBastard', 'Media', 'receipt-edge.tga')
with open(out, 'wb') as f:
    f.write(header + bytes(pixels))
print(os.path.normpath(out), len(header) + len(pixels), 'bytes')
