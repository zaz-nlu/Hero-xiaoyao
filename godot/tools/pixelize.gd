extends SceneTree

const Pixelizer = preload("res://tools/pixelizer.gd")


func _init() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var in_path: String = str(args.get("in", ""))
	var out_path: String = str(args.get("out", ""))
	var height: int = int(args.get("height", 96))
	var colors: int = int(args.get("colors", 24))
	var tol: float = float(args.get("tol", 40.0))
	if in_path == "" or out_path == "":
		printerr("usage: --in=<png> --out=<png> [--height=96] [--colors=24] [--tol=40]")
		quit(1)
		return

	var source: Image = Image.load_from_file(in_path)
	if source == null or source.is_empty():
		printerr("cannot load " + in_path)
		quit(1)
		return

	var result: Image = Pixelizer.process(source, height, colors, tol)
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

	var color_count: int = Pixelizer.count_unique_opaque_colors(result)
	print("ok %s %dx%d colors=%d" % [out_path, result.get_width(), result.get_height(), color_count])
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
