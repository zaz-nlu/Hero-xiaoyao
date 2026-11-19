extends RefCounted

# 技能栏的横向几何：避开左下角单位卡，同时不越过窗口右边界。
# 1152 宽时单位卡右边缘约 316，技能栏左边缘至少 324。

const BAR_LEFT_MIN := 324.0
const BAR_SHIFT_PX := 80.0
const RIGHT_MARGIN_PX := 8.0


static func bar_shift(bar_width: float, panel_width: float) -> float:
	var shift := BAR_LEFT_MIN + bar_width * 0.5 - panel_width * 0.5
	shift = maxf(shift, BAR_SHIFT_PX)
	var max_shift := panel_width - RIGHT_MARGIN_PX - bar_width * 0.5 - panel_width * 0.5
	return minf(shift, maxf(BAR_SHIFT_PX, max_shift))


static func bar_rect(bar_size: Vector2, panel_size: Vector2) -> Rect2:
	var shift := bar_shift(bar_size.x, panel_size.x)
	var center_x := panel_size.x * 0.5 + shift
	return Rect2(
		center_x - bar_size.x * 0.5,
		panel_size.y - RIGHT_MARGIN_PX - bar_size.y,
		bar_size.x,
		bar_size.y)


# 窗口变窄时先压缩按钮间距，0 为下限。
static func separation_for(
	panel_width: float,
	count: int,
	content_width: float,
	button_width: float,
	default_separation: int
) -> int:
	if count <= 1:
		return default_separation
	var available := panel_width - RIGHT_MARGIN_PX - BAR_LEFT_MIN - content_width
	var gaps := float(count - 1)
	var room := available - button_width * float(count)
	return clampi(int(floorf(room / gaps)), 0, default_separation)


static func fit_separation(
	box: HBoxContainer,
	style: StyleBox,
	panel_width: float,
	button_width: float,
	default_separation: int
) -> void:
	if box == null or box.get_child_count() <= 1:
		return
	var content := style.get_content_margin(SIDE_LEFT) \
			+ style.get_content_margin(SIDE_RIGHT)
	var sep := separation_for(
		panel_width, box.get_child_count(), content, button_width, default_separation)
	box.add_theme_constant_override("separation", sep)


static func place_center(center: CenterContainer, bar: Control, panel_width: float) -> void:
	if center == null or bar == null:
		return
	center.offset_left = bar_shift(bar.get_combined_minimum_size().x, panel_width) * 2.0


static func bar_rect_for(bar: Control, panel_size: Vector2) -> Rect2:
	if bar == null:
		return Rect2()
	return bar_rect(bar.get_combined_minimum_size(), panel_size)
