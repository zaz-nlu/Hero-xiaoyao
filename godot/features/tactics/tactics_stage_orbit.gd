extends RefCounted

# 战棋 3D 舞台的视角旋转状态：目标 yaw 以 90° 为步进累加，显示值按 smoothstep
# 在 TURN_TIME 内逼近目标。过渡期间继续接受新输入；落定后精确停在 90° 倍数。

const StageCamera = preload("res://features/tactics/tactics_stage_camera.gd")

const STEP_DEG := 90.0
const TURN_TIME := 0.25

var yaw_deg: float = 0.0
var target_deg: float = 0.0

var _from_deg: float = 0.0
var _elapsed: float = 0.0


func rotate(direction: int) -> void:
	if direction == 0:
		return
	_from_deg = yaw_deg
	_elapsed = 0.0
	target_deg += STEP_DEG * (1.0 if direction > 0 else -1.0)


# 推进过渡；返回 true 表示本帧 yaw 发生了变化（调用方需要重新取景）。
func advance(delta: float) -> bool:
	if is_settled():
		return false
	_elapsed += maxf(0.0, delta)
	var t := clampf(_elapsed / TURN_TIME, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	yaw_deg = lerpf(_from_deg, target_deg, eased)
	if t >= 1.0:
		yaw_deg = target_deg
	return true


func is_settled() -> bool:
	return yaw_deg == target_deg


# 无帧循环的场景（测试、未入树）直接落到目标。
func snap() -> void:
	yaw_deg = target_deg
	_elapsed = TURN_TIME


func reset() -> void:
	yaw_deg = 0.0
	target_deg = 0.0
	_from_deg = 0.0
	_elapsed = TURN_TIME


# 对外展示用：归一到 [0, 360)。
func current_yaw() -> float:
	return fposmod(yaw_deg, 360.0)


func direction() -> Vector3:
	return StageCamera.direction_for_yaw(yaw_deg)
