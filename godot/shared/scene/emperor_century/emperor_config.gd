extends RefCounted

# 帝王世纪演出参数：集中放在 data/emperor_century.json，所有项都有默认值。
# 用法：EmperorConfig.load_default() 取一份可修改的副本；override(dict) 覆盖单次演出的参数。

const PATH := "res://data/emperor_century.json"
const PHASES: Array[String] = ["opening", "expansion", "gravity", "slash", "settle"]
const DEFAULTS := {
	"opening_duration": 1.2, "expansion_duration": 1.6, "gravity_duration": 1.7,
	"slash_duration": 2.0, "settle_duration": 1.5, "closing_duration": 1.2,
	"domain_radius": 7.0, "domain_opacity": 0.85, "boundary_brightness": 0.55,
	"gravity_visual_strength": 1.0, "screen_shake_strength": 0.6,
	"gravity_particle_count": 28, "auto_cut_visual_frequency": 1.4,
	"auto_cut_line_width": 0.08, "auto_cut_duration": 0.7, "slash_flash_strength": 1.0,
	"camera_zoom_strength": 1.0, "cinematic_speed": 1.0, "preview_cut_count": 4,
	"dim_amount": 0.22, "press_sink": 0.14, "rock_count": 14, "arc_chance": 0.25,
	"unit_width": 1.0, "seed": 20251120,
}

var values: Dictionary = DEFAULTS.duplicate()
var roles: Dictionary = {}


static func load_default() -> RefCounted:
	var out: RefCounted = load("res://shared/scene/emperor_century/emperor_config.gd").new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		var data: Dictionary = parsed
		var raw_values: Variant = data.get("values", {})
		if raw_values is Dictionary:
			for key in (raw_values as Dictionary).keys():
				out.values[str(key)] = raw_values[key]
		var raw_roles: Variant = data.get("roles", {})
		if raw_roles is Dictionary:
			out.roles = raw_roles
	return out


func override(extra: Dictionary) -> void:
	for key in extra.keys():
		if values.has(str(key)):
			values[str(key)] = extra[key]


func f(key: String) -> float:
	return float(values.get(key, DEFAULTS.get(key, 0.0)))


func i(key: String) -> int:
	return int(values.get(key, DEFAULTS.get(key, 0)))


func duration_of(phase: String) -> float:
	return maxf(0.01, f(phase + "_duration"))


# 每个阶段在“演出时间轴”上的 [起点, 终点]（秒，未乘倍速）。
func phase_bounds() -> Dictionary:
	var out := {}
	var cursor := 0.0
	for phase in PHASES:
		var length := duration_of(phase)
		out[phase] = [cursor, cursor + length]
		cursor += length
	return out


func total_duration() -> float:
	var total := 0.0
	for phase in PHASES:
		total += duration_of(phase)
	return total
