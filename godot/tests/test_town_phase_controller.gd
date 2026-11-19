extends "res://tests/test_case.gd"

const TownPhaseController = preload("res://shared/scenery/town/town_phase_controller.gd")


func _tagged_node(node_name: String, phase: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.set_meta("phase", phase)
	return node


func _make_fixture() -> Dictionary:
	var sun := DirectionalLight3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	var root := Node3D.new()
	var day_node := _tagged_node("DayProp", "day")
	var night_node := _tagged_node("NightProp", "night")
	var both_node := _tagged_node("BothProp", "both")
	root.add_child(day_node)
	root.add_child(night_node)
	root.add_child(both_node)
	var lamp := Node3D.new()
	lamp.name = "Lamp"
	lamp.set_meta("night_light", true)
	var light := OmniLight3D.new()
	light.light_energy = 0.0
	lamp.add_child(light)
	root.add_child(lamp)
	var controller := TownPhaseController.new()
	controller.setup(sun, env, null, root)
	return {
		"controller": controller,
		"sun": sun,
		"root": root,
		"day": day_node,
		"night": night_node,
		"both": both_node,
		"light": light,
	}


func _free_fixture(fixture: Dictionary) -> void:
	fixture["controller"].free()
	fixture["sun"].free()
	fixture["root"].free()


func test_apply_night_switches_lighting_props_and_lamps() -> void:
	var fixture := _make_fixture()
	var controller: Variant = fixture["controller"]
	var sun: DirectionalLight3D = fixture["sun"]
	var day_node: Node3D = fixture["day"]
	var night_node: Node3D = fixture["night"]
	var both_node: Node3D = fixture["both"]
	var light: OmniLight3D = fixture["light"]

	controller.apply_phase("night", false)

	assert_near(sun.light_energy, 0.35, 0.0001, "night sun energy")
	var night_color: Color = sun.light_color
	assert_true(night_color.is_equal_approx(Color("#8aa8ff")), "night moonlight color")
	assert_eq(day_node.visible, false, "day props are hidden at night")
	assert_eq(night_node.visible, true, "night props are visible at night")
	assert_eq(both_node.visible, true, "both props stay visible at night")
	assert_true(light.light_energy > 0.0, "lamps turn on at night")
	assert_eq(controller.current_phase(), "night", "controller reports night")
	_free_fixture(fixture)


func test_apply_day_restores_defaults() -> void:
	var fixture := _make_fixture()
	var controller: Variant = fixture["controller"]
	var sun: DirectionalLight3D = fixture["sun"]
	var day_node: Node3D = fixture["day"]
	var night_node: Node3D = fixture["night"]
	var both_node: Node3D = fixture["both"]
	var light: OmniLight3D = fixture["light"]

	controller.apply_phase("night", false)
	controller.apply_phase("day", false)

	assert_near(sun.light_energy, 1.25, 0.0001, "day sun energy")
	var day_color: Color = sun.light_color
	assert_true(day_color.is_equal_approx(Color("#ffd9a8")), "day sun color")
	assert_eq(day_node.visible, true, "day props are visible by day")
	assert_eq(night_node.visible, false, "night props are hidden by day")
	assert_eq(both_node.visible, true, "both props stay visible by day")
	assert_near(light.light_energy, 0.0, 0.0001, "lamps turn off by day")
	_free_fixture(fixture)


func test_invalid_phase_falls_back_to_day() -> void:
	var fixture := _make_fixture()
	var controller: Variant = fixture["controller"]
	var sun: DirectionalLight3D = fixture["sun"]
	var day_node: Node3D = fixture["day"]
	var night_node: Node3D = fixture["night"]

	controller.apply_phase("night", false)
	controller.apply_phase("noon", false)

	assert_eq(controller.current_phase(), "day", "an invalid phase falls back to day")
	assert_near(sun.light_energy, 1.25, 0.0001, "invalid phase restores day lighting")
	assert_eq(day_node.visible, true, "day props are visible after fallback")
	assert_eq(night_node.visible, false, "night props are hidden after fallback")
	_free_fixture(fixture)
