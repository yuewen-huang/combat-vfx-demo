@tool
class_name PixelSlash
extends Node2D
## Procedural pixel slash. A ribbon in three parts, all drawn into a
## low-resolution SubViewport and shown with nearest-neighbour scaling:
##   main band — the tip's recent path; older samples narrow and darken in steps and are
##               removed after `tail` seconds (no whole-trail alpha fade);
##   outer line — thin band(s) beyond a gap, same ageing;
##   tip edge  — a bright block on the newest part while the tip is moving.
## The swing ends by dropping the tip; the tail keeps narrowing until nothing is left.
## Shapes:
##   arc   — tip runs along an ellipse (radius × squash, rotated by tilt). squash < 1
##           reads as a horizontal swing seen from the side; any angle via start/end/tilt.
##   line  — tip runs straight from from_point to to_point: a thrust, with speed lines on
##           both sides and an arrow head.
##   burst — a ring and spikes opening at `center` (impacts, grab closures).
##   path  — one continuous stroke through a list of commands (see build_path): lines and
##           arcs joined tangent to each other, speed and width changing continuously, so
##           a whole combo flows without a stop or a kink; `jump` lifts the blade.
##   crescent — a fighting-game sword smear on the ellipse arc: thin at both ends and thick
##              in the middle, opens in `duration`, holds `hold`, then erodes from its old end
##              and thins over `fade`; layered body / mid / white core, an outer echo line,
##              an inner ghost one frame behind, and speed lines flung out as it fades.
##   star   — a hit spark: sharp rays (burst_spikes, alternating long/short) and a white
##            core opening in `duration`, holding `hold`, shrinking over `fade`.
##   sparks — pixel shards sprayed from `center` in a fan around spark_dir, under gravity;
##            with spark_streak off they are single drifting embers.
## Time only advances through advance(), so the owner can drive it with its action clock;
## `delay` holds the slash hidden for that much action time first.

signal finished

## World pixels per slash texel.
var PIXEL := 3.0
## Largest step between two samples; keeps curves round at low frame rates.
const MAX_ARC_STEP := deg_to_rad(4.0)
const MAX_LINE_STEP := 0.04
const BURST_SPIKES := 8
## Path sampling distance in world pixels.
const PATH_STEP := 2.0
## Newest path points drawn as the bright leading edge.
const PATH_TIP_POINTS := 6
## Path stroke kinds: a striking blade, the thin blade carry between strikes, and a
## gathering wind-up that shimmers.
enum Kind { HIT, CARRY, CHARGE }
const KIND_NAMES := {"hit": Kind.HIT, "carry": Kind.CARRY, "charge": Kind.CHARGE}
## Period of the charge shimmer between the two brightest colours.
const CHARGE_FLICKER := 0.04

const PALETTES := {
	&"violet": [Color("fff4ff"), Color("f3b6ff"), Color("c25fe6"), Color("4f1c72")],
	&"normal": [Color("ffffff"), Color("d6f3ff"), Color("78c4ea"), Color("33618f")],
	&"red": [Color("fff0dd"), Color("ff9c66"), Color("e2412f"), Color("6e1222")],
	&"gold": [Color("fffbe2"), Color("ffe189"), Color("e4ab35"), Color("80530f")],
	&"green": [Color("f4ffe6"), Color("b9f27c"), Color("4fbf4a"), Color("1d5a2c")],
}

