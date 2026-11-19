extends "res://tests/test_case.gd"

# 环境配置回归：旧地图默认值、天空/光照/相机/边界林的校验与访问器、
# 相机启动/更新夹取、光照预设变化、指定边林生成，以及工坊应用/撤销/试跑。

const EditState := preload("res://addons/layout_editor/edit_state.gd")
const LayoutDocument := preload("res://core/layouts/layout_document.gd")
const LayoutEnvironment := preload("res://core/layouts/layout_environment.gd")
const LayoutEnvironmentBuilder := preload("res://shared/scenery/layouts/layout_environment_builder.gd")
const LayoutTerrain := preload("res://core/layouts/layout_terrain.gd")
const TownBorder := preload("res://shared/scenery/town/town_border.gd")
const WorldCamera := preload("res://shared/scene/world_camera.gd")

const FIXTURE_PATH := "res://tests/fixtures/layout_workshop.json"
const PANEL_PATH := "res://addons/layout_editor/main_panel.tscn"
const TEMP_PATH := "user://test_layout_environment_playtest.json"
const OFFSET := Vector3(0.0, 16.7, 37.5)
const LOOK_AHEAD := Vector3(0.0, 1.0, -4.0)


func _load() -> Dictionary:
	return LayoutDocument.load_document(FIXTURE_PATH)


func _has_error(errors: Array, needle: String) -> bool:
	for message in errors:
		if str(message).contains(needle):
			return true
	return false


func _validate_with(environment: Dictionary) -> Array:
	var loaded := _load()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	document["environment"] = environment
	return LayoutDocument.validate_document(document, loaded.get("catalog", {}))


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- 数据与校验


func test_legacy_map_keeps_environment_defaults() -> void:
	var loaded := _load()
	assert_true(bool(loaded.get("ok", false)),
		"测试布局应能加载：%s" % str(loaded.get("errors", [])))
	var document: Dictionary = loaded.get("document", {})
	assert_eq(LayoutEnvironment.sky_id(document), "default", "缺省天空是 default")
	assert_eq(LayoutEnvironment.lighting_id(document), "default", "缺省光照是 default")
	assert_eq(LayoutEnvironment.camera_clamp(document).size, Vector2.ZERO,
		"没有 camera_clamp 时不夹取")
	assert_true(LayoutEnvironment.border_options(document).is_empty(),
		"没有 border 时不建边界林")


func test_rejects_invalid_environment() -> void:
	assert_true(_has_error(_validate_with({"sky": "sunset"}), "environment: sky"),
		"未知天空预设应被拒绝")
	assert_true(_has_error(_validate_with({"lighting": "candle"}), "environment: lighting"),
		"未知光照预设应被拒绝")
	assert_true(_has_error(_validate_with({"camera_clamp": [0, 0]}), "camera_clamp"),
		"不完整相机范围应被拒绝")
	assert_true(_has_error(_validate_with({"camera_clamp": [10, 10, 5, 20]}), "positive area"),
		"倒置相机范围应被拒绝")
	assert_true(_has_error(_validate_with({"camera_clamp": [0, 0, 100, 10]}), "inside the map"),
		"越界相机范围应被拒绝")
	assert_true(_has_error(_validate_with({"camera_clamp": [0, 0, INF, 10]}), "finite"),
		"非有限相机范围应被拒绝")
	assert_true(_has_error(_validate_with({"border": {"sides": ["up"]}}), "border.sides"),
		"未知林带方向应被拒绝")
	assert_true(_has_error(
		_validate_with({"border": {"sides": ["north"], "spacing": 0.1}}),
		"border.spacing"
	), "过密间距应被拒绝")
	assert_true(_has_error(
		_validate_with({"border": {"sides": ["north"], "depth": 60, "spacing": 1}}),
		"would place"
	), "树数量超限应被拒绝")
	var empty_sides := _validate_with({"border": {"sides": []}})
	assert_true(empty_sides.is_empty(), "空 sides 等于关闭，应当有效")


func test_valid_environment_and_accessors() -> void:
	var environment := {
		"sky": "night",
		"lighting": "warm",
		"camera_clamp": [8, 8, 24, 20],
		"border": {"sides": ["north", "west"], "depth": 6, "spacing": 4, "seed": 3},
	}
	var loaded := _load()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	document["environment"] = environment.duplicate(true)
	var before := JSON.stringify(document)
	var errors := LayoutDocument.validate_document(document, loaded.get("catalog", {}))
	assert_true(errors.is_empty(), "完整环境配置应通过校验：%s" % str(errors))
	assert_eq(JSON.stringify(document), before, "校验只读，不规范化或回写原文档")

	assert_eq(LayoutEnvironment.sky_id(document), "night")
	assert_eq(LayoutEnvironment.lighting_id(document), "warm")
	var clamp := LayoutEnvironment.camera_clamp(document)
	assert_eq(clamp, Rect2(8.0, 8.0, 16.0, 12.0), "相机范围按世界单位读取")
	var border := LayoutEnvironment.border_options(document)
	assert_eq(border.get("sides", []), ["north", "west"])
	assert_near(float(border.get("depth", 0.0)), 6.0)
	assert_near(float(border.get("spacing", 0.0)), 4.0)
	assert_eq(int(border.get("seed", 0)), 3)


