extends RefCounted

# 战旗打击反馈：把 core 事件映射成 data/tactics_sfx.json 里的音效与顿帧配置。
# 音效只通过 AudioManager.play_sfx 播放（WAV 由 shared 的 AudioLoader 读取），
# 同一批事件按 STAGGER 秒错开；顿帧取一批事件里的最大值，不叠加。
# 本类是纯映射 + 计时辅助，不持有战斗规则；host 为空时静默且不顿帧。

const CONFIG_PATH := "res://data/tactics_sfx.json"
const STAGGER := 0.06
const HITSTOP_SCALE := 0.05

static var _table: Dictionary = {}
static var _loaded: bool = false

var _host: Node = null
var _guard: Variant = null
var _hitstop_active: bool = false
var _hitstop_until: int = 0


func setup(host: Node) -> void:
	_host = host


# 纯函数：core 事件 → 配置键。优先级：perfect 反制 > 弱点命中 > 其余结果。
static func key_for(event: Dictionary) -> String:
	match str(event.get("type", "")):
		"hit":
			var outcome := str(event.get("outcome", "none"))
			if outcome == "perfect":
				return "hit_perfect"
			if bool(event.get("weak", false)):
				return "weak_hit"
			match outcome:
				"counter":
					return "hit_counter"
				"scrape":
					return "hit_block"
				_:
					return "hit_plain"
		"stun":
			return "stun"
		"jianyi":
			return "jianyi"
		"heal":
			return "heal"
		"dead":
			return "dead"
	return ""


static func entry_for(key: String) -> Dictionary:
	if key == "":
		return {}
	var raw: Variant = _events().get(key, null)
	if raw is Dictionary:
		return raw
	return {}


func play_events(audio, events: Array) -> void:
	var slot := 0
	var hitstop := 0
	var playable := _has_sfx(audio)
	for raw in events:
		if not (raw is Dictionary):
			continue
		var event: Dictionary = raw
		var entry := entry_for(key_for(event))
		if entry.is_empty():
			continue
		hitstop = maxi(hitstop, int(entry.get("hitstop_ms", 0)))
		var sfx := str(entry.get("sfx", ""))
		if sfx == "" or not playable:
			continue
		var deferred := Callable(self, "_play_sfx").bind(
			audio, sfx, float(entry.get("volume", 1.0)))
		_schedule(STAGGER * float(slot), deferred)
		slot += 1
	_start_hitstop(hitstop)


static func _events() -> Dictionary:
	if _loaded:
		return _table
	_loaded = true
	var text := FileAccess.get_file_as_string(CONFIG_PATH)
	if text == "":
		return _table
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return _table
	var events: Variant = (parsed as Dictionary).get("events", {})
	if events is Dictionary:
		_table = events
	return _table


func _play_sfx(audio, name: String, volume: float) -> void:
	if not _has_sfx(audio):
		return
	audio.play_sfx(name, volume)


func _has_sfx(audio) -> bool:
	if audio == null or not (audio is Object) or not is_instance_valid(audio):
		return false
	return audio.has_method("play_sfx")


func _schedule(delay: float, action: Callable) -> void:
	if delay <= 0.0 or _is_headless() or not _host_in_tree():
		action.call()
		return
	var tree: SceneTree = _host.get_tree()
	if tree == null:
		action.call()
		return
	var timer := tree.create_timer(delay, true, false, true)
	timer.timeout.connect(action)


# 顿帧：把 Engine.time_scale 压到 HITSTOP_SCALE，用忽略时间缩放的计时器恢复。
func _start_hitstop(ms: int) -> void:
	if ms <= 0 or _is_headless() or not _host_in_tree():
		return
	var until := Time.get_ticks_msec() + ms
	if _hitstop_active:
		_hitstop_until = maxi(_hitstop_until, until)
		_arm_guard()
		return
	_hitstop_active = true
	_hitstop_until = until
	_arm_guard()
	Engine.time_scale = HITSTOP_SCALE
	_arm_hitstop(ms)


func _arm_hitstop(ms: int) -> void:
	if not _host_in_tree():
		_release_hitstop()
		return
	var tree: SceneTree = _host.get_tree()
	if tree == null:
		_release_hitstop()
		return
	var timer := tree.create_timer(float(ms) / 1000.0, true, false, true)
	timer.timeout.connect(_on_hitstop_timer)


func _on_hitstop_timer() -> void:
	var left := _hitstop_until - Time.get_ticks_msec()
	if left > 0:
		_arm_hitstop(left)
		return
	_release_hitstop()


# 场景被切走时也必须复位：靠挂在视图下的守护节点在退出树时兜底。
func _arm_guard() -> void:
	if _guard != null and is_instance_valid(_guard):
		_guard.armed = true
		return
	_guard = HitstopGuard.new()
	_guard.name = "TacticsHitstop"
	_host.add_child(_guard)
	_guard.armed = true


func _release_hitstop() -> void:
	if not _hitstop_active:
		return
	_hitstop_active = false
	_hitstop_until = 0
	if _guard != null and is_instance_valid(_guard):
		_guard.armed = false
	Engine.time_scale = 1.0


func _is_headless() -> bool:
	var server := DisplayServer.get_name()
	return server == "headless" or server == "dummy"


func _host_in_tree() -> bool:
	return _host != null and is_instance_valid(_host) and _host.is_inside_tree()


# 顿帧期间挂在视图下的守护节点：视图被移出场景树时把 time_scale 复位。
class HitstopGuard extends Node:
	var armed: bool = false

	func _exit_tree() -> void:
		if armed:
			armed = false
			Engine.time_scale = 1.0
