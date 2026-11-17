武侠古镇角色四方向待机图集 / Wuxia HD-2D field sprites

包含角色：任逍遥、紫霞、紫霞弟子、包子摊老板、马友为、马匪。

每位角色目录：
- *_source_2048x768.png: AI 原始高清像素绘制图（洋红背景）
- *_idle_32x48_magenta.png: 128x48 整张四方向图集（4 列，每格 32x48）
- *_idle_32x48_alpha.png: 同规格透明背景 PNG
- *_front/back/left/right_32x48_alpha.png: 独立方向透明 PNG
- *_idle_preview_8x.png: 最近邻放大 8 倍预览

方向顺序：front / back / left / right（正、背、左、右），各 1 帧站立待机。

Godot 导入：
- 在项目中将 godot/assets/ai/characters 拷贝到 res://assets/ai/characters/。
- CanvasItem texture_filter 设为 Nearest，避免像素模糊。
- 128x48 图集以 hframes=4，vframes=1 使用；每帧 32x48。
- 目前没有行走动画，这只是每方向单帧待机图；后续需要绘制独立步行帧。
- AI 输出经最近邻缩至真实 32×48 单元格，并用色键阈值提取透明。细节/配色/边缘可能需要逐帧人工像素修整。
- 该文件夹是在当前工作区制作，并没有自动写入你本机的 Godot 项目。
