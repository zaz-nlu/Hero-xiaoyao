extends Control

# A row of glowing orbs (full) and hollow rings (empty), used for jianyi and foresight points.

const Hud = preload("res://ui/battle_hud_style.gd")

const ORB := 7.0
const GAP := 5.0

var color: Color = Hud.GOLD
var filled: int = 0
var total: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_pips(filled_count: int, total_count: int) -> void:
	filled = maxi(0, filled_count)
	total = maxi(0, total_count)
	custom_minimum_size = Vector2(
		maxf(0.0, total * (ORB * 2.0 + GAP) - GAP), ORB * 2.0 + 6.0
	)
	queue_redraw()


func _draw() -> void:
	var mid_y: float = maxf(size.y, custom_minimum_size.y) * 0.5
	for i in range(total):
		var c := Vector2(ORB + i * (ORB * 2.0 + GAP), mid_y)
		draw_circle(c, ORB + 1.5, Color(0.02, 0.015, 0.04, 0.9))
		if i < filled:
			draw_texture_rect(
				Hud.radial_glow(), Rect2(c - Vector2(ORB, ORB) * 2.2, Vector2(ORB, ORB) * 4.4),
				false, Color(color.r, color.g, color.b, 0.55)
			)
			draw_circle(c, ORB, color)
			draw_circle(c + Vector2(-2.0, -2.2), 2.3, Color(1.0, 1.0, 1.0, 0.6))
		else:
			draw_circle(c, ORB, Color(0.1, 0.08, 0.13, 1.0))
			draw_arc(c, ORB - 0.8, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.65), 1.5, true)
