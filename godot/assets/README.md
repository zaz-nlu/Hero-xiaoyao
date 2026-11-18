# 运行素材

`godot/assets/` 主要存放游戏运行素材，也暂时保留现有生成工具依赖的输入和试验产物，具体位置见下表。本轮归档的原始包和历史备份见 [art_source/README.md](../../art_source/README.md)。

## 目录

| 路径 | 用途 | 读取方式 |
| --- | --- | --- |
| `ai/game/` | 建筑立面、场景道具、树木植被、地表材质、酒馆家具、宝箱/采集物，以及 `icon_*.png` 界面图标 | `shared/resources/ai_assets.gd` 按文件名用 `Image.load_from_file` 读取并缓存；图标由 `shared/ui/icon_lib.gd` 映射 |
| `sprites/` | 角色图集（`shared/scene/character_sprite.gd` 按 5×4 帧切分） | `shared/resources/image_cache.gd` + `shared/resources/asset_paths.gd` |
| `portraits/` | 对话立绘 | `shared/resources/image_cache.gd`；路径来自 `data/speakers.json` |
| `audio/` | WAV 音乐与音效 | `shared/audio/audio_loader.gd` 直接解析 PCM 字节并缓存 |
| `ai/raw_user/` | 素材生成工具的输入（角色包、森林包、NPC 包、图标包、预览条） | 由 `godot/tools/` 读取，不是运行素材；不要移走 |
| `sprites/_trial/` | 试验图、截图产物 | 不参与运行；已被 `godot/.gitignore` 忽略 |
| `npc_six_preview.jpg` | 村民接触表，`tools/extract_preview_pack.py` 的输入 | 不是运行素材；不要移走 |

`README.txt` 是早期角色图集的导入说明，保留。本目录下的 zip 是素材包存档，现有根 `.gitignore` 的 `*.zip` 会让它们不进版本库，但文件仍保留在磁盘上。

## 命名

运行素材统一用 snake_case，例如 `facade_tavern.png`、`prop_willow.png`、`icon_item_herbs.png`、`ren_xiaoyao.png`、`sfx_hit.wav`。

新增界面图标沿用 `shared/ui/icon_lib.gd` 的规则，放进 `ai/game/`：

- 武学：`icon_martial_<id>.png`
- 物品：`icon_item_<id>.png`；个别特例写在 `ITEM_FILES` 映射里
- 属性：`icon_stat_<stat>.png`

新图标需要同时在 `icon_lib.gd` 中补映射或确认默认命名能命中，不要改读取顺序。

## 改名或移动前

运行素材并非只靠完整路径字面量加载，不能只用 Grep 搜不到文件名就判断“没人用”。改名/移动前至少同时检查：

1. 动态加载：`shared/resources/asset_paths.gd`、`shared/resources/ai_assets.gd`、`shared/ui/icon_lib.gd`、`shared/audio/audio_loader.gd` 与 `shared/resources/image_cache.gd` 及相关调用名。
2. JSON：`data/speakers.json` 的立绘完整路径；`data/town.json`、`data/forest.json` 里的 `sprite` 文件名。
3. 工具：`godot/tools/` 下读取或输出这些路径的脚本。
4. 测试：`godot/tests/` 中断言素材存在或读取素材的用例（如 `test_ai_assets.gd`）。

## 加载约定

- 这些图片/音频没有经过 Godot 导入，现有代码用 `Image.load_from_file` / `FileAccess` 直接读原始文件；不要擅自改成 `load()` / `preload()`。
- 运行素材路径优先收敛到 `shared/resources/asset_paths.gd` 的常量。`data/speakers.json` 中的显式立绘完整路径是内容数据，暂时保留。
- 纹理/音频的进程内缓存分别在 `shared/resources/ai_assets.gd`、`shared/resources/image_cache.gd`、`shared/ui/icon_lib.gd`、`shared/audio/audio_loader.gd` 中；不要另建重复缓存或改变读取顺序。
- 本轮只移动了三组确认无硬编码引用的原始/备份目录到 `art_source/`；`ai/raw_user/`、`npc_six_preview.jpg`、`sprites/_trial/` 和原有 zip 都留在原位。
