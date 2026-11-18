extends RefCounted

# 森林采集物与宝箱：节点生成、最近采集点、拾取发奖、宝箱开盖动画。
# 采集条目与空间坐标由 ForestLayout 提供；物品/flag 逻辑保留在 feature 层。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Pickups = preload("res://shared/gameplay/pickups.gd")
const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const ForestLayout = preload("res://shared/resources/forest_layout.gd")
const ForestArt = preload("res://shared/scenery/forest/forest_art.gd")

const INTERACT_RANGE := 1.8
const CHEST_OPEN_DURATION := 0.6
const CHEST_SPRITE_DURATION := 0.5
const CHEST_SWAP_TIME := 0.25
const CHEST_LID_ANGLE := 70.0

var chest_node: Node3D = null
var chest_pivot: Node3D = null
var chest_sprite: Sprite3D = null
var chest_opened: bool = false
var anim_t: float = -1.0
var swapped: bool = false

var _layout: ForestLayout = null


func build(parent: Node3D, layout: ForestLayout, art: ForestArt) -> void:
	build_pickups(parent, layout)
	build_chest(parent, layout, art)


func build_pickups(parent: Node3D, layout: ForestLayout) -> void:
	_layout = layout
	var root := _pickup_root(parent)
	for pickup_value in layout.pickups:
		var pickup: Dictionary = pickup_value
		if str(pickup.get("kind", "")) == "chest":
			continue
		Pickups.spawn(root, pickup)
	_generate_deco_herbs(root, layout)


func build_chest(parent: Node3D, layout: ForestLayout, art: ForestArt) -> void:
	_layout = layout
	var entry: Dictionary = _chest_entry(layout.pickups)
	if entry.is_empty():
		return
	var flag := str(entry.get("flag", ""))
	chest_opened = flag != "" and GameState.has_flag(flag)
	var pos_value: Variant = entry.get("pos", Vector2.ZERO)
	if not (pos_value is Vector2):
		return
	var pos: Vector2 = pos_value
	var root := _pickup_root(parent)
	var node := Node3D.new()
	node.name = "Chest"
	node.position = Vector3(pos.x, 0.0, pos.y)
	root.add_child(node)

	var closed_tex: ImageTexture = AiAssets.load_texture("chest_closed.png")
	var open_tex: ImageTexture = AiAssets.load_texture("chest_open.png")
	if closed_tex != null and open_tex != null:
		var sprite := AiAssets.make_sprite("chest_closed.png", 0.9, Vector3.ZERO, "ChestSprite")
		if sprite != null:
			node.add_child(sprite)
			# Kept for backwards compatibility; the sprite chest animates by texture.
			var pivot := Node3D.new()
			pivot.name = "LidPivot"
			node.add_child(pivot)
			chest_node = node
			chest_pivot = pivot
			chest_sprite = sprite
			entry["node"] = node
			swapped = false
			if chest_opened:
				_set_chest_sprite_open()
			return

	var wood: StandardMaterial3D = art.dark_wood_material()
	var gold: StandardMaterial3D = art.solid_material(Color("#c9a23f"))
	SceneKit.add_box(node, Vector3(1.1, 0.62, 0.75), wood, Vector3(0.0, 0.31, 0.0), "Body")
	SceneKit.add_box(node, Vector3(1.16, 0.08, 0.81), gold, Vector3(0.0, 0.04, 0.0), "BaseBand")
	SceneKit.add_box(node, Vector3(0.08, 0.66, 0.79), gold, Vector3(-0.44, 0.33, 0.0), "BandLeft")
	SceneKit.add_box(node, Vector3(0.08, 0.66, 0.79), gold, Vector3(0.44, 0.33, 0.0), "BandRight")
	SceneKit.add_box(node, Vector3(0.16, 0.2, 0.06), gold, Vector3(0.0, 0.42, 0.39), "Lock")

	var pivot := Node3D.new()
	pivot.name = "LidPivot"
	pivot.position = Vector3(0.0, 0.62, -0.375)
	node.add_child(pivot)
	SceneKit.add_box(pivot, Vector3(1.1, 0.16, 0.75), wood, Vector3(0.0, 0.08, 0.375), "Lid")
	SceneKit.add_box(pivot, Vector3(1.16, 0.06, 0.79), gold, Vector3(0.0, 0.17, 0.375), "LidBand")

	chest_node = node
	chest_pivot = pivot
	chest_sprite = null
	entry["node"] = node
	if chest_opened:
		pivot.rotation.x = -deg_to_rad(CHEST_LID_ANGLE)


func _pickup_root(parent: Node3D) -> Node3D:
	var existing: Variant = parent.get_node_or_null("Pickups")
	if existing is Node3D:
		return existing
	var root := Node3D.new()
	root.name = "Pickups"
	parent.add_child(root)
	return root


