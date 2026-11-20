# 帝王世纪（Emperor Century）演出系统

东方阳的领域演出：约 8 秒展开 + 常驻领域 + 规则层驱动的自动切割。**只做表现**：领域范围、重力数值映射、
切割伤害与目标都由战斗规则层决定，本系统不改任何数值，也不改单位的真实坐标。

## 文件
| 路径 | 作用 |
|---|---|
| `godot/shared/scene/emperor_century/emperor_century_controller.gd` | 生命周期与时间轴（inactive / opening / active / closing），对外接口与信号 |
| `.../emperor_domain_fx.gd` | 光点聚集、贴地金环展开、领域边界（常驻）、淡薄穹顶、金色颗粒 |
| `.../emperor_gravity_fx.gd` | 地面裂纹、被压下的石块、重力冲击、单位视觉受压（只改 Sprite 子节点，可还原） |
| `.../emperor_autocut_fx.gd` | 无形切割：细金线 → 切痕 → 火花 → 延迟音效；前景/背景/地面三层 |
| `.../emperor_environment_fx.gd` | 整体压暗（CanvasLayer，关闭即释放） |
| `.../emperor_gfx.gd` | 素材读取、程序化贴图（细圆环/斩线/光点）、QuadMesh 对象池 |
| `.../emperor_config.gd` + `godot/data/emperor_century.json` | 全部可调参数与素材角色表 |
| `godot/features/emperor_preview/emperor_century_preview.tscn/.gd` | 独立预览场景与调试面板 |
| `godot/tools/prepare_emperor_century_vfx.py` | 离线素材预处理（不改原图） |
| `godot/tests/test_emperor_century.gd` | 生命周期/阶段/切割/还原/清理测试 |

## 素材
原始图：`godot/assets/vfx/emperor_century_*_sequence.png`（不修改）。预处理产物：`godot/assets/vfx/emperor_century/*.png`
与 `manifest.json`；人工复核预览图在 `art_source/emperor_century_previews/`。

这些图**不是等宽 8 帧**，而是不同尺寸的元素按行排列（已人工核对）：
- `domain_expansion` 6 个：细环 / 加粗环 / 符文环 / 带光芒环 / 穹顶 / 带废墟场景的大穹顶（最后一个自带场景，**未使用**）。
- `auto_cut` 10 个：6 条水平斩线 + 4 张斩击火花。
- `gravity_crack` 7 张地裂递进；`gravity_floating_rocks` 8 块岩石 + 4 个星环；`gravity_impact` 4 个（第 4 个自带场景，**未使用**）；`slash_arc` 7 张弧光。
- 原图的深色底在预处理时按亮度抠掉，输出为真透明；总览图 `full_sheet` 只导出 4 个候选元素（unverified，未使用）。
重新生成：`py -3 godot/tools/prepare_emperor_century_vfx.py`。

## 运行预览
```
godot --path godot res://features/emperor_preview/emperor_century_preview.tscn
```
1 完整演出 · 2 只播展开 · 3 只播重力 · 4 只播切割 · 5 直接常驻 · 6 关闭 · 7 对敌人的战斗切割 · Esc 取消清理 ·
`[` `]` 半径 · `-` `=` 速度 · Q/E 转镜头。左上角显示状态、阶段、时间、特效节点数。

## 接入战斗
```gdscript
var domain := EmperorCenturyController.new()      # 加到战场 3D 根节点下
stage.add_child(domain)
domain.audio_event.connect(...)                    # domain_hum / domain_open / gravity_slam / cut_start / cut_hit / domain_close
domain.camera_changed.connect(...)                 # {fov_scale, offset, shake, reset}，由宿主应用到相机
domain.open_domain(emperor_pos, affected_cell_world_positions, {"targets": enemy_nodes, "battle_driven": true})
domain.play_auto_cut(hit_target_nodes)             # 只由规则层调用；视觉不决定伤害
domain.update_domain_cells(new_cells)              # 领域范围变化
domain.close_domain()                              # 领域结束；cleanup() 可随时强制清理
```
`battle_driven = true` 时控制器不会自己生成任何切割；`false`（剧情/预览）才会在切割阶段内分散排布 3～5 次，
常驻阶段偶尔出现纯装饰性的地面切痕。

## 还没做 / 未验证
- 没有接入 `features/tactics`（没有现成的"领域"规则）；接入时战棋舞台的相机需处理 `camera_changed`。
- 音效只有事件接口，没有音频素材。
- 屏幕外剔除、暂停时的挂起没有做；倍速与暂停靠 `speed` / `auto_process` 控制。
- 序章战后页面（2D）目前仍是之前的 `opening_domain_stage.gd`，没有换成这套 3D 控制器。
