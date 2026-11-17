"""Cut the villager contact sheet (assets/npc_six_preview.jpg, 6 panels) into portraits and sprites.

Usage (repo root):  python godot/tools/extract_preview_pack.py

Each panel = a painted portrait (left), one big pixel sprite (top right) and a row of four small
sprites (bottom: front, front-variant, left 3/4, left profile). The sheet is a JPG preview, so:
  * portraits are upscaled (LANCZOS) to 768 tall,
  * small sprites are scaled to 46 px tall in a 32x48 cell (NEAREST), the first sprite is often
    partly covered by the portrait, so sprite #2 is used as the front view, #4 as the left
    profile, and the right view is its mirror,
  * the back view is synthesised from the front view by painting skin pixels of the head with the
    hair colour.
Outputs (under assets/ai/raw_user/preview_strips/<id>/<id>_idle_32x48_alpha.png, 128x48:
front, back, left, right) and assets/portraits/<id>.png, then run build_ai_sheets.py on them.
"""
import colorsys
import os
import sys
from collections import Counter

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_ai_packs import components, trim, despill  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
SRC = os.path.join(ASSETS, "npc_six_preview.jpg")
OUT_STRIPS = os.path.join(ASSETS, "ai", "raw_user", "preview_strips")
OUT_PORTRAITS = os.path.join(ASSETS, "portraits")

PANELS = [
    (9, 10, 591, 610),
    (609, 10, 1192, 610),
    (1209, 10, 1791, 610),
    (9, 629, 591, 1232),
    (609, 629, 1192, 1232),
    (1209, 629, 1791, 1232),
]
# panel order in the sheet -> label
LABELS = ["herbalist", "tailor", "grandmother", "scholar", "shopkeeper", "guard"]
# which game id each *row of small sprites* becomes, and which id each portrait / big sprite becomes
ROW_IDS = ["elder", "girl", "grandmother", "scholar", "shopkeeper_m", "guard"]
PORTRAIT_IDS = ["herbalist", "tailor", "grandmother", "scholar", "shopkeeper_f", "guard"]
BIG_SPRITE_IDS = {"herbalist": True, "tailor": True, "shopkeeper_f": True}  # portrait chars whose row does not match
CELL_W, CELL_H, SPRITE_H = 32, 48, 46


def panel_mask(img, box):
    x0, y0, x1, y1 = box
    sub = np.array(img.crop(box).convert("RGB")).astype(np.int32)
    bg = np.median(np.concatenate([sub[20:30, 20:30].reshape(-1, 3), sub[-30:-20, -30:-20].reshape(-1, 3)]), axis=0)
    dist = np.sqrt(((sub - bg) ** 2).sum(axis=2))
    mask = dist > 58
    mask[:45, :180] = False  # panel label
    mask[:6, :] = False
    mask[-6:, :] = False
    mask[:, :6] = False
    mask[:, -6:] = False
    return sub.astype(np.uint8), mask, bg


