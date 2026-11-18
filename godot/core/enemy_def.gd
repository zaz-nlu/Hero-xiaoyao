extends RefCounted

const Stats = preload("res://core/stats.gd")
const Pattern = preload("res://core/tactics/pattern.gd")

var id: String = ""
var name: String = ""
var sprite: String = ""
var tier: String = ""
var realm: String = "lianti"
var exp: int = 0
var stats: Dictionary = {}
var max_hp: int = 0
var toughness: int = 0
var stun_turns: int = 0
var moves: Array = []
var weak_moves: Array[String] = []
var incorporeal: bool = false
var ai: String = "rush"
var move_override: int = -1


static func from_dict(d: Dictionary) -> RefCounted:
	var script: Variant = load("res://core/enemy_def.gd")
	var e: Variant = script.new()
	e.id = str(d.get("id", ""))
	e.name = str(d.get("name", ""))
	e.sprite = str(d.get("sprite", e.id))
	e.tier = str(d.get("tier", ""))
	e.realm = str(d.get("realm", "lianti"))
	e.exp = maxi(0, int(d.get("exp", 0)))
	e.stats = _int_stats(d.get("stats", {}))
	e.max_hp = int(d.get("max_hp", 0))
	e.toughness = int(d.get("toughness", 0))
	e.stun_turns = int(d.get("stun_turns", 0))
	e.ai = str(d.get("ai", "rush"))
	e.move_override = int(d.get("move", -1))

	var parsed_moves: Array = []
	var raw_moves = d.get("moves", [])
	if raw_moves is Array:
		for raw in raw_moves:
			if raw is Dictionary:
				var move_type := str(raw.get("type", ""))
				var raw_range = raw.get("range", null)
				var move_range := {}
				if raw_range is Dictionary:
					move_range = Pattern.normalize(raw_range)
				elif move_type == "ranged":
					move_range = Pattern.normalize({"shape": "ranged", "min": 2, "max": 4})
				else:
					move_range = Pattern.normalize({})
				parsed_moves.append({
					"id": str(raw.get("id", "")),
					"name": str(raw.get("name", "")),
					"type": move_type,
					"threat": int(raw.get("threat", 0)),
					"power": int(raw.get("power", 0)),
					"range": move_range,
				})
	e.moves = parsed_moves

	var parsed_weak: Array[String] = []
	var raw_weak = d.get("weak_moves", [])
	if raw_weak is Array:
		for value in raw_weak:
			parsed_weak.append(str(value))
	e.weak_moves = parsed_weak
	e.incorporeal = bool(d.get("incorporeal", false))
	return e


static func _int_stats(raw) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for key in raw.keys():
		if Stats.KEYS.has(key):
			out[key] = int(raw[key])
		else:
			out[key] = raw[key]
	return out
