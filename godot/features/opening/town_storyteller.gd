extends Node

# 序章里书生讲故事（在真正的紫霞镇地图上演出，不另开动画场景）：
# 书生站在街边，镇民围成半圈，任逍遥站在人群里；黑场淡入，《少年剑影》响起，播放对话，
# 对话结束后镇民散去（临时演员移除）、书生恢复游走、玩家拿回控制权。
# 作为小镇的子节点工作，只使用小镇已有的公开接口：npc_nodes / npc_wander / player /
# player_pos / follow_target / dialogue_view / input_blocked / prompt_label / snap_camera()。
# 时间由 advance(delta) 推进（_process 自动驱动，测试可手动步进）。

signal finished

const Dialogue = preload("res://core/dialogue.gd")
const DataLoader = preload("res://core/data_loader.gd")
const CharacterSprite = preload("res://shared/scene/character_sprite.gd")

enum Phase { FADE_IN, DIALOGUE, DONE }

const FADE_IN := 1.0
const CUE := "opening_town"
const PLAYER_OFFSET := Vector2(-2.6, 1.7)
const CROWD_RADIUS := Vector2(4.4, 2.6)
const CROWD_ARC_DEG := Vector2(25.0, 155.0)   # 以书生正南为 90°，在两侧展开半圈

var town: Node = null
var audio: Variant = null
var phase: int = Phase.FADE_IN
var crowd: Array = []

var _time: float = 0.0
var _scholar_id: String = "scholar"
var _dialogue_path: String = ""
var _saved_wander: Variant = null
var _layer: CanvasLayer = null
var _fade: ColorRect = null
var _done: bool = false


func _process(delta: float) -> void:
	if town != null and not _done:
		advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _done or not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	var key := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	if key_event.pressed and not key_event.echo and key == KEY_ESCAPE:
		finish()


# data 是 OpeningData 校验后的结果（music / storyteller）。
func begin(p_town: Node, p_audio: Variant, data: Dictionary) -> void:
	town = p_town
	audio = p_audio
	var story: Dictionary = data.get("storyteller", {})
	_dialogue_path = str(story.get("dialogue", ""))
	_scholar_id = str(story.get("scholar", "scholar"))
	town.input_blocked = true
	var scholar: Node3D = town.npc_nodes.get(_scholar_id, null)
	var center := Vector2(8.0, 0.5)
	if scholar != null:
		center = Vector2(scholar.position.x, scholar.position.z)
		if town.npc_wander.has(_scholar_id):
			_saved_wander = town.npc_wander[_scholar_id]
			town.npc_wander.erase(_scholar_id)
		scholar.call("set_facing", "down")
		scholar.call("set_moving", false)
	var ids: Array = story.get("crowd", [])
	for index in range(ids.size()):
		var t := float(index) / maxf(1.0, float(ids.size() - 1))
		var angle := deg_to_rad(lerpf(CROWD_ARC_DEG.x, CROWD_ARC_DEG.y, t))
		var pos := center + Vector2(cos(angle) * CROWD_RADIUS.x, sin(angle) * CROWD_RADIUS.y)
		var facing := "right" if pos.x < center.x else "left"
		var actor: Node3D = CharacterSprite.new()
		actor.call("setup", str(ids[index]))
		actor.call("set_facing", facing)
		actor.position = Vector3(pos.x, 0.0, pos.y)
		town.add_child(actor)
		crowd.append(actor)
	town.player_pos = center + PLAYER_OFFSET
	town.player.position = Vector3(town.player_pos.x, 0.0, town.player_pos.y)
	town.player.call("set_facing", "right")
	town.snap_camera()
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)
	if audio != null and audio is Object and audio.has_method("play_cue"):
		audio.play_cue(str((data.get("music", {}) as Dictionary).get("town", CUE)))


func advance(delta: float) -> void:
	if town == null or _done:
		return
	_time += maxf(delta, 0.0)
	if town.prompt_label != null:
		town.prompt_label.visible = false
	if phase == Phase.FADE_IN:
		_fade.color.a = 1.0 - clampf(_time / FADE_IN, 0.0, 1.0)
		if _time >= FADE_IN:
			_start_dialogue()


func finish() -> void:
	if _done:
		return
	_done = true
	phase = Phase.DONE
	for actor in crowd:
		if is_instance_valid(actor):
			if actor.is_inside_tree():
				actor.queue_free()
			else:
				actor.free()
	crowd.clear()
	if _saved_wander != null:
		town.npc_wander[_scholar_id] = _saved_wander
	var view: Variant = town.dialogue_view
	if view != null and view.is_connected("finished", Callable(self, "_on_dialogue_finished")):
		view.disconnect("finished", Callable(self, "_on_dialogue_finished"))
	town.input_blocked = false
	if _fade != null:
		_fade.color.a = 0.0
	finished.emit()


func _start_dialogue() -> void:
	phase = Phase.DIALOGUE
	var lines := _lines()
	var view: Variant = town.dialogue_view
	if lines.is_empty() or view == null:
		finish()
		return
	view.connect("finished", Callable(self, "_on_dialogue_finished"))
	view.call("start", lines)


func _on_dialogue_finished() -> void:
	if phase == Phase.DIALOGUE:
		finish()


func _lines() -> Array:
	if _dialogue_path == "" or not FileAccess.file_exists(_dialogue_path):
		return []
	var speakers: Dictionary = Dialogue.load_speakers(DataLoader.SPEAKERS_PATH).get("defs", {})
	var loaded: Dictionary = Dialogue.load_file(_dialogue_path, speakers)
	if not (loaded.get("errors", []) as Array).is_empty():
		push_warning("opening storyteller dialogue skipped: %s" % str(loaded.get("errors", [])))
		return []
	return loaded.get("lines", [])
