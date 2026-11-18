extends Panel

# A Panel with a little extra dressing on top of its stylebox: a soft top sheen, an inner
# hairline and diamond studs at the corners. Set the stylebox as usual; call set_frame()
# when the border colour changes so the studs follow. Use OrnateBox when the panel should
# size itself to its content.

const Hud = preload("res://shared/ui/battle_hud_style.gd")

var frame_color: Color = Hud.GOLD
var studs: bool = true


func set_frame(color: Color) -> void:
	frame_color = color
	queue_redraw()


func _draw() -> void:
	Hud.draw_ornament(self, frame_color, studs)
