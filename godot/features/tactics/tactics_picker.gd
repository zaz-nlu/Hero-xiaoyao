extends RefCounted

# 屏幕坐标 → 棋盘格子。射线与每格顶面求交，取最近且落点在该格范围内的格子。
# 相机必须位于场景树内（project_ray_* 依赖 viewport）。


static func cell_at_screen(
	camera: Camera3D, screen_pos: Vector2, grid, tiles
) -> Vector2i:
	if camera == null or grid == null or tiles == null:
		return Vector2i(-1, -1)
	if not camera.is_inside_tree():
		return Vector2i(-1, -1)
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.00001:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_distance := INF
	var half := float(tiles.cell_size) * 0.5
	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			var cell := Vector2i(x, y)
			var plane_y := float(tiles.top_y(cell))
			var distance := (plane_y - origin.y) / direction.y
			if distance <= 0.0 or distance >= best_distance:
				continue
			var point := origin + direction * distance
			var center: Vector3 = tiles.cell_center(cell)
			if absf(point.x - center.x) > half:
				continue
			if absf(point.z - center.z) > half:
				continue
			best = cell
			best_distance = distance
	return best
