extends RefCounted

# 酒馆房间静态几何构建：墙体、梁、窗、墙面装饰与楼梯。

const SceneKit = preload("res://shared/scene/scene_kit.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const Layout = preload("res://shared/scenery/tavern/tavern_layout.gd")
const TavernArt = preload("res://shared/scenery/tavern/tavern_art.gd")


static func build_room(parent: Node3D, room: Dictionary, art: TavernArt) -> Node3D:
	var root := Node3D.new()
	root.name = "Room"
	parent.add_child(root)
	var x0 := Layout.room_float(room, "x0", 0.0)
	var x1 := Layout.room_float(room, "x1", 22.0)
	var z_back := Layout.room_float(room, "z_back", -12.0)
	var z_front := Layout.room_float(room, "z_front", 6.0)
	var wall_h := Layout.room_float(room, "wall_height", 6.5)
	var wall_t := Layout.room_float(room, "wall_thickness", 0.3)
	var width := x1 - x0
	var depth := z_front - z_back
	var cx := (x0 + x1) * 0.5
	var cz := (z_back + z_front) * 0.5

	# Floor: the AI wood tile repeats every 4 units. The plane is rotated a quarter
	# turn so the planks run across the room.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(depth, width)
	var floor_mat: StandardMaterial3D = art.floor_material(Vector2(depth / 4.0, width / 4.0))
	floor_mat.albedo_color = Color(0.5, 0.44, 0.4)
	var floor_instance := SceneKit.add_mesh(
		root, floor_mesh, floor_mat, Vector3(cx, 0.0, cz), "Floor"
	)
	floor_instance.rotation.y = PI / 2.0

	var wainscot_h := 2.2
	var lower_wood: StandardMaterial3D = art.wood_material(
		Vector2(width / 3.0, wainscot_h / 3.0)
	)
	var upper_plaster: StandardMaterial3D = art.plaster_material(
		Vector2(width / 2.5, (wall_h - wainscot_h) / 2.5)
	)
	var side_lower_wood: StandardMaterial3D = art.wood_material(
		Vector2(depth / 3.0, wainscot_h / 3.0)
	)
	var side_upper_plaster: StandardMaterial3D = art.plaster_material(
		Vector2(depth / 2.5, (wall_h - wainscot_h) / 2.5)
	)

	# Back wall (z_back), only its inner face is ever seen.
	SceneKit.add_box(
		root,
		Vector3(width, wainscot_h, wall_t),
		lower_wood,
		Vector3(cx, wainscot_h * 0.5, z_back - wall_t * 0.5),
		"WainscotBack"
	)
	SceneKit.add_box(
		root,
		Vector3(width, wall_h - wainscot_h, wall_t),
		upper_plaster,
		Vector3(cx, wainscot_h + (wall_h - wainscot_h) * 0.5, z_back - wall_t * 0.5),
		"PlasterBack"
	)

	# Left and right walls.
	for side in range(2):
		var wall_x: float = x0 - wall_t * 0.5
		var side_name := "West"
		if side == 1:
			wall_x = x1 + wall_t * 0.5
			side_name = "East"
		SceneKit.add_box(
			root,
			Vector3(wall_t, wainscot_h, depth),
			side_lower_wood,
			Vector3(wall_x, wainscot_h * 0.5, cz),
			"Wainscot%s" % side_name
		)
		SceneKit.add_box(
			root,
			Vector3(wall_t, wall_h - wainscot_h, depth),
			side_upper_plaster,
			Vector3(wall_x, wainscot_h + (wall_h - wainscot_h) * 0.5, cz),
			"Plaster%s" % side_name
		)

	# Dark timber posts every 5 units along the back wall and both side walls.
	var post_mat: StandardMaterial3D = SceneKit.solid_material(Color("#3e2a1a"))
	var post_x := x0 + 0.35
	while post_x <= x1 - 0.2:
		SceneKit.add_box(
			root,
			Vector3(0.32, wall_h, 0.12),
			post_mat,
			Vector3(post_x, wall_h * 0.5, z_back + 0.06)
		)
		post_x += 5.0
	var post_z := z_back + 0.5
	while post_z <= z_front - 0.3:
		SceneKit.add_box(
			root,
			Vector3(0.12, wall_h, 0.32),
			post_mat,
			Vector3(x0 + 0.06, wall_h * 0.5, post_z)
		)
		SceneKit.add_box(
			root,
			Vector3(0.12, wall_h, 0.32),
			post_mat,
			Vector3(x1 - 0.06, wall_h * 0.5, post_z)
		)
		post_z += 5.0

	# Top beam across the back wall.
	SceneKit.add_box(
		root,
		Vector3(width, 0.35, 0.45),
		post_mat,
		Vector3(cx, wall_h - 0.175, z_back + 0.12),
		"TopBeam"
	)

	# A very large dark board behind the building stops the sky from showing above
	# the walls and keeps the outside of the room from reading as pure black.
	var backdrop_mat: StandardMaterial3D = SceneKit.solid_material(Color("#0f0a08"))
	backdrop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var backdrop := SceneKit.add_quad(
		root, Vector2(120.0, 60.0), backdrop_mat, Vector3(cx, 15.0, -30.0), "Backdrop"
	)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func build_beams(parent: Node3D, room: Dictionary, art: TavernArt) -> Node3D:
	var root := Node3D.new()
	root.name = "Beams"
	parent.add_child(root)
	var x0 := Layout.room_float(room, "x0", 0.0)
	var x1 := Layout.room_float(room, "x1", 22.0)
	var width := x1 - x0
	var cx := (x0 + x1) * 0.5
	var beam_mat: StandardMaterial3D = art.wood_material(Vector2(3.0, 1.0))
	beam_mat.albedo_color = Color(0.35, 0.3, 0.27)

	# Only two beams, tucked against the back wall: more of them cross the camera's view of the
	# upper wall and the windows and make the room look cluttered.
	for beam_z in [-11.2, -8.6]:
		SceneKit.add_box(
			root,
			Vector3(width, 0.4, 0.4),
			beam_mat,
			Vector3(cx, 6.2, float(beam_z)),
			"Beam"
		)
	return root


static func build_windows(parent: Node3D, room: Dictionary, art: TavernArt) -> Node3D:
	var root := Node3D.new()
	root.name = "Windows"
	parent.add_child(root)
	var z_back := Layout.room_float(room, "z_back", -12.0)
	var glass_mat: StandardMaterial3D = SceneKit.emissive_material(Color("#ffcf8a"), 1.2)
	var mullion_mat: StandardMaterial3D = SceneKit.solid_material(Color("#3a2818"))
	var window_xs: Array[float] = [3.5, 11.0, 18.5]
	var window_y := 3.8
	for i in range(window_xs.size()):
		var wx: float = window_xs[i]
		SceneKit.add_quad(
			root,
			Vector2(1.8, 1.4),
			glass_mat,
			Vector3(wx, window_y, z_back + 0.03),
			"WindowGlow%d" % i
		)
		for offset in [-0.6, -0.2, 0.2, 0.6]:
			SceneKit.add_box(
				root,
				Vector3(0.05, 1.4, 0.05),
				mullion_mat,
				Vector3(wx + float(offset), window_y, z_back + 0.06)
			)
		SceneKit.add_box(
			root,
			Vector3(1.8, 0.06, 0.05),
			mullion_mat,
			Vector3(wx, window_y, z_back + 0.06)
		)
		# Cold daylight spilling in from just inside the window.
		SceneKit.add_omni_light(
			root,
			Vector3(wx, window_y, z_back + 0.6),
			Color(0.62, 0.72, 0.9),
			9.0,
			0.9
		)
	return root


static func build_wall_decor(parent: Node3D, room: Dictionary, art: TavernArt) -> Node3D:
	var root := Node3D.new()
	root.name = "WallDecor"
	parent.add_child(root)
	var x0 := Layout.room_float(room, "x0", 0.0)
	var x1 := Layout.room_float(room, "x1", 22.0)
	var z_back := Layout.room_float(room, "z_back", -12.0)
	var z_front := Layout.room_float(room, "z_front", 6.0)
	var wall_h := Layout.room_float(room, "wall_height", 6.5)
	var cx := (x0 + x1) * 0.5
	var cz := (z_back + z_front) * 0.5
	var post_mat: StandardMaterial3D = SceneKit.solid_material(Color("#3e2a1a"))

	# Two extra timber posts on each side wall, matching the back wall rhythm.
	for side in range(2):
		var post_x := x0 + 0.08
		if side == 1:
			post_x = x1 - 0.08
		for post_z in [-8.0, 2.0]:
			SceneKit.add_box(
				root,
				Vector3(0.12, wall_h, 0.32),
				post_mat,
				Vector3(post_x, wall_h * 0.5, float(post_z))
			)

	# A small glowing wall lamp and its warm pool in the middle of each side wall.
	var lamp_mat: StandardMaterial3D = SceneKit.emissive_material(Color(1.0, 0.55, 0.28), 1.4)
	for side in range(2):
		var lamp_x := x0 + 0.15
		var light_x := x0 + 0.8
		if side == 1:
			lamp_x = x1 - 0.15
			light_x = x1 - 0.8
		SceneKit.add_box(
			root,
			Vector3(0.18, 0.28, 0.18),
			lamp_mat,
			Vector3(lamp_x, 3.3, cz),
			"WallLampWest" if side == 0 else "WallLampEast"
		)
		SceneKit.add_omni_light(
			root,
			Vector3(light_x, 3.3, cz),
			Color(1.0, 0.62, 0.32),
			4.0,
			0.7
		)

	# Two hanging scrolls flank the sign above the bar.
	var scroll_mat: StandardMaterial3D = art.image_material(art.scroll_image())
	var roller_mat: StandardMaterial3D = SceneKit.solid_material(Color("#3e2a1a"))
	var scroll_xs: Array[float] = [3.3, 18.7]
	for i in range(scroll_xs.size()):
		var sx: float = scroll_xs[i]
		SceneKit.add_quad(
			root,
			Vector2(0.9, 2.4),
			scroll_mat,
			Vector3(sx, 3.6, z_back + 0.15),
			"Scroll_%d" % (i + 1)
		)
		SceneKit.add_box(
			root,
			Vector3(0.98, 0.07, 0.07),
			roller_mat,
			Vector3(sx, 4.83, z_back + 0.17)
		)
		SceneKit.add_box(
			root,
			Vector3(0.98, 0.07, 0.07),
			roller_mat,
			Vector3(sx, 2.37, z_back + 0.17)
		)

	# The tavern sign, only when the painted prop is available.
	var sign := AiAssets.make_sprite(
		"prop_tavern_sign.png",
		1.7,
		Vector3(cx, 3.3, z_back + 0.2),
		"WallSign"
	)
	if sign != null:
		root.add_child(sign)
	return root


static func build_stairs(parent: Node3D, data: Dictionary, art: TavernArt) -> Node3D:
	var root := Node3D.new()
	root.name = "Stairs"
	parent.add_child(root)
	var stairs_value: Variant = data.get("stairs", null)
	var depth := 0.5
	if stairs_value is Dictionary:
		var stairs: Dictionary = stairs_value
		var sx0 := float(stairs.get("x0", 19.0))
		var sx1 := float(stairs.get("x1", 22.0))
		var z_top := float(stairs.get("z_top", -8.0))
		var z_bottom := float(stairs.get("z_bottom", -5.0))
		var steps: int = int(stairs.get("steps", 6))
		var height := float(stairs.get("height", 3.0))
		var step_mat: StandardMaterial3D = art.wood_material(Vector2(1.0, 1.0))
		var stairs_sprite: Sprite3D = art.sprite_by_width(
			root, "tavern_stairs.png", 6.0,
			Vector3(sx1 - 3.0, 0.0, (z_top + z_bottom) * 0.5),
			"StairsSprite"
		)
		if stairs_sprite == null and steps > 0:
			depth = (z_bottom - z_top) / float(steps)
			for i in range(steps):
				var step_h := height - (height / float(steps)) * float(i)
				var z_center := z_top + depth * (float(i) + 0.5)
				SceneKit.add_box(
					root,
					Vector3(sx1 - sx0, step_h, depth),
					step_mat,
					Vector3((sx0 + sx1) * 0.5, step_h * 0.5, z_center)
				)

	var platform_value: Variant = data.get("platform", null)
	if platform_value is Dictionary:
		var platform: Dictionary = platform_value
		var px0 := float(platform.get("x0", 16.5))
		var px1 := float(platform.get("x1", 22.0))
		var pz0 := float(platform.get("z0", -12.0))
		var pz1 := float(platform.get("z1", -8.0))
		var py := float(platform.get("y", 3.0))
		var deck_mat: StandardMaterial3D = art.wood_material(Vector2(1.0, 1.0))
		SceneKit.add_box(
			root,
			Vector3(px1 - px0, 0.3, pz1 - pz0),
			deck_mat,
			Vector3((px0 + px1) * 0.5, py - 0.15, (pz0 + pz1) * 0.5),
			"CorridorDeck"
		)
		# Railing along the front edge of the corridor.
		var rail_mat: StandardMaterial3D = SceneKit.solid_material(Color("#3e2a1a"))
		var rail_x := px0 + 0.3
		while rail_x <= px1 - 0.2:
			SceneKit.add_box(
				root,
				Vector3(0.1, 0.95, 0.1),
				rail_mat,
				Vector3(rail_x, py + 0.475, pz1 - 0.1)
			)
			rail_x += 1.1
		SceneKit.add_box(
			root,
			Vector3(px1 - px0, 0.08, 0.1),
			rail_mat,
			Vector3((px0 + px1) * 0.5, py + 0.95, pz1 - 0.1)
		)
		# A heavier handrail along the top, plus two post lamps (no light source).
		SceneKit.add_box(
			root,
			Vector3(px1 - px0, 0.12, 0.18),
			rail_mat,
			Vector3((px0 + px1) * 0.5, py + 1.04, pz1 - 0.1),
			"Handrail"
		)
		var lamp_mat: StandardMaterial3D = SceneKit.emissive_material(Color(1.0, 0.55, 0.28), 1.6)
		for lamp_x in [px0 + 1.1, px1 - 1.1]:
			SceneKit.add_box(
				root,
				Vector3(0.12, 1.9, 0.12),
				rail_mat,
				Vector3(float(lamp_x), py + 0.95, pz1 - 0.1)
			)
			SceneKit.add_box(
				root,
				Vector3(0.26, 0.3, 0.26),
				lamp_mat,
				Vector3(float(lamp_x), py + 2.05, pz1 - 0.1)
			)
	return root
