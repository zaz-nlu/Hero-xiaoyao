# 运行素材

`godot/assets/` 只存放游戏运行素材；原始包、生成工具输入和历史产物在 [art_source/](../../art_source/README.md)，具体位置见下表。

## 目录

| 路径 | 用途 | 读取方式 |
| --- | --- | --- |
| `scenery/` | 建筑立面、场景道具、树木植被、酒馆家具、宝箱/采集物等非贴图素材 | `shared/resources/ai_assets.gd` 按文件名用 `Image.load_from_file` 读取并缓存 |
| `textures/` | `tex_*.png` 地表、墙面等平铺材质 | 同上；`ai_assets.gd` 按 `tex_` 前缀定位 |
| `icons/` | `icon_*.png` 界面图标 | `ai_assets.gd` 读取，`shared/ui/icon_lib.gd` 映射 |
| `sprites/` | 角色图集（`shared/scene/character_sprite.gd` 按 5×4 帧切分） | `shared/resources/image_cache.gd` + `shared/resources/asset_paths.gd` |
| `portraits/` | 对话立绘 | `shared/resources/image_cache.gd`；路径来自 `data/speakers.json` |
| `audio/` | WAV 音乐与音效 | `shared/audio/audio_loader.gd` 直接解析 PCM 字节并缓存 |
| `fonts/` | 界面/招牌字体（TTF） | `shared/scenery/town/town_fonts.gd` 用 `FontFile.load_dynamic_font` 读取原始文件 |
| `ui/world/` | 世界内界面图标，如头顶任务标记徽章 | `shared/scenery/town/town_marker_icons.gd` 用 `Image.load_from_file` 读取 |

素材生成工具读取的原始包、接触表、图集和中间条带在 `art_source/inputs/`（角色包、森林包、NPC 包、图标包、预览条等），不放在本目录；不要把它们当作运行素材。目录与来源见 [art_source/README.md](../../art_source/README.md)。

## 命名

运行素材统一用 snake_case，例如 `facade_tavern.png`、`prop_willow.png`、`icon_item_herbs.png`、`ren_xiaoyao.png`、`sfx_hit.wav`。目录按文件名前缀分流：`textures/` 用 `tex_`，`icons/` 用 `icon_`，其余场景素材放 `scenery/`；角色图集、立绘和音频使用各自文件名。

新增界面图标沿用 `shared/ui/icon_lib.gd` 的规则，放进 `icons/`：

- 武学：`icon_martial_<id>.png`
- 物品：`icon_item_<id>.png`；个别特例写在 `ITEM_FILES` 映射里
- 属性：`icon_stat_<stat>.png`

新图标需要同时在 `icon_lib.gd` 中补映射或确认默认命名能命中，不要改读取顺序。

## 字体与任务标记图标

- `fonts/MaShanZheng-Regular.ttf`：马善政毛笔字（Ma Shan Zheng），用于小镇门楣木匾等招牌文字。
  许可证为 SIL Open Font License 1.1（OFL-1.1），可随游戏分发；修改或再分发时保留许可证与保留字体名。
  该 TTF 未经过 Godot 导入，`shared/scenery/town/town_fonts.gd` 用 `FontFile.load_dynamic_font` 直接读取原始文件，
  不要改成 `load()`/`preload()`。
- `ui/world/quest_available.png`（红底金边“!”）、`ui/world/quest_ready.png`（青底金边“?”）、
  `ui/world/quest_active.png`（灰底“…”）：128×128 透明底，作为 NPC 头顶任务标记徽章。
  `shared/scenery/town/town_marker_icons.gd` 按标记文字 `"!"` / `"?"` / `"…"` 映射并用 `Image.load_from_file`
  读取缓存；空串表示不显示标记。

## 战棋打击音效

- `audio/sfx_parry.wav`（完美破招）、`sfx_parry_soft.wav`（普通反制）、`sfx_block.wav`（格挡）、`sfx_weak.wav`（弱点，预留）、`sfx_break.wav`（破势）：战棋打击反馈音效。
- 生成：`py -3 godot/tools/make_battle_sfx.py`（复用 `make_music.py` 的合成辅助，输出到 `assets/audio/`，重复运行结果一致）。
- 事件 → 音效/音量/顿帧的映射在 `data/tactics_sfx.json`；播放走 `shared/audio/audio_manager.gd` 的 `play_sfx`，读取仍由 `shared/audio/audio_loader.gd` 解析原始 WAV。

