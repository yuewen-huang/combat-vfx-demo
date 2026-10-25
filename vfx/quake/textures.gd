extends RefCounted
## Small procedural textures shared by every ground impact, generated once per run:
## a soft round glow and three cloudy dust puffs lit from above.
static var _soft: Texture2D
static var _puffs: Array[Texture2D] = []
static var _atlas: Texture2D

static func soft() -> Texture2D:
	if _soft == null:
		var size := 64
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var r := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
				var a := pow(clampf(1.0 - r, 0.0, 1.0), 2.2)
				image.set_pixel(x, y, Color(1, 1, 1, a))
		_soft = ImageTexture.create_from_image(image)
	return _soft

static func puff(index: int) -> Texture2D:
	if _puffs.is_empty():
		for variant in 3: _puffs.append(_make_puff(variant))
	return _puffs[posmod(index, _puffs.size())]

## The three billows side by side, for the GPU dust (tiles = 3).
static func puff_atlas() -> Texture2D:
	if _atlas == null:
		puff(0)
		var first := _puffs[0].get_image()
		var image := Image.create(first.get_width() * 3, first.get_height(), false, first.get_format())
		for i in 3: image.blit_rect(_puffs[i].get_image(), Rect2i(Vector2i.ZERO, first.get_size()), Vector2i(i * first.get_width(), 0))
		_atlas = ImageTexture.create_from_image(image)
	return _atlas

static func _hash(x: int, y: int, s: int) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0

static func _noise(p: Vector2, s: int) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash(i.x, i.y, s)
	var b := _hash(i.x + 1, i.y, s)
	var c := _hash(i.x, i.y + 1, s)
	var d := _hash(i.x + 1, i.y + 1, s)
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

static func _make_puff(variant: int) -> Texture2D:
	var size := 96
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var uv := Vector2(x + 0.5, y + 0.5) / size
			var q := uv * 4.0
			var n := _noise(q, variant) * 0.55 + _noise(q * 2.0, variant + 7) * 0.3 + _noise(q * 4.0, variant + 13) * 0.15
			var r := (uv - Vector2(0.5, 0.52)).length() * 2.0
			var edge := r + (n - 0.5) * 0.75
			var a := 1.0 - smoothstep(0.35, 0.95, edge)
			a *= 0.55 + 0.45 * n
			# Lit from above: the top of the billow is brighter, the underside sinks into shade.
			var light := clampf(0.62 + (0.5 - uv.y) * 0.65 + (n - 0.5) * 0.35, 0.35, 1.0)
			image.set_pixel(x, y, Color(light, light, light, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)
