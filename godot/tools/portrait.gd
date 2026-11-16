extends SceneTree

const Portrait = preload("res://tools/portrait_lib.gd")


func _init() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var in_path: String = str(args.get("in", ""))
	var out_path: String = str(args.get("out", ""))
	var height: int = int(args.get("height", 768))
	var tol: float = float(args.get("tol", 40.0))
	var feather: int = int(args.get("feather", 1))
	if in_path == "" or out_path == "":
		printerr("usage: --in=<png> --out=<png> [--height=768] [--tol=40] [--feather=1]")
		quit(1)
		return

	var source: Image = Image.load_from_file(in_path)
	if source == null or source.is_empty():
		printerr("cannot load " + in_path)
		quit(1)
		return

	var result: Image = Portrait.make_portrait(source, height, tol, feather)
	var parent: String = out_path.get_base_dir()
	if parent != "":
		var dir_err: Error = DirAccess.make_dir_recursive_absolute(parent)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			printerr("cannot create directory " + parent)
			quit(1)
			return

	var save_err: Error = result.save_png(out_path)
	if save_err != OK:
		printerr("cannot save " + out_path)
		quit(1)
		return

	print("ok %s %dx%d" % [out_path, result.get_width(), result.get_height()])
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
