extends Control

# 序幕战后演出（2D 舞台，由 opening_backdrop 的 "domain" 背景挂载）：
#   stage = "recover"：东方阳连续击倒东方云与索尔，二人倒地后瞬间复原，一次又一次；
#   stage = "domain" ：东方阳举剑展开「帝王世纪」——领域扩张、重力冲击、地裂、浮石，
#                      小人被压得下沉，帝王剑气不断切割，最后白光收场。
# 特效来自 assets/vfx/emperor_century_*_sequence.png（1×8 帧序列，叠加混合）。
# 时间完全由 advance(delta) 推进，测试可手动步进。

const ImageCache = preload("res://shared/resources/image_cache.gd")
const AssetPaths = preload("res://shared/resources/asset_paths.gd")

const VFX_DIR := "res://assets/vfx/"
const BG_PATH := "res://assets/scenery/bg_battle_dusk.png"
const FRAMES := 8
const GROUND := 0.8
const CYCLE := 2.6
const HIT_TINT := Color(1.6, 0.5, 0.5)
const REGEN_TINT := Color(1.5, 1.9, 1.5)
const GOLD_TINT := Color(1.5, 1.3, 0.9)
const SINK := 0.035

var stage_kind: String = "recover"
var elapsed: float = 0.0
var seconds: float = 8.0

var _world: Control = null
var _dim: ColorRect = null
var _flash: ColorRect = null
var _figures: Dictionary = {}
var _effects: Array = []
var _fired: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true


func build(backdrop: Dictionary, p_seconds: float) -> void:
	stage_kind = str(backdrop.get("stage", "recover"))
	seconds = maxf(p_seconds, 0.001)
	_rng.seed = 7
	_world = Control.new()
	_world.name = "World"
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_world)
	var bg := TextureRect.new()
	bg.name = "Sky"
	bg.texture = ImageCache.texture(BG_PATH)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.add_child(bg)
	var floor_rect := ColorRect.new()
	floor_rect.name = "Ground"
	floor_rect.color = Color(0.12, 0.08, 0.05, 0.86)
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.anchor_top = GROUND - 0.02
	floor_rect.anchor_right = 1.0
	floor_rect.anchor_bottom = 1.0
	_world.add_child(floor_rect)
	_figures = {
		"yang": _make_figure("dongfang_yang", 2, 0.30, 0.44),
		"yun": _make_figure("dongfang_yun", 3, 0.62, 0.44),
		"sol": _make_figure("sol_demon_king", 3, 0.78, 0.54),
	}
	_dim = _overlay(Color(0.0, 0.0, 0.0, 0.0))
	_flash = _overlay(Color(1.0, 0.96, 0.82, 0.0))
	_layout()


func advance(delta: float) -> void:
	elapsed += maxf(delta, 0.0)
	if _world == null:
		return
	if stage_kind == "domain":
		_run_domain()
	else:
		_run_recover()
	_advance_effects(delta)
	_layout()


func figure(id: String) -> Control:
	return _figures.get(id, {}).get("rect", null)


func effect_count() -> int:
	return _effects.size()


# ---------------------------------------------------------------- recover

