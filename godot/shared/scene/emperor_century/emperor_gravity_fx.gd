extends RefCounted

# 帝王世纪：重力统治。地面裂纹（贴地、逐阶段加深）、原本悬浮的石块被强行压向地面、
# 重力冲击的光柱与碎裂，以及单位的“视觉受压”。
# 受压只改显示层（角色的 Sprite 子节点的位置/缩放/颜色），不碰单位的真实 position、
# 寻路坐标和碰撞；关闭或清理时全部还原。

const Gfx = preload("res://shared/scene/emperor_century/emperor_gfx.gd")

var host: Node3D = null
var config: RefCounted = null
var gfx: RefCounted = null
var origin: Vector3 = Vector3.ZERO

var _cracks: Array = []   # {node, pos}
var _rocks: Array = []    # {node, vel, age, delay, landed, size}
var _bursts: Array = []   # {node, age, life, kind}
var _pressed: Dictionary = {}   # visual -> {pos, scale, tint}
var _rng := RandomNumberGenerator.new()
var _impact_done: bool = false
var _press_level: float = 0.0


func setup(p_host: Node3D, p_config: RefCounted, p_gfx: RefCounted) -> void:
	host = p_host
	config = p_config
	gfx = p_gfx
	_rng.seed = int(config.i("seed")) + 29


func begin(p_origin: Vector3, ground_points: Array) -> void:
	cleanup()
	origin = p_origin
	_impact_done = false
	for point in ground_points:
		var pos: Vector3 = point
		var node: MeshInstance3D = gfx.acquire(host, "flat")
		Gfx.setup(node, Gfx.role_texture(config, "cracks", 0), Vector2.ONE * 3.4, Color(1.0, 1.0, 1.0, 0.0))
		node.position = Vector3(pos.x, 0.03, pos.z)
		node.rotation.y = _rng.randf() * TAU
		_cracks.append({"node": node, "pos": pos})


func count() -> int:
	return _cracks.size() + _rocks.size() + _bursts.size()


func pressed_count() -> int:
	return _pressed.size()


# u：重力阶段内进度 0..1；strength：已进入的受压强度（0..1，常驻阶段保持约 0.6）。
func tick(delta: float, phase: String, u: float, targets: Array) -> void:
	var strength: float = config.f("gravity_visual_strength")
	if phase == "gravity":
		_run_gravity(delta, u, strength)
		_press_level = smoothstep(0.1, 0.8, u)
	elif phase == "slash":
		_press_level = 1.0
	elif phase == "settle":
		_press_level = lerpf(1.0, 0.6, u)
	elif phase == "active":
		_press_level = 0.6
	elif phase == "closing":
		_press_level = maxf(0.0, _press_level - delta * 1.2)
	_apply_press(targets, _press_level)
	_update_rocks(delta)
	_update_bursts(delta)
	var crack_alpha := 0.0
	var crack_u := 0.0
	match phase:
		"gravity":
			crack_alpha = smoothstep(0.0, 0.25, u)
			crack_u = u
		"slash", "settle":
			crack_alpha = 0.9
			crack_u = 1.0
		"active":
			crack_alpha = 0.55
			crack_u = 1.0
		"closing":
			crack_alpha = 0.55 * maxf(0.0, _press_level)
			crack_u = 1.0
	_update_cracks(crack_u, crack_alpha * strength)


func cleanup() -> void:
	for crack in _cracks:
		gfx.release(crack["node"])
	_cracks.clear()
	for rock in _rocks:
		gfx.release(rock["node"])
	_rocks.clear()
	for burst in _bursts:
		gfx.release(burst["node"])
	_bursts.clear()
	_restore_pressed()
	_impact_done = false
	_press_level = 0.0


# ---------------------------------------------------------------- 内部

func _update_cracks(u: float, alpha: float) -> void:
	var files := Gfx.role_files(config, "cracks")
	if files.is_empty():
		return
	var index := clampi(int(u * float(files.size())), 0, files.size() - 1)
	var tex: Texture2D = Gfx.texture(str(files[index]))
	for crack in _cracks:
		var node: MeshInstance3D = crack["node"]
		(node.material_override as StandardMaterial3D).albedo_texture = tex
		Gfx.set_alpha(node, alpha)
		node.visible = alpha > 0.01


