#!/usr/bin/env python3
"""check-frame-edges.py — the window-edge check, components.md §17.2 rule 6
(added 2026-10-08, Phase 2 acceptance; closes G-053). Kept from P2-SF1 / CF5.

In a window frame, no opaque pixel in the outermost 2px band may match
`accent` / `focusRing` (light #0A6CFF, dark #4C9BFF) or the system ring tints
seen in the B35 frames (#80B3FA, #8DBBFB), nor be blue-dominant. A pixel within
30 (sum of |dR|+|dG|+|dB|) of a listed colour, or with B > R + 40 and
B > G + 40, is flagged.

The one exemption — §14.4's preview border while a preview is active — is
implemented from rule 6's three conditions, never from a per-file allow-list:

  1. the frame is filed under an item that asks for an active preview: the
     caller says so with `--preview` (an item property, not a file name);
  2. the flagged pixels form a COMPLETE rectangle, 2pt wide (2–6 px at 1x–3x),
     following the canvas on all four sides — including the side that does not
     touch the window edge; each side must be flagged along >= 90% of its
     length (the window's rounded corners are transparent and eat a little);
  3. every flagged pixel in the band lies on that rectangle's own strips:
     accent anywhere else in the band (the inspector's or sidebar's outer edge,
     the title bar) still fails.

Usage: Scripts/check-frame-edges.py [--preview] FRAME.png [...]
       exit 1 if any frame flags.
"""
import sys
from collections import Counter

from PIL import Image

ACCENTS = [(0x0A, 0x6C, 0xFF), (0x4C, 0x9B, 0xFF), (0x80, 0xB3, 0xFA), (0x8D, 0xBB, 0xFB)]
BAND = 2
# A straight run of flagged pixels at least this long is a candidate border side.
MIN_RUN = 100
# 2pt at 1x … 3x.
MIN_EDGE_PX, MAX_EDGE_PX = 2, 6
# A side counts as present when this share of its length is flagged.
COVERAGE = 0.90
# Antialiasing slack, in px, when matching band pixels to the rectangle's strips.
SLACK = 1


def flagged(rgb):
    r, g, b = rgb
    if any(abs(r - a) + abs(g - c) + abs(b - d) <= 30 for a, c, d in ACCENTS):
        return True
    return b > r + 40 and b > g + 40


def flag_mask(image):
    w, h = image.size
    px = image.load()
    mask = [[False] * w for _ in range(h)]
    for y in range(h):
        row = mask[y]
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 255 and flagged((r, g, b)):
                row[x] = True
    return mask


def longest_run(values):
    best = cur = 0
    for v in values:
        cur = cur + 1 if v else 0
        best = max(best, cur)
    return best


def groups(indices):
    """Adjacent indices → [(first, last)]."""
    out = []
    for i in sorted(indices):
        if out and i == out[-1][1] + 1:
            out[-1] = (out[-1][0], i)
        else:
            out.append((i, i))
    return out


def edge_groups(mask, w, h):
    cols = [x for x in range(w) if longest_run(mask[y][x] for y in range(h)) >= MIN_RUN]
    rows = [y for y in range(h) if longest_run(mask[y]) >= MIN_RUN]
    keep = lambda g: MIN_EDGE_PX <= g[1] - g[0] + 1 <= MAX_EDGE_PX
    return [g for g in groups(cols) if keep(g)], [g for g in groups(rows) if keep(g)]


def coverage_v(mask, cols, y0, y1):
    hit = sum(1 for y in range(y0, y1 + 1) if any(mask[y][x] for x in range(cols[0], cols[1] + 1)))
    return hit / (y1 - y0 + 1)


def coverage_h(mask, rows, x0, x1):
    hit = sum(1 for x in range(x0, x1 + 1) if any(mask[y][x] for y in range(rows[0], rows[1] + 1)))
    return hit / (x1 - x0 + 1)


def on_strips(x, y, rect):
    (l0, l1), (r0, r1), (t0, t1), (b0, b1) = rect
    s = SLACK
    inside_y = t0 - s <= y <= b1 + s
    inside_x = l0 - s <= x <= r1 + s
    vertical = inside_y and (l0 - s <= x <= l1 + s or r0 - s <= x <= r1 + s)
    horizontal = inside_x and (t0 - s <= y <= t1 + s or b0 - s <= y <= b1 + s)
    return vertical or horizontal


def preview_rectangle(mask, w, h, hits):
    """The largest complete 2pt rectangle that carries every band hit, or None."""
    verticals, horizontals = edge_groups(mask, w, h)
    best = None
    for i, left in enumerate(verticals):
        for right in verticals[i + 1:]:
            for j, top in enumerate(horizontals):
                for bottom in horizontals[j + 1:]:
                    y0, y1, x0, x1 = top[0], bottom[1], left[0], right[1]
                    sides = (coverage_v(mask, left, y0, y1), coverage_v(mask, right, y0, y1),
                             coverage_h(mask, top, x0, x1), coverage_h(mask, bottom, x0, x1))
                    if min(sides) < COVERAGE:
                        continue
                    rect = (left, right, top, bottom)
                    if not all(on_strips(x, y, rect) for x, y, _ in hits):
                        continue
                    area = (x1 - x0) * (y1 - y0)
                    if best is None or area > best[0]:
                        best = (area, rect)
    return best[1] if best else None


def check(path, preview=False):
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
    if not hits:
        print(f"ok      {path}: no accent-like px; band: {common}")
        return True
    x, y, (r, g, b) = hits[0]
    if preview:
        rect = preview_rectangle(flag_mask(image), w, h, hits)
        if rect:
            (l0, _), (_, r1), (t0, _), (_, b1) = rect
            print(f"ok      {path}: {len(hits)} accent px in the band, all on a complete preview "
                  f"border x {l0}–{r1}, y {t0}–{b1} (§17.2 rule 6 exemption); band: {common}")
            return True
        print(f"FLAGGED {path}: {len(hits)} accent-like px (first at {x},{y} #{r:02X}{g:02X}{b:02X}); "
              f"not a complete preview rectangle, or accent outside it; band: {common}")
        return False
    print(f"FLAGGED {path}: {len(hits)} accent-like px (first at {x},{y} #{r:02X}{g:02X}{b:02X}); band: {common}")
    return False


if __name__ == "__main__":
    args = sys.argv[1:]
    preview = "--preview" in args
    paths = [a for a in args if a != "--preview"]
    results = [check(p, preview) for p in paths]
    sys.exit(0 if results and all(results) else 1)
