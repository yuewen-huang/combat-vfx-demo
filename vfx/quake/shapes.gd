extends RefCounted
## Stateless painters for ground-impact bodies and debris. Every function draws at `at`
## (a point on the ground, y up is negative) on the given CanvasItem from local time `t`,
## so a frame can be reproduced from the event clock alone.
const Tex = preload("res://vfx/quake/textures.gd")
const M = preload("res://vfx/quake/materials.gd")

static func h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)

static func c(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * clampf(alpha, 0.0, 1.0))

static func back_out(x: float) -> float:
	var k := clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * k * k * k + 1.70158 * k * k

static func _edge(pal: Dictionary) -> Color:
	return M.v(0.95)

## Quad strip between two polylines with a colour per side, safe for any bends.
static func strip(ci: CanvasItem, a: PackedVector2Array, b: PackedVector2Array, ca: Array, cb: Array) -> void:
	for i in a.size() - 1:
		ci.draw_primitive(PackedVector2Array([a[i], a[i + 1], b[i + 1], b[i]]),
			PackedColorArray([ca[i], ca[i + 1], cb[i + 1], cb[i]]), PackedVector2Array())

## 兜底: the widest a soft glow may be (0 = no limit). Large soft glows cost the most on a
## software renderer.
static var glow_limit := 0.0

static func glow(ci: CanvasItem, at: Vector2, size: Vector2, colour: Color) -> void:
	if colour.a <= 0.003: return
	if glow_limit > 0.0 and maxf(size.x, size.y) > glow_limit: size *= glow_limit / maxf(size.x, size.y)
	ci.draw_texture_rect(Tex.soft(), Rect2(at - size * 0.5, size), false, colour)

## Irregular faceted pebble: body, lit cap, crisp outline.
static func chunk(ci: CanvasItem, at: Vector2, size: float, angle: float, seed: float, pal: Dictionary, alpha: float, heat := 0.0) -> void:
	if alpha <= 0.01 or size < 0.5: return
	var pts := PackedVector2Array()
	var n := 5 + int(h(seed) * 2.0)
	for i in n:
		var a := TAU * (i + h(seed + i) * 0.5) / n
		pts.append(at + Vector2(cos(a), sin(a) * 0.8).rotated(angle) * size * (0.7 + h(seed + i * 3.1) * 0.45))
	ci.draw_colored_polygon(pts, c(pal.dark, alpha))
	var cap := PackedVector2Array([pts[n - 1], pts[0], pts[1], at + Vector2(0, -size * 0.1)])
	var top := 0
	for i in n: if pts[i].y < pts[top].y: top = i
	cap = PackedVector2Array([pts[posmod(top - 1, n)], pts[top], pts[(top + 1) % n], at])
	ci.draw_colored_polygon(cap, c(pal.light if heat <= 0.0 else M.v(0.93), alpha))
	pts.append(pts[0])
	ci.draw_polyline(pts, c(pal.deep, alpha), 1.2, true)

