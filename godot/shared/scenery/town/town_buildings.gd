extends RefCounted

# 小镇房屋：立面、体块、坡屋顶、招牌、灯笼与阳台。坐标与节点命名保持原样。

const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const TownArt = preload("res://shared/scenery/town/town_art.gd")
const TownData = preload("res://shared/resources/town_data.gd")
const TownFacades = preload("res://shared/scenery/town/town_facades.gd")

# Eave height as a fraction of the facade image height, per building kind.
const EAVE_FRAC := {
	"tavern": 0.80,
	"shop": 0.70,
	"smith": 0.75,
	"house": 0.66,
}

var tavern_facade: bool = false


func build_buildings(parent: Node3D, data: Dictionary, art: TownArt) -> bool:
	var root := Node3D.new()
	root.name = "Buildings"
	parent.add_child(root)
	var buildings: Array = data.get("buildings", [])
	for i in range(buildings.size()):
		var building_value: Variant = buildings[i]
		if typeof(building_value) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = building_value
		var building_root := Node3D.new()
		building_root.name = str(building.get("id", "building_%d" % i))
		root.add_child(building_root)
		building_root.position.y = _building_base_y(data, building)
		_build_building(building_root, building, art)
	return tavern_facade


func _building_base_y(data: Dictionary, building: Dictionary) -> float:
	var door_x := float(building.get("door_x", (float(building.get("x0", 0.0)) + float(building.get("x1", 0.0))) * 0.5))
	var ground: float = TownData.ground_height(data, door_x, float(building.get("z_front", 0.0)) - 0.3)
	return float(building["y"]) if typeof(building.get("y", null)) in [TYPE_INT, TYPE_FLOAT] else ground


