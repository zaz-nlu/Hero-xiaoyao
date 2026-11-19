extends RefCounted

# 运行时素材目录。路径值与原先散落在各处的字面量一致。

const SCENERY := "res://assets/scenery/"
const TEXTURES := "res://assets/textures/"
const ICONS := "res://assets/icons/"
const SPRITES := "res://assets/sprites/"
const PORTRAITS := "res://assets/portraits/"
const AUDIO := "res://assets/audio/"


static func art_dir(file: String) -> String:
	var name := file.get_file()
	if name.begins_with("icon_"):
		return ICONS
	if name.begins_with("tex_"):
		return TEXTURES
	return SCENERY


static func sprite_path(sprite_id: String) -> String:
	return SPRITES + sprite_id + ".png"
