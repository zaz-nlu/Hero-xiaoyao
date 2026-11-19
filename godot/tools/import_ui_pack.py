"""Imports the tactics HUD art pack: scales frames/bars to their in-game display size.

Run from the repo root:  py -3 godot/tools/import_ui_pack.py [pack_dir]
pack_dir defaults to the unzipped pack at art_source/incoming/ui_batch_01/ui/godot/assets/ai/ui.
Originals stay in art_source/incoming/ui_batch_01 (zip); the runtime copies live in
godot/assets/ui/tactics together with layout.json (display sizes + nine-patch margins).
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "godot", "assets", "ui", "tactics")
DEFAULT_SRC = os.path.join(ROOT, "art_source", "incoming", "ui_batch_01", "ui", "godot", "assets", "ai", "ui")

# file -> (display width, height); nine-patch margins are the pack's recommendation scaled by the same factor.
SCALED = {
    "turn_card.png": ((84, 98), (20, 22), (112, 128)),
    "turn_card_active.png": ((84, 98), (20, 22), (112, 128)),
    "skill_button.png": ((64, 64), (18, 18), (128, 128)),
    "skill_button_selected.png": ((64, 64), (18, 18), (128, 128)),
    "skill_button_disabled.png": ((64, 64), (18, 18), (128, 128)),
    "unit_card.png": ((300, 185), (38, 30), (520, 320)),
    "panel_frame.png": ((340, 170), (30, 24), (512, 256)),
    "panel_frame_wood_filled.png": ((340, 170), (30, 24), (512, 256)),
    "bar_hp.png": ((160, 15), (12, 6), (256, 24)),
    "bar_hp_bg.png": ((160, 15), (12, 6), (256, 24)),
    "bar_toughness.png": ((160, 10), (12, 4), (256, 16)),
}


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    os.makedirs(OUT, exist_ok=True)
    layout = {}
    for name in sorted(os.listdir(src)):
        if not name.endswith(".png"):
            continue
        im = Image.open(os.path.join(src, name)).convert("RGBA")
        if name in SCALED:
            (w, h), (ml, mt), (sw, sh) = SCALED[name]
            fx, fy = w / sw, h / sh
            im = im.resize((w, h), Image.LANCZOS)
            layout[name] = {
                "size": [w, h],
                "margins": {"left": round(ml * fx), "right": round(ml * fx),
                            "top": round(mt * fy), "bottom": round(mt * fy)},
            }
        else:
            layout[name] = {"size": list(im.size)}
        im.save(os.path.join(OUT, name), optimize=True)
        print("wrote", name, im.size)
    with open(os.path.join(OUT, "layout.json"), "w", encoding="utf-8") as fh:
        json.dump(layout, fh, ensure_ascii=False, indent=1)
    print("layout.json written")


if __name__ == "__main__":
    main()