func _build_building(parent: Node3D, building: Dictionary, art: TownArt) -> void:
	var x0 := float(building.get("x0", 0.0))
	var x1 := float(building.get("x1", 0.0))
	var z_front := float(building.get("z_front", 0.0))
	var depth := float(building.get("depth", 0.0))
	var wall_h := float(building.get("wall_h", 4.5))
	var roof_h := float(building.get("roof_h", 2.5))
	var door_x := float(building.get("door_x", (x0 + x1) * 0.5))
	var door_w := float(building.get("door_w", 1.6))
	var kind := str(building.get("kind", "house"))
	if x1 <= x0 or depth <= 0.0:
		return
	var facade_height: float = _try_build_facade(
		parent, building, x0, x1, z_front, kind, art
	)
	if facade_height > 0.0:
		_build_building_volume(parent, building, facade_height, art)
		return
	var width := x1 - x0
	var z_back := z_front - depth
	var cx := (x0 + x1) * 0.5
	var cz := (z_back + z_front) * 0.5
	var base_y := 0.6
	var top_y := base_y + wall_h
	var door_h := 3.6 if kind == "tavern" else 3.2

	# stone base
	var base_mat: StandardMaterial3D = art.make_step_stone_material(Vector2(width, depth))
	SceneKit.add_box(
		parent,
		Vector3(width + 0.2, base_y, depth + 0.2),
		base_mat,
		Vector3(cx, base_y * 0.5, cz)
	)

	# plaster wall
	var wall_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("plaster"), Vector2(width, wall_h)
	)
	SceneKit.add_box(
		parent,
		Vector3(width, wall_h, depth),
		wall_mat,
		Vector3(cx, base_y + wall_h * 0.5, cz)
	)

	# timber frames
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(1.0, 3.0)
	)
	var beam_x := x0 + 0.15
	while beam_x <= x1 - 0.15 + 0.001:
		SceneKit.add_box(
			parent,
			Vector3(0.25, wall_h, 0.16),
			wood_mat,
			Vector3(beam_x, base_y + wall_h * 0.5, z_front + 0.08)
		)
		beam_x += 2.5
	SceneKit.add_box(
		parent,
		Vector3(width, 0.35, 0.2),
		wood_mat,
		Vector3(cx, top_y - 0.175, z_front + 0.08)
	)

	# door
	var door_mat: StandardMaterial3D = Texgen.make_material(art.get_tex("door"), Vector2.ONE)
	SceneKit.add_quad(
		parent,
		Vector2(door_w, door_h),
		door_mat,
		Vector3(door_x, base_y + door_h * 0.5, z_front + 0.05)
	)
	SceneKit.add_box(
		parent,
		Vector3(door_w + 0.3, 0.3, 0.16),
		wood_mat,
		Vector3(door_x, base_y + door_h + 0.15, z_front + 0.06)
	)

	# sign position, used to keep windows clear
	var sign_text := str(building.get("sign", ""))
	var sign_x := door_x - door_w * 0.5 - 0.85

	# windows
	var window_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("window"), Vector2.ONE
	)
	var window_y := base_y + 1.6
	var window_x := x0 + 1.5
	while window_x <= x1 - 1.5 + 0.001:
		var near_door := absf(window_x - door_x) < door_w * 0.5 + 0.6
		var near_sign := sign_text != "" and absf(window_x - sign_x) < 1.1
		if not near_door and not near_sign:
			SceneKit.add_quad(
				parent,
				Vector2(1.2, 1.2),
				window_mat,
				Vector3(window_x, window_y, z_front + 0.06)
			)
		window_x += 3.0

	if kind == "tavern":
		var upper_x := x0 + 1.5
		while upper_x <= x1 - 1.5 + 0.001:
			SceneKit.add_quad(
				parent,
				Vector2(1.2, 1.2),
				window_mat,
				Vector3(upper_x, 4.2, z_front + 0.06)
			)
			upper_x += 3.0

	# roof
	_build_roof(parent, x0, x1, z_front, depth, top_y, roof_h, art)

	# sign board
	if sign_text != "":
		_build_sign(parent, sign_x, z_front, sign_text, art)

	# awning
	if bool(building.get("awning", false)):
		var awning_mat: StandardMaterial3D = Texgen.make_material(
			art.get_tex("awning_stripes"), Vector2(door_w + 1.5, 1.6)
		)
		var awning := SceneKit.add_quad(
			parent,
			Vector2(door_w + 1.5, 1.6),
			awning_mat,
			Vector3(door_x, base_y + door_h + 0.55, z_front + 0.75)
		)
		awning.rotation.x = -deg_to_rad(25.0)

	# lanterns
	if bool(building.get("lantern", false)):
		var lantern_y := base_y + door_h + 0.35
		_build_lantern(parent, door_x - door_w * 0.5 - 0.8, lantern_y, z_front + 0.4)
		_build_lantern(parent, door_x + door_w * 0.5 + 0.8, lantern_y, z_front + 0.4)

	if kind == "tavern":
		_build_balcony(parent, door_x, z_front, art)

	if kind == "smith":
		var chimney_mat: StandardMaterial3D = art.make_step_stone_material(Vector2(0.8, 2.0))
		SceneKit.add_box(
			parent,
			Vector3(0.8, 2.0, 0.8),
			chimney_mat,
			Vector3(x1 - 2.0, top_y + roof_h + 0.4, z_back + 2.0)
		)


func _try_build_facade(
	parent: Node3D, building: Dictionary, x0: float, x1: float, z_front: float,
	kind: String, art: TownArt
) -> float:
	var result := TownFacades.build(parent, building, x0, x1, z_front, kind, art)
	tavern_facade = tavern_facade or bool(result.get("tavern", false))
	return float(result.get("height", 0.0))


