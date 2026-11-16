extends SceneTree

const SpriteGen = preload("res://tools/sprite_gen.gd")


func _init() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var def_path: String = str(args.get("def", ""))
	var out_path: String = str(args.get("out", ""))
	if def_path == "" or out_path == "":
		printerr("usage: --def=<json> --out=<png>")
		quit(1)
		return

	var def: Dictionary = SpriteGen.load_def(def_path)
	if def.is_empty():
		printerr("cannot load " + def_path)
		quit(1)
		return

	var sheet: Image = SpriteGen.render_sheet(def)
	var parent: String = out_path.get_base_dir()
	if parent != "":
		var dir_err: Error = DirAccess.make_dir_recursive_absolute(parent)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			printerr("cannot create directory " + parent)
			quit(1)
			return

	var save_err: Error = sheet.save_png(out_path)
	if save_err != OK:
		printerr("cannot save " + out_path)
		quit(1)
		return

	print("ok %s %dx%d" % [out_path, sheet.get_width(), sheet.get_height()])
	quit(0)


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for arg in raw:
		if not arg.begins_with("--"):
			continue
		var body: String = arg.substr(2)
		var eq: int = body.find("=")
		if eq < 0:
			parsed[body] = true
		else:
			parsed[body.substr(0, eq)] = body.substr(eq + 1)
	return parsed
