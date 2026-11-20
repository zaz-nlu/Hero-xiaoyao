extends RefCounted

# 帝王世纪：自动切割。理念是“先看到结果，再意识到攻击已经发生”：
#   0.00 s 目标附近出现一道极细的金线（亮度很低）
#   0.05 s 金线亮度骤升
#   0.10 s 金线消失，目标上留下一道暗金的切痕
#   0.16 s 切口火花与碎屑
#   0.24 s 延迟的切割声（audio_event "cut_hit"）
#   0.35 s 碎片与灰尘散去，切痕慢慢淡出
# 本模块只负责画面：伤害、命中目标由规则层决定，play_cut 的位置来自规则层给出的目标。
# 切线是手动朝向相机的细条（不会因视角变成一条面片），线宽与持续时间来自配置。

const Gfx = preload("res://shared/scene/emperor_century/emperor_gfx.gd")

signal event(id: String, position: Vector3)
signal hitstop(seconds: float)

var host: Node3D = null
var config: RefCounted = null
var gfx: RefCounted = null

var _jobs: Array = []
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
var _serial: int = 0


func setup(p_host: Node3D, p_config: RefCounted, p_gfx: RefCounted) -> void:
	host = p_host
	config = p_config
	gfx = p_gfx
	_rng.seed = int(config.i("seed")) + 47


func count() -> int:
	var n := 0
	for job in _jobs:
		n += (job["handles"] as Array).size()
	return n


func pending() -> int:
	return _jobs.size()


# 排队一次切割。stagger 让多目标错开出现（不允许同一帧全部出现）。
func play_cut(position: Vector3, delay: float = 0.0, options: Dictionary = {}) -> void:
	_serial += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.i("seed")) * 31 + _serial
	var layer := str(options.get("layer", ""))
	if layer == "":
		layer = ["front", "front", "back", "ground"][rng.randi_range(0, 3)]
	_jobs.append({
		"t0": _clock + maxf(0.0, delay), "pos": position, "layer": layer, "stage": 0,
		"angle": float(options.get("angle", rng.randf() * PI)),
		"length": float(options.get("length", rng.randf_range(2.4, 4.8))),
		"offset": Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.5, 1.5), rng.randf_range(-0.4, 0.4)),
		"arc": rng.randf() < config.f("arc_chance"),
		"handles": [],
	})


func tick(delta: float) -> void:
	_clock += delta
	var kept: Array = []
	var life: float = config.f("auto_cut_duration")
	for job in _jobs:
		var age: float = _clock - float(job["t0"])
		if age < 0.0:
			kept.append(job)
			continue
		_advance_job(job, age)
		if age >= life:
			for handle in job["handles"]:
				gfx.release(handle["node"])
			(job["handles"] as Array).clear()
			continue
		_fade_handles(job, age, life)
		kept.append(job)
	_jobs = kept


func cleanup() -> void:
	for job in _jobs:
		for handle in job["handles"]:
			gfx.release(handle["node"])
	_jobs.clear()
	_clock = 0.0


# ---------------------------------------------------------------- 内部

func _advance_job(job: Dictionary, age: float) -> void:
	var stage: int = job["stage"]
	var pos: Vector3 = job["pos"]
	var center: Vector3 = pos + (job["offset"] as Vector3)
	if stage == 0 and age >= 0.0:
		job["stage"] = 1
		var node := _line(center, float(job["angle"]), float(job["length"]), str(job["layer"]), 1.0)
		_track(job, node, "line", 0.35)
		event.emit("cut_start", center)
	if int(job["stage"]) == 1 and age >= 0.05:
		job["stage"] = 2
		for handle in job["handles"]:
			if handle["kind"] == "line":
				handle["alpha"] = 1.0 * config.f("slash_flash_strength")
				Gfx.set_alpha(handle["node"], minf(1.0, handle["alpha"]))
	if int(job["stage"]) == 2 and age >= 0.10:
		job["stage"] = 3
		_drop(job, "line")
		var scar := _line(center, float(job["angle"]), float(job["length"]) * 0.8, "ground" if job["layer"] == "ground" else str(job["layer"]), 0.45)
		(scar.material_override as StandardMaterial3D).albedo_color = Color(0.75, 0.55, 0.2, 0.5)
		_track(job, scar, "scar", 0.5)
		hitstop.emit(0.06)
	if int(job["stage"]) == 3 and age >= 0.16:
		job["stage"] = 4
		_spark(job, center)
	if int(job["stage"]) == 4 and age >= 0.24:
		job["stage"] = 5
		event.emit("cut_hit", center)