var shape := &"arc"
## Arc: centre relative to this node; angles in radians (y down, so increasing turns
## clockwise on screen); radius is the outer edge.
var center := Vector2.ZERO
var start_angle := 0.0
var end_angle := PI * 0.5
var radius := 120.0
var squash := 1.0
var tilt := 0.0
## Line: the tip travels from_point → to_point.
var from_point := Vector2.ZERO
var to_point := Vector2(200, 0)
## Path: commands for build_path(), squashed vertically then rotated (radians).
var path: Array = []
var path_squash := 1.0
var path_tilt := 0.0
## Scales every path width; echo layers reuse the same path thinner.
var width_scale := 1.0
## Line: draw the arrow head while the tip moves (off for plain cut lines).
var arrow_head := true
## Crescent and star: seconds fully open, then seconds to vanish.
var hold := 0.04
var fade := 0.12
## Crescent speed lines flung outward as it fades.
const SPEED_LINES := 5
## Burst: ring spikes (0 for a plain ring such as a ground shockwave).
var burst_spikes := BURST_SPIKES
## Sparks: count, fan direction (radians, facing-forward) and half-spread, speed and life
## ranges, downward gravity (negative drifts up), fixed seed so a spray is repeatable.
var spark_count := 10
var spark_dir := 0.0
var spark_spread := deg_to_rad(35.0)
var spark_speed := Vector2(250, 650)
var spark_life := Vector2(0.18, 0.32)
var spark_gravity := 900.0
var spark_seed := 1
var spark_streak := true
## Converging shards start on a ring and arrive at `center` as their life ends (a gather).
var spark_converge := false
## Main band width at full strength (arc: inward from the outer edge; line: centred).
var width := 40.0
var line_gap := 6.0
var line_width := 4.0
var duration := 0.12
var tail := 0.16
var delay := 0.0
var palette: Array = palette_of(&"normal")
## 1 faces right; -1 mirrors the whole slash.
var facing := 1.0

var age := 0.0
var _samples: Array[Vector2] = []  # x = path parameter, y = birth time
var _swinging := true
var _viewport: SubViewport
var _canvas: Node2D
var _display: Sprite2D
var _path: Dictionary
var _next_point := 1
var _particles: Array[Dictionary] = []