func _run_recover() -> void:
	var cycle := int(elapsed / CYCLE)
	var p := fmod(elapsed, CYCLE) / CYCLE
	_fire("rc%d" % cycle, p >= 0.06, func() -> void:
		_spawn("slash_arc", _center("yun", 0.5), 0.34, 14.0, Color(1.4, 1.2, 0.8))
		_spawn("slash_arc", _center("sol", 0.5), 0.40, 14.0, Color(1.4, 1.2, 0.8)))
	var down := 0.0
	if p >= 0.1 and p < 0.55:
		down = clampf((p - 0.1) / 0.12, 0.0, 1.0)
	elif p >= 0.55 and p < 0.8:
		down = 1.0 - clampf((p - 0.55) / 0.22, 0.0, 1.0)
	var glow := p >= 0.55 and p < 0.82
	for id in ["yun", "sol"]:
		var fig: Dictionary = _figures[id]
		fig["fall"] = down
		var tint := Color.WHITE.lerp(Color(0.5, 0.5, 0.56), down)
		if p >= 0.1 and p < 0.2:
			tint = HIT_TINT
		if glow:
			tint = Color.WHITE.lerp(REGEN_TINT, 0.5 + 0.5 * sin(elapsed * 22.0))
		fig["tint"] = tint
	var yang: Dictionary = _figures["yang"]
	var lunge := 0.0
	if p < 0.3:
		lunge = 0.05 * sin(clampf(p / 0.3, 0.0, 1.0) * PI)
	yang["dx"] = lunge
	yang["dy"] = 0.0
	yang["tint"] = Color.WHITE


# ---------------------------------------------------------------- domain

func _run_domain() -> void:
	var t := elapsed
	_dim.color.a = clampf(t / 1.6, 0.0, 1.0) * 0.5
	var yang: Dictionary = _figures["yang"]
	var raise := clampf(t / 1.0, 0.0, 1.0)
	yang["scale"] = 1.0 + 0.12 * raise
	yang["tint"] = Color.WHITE.lerp(GOLD_TINT, 0.5 + 0.5 * sin(t * 6.0)) if t > 0.4 else Color.WHITE
	yang["dx"] = 0.0
	yang["dy"] = 0.0
	_fire("expand", t >= 1.0, func() -> void:
		_spawn("domain_expansion", _center("yang", 0.55), 1.5, 6.0, GOLD_TINT))
	_fire("impact", t >= 2.4, func() -> void:
		_spawn("gravity_impact", Vector2(size.x * 0.55, size.y * GROUND), 1.15, 9.0, Color.WHITE))
	_fire("cracks", t >= 2.7, func() -> void:
		for id in ["yun", "sol"]:
			_spawn("gravity_crack", Vector2(_center(id, 0.0).x, size.y * (GROUND + 0.03)), 0.55, 8.0, Color.WHITE)
			_spawn("gravity_floating_rocks", _center(id, 0.8), 0.6, 6.0, Color(1.2, 1.1, 1.0)))
	var press := clampf((t - 2.4) / 0.8, 0.0, 1.0)
	for id in ["yun", "sol"]:
		var fig: Dictionary = _figures[id]
		fig["dy"] = SINK * press
		fig["scale_y"] = 1.0 - 0.1 * press
		fig["dx"] = -0.05 * clampf(t / 1.5, 0.0, 1.0)
		fig["tint"] = Color.WHITE.lerp(Color(0.8, 0.72, 0.9), press)
	if t >= 3.4 and t < 6.8:
		var step := int((t - 3.4) / 0.4)
		_fire("cut%d" % step, true, func() -> void:
			var target: String = "yun" if step % 2 == 0 else "sol"
			var at := _center(target, 0.2 + 0.6 * _rng.randf())
			_spawn("auto_cut", at, 0.42, 14.0, Color(1.5, 1.3, 0.9))
			var fig: Dictionary = _figures[target]
			fig["tint"] = HIT_TINT)
	var shake := 0.0
	if t >= 2.4 and t < 6.8:
		shake = 5.0 * sin(t * 53.0)
	_world.position = Vector2(shake, shake * 0.6)
	var white := clampf((t - (seconds - 1.2)) / 1.0, 0.0, 1.0)
	_flash.color.a = white * white


# ---------------------------------------------------------------- figures

func _make_figure(sprite_id: String, row: int, x_frac: float, height_frac: float) -> Dictionary:
	var sheet: Texture2D = ImageCache.texture(AssetPaths.sprite_path(sprite_id))
	var rect := TextureRect.new()
	rect.name = "Fig_" + sprite_id
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sheet != null:
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(0.0, float(row) * sheet.get_height() / 4.0,
			sheet.get_width() / 5.0, sheet.get_height() / 4.0)
		rect.texture = frame
	_world.add_child(rect)
	return {"rect": rect, "x": x_frac, "h": height_frac, "dx": 0.0, "dy": 0.0,
		"fall": 0.0, "scale": 1.0, "scale_y": 1.0, "tint": Color.WHITE}


