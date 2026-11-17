extends "res://tests/test_case.gd"

const KAISHAN: Dictionary = {
	"id": "kaishan",
	"name": "开山",
	"type": "heavy",
	"threat": 18,
	"power": 18,
}


func _make_view() -> Variant:
	var view: Variant = load("res://ui/battle_view.gd").new()
	view.build_ui()
	return view


func _popup_texts(stage: Variant) -> String:
	var texts := ""
	for entry in stage.popups:
		var label: Label3D = entry["node"]
		texts += str(label.text) + "\n"
	return texts


func _setup_kaishan(view: Variant) -> void:
	view.battle.intents[0] = KAISHAN.duplicate()
	view.battle.enemies[0].weak_moves = ["kaishan"]
	view.battle.player.stats["skill"] = 30  # initial skill 12 cannot counter threat 22


func test_stage_created_under_view() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	assert_true(view.stage != null, "the stage exists")
	assert_true(view.stage.get_parent() == view, "the stage is a child of the view")
	var index: int = -1
	for i in range(view.get_child_count()):
		if view.get_child(i) == view.stage:
			index = i
	assert_eq(index, 0, "the stage renders below the ui")
	view.free()


func test_hit_creates_damage_popup() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	assert_true(view.stage.popups.size() >= 1, "a hit spawns a damage popup")
	view.free()


func test_enemy_flash_on_damage() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.press_action({"kind": "martial", "id": "basic_sword", "target": 0})
	var sprite: Sprite3D = view.stage.enemy_actors[0].get_node("Sprite") as Sprite3D
	assert_true(sprite.modulate.g < 0.8, "a damaged enemy flashes red")
	view.free()


func test_perfect_counter_popup_text() -> void:
	var view: Variant = _make_view()
	view.start("ma_youwei", 1, false, false)
	view.battle.player.stats["recovery"] = 99
	_setup_kaishan(view)
	view.press_action({"kind": "martial", "id": "taiji", "target": 0})
	assert_true(_popup_texts(view.stage).contains("完美破招"), "a perfect counter shows its popup")
	view.free()


func test_counter_popup() -> void:
	var view: Variant = _make_view()
	view.start("ma_youwei", 1, false, false)
	_setup_kaishan(view)
	view.press_action({"kind": "martial", "id": "taiji", "target": 0})
	assert_true(_popup_texts(view.stage).contains("破"), "a counter shows a break popup")
	view.free()


func test_stun_popup() -> void:
	var view: Variant = _make_view()
	view.start("ma_youwei", 1, false, false)
	_setup_kaishan(view)
	view.battle.enemies[0].toughness_left = 1.0
	view.press_action({"kind": "martial", "id": "taiji", "target": 0})
	assert_true(_popup_texts(view.stage).contains("破势"), "breaking toughness shows a stun popup")
	view.free()


func test_restart_replaces_stage() -> void:
	var view: Variant = _make_view()
	view.start("bandit", 1, false)
	view.start("bandit", 1, false)
	var live_stages: int = 0
	for child in view.get_children():
		if child is Node3D and not child.is_queued_for_deletion():
			live_stages += 1
	assert_eq(live_stages, 1, "restarting leaves exactly one live stage")
	view.free()
