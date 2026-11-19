extends RefCounted

# 按 JSON 直接摆放 AI 素材图（kind = "sprite"）。
# 条目字段：sprite（素材文件名）、x、z、height、y、lift、flip、phase、light。
# phase 只写进节点 meta，供以后昼夜切换使用，本轮不做切换。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const TownData = preload("res://shared/resources/town_data.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")


static func build(parent: Node3D, data: Dictionary, prop: Dictionary, index: int) -> void:
	var file := str(prop.get("sprite", ""))
	if file == "":
		return
	var x := float(prop.get("x", 0.0))
	var z := float(prop.get("z", 0.0))
	var ground_y: float = TownData.ground_height(data, x, z)
	var y_value: Variant = prop.get("y", null)
	if typeof(y_value) == TYPE_INT or typeof(y_value) == TYPE_FLOAT:
		ground_y = float(y_value)
	var pos := Vector3(x, ground_y + float(prop.get("lift", 0.0)), z)
	var sprite := AiAssets.make_sprite(
		file,
		float(prop.get("height", 1.0)),
		pos,
		"Sprite_%d_%s" % [index, file.get_file().get_basename()]
	)
	if sprite == null:
		return
	if bool(prop.get("flip", false)):
		sprite.flip_h = true
	var phase := str(prop.get("phase", "both"))
	if phase == "":
		phase = "both"
	sprite.set_meta("phase", phase)
	if bool(prop.get("light", false)):
		sprite.set_meta("night_light", true)
		SceneKit.add_omni_light(
			sprite,
			Vector3(0.0, float(prop.get("height", 1.0)) * 0.6, 0.0),
			Color("#ffb860"),
			7.0,
			0.0
		)
	parent.add_child(sprite)
