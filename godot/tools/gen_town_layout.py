"""Regenerate the layout part of godot/data/town.json (terraces, ground, buildings,
NPC positions, props, border, camera clamp, forest, unlock zones).

Usage (from the repo root):
    python godot/tools/gen_town_layout.py

It reads the current godot/data/town.json and keeps everything that is not layout
(building kinds/signs, NPC ids/sprites/wander settings, pickup definitions, stall text);
positions, props and zone data are rewritten from the tables below, so it is idempotent.
Buildings may carry `facade` (PNG in godot/assets/scenery/), `plaque` ([fx, fy] of the
plaque center in the facade image) and `plaque_w` (plaque width as a facade fraction);
the EXTRAS table below sets them together with the layout.
Edit the tables here (or tweak town.json by hand for one-off nudges), run it, then run
`npm run check`. Sprite sizes come from the aspect ratio of godot/assets/scenery/town_*.png.
Requires: Pillow.
"""
import json, copy, os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
old = json.load(open(ROOT + "/data/town.json", encoding="utf-8"))
SC = ROOT + "/assets/scenery/"

def aspect(name):
    im = Image.open(SC + "town_%s.png" % name)
    return im.width / im.height

props = []

def spr(name, x, z, h=None, w=None, collide=None, phase=None, flip=False, y=None, lift=None, light=False):
    a = aspect(name)
    if h is None:
        h = w / a
    p = {"kind": "sprite", "sprite": "town_%s.png" % name, "x": round(x, 2), "z": round(z, 2), "height": round(h, 2)}
    if collide: p["collide"] = collide
    if phase: p["phase"] = phase
    if flip: p["flip"] = True
    if y is not None: p["y"] = y
    if lift: p["lift"] = lift
    if light: p["light"] = True
    props.append(p)

def old_kind(kind, x, z, **kw):
    p = {"kind": kind, "x": round(x, 2), "z": round(z, 2)}
    p.update(kw)
    props.append(p)

# ---------------- bounds / ground ----------------
X0, X1, Z0, Z1 = -30, 30, -27, 19
data = {}
data["bounds"] = {"x0": X0, "x1": X1, "z0": Z0, "z1": Z1}
data["spawn"] = {"x": -6.0, "z": -2.0, "facing": "right"}
data["ground"] = [
    {"type": "grass", "rect": [-90, -60, 90, 70]},
    {"type": "flagstone", "rect": [X0, -5.2, X1, 1.0]},
    {"type": "mud", "rect": [X0, 1.0, X1, 2.2]},
    {"type": "water", "rect": [X0, 2.2, X1, 5.6]},
    {"type": "mud", "rect": [X0, 5.6, X1, 6.6]},
    {"type": "pier", "rect": [-28, 5.6, -13, 9.2]},
    {"type": "flagstone", "rect": [8, 6.6, 28, 12]},
    {"type": "flagstone", "rect": [-9, 8, -3, 12.5]},
    {"type": "stone", "rect": [-3, 6.6, 3, Z1]},
]
data["bridges"] = [
    {"x0": -2.5, "x1": 2.5, "z0": 2.2, "z1": 5.6},
    {"x0": -20, "x1": -16, "z0": 2.2, "z1": 5.6},
]
data["terraces"] = [
    {"rect": [X0, -20, X1, -10], "y": 1.5, "top": "flagstone", "from_y": 0.0,
     "stairs": [{"x0": -3.0, "x1": 3.0}]},
    {"rect": [-10, Z0, 10, -20], "y": 3.0, "top": "flagstone", "from_y": 1.5,
     "stairs": [{"x0": -2.5, "x1": 2.5}]},
]
data["camera_clamp"] = [-12, -18, 12, 10]
data["border"] = {"sides": ["west", "east"], "depth": 14.0, "spacing": 3.2, "seed": 7, "files": ["prop_willow.png", "town_tree_pine_bonsai.png", "town_tree_ginkgo.png", "town_tree_maple_red.png"], "height": [5.0, 8.0]}
data["forest"] = {"sign": [4.8, 16.2], "return": [0.0, 15.0], "exit_rect": [-4.0, 17.2, 8.0, 1.6]}
data["unlock_zones"] = [{"id": "west_street", "x_lt": -22.0}, {"id": "gate", "z_lt": -19.0}]

