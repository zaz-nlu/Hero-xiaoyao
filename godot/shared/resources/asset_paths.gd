extends RefCounted

# 运行时素材目录。路径值与原先散落在各处的字面量一致。

const AI_GAME := "res://assets/ai/game/"
const SPRITES := "res://assets/sprites/"
const PORTRAITS := "res://assets/portraits/"
const AUDIO := "res://assets/audio/"


static func sprite_path(sprite_id: String) -> String:
	return SPRITES + sprite_id + ".png"
