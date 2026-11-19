extends RefCounted

const Facing = preload("res://core/tactics/facing.gd")
const StatsRules = preload("res://core/tactics/stats_rules.gd")
const TacticsEnergy = preload("res://core/tactics/tactics_energy.gd")

var id: String = ""
# 包装的 core/unit.gd 实例。
var unit: Variant = null
var side: String = "player"
var pos: Vector2i = Vector2i.ZERO
var facing: Vector2i = Facing.DOWN
# 玩家可用的武学 id。
var loadout: Array[String] = []
# 能量池：内力 / 紫气 / 仙气各自的剩余与上限（玩家方）。
var energy_left: Dictionary = {}
var energy_max: Dictionary = {}
var reactions_left: int = 0
var has_moved: bool = false
var has_acted: bool = false
# 弱点颜色槽（敌人）；"none" 表示中性槽，不可被命中。
var weaknesses: Array = []
var last_weak_color: String = ""
# 连续多少个自己的回合没有被弱点命中。
var no_weak_turns: int = 0
var empowered: bool = false


static func create(
	p_id: String,
	p_unit,
	p_side: String,
	p_pos: Vector2i,
	p_facing: Vector2i,
	p_loadout: Array = [],
	p_energy: Dictionary = {}
) -> RefCounted:
	var script: Variant = load("res://core/tactics/tactics_unit.gd")
	var out: Variant = script.new()
	out.id = p_id
	out.unit = p_unit
	out.side = p_side
	out.pos = p_pos
	if p_facing == Vector2i.ZERO:
		out.facing = Facing.DOWN if p_side == "player" else Facing.UP
	else:
		out.facing = p_facing
	var parsed_loadout: Array[String] = []
	for value in p_loadout:
		parsed_loadout.append(str(value))
	out.loadout = parsed_loadout
	if p_side == "player":
		out.energy_max = TacticsEnergy.initial_pools()
		out.energy_left = out.energy_max.duplicate()
		for raw_key in p_energy.keys():
			var key := str(raw_key)
			if out.energy_max.has(key):
				out.energy_max[key] = maxi(0, int(p_energy[raw_key]))
				out.energy_left[key] = maxi(0, int(p_energy[raw_key]))
	return out


func speed() -> int:
	return int(unit.stats.get("speed", 0))


func skill() -> int:
	return int(unit.stats.get("skill", 0))


func move_range() -> int:
	if side == "enemy" and unit.def != null and int(unit.def.move_override) >= 0:
		return int(unit.def.move_override)
	return StatsRules.move_range(speed())


func max_climb() -> int:
	return StatsRules.max_climb(skill())


func is_alive() -> bool:
	return unit != null and not unit.is_dead()


func start_turn() -> void:
	reactions_left = StatsRules.reaction_points(skill())
	has_moved = false
	has_acted = false


func has_energy(energy: String) -> bool:
	return energy_left.has(energy) and not TacticsEnergy.is_locked(energy)


func can_pay(energy: String, cost: int) -> bool:
	if not has_energy(energy):
		return false
	return int(energy_left.get(energy, 0)) >= maxi(0, cost)


func spend_energy(energy: String, cost: int) -> void:
	if energy_left.has(energy):
		energy_left[energy] = maxi(0, int(energy_left[energy]) - maxi(0, cost))
