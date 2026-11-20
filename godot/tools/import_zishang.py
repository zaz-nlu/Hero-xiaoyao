"""导入紫殇的角色图（Downloads 里的两张图）：
  - 紫殇四视图像素小人.png 是一张设定图，右下角的“像素·四方向”依次为 正面 / 右 / 背面 / 左，
    这里裁出这一块、去掉纸色底和脚下阴影，重排成游戏用的 正/背/左/右，再交给 build_ai_sheets 合成精灵表；
  - 紫殇立绘.png 用 import_opening_pack 的立绘流程生成对话立绘。
用法：py -3 godot/tools/import_zishang.py [设定图] [立绘图]
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_ai_sheets
import import_opening_pack as pack

HOME = os.path.expanduser("~")
SHEET = os.path.join(HOME, "Downloads", "紫殇四视图像素小人.png")
ART = os.path.join(HOME, "Downloads", "紫殇立绘.png")
CROP = (1010, 610, 1536, 750)   # 设定图中“像素·四方向”那一块（原图 1536×1024）
SHADOW_ROW = 119   # 裁切块内阴影开始的行
SOURCE_ORDER = ("front", "right", "back", "left")
FW, FH = 32, 48


def main():
    sheet = sys.argv[1] if len(sys.argv) > 1 else SHEET
    art = sys.argv[2] if len(sys.argv) > 2 else ART
    arr = np.array(Image.open(sheet).convert("RGB").crop(CROP))
    bg, _ = pack.flood_background(arr, tol=34)
    mask = ndimage.binary_opening(~bg, iterations=1)
    # 脚下的灰色椭圆阴影：只在最底部几行里去掉低饱和的灰色（头发也是暗色低饱和，不能全图去）。
    gray = (arr.max(axis=2).astype(int) - arr.min(axis=2).astype(int) < 28) & (arr.max(axis=2) < 170)
    rows = np.arange(arr.shape[0])[:, None] >= SHADOW_ROW
    mask &= ~(gray & rows)
    spans = pack.split_views(mask)
    views = [pack.cut_view(arr, mask, x0, x1) for x0, x1 in spans]
    if any(v is None for v in views) or len(views) != 4:
        sys.exit("无法切出四个视角")
    by_name = dict(zip(SOURCE_ORDER, views))
    ordered = [by_name[n] for n in ("front", "back", "left", "right")]
    max_h = max(v.height for v in ordered)
    max_w = max(v.width for v in ordered)
    scale = min(46.0 / max_h, 30.0 / max_w)
    strip = Image.new("RGBA", (FW * 4, FH), (0, 0, 0, 0))
    for i, v in enumerate(ordered):
        w, h = max(1, round(v.width * scale)), max(1, round(v.height * scale))
        small = v.resize((w, h), Image.LANCZOS)
        small.putalpha(small.getchannel("A").point(lambda p: 255 if p > 110 else 0))
        frame = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
        frame.paste(small, ((FW - w) // 2, FH - 1 - h), small)
        strip.paste(frame, (i * FW, 0))
    tmp = os.environ.get("TEMP", ".")
    strip_file = os.path.join(tmp, "zishang_idle_32x48_alpha.png")
    strip.save(strip_file)
    build_ai_sheets.build("zishang", strip_file)
    pack.import_portrait("zishang", art)
    print("done: sprite + portrait for zishang")


if __name__ == "__main__":
    main()
