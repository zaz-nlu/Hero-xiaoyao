# 《英雄传》百年前序幕完整追加包（更新版）

内容：第一批14张（战场8张+三人四视图3张+立绘3张），新增4张（魔族士兵、妖族虎人、精灵弓手、茶棚道具），以及帝王世纪特效图1张和分类条带6张。**不包含 opening_emperor.png**（按照要求删除帝王威仪场景）。

## 帝王世纪
- emperor_century_vfx_full_sheet.png：全套原始特效，保留完整构图
- slash_arc_sequence.png：金色刀刃切割弧线
- auto_cut_sequence.png：自动连续切割/斩击线
- domain_expansion_sequence.png：领域展开的金色同心环和穹顶
- gravity_crack_sequence.png：重力压裂地面
- gravity_floating_rocks_sequence.png：重力失衡的碎石悬浮
- gravity_impact_sequence.png：重力压制冲击效果

特效条带均由一张组合图直接按行裁切，**并非严格等宽、逐帧定格的动画序列**；需要根据画面内容二次裁切/重排为帧图集，或使用其中元素以 Tween、Shader、GPUParticles2D 和 Add/Mix 混合方式组合演出。原素材部分像素已带透明通道，建议按最终显示效果检查边缘。

注意：早期战场素材和三人立绘仍保留其初版限制；茶棚为组合裁切稿，请检查透明背景后再用于正式游戏。像素四视图以角色外观参考为主，不保证已经能直接交给 build_ai_sheets.py 自动识别帧边界。
