"""Import the town pack v2 (24 files) and the battle VFX pack (15 files).

Usage (from the repo root):
    python godot/tools/import_pack_v2.py

Reads  art_source/incoming/town_pack_v2/   (transparent/*.png, godot/assets/ai/*)
       art_source/incoming/battle_vfx_pack/godot/assets/ai/vfx/*.png
Writes godot/assets/scenery/town_*.png   sliced props (names in PROPS below)
       godot/assets/scenery/bg_*.png     backgrounds
       godot/assets/textures/tex_*.png   terrain tiles
       godot/assets/vfx/*.png            VFX sheets with real alpha
Requires: Pillow, numpy, scipy.
"""
import glob
import os

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
TOWN = os.path.join(ROOT, "art_source", "incoming", "town_pack_v2")
VFX = os.path.join(ROOT, "art_source", "incoming", "battle_vfx_pack", "godot", "assets", "ai", "vfx")
SCENERY = os.path.join(ROOT, "godot", "assets", "scenery")
TEXTURES = os.path.join(ROOT, "godot", "assets", "textures")
VFX_OUT = os.path.join(ROOT, "godot", "assets", "vfx")

# sheet -> {slice index (row-major, 1-based): output name}; slices not listed are dropped
PROPS = {
    "balustrade": {1: "balustrade_long", 2: "pillar", 3: "pillar_flowers", 4: "balustrade_planter",
                   5: "stone_bench", 6: "stone_stairs"},
    "banners": {1: "banner_red", 2: "banner_blue", 3: "bunting", 4: "ribbons", 5: "flag_white",
                6: "curtain_blue", 7: "bamboo_blind", 8: "paper_tags"},
    "boats": {1: "boat_house", 2: "boat_small", 3: "boat_fishing"},
    "bridges": {2: "bridge_stone", 4: "bridge_wood"},
    "building_parts": {2: "pillar_blossom", 3: "eave_roof", 5: "window_flowers", 7: "door_red",
                       9: "door_wood", 11: "signboard", 13: "railing_wood", 15: "stone_steps",
                       17: "blind_bamboo", 19: "roof_ornament"},
    "cargo": {1: "jars", 2: "water_vat", 3: "barrels", 4: "veg_crate", 5: "sacks", 6: "baskets",
              7: "rope", 8: "cart_wheel", 9: "firewood", 10: "fish_rack"},
    "dock": {1: "post", 2: "pier_stand", 3: "net_rack", 4: "fish_basket", 5: "fishing_rod",
             6: "crates_cloth", 7: "signpost", 8: "boat_hull"},
    "gate_paifang": {1: "gate_paifang"},
    "lantern_strings_day": {1: "lanterns_day_red", 2: "lanterns_day_white", 3: "lanterns_day_orange",
                            4: "lanterns_day_charms"},
    "lantern_strings_night": {1: "lanterns_night_a", 2: "lanterns_night_b", 3: "lanterns_night_c",
                              4: "lanterns_night_d"},
    "parasols": {1: "parasol_plain", 2: "parasol_red", 3: "parasol_blue", 4: "parasol_green",
                 5: "parasol_lantern", 6: "parasol_torn"},
    "riverside": {1: "reeds_pampas", 2: "cattails", 3: "lotus", 4: "rock_moss", 5: "rock_grass",
                  6: "stones_water", 7: "rock_fern", 8: "stepping_stones", 9: "log_float",
                  10: "bamboo_raft", 11: "fence_bank", 12: "ducks"},
    "sect_props": {1: "lion_left", 2: "lion_right", 3: "incense_burner", 4: "stele",
                   5: "stone_lantern_a", 6: "stone_lantern_b", 7: "weapon_rack", 8: "wooden_dummy",
                   9: "drum", 10: "scroll_stand", 11: "lotus_pond", 12: "altar_table"},
    "stalls": {1: "stall_pottery", 2: "stall_fruit", 3: "stall_cloth", 4: "stall_meat",
               5: "stall_books", 6: "stall_plants"},
    "trees_extra": {1: "tree_maple_red", 3: "tree_ginkgo", 4: "tree_sakura", 7: "tree_pine_bonsai",
                    9: "tree_maple_twisted", 10: "tree_orange"},
    "village": {1: "laundry", 2: "fountain", 3: "chrysanthemum_pot", 4: "corn_chili", 5: "bench_wood",
                6: "millstone", 7: "cat", 8: "shrine", 9: "woodshed", 10: "ladder", 11: "birdcage",
                12: "clay_oven"},
}

