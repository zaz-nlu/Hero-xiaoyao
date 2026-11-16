extends RefCounted

const NARRATOR_ID := "narrator"
const SIDES := ["left", "right"]


static func load_speakers(path: String) -> Dictionary:
	var defs: Dictionary = {}
	var errors: Array[String] = []
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		errors.append("cannot read %s" % path)
		return {"defs": defs, "errors": errors}

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		errors.append("speakers: invalid JSON")
		return {"defs": defs, "errors": errors}
	if not (parsed is Array):
		errors.append("speakers: top-level JSON must be an array")
		return {"defs": defs, "errors": errors}

	for i in range(parsed.size()):
		var item: Variant = parsed[i]
		if not (item is Dictionary):
			errors.append("speakers[%d]: entry must be an object" % i)
			continue
		var entry: Dictionary = item

		var raw_id: Variant = entry.get("id", "")
		if not (raw_id is String) or str(raw_id) == "":
			errors.append("speakers[%d]: missing id" % i)
			continue
		var speaker_id: String = str(raw_id)

		var side: String = "right"
		if entry.has("side"):
			var raw_side: Variant = entry["side"]
			if not (raw_side is String) or not SIDES.has(str(raw_side)):
				errors.append("speaker '%s': unknown side '%s'" % [speaker_id, str(raw_side)])
				continue
			side = str(raw_side)

		var portrait: String = ""
		var raw_portrait: Variant = entry.get("portrait", "")
		if raw_portrait is String:
			portrait = str(raw_portrait)
		var speaker_name: String = speaker_id
		var raw_name: Variant = entry.get("name", speaker_id)
		if raw_name is String:
			speaker_name = str(raw_name)

		defs[speaker_id] = {
			"name": speaker_name,
			"portrait": portrait,
			"side": side,
		}
	return {"defs": defs, "errors": errors}


static func parse(json_text: String, speakers: Dictionary) -> Dictionary:
	var lines: Array = []
	var errors: Array[String] = []

	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null:
		errors.append("dialogue: invalid JSON")
		return {"lines": lines, "errors": errors}
	if not (parsed is Array):
		errors.append("dialogue: top-level JSON must be an array")
		return {"lines": lines, "errors": errors}

	for i in range(parsed.size()):
		var item: Variant = parsed[i]
		if not (item is Dictionary):
			errors.append("dialogue[%d]: entry must be an object" % i)
			continue
		var entry: Dictionary = item

		var raw_speaker: Variant = entry.get("speaker", "")
		if not (raw_speaker is String) or str(raw_speaker) == "":
			errors.append("dialogue[%d]: missing speaker" % i)
			continue
		var speaker: String = str(raw_speaker)
		if speaker != NARRATOR_ID and not speakers.has(speaker):
			errors.append("dialogue[%d]: unknown speaker '%s'" % [i, speaker])
			continue

		var raw_text: Variant = entry.get("text", "")
		if not (raw_text is String):
			errors.append("dialogue[%d]: speaker '%s' text must be a string" % [i, speaker])
			continue
		var line_text: String = str(raw_text)
		if line_text.strip_edges() == "":
			errors.append("dialogue[%d]: speaker '%s' has empty text" % [i, speaker])
			continue

		var side_override: String = ""
		if entry.has("side"):
			var raw_side: Variant = entry["side"]
			if not (raw_side is String) or not SIDES.has(str(raw_side)):
				errors.append("dialogue[%d]: speaker '%s' has invalid side '%s'" % [i, speaker, str(raw_side)])
				continue
			side_override = str(raw_side)

		var line_name: String = ""
		var line_portrait: String = ""
		var line_side: String = "center"
		if speaker != NARRATOR_ID:
			var def: Variant = speakers[speaker]
			if def is Dictionary:
				var def_dict: Dictionary = def
				line_name = str(def_dict.get("name", speaker))
				line_portrait = str(def_dict.get("portrait", ""))
				line_side = str(def_dict.get("side", "right"))
			else:
				line_name = speaker
			if side_override != "":
				line_side = side_override

		lines.append({
			"speaker": speaker,
			"name": line_name,
			"text": line_text,
			"portrait": line_portrait,
			"side": line_side,
		})
	return {"lines": lines, "errors": errors}


static func load_file(path: String, speakers: Dictionary) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return {"lines": [], "errors": ["cannot read %s" % path]}
	return parse(text, speakers)


var lines: Array = []
var index: int = 0


func _init(p_lines: Array) -> void:
	lines = p_lines


func current() -> Dictionary:
	if index < 0 or index >= lines.size():
		return {}
	var line: Variant = lines[index]
	if line is Dictionary:
		return line
	return {}


func advance() -> void:
	index += 1


func is_finished() -> bool:
	return index >= lines.size()
