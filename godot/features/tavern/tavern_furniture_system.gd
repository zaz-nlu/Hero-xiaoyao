extends RefCounted

# 酒馆家具所有权：entries/nodes、残骸根、可见性/目标变换与视觉 swap。
# 构造时显式接收已建节点；动画任务提交给 StateAnimation，不持有控制器。

const TavernLayout = preload("res://shared/scenery/tavern/tavern_layout.gd")
const TavernFurnitureVisuals = preload("res://shared/scenery/tavern/tavern_furniture_visuals.gd")
const TavernStateAnimation = preload("res://features/tavern/tavern_state_animation.gd")

var entries: Dictionary = {}
var nodes: Dictionary = {}
var debris_root: Node3D = null


static func collect_entries(data: Dictionary) -> Dictionary:
	var entries: Dictionary = {}
	var furniture: Array = data.get("furniture", [])
	for i in range(furniture.size()):
		var entry_value: Variant = furniture[i]
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		entries[str(entry.get("id", "furniture_%d" % i))] = entry
	return entries


func setup(
	entries_value: Dictionary, nodes_value: Dictionary, debris: Node3D
) -> void:
	entries = entries_value
	nodes = nodes_value
	debris_root = debris


func apply_state(
	new_state: String, animate: bool, animation: TavernStateAnimation
) -> void:
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		var node_value: Variant = nodes.get(id, null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		var target: Transform3D = TavernLayout.transform_for(entry, new_state)
		node.visible = TavernLayout.visible_for(entry, new_state)
		if animate:
			animation.add_move(node, node.transform, target)
		else:
			node.transform = target
		_apply_visual_swap(node, entry, new_state, animate, animation)
	if debris_root != null:
		debris_root.visible = new_state != "normal"


func furniture_target(id: String, new_state: String) -> Transform3D:
	var entry_value: Variant = entries.get(id, null)
	if not (entry_value is Dictionary):
		return Transform3D.IDENTITY
	return TavernLayout.transform_for(entry_value, new_state)


func fallen_table_count() -> int:
	var count := 0
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		if str(entry.get("kind", "")) != "table":
			continue
		var node_value: Variant = nodes.get(id, null)
		if not (node_value is Node3D):
			continue
		var node: Node3D = node_value
		if absf(node.rotation.z) > 0.5 or absf(node.rotation.x) > 0.5:
			count += 1
	return count


func _apply_visual_swap(
	node: Node3D,
	entry: Dictionary,
	new_state: String,
	animate: bool,
	animation: TavernStateAnimation
) -> void:
	if not animate:
		TavernFurnitureVisuals.apply_swap(node, entry, new_state)
		return
	var swap: Dictionary = TavernFurnitureVisuals.swap_targets(node, entry, new_state)
	if swap.is_empty():
		return
	var normal: Sprite3D = swap["normal"] as Sprite3D
	var wrecked: Sprite3D = swap["wrecked"] as Sprite3D
	animation.add_swap(
		normal,
		wrecked,
		normal.modulate.a,
		wrecked.modulate.a,
		float(swap["to_normal"]),
		float(swap["to_wrecked"])
	)
