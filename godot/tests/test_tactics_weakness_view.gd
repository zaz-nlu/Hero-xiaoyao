extends "res://tests/test_case.gd"

# 弱点可视化：头顶图标数量、刷新弹出/清空移除、弱点飘字、单位卡弱点行与缺素材回退。

const GameState = preload("res://core/game_state.gd")
const TacticsSetup = preload("res://core/tactics/tactics_setup.gd")
const TacticsStage = preload("res://features/tactics/tactics_stage.gd")
const TacticsWeakness = preload("res://core/tactics/tactics_weakness.gd")
const UnitCard = preload("res://features/tactics/tactics_unit_card.gd")
const UI = preload("res://features/tactics/tactics_ui_style.gd")

const TAVERN_GROUP := [{"id": "ma_youwei", "count": 1}, {"id": "bandit", "count": 5}]
const MISSING_DIR := "res://assets/ui/__missing_tactics__/"
const NONE := "none"


func _make_battle() -> Variant:
	GameState.reset()
	var built: Dictionary = TacticsSetup.build("tavern_brawl", TAVERN_GROUP, null, 1)
	if not bool(built.get("ok", false)):
		return null
	return built["battle"]


func _make_stage(battle: Variant) -> Variant:
	var stage: Variant = TacticsStage.new()
	stage.build(battle, "tavern")
	return stage


func _boss(battle: Variant) -> Variant:
	return battle.get_unit(str(battle.leader_id))


func _first_minion(battle: Variant) -> Variant:
	for unit in battle.units:
		if unit.side == "enemy" and str(unit.id) != str(battle.leader_id):
			return unit
	return null


func _weak_node(stage: Variant, uid: String) -> Node:
	var root = stage.units.actor(uid)
	if root == null:
		return null
	return root.get_node_or_null("WeaknessIcons")


func _non_none(unit: Variant) -> int:
	var count := 0
	for raw in unit.weaknesses:
		var color := str(raw)
		if color != "" and color != NONE:
			count += 1
	return count


func test_enemy_weakness_icons_follow_slots() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var stage: Variant = _make_stage(battle)
	var boss: Variant = _boss(battle)
	assert_true(boss != null, "the tavern group has a leader")
	if boss != null:
		var weak: Variant = _weak_node(stage, str(boss.id))
		assert_true(weak != null, "the boss actor carries weakness icons")
		if weak != null:
			assert_true(_non_none(boss) > 0, "the boss has usable weakness slots")
			assert_eq(weak.icon_count(), _non_none(boss),
				"one icon per non-none slot")
			if weak.get_child_count() > 0:
				var icon = weak.get_child(0)
				assert_true(icon is Sprite3D, "icons are Sprite3D billboards")
				if icon is Sprite3D:
					var sprite := icon as Sprite3D
					assert_eq(sprite.billboard, BaseMaterial3D.BILLBOARD_ENABLED,
						"the icon always faces the camera")
					assert_true(not sprite.shaded, "the icon is unshaded")
					assert_true(sprite.no_depth_test, "the icon ignores depth")
	var minion: Variant = _first_minion(battle)
	assert_true(minion != null, "the tavern group has minions")
	if minion != null:
		var weak_minion: Variant = _weak_node(stage, str(minion.id))
		assert_true(weak_minion != null, "minions still have the icon container")
		if weak_minion != null:
			assert_eq(weak_minion.icon_count(), 0, "minions show no weakness icons")
	stage.free()


func test_color_change_pops_and_none_removes() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var boss: Variant = _boss(battle)
	var stage: Variant = _make_stage(battle)
	var weak: Variant = _weak_node(stage, str(boss.id))
	assert_true(weak != null, "the boss actor carries weakness icons")
	if weak == null:
		stage.free()
		return
	var before := int(weak.icon_count())
	var pops_before := int(weak.pop_count())
	var next := "ziqi" if str(boss.weaknesses[0]) != "ziqi" else "neili"
	boss.weaknesses[0] = next
	stage.set_state(battle, {})
	assert_true(int(weak.pop_count()) > pops_before,
		"changing a slot colour plays the pop animation")
	assert_eq(int(weak.icon_count()), before, "the changed slot keeps its icon")
	boss.weaknesses[0] = NONE
	stage.set_state(battle, {})
	assert_eq(int(weak.icon_count()), before - 1, "a none slot removes its icon")
	stage.free()


func test_cleared_weaknesses_remove_every_icon() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var boss: Variant = _boss(battle)
	var stage: Variant = _make_stage(battle)
	var weak: Variant = _weak_node(stage, str(boss.id))
	assert_true(weak != null, "the boss actor carries weakness icons")
	if weak != null:
		assert_true(int(weak.icon_count()) > 0, "icons exist before the break")
		TacticsWeakness.clear(boss)
		stage.set_state(battle, {})
		assert_eq(int(weak.icon_count()), 0, "breaking clears every icon")
		boss.weaknesses = ["neili", "ziqi"]
		stage.set_state(battle, {})
		assert_eq(int(weak.icon_count()), 2, "redrawn slots show icons again")
		assert_true(int(weak.pop_count()) > 0, "redrawn slots pop in")
	stage.free()


func test_weak_hit_number_is_gold_and_labeled() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var boss: Variant = _boss(battle)
	var stage: Variant = _make_stage(battle)
	stage.set_state(battle, {})
	stage.show_events([{
		"type": "hit", "attacker": "player", "defender": str(boss.id),
		"damage": 12, "relation": "front", "weak": true,
		"weak_color": "neili",
	}])
	var found := false
	for child in stage.fx.get_children():
		if not (child is Label3D):
			continue
		var label := child as Label3D
		if not label.text.contains("弱点"):
			continue
		found = true
		assert_true(label.modulate.g > 0.75 and label.modulate.b < 0.5,
			"the weakness number is gold")
		assert_true(label.font_size > 64, "the weakness number is slightly larger")
	assert_true(found, "a weak hit spawns a 弱点 damage number")
	stage.free()


func test_unit_card_shows_weakness_row_for_boss_only() -> void:
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle is assembled")
	if battle == null:
		return
	var boss: Variant = _boss(battle)
	var card: Variant = UnitCard.new()
	card.show_unit(battle, str(boss.id))
	assert_true(card.weakness_row_visible(), "the boss card shows the 弱点 row")
	assert_eq(card.weakness_icon_count(), _non_none(boss),
		"the card lists every non-none slot")
	var minion: Variant = _first_minion(battle)
	if minion != null:
		card.show_unit(battle, str(minion.id))
		assert_true(not card.weakness_row_visible(),
			"minion cards hide the 弱点 row")
		assert_eq(card.weakness_icon_count(), 0)
	card.free()


func test_missing_weak_art_falls_back_without_errors() -> void:
	UI.set_texture_dir(MISSING_DIR)
	var battle: Variant = _make_battle()
	assert_true(battle != null, "the tavern battle still assembles")
	if battle != null:
		var boss: Variant = _boss(battle)
		var stage: Variant = _make_stage(battle)
		var weak: Variant = _weak_node(stage, str(boss.id))
		assert_true(weak != null, "the icon container is built without art")
		if weak != null:
			assert_eq(int(weak.icon_count()), _non_none(boss),
				"fallback icons cover the same slots")
			if weak.get_child_count() > 0:
				var icon = weak.get_child(0)
				assert_true(icon is Sprite3D and (icon as Sprite3D).texture != null,
					"a tinted dot texture stands in for the missing art")
		stage.free()
	UI.reset_texture_dir()
