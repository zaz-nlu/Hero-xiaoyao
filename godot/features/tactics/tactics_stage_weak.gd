extends Node3D

# 敌人头顶的弱点图标：每个非 none 的弱点槽一枚 Sprite3D billboard，挂在演员节点下，
# 随单位移动。sync 时与上次颜色比较：颜色变化则弹出（0.4 → 1.35 → 1.0，并短暂提亮），
# 槽被清空则淡出移除。只读 TacticsUnit.weaknesses，不调用规则。

const UI = preload("res://features/tactics/tactics_ui_style.gd")

const ICON_HEIGHT := 1.0
const ICON_GAP := 0.18
const ICON_Y := 1.1
const ICON_RING := 1.15
const WEDGE_RING := 1.0
const WEDGE_SIZE := 2.5
const WEDGE_TEX := 128
const PULSE_SPEED := 5.0
const POP_RISE := 0.16
const POP_SETTLE := 0.14
const GLOW_TIME := 0.25
const FADE_TIME := 0.2
const FADE_SCALE := 0.6
const GLOW_COLOR := Color(1.7, 1.7, 1.7, 1.0)
const FALLBACK_COLORS := {
	"neili": Color(0.35, 0.62, 1.0),
	"ziqi": Color(0.72, 0.45, 1.0),
	"xianqi": Color(0.30, 0.88, 0.88),
}
const FALLBACK_TEXTURE_SIZE := 64
const NONE := "none"

static var _fallback_textures: Dictionary = {}
static var _wedge_texture: Texture2D = null
static var _core_texture: Texture2D = null

var _icons: Dictionary = {}
var _slot_colors: Array = []
var _slot_dirs: Array = []
var _pops: int = 0
var _initialized: bool = false
var _wedges: Dictionary = {}
var _time: float = 0.0


# 每次 set_state 调用：首次建立基线不播放弹出；颜色变化的槽弹出，清空的槽移除。
func sync(unit) -> void:
	if unit == null:
		return
	var colors := _read_colors(unit)
	var dirs := _read_dirs(unit)
	if not _initialized:
		_initialized = true
		_slot_colors = colors
		_slot_dirs = dirs
		for i in range(colors.size()):
			var color := str(colors[i])
			if color != NONE and color != "":
				_ensure(i, color)
		_layout()
		return
	for i in range(colors.size()):
		var old := NONE
		if i < _slot_colors.size():
			old = str(_slot_colors[i])
		var next := str(colors[i])
		var old_dir: Vector2i = _slot_dirs[i] if i < _slot_dirs.size() else Vector2i.ZERO
		if old == next and old_dir == dirs[i]:
			continue
		if next == NONE or next == "":
			_remove(i)
			continue
		_ensure(i, next)
		_pop(i)
	for i in range(colors.size(), _slot_colors.size()):
		_remove(i)
	_slot_colors = colors
	_slot_dirs = dirs
	_layout()


func icon_count() -> int:
	return _icons.size()


func pop_count() -> int:
	return _pops


func _read_colors(unit) -> Array:
	var out: Array = []
	if unit == null:
		return out
	for raw in unit.weaknesses:
		out.append(str(raw))
	return out


func _read_dirs(unit) -> Array:
	var out: Array = []
	for i in range(unit.weaknesses.size()):
		out.append(unit.weak_dirs[i] if i < unit.weak_dirs.size() else Vector2i.ZERO)
	return out


func _ensure(slot: int, color: String) -> void:
	if _icons.has(slot):
		var entry = _icons[slot]
		entry["color"] = color
		var existing: Sprite3D = entry["node"]
		if is_instance_valid(existing):
			existing.texture = _texture(color)
		_ensure_wedge(slot, color)
		return
	var texture := _texture(color)
	var sprite := Sprite3D.new()
	sprite.name = "WeakIcon_%d" % slot
	sprite.centered = true
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.transparent = true
	sprite.no_depth_test = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var size := texture.get_size()
	sprite.pixel_size = ICON_HEIGHT / maxf(1.0, size.y)
	add_child(sprite)
	_icons[slot] = {"node": sprite, "color": color}
	_ensure_wedge(slot, color)