# ---------------------------------------------------------------- 运行时


func test_camera_snap_and_update_respect_clamp() -> void:
	var parent := Node3D.new()
	var camera := Camera3D.new()
	var target := Node3D.new()
	target.position = Vector3(80.0, 0.0, 80.0)
	parent.add_child(camera)
	parent.add_child(target)
	var clamp_rect := Rect2(-10.0, -8.0, 20.0, 16.0)

	var focus := WorldCamera.snap(
		camera, target, OFFSET, LOOK_AHEAD, Vector3.ZERO, clamp_rect
	)
	assert_near(focus.x, 10.0, 0.01, "初次 snap 也应夹取 x")
	assert_near(focus.z, 8.0, 0.01, "初次 snap 也应夹取 z")
	assert_near(camera.position.x, 10.0, 0.01, "相机启动位置夹取 x")
	assert_near(camera.position.z, 8.0 + OFFSET.z, 0.01, "相机启动位置夹取 z")

	camera.position = Vector3.ZERO
	for i in range(30):
		focus = WorldCamera.update(
			camera, target, focus, OFFSET, LOOK_AHEAD, 0.1, Vector3.ZERO, clamp_rect
		)
	assert_near(focus.x, 10.0, 0.01, "更新时焦点保持夹取 x")
	assert_near(focus.z, 8.0, 0.01, "更新时焦点保持夹取 z")
	parent.free()


func test_lighting_presets_change_scene() -> void:
	var default_parent := Node3D.new()
	var default_nodes := LayoutEnvironmentBuilder.build_lighting(default_parent, {})
	var default_sun: DirectionalLight3D = default_nodes["sun"]
	assert_near(default_sun.light_energy, 0.72, 0.001, "默认光照保持原参数")
	var default_energy := default_sun.light_energy
	var default_env: WorldEnvironment = default_nodes["world_environment"]
	assert_near(default_env.environment.ambient_light_energy, 0.36, 0.001,
		"默认环境光保持原参数")
	default_parent.free()

	var night_parent := Node3D.new()
	var document := {"environment": {"sky": "night", "lighting": "night"}}
	var night_nodes := LayoutEnvironmentBuilder.build_lighting(night_parent, document)
	var night_sun: DirectionalLight3D = night_nodes["sun"]
	assert_true(night_sun.light_energy < default_energy, "夜色光照应更暗")
	var night_env: WorldEnvironment = night_nodes["world_environment"]
	var sky_material := night_env.environment.sky.sky_material as ProceduralSkyMaterial
	assert_true(sky_material != null, "天空应使用 ProceduralSkyMaterial")
	if sky_material != null:
		assert_true(sky_material.sky_top_color.get_luminance() < 0.4, "夜色天空更暗")
	night_parent.free()


func test_border_builds_selected_side_and_follows_height() -> void:
	var loaded := _load()
	var document: Dictionary = (loaded.get("document", {}) as Dictionary).duplicate(true)
	document["environment"] = {
		"border": {"sides": ["north"], "depth": 6, "spacing": 4, "seed": 1},
	}
	var terrain := LayoutTerrain.compile(document)
	var parent := Node3D.new()
	var border := LayoutEnvironmentBuilder.build_border(parent, document, terrain)
	assert_true(border != null, "选北侧时应生成 Border 根节点")
	if border != null:
		assert_true(border.get_child_count() > 0, "北侧林带应有树")
		for child in border.get_children():
			var node := child as Node3D
			if node == null:
				continue
			assert_true(node.position.z < 0.0, "北侧树全部在地图外")
	parent.free()

	# 可选高度回调：兼容小镇旧调用（不传时仍落在 y=0）。
	var callback_parent := Node3D.new()
	var data := {
		"bounds": {"x0": 0.0, "z0": 0.0, "x1": 10.0, "z1": 10.0},
		"border": {
			"sides": ["north"], "depth": 4, "spacing": 4, "seed": 1,
			"files": ["prop_willow.png"],
		},
	}
	var height_callback := func(_point: Vector2) -> float:
		return 2.5
	TownBorder.new().build(callback_parent, data, height_callback)
	var custom := callback_parent.get_node_or_null("Border") as Node3D
	assert_true(custom != null, "自定义边界林应生成")
	if custom != null:
		for child in custom.get_children():
			var node := child as Node3D
			if node != null:
				assert_near(node.position.y, 2.5, 0.001, "树根跟随高度回调")
	callback_parent.free()


# ---------------------------------------------------------------- 工坊入口


