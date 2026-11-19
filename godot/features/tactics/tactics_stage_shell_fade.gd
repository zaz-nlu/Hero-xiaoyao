extends RefCounted

# 战旗 3D 舞台的外壳淡出：转到相机一侧的外壳墙（酒馆后墙/侧墙、森林外圈树）
# 会淡化隐藏，避免挡住棋盘。只处理棋盘外围的装饰壳；棋盘内部的 wall 格子
# 属于玩法的一部分，永远不参与。灯光不隐藏，避免整个舞台变暗。

const TacticsTheme = preload("res://features/tactics/tactics_theme.gd")

const NORMAL_META := "shell_normal"
const FADE_TIME := 0.2
const DOT_THRESHOLD := 0.35
# 初始视角保护：yaw 从 0° 转出的前 30° 内逐渐启用淡出，保证 yaw=0 的
# 画面与改造前完全一致（森林树环在近侧时也不会一开局就消失）。
const INITIAL_GUARD_DEG := 30.0

var _entries: Array = []


# 在外壳节点建好后调用：记录每个外壳节点的向外法线，并复制共享材质。
func setup(stage: Node3D, grid) -> void:
	_entries.clear()
	if stage == null or grid == null:
		return
	var root := _shell_root(stage)
	if root == null:
		return
	var half_w := float(grid.width) * TacticsTheme.CELL_SIZE * 0.5
	var half_d := float(grid.height) * TacticsTheme.CELL_SIZE * 0.5
	for child in root.get_children():
		if child is Sprite3D:
			_add_sprite(child as Sprite3D)
		elif child is MeshInstance3D:
			_add_mesh(child as MeshInstance3D, half_w, half_d)


# 每帧调用；camera_dir 是「棋盘中心 → 相机」。过渡与静止时都持续调用。
func update(camera_dir: Vector3, delta: float) -> void:
	var flat := Vector3(camera_dir.x, 0.0, camera_dir.z)
	if flat.length() < 0.001:
		return
	flat = flat.normalized()
	var gate := _initial_gate(flat)
	var step := maxf(0.0, delta) / FADE_TIME
	for entry in _entries:
		var node: Node3D = entry["node"]
		if node == null or not is_instance_valid(node):
			continue
		var normal: Vector3 = entry["normal"]
		var target := 1.0
		if flat.dot(normal) > DOT_THRESHOLD:
			target = 1.0 - gate
		var alpha: float = move_toward(float(entry["alpha"]), target, step)
		entry["alpha"] = alpha
		_apply(entry, alpha)


# 无帧循环（未入树/测试）时直接落到目标状态。
func snap(camera_dir: Vector3) -> void:
	update(camera_dir, FADE_TIME)


func _shell_root(stage: Node3D) -> Node3D:
	var tavern := stage.get_node_or_null("TavernShell")
	if tavern is Node3D:
		return tavern as Node3D
	var forest := stage.get_node_or_null("ForestRing")
	if forest is Node3D:
		return forest as Node3D
	return null


func _add_mesh(node: MeshInstance3D, half_w: float, half_d: float) -> void:
	var normal := _wall_normal(node.position, half_w, half_d)
	if normal == Vector3.ZERO:
		# 棋盘上方的吊灯、横梁等不属于外壳墙，保持原样。
		return
	node.set_meta(NORMAL_META, normal)
	var entry := {
		"node": node, "normal": normal, "alpha": 1.0, "sprite": false,
		"material": null, "base": Color.WHITE,
		"transparency": BaseMaterial3D.TRANSPARENCY_DISABLED,
	}
	var mat := node.material_override
	if mat is StandardMaterial3D:
		var fade_mat := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		node.material_override = fade_mat
		entry["material"] = fade_mat
		entry["base"] = fade_mat.albedo_color
		entry["transparency"] = fade_mat.transparency
	_entries.append(entry)


func _add_sprite(node: Sprite3D) -> void:
	var flat := Vector3(node.position.x, 0.0, node.position.z)
	if flat.length() < 0.001:
		return
	var normal := flat.normalized()
	node.set_meta(NORMAL_META, normal)
	_entries.append({
		"node": node, "normal": normal, "alpha": 1.0, "sprite": true,
		"modulate": node.modulate,
	})


# 墙体的向外法线：按节点相对棋盘中心的偏移判断属于哪一面。
# 两侧都在棋盘范围内的节点（棋盘正上方）不算外壳，返回零向量。
func _wall_normal(pos: Vector3, half_w: float, half_d: float) -> Vector3:
	var outside_x := absf(pos.x) - half_w
	var outside_z := absf(pos.z) - half_d
	if maxf(outside_x, outside_z) <= 0.0:
		return Vector3.ZERO
	if outside_x > outside_z:
		return Vector3(1.0 if pos.x > 0.0 else -1.0, 0.0, 0.0)
	return Vector3(0.0, 0.0, 1.0 if pos.z > 0.0 else -1.0)


func _initial_gate(flat: Vector3) -> float:
	var yaw := fposmod(rad_to_deg(atan2(flat.x, flat.z)), 360.0)
	var from_start := minf(yaw, 360.0 - yaw)
	return smoothstep(0.0, INITIAL_GUARD_DEG, from_start)


func _apply(entry: Dictionary, alpha: float) -> void:
	var node: Node3D = entry["node"]
	node.visible = alpha > 0.001
	if bool(entry["sprite"]):
		var sprite: Sprite3D = entry["node"]
		var color: Color = entry["modulate"]
		color.a = color.a * alpha
		sprite.modulate = color
		return
	var mat: StandardMaterial3D = entry["material"]
	if mat == null:
		return
	var base: Color = entry["base"]
	if alpha >= 0.999:
		mat.transparency = int(entry["transparency"])
		mat.albedo_color = base
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(base.r, base.g, base.b, base.a * alpha)