# 地面扇形标记：贴在该方向的格边，颜色 = 弱点能量色，随时间脉动，站到这一侧攻击才算命中。
func _ensure_wedge(slot: int, color: String) -> void:
	var base: Color = FALLBACK_COLORS.get(color, Color(0.85, 0.75, 0.45))
	var tint := Color(base.r * 1.9, base.g * 1.9, base.b * 1.9, 1.0)
	if _wedges.has(slot):
		(_wedges[slot] as Sprite3D).modulate = tint
		return
	var wedge := Sprite3D.new()
	wedge.name = "WeakWedge_%d" % slot
	wedge.texture = _wedge()
	wedge.axis = Vector3.AXIS_Y
	wedge.pixel_size = WEDGE_SIZE / float(WEDGE_TEX)
	wedge.shaded = false
	wedge.transparent = true
	wedge.double_sided = true
	wedge.no_depth_test = true
	wedge.render_priority = 20
	wedge.modulate = tint
	wedge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wedge)
	_wedges[slot] = wedge
	# 白色细芯：在蓝色移动格上也一眼能看到。
	var core := Sprite3D.new()
	core.name = "Core"
	core.texture = _wedge(true)
	core.axis = Vector3.AXIS_Y
	core.pixel_size = wedge.pixel_size
	core.shaded = false
	core.transparent = true
	core.no_depth_test = true
	core.render_priority = 21
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wedge.add_child(core)


