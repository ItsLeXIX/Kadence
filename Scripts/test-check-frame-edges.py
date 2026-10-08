#!/usr/bin/env python3
"""test-check-frame-edges.py — P3-H2's acceptance for check-frame-edges.py
(components.md §17.2 rule 6, the preview-border exemption).

  1. screenshots/2/template-conflict-panel-p2c.png passes with --preview
     (and still fails without it: the exemption needs the item's say-so).
  2. A synthetic frame with a one-edge accent line in the band fails, with
     --preview too.
  3. A synthetic preview frame whose rectangle is missing its inner side fails.
  4. Control: the same synthetic frame with the inner side drawn passes with
     --preview; accent added on the band outside the rectangle then fails.

Usage: Scripts/test-check-frame-edges.py     exit 1 on any failed expectation.
"""
import importlib.util
import os
import sys
import tempfile

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cfe", os.path.join(HERE, "check-frame-edges.py"))
cfe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cfe)

ACCENT = (0x4C, 0x9B, 0xFF, 255)
CANVAS = (0x1E, 0x1E, 0x20, 255)
W, H = 1200, 800
# The canvas reaches the window's left and bottom edges; the inspector sits to
# its right (x >= 900) and the day header above it (y < 120) — as in item 16.
CX0, CY0, CX1, CY1 = 0, 120, 899, H - 1
EDGE = 4  # 2pt at 2x


def frame(sides=("left", "right", "top", "bottom"), extra=None):
    im = Image.new("RGBA", (W, H), CANVAS)
    d = ImageDraw.Draw(im)
    if "left" in sides:
        d.rectangle([CX0, CY0, CX0 + EDGE - 1, CY1], fill=ACCENT)
    if "right" in sides:
        d.rectangle([CX1 - EDGE + 1, CY0, CX1, CY1], fill=ACCENT)
    if "top" in sides:
        d.rectangle([CX0, CY0, CX1, CY0 + EDGE - 1], fill=ACCENT)
    if "bottom" in sides:
        d.rectangle([CX0, CY1 - EDGE + 1, CX1, CY1], fill=ACCENT)
    if extra:
        d.rectangle(extra, fill=ACCENT)
    return im


def run(name, image_or_path, preview, expect):
    if isinstance(image_or_path, str):
        path = image_or_path
    else:
        path = os.path.join(tempfile.mkdtemp(), name + ".png")
        image_or_path.save(path)
    got = cfe.check(path, preview)
    ok = got == expect
    print(f"{'PASS' if ok else 'FAIL'}  {name}: expected {'pass' if expect else 'flag'}, got {'pass' if got else 'flag'}")
    return ok


def main():
    real = os.path.join(HERE, "..", "screenshots", "2", "template-conflict-panel-p2c.png")
    results = [
        run("item 16 frame, --preview", real, True, True),
        run("item 16 frame, no --preview", real, False, False),
        run("one-edge line in the band", frame(sides=("left",)), True, False),
        run("one-edge line in the band, no --preview", frame(sides=("left",)), False, False),
        run("preview rectangle missing its inner side", frame(sides=("left", "top", "bottom")), True, False),
        run("complete preview rectangle", frame(), True, True),
        run("complete rectangle + accent on the inspector's outer edge",
            frame(extra=[W - 2, 300, W - 1, 500]), True, False),
        run("complete rectangle + accent in the title-bar band",
            frame(extra=[950, 0, 1100, 1]), True, False),
    ]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
