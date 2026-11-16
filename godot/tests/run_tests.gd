extends SceneTree


func _init() -> void:
	var dir := DirAccess.open("res://tests")
	if dir == null:
		printerr("cannot open res://tests")
		quit(1)
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() \
				and file_name.begins_with("test_") \
				and file_name.ends_with(".gd") \
				and file_name != "test_case.gd":
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()

	var passed := 0
	var failed := 0
	for f in files:
		var script = load("res://tests/" + f)
		if script == null:
			printerr("cannot load " + f)
			failed += 1
			continue
		var instance = script.new()
		for method in instance.get_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			instance.failures.clear()
			instance.call(method_name)
			if instance.failures.is_empty():
				print("PASS %s::%s" % [f, method_name])
				passed += 1
			else:
				print("FAIL %s::%s" % [f, method_name])
				for reason in instance.failures:
					print("  " + str(reason))
				failed += 1

	print("PASS %d / FAIL %d" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)
