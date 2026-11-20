extends Node3D

# 帝王世纪（Emperor Century）领域演出控制器。
#
# 生命周期：inactive → opening（约 8 秒的 5 个阶段）→ active（常驻领域）→ closing → inactive。
# 分层：
#   规则层（战斗系统）决定领域是否展开、哪些格子在领域内、谁被自动切割、持续几回合；
#   本控制器只做表现：open_domain / activate_domain / play_auto_cut / update_domain_cells /
#   close_domain / cleanup，以及 audio_event / camera_changed / hitstop 三类通知。
#   特效不决定任何数值，也不修改单位的真实坐标（受压只改显示层，关闭时还原）。
#
# 接入战斗：在舞台根节点下 add_child(控制器)，规则层事件到来时调用上面的方法；
# 摄像机由宿主处理 camera_changed(effect)（fov_scale / offset / shake / reset）。
# 时间由 advance(delta) 推进（auto_process 时自动用 _process，测试可手动步进）。

const EmperorConfig = preload("res://shared/scene/emperor_century/emperor_config.gd")
const Gfx = preload("res://shared/scene/emperor_century/emperor_gfx.gd")
const DomainFx = preload("res://shared/scene/emperor_century/emperor_domain_fx.gd")
const GravityFx = preload("res://shared/scene/emperor_century/emperor_gravity_fx.gd")
const AutoCutFx = preload("res://shared/scene/emperor_century/emperor_autocut_fx.gd")
const EnvironmentFx = preload("res://shared/scene/emperor_century/emperor_environment_fx.gd")

signal state_changed(state_name: String)
signal phase_changed(phase: String)
signal audio_event(id: String, position: Vector3)
signal camera_changed(effect: Dictionary)
signal hitstop(seconds: float)
signal opened
signal closed

enum State { INACTIVE, OPENING, ACTIVE, CLOSING }
const STATE_NAMES: Array[String] = ["inactive", "opening", "active", "closing"]

var state: int = State.INACTIVE
var phase: String = ""
var time: float = 0.0
var auto_process: bool = true
var speed: float = 1.0
var config: RefCounted = EmperorConfig.load_default()
var origin: Vector3 = Vector3.ZERO
var radius: float = 7.0
var targets: Array = []
var battle_driven: bool = false

var _gfx: RefCounted = Gfx.new()
var _domain: DomainFx = DomainFx.new()
var _gravity: GravityFx = GravityFx.new()
var _cut: AutoCutFx = AutoCutFx.new()
var _env: EnvironmentFx = EnvironmentFx.new()
var _only_phase: String = ""
var _end_time: float = 0.0
var _closing: float = 0.0
var _active_time: float = 0.0
var _fired: Dictionary = {}
var _cuts_planned: int = 0
var _decor_clock: float = 0.0
var _last_camera: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	if auto_process and state != State.INACTIVE:
		advance(delta * speed)


# ---------------------------------------------------------------- 对外接口

# origin: 领域中心（世界坐标）；affected_points: 领域内格子的世界坐标（由规则层给出，只用来
# 估算半径与放置裂纹）；options: 可含 radius / targets / battle_driven / only_phase / speed，
# 其余键按名字覆盖配置参数（如 domain_radius、screen_shake_strength）。
func open_domain(p_origin: Vector3, affected_points: Array = [], options: Dictionary = {}) -> void:
	cleanup()
	config = EmperorConfig.load_default()
	var overrides := options.duplicate()
	for key in ["radius", "targets", "battle_driven", "only_phase", "speed"]:
		overrides.erase(key)
	config.override(overrides)
	origin = p_origin
	targets = options.get("targets", []).duplicate()
	battle_driven = bool(options.get("battle_driven", false))
	speed = float(options.get("speed", config.f("cinematic_speed")))
	radius = _radius_from(affected_points, float(options.get("radius", config.f("domain_radius"))))
	_rng.seed = int(config.i("seed"))
	_setup_modules(affected_points)
	_only_phase = str(options.get("only_phase", ""))
	var bounds: Dictionary = config.phase_bounds()
	time = 0.0
	_end_time = config.total_duration()
	if _only_phase != "" and bounds.has(_only_phase):
		time = float((bounds[_only_phase] as Array)[0])
		_end_time = float((bounds[_only_phase] as Array)[1])
	_set_state(State.OPENING)
	advance(0.0)


# 跳过展开演出，直接进入常驻领域（读档、剧情中途接入时使用）。
func activate_domain() -> void:
	if state == State.INACTIVE:
		return
	time = config.total_duration()
	_only_phase = ""
	_finish_opening()


