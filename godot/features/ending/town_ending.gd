extends Node

# Demo 结尾（在真正的紫霞镇地图上演出，不另开动画场景）：
# 任逍遥和紫霞等人刚从酒馆出来站在门口街上，《紫殇登场》响起，紫殇从街那头跑来，
# 说完“什么情况？马匪呢？”，镜头慢慢移向北边的紫霞派大门，最后出现“Demo 完”字卡，回到标题。
# 作为小镇的子节点工作，只使用小镇已有的公开接口：player / player_pos / follow_target /
# dialogue_view / input_blocked / tavern_door() / bounds_rect / snap_camera()。
# 时间由 advance(delta) 推进（_process 自动驱动，测试可手动步进）。

signal finished

const Dialogue = preload("res://core/dialogue.gd")
const DataLoader = preload("res://core/data_loader.gd")
const CharacterSprite = preload("res://shared/scene/character_sprite.gd")

enum Phase { INTRO, RUN_IN, DIALOGUE, PAN, CARD, DONE }

const CUE := "zishang_entrance"
const DIALOGUE_PATH := "res://data/dialogues/ending_street.json"
const INTRO_SECONDS := 0.8
const RUN_SECONDS := 3.6
const PAN_SECONDS := 9.0
const CARD_FADE := 2.0
const CARD_AUTO_CLOSE := 12.0
const GATE := Vector3(0.0, 0.0, -21.0)   # 紫霞派大门（town.json 里牌坊在 z=-25）
const GROUP_OFFSETS := [
	{"id": "zixia", "off": Vector2(-1.4, 0.8)},
	{"id": "zixia_disciple", "off": Vector2(-3.0, 0.4)},
	{"id": "zixia_disciple", "off": Vector2(1.6, 0.9)},
	{"id": "zixia_disciple", "off": Vector2(3.2, 0.3)},
]
const PLAYER_OFFSET := Vector2(0.0, 1.8)
const ZISHANG_FROM := Vector2(20.0, 1.8)
const ZISHANG_TO := Vector2(3.8, 1.8)

var town: Node = null
var audio: Variant = null
var phase: int = Phase.INTRO
var zishang: Node3D = null
var group: Array = []

var _time: float = 0.0
var _focus: Node3D = null
var _focus_from: Vector3 = Vector3.ZERO
var _layer: CanvasLayer = null
var _dim: ColorRect = null
var _card: Label = null
var _done: bool = false


func _process(delta: float) -> void:
	if town != null and not _done:
		advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _done or not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	if key == KEY_ESCAPE or (phase == Phase.CARD and (key == KEY_SPACE or key == KEY_ENTER)):
		finish()


# 摆好人物并开始（调用者已经把本节点加到小镇下）。
func begin(p_town: Node, p_audio: Variant) -> void:
	town = p_town
	audio = p_audio
	town.input_blocked = true
	var door: Vector2 = town.tavern_door()
	if door == Vector2.INF:
		door = Vector2(0.0, 0.0)
	var base := _clamp(door + Vector2(0.0, 2.2))
	town.player_pos = _clamp(base + PLAYER_OFFSET)
	town.player.position = Vector3(town.player_pos.x, 0.0, town.player_pos.y)
	town.player.call("set_facing", "right")
	for entry in GROUP_OFFSETS:
		var actor: Node3D = _spawn(str(entry["id"]), _clamp(base + (entry["off"] as Vector2)), "right")
		group.append(actor)
	zishang = _spawn("zishang", _clamp(base + ZISHANG_FROM), "left")
	zishang.call("set_moving", true)
	_focus = Node3D.new()
	_focus.name = "EndingFocus"
	town.add_child(_focus)
	_focus.position = town.player.position
	town.follow_target = _focus
	town.snap_camera()
	_build_overlay()
	if audio != null and audio is Object and audio.has_method("play_cue"):
		audio.play_cue(CUE)


