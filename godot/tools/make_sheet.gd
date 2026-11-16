extends SceneTree

const GAP := 16


func _init() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var out_path: String = str(args.get("out", ""))
	var inputs_raw: String = str(args.get("inputs", ""))
	var scale: int = int(args.get("scale", 4))
	if out_path == "" or inputs_raw == "":
		printerr("usage: --out=<png> --inputs=<a.png|b.png> [--scale=4]")
		quit(1)
		return
	if scale < 1:
		scale = 1

	var paths: PackedStringArray = inputs_raw.split("|", false)
	var images: Array[Image] = []
	var total_width: int = 0
	var max_height: int = 0
	for path in paths:
		var source: Image = Image.load_from_file(path)
		if source == null or source.is_empty():
			printerr("cannot load " + path)
			quit(1)
			return
		var scaled: Image = Image.new()
		scaled.copy_from(source)
		if scaled.get_format() != Image.FORMAT_RGBA8:
			scaled.convert(Image.FORMAT_RGBA8)
		scaled.resize(source.get_width() * scale, source.get_height() * scale, Image.INTERPOLATE_NEAREST)
		images.append(scaled)
		total_width += scaled.get_width()
		max_height = maxi(max_height, scaled.get_height())

	total_width += GAP * (images.size() - 1)
	var sheet: Image = Image.create_empty(total_width, max_height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(90, 90, 90, 255))

	var cursor: int = 0
	for image in images:
		var y: int = max_height - image.get_height()
		sheet.blend_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i(cursor, y))
		cursor += image.get_width() + GAP

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