## Turns path commands into dense points. Each command after "start" ends at its own
## `speed` (px/s) and `width`; both change linearly in time across the command, so speed
## is continuous at every joint. Commands:
##   {start: Vector2, heading: deg, speed, width}
##   {line: length, speed, width}
##   {arc: turn deg (positive turns clockwise on screen), r: radius, speed, width}
##   {jump: Vector2, heading, speed, width, wait: s} — lifts the blade (the trail breaks)
## Any drawing command may add burst: true (radius burst_radius) to mark its end point.
## Drawing commands may also set kind ("hit" default, "carry", "charge"), palette (a
## PALETTES key overriding the slash's own) and contact: fraction of the command where the
## blade lands, with stop (hit-stop seconds), shake, sparks (count), flash (seconds the
## stroke shows white) and finisher (bool) carried into the contact record; gather: true
## records the command's end (time, at) in `gathers`, where a wind-up peaks.
## Returns points, times, widths, strokes, kinds, commands (index per point), palettes
## (PALETTES key per point, &"" = the slash's own), normals, sides (+1 = outside of the
## turn is the normal's side), joints (last point index of each drawing command), bursts
## [{time, at, radius}], contacts [{time, at, dir, command, stop, shake, sparks, flash,
## finisher}] and total time.
static func build_path(commands: Array, squash := 1.0, tilt := 0.0) -> Dictionary:
	var points := PackedVector2Array()
	var times := PackedFloat32Array()
	var widths := PackedFloat32Array()
	var strokes := PackedInt32Array()
	var kinds := PackedByteArray()
	var command_of := PackedInt32Array()
	var palettes: Array[StringName] = []
	var bursts: Array[Dictionary] = []
	var contacts: Array[Dictionary] = []
	var gathers: Array[Dictionary] = []
	var joints := PackedInt32Array()
	var pos := Vector2.ZERO
	var heading := 0.0
	var speed := 0.0
	var width := 8.0
	var time := 0.0
	var stroke := 0
	for command_index in commands.size():
		var c: Dictionary = commands[command_index]
		if c.has("start") or c.has("jump"):
			if c.has("jump"):
				time += float(c.get("wait", 0.05))
				stroke += 1
			pos = c.get("start", c.get("jump"))
			heading = deg_to_rad(float(c.get("heading", 0.0)))
			speed = float(c.speed)
			width = float(c.get("width", width))
			points.append(pos)
			times.append(time)
			widths.append(width)
			strokes.append(stroke)
			kinds.append(Kind.CARRY)
			command_of.append(command_index)
			palettes.append(&"")
			continue
		var end_speed := float(c.speed)
		var end_width := float(c.get("width", width))
		var turn := deg_to_rad(float(c.get("arc", 0.0)))
		var arc_radius := float(c.get("r", 0.0))
		var length := absf(turn) * arc_radius if c.has("arc") else float(c.line)
		var span := 2.0 * length / (speed + end_speed)
		var accel := (end_speed * end_speed - speed * speed) / (2.0 * length)
		var dir := Vector2.from_angle(heading)
		var pivot := pos - dir.orthogonal() * signf(turn) * arc_radius
		var count := maxi(1, ceili(length / PATH_STEP))
		var first := points.size()
		var kind: int = KIND_NAMES[String(c.get("kind", "hit"))]
		var colours := StringName(c.get("palette", &""))
		for k in range(1, count + 1):
			var dist := length * k / count
			var tau := dist / speed if absf(accel) < 0.000001 else (-speed + sqrt(maxf(speed * speed + 2.0 * accel * dist, 0.0))) / accel
			var p := pivot + (pos - pivot).rotated(signf(turn) * dist / arc_radius) if c.has("arc") else pos + dir * dist
			points.append(p)
			times.append(time + tau)
			widths.append(lerpf(width, end_width, tau / span))
			strokes.append(stroke)
			kinds.append(kind)
			command_of.append(command_index)
			palettes.append(colours)
		if c.has("contact"):
			var at := clampi(first + roundi(float(c.contact) * (count - 1)), first, points.size() - 1)
			var ahead := mini(at + 1, points.size() - 1)
			contacts.append({"time": times[at], "at": points[at], "dir": (points[ahead] - points[at - 1]).normalized(),
				"command": command_index, "stop": float(c.get("stop", 0.0)), "shake": float(c.get("shake", 0.0)),
				"sparks": int(c.get("sparks", 0)), "flash": float(c.get("flash", 0.0)), "finisher": bool(c.get("finisher", false))})
		heading += turn
		joints.append(points.size() - 1)
		pos = points[-1]
		time += span
		speed = end_speed
		width = end_width
		if c.get("burst", false): bursts.append({"time": time, "at": pos, "radius": float(c.get("burst_radius", 46.0))})
		if c.get("gather", false): gathers.append({"time": time, "at": pos})
	for i in points.size():
		points[i] = Vector2(points[i].x, points[i].y * squash).rotated(tilt)
	for b in bursts: b.at = Vector2(b.at.x, b.at.y * squash).rotated(tilt)
	for g in gathers: g.at = Vector2(g.at.x, g.at.y * squash).rotated(tilt)
	for contact in contacts:
		contact.at = Vector2(contact.at.x, contact.at.y * squash).rotated(tilt)
		contact.dir = Vector2(contact.dir.x, contact.dir.y * squash).rotated(tilt).normalized()
	var normals := PackedVector2Array()
	var sides := PackedFloat32Array()
	normals.resize(points.size())
	sides.resize(points.size())
	var side := 1.0
	for i in points.size():
		var before := i - 1 if i > 0 and strokes[i - 1] == strokes[i] else i
		var after := i + 1 if i + 1 < points.size() and strokes[i + 1] == strokes[i] else i
		normals[i] = (points[after] - points[before]).normalized().orthogonal()
		if before != i and after != i:
			var turning := (points[i] - points[before]).cross(points[after] - points[i])
			# A clockwise turn (positive cross, y down) has its outside on the normal's side
			# (orthogonal() points left of travel); keep the last side on straights.
			if absf(turning) > 0.02: side = signf(turning)
		sides[i] = side
	return {"points": points, "times": times, "widths": widths, "strokes": strokes, "kinds": kinds, "commands": command_of,
		"palettes": palettes, "normals": normals, "sides": sides, "joints": joints, "bursts": bursts, "contacts": contacts, "gathers": gathers, "total": time}

static func ease_swing(t: float) -> float:
	# Fast through the middle and a short settle at the end, like a struck blow.
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2.4)

## A palette by name, as the style overrides it.
static func palette_of(name: StringName) -> Array:
	return ComboStyle.palette(name, PALETTES[name])

func configure(preset: Dictionary) -> PixelSlash:
	for key: String in preset:
		if key == "palette": palette = palette_of(preset.palette)
		else: set(key, preset[key])
	return self

