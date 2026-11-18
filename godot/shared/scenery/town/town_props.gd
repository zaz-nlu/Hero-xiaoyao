extends RefCounted

# 小镇道具与植被：摊位、水井、告示牌、旗帜、树木与紫霞林路牌。
# 旗帜摆动由本对象自己的计时器推进，不依赖 controller 的 _time。

const SceneKit = preload("res://shared/scene/scene_kit.gd")
const Texgen = preload("res://shared/scene/texgen.gd")
const AiAssets = preload("res://shared/resources/ai_assets.gd")
const TownArt = preload("res://shared/scenery/town/town_art.gd")

const FOREST_SIGN_POS := Vector2(5.4, 20.7)
const DECOR_FILES := {
	"shrub": "prop_shrub.png",
	"grass_tuft": "prop_grass.png",
	"peony": "prop_peony.png",
	"chrysanthemum": "prop_chrysanthemum.png",
	"bamboo": "prop_bamboo.png",
	"rocks": "prop_rocks.png",
}
const DECOR_HEIGHTS := {
	"shrub": 1.1,
	"grass_tuft": 1.0,
	"peony": 1.0,
	"chrysanthemum": 0.9,
	"bamboo": 3.2,
	"rocks": 1.0,
}

var _banners: Array[Node3D] = []
var _banner_phases: Array[float] = []
var _time: float = 0.0


func build_props(
	parent: Node3D, data: Dictionary, art: TownArt, tavern_facade: bool
) -> void:
	var root := Node3D.new()
	root.name = "Props"
	parent.add_child(root)
	var props: Array = data.get("props", [])
	for i in range(props.size()):
		var prop_value: Variant = props[i]
		if typeof(prop_value) != TYPE_DICTIONARY:
			continue
		var prop: Dictionary = prop_value
		var kind := str(prop.get("kind", ""))
		var x := float(prop.get("x", 0.0))
		var z := float(prop.get("z", 0.0))
		match kind:
			"barrel":
				_build_barrel(root, x, z, art)
			"crate":
				_build_crate(root, x, z, art)
			"bench":
				_build_bench(root, x, z, art)
			"lamp_post":
				_build_lamp_post(root, x, z, art)
			"banner":
				if not tavern_facade:
					_build_banner(root, x, z, str(prop.get("text", "")), art)
			"cart":
				_build_cart(root, x, z, float(prop.get("rot", 0.0)), art)
			"stall":
				_build_stall(
					root,
					x,
					z,
					float(prop.get("w", 4.0)),
					float(prop.get("d", 2.0)),
					str(prop.get("text", "")),
					art
				)
			"tree":
				_build_tree(root, x, z, art)
			"jars":
				_build_jars(root, x, z, i)
			"baskets":
				_build_baskets(root, x, z, i)
			"stone_lantern":
				_build_stone_lantern(root, x, z, i)
			"boat":
				_build_boat(root, x, z, i)
			"well":
				_build_well(root, x, z, art)
			"notice_board":
				_build_notice_board(root, x, z, art)
			"shrub", "grass_tuft", "peony", "chrysanthemum", "bamboo", "rocks":
				_build_decor(root, kind, x, z, i)


func build_forest_sign(parent: Node3D, art: TownArt) -> void:
	var root := Node3D.new()
	root.name = "ForestSign"
	root.position = Vector3(FOREST_SIGN_POS.x, 0.0, FOREST_SIGN_POS.y)
	parent.add_child(root)
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(0.5, 2.0)
	)
	SceneKit.add_box(root, Vector3(0.14, 1.7, 0.14), wood_mat, Vector3(0.0, 0.85, 0.0), "Post")
	SceneKit.add_box(root, Vector3(2.0, 0.55, 0.1), wood_mat, Vector3(0.0, 1.55, 0.0), "Board")
	var label := art.make_label("紫霞林", 0.012, 48)
	label.position = Vector3(0.0, 1.55, 0.08)
	root.add_child(label)


func advance(delta: float) -> void:
	_time += delta
	for i in range(_banners.size()):
		var banner: Node3D = _banners[i]
		if not is_instance_valid(banner):
			continue
		var phase: float = _banner_phases[i]
		banner.rotation.y = sin(_time * TAU / 3.0 + phase) * deg_to_rad(6.0)