func _layout() -> void:
	for id in _figures.keys():
		var fig: Dictionary = _figures[id]
		var rect: TextureRect = fig["rect"]
		var h: float = size.y * float(fig["h"]) * float(fig["scale"])
		var w: float = h * 32.0 / 48.0
		rect.size = Vector2(w, h * float(fig["scale_y"]))
		rect.pivot_offset = Vector2(w * 0.5, rect.size.y)
		rect.rotation = float(fig["fall"]) * PI * 0.5
		rect.modulate = fig["tint"]
		var cx: float = size.x * (float(fig["x"]) + float(fig["dx"]))
		var base: float = size.y * (GROUND + float(fig["dy"]))
		rect.position = Vector2(cx - w * 0.5, base - rect.size.y)


func _center(id: String, up: float) -> Vector2:
	var fig: Dictionary = _figures[id]
	var h: float = size.y * float(fig["h"])
	return Vector2(size.x * (float(fig["x"]) + float(fig["dx"])), size.y * GROUND - h * up)


# ---------------------------------------------------------------- effects

# 特效图自带深色底：按亮度抠掉暗部，剩下的亮部做叠加混合，边缘不会露出方框。
static var _shader: Shader = null


static func _glow_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type canvas_item;
render_mode blend_add;
uniform vec3 tint = vec3(1.0);
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float lum = max(t.r, max(t.g, t.b));
	float k = smoothstep(0.32, 0.75, lum) * t.a;
	COLOR = vec4(t.rgb * tint * k, 1.0);
}
"""
	return _shader


# key 只触发一次：避免在 advance 的每一帧重复生成。
func _fire(key: String, ready: bool, action: Callable) -> void:
	if ready and not _fired.has(key):
		_fired[key] = true
		action.call()


func _spawn(sheet: String, center: Vector2, width_frac: float, fps: float, tint: Color) -> void:
	var texture: Texture2D = ImageCache.texture(VFX_DIR + "emperor_century_" + sheet + "_sequence.png")
	if texture == null or _world == null:
		return
	var cell_w: float = texture.get_width() / float(FRAMES)
	var cell_h: float = float(texture.get_height())
	var w: float = size.x * width_frac
	var h: float = w * cell_h / cell_w
	var rect := TextureRect.new()
	rect.name = "Vfx_" + sheet
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.size = Vector2(w, h)
	rect.position = center - Vector2(w * 0.5, h * 0.5)
	rect.modulate = tint
	var material := ShaderMaterial.new()
	material.shader = _glow_shader()
	material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	rect.material = material
	rect.modulate = Color.WHITE
	var frame := AtlasTexture.new()
	frame.atlas = texture
	frame.region = Rect2(0.0, 0.0, cell_w, cell_h)
	rect.texture = frame
	_world.add_child(rect)
	_effects.append({"rect": rect, "frame": frame, "w": cell_w, "h": cell_h, "age": 0.0, "fps": fps})


func _advance_effects(delta: float) -> void:
	var kept: Array = []
	for entry in _effects:
		var rect: TextureRect = entry["rect"]
		entry["age"] = float(entry["age"]) + delta
		var index := int(float(entry["age"]) * float(entry["fps"]))
		if index >= FRAMES:
			if is_instance_valid(rect):
				rect.get_parent().remove_child(rect)
				rect.free()
			continue
		var frame: AtlasTexture = entry["frame"]
		frame.region = Rect2(float(index) * float(entry["w"]), 0.0, float(entry["w"]), float(entry["h"]))
		kept.append(entry)
	_effects = kept


func _overlay(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	return rect
