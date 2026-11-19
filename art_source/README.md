# 原始素材归档

`art_source/` 存放原始素材、历史备份和参考包，**不参与 Godot 运行打包**，也不是游戏里的加载路径。运行素材在 `godot/assets/`，说明见 [godot/assets/README.md](../godot/assets/README.md)。

## 目录与来源

| 当前路径 | 原路径/来源 | 内容 |
| --- | --- | --- |
| `inputs/` | 各素材包裁切/生成工具的输入 | `forest/`（`transparent/` 去背图集与原始 `tex_*.png`）、`npc_sheets/`（六位 NPC 原图）、`npc_strips/`、`contact_sheets/`、`preview_strips/`、`character_sheets/`（五人物包）、`tavern_and_icons/`、`legacy_sources/` |
| `archive/packages/` | 原始素材 ZIP | `five_character_sheets.zip`、`forest_scenery_pack.zip`、`six_npc_sheets.zip`、`tavern_and_icons_pack.zip`、`town_scenery_pack.zip` |
| `incoming/user_art/` | `src/assets、/`（目录名含顿号） | 原先散放在源码目录的用户美术，包括 6 张角色 PNG 和解压后的古镇参考包。原 ZIP 现为 `archive/packages/town_scenery_pack.zip` |
| `archive/legacy_nested_assets/` | `godot/assets/godot/` | 重复嵌套的旧角色素材树：每位角色 8 个文件（source / magenta / alpha / preview / 四方向） |
| `archive/sprite_trials/` | 本地生成试验 | 历史预览/试验图（如 `ai_atlas.png`、`bandit_64.png`），仅本地参考，不进版本库 |
| `reference/wuxia_town_hd2d_assets_v1/` | `godot/assets/ai/wuxia_town_hd2d_assets_v1/` | 古镇 HD-2D 原始参考包（材质、建筑立面、道具、背景，以及原包 README） |

`inputs/` 是生成工具真正读取/写回的输入目录，和只作留档的 `archive/packages/` 不同：

- `inputs/forest/transparent/*.png` 是森林去背图集，`inputs/forest/tex_*.png` 是原始平铺贴图。
- `inputs/npc_sheets/<npc_id>_character_sheet.png` 是六位 NPC 原图，id 为 `smith`、`hunter`、`fisherman`、`peddler`、`waiter`、`townswoman`；工具把 32×48 待机条写回 `inputs/npc_strips/<npc_id>_idle_32x48_alpha.png`（扁平，无子目录）。
- `inputs/contact_sheets/villager_reference_sheet.jpg` 是村民接触表；条带写到 `inputs/preview_strips/<id>_idle_32x48_alpha.png`（扁平）。
- `inputs/character_sheets/` 是五人物包，保留一角色一目录的旧布局；`sprite_source_notes.txt` 保留了早期 Godot 导入说明，作为历史来源，不再改动。
- `inputs/tavern_and_icons/`、`inputs/legacy_sources/` 是酒馆/图标原包和既有素材来源。

`archive/packages/` 保留五份原 ZIP 的内容，文件名按用途统一。原有两个 NPC ZIP 的 SHA-256 相同，归档保留 `six_npc_sheets.zip` 一份，重复副本已移到临时目录。`incoming/`、`archive/legacy_nested_assets/` 和 `reference/` 其余原始文件仍保留各自的目录结构和文件名。

现有根 `.gitignore` 的 `*.zip` 让压缩包不进版本库，但文件仍在磁盘上保留；`archive/sprite_trials/` 另有精确忽略条目，`godot` 侧 `sprites/_trial/` 的忽略规则保持不变。

## 使用约定

- 新收到的素材包先放 `incoming/`，保留原始文件名和包内结构。
- 生成工具的输入/中间产物放 `inputs/`，按现有脚本消费的目录名和文件名摆放；不要把输入写回 `godot/assets/`。
- 确认要在游戏里使用后，再输出到 `godot/assets/` 的对应运行目录：`scenery/`、`textures/`、`icons/`、`sprites/`、`portraits/`、`audio/`。
- 输出为运行素材时改成 snake_case，并同时更新动态加载、JSON、工具和测试中的引用；检查清单见 [godot/assets/README.md](../godot/assets/README.md)。
- `incoming/`、`inputs/` 和 `archive/` 中的原始资产保留原有命名习惯；运行目录统一 snake_case。

## 现有工具的路径

| 工具 | 读取 | 写出 |
| --- | --- | --- |
| `godot/tools/extract_ai_packs.py forest` | `inputs/forest/transparent/*.png`、`inputs/forest/tex_*.png` | `godot/assets/scenery/`、`godot/assets/textures/` |
| `godot/tools/extract_ai_packs.py npc` | `inputs/npc_sheets/<id>_character_sheet.png` | `godot/assets/portraits/`、`inputs/npc_strips/<id>_idle_32x48_alpha.png` |
| `godot/tools/extract_preview_pack.py` | `inputs/contact_sheets/villager_reference_sheet.jpg` | `godot/assets/portraits/`、`inputs/preview_strips/<id>_idle_32x48_alpha.png` |
| `godot/tools/build_ai_sheets.py` | `inputs/character_sheets/<id>/<id>_idle_32x48_alpha.png` 或扁平的 `inputs/npc_strips/`、`inputs/preview_strips/` | `godot/assets/sprites/` |
| `godot/tools/make_special_icons.py` | `godot/assets/icons/icon_martial_taiji.png` | `godot/assets/icons/icon_special_*.png` |
