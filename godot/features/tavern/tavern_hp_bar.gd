extends RefCounted

# 酒馆前戏用的头顶血条：返回 [根节点, 填充条, 文字标签]。填充条靠 scale.x 表示比例。

static func make(parent: Node3D, bar_name: String, color: Color) -> Array:
	var root := Node3D.new()
	root.name = bar_name
	parent.add_child(root)
	var back := _sprite(Color(0.16, 0.05, 0.05, 0.95), 108, 12)
	back.position = Vector3(-1.08, -0.06, 0.0)
	root.add_child(back)
	var fill := _sprite(color, 100, 6)
	fill.position = Vector3(-1.0, 0.0, 0.01)
	root.add_child(fill)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.008
	label.font_size = 40
	label.outline_size = 8
	label.outline_modulate = Color.BLACK
	label.position = Vector3(0.0, 0.42, 0.0)
	root.add_child(label)
	root.visible = false
	return [root, fill, label]


static func _sprite(color: Color, width: int, height: int) -> Sprite3D:
	var img: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var sprite := Sprite3D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.pixel_size = 0.02
	sprite.centered = false
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return sprite