func test_edit_state_apply_undo_and_playtest() -> void:
	_remove_user_file(TEMP_PATH)
	var state := EditState.new()
	assert_true(bool(state.load_map(FIXTURE_PATH).get("ok", false)),
		"测试布局应能打开：%s" % state.last_error)
	var original := JSON.stringify(state.document)

	var applied := state.apply_environment(
		"dusk", "warm", [8, 8, 24, 20],
		{"sides": ["north"], "depth": 6, "spacing": 4, "seed": 3}
	)
	assert_true(bool(applied.get("ok", false)),
		"环境应能应用：%s" % state.last_error)
	var env: Dictionary = state.document.get("environment", {})
	assert_eq(str(env.get("sky", "")), "dusk")
	assert_eq(str(env.get("lighting", "")), "warm")
	assert_eq(env.get("camera_clamp", []), [8.0, 8.0, 24.0, 20.0])
	assert_eq((env.get("border", {}) as Dictionary).get("sides", []), ["north"])

	var exported := state.export_playtest(TEMP_PATH)
	assert_true(bool(exported.get("ok", false)), "试跑快照应写出：%s" % state.last_error)
	var reloaded := LayoutDocument.load_document(TEMP_PATH)
	assert_true(bool(reloaded.get("ok", false)), "试跑快照应能完整校验")
	var snapshot_env: Dictionary = (reloaded.get("document", {}) as Dictionary).get(
		"environment", {}
	)
	assert_eq(str(snapshot_env.get("sky", "")), "dusk", "试跑 JSON 包含天空字段")
	assert_true(snapshot_env.has("camera_clamp"), "试跑 JSON 包含相机范围")
	assert_true(snapshot_env.has("border"), "试跑 JSON 包含边界林")

	var depth := state.undo_stack.size()
	var rejected := state.apply_environment("default", "default", [0, 0, 100, 10], {})
	assert_true(not bool(rejected.get("ok", false)), "越界相机范围应被拒绝")
	assert_true(state.last_error.contains("camera_clamp"), "错误应说明 camera_clamp")
	assert_eq(state.undo_stack.size(), depth, "失败环境应用不写入历史")

	assert_true(state.undo(), "环境应用应能撤销")
	assert_true(not state.document.has("environment"), "撤销后回到无环境文档")
	assert_true(state.redo(), "环境应用应能重做")
	assert_true(state.document.has("environment"), "重做后环境恢复")
	assert_true(JSON.stringify(state.document) != original, "草稿确实包含环境字段")

	assert_true(bool(state.clear_environment().get("ok", false)), "清空环境应成功")
	assert_true(not state.document.has("environment"), "清空后移除 environment")
	_remove_user_file(TEMP_PATH)


func test_panel_environment_entry_paths() -> void:
	var tree: Variant = Engine.get_meta("test_tree", null)
	if tree == null:
		assert_true(false, "面板测试需要真实 SceneTree")
		return
	var panel: Variant = load(PANEL_PATH).instantiate()
	tree.root.add_child(panel)
	if panel.state == null:
		panel._ready()
		panel._terrain_panel._ready()
		panel._environment_panel._ready()
	panel.show()
	assert_true(bool(panel.state.load_map(FIXTURE_PATH).get("ok", false)),
		"面板应能打开测试布局：%s" % panel.state.last_error)

	panel.set_environment_tools_open(true)
	var tools: Variant = panel._environment_panel
	assert_true(tools != null, "环境工具区应已创建")
	tools._sky_option.select(3)      # night
	tools._lighting_option.select(1) # warm
	tools._north_check.set_pressed_no_signal(true)
	tools._depth_spin.value = 6
	tools._spacing_spin.value = 4
	tools._on_pick_camera_pressed()
	assert_true(tools.is_pending(), "点“框选相机范围”后应等待两次点击")
	panel._on_cell_clicked(Vector2i(2, 2), MOUSE_BUTTON_LEFT)
	panel._on_cell_hovered(Vector2i(5, 5))
	assert_eq(panel.grid._camera_rect, Rect2(4.0, 4.0, 8.0, 8.0),
		"框选预览应显示紫色矩形")
	panel._on_cell_clicked(Vector2i(5, 5), MOUSE_BUTTON_LEFT)
	assert_true(not tools.is_pending(), "第二次点击后结束框选")

	tools._on_apply_pressed()
	var env: Dictionary = panel.state.document.get("environment", {})
	assert_eq(str(env.get("sky", "")), "night", "面板应用应写入天空")
	assert_eq(str(env.get("lighting", "")), "warm", "面板应用应写入光照")
	assert_eq(env.get("camera_clamp", []), [4.0, 4.0, 12.0, 12.0])
	assert_eq((env.get("border", {}) as Dictionary).get("sides", []), ["north"])

	# 切换到地形页应取消未完成的相机框选。
	panel.set_environment_tools_open(true)
	tools._on_pick_camera_pressed()
	assert_true(tools.is_pending(), "重新开始框选")
	panel.set_terrain_tools_open(true)
	assert_true(not tools.is_pending(), "切换页签应取消环境框选")
	panel.free()
	_remove_user_file(TEMP_PATH)
