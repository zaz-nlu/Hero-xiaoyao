extends RefCounted

# 森林背景场景：地形/植被/地标/光照/相机。没有背景演员（NPC/玩家/宝箱）。
# 生成顺序与 ForestLayout 的 RNG 调用顺序保持不变。

const CAMERA_OFFSET := Vector3(0.0, 16.7, 37.5)
const LOOK_AHEAD := Vector3(0.0, 1.0, -4.0)
const CAMERA_FOV := 28.0

const ForestLayout = preload("res://shared/resources/forest_layout.gd")
const WorldCamera = preload("res://shared/scene/world_camera.gd")
const ForestArt = preload("res://shared/scenery/forest/forest_art.gd")
const ForestTerrain = preload("res://shared/scenery/forest/forest_terrain.gd")
const ForestVegetation = preload("res://shared/scenery/forest/forest_vegetation.gd")
const ForestLandmarks = preload("res://shared/scenery/forest/forest_landmarks.gd")
const ForestVisuals = preload("res://shared/scenery/forest/forest_visuals.gd")

var layout: ForestLayout = ForestLayout.new()
var camera: Camera3D = null

var _art: ForestArt = ForestArt.new()
var _terrain: ForestTerrain = ForestTerrain.new()
var _vegetation: ForestVegetation = ForestVegetation.new()
var _landmarks: ForestLandmarks = ForestLandmarks.new()
var _visuals: ForestVisuals = ForestVisuals.new()
var _focus: Vector3 = Vector3.ZERO
var _time: float = 0.0

var data: Dictionary:
	get:
		return layout.data
var bounds_rect: Rect2:
	get:
		return layout.bounds_rect
var arena_origin: Vector3:
	get:
		return layout.arena_origin


func build(parent: Node3D, _options: Dictionary) -> void:
	layout.load_data(ForestLayout.FOREST_PATH)
	layout.begin_generation()
	_terrain.build(parent, layout, _art)
	var vegetation_root: Node3D = _vegetation.build(parent, layout, _art)
	_landmarks.build(parent, layout, vegetation_root, _art)
	_visuals.build(parent, layout)
	camera = WorldCamera.build(parent, CAMERA_OFFSET, CAMERA_FOV)


func advance(delta: float) -> void:
	_time += delta
	_landmarks.update_camp_light(_time)
	_focus = WorldCamera.update(
		camera, null, _focus, CAMERA_OFFSET, LOOK_AHEAD, delta, _spawn_point()
	)


func _spawn_point() -> Vector3:
	var spawn := layout.spawn_point()
	return Vector3(spawn.x, 0.0, spawn.y)
