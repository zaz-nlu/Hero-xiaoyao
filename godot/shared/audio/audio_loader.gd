extends RefCounted

# Loads the hand-rendered WAV files (tools/make_music.py) into AudioStreamWAV at
# runtime. They are never imported by Godot, so load() cannot be used: the bytes
# are parsed from the canonical 44-byte PCM 16-bit header instead.

const AssetPaths = preload("res://shared/resources/asset_paths.gd")

const WAV_DIR := AssetPaths.AUDIO

static var _cache: Dictionary = {}


static func load_wav(name: String, loop: bool) -> AudioStreamWAV:
	if name == "":
		return null
	var key := name + ("|loop" if loop else "|once")
	if _cache.has(key):
		var cached: Variant = _cache[key]
		return cached
	var path := WAV_DIR + name + ".wav"
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44:
		return null
	if _tag(bytes, 0) != "RIFF" or _tag(bytes, 8) != "WAVE":
		return null
	if _tag(bytes, 12) != "fmt " or _tag(bytes, 36) != "data":
		return null
	var audio_format: int = _u16(bytes, 20)
	var channels: int = _u16(bytes, 22)
	var sample_rate: int = _u32(bytes, 24)
	var bits: int = _u16(bytes, 34)
	var data_size: int = _u32(bytes, 40)
	if audio_format != 1:
		return null
	if channels != 1 and channels != 2:
		return null
	if sample_rate <= 0 or bits != 16:
		return null
	if data_size <= 0 or 44 + data_size > bytes.size():
		return null
	if data_size % (channels * 2) != 0:
		return null

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = channels == 2
	stream.data = bytes.slice(44, 44 + data_size)
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(data_size / float(channels * 2))
	_cache[key] = stream
	return stream


static func clear_cache() -> void:
	_cache.clear()


static func _tag(bytes: PackedByteArray, offset: int) -> String:
	return bytes.slice(offset, offset + 4).get_string_from_ascii()


static func _u16(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8)


static func _u32(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8) \
		| (int(bytes[offset + 2]) << 16) | (int(bytes[offset + 3]) << 24)
