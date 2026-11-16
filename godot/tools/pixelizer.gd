extends RefCounted

const DILATE_ROUNDS := 4
const BORDER_BAND := 8


static func extract_foreground(img: Image, tol: float) -> Image:
	var work: Image = Image.new()
	work.copy_from(img)
	if work.get_format() != Image.FORMAT_RGBA8:
		work.convert(Image.FORMAT_RGBA8)
	var w: int = work.get_width()
	var h: int = work.get_height()
	if w == 0 or h == 0:
		return work

	var data: PackedByteArray = work.get_data()
	var bg_color: Color = _median_border_color(data, w, h, BORDER_BAND)
	var bg_r: int = int(round(bg_color.r * 255.0))
	var bg_g: int = int(round(bg_color.g * 255.0))
	var bg_b: int = int(round(bg_color.b * 255.0))
	var tol_sq: float = tol * tol

	var is_bg: PackedByteArray = PackedByteArray()
	is_bg.resize(w * h)
	var queue: PackedInt32Array = PackedInt32Array()

	# Flood fill every edge pixel that matches the paper colour.
	var seeds: PackedInt32Array = PackedInt32Array()
	for x in range(w):
		seeds.append(x)
		seeds.append((h - 1) * w + x)
	for y in range(1, h - 1):
		seeds.append(y * w)
		seeds.append(y * w + (w - 1))
	for p in seeds:
		if is_bg[p] == 0 and _near_color(data, p, bg_r, bg_g, bg_b, tol_sq):
			is_bg[p] = 1
			queue.append(p)

	var head: int = 0
	while head < queue.size():
		var p: int = queue[head]
		head += 1
		var px: int = p % w
		@warning_ignore("integer_division")
		var py: int = p / w
		if px > 0 and is_bg[p - 1] == 0 and _near_color(data, p - 1, bg_r, bg_g, bg_b, tol_sq):
			is_bg[p - 1] = 1
			queue.append(p - 1)
		if px < w - 1 and is_bg[p + 1] == 0 and _near_color(data, p + 1, bg_r, bg_g, bg_b, tol_sq):
			is_bg[p + 1] = 1
			queue.append(p + 1)
		if py > 0 and is_bg[p - w] == 0 and _near_color(data, p - w, bg_r, bg_g, bg_b, tol_sq):
			is_bg[p - w] = 1
			queue.append(p - w)
		if py < h - 1 and is_bg[p + w] == 0 and _near_color(data, p + w, bg_r, bg_g, bg_b, tol_sq):
			is_bg[p + w] = 1
			queue.append(p + w)

	# Label the remaining foreground and drop components that are too small.
	var labels: PackedInt32Array = PackedInt32Array()
	labels.resize(w * h)
	var areas: Array[int] = [0]
	var label_count: int = 0
	var stack: PackedInt32Array = PackedInt32Array()
	for start in range(w * h):
		if is_bg[start] == 1 or labels[start] != 0:
			continue
		label_count += 1
		labels[start] = label_count
		var area: int = 0
		stack.clear()
		stack.append(start)
		while not stack.is_empty():
			var p: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			area += 1
			var px: int = p % w
			@warning_ignore("integer_division")
			var py: int = p / w
			if px > 0 and is_bg[p - 1] == 0 and labels[p - 1] == 0:
				labels[p - 1] = label_count
				stack.append(p - 1)
			if px < w - 1 and is_bg[p + 1] == 0 and labels[p + 1] == 0:
				labels[p + 1] = label_count
				stack.append(p + 1)
			if py > 0 and is_bg[p - w] == 0 and labels[p - w] == 0:
				labels[p - w] = label_count
				stack.append(p - w)
			if py < h - 1 and is_bg[p + w] == 0 and labels[p + w] == 0:
				labels[p + w] = label_count
				stack.append(p + w)
		areas.append(area)

	var max_area: int = 0
	for i in range(1, areas.size()):
		if areas[i] > max_area:
			max_area = areas[i]
	var min_area: float = float(max_area) * 0.01
	for p in range(w * h):
		if is_bg[p] == 1:
			continue
		var label: int = labels[p]
		if label == 0 or float(areas[label]) < min_area:
			is_bg[p] = 1

	# Write the alpha channel and remember which pixels need the colour bleed.
	var bg_indices: PackedInt32Array = PackedInt32Array()
	var filled: PackedByteArray = PackedByteArray()
	filled.resize(w * h)
	for p in range(w * h):
		var alpha_index: int = p * 4 + 3
		if is_bg[p] == 1:
			data[alpha_index] = 0
			bg_indices.append(p)
		else:
			data[alpha_index] = 255
			filled[p] = 1

	# Bleed foreground colours outward so resampling never picks up paper colour.
	var frontier: PackedInt32Array = PackedInt32Array()
	var frontier_colors: PackedByteArray = PackedByteArray()
	for p in bg_indices:
		var px: int = p % w
		@warning_ignore("integer_division")
		var py: int = p / w
		var src: int = -1
		if px > 0 and filled[p - 1] == 1:
			src = p - 1
		elif px < w - 1 and filled[p + 1] == 1:
			src = p + 1
		elif py > 0 and filled[p - w] == 1:
			src = p - w
		elif py < h - 1 and filled[p + w] == 1:
			src = p + w
		if src >= 0:
			frontier.append(p)
			frontier_colors.append(data[src * 4])
			frontier_colors.append(data[src * 4 + 1])
			frontier_colors.append(data[src * 4 + 2])
	for k in range(frontier.size()):
		var p: int = frontier[k]
		data[p * 4] = frontier_colors[k * 3]
		data[p * 4 + 1] = frontier_colors[k * 3 + 1]
		data[p * 4 + 2] = frontier_colors[k * 3 + 2]
		filled[p] = 1

	for _round in range(1, DILATE_ROUNDS):
		var next_frontier: PackedInt32Array = PackedInt32Array()
		var next_sources: PackedInt32Array = PackedInt32Array()
		for p in frontier:
			var px: int = p % w
			@warning_ignore("integer_division")
			var py: int = p / w
			if px > 0 and filled[p - 1] == 0:
				filled[p - 1] = 1
				next_frontier.append(p - 1)
				next_sources.append(p)
			if px < w - 1 and filled[p + 1] == 0:
				filled[p + 1] = 1
				next_frontier.append(p + 1)
				next_sources.append(p)
			if py > 0 and filled[p - w] == 0:
				filled[p - w] = 1
				next_frontier.append(p - w)
				next_sources.append(p)
			if py < h - 1 and filled[p + w] == 0:
				filled[p + w] = 1
				next_frontier.append(p + w)
				next_sources.append(p)
		for k in range(next_frontier.size()):
			var p: int = next_frontier[k]
			var src: int = next_sources[k]
			data[p * 4] = data[src * 4]
			data[p * 4 + 1] = data[src * 4 + 1]
			data[p * 4 + 2] = data[src * 4 + 2]
		frontier = next_frontier

	work.set_data(w, h, false, Image.FORMAT_RGBA8, data)
	return work


