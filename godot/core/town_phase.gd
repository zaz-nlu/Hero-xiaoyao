extends RefCounted

# 小镇昼夜时段（day / dusk / night）的纯数据与插值。
# 只使用 Color/Vector3/Dictionary，不依赖任何场景/UI 类型。

const PHASES: Array[String] = ["day", "dusk", "night"]

const DAY := {
	"sun_rotation": Vector3(-48.0, -38.0, 0.0),
	"sun_color": Color("#ffd9a8"),
	"sun_energy": 1.25,
	"sky_top": Color("#7fa6d8"),
	"sky_horizon": Color("#f2d9b0"),
	"sky_ground_horizon": Color("#f2d9b0"),
	"sky_ground_bottom": Color("#c8b898"),
	"ambient_energy": 0.65,
	"fog_color": Color("#e8d8c0"),
	"lamps_on": false,
	"mountain": "bg_mountains.png",
}

const DUSK := {
	"sun_rotation": Vector3(-12.0, -60.0, 0.0),
	"sun_color": Color("#ff9a5a"),
	"sun_energy": 0.9,
	"sky_top": Color("#5a6aa8"),
	"sky_horizon": Color("#f0a070"),
	"sky_ground_horizon": Color("#d08860"),
	"sky_ground_bottom": Color("#6a5a58"),
	"ambient_energy": 0.455,
	"fog_color": Color("#b08a70"),
	"lamps_on": true,
	"mountain": "bg_mountains.png",
}

const NIGHT := {
	"sun_rotation": Vector3(-55.0, 30.0, 0.0),
	"sun_color": Color("#8aa8ff"),
	"sun_energy": 0.35,
	"sky_top": Color("#0b1230"),
	"sky_horizon": Color("#1b2a52"),
	"sky_ground_horizon": Color("#1b2a52"),
	"sky_ground_bottom": Color("#0b1230"),
	"ambient_energy": 0.2925,
	"fog_color": Color("#16203a"),
	"lamps_on": true,
	"mountain": "bg_night_mountains.png",
}


static func is_valid(p) -> bool:
	return PHASES.has(str(p))


static func next(p) -> String:
	var index := PHASES.find(str(p))
	if index < 0:
		return PHASES[0]
	return PHASES[(index + 1) % PHASES.size()]


static func preset(p) -> Dictionary:
	match str(p):
		"dusk":
			return DUSK.duplicate(true)
		"night":
			return NIGHT.duplicate(true)
		_:
			return DAY.duplicate(true)


# 数值与颜色线性插值；布尔/字符串在 t<0.5 取 a，否则取 b。
static func lerp_preset(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var weight := clampf(t, 0.0, 1.0)
	var result := {}
	for key in a.keys():
		var from_value: Variant = a[key]
		var to_value: Variant = b.get(key, from_value)
		match typeof(from_value):
			TYPE_INT, TYPE_FLOAT:
				result[key] = lerpf(float(from_value), float(to_value), weight)
			TYPE_VECTOR3:
				var from_vec: Vector3 = from_value
				var to_vec: Vector3 = to_value
				result[key] = from_vec.lerp(to_vec, weight)
			TYPE_COLOR:
				var from_color: Color = from_value
				var to_color: Color = to_value
				result[key] = from_color.lerp(to_color, weight)
			_:
				result[key] = to_value if weight >= 0.5 else from_value
	return result