static func _wedge(thin: bool = false) -> Texture2D:
	if thin and _core_texture != null:
		return _core_texture
	if not thin and _wedge_texture != null:
		return _wedge_texture
	var image := Image.create_empty(WEDGE_TEX, WEDGE_TEX, false, Image.FORMAT_RGBA8)
	var c := float(WEDGE_TEX) * 0.5
	for y in range(WEDGE_TEX):
		for x in range(WEDGE_TEX):
			var dx := float(x) + 0.5 - c
			var dy := float(y) + 0.5 - c
			var r := sqrt(dx * dx + dy * dy)
			# 向上（贴图 -y 方向）±60° 的弧带，半径 38..56，外加柔和光晕。
			var angle := absf(atan2(dx, -dy))
			var half := 5.0 if thin else 14.0
			var band := 1.0 - clampf(absf(r - 47.0) / half, 0.0, 1.0)
			var glow := 0.0 if thin else 1.0 - clampf(absf(r - 47.0) / 22.0, 0.0, 1.0)
			var arc := 1.0 - clampf((angle - 1.1) / 0.35, 0.0, 1.0)
			var alpha := clampf((band + glow * 0.5) * arc, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var made := ImageTexture.create_from_image(image)
	if thin:
		_core_texture = made
	else:
		_wedge_texture = made
	return made


func _process(delta: float) -> void:
	_time += delta
	for raw in _wedges.values():
		var wedge: Sprite3D = raw
		if is_instance_valid(wedge):
			wedge.modulate.a = 0.88 + 0.12 * sin(_time * PULSE_SPEED)


func _texture(color: String) -> Texture2D:
	var texture: Texture2D = UI.texture_for("weak_" + color)
	if texture != null:
		return texture
	return _fallback_texture(color)


# 缺素材时的回退：用同色圆点贴图，保证图标仍可见。
static func _fallback_texture(color: String) -> Texture2D:
	if _fallback_textures.has(color):
		return _fallback_textures[color]
	var tint: Color = FALLBACK_COLORS.get(color, Color(0.85, 0.75, 0.45))
	var image := Image.create_empty(
		FALLBACK_TEXTURE_SIZE, FALLBACK_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(FALLBACK_TEXTURE_SIZE, FALLBACK_TEXTURE_SIZE) * 0.5
	var radius := float(FALLBACK_TEXTURE_SIZE) * 0.5 - 3.0
	for y in range(FALLBACK_TEXTURE_SIZE):
		for x in range(FALLBACK_TEXTURE_SIZE):
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance := point.distance_to(center)
			var alpha := clampf((radius - distance) / 3.0, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var shade := 0.55 if distance > radius - 6.0 else 1.0
			image.set_pixel(x, y, Color(
				tint.r * shade, tint.g * shade, tint.b * shade, alpha))
	var texture := ImageTexture.create_from_image(image)
	_fallback_textures[color] = texture
	return texture


func _pop(slot: int) -> void:
	_pops += 1
	var entry = _icons.get(slot, {})
	var node: Sprite3D = entry.get("node", null)
	if node == null or not is_instance_valid(node):
		return
	_kill_tween(entry, "tween")
	_kill_tween(entry, "glow")
	if not is_inside_tree():
		node.scale = Vector3.ONE
		node.modulate = Color.WHITE
		return
	node.scale = Vector3.ONE * 0.4
	node.modulate = Color.WHITE
	var tween := create_tween()
	entry["tween"] = tween
	var rise := tween.tween_property(
		node, "scale", Vector3.ONE * 1.35, POP_RISE)
	rise.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE, POP_SETTLE)
	var glow := create_tween()
	entry["glow"] = glow
	glow.tween_property(node, "modulate", GLOW_COLOR, GLOW_TIME * 0.3)
	glow.tween_property(node, "modulate", Color.WHITE, GLOW_TIME * 0.7)


func _kill_tween(entry: Dictionary, key: String) -> void:
	var tween = entry.get(key, null)
	if tween != null and tween is Tween and tween.is_valid():
		tween.kill()


func _remove(slot: int) -> void:
	var entry = _icons.get(slot, null)
	if entry == null:
		return
	_icons.erase(slot)
	if _wedges.has(slot):
		var old: Variant = _wedges[slot]
		_wedges.erase(slot)
		if is_instance_valid(old):
			if is_inside_tree():
				(old as Node).queue_free()
			else:
				(old as Node).free()
	var node: Sprite3D = entry.get("node", null)
	if node == null or not is_instance_valid(node):
		return
	_kill_tween(entry, "tween")
	_kill_tween(entry, "glow")
	if not is_inside_tree():
		if node.get_parent() == self:
			remove_child(node)
		node.free()
		return
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 0.0, FADE_TIME)
	tween.parallel().tween_property(
		node, "scale", Vector3.ONE * FADE_SCALE, FADE_TIME)
	tween.tween_callback(Callable(node, "queue_free"))


# 图标摆在敌人对应方向的相邻格一侧；没有方向的槽（旧数据）仍排在头顶。
func _layout() -> void:
	var slots: Array = _icons.keys()
	slots.sort()
	var step := ICON_HEIGHT + ICON_GAP
	var start := -float(slots.size() - 1) * step * 0.5
	for i in range(slots.size()):
		var slot: int = slots[i]
		var entry = _icons[slot]
		var node: Sprite3D = entry.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		var dir: Vector2i = _slot_dirs[slot] if slot < _slot_dirs.size() else Vector2i.ZERO
		if dir == Vector2i.ZERO:
			node.position = Vector3(start + step * float(i), 4.9, 0.0)
		else:
			node.position = Vector3(float(dir.x) * ICON_RING, ICON_Y, float(dir.y) * ICON_RING)
			var wedge: Variant = _wedges.get(slot, null)
			if wedge != null and is_instance_valid(wedge):
				(wedge as Sprite3D).position = Vector3(
					float(dir.x) * WEDGE_RING, 0.06, float(dir.y) * WEDGE_RING)
				(wedge as Sprite3D).rotation.y = atan2(-float(dir.x), -float(dir.y))