# ---------------- buildings ----------------
B = {b["id"]: b for b in old["buildings"]}
# facade: 立面文件名；plaque: [fx, fy] 木匾中心在立面图中的比例；sign 由游戏叠加。
EXTRAS = {
    "smith": ("facade_smithy.png", "铁", [0.56, 0.46]),
    "shop": ("facade_grocery.png", "杂", [0.50, 0.43]),
    "herb_shop": ("facade_herb_shop.png", "药", [0.50, 0.60]),
    "tailor_shop": ("facade_tailor.png", "布", [0.48, 0.62]),
    "house_w": ("facade_house_narrow.png", None, None),
    "house_w3": ("facade_house_thatch.png", None, None),
    "house_e2": ("facade_courtyard.png", None, None),
    "house_e1": ("facade_pavilion.png", "楼", [0.50, 0.66]),
}
def place(bid, x0, x1, zf, depth, door_x=None):
    b = copy.deepcopy(B[bid])
    for key in ("facade", "plaque", "plaque_w"):
        b.pop(key, None)
    b.update({"x0": x0, "x1": x1, "z_front": zf, "depth": depth, "door_x": door_x if door_x is not None else (x0 + x1) / 2})
    if bid in EXTRAS:
        facade, sign, plaque = EXTRAS[bid]
        b["facade"] = facade
        if sign is not None:
            b["sign"] = sign
            b["plaque"] = plaque
    return b
blds = [
    # 第一排：z_front 前后错开，中间留出 T2 台阶通道（x -3..3）。
    place("house_w", -29, -24, -5.8, 3),
    place("smith", -22, -13.5, -4.6, 3),
    place("shop", -11.5, -3.5, -5.4, 3),
    place("tavern", 5, 17, -5, 3, 11.0),
    place("house_e1", 19, 27, -6.4, 3),
    # 第二排：在 T2 台地上，同样前后错开，避开 T1/T3 台阶与桥。
    place("herb_shop", -29, -21, -12.2, 4),
    place("tailor_shop", -18.5, -10.5, -13.6, 4),
    place("house_w3", -8, -1.5, -12.8, 4),
    place("house_e2", 5.5, 14.2, -12.4, 4),
    place("house_w2", 15, 22, -14.2, 4),
]
data["buildings"] = blds

# ---------------- NPCs ----------------
POS = {
    "bun_vendor": (22.0, 7.6), "disciple": (18.5, 7.6), "smith": (-16.5, -3.6),
    "shopkeeper_f": (-8.0, -3.6), "waiter": (7.0, -3.6), "grandmother": (21.5, -3.6),
    "guard": (4.0, -22.0), "scholar": (8.0, 0.5), "hunter": (-4.5, 14.0),
    "fisherman": (-20.5, 7.8), "girl": (-6.0, 10.4), "townswoman": (-25.5, -3.6),
    "elder": (-7.0, -11.8), "peddler": (-22.0, -1.0), "shopkeeper_m": (8.5, -11.1),
    "herbalist": (-25.0, -10.9), "tailor": (-14.5, -12.3), "villager_1": (-27.5, 0.2),
    "villager_2": (2.5, -3.8), "villager_3": (-10.5, 12.8), "villager_4": (26.5, -1.0),
}
npcs = []
for n in old["npcs"]:
    n = copy.deepcopy(n)
    nx, nz = POS[n["id"]]
    dx, dz = nx - n["x"], nz - n["z"]
    n["x"], n["z"] = nx, nz
    w = n.get("wander")
    if w:
        w["route"] = [[round(px + dx, 2), round(pz + dz, 2)] for px, pz in w["route"]]
    npcs.append(n)
data["npcs"] = npcs

# pickups
pk = copy.deepcopy(old["pickups"])
pk[0]["x"], pk[0]["z"] = 10.5, 14.2
data["pickups"] = pk

# ---------------- props ----------------
# street furniture
for x in (-27, -15, -1.2, 3.2, 19.5, 27.5):
    old_kind("lamp_post", x, 0.4)
old_kind("barrel", -21.5, -4.2); old_kind("crate", -11.8, -4.0); old_kind("jars", -9.0, -4.3)
old_kind("barrel", -4.4, -4.1); old_kind("baskets", 18.6, -4.2)
old_kind("bench", 14.6, -1.6); old_kind("bench", -12.5, 0.0)
old_kind("notice_board", -3.5, -3.6)
old_kind("well", 26.8, -3.4)
old_kind("cart", -23.5, -0.2, rot=0.3)
spr("parasol_red", 13.0, -3.0, h=2.6)
spr("parasol_plain", 16.2, -3.4, h=2.4)
spr("banner_red", 4.2, -3.9, h=3.2)
spr("banner_blue", 17.8, -3.9, h=3.2)
spr("lanterns_day_red", 0.0, -2.0, w=12, phase="day")
spr("lanterns_night_a", 0.0, -2.0, w=12, phase="night")
spr("lanterns_day_orange", -18.0, -2.0, w=12, phase="day")
spr("lanterns_night_b", -18.0, -2.0, w=12, phase="night")

