extends "res://tests/test_case.gd"

const TownData = preload("res://shared/resources/town_data.gd")
const TownArt = preload("res://shared/scenery/town/town_art.gd")
const TownBuildings = preload("res://shared/scenery/town/town_buildings.gd")
const TownNpcRoster = preload("res://shared/scenery/town/town_npc_roster.gd")
const Pickups = preload("res://shared/gameplay/pickups.gd")

const TERRACE_Y := 1.5
const TOWN_BOUNDS := Rect2(-20.0, -20.0, 40.0, 40.0)


# 自造数据：左侧一块台地（y=1.5），台地上一栋房/一个 NPC/一个采集点，
# 台地外各放一份对照，另有一栋显式 "y" 的建筑。
func _elevated_data() -> Dictionary:
	return {
		"bounds": {"x0": -20, "z0": -20, "x1": 20, "z1": 20},
		"terraces": [
			{
				"rect": [-14, -14, -4, -6],
				"y": TERRACE_Y,
				"top": "flagstone",
				"from_y": 0.0,
				"stairs": [],
			}
		],
		"buildings": [
			{
				"id": "on_terrace",
				"kind": "house",
				"x0": -12,
				"x1": -6,
				"z_front": -8,
				"depth": 4,
				"door_x": -9,
				"door_w": 1.6,
			},
			{
				"id": "flat_house",
				"kind": "house",
				"x0": 2,
				"x1": 8,
				"z_front": 4,
				"depth": 4,
				"door_x": 5,
				"door_w": 1.6,
			},
			{
				"id": "fixed_house",
				"kind": "house",
				"x0": 12,
				"x1": 18,
				"z_front": 4,
				"depth": 4,
				"door_x": 15,
				"door_w": 1.6,
				"y": 3.0,
			},
		],
		"npcs": [
			{"id": "npc_terrace", "sprite": "elder", "x": -9.0, "z": -10.0},
			{"id": "npc_flat", "sprite": "elder", "x": 5.0, "z": 2.0},
		],
		"pickups": [
			{
				"id": "terrace_herb",
				"item": "herb",
				"sprite": "prop_grass.png",
				"x": -9.0,
				"z": -10.0,
			},
			{
				"id": "flat_herb",
				"item": "herb",
				"sprite": "prop_grass.png",
				"x": 5.0,
				"z": 2.0,
			},
		],
	}


func test_buildings_follow_terrace_height() -> void:
	var data := _elevated_data()
	var parent := Node3D.new()
	var buildings := TownBuildings.new()
	buildings.build_buildings(parent, data, TownArt.new())
	var raised := parent.get_node_or_null("Buildings/on_terrace") as Node3D
	assert_true(raised != null, "the raised house is built")
	if raised != null:
		assert_near(raised.position.y, TERRACE_Y, 0.0001, "the house sits on the terrace")
		assert_true(
			raised.get_node_or_null("Facade_on_terrace") != null,
			"the facade is part of the raised house"
		)
	var flat := parent.get_node_or_null("Buildings/flat_house") as Node3D
	assert_true(flat != null, "the flat house is built")
	if flat != null:
		assert_near(flat.position.y, 0.0, 0.0001, "no terrace keeps the old height")
	var fixed := parent.get_node_or_null("Buildings/fixed_house") as Node3D
	assert_true(fixed != null, "the explicit-y house is built")
	if fixed != null:
		assert_near(fixed.position.y, 3.0, 0.0001, "an explicit y wins over the ground height")
	parent.free()


