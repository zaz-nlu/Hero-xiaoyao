# 开发约定

本文件是仓库内实际执行的开发约定。目录细节、依赖图和已知技术债见
[docs/architecture.md](docs/architecture.md)；本文件不重复那些细节。

## 工程边界

- `godot/` 是主游戏（Godot 4）。游戏功能、内容、测试以这里为准。
- 早期 Web 原型已移除（git 标签 `web-prototype-final` 可取回）。所有游戏功能都在 `godot/`。
- `art_source/` 只存原始/备份素材，不参与运行打包。

## 目录职责

Godot 生产脚本只能放在 `app/`、`core/`、`features/`、`shared/` 之下：

| 目录 | 放什么 |
| --- | --- |
| `app/` | 组合根、场景切换、跨 feature 的编排 |
| `core/` | 规则、数值、状态与数据读取；不能依赖场景/UI 类型 |
| `features/<name>/` | 单个功能或界面的场景、控制器与专属辅助 |
| `shared/` | 可复用的资源、场景搭建、玩法、音频与 UI 组件 |
| `data/` | 内容 JSON 与地图数据 |
| `assets/` | 运行时原始素材 |
| `tools/` | 离线生成、调参与调试脚本 |
| `tests/` | 自动测试，文件名 `test_*.gd` |

## 依赖方向

- `app` 可以依赖 `app`、`core`、`features`、`shared`。
- `core` 只能依赖 `core`。
- `shared` 可以依赖 `shared`、`core`，**不能** import `features`。
- `features/<x>` 可以依赖同一 feature、`core`、`shared`。
- feature 之间不要直接互相 import；跨 feature 协作走 `app/` 编排或明确的事件/信号。
  `architecture.config.json` 的跨 feature 白名单是例外通道，不是常规写法；条目必须带 reason。
- `core` 里不允许出现场景/UI 类型（`Node`、`Control`、`Node3D`、`CanvasLayer` 等；完整列表见
  `scripts/architecture/config.mjs`）。
- 不要重新创建 `godot/ui/` 或 `godot/world/`；这两个旧根目录已废弃，检查会拒绝其中的脚本与场景。
- 新战棋规则放 `core/tactics/`，战棋界面放 `features/tactics/`，地图数据放 `data/maps/`。

## 状态归属

- 状态属于真正使用它的具体模块，不集中塞进控制器。
- 控制器只做编排、信号转发和生命周期管理，不做万能 host/代理；公开转发仅限测试或既有调用点需要兼容的字段。
- 持久游戏状态在 `core/game_state.gd`，场景内的运行时状态由对应 feature 自己持有。

## 文件大小预算

- 新增生产脚本通常不超过 500 行（`architecture.config.json` 的 `defaultMaxLines`）。
- 旧的大文件在 `legacyLineBudgets` 里有精确行数预算：不能超出，也不能在拆分后继续保留偏高的预算。
- 拆分大文件时，必须在同一次修改里下调或删除对应预算；**不要为了通过检查而放宽预算**。

## 修改习惯

- 只改与任务相关的代码；不要顺手重构、格式化或改动无关文件。
- 保留工作区里未提交的修改；不要回滚或覆盖别人的改动。
- 不要删除、移动来源不明的素材。素材移动前按
  [godot/assets/README.md](godot/assets/README.md) 的清单检查动态加载、JSON、工具和测试。
- 行为变化要补测试；至少运行受影响范围的检查。
- 提交前最终运行 `npm run check`（架构单测 → 架构检查 → Godot 检查）。
  只改 Godot 时可以先跑 `npm run check:godot`。

## 检查环境

`scripts/check-godot.mjs` 需要 Godot 4 的 console 可执行文件，优先读取 `GODOT_BIN`，
否则尝试本机默认路径和 PATH 中的 `godot4` / `godot`：

```powershell
$env:GODOT_BIN = "D:/godot/Godot_v4.7.2-stable_win64_console.exe"
npm run check
```

运行失败时脚本会打印具体断言、Parse Error 或 SCRIPT ERROR 的上下文，并终止自己启动的进程树。
不要按进程名批量结束 Godot，以免关掉用户已经打开的编辑器。

本仓库不引入额外的审批流程；以检查与测试结果作为修改依据。