def cutout(sub, mask, box):
    x0, y0, x1, y1 = box
    rgba = np.dstack([sub[y0:y1, x0:x1], (mask[y0:y1, x0:x1] * 255).astype(np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def column_clusters(mask, gap=10):
    cols = np.nonzero(mask.any(axis=0))[0]
    if len(cols) == 0:
        return []
    clusters, start, prev = [], cols[0], cols[0]
    for c in cols[1:]:
        if c - prev > gap:
            clusters.append((start, prev + 1))
            start = c
        prev = c
    clusters.append((start, prev + 1))
    return clusters


def to_cell(sprite):
    sprite = trim(sprite)
    scale = SPRITE_H / sprite.height
    w = max(1, round(sprite.width * scale))
    if w > CELL_W:
        scale = CELL_W / sprite.width
        w = CELL_W
    h = max(1, round(sprite.height * scale))
    small = sprite.resize((w, h), Image.NEAREST)
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    cell.paste(small, ((CELL_W - w) // 2, CELL_H - 1 - h), small)
    return cell


def is_skin(rgb):
    r, g, b = [c / 255.0 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return 0.02 <= h <= 0.12 and 0.18 <= s <= 0.7 and v >= 0.55


def make_back(front):
    """Front view -> back view: skin pixels in the head rows become the hair colour."""
    back = front.copy()
    px = back.load()
    rows = range(0, 16)
    top = [px[x, y][:3] for y in range(0, 7) for x in range(CELL_W) if px[x, y][3] > 0 and not is_skin(px[x, y][:3])]
    if not top:
        return back
    hair = tuple(int(np.median([c[i] for c in top])) for i in range(3))
    for y in rows:
        for x in range(CELL_W):
            p = px[x, y]
            if p[3] > 0 and is_skin(p[:3]):
                px[x, y] = hair + (255,)
    return back


def make_strip(front, left):
    right = left.transpose(Image.FLIP_LEFT_RIGHT)
    back = make_back(front)
    strip = Image.new("RGBA", (CELL_W * 4, CELL_H), (0, 0, 0, 0))
    for i, cell in enumerate([front, back, left, right]):
        strip.paste(cell, (i * CELL_W, 0))
    return strip


def save_strip(npc_id, strip):
    d = os.path.join(OUT_STRIPS, npc_id)
    os.makedirs(d, exist_ok=True)
    strip.save(os.path.join(d, npc_id + "_idle_32x48_alpha.png"))


def main():
    img = Image.open(SRC).convert("RGB")
    os.makedirs(OUT_PORTRAITS, exist_ok=True)
    for i, box in enumerate(PANELS):
        sub, mask, bg = panel_mask(img, box)
        ph, pw = mask.shape
        band_y = int(ph * 0.70)
        # --- row of small sprites -------------------------------------------------
        band = mask.copy()
        band[:band_y, :] = False
        band[:, :170] = False  # skip the portrait's hem on the left
        clusters = column_clusters(band)
        clusters = [c for c in clusters if c[1] - c[0] > 25]
        print(LABELS[i], "sprite clusters:", clusters)
        sprites = []
        for (c0, c1) in clusters[-3:]:
            sprites.append(trim(cutout(sub, band, (c0, band_y, c1, ph))))
        # sprites[0] = front variant, sprites[1] = left 3/4, sprites[2] = left profile
        if len(sprites) == 3:
            front, profile = to_cell(sprites[0]), to_cell(sprites[2])
            save_strip(ROW_IDS[i], make_strip(front, profile))
        else:
            print("  WARNING: expected 3 sprite clusters")
        # --- big pixel sprite (top right) ------------------------------------------
        big_mask = mask.copy()
        big_mask[int(ph * 0.62):, :] = False
        big_mask[:, : int(pw * 0.50)] = False
        boxes = components(big_mask, ds=2, dilate=2, min_cells=40)
        big = None
        if boxes:
            bb = max(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))
            big = trim(cutout(sub, big_mask, bb))
        # --- portrait (left) --------------------------------------------------------
        port_mask = mask.copy()
        port_mask[:, int(pw * 0.50):] = False
        # the first small sprite overlaps the portrait's hem: blank it out of the portrait
        port_mask[int(ph * 0.78):, 165:] = False
        boxes = components(port_mask, ds=2, dilate=3, min_cells=200)
        pb = max(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))
        portrait = trim(despill(cutout(sub, port_mask, pb)))
        scale = 768.0 / portrait.height
        portrait = portrait.resize((round(portrait.width * scale), 768), Image.LANCZOS)
        pid = PORTRAIT_IDS[i]
        portrait.save(os.path.join(OUT_PORTRAITS, pid + ".png"))
        print("  portrait", pid, portrait.size)
        if pid in BIG_SPRITE_IDS and big is not None:
            cell = to_cell(despill(big))
            save_strip(pid, make_strip(cell, cell))
            print("  big sprite ->", pid)


if __name__ == "__main__":
    main()
