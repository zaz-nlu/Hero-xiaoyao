extends Node3D

const CharacterSprite = preload("res://world/character_sprite.gd")
const GameState = preload("res://core/game_state.gd")

const PLAYER_POS := Vector3(4.2, 0.0, 1.6)
const PLAYER_SPRITE_ID := "ren_xiaoyao"
const ENEMY_POSITIONS: Array = [
	[Vector3(8.4, 0.0, 1.2)],
	[Vector3(7.0, 0.0, 0.2), Vector3(10.8, 0.0, 2.4)],
	[Vector3(6.8, 0.0, -0.2), Vector3(9.8, 0.0, 1.2), Vector3(12.8, 0.0, 2.6)],
	[
		Vector3(7.4, 0.0, -2.6), Vector3(10.8, 0.0, -2.6),
		Vector3(9.0, 0.0, 3.0), Vector3(12.4, 0.0, 3.0),
	],
	[
		Vector3(7.2, 0.0, -2.8), Vector3(10.2, 0.0, -2.8), Vector3(13.2, 0.0, -2.8),
		Vector3(8.7, 0.0, 3.2), Vector3(11.7, 0.0, 3.2),
	],
	[
		Vector3(7.2, 0.0, -2.8), Vector3(10.2, 0.0, -2.8), Vector3(13.2, 0.0, -2.8),
		Vector3(8.7, 0.0, 3.2), Vector3(11.7, 0.0, 3.2), Vector3(14.7, 0.0, 3.2),
	],
]
const CAM_POS := Vector3(6.4, 14.0, 36.0)
const CAM_TARGET := Vector3(6.4, 0.0, 0.0)
const CAM_POS_TAVERN := Vector3(8.0, 13.0, 33.0)
const CAM_TARGET_TAVERN := Vector3(8.0, 0.5, -1.0)
const CAM_FOV := 26.0

const HIT_COLOR := Color(1.0, 0.35, 0.35, 1.0)
const POPUP_LIFE := 0.9
const POPUP_RISE := 1.6
const POPUP_HEIGHT := 2.2

var town: Variant = null
var camera: Camera3D = null
var player_actor: Variant = null
var enemy_actors: Array = []
var popups: Array = []
var origin: Vector3 = Vector3.ZERO

var _bases: Dictionary = {}
var _flashes: Array = []
var _lunges: Array = []
var _cam_pos: Vector3 = CAM_POS
var _cam_target: Vector3 = CAM_TARGET


func _process(delta: float) -> void:
	advance(delta)


# ---------------------------------------------------------------- build

func build(enemy_sprite_ids: Array) -> void:
	_clear_actors()
	_build_town()
	_setup_camera()
	_build_player_actor()
	_build_enemy_actors(enemy_sprite_ids)


func _clear_actors() -> void:
	if player_actor != null and is_instance_valid(player_actor):
		_detach_and_free(player_actor)
	player_actor = null
	for actor in enemy_actors:
		if actor != null and is_instance_valid(actor):
			_detach_and_free(actor)
	enemy_actors.clear()
	_bases.clear()
	_flashes.clear()
	_lunges.clear()


func _detach_and_free(actor: Variant) -> void:
	if not (actor is Node):
		return
	var node: Node = actor
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


func _build_town() -> void:
	if town != null and is_instance_valid(town):
		return
	var backdrop := str(GameState.battle_backdrop)
	_cam_pos = CAM_POS
	_cam_target = CAM_TARGET
	if backdrop == "forest":
		town = load("res://world/forest.gd").new()
		town.set("skip_actors", true)
		add_child(town)
		if not town.is_inside_tree():
			town.build()
		origin = town.arena_origin
	elif backdrop == "tavern":
		town = load("res://world/tavern.gd").new()
		town.set("skip_actors", true)
		town.set("force_state", "brawl")
		add_child(town)
		if not town.is_inside_tree():
			town.build()
		origin = town.arena_origin
		_cam_pos = CAM_POS_TAVERN
		_cam_target = CAM_TARGET_TAVERN
	else:
		town = load("res://world/town.gd").new()
		town.set("skip_actors", true)
		add_child(town)
		if not town.is_inside_tree():
			town.build()
		origin = Vector3.ZERO
	town.set_process(false)


func _setup_camera() -> void:
	if town == null:
		return
	camera = town.camera
	if camera == null:
		return
	camera.fov = CAM_FOV
	camera.position = origin + _cam_pos
	_setup_dof(_cam_pos.distance_to(_cam_target))
	if camera.is_inside_tree():
		camera.look_at(origin + _cam_target, Vector3.UP)
		camera.current = true
	else:
		camera.transform = Transform3D(
			Basis.looking_at(_cam_target - _cam_pos, Vector3.UP), origin + _cam_pos
		)


# The town's depth of field is tuned for the close walking camera; re-centre it on the stage.
func _setup_dof(dist: float) -> void:
	var attributes: Variant = camera.attributes
	if attributes == null:
		return
	attributes.dof_blur_far_distance = dist + 14.0
	attributes.dof_blur_far_transition = 20.0
	attributes.dof_blur_near_distance = dist - 12.0
	attributes.dof_blur_near_transition = 8.0


