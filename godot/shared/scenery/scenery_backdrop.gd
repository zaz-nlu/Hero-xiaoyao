extends Node3D

# 纯呈现背景：把 shared 场景构建器、灯光/相机和可选环境演员组合成一个节点。
# 不 import 任何 feature，也不接触剧情、奖励、任务或玩家输入系统。
# BattleStage / TitleCinematic 通过 BackdropFactory 创建它。

const TownBackdropScene = preload("res://shared/scenery/town/town_backdrop_scene.gd")
const ForestBackdropScene = preload("res://shared/scenery/forest/forest_backdrop_scene.gd")
const TavernBackdropScene = preload("res://shared/scenery/tavern/tavern_backdrop_scene.gd")

const WORLDS: Array[String] = ["town", "forest", "tavern"]

var world: String = "town"
var camera: Camera3D = null
var arena_origin: Vector3 = Vector3.ZERO
var player: Node3D = null
var player_pos: Vector2 = Vector2.ZERO
var npc_nodes: Dictionary = {}
var furniture_nodes: Dictionary = {}
var skip_actors: bool = true
var force_state: String = "normal"
var input_blocked: bool = false
var bounds_rect: Rect2 = Rect2()
var data: Dictionary = {}

var _options: Dictionary = {}
var _scene: RefCounted = null
var _built: bool = false
var _cinematic: bool = false


func configure(world_id: String, options: Dictionary = {}) -> void:
	if _built:
		return
	world = world_id if WORLDS.has(world_id) else "town"
	_options = options.duplicate(true)
	skip_actors = bool(_options.get("skip_actors", true))
	force_state = str(_options.get("force_state", "normal"))
	if force_state == "":
		force_state = "normal"
	input_blocked = bool(_options.get("input_blocked", false))
	_cinematic = bool(_options.get("cinematic", false))


func _ready() -> void:
	build()


func _process(delta: float) -> void:
	advance(delta)


func build() -> void:
	if _built:
		return
	_built = true
	match world:
		"forest":
			_build_forest()
		"tavern":
			_build_tavern()
		_:
			_build_town()
	if _cinematic:
		prepare_cinematic()


func advance(delta: float) -> void:
	if _scene != null and _scene.has_method("advance"):
		_scene.call("advance", delta)


func set_state(new_state: String, animate: bool = false) -> void:
	force_state = new_state
	if _scene != null and _scene.has_method("apply_state"):
		_scene.call("apply_state", new_state, animate)


# Title 演出使用独立相机：隐藏背景里的玩家并让出场景相机。
# 背景不创建任务标记，因此这里不需要按节点名递归清理。
func prepare_cinematic() -> void:
	if player != null and is_instance_valid(player):
		player.visible = false
	if camera != null and is_instance_valid(camera):
		camera.current = false


# ---------------------------------------------------------------- worlds

func _build_town() -> void:
	var scene := TownBackdropScene.new()
	var options: Dictionary = _options.duplicate(true)
	options["skip_actors"] = skip_actors
	scene.build(self, options)
	_scene = scene
	camera = scene.camera
	arena_origin = scene.arena_origin
	player = scene.player
	player_pos = scene.player_pos
	npc_nodes = scene.npc_nodes
	bounds_rect = scene.bounds_rect
	data = scene.data


func _build_forest() -> void:
	var scene := ForestBackdropScene.new()
	scene.build(self, _options)
	_scene = scene
	camera = scene.camera
	arena_origin = scene.arena_origin
	player = null
	npc_nodes = {}
	bounds_rect = scene.bounds_rect
	data = scene.data


func _build_tavern() -> void:
	var scene := TavernBackdropScene.new()
	scene.build(self, _options)
	_scene = scene
	camera = scene.camera
	arena_origin = scene.arena_origin
	player = null
	npc_nodes = {}
	furniture_nodes = scene.furniture_nodes
	data = scene.data
	scene.apply_state(force_state, false)