# Gives the flat facade a real 3D body behind it: walls, two roof slopes, a
# ridge cap and side gables. Everything lives under "Volume_<id>", a sibling of
# the facade, so the facade itself stays untouched.
func _build_building_volume(
	parent: Node3D, building: Dictionary, facade_height: float, art: TownArt
) -> void:
	var x0 := float(building.get("x0", 0.0))
	var x1 := float(building.get("x1", 0.0))
	var z_front := float(building.get("z_front", 0.0))
	var depth := float(building.get("depth", 0.0))
	var kind := str(building.get("kind", "house"))
	if x1 <= x0 or depth <= 0.0 or facade_height <= 0.0:
		return
	var width := x1 - x0
	var cx := (x0 + x1) * 0.5
	var roof_w := width * 1.08
	var z_back := z_front - depth
	var z_mid := z_front - depth * 0.5
	var h_top := facade_height
	var h_eave := h_top * float(EAVE_FRAC.get(kind, 0.7))
	var front_z := z_front - 0.02
	var xl := cx - roof_w * 0.5
	var xr := cx + roof_w * 0.5
	var slope_h := h_top - h_eave
	var front_run := front_z - z_mid
	var back_run := z_mid - z_back
	var front_len := sqrt(front_run * front_run + slope_h * slope_h)
	var back_len := sqrt(back_run * back_run + slope_h * slope_h)

	var root := Node3D.new()
	root.name = "Volume_%s" % str(building.get("id", ""))
	parent.add_child(root)

	var plaster_tex: ImageTexture = AiAssets.load_texture("tex_aged_plaster.png")
	var wall_uv := Vector2(width * 0.98, h_eave) / 2.5
	var wall_mat: StandardMaterial3D
	if plaster_tex != null:
		wall_mat = Texgen.make_material(plaster_tex, wall_uv)
	else:
		wall_mat = Texgen.make_material(art.get_tex("plaster"), wall_uv * 2.5)
	SceneKit.add_box(
		root,
		Vector3(width * 0.98, h_eave, depth - 0.1),
		wall_mat,
		Vector3(cx, h_eave * 0.5, z_front - depth * 0.5 - 0.05),
		"Walls"
	)

	# Roof tiles repeat every 2 world units along and across the slopes.
	var roof_tex: ImageTexture = AiAssets.load_texture("tex_gray_roof_tiles.png")
	var roof_mat: StandardMaterial3D
	if roof_tex != null:
		roof_mat = Texgen.make_material(roof_tex, Vector2(0.5, 0.5))
	else:
		roof_mat = Texgen.make_material(art.get_tex("roof_tiles"), Vector2(1.0, 1.0))
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	roof_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	roof_mat.roughness = 1.0

	var front_normal := Vector3(0.0, slope_h, front_run).normalized()
	var front_st := SurfaceTool.new()
	front_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_roof_vertex(front_st, Vector3(xl, h_eave, front_z), Vector2(0.0, 0.0), front_normal)
	_roof_vertex(front_st, Vector3(xr, h_eave, front_z), Vector2(roof_w, 0.0), front_normal)
	_roof_vertex(front_st, Vector3(xr, h_top, z_mid), Vector2(roof_w, front_len), front_normal)
	_roof_vertex(front_st, Vector3(xl, h_eave, front_z), Vector2(0.0, 0.0), front_normal)
	_roof_vertex(front_st, Vector3(xr, h_top, z_mid), Vector2(roof_w, front_len), front_normal)
	_roof_vertex(front_st, Vector3(xl, h_top, z_mid), Vector2(0.0, front_len), front_normal)
	var front_roof := SceneKit.add_mesh(
		root, front_st.commit(), roof_mat, Vector3.ZERO, "RoofFront"
	)
	front_roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var back_normal := Vector3(0.0, slope_h, z_back - z_mid).normalized()
	var back_st := SurfaceTool.new()
	back_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_roof_vertex(back_st, Vector3(xr, h_eave, z_back), Vector2(roof_w, 0.0), back_normal)
	_roof_vertex(back_st, Vector3(xl, h_eave, z_back), Vector2(0.0, 0.0), back_normal)
	_roof_vertex(back_st, Vector3(xl, h_top, z_mid), Vector2(0.0, back_len), back_normal)
	_roof_vertex(back_st, Vector3(xr, h_eave, z_back), Vector2(roof_w, 0.0), back_normal)
	_roof_vertex(back_st, Vector3(xl, h_top, z_mid), Vector2(0.0, back_len), back_normal)
	_roof_vertex(back_st, Vector3(xr, h_top, z_mid), Vector2(roof_w, back_len), back_normal)
	var back_roof := SceneKit.add_mesh(
		root, back_st.commit(), roof_mat, Vector3.ZERO, "RoofBack"
	)
	back_roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Ridge cap.
	SceneKit.add_box(
		root,
		Vector3(roof_w, 0.25, 0.35),
		SceneKit.solid_material(Color("#3a322e")),
		Vector3(cx, h_top + 0.05, z_mid),
		"Ridge"
	)

	# Side gables close the triangular space under the slopes.
	var gable_mat: StandardMaterial3D
	if plaster_tex != null:
		gable_mat = Texgen.make_material(plaster_tex, Vector2(0.4, 0.4))
	else:
		gable_mat = Texgen.make_material(art.get_tex("plaster"), Vector2(1.0, 1.0))
	gable_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var west_st := SurfaceTool.new()
	west_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var west_normal := Vector3(-1.0, 0.0, 0.0)
	var west_x := x0 + 0.02
	_roof_vertex(west_st, Vector3(west_x, h_eave, front_z), Vector2(0.0, 0.0), west_normal)
	_roof_vertex(west_st, Vector3(west_x, h_top, z_mid), Vector2(depth * 0.5, slope_h), west_normal)
	_roof_vertex(west_st, Vector3(west_x, h_eave, z_back), Vector2(depth, 0.0), west_normal)
	SceneKit.add_mesh(root, west_st.commit(), gable_mat, Vector3.ZERO, "GableWest")

	var east_st := SurfaceTool.new()
	east_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var east_normal := Vector3(1.0, 0.0, 0.0)
	var east_x := x1 - 0.02
	_roof_vertex(east_st, Vector3(east_x, h_eave, front_z), Vector2(0.0, 0.0), east_normal)
	_roof_vertex(east_st, Vector3(east_x, h_eave, z_back), Vector2(depth, 0.0), east_normal)
	_roof_vertex(east_st, Vector3(east_x, h_top, z_mid), Vector2(depth * 0.5, slope_h), east_normal)
	SceneKit.add_mesh(root, east_st.commit(), gable_mat, Vector3.ZERO, "GableEast")


