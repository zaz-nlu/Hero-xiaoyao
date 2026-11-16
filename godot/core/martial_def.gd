extends RefCounted

var id: String = ""
var name: String = ""
var power: int = 0
var counters: Array[String] = []
var initiative: int = 0
var counter_level: int = 0
var advantage_stat: String = ""
var effects: Array = []


static func from_dict(d: Dictionary) -> RefCounted:
	var script: Variant = load("res://core/martial_def.gd")
	var m: Variant = script.new()
	m.id = str(d.get("id", ""))
	m.name = str(d.get("name", ""))
	m.power = int(d.get("power", 0))
	m.counters = _string_array(d.get("counters", []))
	m.initiative = int(d.get("initiative", 0))
	m.counter_level = int(d.get("counter_level", 0))
	m.advantage_stat = str(d.get("advantage_stat", ""))

	var parsed_effects: Array = []
	var raw_effects = d.get("effects", [])
	if raw_effects is Array:
		for raw in raw_effects:
			if raw is Dictionary:
				parsed_effects.append({
					"kind": str(raw.get("kind", "")),
					"value": float(raw.get("value", 0.0)),
				})
	m.effects = parsed_effects
	return m


static func _string_array(raw) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for value in raw:
			out.append(str(value))
	return out
