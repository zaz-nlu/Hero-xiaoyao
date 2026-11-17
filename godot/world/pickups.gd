extends RefCounted

# 采集点通用逻辑：解析 JSON 条目、生成节点、查找最近采集点、拾取。
# forest.gd 与 town.gd 共用这一份，避免两套重复代码。

const GameState = preload("res://core/game_state.gd")
const Progression = preload("res://core/progression.gd")
const AiAssets = preload("res://world/ai_assets.gd")

const INTERACT_RANGE := 1.8
const DEFAULT_HEIGHT := 0.6
const GLOW_HEIGHT_FACTOR := 0.6
const GLOW_COLOR := Color("#d8e878")
const SPARK_TINT := Color("#7ce8d8")


static func parse_entries(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array):
		return result
	var entries: Array = raw
	for i in range(entries.size()):
		var entry: Dictionary = parse_entry(entries[i], i)
		if not entry.is_empty():
			result.append(entry)
	return result


static func parse_entry(raw: Variant, index: int) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var entry: Dictionary = raw
	var raw_id: Variant = entry.get("id", index + 1)
	return {
		"id": raw_id,
		"kind": str(entry.get("kind", "pickup")),
		"item": str(entry.get("item", "")),
		"count": int(entry.get("count", 1)),
		"name": str(entry.get("name", "")),
		"sprite": str(entry.get("sprite", "")),
		"height": float(entry.get("height", DEFAULT_HEIGHT)),
		"pos": Vector2(float(entry.get("x", 0.0)), float(entry.get("z", 0.0))),
		"flag": str(entry.get("flag", "")),
		"glint": bool(entry.get("glint", true)),
		"tint": entry.get("tint", null),
		"node": null,
	}


static func node_name(entry: Dictionary) -> String:
	# JSON numbers load as floats: "1.0" would become "1_0" in a node name.
	var raw_id: Variant = entry.get("id", "")
	var id := str(int(raw_id)) if (raw_id is float and is_equal_approx(float(raw_id), roundf(float(raw_id)))) else str(raw_id)
	if str(entry.get("kind", "")) == "herb" or str(entry.get("item", "")) == "herb":
		return "Herb_%s" % id
	return "Pickup_%s" % id


static func is_picked(entry: Dictionary) -> bool:
	var flag := str(entry.get("flag", ""))
	return flag != "" and GameState.has_flag(flag)


static func spawn(root: Node3D, entry: Dictionary) -> Node3D:
	if root == null or entry.is_empty() or is_picked(entry):
		return null
	var pos_value: Variant = entry.get("pos", Vector2.ZERO)
	if not (pos_value is Vector2):
		return null
	var pos: Vector2 = pos_value
	var height := float(entry.get("height", DEFAULT_HEIGHT))
	var node := Node3D.new()
	node.name = node_name(entry)
	node.position = Vector3(pos.x, 0.0, pos.y)
	var sprite := _make_sprite(entry, height)
	if sprite != null:
		node.add_child(sprite)
	if bool(entry.get("glint", true)):
		_add_glow(node, entry, height)
	root.add_child(node)
	entry["node"] = node
	return node


static func nearest(
	entries: Array, player_pos: Vector2, max_dist: float = INTERACT_RANGE
) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := max_dist
	for entry_value in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("kind", "")) == "chest":
			continue
		var node_value: Variant = entry.get("node", null)
		if not (node_value is Node3D) or not is_instance_valid(node_value):
			continue
		var pos_value: Variant = entry.get("pos", Vector2.ZERO)
		if not (pos_value is Vector2):
			continue
		var pos: Vector2 = pos_value
		var dist: float = player_pos.distance_to(pos)
		if dist <= best_dist:
			best = entry
			best_dist = dist
	return best


static func prompt_text(entry: Dictionary) -> String:
	var display := str(entry.get("name", ""))
	if display == "":
		display = str(entry.get("item", ""))
	return "按 E 采集 %s" % display


static func collect(entry: Dictionary) -> bool:
	if entry.is_empty() or is_picked(entry):
		return false
	var flag := str(entry.get("flag", ""))
	if flag != "":
		GameState.set_flag(flag)
	Progression.give_item(str(entry.get("item", "")), int(entry.get("count", 1)))
	remove_node(entry)
	return true


static func remove_node(entry: Dictionary) -> void:
	var node_value: Variant = entry.get("node", null)
	entry["node"] = null
	if not (node_value is Node):
		return
	var node: Node = node_value
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	if node.is_inside_tree():
		node.queue_free()
	else:
		node.free()


# ---------------------------------------------------------------- visuals

static func _make_sprite(entry: Dictionary, height: float) -> Sprite3D:
	var file := str(entry.get("sprite", ""))
	var sprite: Sprite3D = null
	if file == "spark":
		sprite = _make_spark(entry, height)
	else:
		if file == "":
			file = "prop_grass.png"
		sprite = AiAssets.make_sprite(file, height, Vector3.ZERO, "PickupSprite")
		if sprite == null:
			sprite = AiAssets.make_sprite(
				"prop_grass.png", height, Vector3.ZERO, "PickupSprite"
			)
	if sprite == null:
		return null
	if file != "spark" and _has_tint(entry):
		sprite.modulate = _tint_value(entry)
	return sprite


# 代码生成的青色小亮点，用于没有合适贴图的采集物（如发簪）。
static func _make_spark(entry: Dictionary, height: float) -> Sprite3D:
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var tint := SPARK_TINT
	if _has_tint(entry):
		tint = _tint_value(entry)
	var center := 7.5
	for y in range(16):
		for x in range(16):
			var d: float = absf(float(x) - center) + absf(float(y) - center)
			if d > 7.0:
				continue
			var alpha: float = clampf(1.0 - d / 8.0, 0.0, 1.0)
			image.set_pixel(x, y, Color(tint.r, tint.g, tint.b, alpha))
	var texture := ImageTexture.create_from_image(image)
	var sprite := Sprite3D.new()
	sprite.name = "PickupSprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.pixel_size = height / 16.0
	sprite.offset = Vector2(0.0, 8.0)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sprite


static func _add_glow(node: Node3D, entry: Dictionary, height: float) -> void:
	var glow := MeshInstance3D.new()
	glow.name = "PickupGlow"
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	glow.mesh = sphere
	var color := GLOW_COLOR
	if _has_tint(entry):
		color = _tint_value(entry)
	glow.material_override = _emissive_material(color, 1.6)
	glow.position = Vector3(0.0, height * GLOW_HEIGHT_FACTOR, 0.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(glow)


static func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	return mat


static func _has_tint(entry: Dictionary) -> bool:
	var raw: Variant = entry.get("tint", null)
	return raw is Array and raw.size() >= 3


static func _tint_value(entry: Dictionary) -> Color:
	if not _has_tint(entry):
		return Color.WHITE
	var tint: Array = entry["tint"]
	return Color(float(tint[0]), float(tint[1]), float(tint[2]), 1.0)
