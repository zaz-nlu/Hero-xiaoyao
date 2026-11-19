extends "res://tests/test_case.gd"

const TownPhase = preload("res://core/town_phase.gd")

const FIELDS: Array[String] = [
	"sun_rotation",
	"sun_color",
	"sun_energy",
	"sky_top",
	"sky_horizon",
	"sky_ground_horizon",
	"sky_ground_bottom",
	"ambient_energy",
	"fog_color",
	"lamps_on",
	"mountain",
]


func test_presets_have_all_fields() -> void:
	for phase in TownPhase.PHASES:
		var preset: Dictionary = TownPhase.preset(phase)
		for field in FIELDS:
			assert_true(preset.has(field), "%s preset has %s" % [phase, field])


func test_day_preset_matches_existing_lighting() -> void:
	var day: Dictionary = TownPhase.preset("day")
	assert_near(float(day["sun_energy"]), 1.25, 0.0001, "day sun energy")
	var sun_color: Color = day["sun_color"]
	assert_eq(sun_color, Color("#ffd9a8"), "day sun color")
	var sun_rotation: Vector3 = day["sun_rotation"]
	assert_true(
		sun_rotation.is_equal_approx(Vector3(-48.0, -38.0, 0.0)), "day sun rotation"
	)
	assert_eq(bool(day["lamps_on"]), false, "day lamps are off")
	assert_eq(str(day["mountain"]), "bg_mountains.png", "day uses the daytime mountains")


func test_is_valid_and_next_cycle() -> void:
	assert_true(TownPhase.is_valid("day"), "day is valid")
	assert_true(TownPhase.is_valid("dusk"), "dusk is valid")
	assert_true(TownPhase.is_valid("night"), "night is valid")
	assert_true(not TownPhase.is_valid("noon"), "noon is invalid")
	assert_eq(TownPhase.next("day"), "dusk", "day -> dusk")
	assert_eq(TownPhase.next("dusk"), "night", "dusk -> night")
	assert_eq(TownPhase.next("night"), "day", "night -> day")
	assert_eq(TownPhase.next("noon"), "day", "an invalid phase falls back to day")


func test_lerp_preset_endpoints_and_midpoint() -> void:
	var day: Dictionary = TownPhase.preset("day")
	var night: Dictionary = TownPhase.preset("night")

	var at_start: Dictionary = TownPhase.lerp_preset(day, night, 0.0)
	assert_near(float(at_start["sun_energy"]), 1.25, 0.0001, "t=0 keeps a energy")
	assert_eq(bool(at_start["lamps_on"]), false, "t=0 keeps a lamps")
	assert_eq(str(at_start["mountain"]), "bg_mountains.png", "t=0 keeps a mountain")

	var at_mid: Dictionary = TownPhase.lerp_preset(day, night, 0.5)
	assert_near(float(at_mid["sun_energy"]), 0.8, 0.0001, "t=0.5 averages energy")
	assert_eq(bool(at_mid["lamps_on"]), true, "t=0.5 switches to b lamps")
	assert_eq(
		str(at_mid["mountain"]), "bg_night_mountains.png", "t=0.5 switches to b mountain"
	)
	var day_color: Color = day["sun_color"]
	var night_color: Color = night["sun_color"]
	var mid_color: Color = at_mid["sun_color"]
	assert_true(
		mid_color.is_equal_approx(day_color.lerp(night_color, 0.5)), "t=0.5 averages color"
	)

	var at_end: Dictionary = TownPhase.lerp_preset(day, night, 1.0)
	assert_near(float(at_end["sun_energy"]), 0.35, 0.0001, "t=1 uses b energy")
	assert_eq(bool(at_end["lamps_on"]), true, "t=1 uses b lamps")
	assert_eq(str(at_end["mountain"]), "bg_night_mountains.png", "t=1 uses b mountain")