# alleys between the staggered front-row houses
spr("firewood", -23.0, -5.2, h=0.9)
spr("ladder", -11.9, -5.6, h=2.2)
spr("barrels", -2.6, -4.8, h=1.1)
spr("baskets", 18.2, -5.4, h=0.8)
spr("railing_wood", 28.2, -5.4, h=1.0)
spr("chrysanthemum_pot", 3.4, -4.6, h=0.9)

# riverside
for x, z in ((-27, 1.6), (-9, 1.5), (7, 1.7), (24, 1.5)):
    spr("reeds_pampas", x, z, h=1.9)
for x, z in ((-12, 1.6), (11, 1.5), (28, 1.7)):
    spr("cattails", x, z, h=1.6)
spr("lotus", -9.5, 3.9, h=0.7); spr("lotus", 9.0, 3.6, h=0.7); spr("lotus", 20.0, 4.0, h=0.6)
spr("ducks", 6.0, 4.4, h=0.5); spr("ducks", -13.0, 3.6, h=0.5, flip=True)
spr("rock_moss", -29.0, 1.8, h=1.6); spr("rock_grass", 29.0, 1.6, h=1.5)
spr("stepping_stones", 12.0, 4.0, h=0.35)
spr("boat_house", -25.0, 3.9, h=2.2)
spr("boat_small", 10.5, 4.7, h=0.9)
spr("boat_fishing", 18.5, 4.4, h=1.7)
spr("bamboo_raft", 24.5, 3.4, h=0.7)

# west dock
spr("post", -28.0, 6.2, h=2.0); spr("post", -13.6, 6.2, h=2.0)
spr("net_rack", -22.5, 8.0, h=2.2, collide=[2.4, 0.8])
spr("fish_basket", -17.5, 7.8, h=0.9)
spr("fishing_rod", -15.0, 6.4, h=1.6)
spr("crates_cloth", -26.0, 8.0, h=1.5, collide=[1.8, 1.0])
spr("signpost", -13.8, 8.6, h=1.6)
spr("jars", -24.2, 6.6, h=1.0) if False else None
spr("sacks", -19.5, 6.4, h=1.0)
spr("firewood", -26.3, 6.2, h=0.9)
old_kind("barrel", -16.0, 8.6)
spr("boat_hull", -21.0, 9.0, h=1.0)

# east market
spr("stall_pottery", 11.5, 9.4, h=3.4, collide=[3.6, 1.6])
spr("stall_fruit", 15.5, 9.4, h=3.4, collide=[3.6, 1.6])
spr("stall_cloth", 25.5, 9.4, h=3.4, collide=[3.6, 1.6])
spr("stall_plants", 12.0, 12.4, h=3.2, collide=[3.6, 1.6]) if False else None
old_kind("stall", 22.0, 8.9, w=4.0, d=2.0, text=([b for b in old["props"] if b["kind"] == "stall"] or [{}])[0].get("text", "包子"))
spr("parasol_blue", 17.5, 11.0, h=2.5)
spr("parasol_green", 23.0, 11.2, h=2.4)
spr("veg_crate", 19.2, 9.6, h=0.9)
spr("water_vat", 27.0, 7.2, h=1.4)
spr("corn_chili", 20.2, 7.2, h=1.5) if False else None

# village plaza (south centre-west)
spr("fountain", -6.0, 9.6, h=1.5, collide=[2.2, 1.2])
spr("bench_wood", -7.0, 12.0, h=0.9, collide=[1.8, 0.7])
spr("cat", -4.6, 11.7, h=0.5)
spr("chrysanthemum_pot", -8.6, 10.6, h=1.0)
spr("laundry", -9.0, 7.6, h=2.2, collide=[2.4, 0.5])
spr("birdcage", -3.8, 8.0, h=1.9)
spr("millstone", 5.6, 8.0, h=1.0, collide=[1.2, 1.2])
spr("clay_oven", 6.4, 11.0, h=1.5, collide=[1.0, 1.0])
spr("woodshed", 8.0, 13.8, h=2.2, collide=[2.4, 1.0])
spr("rock_fern", 3.8, 14.0, h=1.2)

