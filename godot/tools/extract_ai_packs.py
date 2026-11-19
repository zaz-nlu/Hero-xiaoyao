"""Slice the user's AI art packs into game-ready files.

Usage (from anywhere; paths are resolved from this script):
    python godot/tools/extract_ai_packs.py forest   # forest props/trees/herbs/chest/camp
    python godot/tools/extract_ai_packs.py npc      # NPC portraits + 32x48 strips

Inputs live under art_source/inputs/, not the runtime assets folder.
forest: reads art_source/inputs/forest/transparent/*.png (alpha cut-outs), finds each connected
        object and writes the crops to godot/assets/scenery/<name>.png. Original textures are
        read from art_source/inputs/forest/tex_*.png and written to godot/assets/textures/.
npc:    reads art_source/inputs/npc_sheets/<id>_character_sheet.png (magenta background; big
        portrait on the left + four pixel sprites front/back/left/right). Writes
        godot/assets/portraits/<id>.png and
        art_source/inputs/npc_strips/<id>_idle_32x48_alpha.png (128x48: front, back, left,
        right), which build_ai_sheets.py turns into walking sheets.
"""
import os
import sys
from collections import deque
from itertools import product

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(REPO, "godot", "assets")
RAW = os.path.join(REPO, "art_source", "inputs")

SCENERY = os.path.join(ASSETS, "scenery")
TEXTURES = os.path.join(ASSETS, "textures")
PORTRAITS = os.path.join(ASSETS, "portraits")
FOREST_DIR = os.path.join(RAW, "forest")
NPC_SHEETS = os.path.join(RAW, "npc_sheets")
NPC_STRIPS = os.path.join(RAW, "npc_strips")

# sheet -> row-major names (rows are discovered by clustering on the object's vertical centre)
FOREST_SHEETS = {
    "forest_trees": ["tree_pine", "tree_camphor", "tree_oak", "tree_poplar", "tree_dead", "tree_maple"],
    "forest_props": [
        "prop_log", "prop_stump", "prop_mushroom_red", "prop_mushroom_brown",
        "prop_fern", "prop_wildflower", "prop_boulder", "prop_stones",
        "prop_vines", "prop_fence", "prop_firewood", "prop_scarecrow",
    ],
    "chest": ["chest_closed", "chest_open"],
    "herbs": ["herb_white", "herb_ginseng", "herb_purple", "herb_glow"],
    "forest_camp": ["camp_signpost", "camp_tent", "camp_fire", "camp_crate"],
}
FOREST_TEXTURES = ["tex_forest_floor", "tex_forest_path"]

NPCS = ["smith", "hunter", "fisherman", "peddler", "waiter", "townswoman"]
PORTRAIT_HEIGHT = 768
CELL_W, CELL_H, SPRITE_H = 32, 48, 46