func _track(job: Dictionary, node: MeshInstance3D, kind: String, alpha: float) -> void:
	(job["handles"] as Array).append({"node": node, "kind": kind, "alpha": alpha})


func _drop(job: Dictionary, kind: String) -> void:
	var kept: Array = []
	for handle in job["handles"]:
		if handle["kind"] == kind:
			gfx.release(handle["node"])
		else:
			kept.append(handle)
	job["handles"] = kept


func _fade_handles(job: Dictionary, age: float, life: float) -> void:
	for handle in job["handles"]:
		var kind: String = handle["kind"]
		if kind == "scar":
			var t := clampf((age - 0.10) / maxf(0.05, life - 0.10), 0.0, 1.0)
			Gfx.set_alpha(handle["node"], 0.55 * (1.0 - t))
		elif kind == "spark":
			var s := clampf((age - 0.16) / 0.3, 0.0, 1.0)
			Gfx.set_alpha(handle["node"], (1.0 - s) * 0.9)
			var files := Gfx.role_files(config, "cut_sparks")
			if not files.is_empty():
				var tex: Texture2D = Gfx.texture(str(files[clampi(int(s * float(files.size())), 0, files.size() - 1)]))
				(handle["node"].material_override as StandardMaterial3D).albedo_texture = tex
		elif kind == "debris":
			var d := clampf((age - 0.16) / 0.35, 0.0, 1.0)
			Gfx.set_alpha(handle["node"], 0.8 * (1.0 - d))
			handle["node"].position += Vector3(handle["drift"]) * 0.016


func _spark(job: Dictionary, center: Vector3) -> void:
	var files := Gfx.role_files(config, "cut_sparks")
	if not files.is_empty():
		var tex: Texture2D = Gfx.texture(str(files[0]))
		var node: MeshInstance3D = gfx.acquire(host, "billboard")
		var width := 1.5
		var aspect := 1.3
		if tex != null:
			aspect = float(tex.get_height()) / float(maxf(1.0, float(tex.get_width())))
		Gfx.setup(node, tex, Vector2(width, width * aspect), Color(1.0, 0.9, 0.65, 0.9))
		node.position = center + Vector3(0.0, width * aspect * 0.4, 0.0)
		_track(job, node, "spark", 0.9)
	if job["arc"]:
		var arc_files := Gfx.role_files(config, "slash_arcs")
		if not arc_files.is_empty():
			var arc_tex: Texture2D = Gfx.texture(str(arc_files[arc_files.size() / 2]))
			var arc: MeshInstance3D = gfx.acquire(host, "billboard")
			Gfx.setup(arc, arc_tex, Vector2(1.6, 1.0), Color(1.0, 0.9, 0.6, 0.55))
			arc.position = center
			_track(job, arc, "scar", 0.4)
	for n in range(4):
		var chip: MeshInstance3D = gfx.acquire(host, "billboard")
		Gfx.setup(chip, Gfx.dot_texture(), Vector2.ONE * 0.12, Color(1.0, 0.85, 0.5, 0.8))
		chip.position = center
		var handle := {"node": chip, "kind": "debris", "alpha": 0.8,
			"drift": Vector3(_rng.randf_range(-3.0, 3.0), _rng.randf_range(0.5, 3.0), _rng.randf_range(-2.0, 2.0))}
		(job["handles"] as Array).append(handle)


# 在相机平面里画一条细线：朝向相机后绕视线轴转 angle，沿线方向拉长到 length。
func _line(center: Vector3, angle: float, length: float, layer: String, alpha: float) -> MeshInstance3D:
	var kind := "flat" if layer == "ground" else "ribbon"
	var node: MeshInstance3D = gfx.acquire(host, kind)
	var width: float = config.f("auto_cut_line_width")
	Gfx.setup(node, Gfx.line_texture(), Vector2(length, width * 3.0), Color(1.0, 0.9, 0.62, alpha))
	var material := node.material_override as StandardMaterial3D
	material.no_depth_test = layer != "back"
	if layer == "ground":
		node.position = Vector3(center.x, 0.06, center.z)
		node.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		node.rotate_y(angle)
		return node
	var camera: Camera3D = host.get_viewport().get_camera_3d() if host.is_inside_tree() else null
	if camera == null or not node.is_inside_tree():
		node.position = center
		node.rotation = Vector3(0.0, 0.0, angle)
		return node
	var basis: Basis = camera.global_transform.basis
	var world_pos: Vector3 = host.to_global(center)
	if layer == "back":
		world_pos -= basis.z * 0.4
	node.global_transform = Transform3D(basis.rotated(basis.z.normalized(), angle), world_pos)
	return node
