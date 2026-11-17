# 项目结构与放置规范

主游戏在 `godot/`，`src/` 是早期 Web 原型。运行素材主要在 `godot/assets/`，本轮归档的原始包和历史备份在 `art_source/`；现有生成工具依赖的 `ai/raw_user/` 和预览 JPG 暂留原位，详见素材说明。

相关文档：[运行素材说明](../godot/assets/README.md) · [原始素材归档](../art_source/README.md)

## 模块职责

| 目录 | 职责 | 主要内容 |
| --- | --- | --- |
| `godot/core/` | 纯规则、状态与数据读取 | 战斗、伤害、招式克制、境界、属性、熟练度、任务、存档、模拟器；`asset_paths.gd` 与 `data_loader.gd` 是路径/读取入口 |
| `godot/data/` | 游戏内容 | 玩家、武学、敌人、遭遇、物品、成长、境界、熟练度、任务、说话人、城镇/森林/酒馆配置；`data/dialogues/` 对话，`data/sprites/` 角色配色定义 |
| `godot/world/` | 地图与 3D 场景 | `town/tavern/forest` 场景脚本与 `.tscn`、战斗舞台、角色精灵、交互、拾取、潜行、玩家移动；`scene_kit.gd`、`texgen.gd`、`ai_assets.gd` 等场景辅助 |
| `godot/ui/` | 界面与演出 | 主场景、战斗界面、对话、角色/任务面板、暂停菜单、标题与过场、HUD、图标映射、图片缓存、音频管理等 |
| `godot/tools/` | 离线生成与调试 | 像素化、角色图集、立绘、图标、音乐生成脚本；数值模拟、Boss/酒馆调参、难度报告、冒烟测试 |
| `godot/tests/` | 自动测试 | `run_tests.gd` 自动发现并执行 `test_*.gd` |
| `src/` | 早期 Web 原型 | React + Vite + three.js，只作参考，不与 Godot 运行素材混用 |
| `art_source/` | 原始素材归档 | 原始包、历史备份、参考素材，不参与运行打包 |
| `scripts/` | 校验入口 | `check.sh`：测试 + 场景启动 + 冒烟测试 |
| `docs/` | 文档 | 设计文档与本结构说明 |

## 共享入口

本轮整理新增/归位了三个共享入口，新代码优先复用：

- `godot/shared/resources/asset_paths.gd`：运行素材目录常量 `AI_GAME`、`SPRITES`、`PORTRAITS`、`AUDIO`，以及 `sprite_path()`。角色图集、立绘、音频和 AI 素材的路径从这里取；JSON 里已有的显式立绘完整路径（如 `data/speakers.json`）属于内容数据，继续保留。
- `godot/core/data_loader.gd`：顶部集中常用 JSON 的 `*_PATH` 常量，并提供武学/敌人/玩家/物品的读取与校验。新增通用数据路径放这里；与某份内容 JSON 绑定的对话路径可以继续写在内容文件里。
- `godot/shared/scene/scene_kit.gd`：小镇、酒馆、森林共用的网格、材质、灯光和暗角搭建函数。多场景重复的 3D 搭建逻辑应进这里，而不是各自复制。

## 放置规则

1. 纯规则、状态、数值计算放 `godot/core/`，不依赖 `Control`、`Node3D` 等界面/场景类型。
2. 内容数据、对话、任务配置放 `godot/data/`，不要把内容写死在脚本里。
3. 只属于某张地图的逻辑留在对应的 `godot/world/*.gd`。
4. 多地图共用的搭建辅助复用到 `scene_kit.gd`；多界面共用的小组件放 `godot/ui/`。
5. 新功能按职责新建脚本或数据文件，避免继续往巨型场景的 `_ready()` / 构建函数里堆代码。
6. 离线生成、调试、模拟放 `godot/tools/`；自动测试放 `godot/tests/`，文件名以 `test_` 开头。

## 已知遗留

- `godot/features/town/town.gd`、`tavern.gd`、`forest.gd` 和 `godot/features/battle/battle_view.gd`、`game.gd` 等仍是较大的模块。演出、相机、道具生成等可以后续逐步独立拆分，**本轮没有完成这些拆分**，不要按已拆分来理解。
- 并非所有路径都已收口：`godot/features/title/title_cinematic.gd` 的 `title_shots.json`、内容 JSON 中的对话路径等仍由各自模块持有。改路径时仍需按调用点逐一确认，不能只改 `AssetPaths`。
- 运行素材按原始文件读取（`Image.load_from_file` / `FileAccess`），不经过 Godot 导入；不要擅自改成 `load()` / `preload()`，详见 [运行素材说明](../godot/assets/README.md)。
