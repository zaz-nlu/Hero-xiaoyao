extends RefCounted

# 战旗特效配置表：读取 data/tactics_vfx.json，失败时回退到内置默认表。
# 只做查表与图集行数查询，不创建节点；帧动画由 tactics_stage_fx 播放。

const CONFIG_PATH := "res://data/tactics_vfx.json"

const FALLBACK_ROWS := {
	"vfx_slash": 3,
	"vfx_thrust_sweep": 2,
	"vfx_combo": 2,
	"vfx_heavy_charge": 2,
	"vfx_projectile": 3,
	"vfx_counter": 3,
	"vfx_taiji_parry": 2,
	"vfx_jianyi": 3,
	"vfx_hit": 2,
	"vfx_stun": 2,
	"vfx_support": 3,
	"vfx_dust": 2,
}

static var _config: Dictionary = {}
static var _loaded: bool = false


static func config() -> Dictionary:
	if _loaded:
		return _config
	_loaded = true
	var text := FileAccess.get_file_as_string(CONFIG_PATH)
	var parsed: Variant = null
	if text != "":
		parsed = JSON.parse_string(text)
	if parsed is Dictionary and not (parsed as Dictionary).is_empty():
		_config = parsed
	else:
		_config = fallback_config()
	return _config


static func fallback_config() -> Dictionary:
	return {
		"sheets": FALLBACK_ROWS.duplicate(),
		"martials": {},
		"enemy_moves": {
			"default": {
				"cast": {"sheet": "vfx_slash", "row": 0, "at": "target"},
				"hit": {"sheet": "vfx_hit", "row": 0},
			},
		},
		"events": {},
		"default": {
			"cast": {"sheet": "vfx_slash", "row": 0, "at": "target"},
			"hit": {"sheet": "vfx_hit", "row": 0},
		},
	}


static func sheet_rows(sheet: String) -> int:
	var sheets: Dictionary = config().get("sheets", {})
	var raw: Variant = sheets.get(sheet, FALLBACK_ROWS.get(sheet, 1))
	return maxi(1, int(raw))


static func martial_entry(martial_id: String) -> Dictionary:
	var table: Dictionary = config().get("martials", {})
	var raw: Variant = table.get(martial_id, null)
	if raw is Dictionary:
		return raw
	return {}


static func cast_spec(martial_id: String) -> Variant:
	var entry := martial_entry(martial_id)
	if entry.is_empty():
		return default_cast()
	return entry.get("cast", default_cast())


static func hit_spec(martial_id: String) -> Variant:
	var entry := martial_entry(martial_id)
	if not entry.is_empty():
		var overridden: Variant = entry.get("hit", null)
		if overridden != null:
			return overridden
	var fallback: Dictionary = config().get("default", {})
	return fallback.get("hit", null)


static func enemy_entry(move_id: String, move_type: String) -> Dictionary:
	var table: Dictionary = config().get("enemy_moves", {})
	for key in [move_id, move_type, "default"]:
		var name := str(key)
		if name == "":
			continue
		var raw: Variant = table.get(name, null)
		if raw is Dictionary:
			return raw
	return {}


static func enemy_cast(move_id: String, move_type: String) -> Variant:
	var entry := enemy_entry(move_id, move_type)
	if entry.is_empty():
		return default_cast()
	return entry.get("cast", entry)


static func enemy_hit(move_id: String, move_type: String) -> Variant:
	var entry := enemy_entry(move_id, move_type)
	var spec: Variant = entry.get("hit", null)
	if spec != null:
		return spec
	return hit_spec("")


static func event_spec(event_name: String) -> Variant:
	var events: Dictionary = config().get("events", {})
	return events.get(event_name, null)


static func default_cast() -> Variant:
	var fallback: Dictionary = config().get("default", {})
	return fallback.get("cast", {"sheet": "vfx_slash", "row": 0})