## 改名或移动前

运行素材并非只靠完整路径字面量加载，不能只用 Grep 搜不到文件名就判断“没人用”。改名/移动前至少同时检查：

1. 动态加载：`shared/resources/asset_paths.gd`、`shared/resources/ai_assets.gd`、`shared/ui/icon_lib.gd`、`shared/audio/audio_loader.gd` 与 `shared/resources/image_cache.gd` 及相关调用名。
2. JSON：`data/speakers.json` 的立绘完整路径；`data/town.json`、`data/forest.json` 里的 `sprite` 文件名。
3. 工具：`godot/tools/extract_ai_packs.py`、`extract_preview_pack.py`、`build_ai_sheets.py`、`make_special_icons.py` 的输入/输出路径（输入在 `art_source/inputs/`）。
4. 测试：`godot/tests/` 中断言素材存在或读取素材的用例（如 `test_ai_assets.gd`）。

## 加载约定

- 这些图片/音频没有经过 Godot 导入，现有代码用 `Image.load_from_file` / `FileAccess` 直接读原始文件；不要擅自改成 `load()` / `preload()`。
- 运行素材路径优先收敛到 `shared/resources/asset_paths.gd` 的常量。`ai_assets.gd` 按文件名的 `icon_` / `tex_` 前缀分流到 `icons/`、`textures/`，其余默认 `scenery/`，调用方仍只传文件名。`data/speakers.json` 中的显式立绘完整路径是内容数据，暂时保留。
- 纹理/音频的进程内缓存分别在 `shared/resources/ai_assets.gd`、`shared/resources/image_cache.gd`、`shared/ui/icon_lib.gd`、`shared/scenery/town/town_marker_icons.gd`、`shared/audio/audio_loader.gd` 中；不要另建重复缓存或改变读取顺序。
- 生成工具输入放 `art_source/inputs/`，本地预览和试验图放 `art_source/archive/sprite_trials/`。

## 新增素材（小镇改造批次）

- 建筑立面（8 张，透明底、已裁边，宽度 800）：`scenery/facade_herb_shop.png`（药铺）、`facade_smithy.png`（铁匠铺）、`facade_tailor.png`（布庄）、`facade_grocery.png`（杂货铺）、`facade_house_narrow.png`（窄楼民居）、`facade_house_thatch.png`（茅草农家）、`facade_courtyard.png`（带院民居）、`facade_pavilion.png`（三层楼阁）。门楣木匾为空白深色木板，文字由游戏用 `Label3D` 叠加；木匾位置写在 `data/town.json` 建筑的 `plaque`（[fx, fy]）与 `plaque_w` 里，`facade` 指定立面文件名。读取仍走 `shared/resources/ai_assets.gd`，不要改成 `load()`/`preload()`。
- `scenery/town_*.png`：110 张小镇道具（摊位、码头、河岸、山门、门派、树木、灯笼串等），`scenery/bg_night_mountains.png`、`bg_rooftops.png`。
- `textures/tex_cliff_rock|flagstone_large|flagstone_wet|riverbank_mud|stone_wall_mossy|wood_pier.png`：新地表/墙面贴图。
- `vfx/`：15 张战斗特效图集与格子高亮（已去背景，战旗界面接入时使用，尚未被代码引用）。
- 生成：`python godot/tools/import_pack_v2.py`，输入在 `art_source/incoming/town_pack_v2/` 与 `battle_vfx_pack/`；切图编号映射写在脚本的 `PROPS` 表里。
- 小镇布局由 `data/town.json` 驱动：`terraces`（台地）、`buildings`（含 `facade` / `plaque` / `plaque_w`）、`sprite` 道具（含 `collide` / `phase` / `light`）、`border`（外围树林）、`camera_clamp`、`forest`、`unlock_zones`；大批量调整建筑坐标与立面映射改 `godot/tools/gen_town_layout.py` 后运行 `python godot/tools/gen_town_layout.py` 重新生成；昼夜由 `core/town_phase.gd` 与 `shared/scenery/town/town_phase_controller.gd` 控制（调试：小镇里按 N 切换）。