func _ready() -> void:
	age = -delay
	# The style's thickness scales every band; the pixel grain follows the style too.
	width *= ComboStyle.thickness
	line_width *= ComboStyle.thickness
	width_scale *= ComboStyle.thickness
	PIXEL = ComboStyle.pixel
	if shape == &"path": _path = build_path(path, path_squash, path_tilt)
	if shape == &"sparks": _particles = make_particles()
	var size := Vector2i.ONE * (ceili(_reach() / PIXEL) * 2 + 4)
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_canvas = Node2D.new()
	_canvas.position = Vector2(size) / 2.0
	_canvas.draw.connect(_draw_slash)
	_viewport.add_child(_canvas)
	_display = Sprite2D.new()
	_display.texture = _viewport.get_texture()
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.scale = Vector2.ONE * PIXEL
	add_child(_display)
	_samples.append(Vector2(_u0(), 0.0))

## Furthest any part of the slash can reach from this node, plus a margin.
func _reach() -> float:
	var outer := line_gap + line_width + 8.0
	match shape:
		&"line": return maxf(from_point.length(), to_point.length()) + width + outer
		&"burst": return center.length() + radius * 1.6 + width + outer
		&"crescent": return center.length() + radius * maxf(1.0, squash) + line_gap * 3.0 + line_width + 48.0
		&"star": return center.length() + radius * 1.4 + width + outer
		&"sparks":
			var life := spark_life.y
			return center.length() + spark_speed.y * life + absf(spark_gravity) * life * life * 0.5 + outer
		&"path":
			var far := 0.0
			for p: Vector2 in _path.points: far = maxf(far, p.length())
			var widest := 0.0
			for w: float in _path.widths: widest = maxf(widest, w)
			return far + widest * width_scale + outer
	return center.length() + radius + outer

func _u0() -> float: return 0.0 if shape in [&"line", &"path"] else start_angle
func _u1() -> float: return 1.0 if shape == &"line" else end_angle

func is_done() -> bool:
	if shape == &"burst": return age >= duration + tail
	if shape == &"sparks": return age >= spark_life.y
	if shape in [&"crescent", &"star"]: return age >= duration + hold + fade
	return not _swinging and _samples.is_empty()

func tip_param() -> float:
	return lerpf(_u0(), _u1(), ease_swing(age / duration))

func advance(delta: float) -> void:
	if delta <= 0.0 or is_done(): return
	age += delta
	if age <= 0.0: return
	if shape == &"path":
		var times: PackedFloat32Array = _path.times
		while _next_point < times.size() and times[_next_point] <= age:
			_samples.append(Vector2(_next_point, times[_next_point]))
			_next_point += 1
		if _next_point >= times.size(): _swinging = false
		while not _samples.is_empty() and age - _samples[0].y >= tail:
			_samples.pop_front()
	elif shape in [&"arc", &"line"]:
		if _swinging:
			# The tip stops at `duration`; a long step must not stamp late births on the path.
			var target := tip_param()
			var last := _samples[-1].x
			var from_time := _samples[-1].y
			var to_time := minf(age, duration)
			var limit := MAX_LINE_STEP if shape == &"line" else MAX_ARC_STEP
			var steps := maxi(1, ceili(absf(target - last) / limit))
			for i in range(1, steps + 1):
				var t := float(i) / steps
				_samples.append(Vector2(lerpf(last, target, t), lerpf(from_time, to_time, t)))
			if age >= duration: _swinging = false
		while not _samples.is_empty() and age - _samples[0].y >= tail:
			_samples.pop_front()
	if is_instance_valid(_canvas): _canvas.queue_redraw()
	if is_done(): finished.emit()

## 1 for a fresh sample, falling to 0 as it reaches the end of the tail. Slightly
## faster than linear, so the old end tapers to a point instead of a blunt block.
func _strength(sample: Vector2) -> float:
	return pow(clampf(1.0 - (age - sample.y) / tail, 0.0, 1.0), 1.4)

