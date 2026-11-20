extends RefCounted

# Exported builds load imported audio. Editor runs can also read the raw
# hand-rendered WAV files from tools/make_music.py.

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
		if not ResourceLoader.exists(path, "AudioStreamWAV"):
			return null
		var imported := ResourceLoader.load(path, "AudioStreamWAV") as AudioStreamWAV
		if imported == null:
			return null
		var copy := imported.duplicate() as AudioStreamWAV
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop:
			copy.loop_begin = 0
			copy.loop_end = int(round(copy.get_length() * copy.mix_rate))
		_cache[key] = copy
		return copy
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


# Prefer Ogg/Vorbis music and fall back to the hand-rendered WAV tracks.
static func load_music(name: String, loop: bool) -> AudioStream:
	if name == "":
		return null
	var key := name + ("|loop" if loop else "|once") + "|music"
	if _cache.has(key):
		var cached: Variant = _cache[key]
		return cached
	var path := WAV_DIR + name + ".ogg"
	var stream: AudioStreamOggVorbis = null
	if FileAccess.file_exists(path):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0:
			stream = AudioStreamOggVorbis.load_from_buffer(bytes)
	elif ResourceLoader.exists(path, "AudioStreamOggVorbis"):
		var imported := ResourceLoader.load(path, "AudioStreamOggVorbis") as AudioStreamOggVorbis
		if imported != null:
			stream = imported.duplicate() as AudioStreamOggVorbis
	if stream != null:
		stream.loop = loop
		stream.loop_offset = 0.0
		_cache[key] = stream
		return stream
	var fallback := load_wav(name, loop)
	if fallback != null:
		_cache[key] = fallback
	return fallback


static func has_music(name: String) -> bool:
	if name == "":
		return false
	return FileAccess.file_exists(WAV_DIR + name + ".ogg") \
		or FileAccess.file_exists(WAV_DIR + name + ".wav") \
		or ResourceLoader.exists(WAV_DIR + name + ".ogg", "AudioStreamOggVorbis") \
		or ResourceLoader.exists(WAV_DIR + name + ".wav", "AudioStreamWAV")


static func clear_cache() -> void:
	_cache.clear()


static func _tag(bytes: PackedByteArray, offset: int) -> String:
	return bytes.slice(offset, offset + 4).get_string_from_ascii()


static func _u16(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8)


static func _u32(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8) \
		| (int(bytes[offset + 2]) << 16) | (int(bytes[offset + 3]) << 24)
