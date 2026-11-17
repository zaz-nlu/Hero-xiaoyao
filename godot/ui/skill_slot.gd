extends Button

# A hotbar slot in the battle HUD: lacquered body, the painted martial icon with a soft
# glow behind it, a name plaque along the bottom and a gold frame with corner studs.
# The key number, verdict badge and name are Label children added by the battle view.

const Hud = preload("res://ui/battle_hud_style.gd")

var icon_texture: Texture2D = null
var accent: Color = Hud.GOLD
var frame_color: Color = Hud.GOLD
var glyph: String = ""

var _lift: float = 0.0
var _tween: Tween = null


func _init() -> void:
	flat = true
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	mouse_entered.connect(_on_hover.bind(1.0))
	mouse_exited.connect(_on_hover.bind(0.0))
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func setup(icon: Texture2D, accent_color: Color, frame: Color, glyph_text: String) -> void:
	icon_texture = icon
	accent = accent_color
	frame_color = frame
	glyph = glyph_text
	queue_redraw()


func _on_hover(target: float) -> void:
	if not is_inside_tree():
		_lift = target
		queue_redraw()
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_lift, _lift, target, 0.12)


func _set_lift(value: float) -> void:
	_lift = value
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var live: bool = not disabled
	var hot: bool = live and _lift > 0.01
	var rect := Rect2(0.0, 0.0, w, h)

	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.085, 0.07, 0.1, 0.97)
	body.set_corner_radius_all(6)
	draw_style_box(body, rect)

	# icon, lifted slightly while hovered
	var side: float = w - 14.0
	var icon_rect := Rect2(7.0, 7.0 - _lift * 3.0, side, side)
	if live:
		var glow_alpha: float = 0.3 + 0.4 * _lift
		draw_texture_rect(
			Hud.radial_glow(), icon_rect.grow(10.0), false,
			Color(accent.r, accent.g, accent.b, glow_alpha)
		)
	if icon_texture != null:
		draw_texture_rect(icon_texture, icon_rect.grow(_lift * 2.0), false)
	else:
		draw_circle(icon_rect.get_center(), side * 0.46, accent)
		var font: Font = get_theme_default_font()
		if font != null and glyph != "":
			draw_string(
				font, icon_rect.get_center() + Vector2(-12.0, 9.0), glyph,
				HORIZONTAL_ALIGNMENT_CENTER, 24.0, 26, Hud.TEXT
			)

	# name plaque
	var plaque := Rect2(4.0, h - 28.0, w - 8.0, 24.0)
	draw_rect(plaque, Color(0.02, 0.015, 0.03, 0.9))
	draw_line(
		plaque.position, Vector2(plaque.end.x, plaque.position.y),
		Color(frame_color.r, frame_color.g, frame_color.b, 0.6), 1.0
	)

	# hover glow rings
	if hot:
		for k in range(1, 4):
			var ring := StyleBoxFlat.new()
			ring.draw_center = false
			ring.border_color = Color(accent.r, accent.g, accent.b, 0.34 - 0.09 * k)
			ring.set_border_width_all(2)
			ring.set_corner_radius_all(6 + k * 2)
			draw_style_box(ring, rect.grow(k * 2.0))

	# frame
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.border_color = Hud.GOLD_BRIGHT if hot else frame_color
	border.set_border_width_all(3 if is_pressed() else 2)
	border.set_corner_radius_all(6)
	draw_style_box(border, rect)
	draw_rect(
		Rect2(3.0, 3.0, w - 6.0, h - 6.0),
		Color(frame_color.r, frame_color.g, frame_color.b, 0.22), false, 1.0
	)
	Hud.draw_studs(self, rect.grow(-1.0), Hud.GOLD_BRIGHT if hot else frame_color, 3.0)

	if is_pressed() and live:
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.12))