func _build_roof(
	parent: Node3D,
	x0: float,
	x1: float,
	z_front: float,
	depth: float,
	eave_y: float,
	roof_h: float,
	art: TownArt
) -> void:
	var z_back := z_front - depth
	var xl := x0 - 0.8
	var xr := x1 + 0.8
	var zf := z_front + 1.0
	var zb := z_back - 1.0
	var zm := (zf + zb) * 0.5
	var ridge_y := eave_y + roof_h
	var span := xr - xl
	var slope_len := sqrt((zf - zm) * (zf - zm) + roof_h * roof_h)
	var slope_len_b := sqrt((zm - zb) * (zm - zb) + roof_h * roof_h)

	var roof_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("roof_tiles"), Vector2.ONE
	)
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var front_normal := Vector3(0.0, roof_h, zf - zm).normalized()
	var back_normal := Vector3(0.0, roof_h, zb - zm).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# front slope
	_roof_vertex(st, Vector3(xl, eave_y, zf), Vector2(0.0, 0.0), front_normal)
	_roof_vertex(st, Vector3(xr, eave_y, zf), Vector2(span, 0.0), front_normal)
	_roof_vertex(st, Vector3(xr, ridge_y, zm), Vector2(span, slope_len), front_normal)
	_roof_vertex(st, Vector3(xl, eave_y, zf), Vector2(0.0, 0.0), front_normal)
	_roof_vertex(st, Vector3(xr, ridge_y, zm), Vector2(span, slope_len), front_normal)
	_roof_vertex(st, Vector3(xl, ridge_y, zm), Vector2(0.0, slope_len), front_normal)
	# back slope
	_roof_vertex(st, Vector3(xr, eave_y, zb), Vector2(span, 0.0), back_normal)
	_roof_vertex(st, Vector3(xl, eave_y, zb), Vector2(0.0, 0.0), back_normal)
	_roof_vertex(st, Vector3(xl, ridge_y, zm), Vector2(0.0, slope_len_b), back_normal)
	_roof_vertex(st, Vector3(xr, eave_y, zb), Vector2(span, 0.0), back_normal)
	_roof_vertex(st, Vector3(xl, ridge_y, zm), Vector2(0.0, slope_len_b), back_normal)
	_roof_vertex(st, Vector3(xr, ridge_y, zm), Vector2(span, slope_len_b), back_normal)
	var roof_mesh: ArrayMesh = st.commit()
	SceneKit.add_mesh(parent, roof_mesh, roof_mat, Vector3.ZERO)

	# gable ends
	var gable_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("plaster"), Vector2.ONE
	)
	gable_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gs := SurfaceTool.new()
	gs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z_mid := (z_front + z_back) * 0.5
	var west_normal := Vector3(-1.0, 0.0, 0.0)
	var east_normal := Vector3(1.0, 0.0, 0.0)
	_roof_vertex(gs, Vector3(x0 - 0.01, eave_y, z_front), Vector2(0.0, 0.0), west_normal)
	_roof_vertex(gs, Vector3(x0 - 0.01, ridge_y, z_mid), Vector2(depth * 0.5, roof_h), west_normal)
	_roof_vertex(gs, Vector3(x0 - 0.01, eave_y, z_back), Vector2(depth, 0.0), west_normal)
	_roof_vertex(gs, Vector3(x1 + 0.01, eave_y, z_front), Vector2(0.0, 0.0), east_normal)
	_roof_vertex(gs, Vector3(x1 + 0.01, eave_y, z_back), Vector2(depth, 0.0), east_normal)
	_roof_vertex(gs, Vector3(x1 + 0.01, ridge_y, z_mid), Vector2(depth * 0.5, roof_h), east_normal)
	var gable_mesh: ArrayMesh = gs.commit()
	SceneKit.add_mesh(parent, gable_mesh, gable_mat, Vector3.ZERO)

	# ridge cap
	var ridge_mat: StandardMaterial3D = SceneKit.solid_material(Color("#3d4248"))
	SceneKit.add_box(
		parent,
		Vector3(span, 0.25, 0.5),
		ridge_mat,
		Vector3((xl + xr) * 0.5, ridge_y + 0.05, zm)
	)


