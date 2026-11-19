extends Control

# 战棋灰盒独立入口（不接入 app/game.gd）：
#   godot --path godot res://features/tactics/tactics_sandbox.tscn
# 鼠标：点格子移动/选择目标；底部按钮选择动作。
# 键盘：1-9 选武学，M 移动，J 剑意，空格待机/结束回合，A 交给 bot 代打，R 重来，
# Q/E 旋转 3D 视角。

const TacticsView = preload("res://features/tactics/tactics_view.gd")

var view: Variant = null


func _ready() -> void:
	view = TacticsView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.start()
	view._player_input.announce_view_controls()
