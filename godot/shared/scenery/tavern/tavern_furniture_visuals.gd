extends RefCounted

# 酒馆家具的纯视觉状态：sprite alpha 与 normal/wrecked 贴图切换。
# 动画时钟/剧情留在 feature；共享背景与 feature 共用这里的静态视觉算法。

const TavernLayout = preload("res://shared/scenery/tavern/tavern_layout.gd")


static func set_sprite_alpha(sprite: Sprite3D, alpha: float) -> void:
	var color: Color = sprite.modulate
	color.a = clampf(alpha, 0.0, 1.0)
	sprite.modulate = color
	sprite.visible = color.a > 0.001


# Describes the normal/wrecked cross-fade for a furniture node, or {} when the
# node has no swappable sprites. Callers own the timing and the alpha writes.
static func swap_targets(node: Node3D, entry: Dictionary, new_state: String) -> Dictionary:
	var kind := str(entry.get("kind", ""))
	var normal_value: Variant = null
	var wrecked_value: Variant = null
	var target_wrecked := false
	match kind:
		"table":
			normal_value = node.get_node_or_null("TableSprite")
			wrecked_value = node.get_node_or_null("TableWreckedSprite")
			target_wrecked = entry.has("wrecked") \
				and TavernLayout.state_key(entry, new_state) == "wrecked"
		"bench":
			normal_value = node.get_node_or_null("BenchSprite")
			wrecked_value = node.get_node_or_null("BenchWreckedSprite")
			target_wrecked = new_state != "normal"
		_:
			return {}
	if not (normal_value is Sprite3D) or not (wrecked_value is Sprite3D):
		return {}
	return {
		"normal": normal_value,
		"wrecked": wrecked_value,
		"to_normal": 0.0 if target_wrecked else 1.0,
		"to_wrecked": 1.0 if target_wrecked else 0.0,
	}


static func apply_swap(node: Node3D, entry: Dictionary, new_state: String) -> void:
	var swap: Dictionary = swap_targets(node, entry, new_state)
	if swap.is_empty():
		return
	set_sprite_alpha(swap["normal"] as Sprite3D, float(swap["to_normal"]))
	set_sprite_alpha(swap["wrecked"] as Sprite3D, float(swap["to_wrecked"]))