# 由规则层触发的自动切割：targets 可以是 Node3D 或世界坐标 Vector3。
# 返回是否已排队；领域未展开时忽略。
func play_auto_cut(cut_targets: Array, options: Dictionary = {}) -> bool:
	if state == State.INACTIVE or state == State.CLOSING:
		return false
	var gap := float(options.get("stagger", 0.14))
	var index := 0
	for raw in cut_targets:
		var pos := _position_of(raw)
		_cut.play_cut(pos, float(index) * gap, options)
		index += 1
	return index > 0


func update_domain_cells(affected_points: Array) -> void:
	if state == State.INACTIVE:
		return
	radius = _radius_from(affected_points, radius)
	_domain.set_radius(radius)


func set_targets(new_targets: Array) -> void:
	targets = new_targets.duplicate()


func close_domain() -> void:
	if state == State.INACTIVE or state == State.CLOSING:
		return
	_closing = 0.0
	_set_state(State.CLOSING)
	audio_event.emit("domain_close", origin)


# 立即清理：释放全部临时节点、还原受压单位、撤销镜头与压暗。可随时安全调用。
func cleanup() -> void:
	_cut.cleanup()
	_gravity.cleanup()
	_domain.cleanup()
	_env.cleanup()
	_gfx.clear()
	_fired.clear()
	_cuts_planned = 0
	_decor_clock = 0.0
	_active_time = 0.0
	time = 0.0
	phase = ""
	if state != State.INACTIVE:
		_set_state(State.INACTIVE)
		_emit_camera({"fov_scale": 1.0, "offset": Vector3.ZERO, "shake": Vector3.ZERO, "reset": true})


func set_speed(value: float) -> void:
	speed = clampf(value, 0.05, 4.0)


func state_name() -> String:
	return STATE_NAMES[state]


func current_phase() -> String:
	return phase


func vfx_node_count() -> int:
	return _domain.count() + _gravity.count() + _cut.count() + _env.node_count()


func pressed_count() -> int:
	return _gravity.pressed_count()


func total_duration() -> float:
	return config.total_duration()


# ---------------------------------------------------------------- 时间轴

func advance(delta: float) -> void:
	if state == State.INACTIVE:
		return
	if state == State.OPENING:
		time = minf(time + delta, _end_time)
		var bounds: Dictionary = config.phase_bounds()
		var phase_name := _phase_at(bounds, time)
		var u := _phase_progress(bounds, phase_name, time)
		_enter_phase(phase_name)
		_run_phase(delta, phase_name, u)
		if time >= _end_time:
			_finish_opening()
	elif state == State.ACTIVE:
		_active_time += delta
		_tick_modules(delta, "active", 0.0)
		_run_decor(delta)
		_update_env(1.0)
	elif state == State.CLOSING:
		_closing += delta / config.duration_of("closing")
		_tick_modules(delta, "closing", clampf(_closing, 0.0, 1.0))
		_env.set_level(self, config.f("dim_amount") * 0.6 * (1.0 - clampf(_closing, 0.0, 1.0)))
		if _closing >= 1.0:
			cleanup()
			closed.emit()
			return
	_cut.tick(delta)
	_emit_camera(_camera_effect())


# ---------------------------------------------------------------- 内部

func _setup_modules(points: Array) -> void:
	_domain.setup(self, config, _gfx)
	_gravity.setup(self, config, _gfx)
	_cut.setup(self, config, _gfx)
	_cut.event.connect(func(id: String, at: Vector3) -> void: audio_event.emit(id, at))
	_cut.hitstop.connect(func(seconds: float) -> void: hitstop.emit(seconds))
	_domain.open_at(origin, radius)
	var ground: Array = [origin]
	for raw in targets:
		ground.append(_position_of(raw))
	for point in points:
		if ground.size() >= 12:
			break
		ground.append(point)
	_gravity.begin(origin, ground)


func _phase_at(bounds: Dictionary, t: float) -> String:
	for phase_name in EmperorConfig.PHASES:
		if t < float((bounds[phase_name] as Array)[1]):
			return phase_name
	return "settle"


func _phase_progress(bounds: Dictionary, phase_name: String, t: float) -> float:
	var span: Array = bounds[phase_name]
	return clampf((t - float(span[0])) / maxf(0.001, float(span[1]) - float(span[0])), 0.0, 1.0)


func _enter_phase(phase_name: String) -> void:
	if phase_name == phase:
		return
	phase = phase_name
	phase_changed.emit(phase_name)
	if phase_name == "expansion":
		audio_event.emit("domain_open", origin)