static func crop_to_content(img: Image) -> Image:
	var work: Image = Image.new()
	work.copy_from(img)
	if work.get_format() != Image.FORMAT_RGBA8:
		work.convert(Image.FORMAT_RGBA8)
	var w: int = work.get_width()
	var h: int = work.get_height()
	if w == 0 or h == 0:
		return work
	var data: PackedByteArray = work.get_data()
	var min_x: int = w
	var min_y: int = h
	var max_x: int = -1
	var max_y: int = -1
	for y in range(h):
		var row: int = y * w
		for x in range(w):
			if data[(row + x) * 4 + 3] > 0:
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
				if y < min_y:
					min_y = y
				if y > max_y:
					max_y = y
	if max_x < min_x or max_y < min_y:
		return work
	return work.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))


static func resize_to_height(img: Image, height: int) -> Image:
	var work: Image = Image.new()
	work.copy_from(img)
	if work.get_format() != Image.FORMAT_RGBA8:
		work.convert(Image.FORMAT_RGBA8)
	var w: int = work.get_width()
	var h: int = work.get_height()
	if w == 0 or h == 0 or height <= 0:
		return work
	var target_w: int = maxi(1, int(round(float(w) * float(height) / float(h))))
	work.resize(target_w, height, Image.INTERPOLATE_LANCZOS)
	_binarize_alpha(work)
	return work


