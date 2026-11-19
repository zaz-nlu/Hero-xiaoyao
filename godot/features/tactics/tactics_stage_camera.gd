extends RefCounted

# 战棋 3D 舞台的相机取景：屏幕可用区域、相机距离、构图偏移与景深参数。
# tactics_stage 只持有相机节点，按这里的数学每帧摆位。
#
# 可用区域：顶部行动条（110 px）之下、底部技能条与单位卡（200 px）之上，
# 左右各留 8 px；不再为右侧日志留空，日志在左上且不拦截棋盘点击。

const CAM_PITCH_DEG := 50.0
const CAM_FOV := 28.0
const FOCUS_HEIGHT := 0.6
const FOLLOW_WEIGHT := 0.2

const UI_TOP_PX := 110.0
const UI_BOTTOM_PX := 200.0
const SCREEN_MARGIN_PX := 8.0
const FRAME_INSET := 1.0
# 留一点余量，避免画面边缘与取景区域正好相切。
const FIT_SAFETY := 1.06
const MIN_CAM_DISTANCE := 24.0


static func camera_direction() -> Vector3:
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	return Vector3(0.0, sin(pitch), cos(pitch)).normalized()


# 相机方向绕 Y 轴旋转 yaw_deg：0 保持默认取景，90/270 时从左右两侧看向棋盘。
static func direction_for_yaw(yaw_deg: float) -> Vector3:
	return camera_direction().rotated(Vector3.UP, deg_to_rad(yaw_deg))


static func initial_distance(board_w: float, board_d: float) -> float:
	return maxf(board_w, board_d) * 2.05 + 6.0


# 按视口与棋盘尺寸求取景。返回 {ok, distance, compose}；
# 可用区域过小时 ok=false，调用方保留自己的距离与构图。
# yaw_deg 只影响棋盘在屏幕上的宽深：旋转 90/270° 时宽深互换，过渡时连续插值。
static func framing(
	viewport_size: Vector2,
	board_w: float,
	board_d: float,
	wall_h: float,
	direction: Vector3,
	yaw_deg: float = 0.0
) -> Dictionary:
	var out := {"ok": false, "distance": MIN_CAM_DISTANCE, "compose": Vector3.ZERO}
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return out
	var left := SCREEN_MARGIN_PX
	var right := viewport_size.x - SCREEN_MARGIN_PX
	var top := UI_TOP_PX
	var bottom := viewport_size.y - UI_BOTTOM_PX
	if right - left < 64.0 or bottom - top < 64.0:
		return out
	var region_w := (right - left) * FRAME_INSET
	var region_h := (bottom - top) * FRAME_INSET
	var center := Vector2((left + right) * 0.5, (top + bottom) * 0.5)

	# 视角转到侧面时棋盘宽深互换；用 |cos|/|sin| 让过渡期间的取景距离连续变化。
	var c := absf(cos(deg_to_rad(yaw_deg)))
	var s := absf(sin(deg_to_rad(yaw_deg)))
	var shell_w := board_w * c + board_d * s + 1.0
	var shell_d := board_d * c + board_w * s + 2.4
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	var screen_h := shell_d * sin(pitch) + wall_h * 0.35 * cos(pitch)
	var tan_half := tan(deg_to_rad(CAM_FOV) * 0.5)
	var dist_h := screen_h * viewport_size.y / maxf(1.0, 2.0 * tan_half * region_h)
	var dist_w := shell_w * viewport_size.y / maxf(1.0, 2.0 * tan_half * region_w)
	var distance := maxf(MIN_CAM_DISTANCE, maxf(dist_h, dist_w) * FIT_SAFETY)

	# 把棋盘中心从屏幕中心搬到可用区域中心：相机沿自身右/上轴反向平移。
	var world_per_px := 2.0 * distance * tan_half / viewport_size.y
	var dx := center.x - viewport_size.x * 0.5
	var dy := center.y - viewport_size.y * 0.5
	var basis := Basis.looking_at(-direction, Vector3.UP)
	var compose := basis.x * (-dx * world_per_px) + basis.y * (dy * world_per_px)
	return {"ok": true, "distance": distance, "compose": compose}


static func camera_position(
	focus: Vector3, direction: Vector3, distance: float, compose: Vector3
) -> Vector3:
	return focus + direction * distance + compose


static func camera_target(focus: Vector3, compose: Vector3) -> Vector3:
	return focus + Vector3(0.0, -0.8, 0.0) + compose


static func dof_attributes(distance: float) -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = distance + 18.0
	attributes.dof_blur_far_transition = 24.0
	attributes.dof_blur_near_enabled = false
	attributes.dof_blur_near_distance = distance - 10.0
	attributes.dof_blur_near_transition = 8.0
	attributes.dof_blur_amount = 0.03
	return attributes