func _run_phase(delta: float, phase_name: String, u: float) -> void:
	if phase_name == "opening" and u >= 0.66 and not _fired.has("hum"):
		_fired["hum"] = true
		audio_event.emit("domain_hum", origin)
	if phase_name == "gravity" and u >= 0.05 and not _fired.has("slam"):
		_fired["slam"] = true
		audio_event.emit("gravity_slam", origin)
	if phase_name == "slash" and not battle_driven:
		_plan_preview_cuts(u)
	_tick_modules(delta, phase_name, u)
	var dim: float = config.f("dim_amount")
	if phase_name == "opening":
		_update_env(smoothstep(0.0, 1.0, u))
	else:
		_update_env(1.0)
	if phase_name == "settle":
		_env.set_level(self, dim * lerpf(1.0, 0.6, u))


func _tick_modules(delta: float, phase_name: String, u: float) -> void:
	_domain.tick(delta, phase_name, u, time)
	_gravity.tick(delta, phase_name, u, targets)


func _update_env(factor: float) -> void:
	var dim: float = config.f("dim_amount")
	if state == State.ACTIVE:
		_env.set_level(self, dim * 0.6)
	else:
		_env.set_level(self, dim * factor)


# 预览/剧情模式：切割阶段内分散地出现 3～5 次，不同时发生。
func _plan_preview_cuts(u: float) -> void:
	var total: int = config.i("preview_cut_count")
	while _cuts_planned < total and u >= (float(_cuts_planned) + 0.2) / float(total + 1):
		var pos := _preview_cut_position(_cuts_planned)
		_cut.play_cut(pos, 0.0, {})
		_cuts_planned += 1


func _preview_cut_position(index: int) -> Vector3:
	if not targets.is_empty():
		return _position_of(targets[index % targets.size()])
	var angle := _rng.randf() * TAU
	var d := sqrt(_rng.randf()) * radius * 0.7
	return origin + Vector3(cos(angle) * d, 0.0, sin(angle) * d)


# 常驻阶段：非战斗驱动时偶尔出现纯装饰性的地面切痕（不指向任何目标）。
func _run_decor(delta: float) -> void:
	if battle_driven:
		return
	_decor_clock += delta
	var gap := 1.0 / maxf(0.2, config.f("auto_cut_visual_frequency") * 0.35)
	if _decor_clock >= gap:
		_decor_clock = 0.0
		var angle := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * radius * 0.8
		_cut.play_cut(origin + Vector3(cos(angle) * d, 0.0, sin(angle) * d), 0.0, {"layer": "ground", "length": 2.0})


func _finish_opening() -> void:
	_tick_modules(0.0, "active", 0.0)
	phase = "active"
	phase_changed.emit("active")
	_set_state(State.ACTIVE)
	_emit_camera({"fov_scale": 1.0, "offset": Vector3.ZERO, "shake": Vector3.ZERO, "reset": true})
	opened.emit()


func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(STATE_NAMES[new_state])


# 镜头：开场缓推，展开时小幅后拉，重力爆发一次短促低幅震动，切割阶段稳定，常驻恢复。
func _camera_effect() -> Dictionary:
	var zoom: float = config.f("camera_zoom_strength")
	var fov := 1.0
	var offset := Vector3.ZERO
	var shake := Vector3.ZERO
	var bounds: Dictionary = config.phase_bounds()
	if state == State.OPENING:
		var phase_name := _phase_at(bounds, time)
		var u := _phase_progress(bounds, phase_name, time)
		match phase_name:
			"opening":
				fov = 1.0 - 0.07 * zoom * smoothstep(0.0, 1.0, u)
			"expansion":
				fov = lerpf(1.0 - 0.07 * zoom, 1.0 + 0.03 * zoom, smoothstep(0.0, 1.0, u))
			"gravity":
				fov = lerpf(1.0 + 0.03 * zoom, 1.0, smoothstep(0.0, 1.0, u))
				if u < 0.3:
					var k: float = (1.0 - u / 0.3) * config.f("screen_shake_strength") * 0.08
					shake = Vector3(sin(time * 71.0) * k * 0.4, absf(sin(time * 53.0)) * -k, 0.0)
	return {"fov_scale": fov, "offset": offset, "shake": shake, "reset": false}


func _emit_camera(effect: Dictionary) -> void:
	if effect == _last_camera:
		return
	_last_camera = effect
	camera_changed.emit(effect)


func _radius_from(points: Array, fallback: float) -> float:
	if points.is_empty():
		return clampf(fallback, 3.0, 24.0)
	var far := 0.0
	for raw in points:
		var p := _position_of(raw)
		far = maxf(far, Vector2(p.x - origin.x, p.z - origin.z).length())
	return clampf(far + 1.2, 3.0, 24.0)


func _position_of(value: Variant) -> Vector3:
	if value is Node3D and is_instance_valid(value):
		return (value as Node3D).position
	if value is Vector3:
		return value
	return origin