static func quantize(img: Image, colors: int) -> Image:
	var work: Image = Image.new()
	work.copy_from(img)
	if work.get_format() != Image.FORMAT_RGBA8:
		work.convert(Image.FORMAT_RGBA8)
	var w: int = work.get_width()
	var h: int = work.get_height()
	if w == 0 or h == 0:
		return work
	var limit: int = maxi(1, colors)
	var data: PackedByteArray = work.get_data()
	var pixels: Array[Color] = []
	for p in range(w * h):
		var i: int = p * 4
		if data[i + 3] == 0:
			continue
		pixels.append(Color8(data[i], data[i + 1], data[i + 2]))
	if pixels.is_empty():
		return work

	var palette: Array[Color] = _median_cut(pixels, limit)
	var pal_r: PackedInt32Array = PackedInt32Array()
	var pal_g: PackedInt32Array = PackedInt32Array()
	var pal_b: PackedInt32Array = PackedInt32Array()
	for color in palette:
		pal_r.append(int(round(color.r * 255.0)))
		pal_g.append(int(round(color.g * 255.0)))
		pal_b.append(int(round(color.b * 255.0)))

	var cache: Dictionary = {}
	for p in range(w * h):
		var i: int = p * 4
		if data[i + 3] == 0:
			continue
		var r: int = data[i]
		var g: int = data[i + 1]
		var b: int = data[i + 2]
		var key: int = (r << 16) | (g << 8) | b
		var best: int = int(cache.get(key, -1))
		if best < 0:
			var best_distance: float = INF
			for k in range(palette.size()):
				var dr: float = float(r - pal_r[k])
				var dg: float = float(g - pal_g[k])
				var db: float = float(b - pal_b[k])
				var distance: float = dr * dr + dg * dg + db * db
				if distance < best_distance:
					best_distance = distance
					best = k
			cache[key] = best
		data[i] = pal_r[best]
		data[i + 1] = pal_g[best]
		data[i + 2] = pal_b[best]

	work.set_data(w, h, false, Image.FORMAT_RGBA8, data)
	return work


static func add_outline(img: Image, color: Color) -> Image:
	var src: Image = Image.new()
	src.copy_from(img)
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var w: int = src.get_width()
	var h: int = src.get_height()
	var out_w: int = w + 2
	var out_h: int = h + 2
	var out: Image = Image.create_empty(out_w, out_h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.0, 0.0, 0.0, 0.0))
	out.blit_rect(src, Rect2i(0, 0, w, h), Vector2i(1, 1))

	var positions: PackedInt32Array = PackedInt32Array()
	for y in range(h):
		for x in range(w):
			if src.get_pixel(x, y).a <= 0.0:
				continue
			var ox: int = x + 1
			var oy: int = y + 1
			if out.get_pixel(ox, oy - 1).a <= 0.0:
				positions.append((oy - 1) * out_w + ox)
			if out.get_pixel(ox, oy + 1).a <= 0.0:
				positions.append((oy + 1) * out_w + ox)
			if out.get_pixel(ox - 1, oy).a <= 0.0:
				positions.append(oy * out_w + (ox - 1))
			if out.get_pixel(ox + 1, oy).a <= 0.0:
				positions.append(oy * out_w + (ox + 1))

	var outline_color: Color = Color(color.r, color.g, color.b, 1.0)
	for index in positions:
		var px: int = index % out_w
		@warning_ignore("integer_division")
		var py: int = index / out_w
		out.set_pixel(px, py, outline_color)
	return out


static func process(img: Image, height: int, colors: int, tol: float) -> Image:
	var result: Image = crop_to_content(extract_foreground(img, tol))
	result = resize_to_height(result, height)
	result = quantize(result, colors)
	var darkest: Color = _darkest_opaque_color(result)
	var outline_color: Color = Color(darkest.r * 0.6, darkest.g * 0.6, darkest.b * 0.6, 1.0)
	return add_outline(result, outline_color)


static func count_unique_opaque_colors(img: Image) -> int:
	var work: Image = Image.new()
	work.copy_from(img)
	if work.get_format() != Image.FORMAT_RGBA8:
		work.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = work.get_data()
	var seen: Dictionary = {}
	for p in range(work.get_width() * work.get_height()):
		var i: int = p * 4
		if data[i + 3] == 0:
			continue
		var key: int = (int(data[i]) << 16) | (int(data[i + 1]) << 8) | int(data[i + 2])
		seen[key] = true
	return seen.size()


static func _near_color(data: PackedByteArray, index: int, r: int, g: int, b: int, tol_sq: float) -> bool:
	var i: int = index * 4
	var dr: float = float(data[i]) - float(r)
	var dg: float = float(data[i + 1]) - float(g)
	var db: float = float(data[i + 2]) - float(b)
	return dr * dr + dg * dg + db * db <= tol_sq