func advance(delta: float) -> void:
	if town == null or _done:
		return
	_time += maxf(delta, 0.0)
	if town.prompt_label != null:
		town.prompt_label.visible = false   # 演出期间不显示“按 E 交谈”提示
	match phase:
		Phase.INTRO:
			_aim_focus(_group_center(), 1.0)
			if _time >= INTRO_SECONDS:
				_enter(Phase.RUN_IN)
		Phase.RUN_IN:
			_run(_time / RUN_SECONDS)
			_aim_focus(_group_center().lerp(_zishang_pos(), 0.5), 1.0)
			if _time >= RUN_SECONDS:
				_run(1.0)
				_start_dialogue()
		Phase.PAN:
			var k := clampf(_time / PAN_SECONDS, 0.0, 1.0)
			var eased := k * k * (3.0 - 2.0 * k)
			_aim_focus(_focus_from.lerp(GATE, eased), 1.0)
			if _time >= PAN_SECONDS:
				_enter(Phase.CARD)
				_card.visible = true
		Phase.CARD:
			var f := clampf(_time / CARD_FADE, 0.0, 1.0)
			_card.modulate.a = f
			_dim.color.a = 0.5 * f
			if _time >= CARD_AUTO_CLOSE:
				finish()


func finish() -> void:
	if _done:
		return
	_done = true
	phase = Phase.DONE
	if town != null and is_instance_valid(town):
		town.input_blocked = false
	finished.emit()


# ---------------------------------------------------------------- 内部

func _enter(next: int) -> void:
	phase = next
	_time = 0.0


func _run(t: float) -> void:
	var k := clampf(t, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - k, 2.0)
	var door: Vector2 = town.tavern_door()
	var base := _clamp(door + Vector2(0.0, 2.2))
	var pos := _clamp(base + ZISHANG_FROM).lerp(_clamp(base + ZISHANG_TO), eased)
	zishang.position = Vector3(pos.x, 0.0, pos.y)
	zishang.call("set_moving", k < 1.0)


func _start_dialogue() -> void:
	_enter(Phase.DIALOGUE)
	var lines := _lines()
	var view: Variant = town.dialogue_view
	if lines.is_empty() or view == null:
		_begin_pan()
		return
	view.connect("finished", Callable(self, "_on_dialogue_finished"), CONNECT_ONE_SHOT)
	view.call("start", lines)


func _on_dialogue_finished() -> void:
	if phase == Phase.DIALOGUE:
		_begin_pan()


func _begin_pan() -> void:
	_focus_from = _focus.position if _focus != null else _group_center()
	_enter(Phase.PAN)


func _aim_focus(target: Vector3, weight: float) -> void:
	if _focus != null:
		_focus.position = _focus.position.lerp(target, clampf(weight, 0.0, 1.0) * 0.12)


func _group_center() -> Vector3:
	var p: Vector3 = town.player.position
	return Vector3(p.x, 0.0, p.z)


func _zishang_pos() -> Vector3:
	return zishang.position if zishang != null else _group_center()


func _spawn(sprite_id: String, pos: Vector2, facing: String) -> Node3D:
	var actor: Node3D = CharacterSprite.new()
	actor.call("setup", sprite_id)
	actor.call("set_facing", facing)
	actor.position = Vector3(pos.x, 0.0, pos.y)
	town.add_child(actor)
	return actor


func _clamp(point: Vector2) -> Vector2:
	var rect: Rect2 = town.bounds_rect
	if rect.size == Vector2.ZERO:
		return point
	return Vector2(clampf(point.x, rect.position.x + 0.5, rect.end.x - 0.5),
		clampf(point.y, rect.position.y + 0.5, rect.end.y - 0.5))


func _lines() -> Array:
	if not FileAccess.file_exists(DIALOGUE_PATH):
		return []
	var speakers: Dictionary = Dialogue.load_speakers(DataLoader.SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(DIALOGUE_PATH, speakers)
	if not (loaded.get("errors", []) as Array).is_empty():
		push_warning("ending dialogue skipped: %s" % str(loaded.get("errors", [])))
		return []
	return loaded.get("lines", [])


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_dim)
	_card = Label.new()
	_card.text = "紫霞派 · 序章 完\n\n感谢游玩\n\n按 空格 回到标题"
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 34)
	_card.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_card.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_card.add_theme_constant_override("outline_size", 10)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.modulate.a = 0.0
	_card.visible = false
	_layer.add_child(_card)