func _build_decor(parent: Node3D, kind: String, x: float, z: float, index: int) -> void:
	var file := str(DECOR_FILES.get(kind, ""))
	if file == "":
		return
	var sprite := AiAssets.make_sprite(
		file,
		float(DECOR_HEIGHTS.get(kind, 1.0)),
		Vector3(x, 0.0, z),
		"Decor_%s_%d" % [kind, index]
	)
	if sprite != null:
		parent.add_child(sprite)


func _build_barrel(parent: Node3D, x: float, z: float, art: TownArt) -> void:
	var sprite := AiAssets.make_sprite("prop_barrel.png", 1.2, Vector3(x, 0.0, z), "Barrel")
	if sprite != null:
		parent.add_child(sprite)
		return
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(1.0, 1.0)
	)
	var body := CylinderMesh.new()
	body.top_radius = 0.45
	body.bottom_radius = 0.45
	body.height = 0.9
	SceneKit.add_mesh(parent, body, wood_mat, Vector3(x, 0.45, z))
	var hoop_mat: StandardMaterial3D = SceneKit.solid_material(Color("#3e2a1a"))
	var hoop_heights: Array[float] = [0.22, 0.68]
	for hoop_y in hoop_heights:
		var hoop := CylinderMesh.new()
		hoop.top_radius = 0.47
		hoop.bottom_radius = 0.47
		hoop.height = 0.08
		SceneKit.add_mesh(parent, hoop, hoop_mat, Vector3(x, hoop_y, z))


func _build_crate(parent: Node3D, x: float, z: float, art: TownArt) -> void:
	var sprite := AiAssets.make_sprite("prop_crates.png", 1.3, Vector3(x, 0.0, z), "Crates")
	if sprite != null:
		parent.add_child(sprite)
		return
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(0.9, 0.9)
	)
	SceneKit.add_box(parent, Vector3(0.9, 0.9, 0.9), wood_mat, Vector3(x, 0.45, z))


func _build_bench(parent: Node3D, x: float, z: float, art: TownArt) -> void:
	var sprite := AiAssets.make_sprite("prop_bench.png", 0.9, Vector3(x, 0.0, z), "Bench")
	if sprite != null:
		parent.add_child(sprite)
		return
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(2.0, 0.6)
	)
	var leg_mat: StandardMaterial3D = SceneKit.solid_material(Color("#4a3020"))
	SceneKit.add_box(parent, Vector3(2.0, 0.15, 0.6), wood_mat, Vector3(x, 0.5, z))
	SceneKit.add_box(parent, Vector3(0.15, 0.5, 0.5), leg_mat, Vector3(x - 0.7, 0.25, z))
	SceneKit.add_box(parent, Vector3(0.15, 0.5, 0.5), leg_mat, Vector3(x + 0.7, 0.25, z))


func _build_lamp_post(parent: Node3D, x: float, z: float, art: TownArt) -> void:
	var sprite := AiAssets.make_sprite(
		"prop_lantern_post.png", 3.0, Vector3(x, 0.0, z), "LanternPost"
	)
	if sprite != null:
		parent.add_child(sprite)
		SceneKit.add_omni_light(parent, Vector3(x, 1.6, z), Color("#ffb870"), 8.0, 0.9)
		return
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(0.5, 4.0)
	)
	SceneKit.add_box(parent, Vector3(0.12, 3.2, 0.12), wood_mat, Vector3(x, 1.6, z))
	var lamp_mat: StandardMaterial3D = SceneKit.emissive_material(Color("#ffc070"), 1.6)
	SceneKit.add_box(parent, Vector3(0.35, 0.45, 0.35), lamp_mat, Vector3(x, 3.35, z))
	var cap_mat: StandardMaterial3D = SceneKit.solid_material(Color("#3e2a1a"))
	SceneKit.add_box(parent, Vector3(0.45, 0.08, 0.45), cap_mat, Vector3(x, 3.62, z))
	SceneKit.add_omni_light(parent, Vector3(x, 3.35, z), Color("#ffb870"), 8.0, 0.9)


func _build_banner(parent: Node3D, x: float, z: float, text: String, art: TownArt) -> void:
	var banner := Node3D.new()
	banner.name = "Banner%d" % _banners.size()
	banner.position = Vector3(x, 0.0, z)
	parent.add_child(banner)
	_banners.append(banner)
	_banner_phases.append(float(_banners.size()) * 1.7)

	var pole_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(0.5, 4.0)
	)
	SceneKit.add_box(banner, Vector3(0.12, 4.0, 0.12), pole_mat, Vector3(0.0, 2.0, 0.0))
	var cloth_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("cloth_red"), Vector2.ONE
	)
	cloth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	SceneKit.add_quad(banner, Vector2(1.2, 2.4), cloth_mat, Vector3(0.66, 2.6, 0.0))
	if text != "":
		var label := art.make_label(text, 0.01, 96)
		label.position = Vector3(0.66, 2.6, 0.06)
		banner.add_child(label)


