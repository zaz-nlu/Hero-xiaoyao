extends RefCounted

var id: String = ""
var name: String = ""
var is_player: bool = false
var stats: Dictionary = {}
var max_hp: int = 0
var hp: int = 0
var wound: int = 0
var toughness_max: int = 0
var toughness_left: float = 0.0
var stun_turns: int = 0
var stun_left: int = 0
var jianyi_max: int = 0
var jianyi_points: int = 0
var foresight_max: int = 0
var foresight_points: int = 0
var weak_moves: Array = []
var weak_revealed: bool = false
var def: Variant = null
var incorporeal: bool = false


static func make_player(name: String, stats: Dictionary, max_hp: int, jianyi_max: int, p_foresight_max: int = 0) -> Variant:
	var script: Variant = load("res://core/unit.gd")
	var u: Variant = script.new()
	u.id = "player"
	u.name = name
	u.is_player = true
	u.stats = stats
	u.max_hp = max_hp
	u.hp = max_hp
	u.jianyi_max = jianyi_max
	u.jianyi_points = jianyi_max
	u.foresight_max = p_foresight_max
	u.foresight_points = p_foresight_max
	return u


static func from_enemy(d) -> Variant:
	var script: Variant = load("res://core/unit.gd")
	var u: Variant = script.new()
	u.id = str(d.id)
	u.name = str(d.name)
	u.is_player = false
	u.stats = d.stats
	u.max_hp = int(d.max_hp)
	u.hp = u.max_hp
	u.toughness_max = int(d.toughness)
	u.toughness_left = float(d.toughness)
	u.stun_turns = int(d.stun_turns)
	u.weak_moves = d.weak_moves
	u.def = d
	u.incorporeal = bool(d.incorporeal)
	return u


func heal(amount: int) -> int:
	var cap: int = max_hp - wound
	if hp >= cap:
		return 0
	var healed: int = mini(amount, cap - hp)
	if healed <= 0:
		return 0
	hp += healed
	return healed


func take_damage(amount: int) -> void:
	hp -= amount


func take_wound(amount: int) -> void:
	hp -= amount
	wound += amount


func is_dead() -> bool:
	return hp <= 0


func is_stunned() -> bool:
	return stun_left > 0


func apply_toughness(cost: float) -> bool:
	if stun_left > 0:
		return false
	toughness_left -= cost
	if toughness_left <= 0.0:
		stun_left = stun_turns
		return true
	return false


func tick_stun() -> void:
	if stun_left <= 0:
		return
	stun_left -= 1
	if stun_left <= 0:
		toughness_left = float(toughness_max)


func probe() -> void:
	weak_revealed = true
