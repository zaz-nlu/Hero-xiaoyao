extends ProgressBar

# A glossy HP bar: dark trough, two-tone fill with a highlight line and a pale "recent
# damage" trail that drains behind the real value after a hit.

const Hud = preload("res://ui/battle_hud_style.gd")

var fill_top: Color = Hud.HP_RED.lightened(0.18)
var fill_bottom: Color = Hud.HP_RED.darkened(0.25)
var trail_color: Color = Color(1.0, 0.86, 0.6, 0.9)

var _trail: float = -1.0
var _hold: float = 0.0
var _last_value: float = -1.0
var _last_max: float = -1.0


func _init() -> void:
	show_percentage = false
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("background", empty)
	add_theme_stylebox_override("fill", empty)


func set_colors(top: Color, bottom: Color) -> void:
	fill_top = top
	fill_bottom = bottom
	queue_redraw()


func _process(delta: float) -> void:
	if _trail < 0.0 or value > _trail or max_value != _last_max:
		_trail = value
		_hold = 0.0
	elif value < _trail:
		if value < _last_value:
			_hold = 0.45
		_hold -= delta
		if _hold <= 0.0:
			_trail = maxf(value, _trail - max_value * 0.4 * delta)
	if value != _last_value or max_value != _last_max or absf(_trail - value) > 0.001:
		queue_redraw()
	_last_value = value
	_last_max = max_value


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_style_box(Hud.bar_bg_style(), Rect2(0.0, 0.0, w, h))
	var inner := Rect2(2.0, 2.0, maxf(0.0, w - 4.0), maxf(0.0, h - 4.0))
	var denominator: float = maxf(1.0, max_value)
	var frac: float = clampf(value / denominator, 0.0, 1.0)
	var trail_frac: float = clampf(maxf(_trail, value) / denominator, 0.0, 1.0)
	if trail_frac > frac:
		draw_rect(
			Rect2(inner.position, Vector2(inner.size.x * trail_frac, inner.size.y)), trail_color
		)
	if frac > 0.0:
		var fw: float = inner.size.x * frac
		var half: float = inner.size.y * 0.5
		draw_rect(Rect2(inner.position, Vector2(fw, half)), fill_top)
		draw_rect(Rect2(inner.position + Vector2(0.0, half), Vector2(fw, inner.size.y - half)), fill_bottom)
		draw_line(
			inner.position + Vector2(0.0, 1.0),
			inner.position + Vector2(fw, 1.0),
			Color(1.0, 1.0, 1.0, 0.3), 1.0
		)
	if w > 90.0:
		for i in range(1, 4):
			var x: float = inner.position.x + inner.size.x * i / 4.0
			draw_line(
				Vector2(x, inner.position.y), Vector2(x, inner.end.y),
				Color(0.0, 0.0, 0.0, 0.28), 1.0
			)