## Path position at parameter u, offset d across it (arc: distance from the centre;
## line: signed distance from the axis). Returned in slash texels, mirrored by facing.
func _point(u: float, d: float) -> Vector2:
	var p: Vector2
	if shape == &"path":
		var points: PackedVector2Array = _path.points
		var normals: PackedVector2Array = _path.normals
		var i := clampi(int(u), 0, points.size() - 1)
		p = points[i] + normals[i] * d
	elif shape == &"line":
		var axis := to_point - from_point
		p = from_point + axis * u + axis.normalized().orthogonal() * d
	else:
		p = center + Vector2(cos(u) * d, sin(u) * d * squash).rotated(tilt)
	p.x *= facing
	return p / PIXEL

func _band(a: float, b: float, inner_a: float, outer_a: float, inner_b: float, outer_b: float, color: Color) -> void:
	if absf(outer_a - inner_a) < 0.5 and absf(outer_b - inner_b) < 0.5: return
	# At a finished tip, consecutive samples can collapse onto the same point.
	if is_equal_approx(a, b): return
	var polygon := PackedVector2Array([_point(a, inner_a), _point(a, outer_a), _point(b, outer_b), _point(b, inner_b)])
	if Geometry2D.triangulate_polygon(polygon).is_empty(): return
	_canvas.draw_colored_polygon(polygon, color)

func _shade(strength: float) -> Color:
	# Discrete steps rather than a smooth fade: new parts bright, old parts dark.
	if strength > 0.66: return palette[1]
	if strength > 0.33: return palette[2]
	return palette[3]

func _draw_slash() -> void:
	if age <= 0.0: return
	match shape:
		&"burst": _draw_burst()
		&"sparks": _draw_sparks()
		&"crescent": _draw_crescent()
		&"star": _draw_star()
		&"line": _draw_line_trail()
		&"path": _draw_path_trail()
		_: _draw_arc_trail()

func _draw_arc_trail() -> void:
	for i in range(1, _samples.size()):
		var a := _samples[i - 1]
		var b := _samples[i]
		var sa := _strength(a)
		var sb := _strength(b)
		# The band narrows toward the outer edge as it ages; the inside is the darker rim.
		var wa := width * sa
		var wb := width * sb
		var shade := _shade((sa + sb) * 0.5)
		_band(a.x, b.x, radius - wa, radius, radius - wb, radius, shade)
		_band(a.x, b.x, radius - wa, radius - wa * 0.72, radius - wb, radius - wb * 0.72, palette[3] if shade != palette[3] else palette[3].darkened(0.3))
		_band(a.x, b.x, radius - maxf(wa * 0.18, PIXEL), radius, radius - maxf(wb * 0.18, PIXEL), radius, palette[0] if sa > 0.5 else palette[1])
		var line_r := radius + line_gap
		_band(a.x, b.x, line_r, line_r + line_width * sa, line_r, line_r + line_width * sb, palette[1] if sa > 0.5 else palette[2])
	if _swinging and _samples.size() >= 2:
		# Leading edge: the newest few degrees at full width in the brightest colour.
		var tip := _samples[-1].x
		var back := tip - signf(end_angle - start_angle) * deg_to_rad(9.0)
		_band(back, tip, radius - width * 0.9, radius + line_gap + line_width, radius - width, radius + line_gap + line_width, palette[0])

func _draw_line_trail() -> void:
	for i in range(1, _samples.size()):
		var a := _samples[i - 1]
		var b := _samples[i]
		var sa := _strength(a)
		var sb := _strength(b)
		var ha := width * sa * 0.5
		var hb := width * sb * 0.5
		_band(a.x, b.x, -ha, ha, -hb, hb, _shade((sa + sb) * 0.5))
		_band(a.x, b.x, -ha, -ha * 0.55, -hb, -hb * 0.55, palette[3])
		var ca := maxf(ha * 0.3, PIXEL * 0.5)
		var cb := maxf(hb * 0.3, PIXEL * 0.5)
		_band(a.x, b.x, -ca, ca, -cb, cb, palette[0] if sa > 0.5 else palette[1])
		# Speed lines on both sides; they thin out with the tail like the band.
		for side: float in [-1.0, 1.0]:
			var ga := side * (ha + line_gap)
			var gb := side * (hb + line_gap)
			_band(a.x, b.x, ga, ga + side * line_width * sa, gb, gb + side * line_width * sb, palette[1] if sa > 0.5 else palette[2])
	if arrow_head and _swinging and _samples.size() >= 2:
		# Arrow head just ahead of the tip.
		var tip := _samples[-1].x
		var head := width * 0.9 / maxf((to_point - from_point).length(), 1.0)
		_canvas.draw_colored_polygon(PackedVector2Array([_point(tip + head, 0.0), _point(tip - head * 0.4, width * 0.7), _point(tip - head * 0.15, 0.0), _point(tip - head * 0.4, -width * 0.7)]), palette[0])

