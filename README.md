# 任逍遥（HD-2D 武侠）

仓库里只有一个工程：

- `godot/`：**主游戏**，Godot 4 的 HD-2D 武侠 RPG。

早期的 React + Vite Web 原型已经移除；需要时可以通过 git 标签 `web-prototype-final` 取回（`git checkout web-prototype-final`）。原始/备份素材归档在 `art_source/`，说明见 [art_source/README.md](art_source/README.md)。检查脚本不内置 Godot 引擎，也没有配置 CI；请用本机安装的 Godot 4，并通过 `GODOT_BIN` 或 PATH 指定。

## 快速开始

### 主游戏（Godot 4）

先准备 Godot 4，并把 console 版可执行文件告诉检查脚本（路径按自己的安装位置替换）：

```powershell
$env:GODOT_BIN = "D:/godot/Godot_v4.7.2-stable_win64_console.exe"
```

也可以把 `godot4` / `godot` 放进 PATH。启动游戏：

```powershell
& $env:GODOT_BIN --path godot
```

运行完整检查（架构单测 → 架构检查 → Godot 测试/场景/冒烟）：

```powershell
npm run check
```

只跑 Godot 检查：

```powershell
npm run check:godot
```

旧入口 `bash scripts/check.sh` 仍可用，它是架构检查 + Godot 检查的薄包装。

## 最小目录

```text
godot/                主游戏：app 组合根、core 规则、data 内容、features 场景/界面、shared 复用件、tools 工具、tests 测试、assets 运行素材
art_source/           原始/备份素材归档，不参与运行打包
docs/                 架构、结构与历史设计文档
scripts/              架构检查、Godot 检查与兼容入口
architecture.config.json  架构检查的项目级例外
package.json          检查脚本入口（`npm run check`）
```

## 文档

- [架构说明](docs/architecture.md)
- [项目结构与放置规范](docs/project-structure.md)
- [开发约定（AGENTS.md）](AGENTS.md)
- [运行素材目录说明](godot/assets/README.md)
- [原始素材归档说明](art_source/README.md)