func _build_player_actor() -> void:
	var actor: Variant = CharacterSprite.new()
	actor.name = "PlayerActor"
	actor.setup(PLAYER_SPRITE_ID)
	actor.set_facing("right")
	actor.position = origin + PLAYER_POS
	add_child(actor)
	player_actor = actor


func _build_enemy_actors(enemy_sprite_ids: Array) -> void:
	if enemy_sprite_ids.is_empty():
		return
	var slot_index: int = clampi(enemy_sprite_ids.size(), 1, 6) - 1
	var slots: Array = ENEMY_POSITIONS[slot_index]
	for i in range(enemy_sprite_ids.size()):
		var actor: Variant = CharacterSprite.new()
		actor.name = "EnemyActor%d" % i
		actor.setup(str(enemy_sprite_ids[i]))
		actor.set_facing("left")
		actor.position = origin + slots[i % slots.size()]
		add_child(actor)
		enemy_actors.append(actor)


# ---------------------------------------------------------------- actors

func actor_position(actor: Node3D) -> Vector3:
	if actor == null:
		return Vector3.ZERO
	return actor.position


func set_actor_tint(actor: Node3D, color: Color) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var sprite_value: Variant = actor.get_node_or_null("Sprite")
	if sprite_value is Sprite3D:
		var sprite: Sprite3D = sprite_value
		sprite.modulate = color


func set_actor_base(actor: Node3D, color: Color) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	_bases[actor.get_instance_id()] = color
	if not _is_flashing(actor):
		set_actor_tint(actor, color)


func flash(actor: Node3D, duration: float = 0.25) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var found := false
	for entry in _flashes:
		if entry["actor"] == actor:
			entry["time"] = duration
			entry["duration"] = maxf(duration, 0.001)
			found = true
			break
	if not found:
		_flashes.append({
			"actor": actor,
			"time": duration,
			"duration": maxf(duration, 0.001),
		})
	set_actor_tint(actor, HIT_COLOR)


func _is_flashing(actor: Node3D) -> bool:
	for entry in _flashes:
		if entry["actor"] == actor and float(entry["time"]) > 0.0:
			return true
	return false


func _apply_base(actor: Variant) -> void:
	if not is_instance_valid(actor):
		return
	var base: Color = Color.WHITE
	if _bases.has(actor.get_instance_id()):
		base = _bases[actor.get_instance_id()]
	set_actor_tint(actor, base)


# ---------------------------------------------------------------- effects

func popup(text: String, world_pos: Vector3, color: Color, size: float = 1.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.02 * size
	label.font_size = 64
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.modulate = color
	label.position = Vector3(world_pos.x, world_pos.y + POPUP_HEIGHT, world_pos.z)
	add_child(label)
	popups.append({
		"node": label,
		"age": 0.0,
		"base_x": label.position.x,
		"base_y": label.position.y,
		"base_z": label.position.z,
		"color": color,
	})


func lunge(actor: Node3D, dx: float, duration: float = 0.18) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var origin: Vector3 = actor.position
	actor.set_meta("lunge_origin", origin)
	var kept: Array = []
	for entry in _lunges:
		if entry["actor"] != actor:
			kept.append(entry)
	_lunges = kept
	_lunges.append({
		"actor": actor,
		"origin": origin,
		"dx": dx,
		"time": 0.0,
		"duration": maxf(duration, 0.001),
	})


func advance(delta: float) -> void:
	_advance_flashes(delta)
	_advance_popups(delta)
	_advance_lunges(delta)


func _advance_flashes(delta: float) -> void:
	var kept: Array = []
	for entry in _flashes:
		var actor_value: Variant = entry["actor"]
		if not is_instance_valid(actor_value):
			continue
		entry["time"] = float(entry["time"]) - delta
		if float(entry["time"]) <= 0.0:
			_apply_base(actor_value)
		else:
			kept.append(entry)
	_flashes = kept


func _advance_popups(delta: float) -> void:
	var kept: Array = []
	for entry in popups:
		var node_value: Variant = entry["node"]
		if not is_instance_valid(node_value) or not (node_value is Label3D):
			continue
		var label: Label3D = node_value
		entry["age"] = float(entry["age"]) + delta
		var age: float = float(entry["age"])
		var t: float = clampf(age / POPUP_LIFE, 0.0, 1.0)
		label.position = Vector3(
			float(entry["base_x"]),
			float(entry["base_y"]) + POPUP_RISE * t,
			float(entry["base_z"])
		)
		var color: Color = entry["color"]
		color.a = 1.0 - t
		label.modulate = color
		if age >= POPUP_LIFE:
			label.queue_free()
			continue
		kept.append(entry)
	popups = kept


func _advance_lunges(delta: float) -> void:
	var kept: Array = []
	for entry in _lunges:
		var actor_value: Variant = entry["actor"]
		if not is_instance_valid(actor_value):
			continue
		var actor: Node3D = actor_value
		entry["time"] = float(entry["time"]) + delta
		var duration: float = float(entry["duration"])
		var t: float = clampf(float(entry["time"]) / duration, 0.0, 1.0)
		var origin: Vector3 = entry["origin"]
		var dx: float = float(entry["dx"])
		actor.position = origin + Vector3(dx * sin(PI * t), 0.0, 0.0)
		if t >= 1.0:
			actor.position = origin
		else:
			kept.append(entry)
	_lunges = kept