func _draw_burst() -> void:
	var t := clampf(age / duration, 0.0, 1.0)
	var fade := clampf((age - duration) / maxf(tail, 0.001), 0.0, 1.0)
	var r := radius * ease_swing(t)
	var thickness := maxf(width * (1.0 - fade) * (1.0 - 0.5 * t), PIXEL * 0.5)
	var colour: Color = palette[0] if fade < 0.3 else (palette[1] if fade < 0.66 else palette[2])
	var c := center
	c.x *= facing
	var steps := 24
	for i in steps:
		var a := Vector2.from_angle(TAU * i / steps) * Vector2(1.0, squash)
		var b := Vector2.from_angle(TAU * (i + 1) / steps) * Vector2(1.0, squash)
		var inner := maxf(r - thickness, 0.0)
		_canvas.draw_colored_polygon(PackedVector2Array([(c + a * inner) / PIXEL, (c + a * r) / PIXEL, (c + b * r) / PIXEL, (c + b * inner) / PIXEL]), colour)
	# Spikes: long thin rays just outside the ring, shrinking as it fades.
	var spike := radius * 0.55 * (1.0 - fade)
	if spike < PIXEL or burst_spikes <= 0: return
	for i in burst_spikes:
		var dir := Vector2.from_angle(TAU * i / burst_spikes + PI / burst_spikes)
		var side := dir.orthogonal() * maxf(thickness * 0.5, PIXEL)
		var base := c + dir * (r + line_gap)
		_canvas.draw_colored_polygon(PackedVector2Array([(base + side) / PIXEL, (base + dir * spike) / PIXEL, (base - side) / PIXEL]), palette[1] if fade < 0.5 else palette[2])

## Colours for a path point: its command's palette override, else the slash's own.
func _colours(index: int) -> Array:
	var key: StringName = (_path.palettes as Array)[index]
	return palette if key == &"" else palette_of(key)

## Index of the command whose stroke is flashing white now, or -1.
func _flashing_command() -> int:
	for contact: Dictionary in _path.contacts:
		if contact.flash > 0.0 and age >= contact.time and age < contact.time + contact.flash: return contact.command
	return -1

