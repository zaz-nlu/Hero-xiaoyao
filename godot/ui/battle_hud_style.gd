extends RefCounted

# Shared visual language for the battle HUD: ink-coloured panels, dark-gold borders
# and the tints used by the health / jianyi / toughness / stun readouts.

const INK := Color(0.07, 0.06, 0.09)
const GOLD := Color(0.78, 0.65, 0.35)
const GOLD_BRIGHT := Color(1.0, 0.88, 0.52)
const TEXT := Color(0.95, 0.92, 0.85)
const MUTED := Color(0.68, 0.64, 0.57)
const HP_RED := Color(0.8, 0.2, 0.2)
const JIANYI_PURPLE := Color(0.62, 0.4, 0.95)
const FORESIGHT_CYAN := Color(0.3, 0.75, 0.8)
const TOUGH_GOLD := Color(0.95, 0.8, 0.35)
const STUN_BLUE := Color(0.6, 0.7, 1.0)
const WOUND_RED := Color(0.85, 0.32, 0.3)


static var _gradients: Dictionary = {}


static func ink(alpha: float = 0.88) -> Color:
	return Color(INK.r, INK.g, INK.b, alpha)


# ---- cached gradient textures used by the custom-drawn HUD controls

static func vertical_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var key := "v|%s|%s" % [top, bottom]
	if _gradients.has(key):
		var cached: GradientTexture2D = _gradients[key]
		return cached
	var gradient := Gradient.new()
	gradient.set_color(0, top)
	gradient.set_color(1, bottom)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 4
	texture.height = 64
	_gradients[key] = texture
	return texture


# White-ish orb glow, tint it with the modulate argument of draw_texture_rect.
static func radial_glow() -> GradientTexture2D:
	if _gradients.has("radial"):
		var cached: GradientTexture2D = _gradients["radial"]
		return cached
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_gradients["radial"] = texture
	return texture


# A line that is transparent at both ends and `color` in the middle.
static func vertical_fade_line(color: Color) -> GradientTexture2D:
	var key := "fade|%s" % color
	if _gradients.has(key):
		var cached: GradientTexture2D = _gradients[key]
		return cached
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, 0.0))
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	gradient.add_point(0.5, Color(color.r, color.g, color.b, 0.9))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 2
	texture.height = 64
	_gradients[key] = texture
	return texture


static func horizontal_fade_line(color: Color) -> GradientTexture2D:
	var key := "hfade|%s" % color
	if _gradients.has(key):
		var cached: GradientTexture2D = _gradients[key]
		return cached
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, 0.0))
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	gradient.add_point(0.5, Color(color.r, color.g, color.b, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.width = 128
	texture.height = 2
	_gradients[key] = texture
	return texture


# Small diamond studs on the four corners of `rect`.
static func draw_studs(item: CanvasItem, rect: Rect2, color: Color, size: float = 3.5) -> void:
	var corners: Array = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	for raw_corner in corners:
		var c: Vector2 = raw_corner
		var outer := size + 1.5
		item.draw_colored_polygon(
			PackedVector2Array([
				c + Vector2(0.0, -outer), c + Vector2(outer, 0.0),
				c + Vector2(0.0, outer), c + Vector2(-outer, 0.0),
			]),
			Color(0.03, 0.02, 0.04, 0.95)
		)
		item.draw_colored_polygon(
			PackedVector2Array([
				c + Vector2(0.0, -size), c + Vector2(size, 0.0),
				c + Vector2(0.0, size), c + Vector2(-size, 0.0),
			]),
			color
		)


# The extra dressing shared by OrnatePanel / OrnateBox: top sheen, inner hairline, studs.
static func draw_ornament(item: Control, color: Color, with_studs: bool = true) -> void:
	var w: float = item.size.x
	var h: float = item.size.y
	item.draw_texture_rect(
		vertical_gradient(Color(1.0, 1.0, 1.0, 0.08), Color(1.0, 1.0, 1.0, 0.0)),
		Rect2(2.0, 2.0, maxf(0.0, w - 4.0), maxf(0.0, h * 0.5)), false
	)
	item.draw_rect(
		Rect2(4.0, 4.0, maxf(0.0, w - 8.0), maxf(0.0, h - 8.0)),
		Color(color.r, color.g, color.b, 0.2), false, 1.0
	)
	if with_studs:
		draw_studs(item, Rect2(1.0, 1.0, w - 2.0, h - 2.0), color, 3.5)


# A heavier plate with a drop shadow: the character card and the hotbar.
static func plate_style(border: Color = GOLD) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.062, 0.09, 0.93)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 3.0)
	return style


static func panel_style(alpha: float = 0.88, border: Color = GOLD, radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ink(alpha)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style


# The bottom HUD strip: translucent ink with a thin gold line along its top edge.
static func hud_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ink(0.62)
	style.border_color = GOLD
	style.set_border_width_all(0)
	style.border_width_top = 2
	style.set_corner_radius_all(4)
	return style


static func card_style(alpha: float = 0.92, border: Color = GOLD) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.12, alpha)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style


static func card_hover_style() -> StyleBoxFlat:
	var style := card_style(0.96, GOLD_BRIGHT)
	style.bg_color = Color(0.16, 0.14, 0.19, 0.97)
	return style


static func card_pressed_style() -> StyleBoxFlat:
	var style := card_style(0.98, GOLD_BRIGHT)
	style.bg_color = Color(0.2, 0.17, 0.22, 1.0)
	return style


static func card_disabled_style() -> StyleBoxFlat:
	var style := card_style(0.62, Color(0.45, 0.39, 0.26, 0.7))
	style.bg_color = Color(0.05, 0.05, 0.07, 0.72)
	return style


static func bar_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.03, 0.75)
	style.border_color = Color(0.78, 0.65, 0.35, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style


static func bar_fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style


static func circle_style(color: Color, radius: int = 22) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.95, 0.92, 0.85, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style


static func bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ink(0.72)
	style.border_color = Color(0.78, 0.65, 0.35, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


# The little dark tag holding a key number or a verdict mark on a hotbar slot.
static func badge_style(border: Color = GOLD) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.02, 0.05, 0.94)
	style.border_color = Color(border.r, border.g, border.b, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


static func head_style(selected: bool, dead: bool) -> StyleBoxFlat:
	var border: Color = GOLD
	if selected:
		border = GOLD_BRIGHT
	if dead:
		border = Color(0.42, 0.39, 0.35, 0.65)
	var style := panel_style(0.92 if selected else 0.84, border, 6)
	if selected:
		style.set_border_width_all(3)
		style.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.42)
		style.shadow_size = 10
	return style


static func configure_label(label: Label, font_size: int, color: Color) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


# A martial's identity colour comes from the move type it counters.
static func move_type_color(type_id: String) -> Color:
	match type_id:
		"heavy":
			return Color(0.78, 0.34, 0.3)
		"thrust":
			return Color(0.88, 0.66, 0.32)
		"sweep":
			return Color(0.36, 0.68, 0.6)
		"combo":
			return Color(0.85, 0.52, 0.3)
		"charge":
			return Color(0.6, 0.42, 0.9)
		"ranged":
			return Color(0.4, 0.58, 0.88)
		_:
			return Color(0.52, 0.54, 0.62)
