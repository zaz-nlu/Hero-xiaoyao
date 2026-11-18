# 原始素材归档

`art_source/` 存放原始素材、历史备份和参考包，**不参与 Godot 运行打包**，也不是游戏里的加载路径。运行素材在 `godot/assets/`，说明见 [godot/assets/README.md](../godot/assets/README.md)。

## 目录与来源

| 当前路径 | 原路径 | 内容 | 文件数 |
| --- | --- | --- | ---: |
| `incoming/user_art/` | `src/assets、/`（目录名含顿号） | 原先散放在源码目录的用户美术：6 张角色 PNG、`ai/wuxia_town_hd2d_assets_v1/`（14 个文件的古镇素材包）、`wuxia_town_game_ready.zip` | 21 |
| `archive/legacy_nested_assets/` | `godot/assets/godot/` | 重复嵌套的旧角色素材树：每位角色 8 个文件（source / magenta / alpha / preview / 四方向） | 40 |
| `reference/wuxia_town_hd2d_assets_v1/` | `godot/assets/ai/wuxia_town_hd2d_assets_v1/` | 古镇 HD-2D 原始参考包（材质、建筑立面、道具、背景，以及原包 README） | 14 |

三组共 75 个文件全部保留，移动时保留内部目录结构和原文件名。它们经只读审计，没有被当前代码、JSON、测试或 `godot/tools/` 硬编码引用；**“当前未被引用”不等于可以删除**，后续素材制作仍可能用到。

原有 zip 和其余未使用素材同样保留。没有为隐藏这些素材新增 `.gitignore` 规则；现有根 `.gitignore` 的 `*.zip` 会让 zip 不进版本库，但文件仍在磁盘上保留。

## 使用约定

- 新收到的素材包先放 `incoming/`，保留原始文件名和包内结构。
- 确认要在游戏里使用后，再输出到 `godot/assets/` 的对应运行目录：`ai/game/`、`sprites/`、`portraits/`、`audio/`。
- 输出为运行素材时改成 snake_case，并同时更新动态加载、JSON、工具和测试中的引用；检查清单见 [godot/assets/README.md](../godot/assets/README.md)。
- `incoming/` 和 `archive/` 中的原始资产保留原名，不要求 snake_case。

## 尚未迁移

素材生成工具仍依赖 `godot/assets/ai/raw_user/` 和 `godot/assets/npc_six_preview.jpg`，本轮没有把它们迁到 `art_source/`。在工具改完之前，不要移走这两个位置。