func _build_cart(parent: Node3D, x: float, z: float, rot: float, art: TownArt) -> void:
	var cart := Node3D.new()
	cart.name = "Cart"
	cart.position = Vector3(x, 0.0, z)
	cart.rotation.y = rot
	parent.add_child(cart)
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(2.4, 1.3)
	)
	SceneKit.add_box(cart, Vector3(2.4, 0.2, 1.3), wood_mat, Vector3(0.0, 0.65, 0.0))
	var wheel_mat: StandardMaterial3D = SceneKit.solid_material(Color("#4a3020"))
	var wheel_xs: Array[float] = [-0.9, 0.9]
	for wheel_x in wheel_xs:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.55
		wheel.bottom_radius = 0.55
		wheel.height = 0.12
		var wheel_node := SceneKit.add_mesh(cart, wheel, wheel_mat, Vector3(wheel_x, 0.55, 0.0))
		wheel_node.rotation = Vector3(0.0, 0.0, PI / 2.0)
	var handle_xs: Array[float] = [-0.45, 0.45]
	for handle_x in handle_xs:
		SceneKit.add_box(cart, Vector3(0.1, 0.1, 1.6), wood_mat, Vector3(handle_x, 0.8, 1.25))


func _build_stall(
	parent: Node3D,
	x: float,
	z: float,
	width: float,
	depth: float,
	text: String,
	art: TownArt
) -> void:
	var sprite := AiAssets.make_sprite(
		"facade_baozi_stall.png", 3.6, Vector3(x, 0.0, z), "StallFacade"
	)
	if sprite != null:
		parent.add_child(sprite)
		return
	var stall := Node3D.new()
	stall.name = "Stall"
	stall.position = Vector3(x, 0.0, z)
	parent.add_child(stall)
	var post_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(0.5, 2.6)
	)
	var post_xs: Array[float] = [-width * 0.5 + 0.15, width * 0.5 - 0.15]
	var post_zs: Array[float] = [-depth * 0.5 + 0.15, depth * 0.5 - 0.15]
	for post_x in post_xs:
		for post_z in post_zs:
			SceneKit.add_box(stall, Vector3(0.12, 2.6, 0.12), post_mat, Vector3(post_x, 1.3, post_z))
	var canopy_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("awning_stripes"), Vector2(width, depth)
	)
	var canopy := SceneKit.add_box(
		stall,
		Vector3(width + 0.4, 0.08, depth + 0.4),
		canopy_mat,
		Vector3(0.0, 2.62, 0.0)
	)
	canopy.rotation.x = -deg_to_rad(6.0)
	var counter_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(width, 0.9)
	)
	SceneKit.add_box(stall, Vector3(width, 0.15, 0.9), counter_mat, Vector3(0.0, 1.0, 0.15))
	var bamboo_mat: StandardMaterial3D = SceneKit.solid_material(Color("#d8c090"))
	for i in range(3):
		var basket := CylinderMesh.new()
		basket.top_radius = 0.3
		basket.bottom_radius = 0.3
		basket.height = 0.25
		SceneKit.add_mesh(stall, basket, bamboo_mat, Vector3(float(i) - 1.0, 1.2, 0.15))
	if text != "":
		var label := art.make_label(text, 0.02, 96)
		label.position = Vector3(0.0, 2.3, depth * 0.5 + 0.1)
		stall.add_child(label)


func _build_tree(parent: Node3D, x: float, z: float, art: TownArt) -> void:
	var willow := AiAssets.make_sprite(
		"prop_willow.png", 4.2, Vector3(x, 0.0, z), "Willow"
	)
	if willow != null:
		parent.add_child(willow)
		return
	var tree := Sprite3D.new()
	tree.name = "Tree"
	tree.texture = art.get_tex("tree")
	tree.pixel_size = 1.0 / 16.0
	tree.offset = Vector2(0, 32)
	tree.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tree.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tree.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	tree.shaded = true
	tree.double_sided = true
	tree.position = Vector3(x, 0.0, z)
	parent.add_child(tree)

	var shadow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 1.2)
	shadow.mesh = quad
	var shadow_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("blob_shadow"), Vector2.ONE, true, true
	)
	shadow_mat.alpha_scissor_threshold = 0.05
	shadow.material_override = shadow_mat
	shadow.position = Vector3(x, 0.03, z)
	shadow.rotation.x = -PI / 2.0
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shadow)


