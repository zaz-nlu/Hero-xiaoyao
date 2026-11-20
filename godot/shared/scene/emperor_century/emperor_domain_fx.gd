extends RefCounted

# 帝王世纪：领域本体。负责 Phase 1 的光点聚集、Phase 2 的贴地金环展开、领域边界（常驻）、
# 淡薄的穹顶光幕，以及全程的金色颗粒。金环是贴地的真圆（贴在地面后随战场透视自然成椭圆），
# 不是屏幕上的 UI 圆圈；只消费传入的半径，有效格子由规则层决定。

const Gfx = preload("res://shared/scene/emperor_century/emperor_gfx.gd")

var host: Node3D = null
var config: RefCounted = null
var gfx: RefCounted = null
var origin: Vector3 = Vector3.ZERO
var radius: float = 7.0
var open: bool = false

var _ring_a: MeshInstance3D = null
var _ring_b: MeshInstance3D = null
var _wave: MeshInstance3D = null
var _boundary: MeshInstance3D = null
var _dome: MeshInstance3D = null
var _motes: Array = []
var _rng := RandomNumberGenerator.new()
var _boundary_level: float = 0.0
var _spawn_budget: float = 0.0


func setup(p_host: Node3D, p_config: RefCounted, p_gfx: RefCounted) -> void:
	host = p_host
	config = p_config
	gfx = p_gfx
	_rng.seed = int(config.i("seed")) + 11


func open_at(p_origin: Vector3, p_radius: float) -> void:
	cleanup()
	origin = p_origin
	radius = maxf(2.0, p_radius)
	open = true
	_ring_a = _flat(Gfx.role_texture(config, "ring_stages", 0))
	_ring_b = _flat(Gfx.role_texture(config, "ring_stages", 1))
	_wave = _flat(Gfx.ring_texture())
	_boundary = _flat(Gfx.ring_texture())
	var dome_tex: Texture2D = Gfx.role_texture(config, "dome")
	_dome = gfx.acquire(host, "billboard")
	Gfx.setup(_dome, dome_tex, Vector2.ONE)
	_dome.visible = false
	for node in [_ring_a, _ring_b, _wave, _boundary]:
		node.visible = false


func set_radius(p_radius: float) -> void:
	radius = maxf(2.0, p_radius)


func count() -> int:
	var n := _motes.size()
	for node in [_ring_a, _ring_b, _wave, _boundary, _dome]:
		if node != null:
			n += 1
	return n


# phase: opening / expansion / gravity / slash / settle / active / closing；u 为该阶段内 0..1。
func tick(delta: float, phase: String, u: float, time: float) -> void:
	if not open:
		return
	var unit: float = config.f("unit_width")
	var opacity: float = config.f("domain_opacity")
	var base_level: float = config.f("boundary_brightness") * opacity
	var ring_diameter := radius * 2.0
	_hide_art_rings()
	match phase:
		"opening":
			_boundary_level = 0.0
			_set_mote_target(12, "converge")
		"expansion":
			var eased := 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), 3.0)
			var current := lerpf(unit * 1.5, radius, eased)
			_show_art_ring(current * 2.0, clampf(u, 0.0, 1.0), opacity)
			_boundary_level = base_level * 1.6 * smoothstep(0.55, 1.0, u)
			_show_wave(u, ring_diameter)
			_show_dome(smoothstep(0.35, 1.0, u) * 0.32 * opacity)
			_set_mote_target(int(config.i("gravity_particle_count") * 0.6), "rise")
		"gravity":
			_boundary_level = lerpf(base_level * 1.6, base_level * 1.2, u)
			_show_dome((1.0 - smoothstep(0.0, 0.35, u)) * 0.32 * opacity)
			_set_mote_target(config.i("gravity_particle_count"), "fall")
		"slash":
			_boundary_level = base_level * 1.1
			_set_mote_target(int(config.i("gravity_particle_count") * 0.4), "fall")
		"settle":
			_boundary_level = lerpf(base_level * 1.1, base_level, u)
			_set_mote_target(int(config.i("gravity_particle_count") * 0.2), "rise")
		"active":
			_boundary_level = base_level * (0.92 + 0.08 * sin(time * 1.7))
			_set_mote_target(6, "rise")
		"closing":
			_boundary_level = base_level * (1.0 - clampf(u, 0.0, 1.0))
			_set_mote_target(0, "rise")
	_update_boundary(ring_diameter)
	_update_motes(delta, phase)


func cleanup() -> void:
	for mote in _motes:
		gfx.release(mote["node"])
	_motes.clear()
	for node in [_ring_a, _ring_b, _wave, _boundary, _dome]:
		if node != null:
			gfx.release(node)
	_ring_a = null
	_ring_b = null
	_wave = null
	_boundary = null
	_dome = null
	open = false
	_boundary_level = 0.0


# ---------------------------------------------------------------- 内部

func _flat(tex: Texture2D) -> MeshInstance3D:
	var node: MeshInstance3D = gfx.acquire(host, "flat")
	Gfx.setup(node, tex, Vector2.ONE)
	node.position = origin + Vector3(0.0, 0.05, 0.0)
	return node


