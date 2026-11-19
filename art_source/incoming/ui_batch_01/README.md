# 武侠战棋 HUD 素材完整包（28 项）

`godot/assets/ai/ui/` 包含用户要求的全部 28 张、按原文件名导出的游戏尺寸 PNG，另赠 `panel_frame_wood_filled.png`。

- 第一批 7 张框体：来自单独生成的原始高清图。
- 第二至五批 21 张：从同一张生成图集中逐项裁切，使用最近邻缩放并去除白色棋盘背景。
- 透明 RGBA 背景；横幅不含任何文字。
- `source_art/` 保留初次生成原始图供美术返工；`manifest.json` 记录尺寸与建议 NinePatchRect 边距。

## Godot 使用

框体用 `NinePatchRect` 并自行调节 stretch_margin；不要对整个框体使用普通 TextureRect 拉伸，以免云纹边角失真。人物头像可以放在卡片正面，HP/韧性条推荐用 TextureProgressBar 的纹理层。

**质检说明**：已统一尺寸与透明通道，但半透明抗锯齿边缘与棋盘背景去除可能留下个别像素，需要在目标缩放倍率下检查。九宫格边距是建议值，未做逐像素美术修补。