func _draw_path_trail() -> void:
	var widths: PackedFloat32Array = _path.widths
	var strokes: PackedInt32Array = _path.strokes
	var sides: PackedFloat32Array = _path.sides
	var kinds: PackedByteArray = _path.kinds
	var commands: PackedInt32Array = _path.commands
	var flashing := _flashing_command()
	for i in range(1, _samples.size()):
		var a := _samples[i - 1]
		var b := _samples[i]
		var ia := int(a.x)
		var ib := int(b.x)
		if strokes[ia] != strokes[ib]: continue  # the blade lifted between these points
		var sa := _strength(a)
		var sb := _strength(b)
		var ha := widths[ia] * width_scale * sa * 0.5
		var hb := widths[ib] * width_scale * sb * 0.5
		var side := sides[ib]
		var colours := _colours(ib)
		match kinds[ib]:
			Kind.CARRY:
				# The blade between strikes: one thin dim band, no rim, edge or line.
				_band(a.x, b.x, -ha, ha, -hb, hb, colours[2] if sa > 0.5 else colours[3])
				continue
			Kind.CHARGE:
				var shimmer := int(age / CHARGE_FLICKER) % 2 == 0
				_band(a.x, b.x, -ha, ha, -hb, hb, (colours[0] if shimmer else colours[1]) if sa > 0.4 else colours[2])
				if line_width > 0.0:
					_band(a.x, b.x, side * (ha + line_gap), side * (ha + line_gap + line_width * sa), side * (hb + line_gap), side * (hb + line_gap + line_width * sb), colours[1])
				continue
		if commands[ib] == flashing:
			# Contact flash: the whole stroke of the landing blow reads as one white cut.
			_band(a.x, b.x, -ha * 1.15, ha * 1.15, -hb * 1.15, hb * 1.15, colours[0])
			continue
		var shade: Color = colours[1] if (sa + sb) * 0.5 > 0.66 else (colours[2] if (sa + sb) * 0.5 > 0.33 else colours[3])
		_band(a.x, b.x, -ha, ha, -hb, hb, shade)
		# Dark rim on the inside of the turn, bright edge and thin line on the outside.
		_band(a.x, b.x, -side * ha, -side * ha * 0.44, -side * hb, -side * hb * 0.44, colours[3])
		_band(a.x, b.x, side * maxf(ha - maxf(ha * 0.36, PIXEL * 0.5), 0.0), side * ha, side * maxf(hb - maxf(hb * 0.36, PIXEL * 0.5), 0.0), side * hb, colours[0] if sa > 0.5 else colours[1])
		if line_width > 0.0:
			_band(a.x, b.x, side * (ha + line_gap), side * (ha + line_gap + line_width * sa), side * (hb + line_gap), side * (hb + line_gap + line_width * sb), colours[1] if sa > 0.5 else colours[2])
	if _swinging and _samples.size() >= 2:
		# Leading edge: the newest few points at full width in the brightest colour.
		for i in range(maxi(1, _samples.size() - PATH_TIP_POINTS), _samples.size()):
			var ia := int(_samples[i - 1].x)
			var ib := int(_samples[i].x)
			if strokes[ia] != strokes[ib]: continue
			var ha := widths[ia] * width_scale * 0.5
			var hb := widths[ib] * width_scale * 0.5
			_band(_samples[i - 1].x, _samples[i].x, -ha, ha, -hb, hb, _colours(ib)[0])

## The spray, fixed by spark_seed: velocity (facing-forward), life per shard.
func make_particles() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = spark_seed
	var list: Array[Dictionary] = []
	for i in spark_count:
		var angle := spark_dir + rng.randf_range(-spark_spread, spark_spread)
		list.append({"velocity": Vector2.from_angle(angle) * rng.randf_range(spark_speed.x, spark_speed.y),
			"life": rng.randf_range(spark_life.x, spark_life.y)})
	return list

func _spark_at(particle: Dictionary, t: float) -> Vector2:
	var p: Vector2 = center + particle.velocity * t + Vector2(0, spark_gravity) * t * t * 0.5
	if spark_converge: p = center + particle.velocity * (float(particle.life) - t)
	p.x = center.x * facing + (p.x - center.x) * facing
	return p / PIXEL

func _draw_sparks() -> void:
	for particle in _particles:
		var life: float = particle.life
		if age >= life: continue
		var fraction := age / life
		var colour: Color = palette[0] if fraction < 0.3 else (palette[1] if fraction < 0.65 else palette[2])
		var head := _spark_at(particle, age)
		if not spark_streak:
			_canvas.draw_rect(Rect2(head.floor(), Vector2.ONE), colour)
			continue
		# A short streak back along its motion, one texel thick.
		var tail_point := _spark_at(particle, maxf(age - 0.03, 0.0))
		var across := (head - tail_point).normalized().orthogonal() * 0.5
		if (head - tail_point).length() < 0.5:
			_canvas.draw_rect(Rect2(head.floor(), Vector2.ONE), colour)
			continue
		_canvas.draw_colored_polygon(PackedVector2Array([tail_point - across, head - across, head + across, tail_point + across]), colour)

## 0..1 through the fade (0 while opening or holding).
func _fade_fraction() -> float:
	return clampf((age - duration - hold) / maxf(fade, 0.001), 0.0, 1.0)

## Thickness profile along a crescent: zero at both ends, full in the middle.
static func lens(along: float) -> float:
	return pow(sin(PI * clampf(along, 0.0, 1.0)), 0.6)

