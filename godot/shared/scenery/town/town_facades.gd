extends RefCounted

# 小镇立面与门楣木匾：优先使用建筑数据里的 facade 文件名，缺省按 kind 走旧映射；
# plaque 给出木匾中心在立面图中的比例位置，文字由 Label3D 叠在立面前方。

const AiAssets = preload("res://shared/resources/ai_assets.gd")
const TownArt = preload("res://shared/scenery/town/town_art.gd")
const TownFonts = preload("res://shared/scenery/town/town_fonts.gd")

const FACADE_BY_KIND := {
	"tavern": "facade_tavern.png",
	"shop": "facade_general_store.png",
	"smith": "facade_blacksmith.png",
	"house": "facade_residence.png",
}
const DEFAULT_PLAQUE_W := 0.2


static func build(
	parent: Node3D,
	building: Dictionary,
	x0: float,
	x1: float,
	z_front: float,
	kind: String,
	art: TownArt
) -> Dictionary:
	var file := str(building.get("facade", ""))
	if file == "":
		file = str(FACADE_BY_KIND.get(kind, ""))
	if file == "":
		return {}
	var facade_w := (x1 - x0) * 1.08
	var facade := AiAssets.make_wall_quad(
		file,
		facade_w,
		Vector3((x0 + x1) * 0.5, 0.0, z_front),
		"Facade_%s" % str(building.get("id", ""))
	)
	if facade == null:
		return {}
	parent.add_child(facade)
	var facade_h := 0.0
	if facade.mesh is QuadMesh:
		facade_h = (facade.mesh as QuadMesh).size.y
	if kind == "tavern":
		_build_tavern_sign(parent, building, x0, x1, z_front)
		return {"height": facade_h, "tavern": true}
	var sign_text := str(building.get("sign", ""))
	if sign_text != "":
		_build_plaque(parent, building, art, sign_text, (x0 + x1) * 0.5, z_front, facade_w, facade_h)
	return {"height": facade_h, "tavern": false}


static func _build_tavern_sign(
	parent: Node3D, building: Dictionary, x0: float, x1: float, z_front: float
) -> void:
	var door_x := float(building.get("door_x", (x0 + x1) * 0.5))
	var sign := AiAssets.make_sprite(
		"prop_tavern_sign.png",
		1.9,
		Vector3(door_x + 2.7, 1.5, z_front + 0.5),
		"TavernSign"
	)
	if sign != null:
		parent.add_child(sign)


static func _build_plaque(
	parent: Node3D,
	building: Dictionary,
	art: TownArt,
	text: String,
	center_x: float,
	z_front: float,
	facade_w: float,
	facade_h: float
) -> void:
	var plaque_value: Variant = building.get("plaque", null)
	if typeof(plaque_value) != TYPE_ARRAY:
		return
	var plaque: Array = plaque_value
	if plaque.size() < 2 or not _is_number(plaque[0]) or not _is_number(plaque[1]):
		return
	var plaque_w := facade_w * float(building.get("plaque_w", DEFAULT_PLAQUE_W))
	# 毛笔字笔画偏细，在原有随木匾宽度缩放的基础上放大约 1.15 倍更醒目。
	var label := art.make_label(text, plaque_w / 150.0 * 0.62 * 1.15, 128)
	label.name = "Plaque_%s" % str(building.get("id", ""))
	label.shaded = false
	label.outline_size = 14
	label.modulate = Color("#f6dc9a")
	label.outline_modulate = Color("#3a1c0a")
	var brush := TownFonts.brush()
	if brush != null:
		label.font = brush
	label.position = Vector3(
		center_x + (float(plaque[0]) - 0.5) * facade_w,
		facade_h * (1.0 - float(plaque[1])),
		z_front + 0.06
	)
	parent.add_child(label)


static func _is_number(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return true
	return false
