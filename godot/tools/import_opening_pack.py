"""Imports the opening-sequence art pack (Heroes_Opening_Expanded_Assets) into the game.

Run from the repo root:
    py -3 godot/tools/import_opening_pack.py [pack_dir]
pack_dir defaults to art_source/incoming/opening_pack_01/Heroes_Opening_Expanded_Assets.

What it does
- skies / ground: copied (skies shrunk to 2048 wide) -> assets/scenery, assets/textures
- four-view strips (magenta background) -> 32x48 sprite sheets in assets/sprites via
  build_ai_sheets.build, plus hi-res cut-outs of the three leaders for cinematics
- ink portraits (paper background) -> transparent PNGs in assets/portraits (edge flood-fill,
  so white robes survive), registered in data/speakers.json
- duel picture: kept as a full illustration (not a cut-out); prop sheets: sliced into single props
- 帝王世纪 VFX sheets copied untouched into assets/vfx (to be framed later)
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT = os.path.join(ROOT, "godot")
ASSETS = os.path.join(GODOT, "assets")
DEFAULT_PACK = os.path.join(
    ROOT, "art_source", "incoming", "opening_pack_01", "Heroes_Opening_Expanded_Assets")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_ai_sheets  # noqa: E402

FW, FH = 32, 48

SPRITES = {  # game id -> (folder, file)
    "dongfang_yang": ("02_character_four_views", "dongfang_yang_strip.png"),
    "dongfang_yun": ("02_character_four_views", "dongfang_yun_strip.png"),
    "sol_demon_king": ("02_character_four_views", "sol_demon_king_strip.png"),
    "imperial_swordsman": ("01_opening_first8", "imperial_swordsman_strip.png"),
    "demon_soldier": ("04_additional_units_and_props", "demon_soldier_strip.png"),
    "beastman_warrior": ("04_additional_units_and_props", "beastman_warrior_strip.png"),
    "elf_archer": ("04_additional_units_and_props", "elf_archer_strip.png"),
}
LEADERS = ("dongfang_yang", "dongfang_yun", "sol_demon_king")
VIEWS = ("front", "back", "left", "right")

PORTRAITS = {
    "dongfang_yang": "东方阳",
    "dongfang_yun": "东方云",
    "sol_demon_king": "魔王索尔",
}

TEA_PROPS = [  # detection order of props_teahouse_sheet.png
    "prop_tea_stall", "prop_tea_storyteller_table", "prop_tea_table", "prop_tea_flag",
    "prop_tea_stool_a", "prop_tea_stool_b", "prop_tea_stool_c", "prop_tea_bench",
]

BATTLE_PROPS = [  # detection order of props_battlefield_sheet.png (three flags are one cluster)
    "prop_battle_smoke", "prop_battle_pole_fallen", "prop_battle_spears", "prop_battle_flags",
    "prop_battle_shield", "prop_battle_ballista", "prop_battle_wagon_burning",
    "prop_battle_campfire",
]


def out(path, *parts):
    full = os.path.join(path, *parts)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    return full


# ------------------------------------------------------------------ helpers
def is_background(arr):
    """Magenta or near-white pixels (the strips have a magenta field and a white frame)."""
    r, g, b = arr[..., 0].astype(int), arr[..., 1].astype(int), arr[..., 2].astype(int)
    magenta = (r > 170) & (b > 170) & (g < 110)
    white = (r > 238) & (g > 238) & (b > 238)
    return magenta | white


def split_views(mask, expected=4, min_gap=14):
    """Column runs of foreground; returns [(x0, x1)] for the four views."""
    cols = mask.any(axis=0)
    runs, start = [], None
    for x, v in enumerate(cols):
        if v and start is None:
            start = x
        elif not v and start is not None:
            runs.append([start, x])
            start = None
    if start is not None:
        runs.append([start, len(cols)])
    merged = []
    for run in runs:
        if merged and run[0] - merged[-1][1] < min_gap:
            merged[-1][1] = run[1]
        else:
            merged.append(run)
    merged = [r for r in merged if r[1] - r[0] > 12]
    if len(merged) != expected:
        width = mask.shape[1]
        merged = [[i * width // expected, (i + 1) * width // expected] for i in range(expected)]
        print("  warning: could not find %d clean views, using equal quarters" % expected)
    return merged


def cut_view(rgb, mask, x0, x1):
    sub = mask[:, x0:x1]
    labels, n = ndimage.label(ndimage.binary_dilation(sub, iterations=3))
    if n == 0:
        return None
    sizes = ndimage.sum(sub, labels, range(1, n + 1))
    keep = (labels == (int(np.argmax(sizes)) + 1)) & sub  # largest part only
    ys, xs = np.where(keep)
    if len(ys) == 0:
        return None
    y0, y1, xa, xb = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    crop = rgb[y0:y1, x0 + xa:x0 + xb]
    alpha = (keep[y0:y1, xa:xb] * 255).astype(np.uint8)
    return Image.fromarray(np.dstack([crop, alpha]).astype(np.uint8), "RGBA")


def import_strip(game_id, strip_path, tmp_dir):
    im = Image.open(strip_path).convert("RGB")
    arr = np.array(im)
    mask = ~is_background(arr)
    mask = ndimage.binary_opening(mask, iterations=1)
    spans = split_views(mask)
    views = [cut_view(arr, mask, x0, x1) for x0, x1 in spans]
    if any(v is None for v in views):
        print("  skipped %s: empty view" % game_id)
        return
    max_h = max(v.height for v in views)
    max_w = max(v.width for v in views)
    scale = min(46.0 / max_h, 30.0 / max_w)
    strip = Image.new("RGBA", (FW * 4, FH), (0, 0, 0, 0))
    for i, v in enumerate(views):
        w = max(1, round(v.width * scale))
        h = max(1, round(v.height * scale))
        small = v.resize((w, h), Image.LANCZOS)
        a = small.getchannel("A").point(lambda p: 255 if p > 110 else 0)
        small.putalpha(a)
        frame = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
        frame.paste(small, ((FW - w) // 2, FH - 1 - h), small)
        strip.paste(frame, (i * FW, 0))
    strip_file = os.path.join(tmp_dir, game_id + "_idle_32x48_alpha.png")
    strip.save(strip_file)
    build_ai_sheets.build(game_id, strip_file)
    if game_id in LEADERS:
        for name, v in zip(VIEWS, views):
            hi = v
            if hi.height > 640:
                f = 640.0 / hi.height
                hi = hi.resize((max(1, round(hi.width * f)), 640), Image.LANCZOS)
            hi.save(out(ASSETS, "scenery", "opening_%s_%s.png" % (game_id, name)), optimize=True)
    print("  sprite %s  (%d views, scale %.3f)" % (game_id, len(views), scale))


def flood_background(arr, tol):
    """Pixels connected to the image border whose colour is close to the paper colour."""
    h, w, _ = arr.shape
    border = np.concatenate([arr[0], arr[-1], arr[:, 0], arr[:, -1]]).astype(float)
    paper = np.median(border, axis=0)
    dist = np.abs(arr.astype(float) - paper).max(axis=2)
    close = dist < tol
    labels, _ = ndimage.label(close)
    edge_labels = set(np.unique(np.concatenate(
        [labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    bg = np.isin(labels, list(edge_labels))
    return bg, paper


def import_portrait(game_id, path):
    arr = np.array(Image.open(path).convert("RGB"))
    bg, paper = flood_background(arr, tol=22)
    bg = ndimage.binary_opening(bg, iterations=1) | bg
    fg = ~bg
    fg = ndimage.binary_closing(fg, iterations=2)
    labels, n = ndimage.label(fg)
    if n > 1:  # drop stray specks, keep big parts
        sizes = ndimage.sum(fg, labels, range(1, n + 1))
        keep = np.isin(labels, [i + 1 for i, s in enumerate(sizes) if s > fg.sum() * 0.01])
        fg = keep
    alpha = Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    rgba = np.dstack([arr, np.array(alpha)]).astype(np.uint8)
    im = Image.fromarray(rgba, "RGBA")
    box = im.getchannel("A").point(lambda p: 255 if p > 20 else 0).getbbox()
    im = im.crop((max(0, box[0] - 6), max(0, box[1] - 6),
                  min(im.width, box[2] + 6), min(im.height, box[3] + 6)))
    scale = 768.0 / im.height
    im = im.resize((max(1, round(im.width * scale)), 768), Image.LANCZOS)
    im.save(out(ASSETS, "portraits", game_id + ".png"), optimize=True)
    print("  portrait %s  %s" % (game_id, im.size))


def register_speakers():
    path = os.path.join(GODOT, "data", "speakers.json")
    speakers = json.load(open(path, encoding="utf-8"))
    known = {s["id"] for s in speakers}
    for game_id, name in PORTRAITS.items():
        if game_id in known:
            continue
        speakers.append({
            "id": game_id, "name": name,
            "portrait": "res://assets/portraits/%s.png" % game_id, "side": "right",
        })
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(speakers, fh, ensure_ascii=False, indent=1)
        fh.write("\n")


def segment_light_background(im, min_light=200, max_sat=42):
    """The sheets sit on a torn pale sheet of paper: treat transparent and very light,
    desaturated pixels as background (the colourful props stay)."""
    rgba = np.array(im.convert("RGBA"))
    rgb = rgba[..., :3].astype(int)
    transparent = rgba[..., 3] < 128
    light = (rgb.min(axis=2) > min_light) & ((rgb.max(axis=2) - rgb.min(axis=2)) < max_sat)
    fg = ~(transparent | light)
    fg = ndimage.binary_opening(fg, iterations=1)
    fg = ndimage.binary_closing(fg, iterations=2)
    alpha = Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    out_im = Image.fromarray(rgba[..., :3].astype(np.uint8), "RGB").convert("RGBA")
    out_im.putalpha(alpha)
    return out_im


def slice_props(sheet_path, names, dest_dir, segment, min_light=200, max_sat=42, min_area=600, dilate=4):
    raw = Image.open(sheet_path)
    im = segment_light_background(raw, min_light, max_sat) if segment else raw.convert("RGBA")
    alpha = np.array(im.getchannel("A")) > 40
    labels, n = ndimage.label(ndimage.binary_dilation(alpha, iterations=dilate) if dilate > 0 else alpha)
    boxes = []
    for i in range(1, n + 1):
        ys, xs = np.where((labels == i) & alpha)
        if len(ys) < min_area:
            continue
        boxes.append((ys.min(), ys.max() + 1, xs.min(), xs.max() + 1, i))
    boxes.sort(key=lambda b: ((b[0] + b[1]) // 2 // 220, b[2]))
    print("  %s: found %d items (expected %d)" % (os.path.basename(sheet_path), len(boxes), len(names)))
    base_alpha = np.array(im.getchannel("A"))
    for box, name in zip(boxes, names):
        own = ndimage.binary_dilation(labels == box[4], iterations=2)
        masked = Image.fromarray((base_alpha * own).astype(np.uint8))
        full = im.copy()
        full.putalpha(masked)
        part = full.crop((box[2] - 3, box[0] - 3, box[3] + 3, box[1] + 3))
        part.save(out(dest_dir, name + ".png"), optimize=True)
        if name == "prop_battle_flags":
            third = part.width // 3
            for k, flag in enumerate(("imperial", "demon", "torn")):
                part.crop((k * third, 0, (k + 1) * third, part.height)).save(
                    out(dest_dir, "prop_battle_flag_%s.png" % flag), optimize=True)


def main():
    pack = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PACK
    if not os.path.isdir(pack):
        print("pack folder not found:", pack)
        return 1
    tmp = os.path.join(ROOT, "art_source", "incoming", "opening_pack_01", "_strips32")
    os.makedirs(tmp, exist_ok=True)

    print("skies & ground")
    for name in ("ash", "dawn", "dusk", "gold"):
        im = Image.open(os.path.join(pack, "01_opening_first8", "bg_battle_%s.png" % name)).convert("RGB")
        im = im.crop((16, 16, im.width - 16, im.height - 16))  # the pack has a white frame
        w = 2048
        im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
        im.save(out(ASSETS, "scenery", "bg_battle_%s.png" % name), optimize=True)
    ground = Image.open(os.path.join(pack, "01_opening_first8", "tex_battlefield_ground.png")).convert("RGB")
    ground = ground.crop((16, 16, ground.width - 16, ground.height - 16))  # drop the white frame
    gw, gh = ground.size  # mirror-tile 2x2 so the texture tiles without seams
    tiled = Image.new("RGB", (gw * 2, gh * 2))
    tiled.paste(ground, (0, 0))
    tiled.paste(ground.transpose(Image.FLIP_LEFT_RIGHT), (gw, 0))
    tiled.paste(ground.transpose(Image.FLIP_TOP_BOTTOM), (0, gh))
    tiled.paste(ground.transpose(Image.ROTATE_180), (gw, gh))
    tiled.resize((1024, 1024), Image.LANCZOS).save(
        out(ASSETS, "textures", "tex_battlefield_ground.png"), optimize=True)

    print("sprites")
    for game_id, (folder, fname) in SPRITES.items():
        import_strip(game_id, os.path.join(pack, folder, fname), tmp)

    print("portraits")
    for game_id in PORTRAITS:
        import_portrait(game_id, os.path.join(pack, "03_character_portraits_ink", game_id + "_portrait.png"))
    register_speakers()

    print("duel illustration & props")
    Image.open(os.path.join(pack, "01_opening_first8", "opening_duel_cutout.png")).convert("RGBA").save(
        out(ASSETS, "scenery", "opening_duel_art.png"), optimize=True)
    slice_props(os.path.join(pack, "01_opening_first8", "props_battlefield_sheet.png"),
                BATTLE_PROPS, os.path.join(ASSETS, "scenery"), segment=True,
                min_light=165, max_sat=75, min_area=700, dilate=0)
    tea = os.path.join(pack, "04_additional_units_and_props", "props_teahouse_sheet.png")
    slice_props(tea, TEA_PROPS, os.path.join(ASSETS, "scenery"), segment=True,
                min_light=225, max_sat=30)

    print("vfx")
    vfx_dir = os.path.join(pack, "05_emperor_century_vfx")
    for fname in sorted(os.listdir(vfx_dir)):
        if fname.endswith(".png"):
            Image.open(os.path.join(vfx_dir, fname)).convert("RGBA").save(
                out(ASSETS, "vfx", "emperor_century_" + fname.replace("emperor_century_", "")), optimize=True)
    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
