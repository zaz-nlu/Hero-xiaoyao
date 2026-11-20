extends RefCounted

# 按 JSON 直接摆放 AI 素材图（kind = "sprite"）。
# 条目字段：sprite（素材文件名）、x、z、height、y、lift、flip、phase、light、
# label（在图上写字，如牌坊匾额：{text, u, v, text_height}，u/v 为字心在原图里的比例位置）。
# phase 只写进节点 meta，供以后昼夜切换使用，本轮不做切换。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const TownData = preload("res://shared/resources/town_data.gd")
const SceneKit = preload("res://shared/scene/scene_kit.gd")
const TownFonts = preload("res://shared/scenery/town/town_fonts.gd")


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
	var label_value: Variant = prop.get("label", null)
	if typeof(label_value) == TYPE_DICTIONARY:
		_add_label(sprite, label_value, float(prop.get("height", 1.0)))
	parent.add_child(sprite)


# 在贴图上的指定位置写字（匾额、招牌）：位置按原图比例换算，字略微离开图面避免被遮挡。
static func _add_label(sprite: Sprite3D, spec: Dictionary, world_height: float) -> void:
	var tex: Texture2D = sprite.texture
	if tex == null or tex.get_height() <= 0:
		return
	var meters_per_px := world_height / float(tex.get_height())
	var text_height := float(spec.get("text_height", 0.5))
	var label := Label3D.new()
	label.name = "Plaque"
	label.text = str(spec.get("text", ""))
	label.font_size = 96
	label.pixel_size = text_height / 96.0
	var font: Font = TownFonts.brush()
	if font != null:
		label.font = font
	label.modulate = Color(spec.get("color", "#f0d27a"))
	label.outline_modulate = Color(0.15, 0.07, 0.02)
	label.outline_size = 8
	label.shaded = false
	label.double_sided = false
	var u := float(spec.get("u", 0.5))
	var v := float(spec.get("v", 0.5))
	label.position = Vector3(
		(u - 0.5) * float(tex.get_width()) * meters_per_px,
		(1.0 - v) * float(tex.get_height()) * meters_per_px,
		0.06)
	sprite.add_child(label)