## One crescent layer between fractions `from_s`..`to_s` of the arc. `inner` is how far the
## layer reaches in from the outer edge (`radius_at`), as a share of the lens thickness.
func _crescent_layer(from_s: float, to_s: float, radius_at: float, thickness: float, inner: float, colour: Color) -> void:
	if to_s - from_s <= 0.0005 or thickness * inner < 0.5: return
	var sweep := end_angle - start_angle
	var steps := maxi(2, ceili(absf(sweep) * (to_s - from_s) / deg_to_rad(3.0)))
	var outer := PackedVector2Array()
	var inside := PackedVector2Array()
	for i in steps + 1:
		var along := lerpf(from_s, to_s, float(i) / steps)
		var angle := start_angle + sweep * along
		outer.append(_point(angle, radius_at))
		inside.append(_point(angle, radius_at - thickness * inner * lens(along)))
	inside.reverse()
	var polygon := outer + inside
	if polygon.size() >= 3 and not Geometry2D.triangulate_polygon(polygon).is_empty():
		_canvas.draw_colored_polygon(polygon, colour)

func _draw_crescent() -> void:
	var open := ease_swing(age / duration)
	var f := _fade_fraction()
	# Fading erodes the old end toward the tip and thins what is left.
	var from_s := pow(f, 0.8)
	var thick := width * (1.0 - f * 0.6)
	# Inner ghost: a smaller, darker copy one frame behind.
	var ghost := ease_swing((age - 1.0 / 60.0) / duration)
	_crescent_layer(from_s, ghost, radius * 0.84, thick * 0.55, 1.0, palette[3])
	_crescent_layer(from_s, open, radius, thick, 1.0, palette[2])
	if f < 0.7: _crescent_layer(from_s, open, radius, thick, 0.62, palette[1])
	if f < 0.35: _crescent_layer(from_s, open, radius, thick, 0.28, palette[0])
	# Outer echo line, a frame after the blade.
	if age > duration * 0.5 and f < 0.85:
		var line_r := radius + line_gap + line_width
		_crescent_layer(from_s, open * 0.96, line_r, line_width / maxf(lens(0.5), 0.01), 1.0, palette[1] if f < 0.4 else palette[2])
	if f <= 0.0: return
	# Speed lines thrown off the outer edge as the cut fades.
	var sweep := end_angle - start_angle
	for k in SPEED_LINES:
		var along := (k + 0.5) / SPEED_LINES
		if along < from_s: continue
		var angle := start_angle + sweep * along
		var r0 := radius + line_gap * 2.0 + 30.0 * f
		var r1 := r0 + 26.0 * (1.0 - f) * lens(along)
		var a := _point(angle, r0)
		var b := _point(angle, r1)
		if a.distance_to(b) < 0.6: continue
		var across := (b - a).normalized().orthogonal() * 0.5
		_canvas.draw_colored_polygon(PackedVector2Array([a - across, b - across, b + across, a + across]), palette[1] if f < 0.5 else palette[2])

func _draw_star() -> void:
	var open := ease_swing(age / duration)
	var f := _fade_fraction()
	var c := center
	c.x *= facing
	c /= PIXEL
	var rays := maxi(burst_spikes, 4)
	for i in rays:
		var long_ray := i % 2 == 0
		var dir := Vector2.from_angle(spark_dir + TAU * i / rays)
		dir.x *= facing
		var length := radius * open * (1.0 if long_ray else 0.5) * (1.0 - f * 0.6) / PIXEL
		var base := width * (1.0 - f) * (0.6 if long_ray else 0.4) / PIXEL
		if length < 0.6 or base < 0.2: continue
		var side := dir.orthogonal() * maxf(base, 0.5)
		var colour: Color = (palette[0] if long_ray else palette[1]) if f < 0.4 else palette[2]
		_canvas.draw_colored_polygon(PackedVector2Array([c + side, c + dir * length, c - side]), colour)
	# White core, then a thin ring that opens past the rays.
	var core := width * 0.9 * (1.0 - f) / PIXEL
	if core >= 0.6: _canvas.draw_circle(c, core, palette[0])
	# A thin ring just inside the long rays, gone early in the fade.
	var ring := radius * 0.7 * open * (0.9 + f * 0.5) / PIXEL
	if f < 0.4: _canvas.draw_arc(c, ring, 0.0, TAU, 24, palette[1], 1.0)
