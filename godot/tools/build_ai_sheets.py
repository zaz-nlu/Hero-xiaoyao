"""Build in-game sprite sheets (160x192: rows down/up/right/left, cols idle + 4 walk)
from the AI turnaround strips (128x48: front, back, left, right).

Usage (from the repo root):
    python godot/tools/build_ai_sheets.py <strip_dir> [id=file_prefix ...]

With no id=file_prefix arguments, the default mappings are:
    zixia, zixia_disciple, vendor=baozi_vendor, ma_youwei, bandit

Each strip is <strip_dir>/<prefix>_idle_32x48_alpha.png. The older
<strip_dir>/<prefix>/<prefix>_idle_32x48_alpha.png layout (one directory per
character, used by the five-character packs) is also accepted; the flat file wins.
Example:
    python godot/tools/build_ai_sheets.py art_source/inputs/character_sheets
    python godot/tools/build_ai_sheets.py art_source/inputs/npc_strips smith=smith
Steps: despill magenta fringe -> split 4 views -> synthesize walk frames -> save
godot/assets/sprites/<id>.png
"""
import os
import sys
import colorsys
from PIL import Image

FW, FH = 32, 48
LEG_Y = 38
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")

DEFAULT = {
    "zixia": "zixia",
    "zixia_disciple": "zixia_disciple",
    "vendor": "baozi_vendor",
    "ma_youwei": "ma_youwei",
    "bandit": "bandit",
}


def magenta_amount(p):
    r, g, b = p[0], p[1], p[2]
    return (r + b) / 2.0 - g


def despill(im):
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size

    def neighbours(x, y):
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx or dy:
                    yield x + dx, y + dy

    def opaque(x, y):
        return 0 <= x < w and 0 <= y < h and px[x, y][3] > 0

    def is_spill(x, y):
        p = px[x, y]
        if p[3] == 0:
            return False
        m = magenta_amount(p)
        edge = any(not opaque(a, b) for a, b in neighbours(x, y))
        strong = m > 70 and p[1] < 0.4 * min(p[0], p[2])
        return (edge and m > 30) or strong

    for _ in range(3):
        changes = {}
        for y in range(h):
            for x in range(w):
                if not is_spill(x, y):
                    continue
                good = [px[a, b] for a, b in neighbours(x, y)
                        if opaque(a, b) and magenta_amount(px[a, b]) <= 15]
                if good:
                    rs = sum(c[0] for c in good) // len(good)
                    gs = sum(c[1] for c in good) // len(good)
                    bs = sum(c[2] for c in good) // len(good)
                    changes[(x, y)] = (rs, gs, bs, 255)
                else:
                    # only magenta neighbours: fringe pixel on the silhouette -> drop it
                    edge = any(not opaque(a, b) for a, b in neighbours(x, y))
                    if edge and magenta_amount(px[x, y]) > 60:
                        changes[(x, y)] = (0, 0, 0, 0)
        for k, v in changes.items():
            px[k] = v
    return im


def make_walk(idle, side):
    def compose(step):
        upper = idle.crop((0, 0, FW, LEG_Y))
        legs = idle.crop((0, LEG_Y, FW, FH))
        out = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
        out.paste(upper, (0, -1), upper)
        lh = legs.crop((0, 0, 16, FH - LEG_Y))
        rh = legs.crop((16, 0, 32, FH - LEG_Y))
        if side:
            out.paste(lh, (0 - step, LEG_Y), lh)
            out.paste(rh, (16 + step, LEG_Y), rh)
        elif step > 0:
            out.paste(lh, (0, LEG_Y), lh)
            out.paste(rh, (16, LEG_Y - 1), rh)
        else:
            out.paste(lh, (0, LEG_Y - 1), lh)
            out.paste(rh, (16, LEG_Y), rh)
        return out

    return [idle, compose(1), idle, compose(-1), idle]


def build(game_id, strip_path):
    src = despill(Image.open(strip_path))
    front = src.crop((0, 0, 32, 48))
    back = src.crop((32, 0, 64, 48))
    left = src.crop((64, 0, 96, 48))
    right = src.crop((96, 0, 128, 48))
    sheet = Image.new("RGBA", (FW * 5, FH * 4), (0, 0, 0, 0))
    for r, (img, side) in enumerate([(front, False), (back, False), (right, True), (left, True)]):
        for c, f in enumerate(make_walk(img, side)):
            sheet.paste(f, (c * FW, r * FH))
    out = os.path.join(OUT_DIR, game_id + ".png")
    sheet.save(out)
    print("wrote", os.path.normpath(out))


def strip_path(strip_dir, prefix):
    flat = os.path.join(strip_dir, prefix + "_idle_32x48_alpha.png")
    if os.path.exists(flat):
        return flat
    return os.path.join(strip_dir, prefix, prefix + "_idle_32x48_alpha.png")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    strip_dir = sys.argv[1]
    mapping = {} if len(sys.argv) > 2 else DEFAULT
    for arg in sys.argv[2:]:
        k, v = arg.split("=")
        mapping[k] = v
    for game_id, prefix in mapping.items():
        path = strip_path(strip_dir, prefix)
        build(game_id, path)


if __name__ == "__main__":
    main()