## A spike or slab of rock torn up out of the ground, leaning `lean` (screen x, −1…1).
## Rises with overshoot, holds, then sinks back; `heat` adds molten seams (magma).
static func rock(ci: CanvasItem, at: Vector2, s: float, seed: float, lean: float, t: float, life: float, pal: Dictionary, heat := 0.0) -> void:
	var rise := back_out(t / 0.085)
	var sink := smoothstep(life * 0.6, life, t)
	var sy := rise * (1.0 - sink)
	if sy <= 0.01: return
	var slab := h(seed + 3.0) < 0.38
	var tall := s * (1.0 + h(seed) * 0.6) * (0.55 if slab else 1.0)
	var w := s * (0.42 + h(seed + 1.0) * 0.22) * (1.7 if slab else 1.0)
	var l := lean * tall * (0.2 + h(seed + 2.0) * 0.35) * (2.0 if slab else 1.0)
	var flip := 1.0 if h(seed + 4.0) < 0.5 else -1.0
	var bl := Vector2(-w * 0.5, 2)
	var br := Vector2(w * 0.5, 2)
	var rb := Vector2(w * (h(seed + 5.0) - 0.5) * 0.35, 2)
	var tip := Vector2(l + (h(seed + 6.0) - 0.5) * w * 0.35, -tall)
	var sl := Vector2(-w * 0.5 + l * 0.45 - w * 0.06, -tall * (0.42 + h(seed + 7.0) * 0.22))
	var sr := Vector2(w * 0.5 + l * 0.55 + w * 0.04, -tall * (0.3 + h(seed + 8.0) * 0.25))
	var tip2 := tip + Vector2(w * 0.28 * flip, tall * (0.1 + h(seed + 9.0) * 0.12)) if slab else tip
	ci.draw_set_transform(at + Vector2(0, sink * s * 0.12), 0.0, Vector2(1.0, sy))
	var lit := PackedVector2Array([bl, sl, tip, rb])
	var shade := PackedVector2Array([rb, tip, tip2, sr, br]) if slab else PackedVector2Array([rb, tip, sr, br])
	if slab and flip < 0.0:
		lit = PackedVector2Array([bl, sl, tip2, tip, rb])
		shade = PackedVector2Array([rb, tip, sr, br])
	ci.draw_colored_polygon(lit, c(pal.rock_lit, 1.0))
	ci.draw_colored_polygon(shade, c(pal.dark, 1.0))
	# Darker foot where the slab leaves the ground, so it reads as torn out of it.
	ci.draw_colored_polygon(PackedVector2Array([bl, br, br + Vector2(0, -tall * 0.16), bl + Vector2(w * 0.1, -tall * 0.2)]), c(pal.deep, 0.45))
	# Fresh fracture faces catch the light along the ridge and the upper edge.
	ci.draw_polyline(PackedVector2Array([sl, tip]), c(pal.rock_hi, 0.9), 1.6, true)
	ci.draw_polyline(PackedVector2Array([rb.lerp(tip, 0.25), tip]), c(pal.light, 0.4), 1.0, true)
	var crack_from := rb.lerp(sr, 0.5) + Vector2(0, -tall * 0.1)
	ci.draw_polyline(PackedVector2Array([crack_from, crack_from.lerp(tip, 0.35) + Vector2(w * 0.08, 0), crack_from.lerp(tip, 0.55)]), c(pal.deep, 0.7), 1.0, true)
	if heat > 0.0:
		var hot := c(M.v(0.92), heat)
		ci.draw_polyline(PackedVector2Array([rb, rb.lerp(tip, 0.4) + Vector2(-w * 0.06, 0), rb.lerp(tip, 0.75)]), hot, 2.0, true)
		ci.draw_polyline(PackedVector2Array([bl.lerp(sl, 0.3), bl.lerp(sl, 0.3).lerp(rb.lerp(tip, 0.3), 0.6)]), hot, 1.4, true)
	var outline := PackedVector2Array([bl, sl, tip2 if slab and flip < 0.0 else tip])
	if slab and flip < 0.0: outline.append(tip)
	elif slab: outline.append(tip2)
	outline.append_array(PackedVector2Array([sr, br]))
	ci.draw_polyline(outline, c(pal.deep, 1.0), 1.8, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Rubble kicked loose around the foot.
	for i in 3:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at2 := at + Vector2(side * w * (0.45 + h(seed + 20.0 + i) * 0.35), 1.0 + h(seed + 30.0 + i) * 3.0)
		chunk(ci, at2, s * (0.08 + h(seed + 40.0 + i) * 0.07) * minf(rise, 1.0), h(seed + i) * TAU, seed + 50.0 + i, pal, 1.0 - sink, heat)

## A cluster of faceted crystals (ice, shadow) that shoots up and shatters at the end.
static func crystal(ci: CanvasItem, at: Vector2, s: float, seed: float, lean: float, t: float, life: float, pal: Dictionary) -> void:
	var rise := back_out(t / 0.07)
	var shatter := smoothstep(life * 0.68, life * 0.8, t)
	if shatter >= 1.0 or rise <= 0.01: return
	var alpha := 1.0 - shatter
	var edge := _edge(pal)
	var count := 3 + int(h(seed) * 2.99)
	for k in count:
		# The main crystal first, the shorter side crystals in front of it.
		var side := 0.0 if k == 0 else (-1.0 if k % 2 == 1 else 1.0)
		var length := s * ((1.5 + h(seed + 1.0) * 0.5) if k == 0 else (0.55 + h(seed + k * 2.3) * 0.5))
		length *= rise * (1.0 + shatter * 0.08)
		var angle := lean * 0.22 + side * (0.32 + h(seed + k * 1.7) * 0.45)
		var base := at + Vector2(side * s * (0.12 + 0.1 * k), (1.0 if k > 0 else 0.0) * 2.0)
		var w := s * (0.16 + h(seed + k * 4.1) * 0.08) * (1.25 if k == 0 else 1.0)
		var b1 := base + Vector2(-w, 0).rotated(angle)
		var b2 := base + Vector2(w, 0).rotated(angle)
		var m1 := base + Vector2(-w * 1.08, -length * 0.3).rotated(angle)
		var m2 := base + Vector2(w * 0.95, -length * 0.36).rotated(angle)
		var tip := base + Vector2(0, -length).rotated(angle)
		var mid := base + Vector2(w * 0.12, 0).rotated(angle)
		ci.draw_colored_polygon(PackedVector2Array([b1, m1, tip, mid]), c(pal.light, 0.92 * alpha))
		ci.draw_colored_polygon(PackedVector2Array([mid, tip, m2, b2]), c(pal.mid, 0.9 * alpha))
		# Depth: the inside of the crystal darkens towards the ground.
		ci.draw_colored_polygon(PackedVector2Array([b1, b2, base.lerp(m2, 0.7), base.lerp(m1, 0.6)]), c(pal.dark, 0.55 * alpha))
		ci.draw_polyline(PackedVector2Array([b1, m1, tip, m2, b2]), c(pal.deep, 0.85 * alpha), 1.5, true)
		ci.draw_polyline(PackedVector2Array([m1.lerp(b1, 0.3), m1, tip]), c(edge, 0.95 * alpha), 1.4, true)
		ci.draw_polyline(PackedVector2Array([mid.lerp(tip, 0.2), tip]), c(edge, 0.55 * alpha), 1.0, true)

## A blob of lava: an ellipse `r` across, `stretch` times longer along `axis`, flattened by
## `squash` (ground pools). pattern 5 shades it molten at `heat`; pattern 0 a flat value.
static func blob(ci: CanvasItem, at: Vector2, r: float, value: float, heat: float, pattern := 5, axis := Vector2.RIGHT, stretch := 1.0, squash := 1.0) -> void:
	if r < 0.4: return
	var pts := PackedVector2Array()
	var turn := axis.angle()
	for i in 16:
		var a := TAU * i / 16.0
		var p := Vector2(cos(a) * r * stretch, sin(a) * r).rotated(turn)
		pts.append(at + Vector2(p.x, p.y * squash))
	ci.draw_polygon(pts, PackedColorArray([M.v(value, 1.0, pattern, heat)]), pts)

## Draws lava pieces [position, radius, heat, axis, stretch] as one liquid: every piece's dark
## skin first, then every molten core, so touching pieces merge instead of beading.
static func liquid(ci: CanvasItem, pieces: Array) -> void:
	for piece: Array in pieces:
		blob(ci, piece[0], float(piece[1]) * 1.18, 0.22, 0.0, 0, piece[3], piece[4])
	for piece: Array in pieces:
		blob(ci, piece[0], float(piece[1]), 0.9, float(piece[2]), 5, piece[3], piece[4])

## Pillar of light (additive) standing on a small glowing ring.
static func beam(ci: CanvasItem, at: Vector2, s: float, seed: float, t: float, life: float, pal: Dictionary, squash: float) -> void:
	if t < 0.0 or t > life: return
	var grow := 1.0 - exp(-t * 28.0)
	var fade := 1.0 - smoothstep(life * 0.3, life * 0.9, t)
	var tall := s * (2.4 + h(seed) * 1.0) * grow
	var w := s * 0.3 * (0.35 + 0.65 * fade) * (1.0 + 0.7 * exp(-t * 14.0))
	var bottom := c(pal.glow, 0.45 * fade)
	var top := c(pal.glow, 0.0)
	ci.draw_polygon(PackedVector2Array([at + Vector2(-w, 0), at + Vector2(w, 0), at + Vector2(w * 0.45, -tall), at + Vector2(-w * 0.45, -tall)]),
		PackedColorArray([bottom, bottom, top, top]))
	var core := c(pal.light, 0.6 * fade)
	ci.draw_polygon(PackedVector2Array([at + Vector2(-w * 0.28, 0), at + Vector2(w * 0.28, 0), at + Vector2(w * 0.1, -tall * 0.9), at + Vector2(-w * 0.1, -tall * 0.9)]),
		PackedColorArray([core, core, c(pal.light, 0.0), c(pal.light, 0.0)]))
	glow(ci, at, Vector2(w * 6.0, w * 6.0 * squash * 1.4), c(pal.glow, 0.4 * fade))
	ring(ci, at, s * (0.35 + t * 1.6), squash, c(pal.light, 0.7 * fade * exp(-t * 2.5)), 1.6)

static func ring(ci: CanvasItem, at: Vector2, radius: float, squash: float, colour: Color, width: float) -> void:
	if colour.a <= 0.01: return
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(at + Vector2(cos(a), sin(a) * squash) * radius)
	ci.draw_polyline(pts, colour, width, true)

## A lightning channel from `a` to `b` by midpoint displacement: `levels` halvings, each
## pushed sideways by `rough` of the span, halving roughly every level.
static func zigzag(a: Vector2, b: Vector2, seed: float, rough: float, levels: int) -> PackedVector2Array:
	var pts: Array[Vector2] = [a, b]
	var push := (b - a).length() * rough
	for level in levels:
		var next: Array[Vector2] = []
		for i in pts.size() - 1:
			var p := pts[i]
			var q := pts[i + 1]
			var side := (q - p).orthogonal().normalized()
			next.append(p)
			next.append((p + q) * 0.5 + side * (h(seed + level * 17.3 + i * 3.71) - 0.5) * push)
		next.append(pts[-1])
		pts = next
		push *= 0.52
	return PackedVector2Array(pts)

## An energy filament along `pts`: a strip `width` px either side, shaded by the filament
## pattern (white-hot core, coloured halo, flowing grain). Tapers towards the far end.
static func filament(ci: CanvasItem, pts: PackedVector2Array, width: float, value: float, alpha: float, seed: float, taper := 0.7) -> void:
	var n := pts.size()
	if n < 2 or alpha <= 0.01 or width <= 0.2: return
	var normals := PackedVector2Array()
	var along := PackedFloat32Array()
	var total := 0.0
	for i in n:
		var d := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		normals.append(d.orthogonal().normalized() if d.length() > 0.0001 else Vector2.UP)
		if i > 0: total += pts[i].distance_to(pts[i - 1])
		along.append(total)
	var tone := M.v(value, alpha, 3, fposmod(seed, 1.0))
	var tones := PackedColorArray([tone, tone, tone, tone])
	for i in n - 1:
		var w0 := width * (1.0 - taper * float(i) / (n - 1))
		var w1 := width * (1.0 - taper * float(i + 1) / (n - 1))
		ci.draw_primitive(PackedVector2Array([pts[i] + normals[i] * w0, pts[i + 1] + normals[i + 1] * w1, pts[i + 1] - normals[i + 1] * w1, pts[i] - normals[i] * w0]),
			tones, PackedVector2Array([Vector2(along[i], -1), Vector2(along[i + 1], -1), Vector2(along[i + 1], 1), Vector2(along[i], 1)]))

## Side branches off a channel: up to `count`, each a shorter zigzag leaving at an angle.
static func branches(main: PackedVector2Array, seed: float, count: int, reach: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for k in count:
		var at := clampi(int(main.size() * (0.18 + h(seed + k * 5.3) * 0.6)), 1, main.size() - 2)
		var heading := (main[at + 1] - main[at - 1]).normalized()
		var turn := (0.35 + h(seed + k * 7.9) * 0.55) * (-1.0 if h(seed + k * 2.2) < 0.5 else 1.0)
		var length := reach * (0.45 + h(seed + k * 3.3) * 0.55)
		out.append(zigzag(main[at], main[at] + heading.rotated(turn) * length, seed + k * 31.0, 0.32, 4))
	return out

## Brightness of a strike over its local time: leader, return stroke, re-strikes, decay.
## Returns [alpha, value, width scale, shown fraction of the channel].
static func strike_curve(t: float, seed: float) -> Array:
	if t < 0.0: return [0.0, 0.0, 0.0, 0.0]
	if t < 0.03: return [0.55, 0.88, 0.45, t / 0.03]
	if t < 0.07: return [1.0, 1.0, 1.25, 1.0]
	var restrike := 1.0 if (t > 0.13 and t < 0.15) or (t > 0.2 and t < 0.215) else 0.0
	var flicker := 0.75 + 0.25 * h(seed + floorf(t * 30.0))
	var decay := exp(-(t - 0.07) * 5.5) * flicker
	var bright := maxf(decay, restrike)
	if t < 0.28: return [bright, lerpf(0.88, 1.0, restrike), lerpf(0.8, 1.15, restrike), 1.0]
	var after := 1.0 - smoothstep(0.28, 0.5, t)
	return [0.45 * after, 0.3, 0.6, 1.0]

## A bolt from the sky onto `at`: a stable main channel with branches; small detail re-forms
## on each re-strike. `tall` is how far above the ground it starts.
static func sky_bolt(ci: CanvasItem, at: Vector2, tall: float, width: float, seed: float, t: float, detail: float) -> void:
	var curve := strike_curve(t, seed)
	if float(curve[0]) <= 0.01: return
	var flash := floorf(clampf((t - 0.07) / 0.07, 0.0, 3.0))
	var top := at + Vector2((h(seed) - 0.5) * tall * 0.45, -tall)
	var main := zigzag(top, at, seed + flash * 0.37, 0.16, 6)
	var shown := int(ceil(float(main.size()) * float(curve[3])))
	if shown < main.size(): main = main.slice(0, maxi(shown, 2))
	var w := width * float(curve[2])
	filament(ci, main, w, float(curve[1]), float(curve[0]), seed, -0.4)
	if float(curve[3]) >= 1.0:
		for branch in branches(main, seed + flash * 11.0, int(2 + detail * 3.0), tall * 0.35):
			filament(ci, branch, w * 0.55, float(curve[1]) * 0.95, float(curve[0]) * 0.8, seed + 0.3, 0.95)

## Short lightning arcs crawling over the ground from `at`, re-forming 24 times a second.
static func ground_arcs(ci: CanvasItem, at: Vector2, size: float, squash: float, seed: float, t: float, span: float, count: int) -> void:
	if t < 0.0 or t > span: return
	var step := floorf(t * 24.0)
	var fade := 1.0 - smoothstep(span * 0.5, span, t)
	for k in count:
		var key := seed + k * 13.0 + step * 7.0
		if h(key) < 0.25: continue
		var dir := Vector2.from_angle(h(key + 1.0) * TAU)
		var end := at + Vector2(dir.x, dir.y * squash) * size * (0.5 + h(key + 2.0) * 0.8)
		var path := zigzag(at, end, key, 0.35, 4)
		filament(ci, path, 5.0, 0.88, 0.85 * fade, key, 0.9)

## Draws a band between `edge` (the cutting edge) and `inner` with the slash pattern.