func _run_gravity(_delta: float, u: float, strength: float) -> void:
	if _impact_done or u < 0.05:
		return
	_impact_done = true
	# 重力冲击：光柱 + 碎裂各一次，随后原本“悬浮”的石块被压下。
	_spawn_burst(Gfx.role_texture(config, "impact_pillar"), origin, 5.2, 0.55, 0.5 * strength)
	_spawn_burst(Gfx.role_texture(config, "impact_burst", 0), origin + Vector3(0, 0, 0.02), 6.0, 0.7, 0.75 * strength)
	var files := Gfx.role_files(config, "rocks")
	for n in range(config.i("rock_count")):
		if files.is_empty():
			break
		var node: MeshInstance3D = gfx.acquire(host, "billboard")
		var tex: Texture2D = Gfx.texture(str(files[_rng.randi_range(0, mini(files.size() - 1, 7))]))
		var size := _rng.randf_range(0.8, 1.7)
		var aspect := 1.0
		if tex != null:
			aspect = float(tex.get_width()) / float(maxf(1.0, float(tex.get_height())))
		Gfx.setup(node, tex, Vector2(size * aspect, size), Color(1.0, 0.95, 0.9, 0.0))
		(node.material_override as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		var angle := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * maxf(3.0, config.f("domain_radius") * 0.8)
		node.position = origin + Vector3(cos(angle) * d, _rng.randf_range(1.6, 3.8), sin(angle) * d)
		_rocks.append({"node": node, "vel": 0.0, "age": 0.0, "delay": _rng.randf_range(0.0, 0.5),
			"landed": false, "size": size})


func _update_rocks(delta: float) -> void:
	var kept: Array = []
	for rock in _rocks:
		var node: MeshInstance3D = rock["node"]
		rock["age"] = float(rock["age"]) + delta
		var age: float = rock["age"]
		var delay: float = rock["delay"]
		if age < delay:
			# 短暂悬停后才被压下：先淡入并微微上浮。
			Gfx.set_alpha(node, clampf(age / maxf(delay, 0.05), 0.0, 1.0))
			node.position.y += delta * 0.15
			kept.append(rock)
			continue
		if not bool(rock["landed"]):
			rock["vel"] = float(rock["vel"]) + 26.0 * delta
			node.position.y -= float(rock["vel"]) * delta
			Gfx.set_alpha(node, 1.0)
			if node.position.y <= 0.15 + float(rock["size"]) * 0.3:
				node.position.y = 0.15 + float(rock["size"]) * 0.3
				rock["landed"] = true
				rock["age"] = delay
				_spawn_burst(Gfx.role_texture(config, "star_rings", 1), node.position - Vector3(0, 0.1, 0),
					float(rock["size"]) * 2.4, 0.3, 0.5)
			kept.append(rock)
			continue
		var rest: float = age - delay
		Gfx.set_alpha(node, 1.0 - clampf(rest / 0.9, 0.0, 1.0))
		if rest >= 0.9:
			gfx.release(node)
			continue
		kept.append(rock)
	_rocks = kept


func _spawn_burst(tex: Texture2D, pos: Vector3, width: float, life: float, alpha: float) -> void:
	if tex == null:
		return
	var node: MeshInstance3D = gfx.acquire(host, "billboard")
	var height := width * float(tex.get_height()) / float(maxf(1.0, float(tex.get_width())))
	Gfx.setup(node, tex, Vector2(width, height), Color(1.0, 0.9, 0.7, alpha))
	node.position = pos + Vector3(0.0, height * 0.5, 0.0)
	_bursts.append({"node": node, "age": 0.0, "life": life, "alpha": alpha})


func _update_bursts(delta: float) -> void:
	var kept: Array = []
	for burst in _bursts:
		var node: MeshInstance3D = burst["node"]
		burst["age"] = float(burst["age"]) + delta
		var t: float = float(burst["age"]) / float(burst["life"])
		if t >= 1.0:
			gfx.release(node)
			continue
		Gfx.set_alpha(node, float(burst["alpha"]) * (1.0 - t * t))
		kept.append(burst)
	_bursts = kept


# 视觉受压：目标可以是角色节点（取其 "Sprite" 子节点）或任意 Node3D。
func _apply_press(targets: Array, level: float) -> void:
	var sink: float = config.f("press_sink") * config.f("gravity_visual_strength")
	for raw in targets:
		var target: Node3D = raw as Node3D
		if target == null or not is_instance_valid(target):
			continue
		var visual: Node3D = target.get_node_or_null("Sprite") as Node3D
		if visual == null:
			visual = target
		if not _pressed.has(visual):
			_pressed[visual] = {"pos": visual.position, "scale": visual.scale}
		var base: Dictionary = _pressed[visual]
		var base_pos: Vector3 = base["pos"]
		var base_scale: Vector3 = base["scale"]
		visual.position = base_pos - Vector3(0.0, sink * level, 0.0)
		visual.scale = Vector3(base_scale.x * (1.0 + 0.05 * level), base_scale.y * (1.0 - 0.08 * level), base_scale.z)


func _restore_pressed() -> void:
	for visual in _pressed.keys():
		if is_instance_valid(visual):
			var base: Dictionary = _pressed[visual]
			(visual as Node3D).position = base["pos"]
			(visual as Node3D).scale = base["scale"]
	_pressed.clear()
