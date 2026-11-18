extends RefCounted

# 创建纯呈现背景的工厂。world 决定场景模块；options 明确展示模式：
#   skip_actors: bool   —— true 时不建任何环境演员/玩家
#   force_state: String —— 酒馆初始静态家具状态（如 "brawl"）
#   input_blocked: bool —— 兼容旧调用方的标记，背景本身不读取输入
#   hide_player: bool   —— 小镇环境演员模式下隐藏玩家（仅用于 NPC 停步）
#   player_anchor: Vector2 —— 调用方显式给出的隐藏玩家锚点（否则用 data spawn）
#   picked_flag_provider: Callable —— 调用方的只读 flag 查询，决定 pickup 是否隐藏
#   skip_npc_ids: Array —— 调用方显式指定不显示的环境 NPC
# 返回值尚未 build；进入场景树时 _ready 会自动 build，未入树时调用方显式 build。

const SceneryBackdrop = preload("res://shared/scenery/scenery_backdrop.gd")


static func create(world: String, options: Dictionary = {}) -> Node3D:
	var backdrop: Node3D = SceneryBackdrop.new()
	backdrop.call("configure", world, options)
	return backdrop