func _build_jars(parent: Node3D, x: float, z: float, index: int) -> void:
	var sprite := AiAssets.make_sprite(
		"prop_jars.png", 1.0, Vector3(x, 0.0, z), "Jars%d" % index
	)
	if sprite != null:
		parent.add_child(sprite)


func _build_baskets(parent: Node3D, x: float, z: float, index: int) -> void:
	var sprite := AiAssets.make_sprite(
		"prop_baskets.png", 0.8, Vector3(x, 0.0, z), "Baskets%d" % index
	)
	if sprite != null:
		parent.add_child(sprite)


func _build_stone_lantern(parent: Node3D, x: float, z: float, index: int) -> void:
	var sprite := AiAssets.make_sprite(
		"prop_stone_lantern.png", 1.6, Vector3(x, 0.0, z), "StoneLantern%d" % index
	)
	if sprite != null:
		parent.add_child(sprite)


func _build_boat(parent: Node3D, x: float, z: float, index: int) -> void:
	var texture := AiAssets.load_texture("prop_boat.png")
	if texture == null:
		return
	var size := texture.get_size()
	if size.x <= 0.0:
		return
	var height: float = 6.0 * size.y / size.x
	var sprite := AiAssets.make_sprite(
		"prop_boat.png", height, Vector3(x, -0.15, z), "Boat%d" % index
	)
	if sprite != null:
		parent.add_child(sprite)


func _build_well(parent: Node3D, x: float, z: float, art: TownArt) -> void:
	var root := Node3D.new()
	root.name = "Well"
	root.position = Vector3(x, 0.0, z)
	parent.add_child(root)
	var stone_mat: StandardMaterial3D = art.make_step_stone_material(Vector2(1.0, 1.0))
	var ring := CylinderMesh.new()
	ring.top_radius = 0.7
	ring.bottom_radius = 0.7
	ring.height = 1.0
	SceneKit.add_mesh(root, ring, stone_mat, Vector3(0.0, 0.5, 0.0), "StoneRing")
	var water_mat: StandardMaterial3D = SceneKit.solid_material(Color("#1d3a44"))
	water_mat.roughness = 0.35
	var water := CylinderMesh.new()
	water.top_radius = 0.5
	water.bottom_radius = 0.5
	water.height = 0.04
	SceneKit.add_mesh(root, water, water_mat, Vector3(0.0, 1.01, 0.0), "WellWater")
	var wood_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(0.5, 2.0)
	)
	SceneKit.add_box(root, Vector3(0.14, 1.6, 0.14), wood_mat, Vector3(-0.62, 0.8, 0.0), "PostLeft")
	SceneKit.add_box(root, Vector3(0.14, 1.6, 0.14), wood_mat, Vector3(0.62, 0.8, 0.0), "PostRight")
	SceneKit.add_box(root, Vector3(1.5, 0.14, 0.16), wood_mat, Vector3(0.0, 1.68, 0.0), "Beam")


func _build_notice_board(parent: Node3D, x: float, z: float, art: TownArt) -> void:
	var root := Node3D.new()
	root.name = "NoticeBoard"
	root.position = Vector3(x, 0.0, z)
	parent.add_child(root)
	var post_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(0.5, 2.0)
	)
	SceneKit.add_box(root, Vector3(0.12, 1.7, 0.12), post_mat, Vector3(-0.65, 0.85, 0.0), "PostLeft")
	SceneKit.add_box(root, Vector3(0.12, 1.7, 0.12), post_mat, Vector3(0.65, 0.85, 0.0), "PostRight")
	var board_mat: StandardMaterial3D = Texgen.make_material(
		art.get_tex("wood_planks"), Vector2(2.0, 1.0)
	)
	SceneKit.add_box(root, Vector3(1.6, 0.9, 0.12), board_mat, Vector3(0.0, 1.25, 0.0), "Board")
	var paper_mat: StandardMaterial3D = SceneKit.solid_material(Color("#efe4c4"))
	var paper_xs: Array[float] = [-0.45, 0.0, 0.45]
	for index in range(paper_xs.size()):
		SceneKit.add_quad(
			root,
			Vector2(0.34, 0.44),
			paper_mat,
			Vector3(paper_xs[index], 1.25, 0.07),
			"Paper%d" % index
		)
