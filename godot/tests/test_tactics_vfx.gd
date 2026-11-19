extends "res://tests/test_case.gd"

# 技能特效数据表与 3D 舞台接线的测试：配置可解析、图集/行号有效、
# 全部武学与敌人招式都能解析出特效，事件能生成特效节点，酒馆墙体与森林障碍物有素材。

const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")
const TacticsStage = preload("res://features/tactics/tactics_stage.gd")
const VfxTable = preload("res://features/tactics/tactics_vfx_table.gd")
const GameState = preload("res://core/game_state.gd")

const CONFIG_PATH := "res://data/tactics_vfx.json"
const MARTIALS_PATH := "res://data/martials.json"
const ENEMIES_PATH := "res://data/enemies.json"
const VFX_DIR := "res://assets/vfx/"
const TAVERN_GROUP := [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": 5}]
const FOREST_GROUP := [{"id": "bandit", "count": 2}]

const SHEET_ROWS := {
	"vfx_slash": 3,
	"vfx_thrust_sweep": 2,
	"vfx_combo": 2,
	"vfx_heavy_charge": 2,
	"vfx_projectile": 3,
	"vfx_counter": 3,
	"vfx_taiji_parry": 2,
	"vfx_jianyi": 3,
	"vfx_hit": 2,
	"vfx_stun": 2,
	"vfx_support": 3,
	"vfx_dust": 2,
}
const ENEMY_MOVE_TYPES := ["heavy", "sweep", "thrust", "ranged", "default"]


func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return null
	return JSON.parse_string(text)


func _make_battle(map_id: String, group: Array) -> Variant:
	GameState.reset()
	var built: Dictionary = TacticsSetup.build(map_id, group, null, 1)
	if not bool(built.get("ok", false)):
		return null
	return built["battle"]


func _build_stage(battle: Variant, backdrop: String) -> Variant:
	var stage: Variant = TacticsStage.new()
	stage.build(battle, backdrop)
	return stage


func _spec_is_filled(raw: Variant) -> bool:
	if raw is Dictionary:
		return not (raw as Dictionary).is_empty()
	if raw is Array:
		return not (raw as Array).is_empty()
	return false


func _collect_specs(raw: Variant, out: Array) -> void:
	if raw is Dictionary:
		var dict: Dictionary = raw
		if dict.has("sheet"):
			out.append(dict)
		for key in dict.keys():
			_collect_specs(dict[key], out)
	elif raw is Array:
		for item in raw:
			_collect_specs(item, out)


func test_config_parses() -> void:
	var raw: Variant = _read_json(CONFIG_PATH)
	assert_true(raw is Dictionary, "tactics_vfx.json parses as an object")
	if not (raw is Dictionary):
		return
	var config: Dictionary = raw
	for key in ["sheets", "martials", "enemy_moves", "events", "default"]:
		assert_true(config.has(key), "config has a %s section" % key)
	var sheets: Dictionary = config.get("sheets", {})
	assert_eq(sheets.size(), SHEET_ROWS.size(), "all vfx sheets are registered")


func test_sheet_files_and_row_counts() -> void:
	var config: Dictionary = VfxTable.config()
	var sheets: Dictionary = config.get("sheets", {})
	for raw_name in SHEET_ROWS.keys():
		var sheet := str(raw_name)
		assert_eq(int(sheets.get(sheet, -1)), int(SHEET_ROWS[sheet]),
			"%s declares its row count" % sheet)
		var path := VFX_DIR + sheet + ".png"
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		assert_true(image != null and not image.is_empty(), "%s loads" % sheet)


func test_every_spec_uses_a_valid_sheet_row() -> void:
	var specs: Array = []
	_collect_specs(VfxTable.config(), specs)
	assert_true(specs.size() >= 20, "the table lists many effect specs")
	for raw_spec in specs:
		var spec: Dictionary = raw_spec
		var sheet := str(spec.get("sheet", ""))
		assert_true(SHEET_ROWS.has(sheet), "spec references a known sheet: %s" % sheet)
		if not SHEET_ROWS.has(sheet):
			continue
		var row := int(spec.get("row", 0))
		assert_true(row >= 0 and row < int(SHEET_ROWS[sheet]),
			"%s row %d is inside 0..%d" % [sheet, row, int(SHEET_ROWS[sheet]) - 1])


func test_all_martials_resolve_effects() -> void:
	var raw: Variant = _read_json(MARTIALS_PATH)
	assert_true(raw is Array, "martials.json parses")
	if not (raw is Array):
		return
	var martials: Array = raw
	assert_eq(martials.size(), 10, "the game defines ten martials")
	for raw_entry in martials:
		if not (raw_entry is Dictionary):
			continue
		var martial: Dictionary = raw_entry
		var martial_id := str(martial.get("id", ""))
		assert_true(_spec_is_filled(VfxTable.cast_spec(martial_id)),
			"%s has a cast effect" % martial_id)
		assert_true(_spec_is_filled(VfxTable.hit_spec(martial_id)),
			"%s has a hit effect" % martial_id)
	assert_true(_spec_is_filled(VfxTable.cast_spec("__missing_martial__")),
		"unknown martials fall back to the default effect")


func test_all_enemy_moves_resolve_effects() -> void:
	var raw: Variant = _read_json(ENEMIES_PATH)
	assert_true(raw is Array, "enemies.json parses")
	if not (raw is Array):
		return
	var enemies: Array = raw
	var moves := 0
	for raw_entry in enemies:
		if not (raw_entry is Dictionary):
			continue
		var enemy: Dictionary = raw_entry
		var table: Array = enemy.get("moves", [])
		for raw_move in table:
			if not (raw_move is Dictionary):
				continue
			var move: Dictionary = raw_move
			var move_id := str(move.get("id", ""))
			var move_type := str(move.get("type", ""))
			moves += 1
			assert_true(_spec_is_filled(VfxTable.enemy_cast(move_id, move_type)),
				"enemy move %s has a cast effect" % move_id)
			assert_true(_spec_is_filled(VfxTable.enemy_hit(move_id, move_type)),
				"enemy move %s has a hit effect" % move_id)
			assert_true(_spec_is_filled(VfxTable.enemy_cast(move_id, "")),
				"enemy move %s resolves by id alone" % move_id)
	assert_true(moves >= 8, "every enemy defines moves")
	for raw_type in ENEMY_MOVE_TYPES:
		var move_type := str(raw_type)
		assert_true(_spec_is_filled(VfxTable.enemy_cast("", move_type)),
			"move type %s resolves an effect" % move_type)


func test_stage_show_events_with_context() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _build_stage(battle, "tavern")
	stage.set_state(battle, {})
	var player = null
	var enemy = null
	for unit in battle.units:
		if not unit.is_alive():
			continue
		if unit.side == "player" and player == null:
			player = unit
		elif unit.side == "enemy" and enemy == null:
			enemy = unit
	assert_true(player != null and enemy != null, "both sides have a living unit")
	if player == null or enemy == null:
		stage.free()
		return
	var context := {
		"attacker_pos": player.pos, "target_cell": enemy.pos,
		"martial_id": "basic_sword",
	}
	var before := int(stage.fx.effect_count())
	stage.show_events([
		{"type": "attack", "unit": str(player.id), "martial_id": "basic_sword",
			"target": enemy.pos},
		{"type": "hit", "attacker": str(player.id), "defender": str(enemy.id),
			"damage": 4, "relation": "front", "reaction": "", "verdict": 0,
			"perfect": false},
		{"type": "counter_hit", "attacker": str(enemy.id),
			"defender": str(player.id), "damage": 2},
		{"type": "stun", "unit": str(enemy.id)},
		{"type": "jianyi", "unit": str(player.id), "defender": str(enemy.id),
			"damage": 9},
	], context)
	assert_true(int(stage.fx.effect_count()) > before, "the event batch spawns vfx")
	var legacy_before := int(stage.fx.effect_count())
	stage.show_events([{
		"type": "hit", "attacker": str(player.id), "defender": str(enemy.id),
		"damage": 1, "relation": "front",
	}])
	assert_true(int(stage.fx.effect_count()) > legacy_before,
		"one-argument show_events still works")
	stage.free()


func test_tavern_wall_rows_have_props() -> void:
	var battle: Variant = _make_battle("tavern_brawl", TAVERN_GROUP)
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _build_stage(battle, "tavern")
	var root = stage.tiles.props_root()
	assert_true(root != null and str(root.name) == "Props",
		"props are grouped under a Props node")
	if root == null:
		stage.free()
		return
	var walls := 0
	var rows: Array = [0, int(battle.grid.height) - 1]
	for raw_row in rows:
		var row := int(raw_row)
		for x in range(int(battle.grid.width)):
			var cell := Vector2i(x, row)
			if str(battle.grid.terrain_at(cell)) != "wall":
				continue
			walls += 1
			assert_true(root.get_node_or_null("Prop_%d_%d" % [x, row]) != null,
				"wall cell %s has a prop sprite" % str(cell))
	assert_true(walls > 0, "the tavern map has wall cells on both rows")
	stage.free()


func test_obstacle_cells_use_sprites_not_solid_boxes() -> void:
	var battle: Variant = _make_battle("forest_clearing", FOREST_GROUP)
	assert_true(battle != null, "the forest battle is assembled")
	if battle == null:
		return
	var stage: Variant = _build_stage(battle, "forest")
	var obstacles := 0
	for y in range(int(battle.grid.height)):
		for x in range(int(battle.grid.width)):
			var cell := Vector2i(x, y)
			if str(battle.grid.terrain_at(cell)) != "obstacle":
				continue
			obstacles += 1
			var prop = stage.tiles.prop_node(cell)
			assert_true(prop != null, "obstacle cell %s has a prop sprite" % str(cell))
			if prop == null:
				continue
			var top: float = stage.tiles.top_y(cell)
			assert_near(float(prop.position.y), top, 0.01,
				"prop %s stands on the tile top" % str(cell))
			var tile = stage.tiles.tile_node(cell)
			var column = tile.get_node_or_null("Column")
			if column is MeshInstance3D:
				var mesh_node: MeshInstance3D = column
				if mesh_node.mesh is BoxMesh:
					var box: BoxMesh = mesh_node.mesh
					var upper := mesh_node.position.y + box.size.y * 0.5
					assert_true(upper <= top + 0.02,
						"obstacle %s has no solid box above the ground" % str(cell))
			assert_true(tile.get_node_or_null("Top") is MeshInstance3D,
				"obstacle %s keeps a flat tile surface" % str(cell))
	assert_true(obstacles > 0, "the forest map has obstacle cells")
	stage.free()
