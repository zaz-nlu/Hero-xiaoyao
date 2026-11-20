"""帝王世纪特效素材预处理（离线工具，不修改原始 PNG）。

用法（仓库根目录）：

    py -3 godot/tools/prepare_emperor_century_vfx.py [--src godot/assets/vfx]
        [--out godot/assets/vfx/emperor_century] [--gap 6] [--key-lo 0.22 --key-hi 0.60]

做的事：
1. 读取 emperor_century_*_sequence.png 与总览图 emperor_century_vfx_full_sheet.png；
2. 按亮度抠掉素材自带的深色底（原图带半透明深色晕，直接叠加会露出方框）；
3. 在抠色后的透明通道上找连通块，把相隔很近的碎片合并成同一帧（--gap 像素）；
4. 逐个裁切，贴到统一画布上并按锚点对齐，保证播放时视觉中心稳定；
5. 导出单帧 PNG、manifest JSON、以及每张图一张人工复核预览图。

不强行切分：序列图预期 8 帧，识别数量不符时在 manifest 里标记 needs_review 并输出预览；
总览图只导出候选元素（unverified），由人决定是否使用。
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

# 这些图不是等宽 8 帧：每张是不同尺寸元素按行排列（人工核对过原图）。
# 名称: (期望元素数, 锚点, 是否允许按行再拆, 列合并间距)；
# 锚点 center / bottom 决定统一画布里的对齐方式。浮石图里每块石头都是独立元素（人工核对为 12 个）。
SEQUENCES = {
    "domain_expansion": (6, "center", False, 6),
    "slash_arc": (7, "bottom", False, 14),
    "auto_cut": (10, "center", True, 14),
    "gravity_crack": (7, "center", False, 14),
    "gravity_floating_rocks": (12, "bottom", False, 14),
    "gravity_impact": (4, "bottom", False, 14),
}
PREFIX = "emperor_century_"
FULL_SHEET = PREFIX + "vfx_full_sheet.png"
PAD = 4


def smoothstep(lo, hi, x):
    t = np.clip((x - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def key_alpha(rgba, lo, hi):
    """亮度抠像：暗部（深色底/晕）透明，亮部保留；乘上原 alpha。"""
    arr = np.asarray(rgba).astype(np.float32) / 255.0
    lum = arr[..., :3].max(axis=2)
    alpha = arr[..., 3] * smoothstep(lo, hi, lum)
    out = arr.copy()
    out[..., 3] = alpha
    return (out * 255.0 + 0.5).astype(np.uint8)


def find_components(keyed, gap, min_area_ratio=0.02):
    mask = keyed[..., 3] > 20
    if not mask.any():
        return []
    merged = ndimage.binary_dilation(mask, structure=np.ones((3, 3)), iterations=max(1, gap))
    labels, count = ndimage.label(merged)
    boxes = []
    for index in range(1, count + 1):
        ys, xs = np.where((labels == index) & mask)
        if xs.size == 0:
            continue
        boxes.append((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1, int(xs.size)))
    if not boxes:
        return []
    median_area = float(np.median([b[4] for b in boxes]))
    kept = [b for b in boxes if b[4] >= median_area * min_area_ratio]
    kept.sort(key=lambda b: (b[0] + b[2]) / 2.0)
    return kept


def _runs(profile, min_gap, min_len):
    """一维投影里连续非空的区间，间隔小于 min_gap 的合并，短于 min_len 的丢弃。"""
    runs, start = [], None
    for index, value in enumerate(profile):
        if value and start is None:
            start = index
        elif not value and start is not None:
            runs.append([start, index])
            start = None
    if start is not None:
        runs.append([start, len(profile)])
    merged = []
    for run in runs:
        if merged and run[0] - merged[-1][1] < min_gap:
            merged[-1][1] = run[1]
        else:
            merged.append(run)
    return [r for r in merged if r[1] - r[0] >= min_len]


def find_by_projection(keyed, col_gap, row_gap, split_rows, min_len=10):
    """按列投影找元素：元素之间有空白列；允许再按行投影拆分上下排布的元素。"""
    mask = keyed[..., 3] > 28
    columns = mask.sum(axis=0) > 1
    boxes = []
    for x0, x1 in _runs(columns, col_gap, min_len):
        band = mask[:, x0:x1]
        rows = band.sum(axis=1) > 1
        row_runs = _runs(rows, row_gap if split_rows else 10 ** 6, min_len)
        for y0, y1 in row_runs:
            sub = mask[y0:y1, x0:x1]
            xs = np.where(sub.sum(axis=0) > 0)[0]
            ys = np.where(sub.sum(axis=1) > 0)[0]
            if xs.size and ys.size:
                boxes.append((x0 + int(xs.min()), y0 + int(ys.min()),
                              x0 + int(xs.max()) + 1, y0 + int(ys.max()) + 1, int(sub.sum())))
    boxes.sort(key=lambda b: (b[0] + b[2]) / 2.0 + (b[1] + b[3]) * 0.0001)
    return boxes


def crop(keyed, box):
    x0, y0, x1, y1, _ = box
    x0 = max(0, x0 - PAD)
    y0 = max(0, y0 - PAD)
    x1 = min(keyed.shape[1], x1 + PAD)
    y1 = min(keyed.shape[0], y1 + PAD)
    return keyed[y0:y1, x0:x1], (x0, y0, x1, y1)


def to_canvas(frames, anchor):
    width = max(f.shape[1] for f in frames)
    height = max(f.shape[0] for f in frames)
    canvases = []
    for frame in frames:
        canvas = np.zeros((height, width, 4), dtype=np.uint8)
        fx = (width - frame.shape[1]) // 2
        fy = (height - frame.shape[0]) // 2 if anchor == "center" else height - frame.shape[0]
        canvas[fy:fy + frame.shape[0], fx:fx + frame.shape[1]] = frame
        canvases.append(canvas)
    return canvases, width, height


def contact_sheet(images, path, bg=(34, 30, 44)):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not images:
        return
    cell_w = max(i.shape[1] for i in images)
    cell_h = max(i.shape[0] for i in images)
    sheet = Image.new("RGBA", (cell_w * len(images), cell_h), bg + (255,))
    for index, arr in enumerate(images):
        sheet.alpha_composite(Image.fromarray(arr), (index * cell_w, 0))
    sheet.save(path)


def process_sequence(name, expected, anchor, split_rows, col_gap, src_dir, out_dir, args):
    src = os.path.join(src_dir, PREFIX + name + "_sequence.png")
    if not os.path.exists(src):
        return {"name": name, "error": "missing source " + src}
    keyed = key_alpha(Image.open(src).convert("RGBA"), args.key_lo, args.key_hi)
    boxes = find_by_projection(keyed, col_gap, args.row_gap, split_rows)
    frames, rects = [], []
    for box in boxes:
        cropped, rect = crop(keyed, box)
        frames.append(cropped)
        rects.append(rect)
    entry = {"name": name, "anchor": anchor, "expected_frames": expected, "found_frames": len(frames),
             "needs_review": len(frames) != expected, "source": os.path.basename(src)}
    if not frames:
        entry["error"] = "no visible content"
        return entry
    canvases, width, height = to_canvas(frames, anchor)
    entry["canvas"] = [width, height]
    entry["frames"] = []
    for index, canvas in enumerate(canvases):
        file_name = "%s_%02d.png" % (name, index)
        Image.fromarray(canvas).save(os.path.join(out_dir, file_name))
        entry["frames"].append({"file": file_name, "source_rect": list(rects[index])})
    contact_sheet(canvases, os.path.join(args.preview_out, "_preview_%s.png" % name))
    return entry


def process_full_sheet(src_dir, out_dir, args):
    src = os.path.join(src_dir, FULL_SHEET)
    if not os.path.exists(src):
        return {"name": "full_sheet", "error": "missing source"}
    keyed = key_alpha(Image.open(src).convert("RGBA"), args.key_lo, args.key_hi)
    boxes = find_components(keyed, max(args.gap * 3, 18), min_area_ratio=0.08)
    entry = {"name": "full_sheet", "status": "unverified", "needs_review": True, "elements": []}
    previews = []
    for index, box in enumerate(boxes):
        cropped, rect = crop(keyed, box)
        file_name = "full_%02d.png" % index
        Image.fromarray(cropped).save(os.path.join(out_dir, file_name))
        entry["elements"].append({"file": file_name, "source_rect": list(rect)})
        previews.append(cropped)
    contact_sheet(previews[:12], os.path.join(args.preview_out, "_preview_full_sheet.png"))
    return entry


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--src", default="godot/assets/vfx")
    parser.add_argument("--out", default="godot/assets/vfx/emperor_century")
    parser.add_argument("--preview-out", default="art_source/emperor_century_previews", help="人工复核预览图目录（不进游戏资源）")
    parser.add_argument("--gap", type=int, default=6, help="合并碎片的像素间距")
    parser.add_argument("--row-gap", type=int, default=6, help="行方向拆分间距")
    parser.add_argument("--key-lo", type=float, default=0.22)
    parser.add_argument("--key-hi", type=float, default=0.60)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    manifest = {"version": 1, "key": [args.key_lo, args.key_hi], "sequences": {}, "full_sheet": {}}
    for name, (expected, anchor, split_rows, col_gap) in SEQUENCES.items():
        entry = process_sequence(name, expected, anchor, split_rows, col_gap, args.src, args.out, args)
        manifest["sequences"][name] = entry
        flag = "REVIEW" if entry.get("needs_review") or entry.get("error") else "ok"
        print("%-24s frames=%s/%s canvas=%s [%s]" % (
            name, entry.get("found_frames"), expected, entry.get("canvas"), flag))
    manifest["full_sheet"] = process_full_sheet(args.src, args.out, args)
    print("full_sheet elements:", len(manifest["full_sheet"].get("elements", [])), "(unverified)")
    with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
