extends PanelContainer

# Same dressing as OrnatePanel, but sizes itself to its children (the hotbar plate).

const Hud = preload("res://ui/battle_hud_style.gd")

var frame_color: Color = Hud.GOLD
var studs: bool = true


func set_frame(color: Color) -> void:
	frame_color = color
	queue_redraw()


func _draw() -> void:
	Hud.draw_ornament(self, frame_color, studs)