func _roof_vertex(st: SurfaceTool, pos: Vector3, uv: Vector2, normal: Vector3) -> void:
	st.set_normal(normal)
	st.set_uv(uv)
	st.add_vertex(pos)


func _build_sign(parent: Node3D, sign_x: float, z_front: float, text: String, art: TownArt) -> void:
	var sign_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(1.0, 2.0)
	)
	SceneKit.add_box(
		parent,
		Vector3(1.1, 2.2, 0.12),
		sign_mat,
		Vector3(sign_x, 2.2, z_front + 0.12)
	)
	var label := art.make_label(text, 0.02, 96)
	label.position = Vector3(sign_x, 2.2, z_front + 0.2)
	parent.add_child(label)


func _build_lantern(parent: Node3D, x: float, y: float, z: float) -> void:
	var lamp_mat: StandardMaterial3D = SceneKit.emissive_material(Color("#d9582b"), 2.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	var lamp := SceneKit.add_mesh(parent, mesh, lamp_mat, Vector3(x, y, z))
	lamp.set_meta("night_light", true)
	SceneKit.add_omni_light(lamp, Vector3.ZERO, Color("#ffb860"), 7.0, 0.0)
	var hanger_mat: StandardMaterial3D = SceneKit.solid_material(Color("#3e2a1a"))
	SceneKit.add_box(parent, Vector3(0.06, 0.6, 0.06), hanger_mat, Vector3(x, y + 0.55, z))
	SceneKit.add_omni_light(parent, Vector3(x, y, z), Color("#ffb066"), 7.0, 1.4)


func _build_balcony(
	parent: Node3D, center_x: float, z_front: float, art: TownArt
) -> void:
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(6.0, 1.2)
	)
	SceneKit.add_box(
		parent, Vector3(6.0, 0.2, 1.2), wood_mat, Vector3(center_x, 3.6, z_front + 0.6)
	)
	SceneKit.add_box(
		parent,
		Vector3(6.0, 0.08, 0.08),
		wood_mat,
		Vector3(center_x, 4.05, z_front + 1.2)
	)
	SceneKit.add_box(
		parent,
		Vector3(0.08, 0.9, 1.2),
		wood_mat,
		Vector3(center_x - 3.0, 4.05, z_front + 0.6)
	)
	SceneKit.add_box(
		parent,
		Vector3(0.08, 0.9, 1.2),
		wood_mat,
		Vector3(center_x + 3.0, 4.05, z_front + 0.6)
	)