TERRAIN = ["tex_cliff_rock", "tex_flagstone_large", "tex_flagstone_wet", "tex_riverbank_mud",
           "tex_stone_wall_mossy", "tex_wood_pier"]

MAGENTA_VFX = ["tile_arrows", "tile_highlights", "vfx_dust", "vfx_ink_banners"]


def slice_sheet(im):
    """Connected components of the alpha channel, ordered row-major."""
    a = np.array(im)[:, :, 3] > 24
    lab, _ = ndi.label(ndi.binary_dilation(a, iterations=6))
    boxes = []
    for i, sl in enumerate(ndi.find_objects(lab)):
        m = (lab[sl] == i + 1) & a[sl]
        if m.sum() < 120:
            continue
        ys, xs = np.where(m)
        boxes.append((sl[0].start + ys.min(), sl[1].start + xs.min(),
                      sl[0].start + ys.max() + 1, sl[1].start + xs.max() + 1))
    boxes.sort(key=lambda b: (b[0] + b[2]) / 2)
    rows = []
    for b in boxes:
        cy = (b[0] + b[2]) / 2
        if rows and abs(cy - rows[-1][0]) < 0.6 * (b[2] - b[0]) + 30:
            rows[-1][1].append(b)
        else:
            rows.append([cy, [b]])
    return [b for _, r in rows for b in sorted(r, key=lambda b: b[1])]


def key_magenta(im):
    arr = np.array(im.convert("RGBA")).astype(np.int32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    mag = (r > 170) & (b > 170) & (g < 110)
    # soft edge: neighbours of keyed pixels that lean magenta get their spill removed
    spill = ((r + b) // 2 - g > 60) & ndi.binary_dilation(mag, iterations=2)
    arr[mag | spill, 3] = 0
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def black_to_alpha(im):
    arr = np.array(im.convert("RGB")).astype(np.float32)
    alpha = arr.max(axis=2)
    safe = np.maximum(alpha, 1.0)[:, :, None]
    rgb = np.clip(arr / safe * 255.0, 0, 255)
    out = np.dstack([rgb, alpha]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def main():
    for d in (SCENERY, TEXTURES, VFX_OUT):
        os.makedirs(d, exist_ok=True)
    for sheet, names in PROPS.items():
        im = Image.open(os.path.join(TOWN, "transparent", "prop_%s.png" % sheet)).convert("RGBA")
        boxes = slice_sheet(im)
        for idx, name in names.items():
            y0, x0, y1, x1 = boxes[idx - 1]
            im.crop((x0, y0, x1, y1)).save(os.path.join(SCENERY, "town_%s.png" % name))
        print("props", sheet, len(names))
    for t in TERRAIN:
        Image.open(os.path.join(TOWN, "godot", "assets", "ai", "terrain", t + ".png")).convert("RGBA").save(
            os.path.join(TEXTURES, t + ".png"))
    src = os.path.join(TOWN, "godot", "assets", "ai")
    Image.open(os.path.join(src, "bg_night_mountains.png")).convert("RGBA").save(
        os.path.join(SCENERY, "bg_night_mountains.png"))
    key_magenta(Image.open(os.path.join(src, "bg_rooftops.png"))).save(os.path.join(SCENERY, "bg_rooftops.png"))
    for f in sorted(glob.glob(os.path.join(VFX, "*.png"))):
        name = os.path.splitext(os.path.basename(f))[0]
        im = Image.open(f)
        out = key_magenta(im) if name in MAGENTA_VFX else black_to_alpha(im)
        out.save(os.path.join(VFX_OUT, name + ".png"))
        print("vfx", name, out.size)


if __name__ == "__main__":
    main()