func test_npc_initial_height_follows_ground() -> void:
	var data := _elevated_data()
	var parent := Node3D.new()
	var roster := TownNpcRoster.new()
	roster.build(
		parent,
		data.get("npcs", []),
		TOWN_BOUNDS,
		[],
		[],
		Callable(),
		data
	)
	var raised := roster.nodes.get("npc_terrace") as Node3D
	assert_true(raised != null, "the terrace npc is built")
	if raised != null:
		assert_near(raised.position.y, TERRACE_Y, 0.0001, "the npc starts on the terrace")
	var flat := roster.nodes.get("npc_flat") as Node3D
	assert_true(flat != null, "the flat npc is built")
	if flat != null:
		assert_near(flat.position.y, 0.0, 0.0001, "a flat npc keeps the old height")
	parent.free()


func test_pickup_height_uses_ground_fn() -> void:
	var data := _elevated_data()
	var root := Node3D.new()
	var entries: Array = Pickups.parse_entries(data.get("pickups", []))
	var ground_fn := func(x: float, z: float) -> float: return TownData.ground_height(data, x, z)
	var raised := Pickups.spawn(root, entries[0], ground_fn)
	assert_true(raised != null, "the terrace pickup is built")
	if raised != null:
		assert_near(raised.position.y, TERRACE_Y, 0.0001, "the pickup sits on the terrace")
	var flat := Pickups.spawn(root, entries[1], ground_fn)
	assert_true(flat != null, "the flat pickup is built")
	if flat != null:
		assert_near(flat.position.y, 0.0, 0.0001, "a flat pickup keeps the old height")
	var raw_pickups: Array = data.get("pickups", [])
	var plain_entry := Pickups.parse_entry(raw_pickups[0], 0)
	var plain := Pickups.spawn(root, plain_entry)
	assert_true(plain != null, "a pickup without ground_fn is still built")
	if plain != null:
		assert_near(plain.position.y, 0.0, 0.0001, "no ground_fn keeps the old height")
	root.free()


func test_forest_points_default_and_override() -> void:
	assert_eq(TownData.forest_sign({}), Vector2(5.4, 20.7), "default forest sign")
	assert_eq(TownData.forest_return({}), Vector2(0.0, 19.2), "default forest return")
	var custom := {"forest": {"sign": [1.5, 2.5], "return": [-3.0, 4.0]}}
	assert_eq(TownData.forest_sign(custom), Vector2(1.5, 2.5), "custom forest sign")
	assert_eq(TownData.forest_return(custom), Vector2(-3.0, 4.0), "custom forest return")
	var malformed := {"forest": {"sign": "here", "return": [1.0]}}
	assert_eq(TownData.forest_sign(malformed), Vector2(5.4, 20.7), "bad sign falls back")
	assert_eq(TownData.forest_return(malformed), Vector2(0.0, 19.2), "bad return falls back")


func test_unlocked_zones_default_rules() -> void:
	assert_eq(TownData.unlocked_zones({}, Vector2(-40.0, 0.0)), ["west_street"], "west rule")
	assert_eq(TownData.unlocked_zones({}, Vector2(30.0, 0.0)), ["gate"], "gate rule")
	assert_eq(TownData.unlocked_zones({}, Vector2(0.0, 0.0)), [], "no zone in the middle")
	assert_eq(
		TownData.unlocked_zones({"unlock_zones": "nope"}, Vector2(-40.0, 0.0)),
		["west_street"],
		"a malformed unlock_zones falls back"
	)


func test_unlocked_zones_from_data() -> void:
	var data := {
		"unlock_zones": [
			{"id": "west_street", "x_lt": -36.0},
			{"id": "gate", "x_gt": 22.0},
			{"id": "south", "z_gt": 15.0},
			{"id": "south_west", "x_lt": 0.0, "z_gt": 15.0},
		],
	}
	assert_eq(
		TownData.unlocked_zones(data, Vector2(-40.0, 20.0)),
		["west_street", "south", "south_west"],
		"every satisfied zone is listed in data order"
	)
	assert_eq(TownData.unlocked_zones(data, Vector2(30.0, -20.0)), ["gate"], "gate only")
	assert_eq(TownData.unlocked_zones(data, Vector2(0.0, 0.0)), [], "no zone in the middle")