def components(mask, ds=4, dilate=2, min_cells=12):
    """Connected objects of a boolean mask -> list of (x0, y0, x1, y1) boxes in full-res pixels."""
    h, w = mask.shape
    small = mask[: h // ds * ds, : w // ds * ds].reshape(h // ds, ds, w // ds, ds).any(axis=(1, 3))
    grown = small.copy()
    for dy, dx in product(range(-dilate, dilate + 1), repeat=2):
        grown |= np.roll(np.roll(small, dy, 0), dx, 1)
    label = np.zeros(grown.shape, int)
    boxes = []
    n = 0
    for y, x in zip(*np.nonzero(grown)):
        if label[y, x]:
            continue
        n += 1
        queue = deque([(y, x)])
        label[y, x] = n
        ys, xs = [y], [x]
        while queue:
            cy, cx = queue.popleft()
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < grown.shape[0] and 0 <= nx < grown.shape[1] and grown[ny, nx] and not label[ny, nx]:
                    label[ny, nx] = n
                    queue.append((ny, nx))
                    ys.append(ny)
                    xs.append(nx)
        if len(ys) >= min_cells:
            boxes.append((min(xs) * ds, min(ys) * ds, (max(xs) + 1) * ds, (max(ys) + 1) * ds))
    return boxes


def row_major(boxes, row_gap=0.5):
    """Sort boxes into rows (by vertical centre) then left-to-right."""
    boxes = sorted(boxes, key=lambda b: (b[1] + b[3]) / 2)
    heights = sorted(b[3] - b[1] for b in boxes)
    tol = heights[len(heights) // 2] * row_gap
    rows, current, last = [], [], None
    for b in boxes:
        c = (b[1] + b[3]) / 2
        if last is not None and c - last > tol:
            rows.append(current)
            current = []
        current.append(b)
        last = c if not current[:-1] else last
    if current:
        rows.append(current)
    out = []
    for r in rows:
        out.extend(sorted(r, key=lambda b: b[0]))
    return out


def despill(im):
    a = np.array(im.convert("RGBA")).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mag = (r > g + 25) & (b > g + 25)
    a[..., 0] = np.where(mag, np.minimum(r, g + 10), r)
    a[..., 2] = np.where(mag, np.minimum(b, g + 10), b)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def key_magenta(im):
    a = np.array(im.convert("RGB")).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    d = np.sqrt((255 - r) ** 2 + g ** 2 + (255 - b) ** 2)
    alpha = np.clip((d - 60) / 60 * 255, 0, 255).astype(np.uint8)
    rgba = np.dstack([a.astype(np.uint8), alpha])
    return despill(Image.fromarray(rgba, "RGBA"))


def trim(im, thresh=10):
    bb = im.getchannel("A").point(lambda v: 255 if v > thresh else 0).getbbox()
    return im.crop(bb) if bb else im


def do_forest():
    os.makedirs(SCENERY, exist_ok=True)
    os.makedirs(TEXTURES, exist_ok=True)
    for sheet, names in FOREST_SHEETS.items():
        im = Image.open(os.path.join(FOREST_DIR, "transparent", sheet + ".png")).convert("RGBA")
        mask = np.array(im.getchannel("A")) > 20
        boxes = components(mask)
        if len(boxes) > len(names):  # drop sparkles / specks: keep the biggest objects
            boxes = sorted(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]), reverse=True)[: len(names)]
        boxes = row_major(boxes)
        if len(boxes) != len(names):
            print("WARNING %s: found %d objects, expected %d" % (sheet, len(boxes), len(names)))
        for name, box in zip(names, boxes):
            piece = trim(despill(im.crop(box)))
            piece.save(os.path.join(SCENERY, name + ".png"))
            print("wrote", name, piece.size)
    for tex in FOREST_TEXTURES:
        Image.open(os.path.join(FOREST_DIR, tex + ".png")).convert("RGB").save(
            os.path.join(TEXTURES, tex + ".png")
        )
        print("wrote", tex)


def sprite_cell(sprite):
    """Scale a keyed sprite to SPRITE_H tall (NEAREST) and centre it, feet down, in a 32x48 cell."""
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


def do_npc():
    os.makedirs(NPC_STRIPS, exist_ok=True)
    os.makedirs(PORTRAITS, exist_ok=True)
    for npc_id in NPCS:
        im = Image.open(os.path.join(NPC_SHEETS, npc_id + "_character_sheet.png")).convert("RGB")
        keyed = key_magenta(im)
        mask = np.array(keyed.getchannel("A")) > 30
        boxes = components(mask, dilate=2)
        big = max(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))
        smalls = sorted([b for b in boxes if b != big], key=lambda b: b[0])
        smalls = [b for b in smalls if (b[3] - b[1]) > 120]
        if len(smalls) != 4:
            print("WARNING %s: %d sprites found (expected 4)" % (npc_id, len(smalls)))
        portrait = trim(keyed.crop(big))
        scale = PORTRAIT_HEIGHT / portrait.height
        portrait = portrait.resize((round(portrait.width * scale), PORTRAIT_HEIGHT), Image.LANCZOS)
        portrait.save(os.path.join(PORTRAITS, npc_id + ".png"))
        strip = Image.new("RGBA", (CELL_W * 4, CELL_H), (0, 0, 0, 0))
        for i, box in enumerate(smalls[:4]):
            strip.paste(sprite_cell(keyed.crop(box)), (i * CELL_W, 0))
        strip.save(os.path.join(NPC_STRIPS, npc_id + "_idle_32x48_alpha.png"))
        print("wrote", npc_id, "portrait", portrait.size)


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else ""
    if what == "forest":
        do_forest()
    elif what == "npc":
        do_npc()
    else:
        print(__doc__)
