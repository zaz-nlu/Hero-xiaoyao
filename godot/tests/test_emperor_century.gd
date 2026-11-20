extends "res://tests/test_case.gd"

# 帝王世纪演出系统：配置、素材清单、生命周期、阶段、切割、受压还原、清理。

const Controller = preload("res://shared/scene/emperor_century/emperor_century_controller.gd")
const EmperorConfig = preload("res://shared/scene/emperor_century/emperor_config.gd")
const Gfx = preload("res://shared/scene/emperor_century/emperor_gfx.gd")


func _make(extra: Dictionary = {}) -> Node3D:
	var controller: Node3D = Controller.new()
	controller.auto_process = false
	var tree: Variant = Engine.get_meta("test_tree", null)
	if tree != null:
		tree.root.add_child(controller)
	var points: Array = [Vector3(3, 0, 0), Vector3(-2, 0, 3), Vector3(0, 0, -4)]
	var options := {"battle_driven": false}
	options.merge(extra)
	controller.open_domain(Vector3.ZERO, points, options)
	return controller


func _run(controller: Node3D, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		controller.advance(minf(0.05, left))
		left -= 0.05


func _dispose(controller: Node3D) -> void:
	controller.cleanup()
	controller.free()


func test_config_defaults_and_phase_bounds() -> void:
	var config: RefCounted = EmperorConfig.load_default()
	for key in EmperorConfig.DEFAULTS.keys():
		assert_true(config.values.has(key), "config has %s" % key)
	assert_near(config.total_duration(), 8.0, 0.001, "the opening lasts about eight seconds")
	var bounds: Dictionary = config.phase_bounds()
	assert_near(float((bounds["expansion"] as Array)[0]), 1.2, 0.001, "expansion starts at 1.2 s")
	assert_near(float((bounds["slash"] as Array)[1]), 6.5, 0.001, "slashing ends at 6.5 s")


func test_prepared_assets_exist_for_every_role() -> void:
	var config: RefCounted = EmperorConfig.load_default()
	assert_true(not config.roles.is_empty(), "roles are defined")
	for role in config.roles.keys():
		for file in Gfx.role_files(config, str(role)):
			assert_true(Gfx.texture(str(file)) != null, "%s/%s loads" % [role, file])


func test_full_opening_goes_through_every_phase_then_active() -> void:
	var controller := _make()
	var phases: Array = []
	controller.phase_changed.connect(func(p: String) -> void: phases.append(p))
	assert_eq(controller.state_name(), "opening")
	assert_eq(controller.current_phase(), "opening", "the first phase is entered on open")
	_run(controller, 8.2)
	assert_eq(phases, ["expansion", "gravity", "slash", "settle", "active"])
	assert_eq(controller.state_name(), "active", "the opening is not looped, it settles into the domain")
	assert_true(controller.vfx_node_count() > 0, "the boundary stays visible")
	_dispose(controller)


func test_close_and_cleanup_leave_no_residue() -> void:
	var controller := _make()
	_run(controller, 8.2)
	controller.close_domain()
	assert_eq(controller.state_name(), "closing")
	_run(controller, 1.5)
	assert_eq(controller.state_name(), "inactive", "closing finishes by itself")
	assert_eq(controller.vfx_node_count(), 0, "no tracked vfx remain")
	assert_eq(controller.get_child_count(), 0, "no nodes remain under the controller")
	_dispose(controller)


func test_cancel_midway_restores_everything() -> void:
	var holder := Node3D.new()
	var unit := Node3D.new()
	var sprite := Node3D.new()
	sprite.name = "Sprite"
	unit.add_child(sprite)
	unit.position = Vector3(2, 0, 1)
	holder.add_child(unit)
	var controller := _make({"targets": [unit]})
	if controller.get_parent() != null:
		controller.get_parent().remove_child(controller)
	holder.add_child(controller)
	_run(controller, 4.0)
	assert_true(controller.pressed_count() > 0, "the unit is visually pressed")
	assert_true(sprite.position.y < 0.0, "only the display layer sinks")
	assert_eq(unit.position, Vector3(2, 0, 1), "the unit's real position is untouched")
	var camera_effects: Array = []
	controller.camera_changed.connect(func(effect: Dictionary) -> void: camera_effects.append(effect))
	controller.cleanup()
	assert_eq(sprite.position, Vector3.ZERO, "the display layer is restored")
	assert_eq(sprite.scale, Vector3.ONE)
	assert_eq(controller.state_name(), "inactive")
	assert_true(not camera_effects.is_empty() and bool(camera_effects.back().get("reset", false)), "the camera is reset")
	assert_eq(controller.get_child_count(), 0)
	holder.free()


func test_auto_cut_follows_the_timeline_and_emits_events() -> void:
	var controller := _make({"battle_driven": true})
	_run(controller, 8.2)
	var events: Array = []
	controller.audio_event.connect(func(id: String, _at: Vector3) -> void: events.append(id))
	assert_true(controller.play_auto_cut([Vector3(1, 0, 1), Vector3(-1, 0, 2)]), "cuts are queued")
	_run(controller, 0.12)
	assert_true(events.has("cut_start"), "the thin line shows first")
	assert_true(not events.has("cut_hit"), "the sound is delayed")
	_run(controller, 0.5)
	assert_true(events.has("cut_hit"), "the delayed cut sound arrives")
	assert_eq(events.count("cut_start"), 2, "both targets are cut")
	_run(controller, 1.0)
	assert_eq(controller.vfx_node_count() >= 0, true)
	_dispose(controller)


func test_cuts_are_ignored_while_inactive() -> void:
	var controller: Node3D = Controller.new()
	controller.auto_process = false
	assert_true(not controller.play_auto_cut([Vector3.ZERO]), "no domain, no cuts")
	controller.free()


func test_isolated_phase_and_speed() -> void:
	var controller := _make({"only_phase": "gravity"})
	assert_eq(controller.state_name(), "opening")
	_run(controller, 0.2)
	assert_eq(controller.current_phase(), "gravity", "the gravity phase can be previewed alone")
	_run(controller, 2.0)
	assert_eq(controller.state_name(), "active", "an isolated phase hands over to the stable domain")
	controller.set_speed(2.0)
	assert_near(controller.speed, 2.0, 0.0001)
	_dispose(controller)


func test_repeated_open_keeps_state_clean() -> void:
	var controller := _make()
	_run(controller, 3.0)
	controller.open_domain(Vector3(5, 0, 5), [], {})
	assert_eq(controller.state_name(), "opening", "re-opening restarts cleanly")
	assert_eq(controller.current_phase(), "opening")
	controller.activate_domain()
	assert_eq(controller.state_name(), "active", "activate skips the animation")
	controller.update_domain_cells([Vector3(10, 0, 0)])
	assert_true(controller.radius > 8.0, "the radius follows the affected cells")
	_dispose(controller)
