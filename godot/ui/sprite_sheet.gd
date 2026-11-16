extends RefCounted

const ImageCache = preload("res://ui/image_cache.gd")

const FRAME_W := 32
const FRAME_H := 48
const DIR_DOWN := 0
const DIR_UP := 1
const DIR_RIGHT := 2
const DIR_LEFT := 3


static func frame(sprite_id: String, direction: int, frame_index: int) -> AtlasTexture:
	var sheet: Texture2D = ImageCache.texture("res://assets/sprites/%s.png" % sprite_id)
	if sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(frame_index * FRAME_W, direction * FRAME_H, FRAME_W, FRAME_H)
	return atlas
