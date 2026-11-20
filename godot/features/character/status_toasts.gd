extends RefCounted

# 地图界面顶部居中的提示条：淡入、停留、淡出，最多同时 MAX 条。
# 由 status_overlay.gd 持有，只负责 toast 的创建与动画。

const Hud = preload("res://shared/ui/battle_hud_style.gd")

const MAX := 3
const FADE_IN := 0.15
const HOLD := 2.2
const FADE_OUT := 0.4

var box: VBoxContainer = null
var _toasts: Array = []


func build(parent: Node) -> void:
	box = VBoxContainer.new()
	box.name = "ToastBox"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = -260.0
	box.offset_right = 260.0
	box.offset_top = 8.0
	box.offset_bottom = 158.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)


func show_toast(text: String) -> void:
	while _toasts.size() >= MAX:
		_remove(0)
	var panel := PanelContainer.new()
	panel.name = "Toast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = Hud.panel_style(0.9, Hud.GOLD, 6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Hud.configure_label(label, 18, Hud.TEXT)
	panel.add_child(label)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	box.add_child(panel)
	_toasts.append({"node": panel, "t": 0.0})


func advance(delta: float) -> void:
	var i: int = _toasts.size() - 1
	while i >= 0:
		var record: Dictionary = _toasts[i]
		var t: float = float(record.get("t", 0.0)) + delta
		record["t"] = t
		if t >= FADE_IN + HOLD + FADE_OUT:
			_remove(i)
			i -= 1
			continue
		var alpha := 1.0
		if t < FADE_IN:
			alpha = t / FADE_IN
		elif t > FADE_IN + HOLD:
			alpha = 1.0 - (t - FADE_IN - HOLD) / FADE_OUT
		var node_value: Variant = record.get("node", null)
		if node_value is CanvasItem:
			var item: CanvasItem = node_value
			item.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
		i -= 1


func _remove(index: int) -> void:
	if index < 0 or index >= _toasts.size():
		return
	var record: Dictionary = _toasts[index]
	_toasts.remove_at(index)
	var node_value: Variant = record.get("node", null)
	if node_value is Node:
		var node: Node = node_value
		var parent: Node = node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.queue_free()