func _hide_art_rings() -> void:
	if _ring_a != null:
		_ring_a.visible = false
	if _ring_b != null:
		_ring_b.visible = false
	if _wave != null:
		_wave.visible = false
	if _dome != null:
		_dome.visible = false


# 三张环素材按进度交叉淡入：细环 → 加粗 → 符文环。贴图本身是压扁的椭圆，这里拉成正方形贴地。
func _show_art_ring(diameter: float, u: float, opacity: float) -> void:
	var stage := u * 2.0
	var low := int(floor(stage))
	var blend := stage - float(low)
	for entry in [[_ring_a, mini(low, 2)], [_ring_b, mini(low + 1, 2)]]:
		var node: MeshInstance3D = entry[0]
		var tex: Texture2D = Gfx.role_texture(config, "ring_stages", int(entry[1]))
		Gfx.setup(node, tex, Vector2(diameter, diameter * 0.98))
		node.position = origin + Vector3(0.0, 0.05, 0.0)
	Gfx.set_alpha(_ring_a, (1.0 - blend) * opacity)
	Gfx.set_alpha(_ring_b, blend * opacity)
	if low >= 2:
		Gfx.set_alpha(_ring_a, opacity)
		_ring_b.visible = false


func _show_wave(u: float, diameter: float) -> void:
	if u < 0.8:
		return
	var w := (u - 0.8) / 0.2
	Gfx.setup(_wave, Gfx.ring_texture(), Vector2.ONE * diameter * lerpf(0.92, 1.12, w))
	Gfx.set_tint(_wave, Gfx.GOLD, (1.0 - w) * config.f("domain_opacity"))
	_wave.position = origin + Vector3(0.0, 0.07, 0.0)


func _show_dome(alpha: float) -> void:
	if alpha <= 0.002:
		return
	var tex: Texture2D = Gfx.role_texture(config, "dome")
	if tex == null:
		return
	var width := radius * 2.2
	var height := width * float(tex.get_height()) / float(tex.get_width())
	Gfx.setup(_dome, tex, Vector2(width, height))
	_dome.position = origin + Vector3(0.0, height * 0.5, 0.0)
	Gfx.set_alpha(_dome, alpha)


func _update_boundary(diameter: float) -> void:
	if _boundary == null:
		return
	if _boundary_level <= 0.003:
		_boundary.visible = false
		return
	Gfx.setup(_boundary, Gfx.ring_texture(), Vector2.ONE * diameter)
	Gfx.set_tint(_boundary, Gfx.GOLD, _boundary_level)
	_boundary.position = origin + Vector3(0.0, 0.04, 0.0)


var _mote_target: int = 0
var _mote_mode: String = "rise"


func _set_mote_target(count_value: int, mode: String) -> void:
	_mote_target = maxi(0, count_value)
	_mote_mode = mode


func _update_motes(delta: float, phase: String) -> void:
	if _motes.size() < _mote_target:
		_spawn_budget += delta * 24.0
		while _spawn_budget >= 1.0 and _motes.size() < _mote_target:
			_spawn_budget -= 1.0
			_spawn_mote()
	var kept: Array = []
	for mote in _motes:
		var node: MeshInstance3D = mote["node"]
		mote["age"] = float(mote["age"]) + delta
		var life: float = mote["life"]
		var t: float = float(mote["age"]) / life
		if t >= 1.0 or (_motes.size() > _mote_target + 4 and t > 0.5):
			gfx.release(node)
			continue
		var velocity: Vector3 = mote["vel"]
		if str(mote["mode"]) == "fall":
			velocity.y -= 7.0 * delta
			mote["vel"] = velocity
		node.position += velocity * delta
		if node.position.y < 0.05:
			node.position.y = 0.05
		var fade := sin(t * PI)
		Gfx.set_alpha(node, fade * 0.8 * config.f("gravity_visual_strength"))
		kept.append(mote)
	_motes = kept


func _spawn_mote() -> void:
	var node: MeshInstance3D = gfx.acquire(host, "billboard")
	var size := _rng.randf_range(0.07, 0.16)
	Gfx.setup(node, Gfx.dot_texture(), Vector2(size, size), Color(1.0, 0.85, 0.5, 0.0))
	var angle := _rng.randf() * TAU
	var vel := Vector3.ZERO
	var pos := origin
	var life := _rng.randf_range(0.9, 1.7)
	match _mote_mode:
		"converge":
			var ring := _rng.randf_range(1.2, 2.4)
			pos = origin + Vector3(cos(angle) * ring, _rng.randf_range(0.2, 1.8), sin(angle) * ring)
			var to_center := origin + Vector3(0.0, 1.0, 0.0) - pos
			vel = to_center / life
		"fall":
			var d := sqrt(_rng.randf()) * radius
			pos = origin + Vector3(cos(angle) * d, _rng.randf_range(1.5, 3.2), sin(angle) * d)
			vel = Vector3(0.0, -1.0, 0.0)
		_:
			var d2 := radius * _rng.randf_range(0.85, 1.0)
			pos = origin + Vector3(cos(angle) * d2, 0.1, sin(angle) * d2)
			vel = Vector3(0.0, _rng.randf_range(0.5, 1.2), 0.0)
	node.position = pos
	_motes.append({"node": node, "vel": vel, "age": 0.0, "life": life, "mode": _mote_mode})
