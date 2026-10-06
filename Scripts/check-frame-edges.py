#!/usr/bin/env python3
"""check-frame-edges.py — the P2-SF1 edge check, kept (PHASE2-REVIEW.md
"Closeout — 2026-10-07" CF5): in a window frame, no opaque pixel in the
outermost 2px band may match `accent` / `focusRing` (light #0A6CFF, dark
#4C9BFF) or the system ring tints seen in the B35 frames (#80B3FA, #8DBBFB),
nor be blue-dominant. Same rule as P2-RC's scratch `edge.py`: a pixel within
30 (sum of |dR|+|dG|+|dB|) of a listed colour, or with B > R + 40 and
B > G + 40, is flagged.

Usage: Scripts/check-frame-edges.py FRAME.png [...]   exit 1 if any frame flags.
"""
import sys
from collections import Counter

from PIL import Image

ACCENTS = [(0x0A, 0x6C, 0xFF), (0x4C, 0x9B, 0xFF), (0x80, 0xB3, 0xFA), (0x8D, 0xBB, 0xFB)]
BAND = 2


def flagged(rgb):
    r, g, b = rgb
    if any(abs(r - a) + abs(g - c) + abs(b - d) <= 30 for a, c, d in ACCENTS):
        return True
    return b > r + 40 and b > g + 40


def check(path):
    image = Image.open(path).convert("RGBA")
    w, h = image.size
    px = image.load()
    band, hits = Counter(), []
    for y in range(h):
        for x in range(w):
            if BAND <= x < w - BAND and BAND <= y < h - BAND:
                continue
            r, g, b, a = px[x, y]
            if a < 255:          # the window's transparent rounded corners
                continue
            band[(r, g, b)] += 1
            if flagged((r, g, b)):
                hits.append((x, y, (r, g, b)))
    common = ", ".join(f"#{r:02X}{g:02X}{b:02X} {n}" for (r, g, b), n in band.most_common(4))
    if hits:
        x, y, (r, g, b) = hits[0]
        print(f"FLAGGED {path}: {len(hits)} accent-like px (first at {x},{y} #{r:02X}{g:02X}{b:02X}); band: {common}")
        return False
    print(f"ok      {path}: no accent-like px; band: {common}")
    return True


if __name__ == "__main__":
    results = [check(p) for p in sys.argv[1:]]
    sys.exit(0 if results and all(results) else 1)