# forest road side
old_kind("tree", -6.0, 17.0); old_kind("tree", 6.5, 17.8); old_kind("tree", -11.0, 15.5)
old_kind("tree", 12.0, 16.4); old_kind("tree", -18.0, 13.5); old_kind("tree", 20.0, 15.0)
spr("tree_pine_bonsai", -9.0, 5.8, h=2.6) if False else None
old_kind("bamboo", -2.4, 18.0); old_kind("bamboo", 2.6, 18.3)
spr("shrine", 4.6, 6.8, h=2.4, collide=[1.8, 1.0]) if False else None

# T2 garden lane (y comes from terrace height automatically)
for x in (-6.5, 6.5):
    spr("stone_lantern_a" if x < 0 else "stone_lantern_b", x, -11.0, h=2.0, light=True)
spr("tree_sakura", -25.0, -18.0, h=5.5); spr("tree_ginkgo", 26.0, -18.0, h=5.5)
spr("tree_maple_red", -14.5, -18.5, h=5.0); spr("tree_orange", 15.0, -18.5, h=4.6)
spr("tree_pine_bonsai", 22.0, -18.5, h=3.0); spr("tree_maple_twisted", -20.5, -18.5, h=4.6)
spr("chrysanthemum_pot", -4.0, -11.4, h=0.9); spr("chrysanthemum_pot", 4.0, -11.4, h=0.9)
spr("stone_bench", -9.5, -19.2, h=0.7, collide=[2.0, 0.6])
spr("balustrade_long", -6.0, -19.4, h=1.1) if False else None
spr("pillar_flowers", -9.5, -19.0, h=1.4) if False else None
spr("rock_moss", 2.6, -16.8, h=1.4); spr("rock_grass", -9.4, -18.8, h=1.2)

# alleys between the staggered second-row houses
spr("firewood", -19.8, -12.6, h=0.9)
spr("laundry", -19.7, -15.2, h=2.2)
spr("crates_cloth", -9.3, -13.2, h=1.5, collide=[1.4, 0.8])
old_kind("bamboo", -9.2, -16.2)
spr("chrysanthemum_pot", 1.0, -13.2, h=0.9)
old_kind("tree", 0.5, -16.0)
spr("barrels", 14.0, -13.6, h=1.1)
spr("sacks", 14.2, -15.4, h=1.0)
spr("rock_fern", 23.6, -13.4, h=1.2)
spr("fence_bank", 24.2, -15.4, h=1.1)

# T3 sect gate plaza
spr("gate_paifang", 0.0, -25.0, w=14.5, collide=[1.2, 1.0])
spr("lion_left", -4.2, -22.6, h=1.9, collide=[1.4, 1.0]); spr("lion_right", 4.2, -22.6, h=1.9, collide=[1.4, 1.0])
spr("incense_burner", 7.0, -23.0, h=1.9, collide=[1.2, 1.0])
spr("stele", -7.5, -24.0, h=2.4, collide=[1.2, 0.8])
spr("stone_lantern_a", -2.8, -21.0, h=1.9, light=True); spr("stone_lantern_b", 2.8, -21.0, h=1.9, light=True)
spr("weapon_rack", -7.0, -21.6, h=1.8, collide=[2.0, 0.6])
spr("drum", 8.0, -21.4, h=1.9, collide=[1.4, 0.8])
spr("banner_red", -4.0, -24.2, h=3.6); spr("banner_blue", 4.0, -24.2, h=3.6)

import random
rng = random.Random(11)
def free(x, z):
    if -3.8 <= x <= 3.8 and z > 6: return False
    if -28.5 <= x <= -12.5 and 5.5 <= z <= 9.5: return False
    if 7.5 <= x <= 28.5 and 6.5 <= z <= 12.5: return False
    if -10 <= x <= -2 and 7 <= z <= 13: return False
    if 3.5 <= x <= 10 and 6.5 <= z <= 15: return False
    return True
kinds = ["grass_tuft"] * 14 + ["shrub"] * 8 + ["rocks"] * 4 + ["peony", "chrysanthemum", "peony", "chrysanthemum"]
n = 0
while n < len(kinds):
    x = rng.uniform(-29, 29); z = rng.uniform(6.8, 18.6)
    if not free(x, z): continue
    if any(abs(p["x"] - x) < 1.6 and abs(p["z"] - z) < 1.6 for p in props if p): continue
    old_kind(kinds[n], x, z); n += 1
data["props"] = props
data["props"] = [p for p in props if p is not None]
json.dump(data, open(ROOT + "/data/town.json", "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
print("props", len(data["props"]), "npcs", len(data["npcs"]), "buildings", len(data["buildings"]))
