extends Control

# A thin vertical gold line fading at both ends with a small diamond in the middle.

const Hud = preload("res://shared/ui/battle_hud_style.gd")


func _init() -> void:
	custom_minimum_size = Vector2(18.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var x: float = size.x * 0.5
	draw_texture_rect(
		Hud.vertical_fade_line(Hud.GOLD), Rect2(x - 1.0, 4.0, 2.0, maxf(0.0, size.y - 8.0)), false
	)
	var c := Vector2(x, size.y * 0.5)
	var d := 5.0
	draw_colored_polygon(
		PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]),
		Hud.GOLD
	)
	var e := 2.5
	draw_colored_polygon(
		PackedVector2Array([c + Vector2(0, -e), c + Vector2(e, 0), c + Vector2(0, e), c + Vector2(-e, 0)]),
		Color(0.07, 0.06, 0.09)
	)
