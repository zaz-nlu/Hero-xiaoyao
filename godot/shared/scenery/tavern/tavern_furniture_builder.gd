extends RefCounted

# 酒馆家具构建：家具节点、残骸与酒架。只负责建树，不持有控制器状态。

const SceneKit = preload("res://shared/scene/scene_kit.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const Layout = preload("res://shared/scenery/tavern/tavern_layout.gd")
const TavernArt = preload("res://shared/scenery/tavern/tavern_art.gd")


static func build_furniture(
	parent: Node3D, entries: Dictionary, art: TavernArt
) -> Dictionary:
	var root := Node3D.new()
	root.name = "Furniture"
	parent.add_child(root)
	var nodes: Dictionary = {}
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		var node := Node3D.new()
		node.name = str(id)
		node.transform = Layout.transform_from_dict(entry.get("normal", {}))
		root.add_child(node)
		fill_furniture(node, str(entry.get("kind", "")), entry, art)
		nodes[str(id)] = node
	var debris_root := build_wrecked_debris(root)
	return {"root": root, "debris_root": debris_root, "nodes": nodes}


static func fill_furniture(
	node: Node3D, kind: String, entry: Dictionary, art: TavernArt
) -> void:
	var wood: StandardMaterial3D = art.wood_material(Vector2(1.0, 1.0))
	var dark: StandardMaterial3D = SceneKit.solid_material(Color("#3e2a1a"))
	match kind:
		"bar":
			var bar_sprite: Sprite3D = art.sprite_by_width(
				node, "tavern_bar_counter.png", 8.0, Vector3.ZERO, "BarSprite"
			)
			if bar_sprite == null:
				SceneKit.add_box(
					node, Vector3(8.0, 1.15, 1.2), wood, Vector3(0.0, 0.575, 0.0), "BarBody"
				)
				SceneKit.add_box(
					node, Vector3(8.3, 0.15, 1.4), wood, Vector3(0.0, 1.225, 0.0), "BarTop"
				)
				var bar_porcelain: StandardMaterial3D = SceneKit.solid_material(
					Color("#efe9da")
				)
				for offset in [-2.5, -1.9, 2.0]:
					var bar_bowl := CylinderMesh.new()
					bar_bowl.top_radius = 0.22
					bar_bowl.bottom_radius = 0.13
					bar_bowl.height = 0.12
					SceneKit.add_mesh(
						node, bar_bowl, bar_porcelain, Vector3(float(offset), 1.36, 0.0)
					)
		"shelf":
			if not add_wine_shelf(node):
				SceneKit.add_box(
					node, Vector3(8.0, 3.2, 0.2), wood, Vector3(0.0, 1.6, -0.05), "ShelfBack"
				)
				SceneKit.add_box(
					node, Vector3(8.0, 0.12, 0.5), wood, Vector3(0.0, 1.0, 0.1), "ShelfLow"
				)
				SceneKit.add_box(
					node, Vector3(8.0, 0.12, 0.5), wood, Vector3(0.0, 2.1, 0.1), "ShelfHigh"
				)
				SceneKit.add_box(
					node, Vector3(8.0, 0.12, 0.5), wood, Vector3(0.0, 2.7, 0.1), "ShelfTop"
				)
				var jar_xs: Array[float] = [-3.0, -1.8, -0.6, 0.6, 1.8, 3.0]
				var jar_fallback: StandardMaterial3D = SceneKit.solid_material(
					Color("#8a6a3a")
				)
				for jar_x in jar_xs:
					var sprite := AiAssets.make_sprite(
						"prop_jars.png", 0.9, Vector3(jar_x, 1.06, 0.15), "Jar"
					)
					if sprite != null:
						node.add_child(sprite)
					else:
						var jar := CylinderMesh.new()
						jar.top_radius = 0.2
						jar.bottom_radius = 0.24
						jar.height = 0.45
						SceneKit.add_mesh(node, jar, jar_fallback, Vector3(jar_x, 1.29, 0.15))
				for jar_x in [-2.4, 0.0, 2.4]:
					var mid_jar := AiAssets.make_sprite(
						"prop_jars.png", 0.42, Vector3(float(jar_x), 2.16, 0.15), "JarMid"
					)
					if mid_jar != null:
						node.add_child(mid_jar)
				for basket_x in [-2.6, 0.0, 2.6]:
					var basket := AiAssets.make_sprite(
						"prop_baskets.png", 0.44, Vector3(float(basket_x), 2.76, 0.15),
						"Basket"
					)
					if basket != null:
						node.add_child(basket)
					else:
						SceneKit.add_box(
							node,
							Vector3(0.45, 0.3, 0.45),
							jar_fallback,
							Vector3(float(basket_x), 2.91, 0.15)
						)
		"barrel":
			art.sprite_prop(
				node, "prop_barrel.png", 1.2, Vector3(0.9, 0.9, 0.9), wood
			)
		"table":
			var table_sprite := AiAssets.make_sprite(
				"tavern_square_table.png", 1.5, Vector3.ZERO, "TableSprite"
			)
			if table_sprite != null:
				node.add_child(table_sprite)
				if entry.has("wrecked"):
					var wrecked_sprite := AiAssets.make_sprite(
						"tavern_wrecked_overturned_table.png", 1.2, Vector3.ZERO,
						"TableWreckedSprite"
					)
					if wrecked_sprite != null:
						wrecked_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
						wrecked_sprite.visible = false
						wrecked_sprite.basis = Layout.wrecked_sprite_basis(entry)
						node.add_child(wrecked_sprite)
			else:
				SceneKit.add_box(
					node, Vector3(1.8, 0.12, 1.8), wood, Vector3(0.0, 0.89, 0.0), "TableTop"
				)
				SceneKit.add_box(
					node, Vector3(1.86, 0.04, 1.86), dark, Vector3(0.0, 0.9, 0.0), "TableRim"
				)
				var leg_xs: Array[float] = [-0.75, 0.75]
				for leg_x in leg_xs:
					for leg_z in leg_xs:
						SceneKit.add_box(
							node,
							Vector3(0.12, 0.83, 0.12),
							dark,
							Vector3(leg_x, 0.415, leg_z)
						)
				var stool := CylinderMesh.new()
				stool.top_radius = 0.34
				stool.bottom_radius = 0.36
				stool.height = 0.16
				SceneKit.add_mesh(node, stool, dark, Vector3(0.0, 0.08, 0.0), "FootStool")
		"bench":
			var bench_sprite := AiAssets.make_sprite(
				"tavern_long_bench.png", 0.7, Vector3.ZERO, "BenchSprite"
			)
			if bench_sprite != null:
				node.add_child(bench_sprite)
				var broken_bench := AiAssets.make_sprite(
					"tavern_wrecked_broken_bench.png", 0.7, Vector3.ZERO,
					"BenchWreckedSprite"
				)
				if broken_bench != null:
					broken_bench.modulate = Color(1.0, 1.0, 1.0, 0.0)
					broken_bench.visible = false
					broken_bench.basis = Layout.wrecked_sprite_basis(entry)
					node.add_child(broken_bench)
			else:
				art.sprite_prop(
					node, "prop_bench.png", 0.9, Vector3(2.0, 0.45, 0.6), wood
				)
		"crates":
			var crate_h: float = Layout.entry_float(entry, "height", 1.3)
			art.sprite_prop(
				node, "prop_crates.png", crate_h, Vector3(0.9, crate_h, 0.9), wood
			)
		"baskets":
			var basket_h: float = Layout.entry_float(entry, "height", 0.8)
			art.sprite_prop(
				node, "prop_baskets.png", basket_h, Vector3(0.7, basket_h, 0.7), dark
			)
		"crate_lid":
			var lid_mat: StandardMaterial3D = art.wood_material(Vector2(0.7, 0.7))
			var crate_lid_mesh := SceneKit.add_box(
				node, Vector3(0.8, 0.07, 0.75), lid_mat, Vector3(0.0, 0.06, 0.0), "CrateLid"
			)
			crate_lid_mesh.rotation.x = deg_to_rad(-58.0)
		"jars":
			art.sprite_prop(
				node, "prop_jars.png", 1.0, Vector3(0.5, 0.6, 0.5), dark
			)
		"bowl":
			var porcelain: StandardMaterial3D = SceneKit.solid_material(Color("#efe9da"))
			var bowl := CylinderMesh.new()
			bowl.top_radius = 0.22
			bowl.bottom_radius = 0.13
			bowl.height = 0.12
			SceneKit.add_mesh(node, bowl, porcelain, Vector3(0.0, 0.06, 0.0), "Bowl")
			var soup_mat: StandardMaterial3D = SceneKit.solid_material(Color("#5e1c1a"))
			var soup := CylinderMesh.new()
			soup.top_radius = 0.185
			soup.bottom_radius = 0.185
			soup.height = 0.02
			SceneKit.add_mesh(node, soup, soup_mat, Vector3(0.0, 0.115, 0.0), "Soup")
			var topping_mat: StandardMaterial3D = SceneKit.solid_material(Color("#e0b070"))
			var topping := CylinderMesh.new()
			topping.top_radius = 0.055
			topping.bottom_radius = 0.055
			topping.height = 0.012
			SceneKit.add_mesh(
				node, topping, topping_mat, Vector3(0.03, 0.126, -0.02), "Topping"
			)
		"cup":
			var cup_porcelain: StandardMaterial3D = SceneKit.solid_material(Color("#efe9da"))
			var cup := CylinderMesh.new()
			cup.top_radius = 0.06
			cup.bottom_radius = 0.045
			cup.height = 0.1
			SceneKit.add_mesh(node, cup, cup_porcelain, Vector3(0.0, 0.05, 0.0), "Cup")
		"abacus":
			var abacus_mat: StandardMaterial3D = SceneKit.solid_material(Color("#4a3020"))
			var rod_mat: StandardMaterial3D = SceneKit.solid_material(Color("#2e1e12"))
			SceneKit.add_box(
				node, Vector3(0.55, 0.06, 0.4), abacus_mat, Vector3(0.0, 0.03, 0.0),
				"AbacusBody"
			)
			for rod_z in [-0.1, 0.1]:
				SceneKit.add_box(
					node,
					Vector3(0.5, 0.02, 0.02),
					rod_mat,
					Vector3(0.0, 0.075, float(rod_z))
				)
		"rug":
			var rug_mat: StandardMaterial3D = art.image_material(art.rug_image())
			var rug := SceneKit.add_quad(
				node, Vector2(9.0, 5.0), rug_mat, Vector3(0.0, 0.006, 0.0), "RugMesh"
			)
			rug.rotation.x = -PI / 2.0
			rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"teapot":
			var pot_mat: StandardMaterial3D = SceneKit.solid_material(Color("#8a5a3a"))
			var body := CylinderMesh.new()
			body.top_radius = 0.16
			body.bottom_radius = 0.2
			body.height = 0.22
			SceneKit.add_mesh(node, body, pot_mat, Vector3(0.0, 0.11, 0.0), "TeapotBody")
			var lid := SphereMesh.new()
			lid.radius = 0.09
			lid.height = 0.1
			SceneKit.add_mesh(node, lid, pot_mat, Vector3(0.0, 0.24, 0.0))
			SceneKit.add_box(node, Vector3(0.22, 0.04, 0.05), pot_mat, Vector3(0.0, 0.2, 0.26))
		"stain":
			var stain_mat := StandardMaterial3D.new()
			stain_mat.albedo_color = Color(0.32, 0.05, 0.04, 0.55)
			stain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			stain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			stain_mat.roughness = 1.0
			stain_mat.metallic = 0.0
			stain_mat.metallic_specular = 0.0
			var quad := SceneKit.add_quad(
				node, Vector2(3.2, 2.2), stain_mat, Vector3.ZERO, "WineStain"
			)
			quad.rotation.x = -PI / 2.0
			quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func build_wrecked_debris(furniture_root: Node3D) -> Node3D:
	var debris_root := Node3D.new()
	debris_root.name = "WreckedDebris"
	debris_root.visible = false
	furniture_root.add_child(debris_root)
	var pieces: Array = [
		["tavern_wrecked_broken_bowls.png", 0.4, Vector3(7.2, 0.0, -2.0), 15.0,
				"wrecked_broken_bowls_1"],
		["tavern_wrecked_broken_bowls.png", 0.34, Vector3(8.1, 0.0, -2.7), -35.0,
				"wrecked_broken_bowls_2"],
		["tavern_wrecked_broken_planks.png", 0.5, Vector3(12.3, 0.0, -1.4), 25.0,
				"wrecked_broken_planks_1"],
		["tavern_wrecked_broken_planks.png", 0.44, Vector3(13.6, 0.0, 0.6), -50.0,
				"wrecked_broken_planks_2"],
		["tavern_wrecked_smashed_stool.png", 0.6, Vector3(9.6, 0.0, 0.6), -20.0,
				"wrecked_smashed_stool_1"],
	]
	for raw in pieces:
		var row: Array = raw
		var sprite := AiAssets.make_sprite(
			str(row[0]), float(row[1]), row[2], str(row[4])
		)
		if sprite == null:
			continue
		sprite.rotation.y = deg_to_rad(float(row[3]))
		debris_root.add_child(sprite)
	var wine := AiAssets.make_sprite(
		"tavern_wrecked_spilled_wine.png", 1.4, Vector3(10.2, 0.03, -0.6),
		"wrecked_spilled_wine_1"
	)
	if wine != null:
		wine.rotation.x = -PI / 2.0
		debris_root.add_child(wine)
	return debris_root


# Two painted wine shelves side by side; false means "use the code-built shelf".
static func add_wine_shelf(node: Node3D) -> bool:
	var texture: ImageTexture = AiAssets.load_texture("tavern_wine_shelf.png")
	if texture == null:
		return false
	var size: Vector2 = texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	var shelf_width := 3.6
	var shelf_height: float = shelf_width * size.y / size.x
	var placed := 0
	for i in range(2):
		var sprite := AiAssets.make_sprite(
			"tavern_wine_shelf.png", shelf_height,
			Vector3(-1.85 + float(i) * 3.7, 0.0, 0.0), "WineShelf_%d" % i
		)
		if sprite == null:
			break
		node.add_child(sprite)
		placed += 1
	return placed == 2