static func _median_border_color(data: PackedByteArray, w: int, h: int, band: int) -> Color:
	var rs: PackedInt32Array = PackedInt32Array()
	var gs: PackedInt32Array = PackedInt32Array()
	var bs: PackedInt32Array = PackedInt32Array()
	for y in range(h):
		for x in range(w):
			if x >= band and y >= band and x < w - band and y < h - band:
				continue
			var i: int = (y * w + x) * 4
			rs.append(data[i])
			gs.append(data[i + 1])
			bs.append(data[i + 2])
	if rs.is_empty():
		return Color(1.0, 1.0, 1.0, 1.0)
	rs.sort()
	gs.sort()
	bs.sort()
	var mid: int = rs.size() >> 1
	return Color(
		float(rs[mid]) / 255.0,
		float(gs[mid]) / 255.0,
		float(bs[mid]) / 255.0,
		1.0
	)


static func _binarize_alpha(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var data: PackedByteArray = img.get_data()
	for p in range(w * h):
		var i: int = p * 4 + 3
		data[i] = 255 if data[i] >= 128 else 0
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)


static func _median_cut(pixels: Array[Color], colors: int) -> Array[Color]:
	var boxes: Array = [pixels.duplicate()]
	while boxes.size() < colors:
		var best_index: int = -1
		var best_range: float = 0.0
		var best_channel: int = 0
		for i in range(boxes.size()):
			var box: Array = boxes[i]
			if box.size() < 2:
				continue
			for channel in range(3):
				var channel_range: float = _channel_range(box, channel)
				if channel_range > best_range:
					best_range = channel_range
					best_index = i
					best_channel = channel
		if best_index < 0 or best_range <= 0.0:
			break
		var target: Array = boxes[best_index]
		var histogram: PackedInt32Array = PackedInt32Array()
		histogram.resize(256)
		var min_value: int = 255
		var max_value: int = 0
		for color in target:
			var value: int = clampi(int(round(_channel(color, best_channel) * 255.0)), 0, 255)
			histogram[value] += 1
			if value < min_value:
				min_value = value
			if value > max_value:
				max_value = value

		var half: int = target.size() >> 1
		var split_value: int = min_value
		var found: bool = false
		var cumulative: int = 0
		for v in range(min_value, max_value + 1):
			cumulative += histogram[v]
			if cumulative >= half and cumulative < target.size():
				split_value = v
				found = true
				break
		if not found:
			split_value = max_value - 1

		var left: Array = []
		var right: Array = []
		for color in target:
			var value: int = clampi(int(round(_channel(color, best_channel) * 255.0)), 0, 255)
			if value <= split_value:
				left.append(color)
			else:
				right.append(color)
		if left.is_empty() or right.is_empty():
			break
		boxes[best_index] = left
		boxes.append(right)

	var palette: Array[Color] = []
	for box in boxes:
		palette.append(_average_color(box))
	return palette


static func _channel_range(box: Array, channel: int) -> float:
	var low: float = 1.0
	var high: float = 0.0
	for color in box:
		var value: float = _channel(color, channel)
		if value < low:
			low = value
		if value > high:
			high = value
	return high - low


static func _channel(color: Color, channel: int) -> float:
	match channel:
		0:
			return color.r
		1:
			return color.g
		_:
			return color.b


static func _average_color(box: Array) -> Color:
	if box.is_empty():
		return Color(0.0, 0.0, 0.0, 1.0)
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	for color in box:
		r += color.r
		g += color.g
		b += color.b
	var count: float = float(box.size())
	return Color(r / count, g / count, b / count, 1.0)


static func _darkest_opaque_color(img: Image) -> Color:
	var data: PackedByteArray = img.get_data()
	var best: Color = Color(0.0, 0.0, 0.0, 1.0)
	var best_luma: float = INF
	for p in range(img.get_width() * img.get_height()):
		var i: int = p * 4
		if data[i + 3] == 0:
			continue
		var luma: float = 0.299 * float(data[i]) + 0.587 * float(data[i + 1]) + 0.114 * float(data[i + 2])
		if luma < best_luma:
			best_luma = luma
			best = Color(float(data[i]) / 255.0, float(data[i + 1]) / 255.0, float(data[i + 2]) / 255.0, 1.0)
	return best