func _generate_deco_herbs(root: Node3D, layout: ForestLayout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ForestLayout.TREE_SEED + 13
	var files: Array[String] = ["herb_ginseng.png", "herb_purple.png", "herb_glow.png"]
	var herb_points: Array[Vector2] = []
	for pickup_value in layout.pickups:
		var pickup: Dictionary = pickup_value
		if str(pickup.get("kind", "")) == "chest":
			continue
		var pos_value: Variant = pickup.get("pos", Vector2.ZERO)
		if pos_value is Vector2:
			herb_points.append(pos_value)
	var added := 0
	var attempts := 0
	while added < 14 and attempts < 800:
		attempts += 1
		var point := Vector2.ZERO
		if not herb_points.is_empty() and added % 2 == 0:
			var anchor: Vector2 = herb_points[rng.randi_range(0, herb_points.size() - 1)]
			var angle := rng.randf_range(0.0, TAU)
			point = anchor + Vector2(cos(angle), sin(angle)) * rng.randf_range(1.2, 2.4)
		elif layout.road_points.size() >= 2:
			var index := rng.randi_range(0, layout.road_points.size() - 2)
			var a: Vector2 = layout.road_points[index]
			var b: Vector2 = layout.road_points[index + 1]
			var along := a.lerp(b, rng.randf())
			var normal := (b - a).normalized().orthogonal()
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			point = along + normal * rng.randf_range(1.0, 2.2) * side
		else:
			point = Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if not layout.in_bounds(point):
			continue
		if layout.road_distance(point) < 1.0:
			continue
		# 采集点周围留出空地，避免装饰草药与可采集的人参/矿石叠在一起。
		var pickup_hit := false
		for collectable_value in layout.pickups:
			var collectable: Dictionary = collectable_value
			if str(collectable.get("kind", "")) == "chest":
				continue
			var pos_value: Variant = collectable.get("pos", Vector2.ZERO)
			if not (pos_value is Vector2):
				continue
			var pickup_pos: Vector2 = pos_value
			if point.distance_to(pickup_pos) < ForestLayout.HERB_CLEARANCE:
				pickup_hit = true
				break
		if pickup_hit:
			continue
		var file: String = files[rng.randi_range(0, files.size() - 1)]
		var height := rng.randf_range(0.6, 0.8)
		var sprite := AiAssets.make_sprite(
			file, height, Vector3(point.x, 0.0, point.y), "DecoHerb_%d" % added
		)
		if sprite == null:
			continue
		root.add_child(sprite)
		added += 1


func _set_chest_sprite_open() -> void:
	if chest_sprite == null or not is_instance_valid(chest_sprite):
		return
	var open_tex: ImageTexture = AiAssets.load_texture("chest_open.png")
	if open_tex == null:
		return
	_apply_sprite_texture(chest_sprite, open_tex, 1.1)


func _apply_sprite_texture(sprite: Sprite3D, texture: Texture2D, world_height: float) -> void:
	if texture == null:
		return
	var size: Vector2 = texture.get_size()
	if size.y <= 0.0:
		return
	sprite.texture = texture
	sprite.pixel_size = world_height / size.y
	sprite.offset = Vector2(0.0, size.y * 0.5)


func _chest_entry(entries: Array) -> Dictionary:
	for pickup_value in entries:
		var pickup: Dictionary = pickup_value
		if str(pickup.get("kind", "")) == "chest":
			return pickup
	return {}


func nearest(player_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	if _layout == null:
		return best
	var best_dist := INTERACT_RANGE
	for pickup_value in _layout.pickups:
		var pickup: Dictionary = pickup_value
		if str(pickup.get("kind", "")) == "chest" and chest_opened:
			continue
		var node_value: Variant = pickup.get("node", null)
		if not (node_value is Node3D) or not is_instance_valid(node_value):
			continue
		var pos_value: Variant = pickup.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var pickup_pos: Vector2 = pos_value
		var dist: float = player_pos.distance_to(pickup_pos)
		if dist <= best_dist:
			best = pickup
			best_dist = dist
	return best


func prompt_text(pickup: Dictionary) -> String:
	if str(pickup.get("kind", "")) == "chest":
		return "按 E 打开 宝箱"
	return Pickups.prompt_text(pickup)


func collect(pickup: Dictionary) -> void:
	var kind := str(pickup.get("kind", ""))
	var flag := str(pickup.get("flag", ""))
	if kind == "chest":
		if chest_opened:
			return
		chest_opened = true
		if flag != "":
			GameState.set_flag(flag)
		Progression.give_item(str(pickup.get("item", "")))
		anim_t = 0.0
		swapped = false
		return
	Pickups.collect(pickup)


func advance_chest(delta: float) -> void:
	if anim_t < 0.0:
		return
	if chest_sprite != null and is_instance_valid(chest_sprite):
		anim_t += delta
		var t := clampf(anim_t / CHEST_SPRITE_DURATION, 0.0, 1.0)
		var pop := 1.0 + 0.08 * sin(t * PI)
		chest_sprite.scale = Vector3(pop, pop, pop)
		if not swapped and anim_t >= CHEST_SWAP_TIME:
			swapped = true
			_set_chest_sprite_open()
		if t >= 1.0:
			anim_t = -1.0
		return
	if chest_pivot == null or not is_instance_valid(chest_pivot):
		anim_t = -1.0
		return
	anim_t += delta
	var t := clampf(anim_t / CHEST_OPEN_DURATION, 0.0, 1.0)
	chest_pivot.rotation.x = -deg_to_rad(CHEST_LID_ANGLE) * t
	if t >= 1.0:
		anim_t = -1.0
