extends Node2D
## One ground impact: a front travels over a footprint on the ground (radial, sweep, split
## or cone), tearing cracks, raising material bodies, throwing debris and dust, with a
## flash and screen shake on every push. All layout comes from the event's seed and all
## motion from `age`, so any frame can be rebuilt exactly (the editor scrubs this way).
##
## Shapes are drawn in values, not colours; each layer's shader maps them through the
## material's ramp (or the event's 配色) in the combo's 画风 (style.json "quake_style":
## real 写实 / cel 赛璐璐 / pixel 像素) and 精细度 ("quake_detail": balanced 均衡 / fine 精细 /
## ultimate 极致 / explosive 炸裂, which adds a heat-warp of the shockwave).
## Without a graphics card (RenderCaps.fallback) it always runs 写实 + 均衡 with the light
## (lite) shader patterns, fewer particles, smaller soft glows and no heat-warp.
const Profile = preload("res://vfx/quake/propagation.gd")
const Materials = preload("res://vfx/quake/materials.gd")
const S = preload("res://vfx/quake/shapes.gd")
const Tex = preload("res://vfx/quake/textures.gd")
const DEFAULTS = Profile.DEFAULTS
const MAX_BODIES := 90
const MAX_DEBRIS := 200
const MAX_PUFFS := 70
const SHADER := preload("res://vfx/quake/shaders/quake.gdshader")
const SHADER_ADD := preload("res://vfx/quake/shaders/quake_add.gdshader")
const PIXEL := preload("res://vfx/quake/shaders/pixel.gdshader")
const WARP := preload("res://vfx/quake/shaders/warp.gdshader")
const SOLID := preload("res://vfx/quake/shaders/solid.gdshader")
const Solid = preload("res://vfx/quake/solid.gd")
const Chunks = preload("res://vfx/quake/chunks.gd")
const CHUNKS := preload("res://vfx/quake/shaders/chunks.gdshader")
const GpuLayers = preload("res://vfx/quake/gpu_layers.gd")
const CRACKS := preload("res://vfx/quake/shaders/cracks.gdshader")
const CRACKS_ADD := preload("res://vfx/quake/shaders/cracks_add.gdshader")
const SPRITES := preload("res://vfx/quake/shaders/sprites.gdshader")
const SPRITES_ADD := preload("res://vfx/quake/shaders/sprites_add.gdshader")
const PATCHES := preload("res://vfx/quake/shaders/patches.gdshader")

class Layer extends Node2D:
	## When on (tools/bench_quake.gd), microseconds of script drawing per layer name.
	static var profile := false
	static var spent := {}
	var paint: Callable
	func _draw() -> void:
		if not profile:
			paint.call(self)
			return
		var start := Time.get_ticks_usec()
		paint.call(self)
		spent[name] = int(spent.get(name, 0)) + Time.get_ticks_usec() - start

var spec: Dictionary
var pal: Dictionary
var kind := "rock"
var age := 0.0
var life := 0.0
var radius := 110.0
var stretch := 0.0
var bodies: Array[Dictionary] = []
var cracks: Array[Dictionary] = []
var debris: Array[Dictionary] = []
var puffs: Array[Dictionary] = []
var pulses: Array[Dictionary] = []
var layers: Dictionary = {}
var style := "real"
var detail := "explosive"
## 兜底: running on a software renderer.
var lite := false
## While style is pixel: [SubViewport, lens, display].
var _pixel: Array = []

static func normalized(event: Dictionary) -> Dictionary:
	return Profile.normalized(event)

static func propagation_duration(event: Dictionary) -> float:
	return Profile.duration(normalized(event))

# --- Layout ----------------------------------------------------------------------------------

func configure(event: Dictionary) -> Node2D:
	spec = normalized(event)
	position = Vector2(float(spec.x), float(spec.y))
	radius = float(spec.width) * 0.5
	stretch = float(spec.length)
	pal = Materials.palette(String(spec.unit), String(spec.dust_color))
	kind = String(pal.body)
	RenderCaps.detect()
	lite = RenderCaps.fallback
	S.glow_limit = 320.0 if lite else 0.0
	style = String(ComboStyle.data.get("quake_style", "real"))
	detail = String(ComboStyle.data.get("quake_detail", "explosive"))
	if not style in Materials.STYLES: style = "real"
	if not detail in Materials.DETAILS: detail = "explosive"
	life = Profile.lifetime(spec)
	pulses = Profile.pulses(spec)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	_build_bodies(rng)
	_build_cracks(rng)
	_build_debris(rng)
	_build_dust(rng)
	_build_layers()
	if kind in ["rock", "crystal"]: _build_solids()
	_build_chunks()
	_build_gpu_layers()
	return self

func _build_layers() -> void:
	var ramp := Materials.ramp(String(spec.unit), spec.ramp)
	for item in [["decal", -3, _paint_decal, false], ["ground_glow", -2, _paint_ground_glow, true],
			["back", -1, _paint_back_dust, false], ["body", 0, _paint_bodies, false],
			["front", 1, _paint_front_dust, false], ["glow", 2, _paint_glow, true]]:
		var layer := Layer.new()
		layer.name = String(item[0]).to_pascal_case()
		layer.z_index = item[1]
		layer.paint = item[2]
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var shading := ShaderMaterial.new()
		shading.shader = SHADER_ADD if item[3] else SHADER
		shading.set_shader_parameter("ramp", ramp)
		if item[0] in ["back", "front"]:
			shading.set_shader_parameter("mode", 1)
			shading.set_shader_parameter("tint", pal.dust_tint)
		layer.material = shading
		add_child(layer)
		layers[item[0]] = layer
	var warp := Layer.new()
	warp.name = "Warp"
	warp.z_index = 3
	warp.paint = _paint_warp
	var bending := ShaderMaterial.new()
	bending.shader = WARP
	warp.material = bending
	add_child(warp)
	layers.warp = warp
	set_look(style, detail)

## Switches 画风 live (keeps the clock). 精细度 changes counts, so a different detail tier
## only takes full effect on the next configure; its shader side applies at once.
func set_look(new_style: String, new_detail: String) -> void:
	style = new_style if new_style in Materials.STYLES else "real"
	detail = new_detail if new_detail in Materials.DETAILS else "explosive"
	if lite:
		style = "real"
		detail = "balanced"
	var octaves: float = {"balanced": 0.3, "fine": 0.6, "ultimate": 1.0, "explosive": 1.0}[detail]
	for key: String in layers:
		if key == "warp": continue
		var shading := (layers[key] as Node2D).material as ShaderMaterial
		shading.set_shader_parameter("style", Materials.STYLES.find(style))
		shading.set_shader_parameter("detail", octaves)
		shading.set_shader_parameter("lite", lite)
	(layers.warp as Node2D).visible = detail == "explosive" and style != "pixel" and not lite
	_apply_pixel()

## 像素: the layers draw into a small viewport covering the stage, shown at pixel grain.
func _apply_pixel() -> void:
	var want := style == "pixel"
	if want == not _pixel.is_empty(): return
	if not want:
		for key: String in layers: (layers[key] as Node2D).reparent(self, false)
		# The lens lives inside the viewport and goes with it.
		(_pixel[0] as Node).free()
		(_pixel[2] as Node).free()
		_pixel.clear()
		return
	var grain := maxf(ComboStyle.pixel, 1.0)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(ceili(1280.0 / grain), ceili(720.0 / grain))
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var lens := Node2D.new()
	lens.scale = Vector2.ONE / grain
	lens.position = position / grain
	viewport.add_child(lens)
	for key: String in layers: (layers[key] as Node2D).reparent(lens, false)
	var display := Sprite2D.new()
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.centered = false
	display.position = -position
	display.scale = Vector2.ONE * grain
	var banding := ShaderMaterial.new()
	banding.shader = PIXEL
	display.material = banding
	add_child(display)
	_pixel = [viewport, lens, display]

func _detail_scale() -> float:
	return float(Materials.DETAIL_SCALE[detail]) * (0.6 if lite else 1.0)

## Half the footprint's length along its axis (straight part plus the round caps).
func extent() -> float:
	return stretch * 0.5 + radius

func reach() -> float:
	return float(spec.width) + stretch

func half_width(u: float) -> float:
	return sqrt(maxf(radius * radius - pow(maxf(absf(u) - stretch * 0.5, 0.0), 2.0), 0.0))

func inside(p: Vector2) -> bool:
	if spec.mode == "cone":
		return p.length() <= reach() + 0.001 and absf(p.angle()) <= deg_to_rad(float(spec.cone)) * 0.5 + 0.0001
	return Vector2(maxf(absf(p.x) - stretch * 0.5, 0.0), p.y).length() <= radius + 0.001

## Distance along the outline from the centre in direction `a` (radial footprint).
func rim(a: float) -> float:
	var direction := Vector2.from_angle(a)
	var lo := 0.0
	var hi := extent() + 1.0
	for i in 18:
		var middle := (lo + hi) * 0.5
		if inside(direction * middle): lo = middle
		else: hi = middle
	return lo

## Travelled fraction (0–1) at which the front reaches ground point `p`.
func distance_at(p: Vector2) -> float:
	var d := 0.0
	match spec.mode:
		"sweep": d = clampf((p.x + extent()) / (extent() * 2.0), 0.0, 1.0)
		"split": d = clampf(absf(p.x) / extent(), 0.0, 1.0)
		"cone": d = clampf(p.length() / reach(), 0.0, 1.0)
		_:
			var r := rim(p.angle())
			d = clampf(p.length() / maxf(r, 0.001), 0.0, 1.0)
	return 1.0 - d if bool(spec.reverse) else d

func arrival(p: Vector2) -> float:
	return Profile.arrival(spec, distance_at(p))

## Ground plane → screen (relative to the event): rotate, then flatten into perspective.
func ground(p: Vector2) -> Vector2:
	var rotated := p.rotated(deg_to_rad(float(spec.angle)))
	return Vector2(rotated.x, rotated.y * float(spec.perspective))

## Screen direction in which the front moves through ground point `p`.
func outward(p: Vector2) -> Vector2:
	var forward := Vector2.RIGHT
	match spec.mode:
		"sweep": forward = Vector2.RIGHT
		"split": forward = Vector2(signf(p.x) if absf(p.x) > 0.01 else 1.0, 0.0)
		_: forward = p.normalized() if p.length() > 0.01 else Vector2.RIGHT
	if bool(spec.reverse): forward = -forward
	var screen := ground(forward)
	return screen.normalized() if screen.length() > 0.0001 else Vector2.RIGHT

func _add_body(p: Vector2, rng: RandomNumberGenerator, scale := 1.0) -> void:
	if bodies.size() >= MAX_BODIES: return
	var d := distance_at(p)
	var g := Profile.gain(spec, d)
	var base := clampf(minf(radius, 130.0) * 0.5, 22.0, 65.0) * float(spec.unit_size) * Profile.body_scale(spec, d)
	var dir := outward(p)
	bodies.append({"p": p, "d": d, "birth": Profile.arrival(spec, d) + rng.randf_range(0.0, 0.025),
		"size": base * scale * rng.randf_range(0.72, 1.18) * sqrt(maxf(g, 0.05)), "seed": rng.randf_range(0.0, 1000.0),
		"gain": g, "lean": clampf(dir.x * 0.8 + rng.randf_range(-0.3, 0.3), -1.0, 1.0)})

func _build_bodies(rng: RandomNumberGenerator) -> void:
	var spacing := float(spec.spacing)
	if spec.mode in ["radial", "cone"]:
		var cone: bool = spec.mode == "cone"
		var outer := reach() if cone else extent()
		var half := deg_to_rad(float(spec.cone)) * 0.5
		var rings := clampi(roundi(outer / spacing), 1, 8)
		if not cone and kind in ["crystal", "lava", "beam", "bolt"]: _add_body(Vector2.ZERO, rng, 1.35)
		for k in rings:
			var d := clampf((k + 0.6 + rng.randf_range(-0.15, 0.15)) / (rings + 0.25), 0.08, 0.97)
			var around := outer * d * half * 2.0 if cone else TAU * radius * d + 2.0 * stretch * d
			var count := maxi(1 if cone else 3, roundi(around / spacing))
			for j in count:
				var a := (j + rng.randf_range(0.2, 0.8)) / count
				var angle := lerpf(-half, half, a) if cone else a * TAU
				var r := outer * d if cone else rim(angle) * d
				_add_body(Vector2.from_angle(angle) * r, rng, 1.15 - 0.3 * d)
	else:
		var columns := clampi(ceili(extent() * 2.0 / spacing), 1, 45)
		var side := 1.0
		for i in columns:
			var u := lerpf(-extent(), extent(), (i + 0.5) / columns) + rng.randf_range(-0.2, 0.2) * spacing
			var w := half_width(u)
			if w < 4.0: continue
			if radius < 60.0:
				_add_body(Vector2(u, rng.randf_range(-0.3, 0.3) * w), rng)
			else:
				for k in 2:
					_add_body(Vector2(u + rng.randf_range(-0.2, 0.2) * spacing, side * rng.randf_range(0.2, 0.68) * w), rng, 1.0 if k == 0 else 0.75)
					side = -side
	if bodies.is_empty(): _add_body(Vector2.ZERO, rng)
	_pick_strikes()
	bodies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ground(a.p).y < ground(b.p).y)

## Lightning lands on a few bodies, spaced in time, rather than on every one.
func _pick_strikes() -> void:
	var order := bodies.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.birth) < float(b.birth))
	var gap: float = {"sky": 0.07, "pillar": 0.12, "ground": 0.0, "eruption": 0.16}.get(String(spec.form), 0.0)
	var last := -1.0
	for body: Dictionary in order:
		body.strike = last < 0.0 or float(body.birth) - last >= gap
		if body.strike: last = float(body.birth)
	for i in order.size(): order[i].order = i

## A jagged crack from `from` heading `direction` for `length` (ground plane units).
func _crack(from: Vector2, direction: Vector2, length: float, width: float, jag: float, rng: RandomNumberGenerator, main := false) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var steps := clampi(ceili(length / 16.0), 3, 14)
	var heading := direction.normalized()
	var at := from
	for i in steps:
		heading = heading.rotated(rng.randf_range(-0.55, 0.55) * jag).lerp(direction.normalized(), 0.35).normalized()
		at += heading * length / steps
		pts.append(at)
	var arrivals := PackedFloat32Array()
	var widths := PackedFloat32Array()
	for i in pts.size():
		arrivals.append(arrival(pts[i]))
		var u := float(i) / (pts.size() - 1)
		widths.append(width * (1.0 - pow(u, 1.6) * 0.85))
	cracks.append({"pts": pts, "arr": arrivals, "w": widths, "main": main})
	return pts

func _build_cracks(rng: RandomNumberGenerator) -> void:
	if not bool(spec.cracks) or float(spec.crack_amount) <= 0.0: return
	var amount := float(spec.crack_amount)
	var width := clampf(radius * 0.045, 2.5, 7.0) * sqrt(float(spec.strength)) * (1.8 if kind == "blade" else 1.0)
	var jag := 0.25 if kind == "blade" else 1.0
	if spec.mode in ["radial", "cone"]:
		var cone: bool = spec.mode == "cone"
		var half := deg_to_rad(float(spec.cone)) * 0.5
		var rays := clampi(roundi((4.0 if cone else 8.0) * amount), 2, 20)
		for i in rays:
			var a := lerpf(-half, half, (i + rng.randf_range(0.25, 0.75)) / rays) if cone else (i + rng.randf_range(0.2, 0.8)) * TAU / rays
			var length := (reach() if cone else rim(a)) * rng.randf_range(0.7, 1.0)
			var start := Vector2.from_angle(a) * minf(radius * 0.12, length * 0.15)
			var pts := _crack(start, Vector2.from_angle(a), length, width, jag, rng, true)
			if rng.randf() < 0.75 * minf(amount, 1.0):
				var from := pts[clampi(roundi(pts.size() * rng.randf_range(0.35, 0.6)), 1, pts.size() - 2)]
				_crack(from, Vector2.from_angle(a + rng.randf_range(0.4, 0.8) * (-1.0 if rng.randf() < 0.5 else 1.0)), length * rng.randf_range(0.25, 0.4), width * 0.6, jag, rng)
		if not cone and kind in ["rock", "lava"]:
			# A broken rim around the point of impact.
			var pit := PackedVector2Array()
			var arrivals := PackedFloat32Array()
			var widths := PackedFloat32Array()
			var r := minf(radius * 0.2, extent() * 0.3)
			for i in 15:
				var a := TAU * i / 14.0
				var p := Vector2.from_angle(a) * r * (0.85 + rng.randf() * 0.3)
				if i == 14: p = pit[0]
				pit.append(p)
				arrivals.append(arrival(p))
				widths.append(width * 0.7)
			cracks.append({"pts": pit, "arr": arrivals, "w": widths})
	else:
		var main_jag := 0.12 if kind == "blade" else 0.35
		var axes := [1.0] if spec.mode == "sweep" else [1.0, -1.0]
		for axis: float in axes:
			var from := Vector2(-extent() * 0.96, 0.0) if spec.mode == "sweep" else Vector2.ZERO
			var length := extent() * (1.92 if spec.mode == "sweep" else 0.96)
			_crack(from, Vector2(axis, 0), length, width * 1.25, main_jag, rng, true)
		var forward := -1.0 if bool(spec.reverse) else 1.0
		var branches := clampi(roundi(extent() * 2.0 / maxf(float(spec.spacing), 30.0) * amount * (0.4 if kind == "blade" else 1.0)), 0, 30)
		for i in branches:
			var u := lerpf(-extent() * 0.9, extent() * 0.9, (i + rng.randf_range(0.2, 0.8)) / branches)
			var w := half_width(u)
			if w < 6.0: continue
			var side := -1.0 if i % 2 == 0 else 1.0
			var heading := forward * (signf(u) if spec.mode == "split" else 1.0)
			_crack(Vector2(u, rng.randf_range(-0.1, 0.1) * w), Vector2(heading * rng.randf_range(0.6, 1.4), side), w * rng.randf_range(0.55, 1.0), width * 0.65, jag, rng)

func _debris_kind() -> String:
	return String(pal.debris) if spec.debris == "auto" else String(spec.debris)

func _build_debris(rng: RandomNumberGenerator) -> void:
	var type := _debris_kind()
	if type == "none" or float(spec.debris_density) <= 0.0: return
	var per: float = {"stone": 1.6, "ice": 2.0, "ember": 3.0, "spark": 3.0, "mote": 2.5}[type] * float(spec.debris_density) * _detail_scale()
	for body: Dictionary in bodies:
		var count := floori(per + rng.randf())
		for i in count:
			if debris.size() >= MAX_DEBRIS: return
			var g := float(body.gain)
			var high := float(spec.debris_height) * sqrt(maxf(g, 0.1)) * rng.randf_range(0.35, 1.0)
			var out := Vector2.from_angle(rng.randf_range(0.0, TAU))
			if spec.mode in ["sweep", "split"]: out = Vector2(signf(outward(body.p).x) * rng.randf_range(0.2, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			elif (body.p as Vector2).length() > 1.0: out = ((body.p as Vector2).normalized() + out * 0.6).normalized()
			if bool(spec.reverse): out = -out
			debris.append({"p": body.p, "birth": float(body.birth) + rng.randf_range(0.0, 0.05), "kind": type,
				"v": sqrt(2.0 * Profile.GRAVITY * high), "drift": out * rng.randf_range(40.0, 170.0) * (1.6 if type == "spark" else 1.0),
				"size": lerpf(2.5, 11.0, pow(rng.randf(), 2.2)) * sqrt(float(spec.unit_size)) * (1.3 if type == "stone" else 1.0),
				"spin": rng.randf_range(-9.0, 9.0), "seed": rng.randf_range(0.0, 1000.0)})
	# Crystals burst into shards when they shatter.
	if kind == "crystal" and type in ["ice", "mote"]:
		for body: Dictionary in bodies:
			for i in 3:
				if debris.size() >= MAX_DEBRIS: return
				debris.append({"p": body.p, "birth": float(body.birth) + float(spec.unit_time) * 0.72, "kind": "ice" if spec.unit == "ice" else "mote",
					"v": sqrt(2.0 * Profile.GRAVITY * float(body.size) * rng.randf_range(0.3, 0.9)),
					"drift": Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(50.0, 140.0),
					"size": rng.randf_range(4.0, 9.0), "spin": rng.randf_range(-12.0, 12.0), "seed": rng.randf_range(0.0, 1000.0)})

func _build_dust(rng: RandomNumberGenerator) -> void:
	if not bool(spec.dust) or float(spec.dust_density) <= 0.0: return
	var count := mini(MAX_PUFFS / 2, ceili(bodies.size() * float(spec.dust_density) * lerpf(0.5, 1.0, _detail_scale())))
	for i in count:
		var body: Dictionary = bodies[floori(float(i) * bodies.size() / count)]
		var out := outward(body.p)
		var size := float(body.size) * Profile.dust_scale(spec, float(body.d))
		var base := {"p": body.p, "d": body.d, "birth": float(body.birth) + 0.02, "seed": rng.randf_range(0.0, 1000.0),
			"out": out, "variant": rng.randi_range(0, 2)}
		var roll := base.duplicate()
		roll.merge({"size": size * rng.randf_range(1.5, 2.1), "rise": rng.randf_range(0.6, 1.0), "skirt": false, "fg": rng.randf() < 0.3,
			"span": float(spec.dust_time) * rng.randf_range(0.8, 1.05)})
		var skirt := base.duplicate()
		skirt.merge({"size": size * rng.randf_range(1.2, 1.6), "rise": 0.1, "skirt": true, "fg": rng.randf() < 0.5,
			"span": float(spec.dust_time) * rng.randf_range(0.5, 0.7), "seed": float(base.seed) + 37.0})
		# A blade skims the ground: it throws a low wake, not billowing clouds.
		if kind != "blade": puffs.append(roll)
		puffs.append(skirt)

# --- Clock -----------------------------------------------------------------------------------

func advance(delta: float) -> void:
	var before := age
	age += maxf(delta, 0.0)
	for pulse: Dictionary in pulses:
		if float(pulse.t) <= age and (float(pulse.t) > before or (before == 0.0 and float(pulse.t) == 0.0 and delta > 0.0)):
			_request_shake(float(spec.shake) * pow(maxf(float(pulse.gain), 0.0), 0.7))
	for key: String in layers:
		var layer: Node2D = layers[key]
		if key != "warp": (layer.material as ShaderMaterial).set_shader_parameter("time", age)
		layer.queue_redraw()

func _request_shake(amount: float) -> void:
	if amount <= 0.0: return
	var holder := get_parent()
	var stage := holder.get_parent() if holder != null else null
	if stage != null and stage.has_method("_shake"): stage._shake(amount, 0.16)

func is_done() -> bool:
	return age >= life

## 1 → 0 over the last half second of the event, so nothing pops out.
func _ending() -> float:
	return 1.0 - smoothstep(life - 0.5, life, age)

# --- Painting --------------------------------------------------------------------------------

func _paint_decal(ci: CanvasItem) -> void:
	# Stains, cracks and molten / frozen patches are GPU meshes (_build_gpu_layers).
	if kind == "lava" and spec.form == "fissure":
		for crack: Dictionary in cracks: if crack.main: _fissure(ci, crack)
func _paint_ground_glow(ci: CanvasItem) -> void:
	var end := _ending()
	if spec.unit in ["magic", "holy"] and spec.mode in ["radial", "cone"]: _sigil(ci)
	if kind == "lava":
		for body: Dictionary in bodies:
			var t := age - float(body.birth)
			if t < 0.0: continue
			var heat := exp(-t * 1.5) * end
			S.glow(ci, ground(body.p), Vector2(float(body.size) * 3.0, float(body.size) * 3.0 * float(spec.perspective) * 1.3), S.c(pal.glow, 0.5 * heat))
	_paint_wave_floor(ci)

func _sigil(ci: CanvasItem) -> void:
	var on := smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(Profile.duration(spec) + float(spec.unit_time) * 0.6, life - 0.2, age))
	if on <= 0.0: return
	var size := (reach() * 0.45 if spec.mode == "cone" else minf(extent(), radius * 1.2) * 0.55) * (0.6 + 0.4 * smoothstep(0.0, 0.2, age))
	var spin := age * 0.8
	var colour := S.c(pal.glow, 0.85 * on)
	var light := S.c(pal.light, 0.7 * on)
	for ring: float in [1.0, 0.84, 0.42]:
		var pts := PackedVector2Array()
		for i in 49: pts.append(ground(Vector2.from_angle(TAU * i / 48.0) * size * ring))
		ci.draw_polyline(pts, colour if ring != 0.84 else light, 2.2 if ring == 1.0 else 1.3, true)
	for i in 6:
		var a := spin + TAU * i / 6.0
		ci.draw_line(ground(Vector2.from_angle(a) * size * 0.84), ground(Vector2.from_angle(a + TAU / 3.0) * size * 0.84), colour, 1.4, true)
	for i in 24:
		var a := -spin * 0.6 + TAU * i / 24.0
		ci.draw_line(ground(Vector2.from_angle(a) * size * 0.88), ground(Vector2.from_angle(a) * size * (0.96 if i % 3 else 1.0)), light, 1.2, true)

## Where the front is right now: a list of {p, out} points across it (ground plane).
func _front(progress: float) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	var d := 1.0 - progress if bool(spec.reverse) else progress
	match spec.mode:
		"sweep", "split":
			var us := [lerpf(-extent(), extent(), d)] if spec.mode == "sweep" else [d * extent(), -d * extent()]
			for u: float in us:
				var w := maxf(half_width(u), radius * 0.3)
				var line := PackedVector2Array()
				for i in 13: line.append(Vector2(u, lerpf(-w, w, i / 12.0)))
				lines.append(line)
		"cone":
			var half := deg_to_rad(float(spec.cone)) * 0.5
			var line := PackedVector2Array()
			for i in 25: line.append(Vector2.from_angle(lerpf(-half, half, i / 24.0)) * reach() * d)
			lines.append(line)
		_:
			var line := PackedVector2Array()
			for i in 49:
				var a := TAU * i / 48.0
				line.append(Vector2.from_angle(a) * rim(a) * d)
			lines.append(line)
	return lines

func _wave_power() -> float:
	if not bool(spec.wave): return 0.0
	var duration := Profile.duration(spec)
	if age > duration + 0.2: return 0.0
	var progress := Profile.progress(spec, age)
	var moving := Profile.progress(spec, age + 0.01) > progress + 0.00001
	var power := float(pal.wave) * (1.0 if moving or age >= duration else 0.3) * (1.0 - smoothstep(duration, duration + 0.2, age))
	return power * sqrt(maxf(Profile.gain(spec, progress), 0.0)) * (1.0 - progress * 0.35)

func _paint_wave_floor(ci: CanvasItem) -> void:
	var power := _wave_power()
	if power <= 0.0: return
	var progress := Profile.progress(spec, age)
	var band := clampf(radius * 0.22, 10.0, 46.0)
	for line in _front(progress):
		if spec.mode in ["sweep", "split"]:
			var at := ground(line[line.size() / 2])
			var back := ground(_trail_dir(line[0]) * band * -0.6)
			var across := absf(ground(line[0]).y - ground(line[line.size() - 1]).y) + band
			S.glow(ci, at + back, Vector2(band * 3.0, across * 1.3), S.c(pal.glow, 0.8 * power))
			S.glow(ci, at, Vector2(band * 1.2, across * 0.8), S.c(pal.light, 0.5 * power))
			continue
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		var ci_ := []
		var co := []
		for p in line:
			var back := -_trail_dir(p) * band
			outer.append(ground(p))
			inner.append(ground(p + back))
			co.append(S.c(pal.glow, 0.75 * power))
			ci_.append(S.c(pal.glow, 0.0))
		S.strip(ci, outer, inner, co, ci_)
		if spec.mode in ["radial", "cone"]: ci.draw_polyline(outer, S.c(pal.light, 0.85 * power), 2.0, true)
		var middle := ground(line[line.size() / 2]) if spec.mode != "radial" else Vector2.ZERO
		var pool := radius * (1.4 if spec.mode != "radial" else 2.2 * maxf(progress, 0.2))
		S.glow(ci, middle, Vector2(pool * 2.0, pool * 2.0 * float(spec.perspective)), S.c(pal.glow, 0.22 * power))

## Ground-plane direction the front travels in at `p`.
func _trail_dir(p: Vector2) -> Vector2:
	var forward := Vector2.RIGHT
	match spec.mode:
		"sweep": forward = Vector2.RIGHT
		"split": forward = Vector2(signf(p.x) if absf(p.x) > 0.01 else 1.0, 0)
		_: forward = p.normalized() if p.length() > 0.01 else Vector2.RIGHT
	return -forward if bool(spec.reverse) else forward

func _paint_back_dust(_ci: CanvasItem) -> void:
	pass  # dust is a GPU mesh (_build_gpu_layers)

func _paint_front_dust(_ci: CanvasItem) -> void:
	pass
func _debris_at(part: Dictionary, t: float) -> Vector2:
	var fly := Profile.flight(float(part.v) * float(part.v) / (2.0 * Profile.GRAVITY))
	var air := minf(t, fly)
	var at := ground(part.p + (part.drift as Vector2) * air)
	at.y -= maxf(0.0, float(part.v) * air - 0.5 * Profile.GRAVITY * air * air)
	return at

func _solid_debris(ci: CanvasItem, part: Dictionary) -> void:
	var t := age - float(part.birth)
	var fly := 2.0 * float(part.v) / Profile.GRAVITY
	if t < 0.0 or t > fly + 0.45: return
	var at := _debris_at(part, t)
	var alpha := (1.0 - smoothstep(fly + 0.1, fly + 0.45, t)) * _ending()
	var angle := float(part.spin) * minf(t, fly)
	if part.kind == "stone":
		S.chunk(ci, at, float(part.size), angle, float(part.seed), pal, alpha, 0.0)
	else:
		var s := float(part.size)
		var tip := Vector2(0, -s * 1.6).rotated(angle)
		var side := Vector2(s * 0.45, 0).rotated(angle)
		ci.draw_colored_polygon(PackedVector2Array([at + tip, at + side, at - tip * 0.6, at - side]), S.c(pal.light, 0.9 * alpha))
		ci.draw_polyline(PackedVector2Array([at + tip, at + side, at - tip * 0.6]), S.c(Materials.v(1.0), alpha), 1.0, true)

func _paint_bodies(ci: CanvasItem) -> void:
	if not bool(spec.body):
		return
	var span := float(spec.unit_time)
	for body: Dictionary in bodies:
		var t := age - float(body.birth)
		if t < 0.0 or t > span: continue
		var at := ground(body.p)
		var s := float(body.size)
		match kind:
			"rock": pass
			"lava":
				if spec.form == "fountain" and S.h(float(body.seed) + 0.5) < 0.4:
					S.rock(ci, at, s * 0.7, float(body.seed), float(body.lean), t, span, pal, exp(-t * 1.2) * 0.9 + 0.1)
			"crystal": pass
	if kind == "lava": _magma(ci)

func _paint_glow(ci: CanvasItem) -> void:
	var span := float(spec.unit_time)
	var squash := float(spec.perspective)
	var end := _ending()
	# Impact flash on every push of the front.
	for pulse: Dictionary in pulses:
		var t := age - float(pulse.t)
		if t < 0.0 or t > 0.5: continue
		var power := exp(-t * 9.0) * float(spec.flash) * minf(float(pulse.gain), 2.0)
		var at := _pulse_point(pulse)
		var r := clampf(radius * 1.6, 60.0, 260.0)
		S.glow(ci, at, Vector2(r * 2.4, r * 2.4 * squash * 1.4), S.c(pal.glow, 0.7 * power))
		S.glow(ci, at + Vector2(0, -r * 0.15), Vector2(r * 0.9, r * 0.7), S.c(pal.light, 0.55 * power))
	_paint_wave_wall(ci)
	if bool(spec.body):
		for body: Dictionary in bodies:
			var t := age - float(body.birth)
			if t < 0.0 or t > span: continue
			var at := ground(body.p)
			var s := float(body.size)
			match kind:
				"beam": S.beam(ci, at, s, float(body.seed), t, span, pal, squash)
				"bolt": pass
				"lava": _magma_light(ci, body, at, s, t, span)
				"crystal":
					# A short glint up the main crystal as it lands.
					var glint := smoothstep(0.05, 0.1, t) * (1.0 - smoothstep(0.1, 0.3, t))
					S.glow(ci, at + Vector2(0, -s * lerpf(0.4, 1.6, smoothstep(0.05, 0.3, t))), Vector2(s * 0.8, s * 0.8), S.c(pal.light, glint))
					S.glow(ci, at, Vector2(s * 2.0, s * 2.0 * squash * 1.4), S.c(pal.glow, 0.35 * exp(-t * 4.0)))
			# The instant each body breaks the ground.
			S.glow(ci, at, Vector2(s * 2.6, s * 2.6 * squash * 1.4), S.c(pal.glow, 0.45 * exp(-t * 14.0)))
		if kind == "bolt": _thunder(ci)
	for part: Dictionary in debris:
		pass  # embers, sparks and motes are a GPU mesh (_build_gpu_layers)

func _pulse_point(pulse: Dictionary) -> Vector2:
	if spec.mode == "radial": return Vector2.ZERO
	var lines := _front(float(pulse.d))
	if lines.is_empty(): return Vector2.ZERO
	var line: PackedVector2Array = lines[0]
	return ground(line[line.size() / 2])

## The pressure front, standing up off the ground as a thin wall of light.
func _paint_wave_wall(ci: CanvasItem) -> void:
	var power := _wave_power()
	if power <= 0.0 or float(spec.wave_height) <= 0.0: return
	var progress := Profile.progress(spec, age)
	var tall := clampf(radius * 0.3, 14.0, 60.0) * float(spec.wave_height) * (1.0 - progress * 0.4)
	for line in _front(progress):
		if spec.mode in ["sweep", "split"]:
			# Seen from the side a straight front is edge-on: show it as a soft rising column.
			var at := ground(line[line.size() / 2])
			S.glow(ci, at + Vector2(0, -tall * 0.55), Vector2(radius * 0.5 + 20.0, tall * 2.6), S.c(pal.glow, 0.55 * power))
			S.glow(ci, at + Vector2(0, -tall * 0.2), Vector2(radius * 0.18 + 8.0, tall * 1.3), S.c(pal.light, 0.5 * power))
			continue
		var low := PackedVector2Array()
		var high := PackedVector2Array()
		var cl := []
		var ch := []
		var ease := smoothstep(0.0, 0.3, progress)
		for p in line:
			low.append(ground(p))
			high.append(ground(p) + Vector2(0, -tall))
			cl.append(S.c(pal.glow, 0.4 * power * ease))
			ch.append(S.c(pal.glow, 0.0))
		S.strip(ci, low, high, cl, ch)

func _paint_warp(ci: CanvasItem) -> void:
	_shimmer(ci)
	var power := _wave_power()
	if power <= 0.0: return
	var progress := Profile.progress(spec, age)
	var band := clampf(radius * 0.25, 14.0, 50.0)
	for line in _front(progress):
		if spec.mode in ["sweep", "split"]:
			var at := ground(line[line.size() / 2])
			var forward := outward(line[line.size() / 2])
			var tall := clampf(radius * 0.9, 40.0, 160.0)
			var tone := Color(0.5 + forward.x * 0.5, 0.5 + forward.y * 0.5, 0.0, power)
			ci.draw_primitive(PackedVector2Array([at + Vector2(-band, -tall), at + Vector2(band, -tall), at + Vector2(band, tall * 0.25), at + Vector2(-band, tall * 0.25)]),
				PackedColorArray([tone, tone, tone, tone]), PackedVector2Array([Vector2(0, -1), Vector2(0, 1), Vector2(0, 1), Vector2(0, -1)]))
			continue
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var out_a := ground(_trail_dir(a)).normalized()
			var out_b := ground(_trail_dir(b)).normalized()
			var ta := Color(0.5 + out_a.x * 0.5, 0.5 + out_a.y * 0.5, 0.0, power)
			var tb := Color(0.5 + out_b.x * 0.5, 0.5 + out_b.y * 0.5, 0.0, power)
			ci.draw_primitive(PackedVector2Array([ground(a) + out_a * band, ground(b) + out_b * band, ground(b) - out_b * band, ground(a) - out_a * band]),
				PackedColorArray([ta, tb, tb, ta]), PackedVector2Array([Vector2(0, 1), Vector2(0, 1), Vector2(0, -1), Vector2(0, -1)]))

# --- Thunder -------------------------------------------------------------------------------------

func _thunder(ci: CanvasItem) -> void:
	var squash := float(spec.perspective)
	var octaves: float = {"balanced": 0.3, "fine": 0.6, "ultimate": 1.0, "explosive": 1.0}[detail]
	var size_scale := float(spec.unit_size)
	var arcs := 1 + int(octaves * 2.0)
	for body: Dictionary in bodies:
		var t := age - float(body.birth)
		if t < 0.0 or t > 0.6: continue
		var at := ground(body.p)
		var s := float(body.size)
		var seed := float(body.seed)
		match String(spec.form):
			"sky":
				if body.strike:
					S.sky_bolt(ci, at, 430.0 * size_scale, 9.0 * size_scale * sqrt(float(body.gain)), seed, t, octaves)
					_strike_light(ci, at, s, t, squash)
				S.ground_arcs(ci, at, s * 0.9, squash, seed, t, 0.3, arcs)
			"pillar":
				if body.strike: _pillar(ci, at, s, seed, t, squash, octaves)
				else: S.ground_arcs(ci, at, s * 0.7, squash, seed, t, 0.25, arcs)
			"ground":
				# Short sparks leap up where the ground breaks; arcs jump on to the next break.
				var spike := S.strike_curve(t * 1.6, seed)
				if float(spike[0]) > 0.01:
					var tip := at + Vector2((S.h(seed) - 0.5) * s * 1.2, -s * (1.8 + S.h(seed + 1.0) * 1.6) * size_scale)
					var spark := S.zigzag(at, tip, seed + floorf(t * 24.0), 0.28, 5)
					S.filament(ci, spark, 8.0 * float(spike[2]), float(spike[1]), float(spike[0]), seed, 0.85)
					for branch in S.branches(spark, seed + floorf(t * 24.0), 2, s * 0.8):
						S.filament(ci, branch, 4.5, float(spike[1]), float(spike[0]) * 0.8, seed, 0.95)
				S.glow(ci, at, Vector2(s * 2.0, s * 2.0 * squash * 1.4), S.c(pal.glow, 0.5 * exp(-t * 8.0)))
				S.ground_arcs(ci, at, s * 1.6, squash, seed, t, 0.4, arcs + 2)
	if spec.form == "ground": _crawling(ci, octaves)

## The return stroke lights everything: a hot core where it lands, a wide wash, a ring.
func _strike_light(ci: CanvasItem, at: Vector2, s: float, t: float, squash: float) -> void:
	var power := exp(-maxf(t - 0.03, 0.0) * 12.0) * (1.0 if t >= 0.03 else 0.3)
	S.glow(ci, at, Vector2(s * 4.0, s * 4.0 * squash * 1.4), S.c(pal.glow, 0.85 * power))
	S.glow(ci, at + Vector2(0, -s * 0.15), Vector2(s * 1.2, s * 0.9), S.c(pal.white, power))
	if detail in ["ultimate", "explosive"]:
		S.glow(ci, at + Vector2(0, -200), Vector2(1400, 900), S.c(pal.glow, 0.16 * power))
	S.ring(ci, at, s * (0.3 + maxf(t - 0.03, 0.0) * 5.0), squash, S.c(pal.light, 0.8 * exp(-maxf(t - 0.03, 0.0) * 6.0)), 2.0)

## Three channels twisting inside a column of light, re-forming 20 times a second.
func _pillar(ci: CanvasItem, at: Vector2, s: float, seed: float, t: float, squash: float, octaves: float) -> void:
	var span := 0.5
	if t > span: return
	var tall := 300.0 * float(spec.unit_size)
	var rise := smoothstep(0.0, 0.05, t)
	var fade := 1.0 - smoothstep(span * 0.55, span, t)
	var width := s * 0.45 * (1.0 + 0.5 * exp(-t * 10.0))
	var top := at + Vector2(0, -tall * rise)
	ci.draw_polygon(PackedVector2Array([at + Vector2(-width, 0), at + Vector2(width, 0), top + Vector2(width * 0.6, 0), top + Vector2(-width * 0.6, 0)]),
		PackedColorArray([S.c(pal.glow, 0.5 * fade), S.c(pal.glow, 0.5 * fade), S.c(pal.glow, 0.0), S.c(pal.glow, 0.0)]))
	var step := floorf(t * 20.0)
	for k in 2 + int(octaves):
		var key := seed + k * 19.0 + step * 3.0
		# Each channel winds around the column's axis, out of phase with the others.
		var path := PackedVector2Array()
		var turns := 1.5 + S.h(seed + k) * 1.0
		for i in 25:
			var u := i / 24.0
			var swing := sin(u * TAU * turns + k * TAU / 3.0 + t * 14.0) * width * 0.55
			path.append(top.lerp(at, u) + Vector2(swing + (S.h(key + i) - 0.5) * width * 0.35, 0))
		S.filament(ci, path, 8.0 if k == 0 else 6.0, 0.95 if k == 0 else 0.88, fade * (1.0 if k == 0 else 0.75), key, -0.2)
		if k == 0:
			for branch in S.branches(path, key, 2 + int(octaves * 2.0), width * 2.2):
				S.filament(ci, branch, 4.0, 0.9, fade * 0.8, key, 0.95)
	_strike_light(ci, at, s, t, squash)
	S.ground_arcs(ci, at, s * 1.1, squash, seed, t, span * 0.8, 3)

## 地脉雷: electricity running along the freshly torn cracks.
func _crawling(ci: CanvasItem, octaves: float) -> void:
	var step := floorf(age * 24.0)
	for c in cracks.size():
		var crack: Dictionary = cracks[c]
		var pts: PackedVector2Array = crack.pts
		var path := PackedVector2Array()
		for i in pts.size():
			var t := age - float(crack.arr[i])
			if t < 0.0: break
			if t > 0.45: continue
			var jitter := (S.h(c * 7.0 + i * 3.0 + step) - 0.5) * 10.0
			path.append(ground(pts[i]) + Vector2(jitter * 0.3, jitter * 0.6 - 2.0))
		if path.size() < 2: continue
		if S.h(c + step * 0.37) < 0.15 * (1.0 - octaves * 0.5): continue
		S.filament(ci, S.zigzag(path[0], path[-1], c + step, 0.0, 0) if path.size() < 2 else path, 9.0, 0.92, 1.0, c * 0.17 + step * 0.01, 0.3)

# --- Magma ---------------------------------------------------------------------------------------

const LAVA_GRAVITY := 1400.0

## Pieces of one lava stream thrown from `at` with launch velocity `velocity`, emitting for
## `pour` seconds. The upper, older part breaks into drops; what lands is dropped.
func _stream(at: Vector2, velocity: Vector2, thick: float, seed: float, t: float, pour: float, cooling: float, density := 28.0, wobble := 0.0) -> Array:
	var flight := 2.0 * -velocity.y / LAVA_GRAVITY
	var newest := maxf(0.0, t - pour)
	var oldest := minf(t, flight)
	var pieces: Array = []
	if newest >= oldest: return pieces
	var count := clampi(int(density * (oldest - newest) / maxf(flight, 0.01)) + 6, 6, 44)
	for i in count:
		var a := lerpf(newest, oldest, float(i) / (count - 1))
		var u := a / flight
		var breakup := smoothstep(0.4, 0.75, u)
		if breakup > 0.0 and S.h(seed + i * 3.3) < breakup * 0.55: continue
		var p := at + velocity * a + Vector2(0, 0.5 * LAVA_GRAVITY * a * a)
		# The top of the jet breaks into a crown of drops; a turbulent column sways.
		p.x += (S.h(seed + i * 5.1) - 0.5) * thick * 5.0 * breakup + sin(a * 23.0 + seed) * thick * wobble
		var v := velocity + Vector2(0, LAVA_GRAVITY * a)
		var r := thick * (1.0 - 0.45 * u) * (0.85 + 0.3 * S.h(seed + i * 1.7)) * (1.0 - 0.45 * breakup)
		pieces.append([p, r, clampf(1.0 - u * 0.25 - cooling * 0.3, 0.3, 1.0), v.normalized(), 1.0 + breakup * 0.5 + minf(v.length() / 1600.0, 0.3)])
	return pieces

func _magma(ci: CanvasItem) -> void:
	var span := float(spec.unit_time)
	var squash := float(spec.perspective)
	var pieces: Array = []
	for body: Dictionary in bodies:
		var t := age - float(body.birth)
		if t < 0.0 or t > span: continue
		var at := ground(body.p)
		var s := float(body.size)
		var seed := float(body.seed)
		var lean := float(body.lean)
		var cooling := smoothstep(span * 0.35, span, t) * 0.8
		match String(spec.form):
			"fountain":
				if S.h(seed + 0.9) > 0.7: continue
				var tall := s * (3.0 + S.h(seed) * 2.2) * sqrt(maxf(float(body.gain), 0.1))
				var velocity := Vector2(lean * s * 4.5 + (S.h(seed + 2.0) - 0.5) * s * 4.0, -sqrt(2.0 * LAVA_GRAVITY * tall))
				pieces.append_array(_stream(at, velocity, s * 0.17, seed, t, span * 0.4, cooling, 40.0))
				S.blob(ci, at, s * 0.55 * smoothstep(0.0, 0.1, t), 0.9, 1.0 - cooling, 5, Vector2.RIGHT, 1.0, squash * 1.6)
				_landing(ci, at + Vector2(velocity.x * 2.0 * -velocity.y / LAVA_GRAVITY, 0), s, t - 2.0 * -velocity.y / LAVA_GRAVITY, squash)
			"fissure":
				# Bubbles swell and burst on the river; now and then a small splash.
				for k in 3:
					var born := S.h(seed + k * 5.0) * span * 0.6
					var b := t - born
					if b < 0.0 or b > 0.28: continue
					var spot := at + Vector2((S.h(seed + k * 7.0) - 0.5) * s * 1.2, (S.h(seed + k * 9.0) - 0.5) * s * 0.3 * squash)
					S.blob(ci, spot + Vector2(0, -b * s * 0.4), s * 0.16 * sin(PI * b / 0.28), 0.95, 0.9, 5)
				if S.h(seed + 4.0) < 0.35:
					var velocity := Vector2((S.h(seed + 2.0) - 0.5) * s * 2.0, -sqrt(2.0 * LAVA_GRAVITY * s * 1.1))
					pieces.append_array(_stream(at, velocity, s * 0.16, seed, t - 0.05, 0.12, cooling))
				if S.h(seed + 6.0) < 0.6: _plate(ci, at, s, seed, lean, t, span)
			"eruption":
				if not body.strike: continue
				var tall := s * 6.0 * sqrt(maxf(float(body.gain), 0.1)) * float(spec.unit_size)
				var velocity := Vector2((S.h(seed + 2.0) - 0.5) * s * 0.6, -sqrt(2.0 * LAVA_GRAVITY * tall))
				pieces.append_array(_stream(at, velocity, s * 0.42, seed, t, span * 0.3, cooling, 44.0, 0.6))
				# The column's crown spills outwards and falls back around it.
				for k in 6:
					var side := Vector2((k - 2.5) * s * 2.2, -sqrt(2.0 * LAVA_GRAVITY * tall * (0.6 + 0.25 * S.h(seed + k))))
					pieces.append_array(_stream(at, side, s * 0.2, seed + k * 13.0, t - 0.08, span * 0.15, cooling, 30.0))
				S.blob(ci, at, s * 1.1 * smoothstep(0.0, 0.1, t), 0.9, 1.0 - cooling, 5, Vector2.RIGHT, 1.0, squash * 1.6)
				_bombs(ci, at, s, seed, t, squash)
	S.liquid(ci, pieces)

## A slab of crust tipped up beside the fissure, its underside glowing.
func _plate(ci: CanvasItem, at: Vector2, s: float, seed: float, lean: float, t: float, span: float) -> void:
	var rise := S.back_out(t / 0.12) * (1.0 - smoothstep(span * 0.7, span, t))
	if rise <= 0.01: return
	var side := -1.0 if S.h(seed + 8.0) < 0.5 else 1.0
	var w := s * (1.0 + S.h(seed + 9.0) * 0.7)
	var tilt := (0.45 + S.h(seed + 10.0) * 0.4) * rise
	var base := at + Vector2(side * s * 0.3, 2.0)
	var top := PackedVector2Array([base, base + Vector2(w * side, 0).rotated(-tilt * side), base + Vector2(w * side * 0.9, -s * 0.5).rotated(-tilt * side), base + Vector2(-side * s * 0.05, -s * 0.42)])
	ci.draw_colored_polygon(top, S.c(pal.rock_lit, 1.0))
	ci.draw_polyline(PackedVector2Array([top[0], top[1]]), S.c(Materials.v(0.92), 0.9 * (1.0 - smoothstep(0.0, span, t))), 2.4, true)
	var outline := top.duplicate()
	outline.append(top[0])
	ci.draw_polyline(outline, S.c(pal.deep, 1.0), 1.5, true)

## Lava bombs flung from an eruption: glowing basalt lumps trailing fire, splashing down.
func _bombs(ci: CanvasItem, at: Vector2, s: float, seed: float, t: float, squash: float) -> void:
	for k in 7:
		var key := seed + k * 17.0
		var velocity := Vector2((S.h(key) - 0.5) * s * 9.0, -lerpf(s * 9.0, s * 16.0, S.h(key + 1.0)))
		var flight := 2.0 * -velocity.y / LAVA_GRAVITY
		var tt := t - 0.04
		if tt < 0.0: continue
		if tt > flight:
			_landing(ci, at + Vector2(velocity.x * flight, 0), s * 0.6, tt - flight, squash)
			continue
		var p := at + velocity * tt + Vector2(0, 0.5 * LAVA_GRAVITY * tt * tt)
		var before := at + velocity * maxf(tt - 0.05, 0.0) + Vector2(0, 0.5 * LAVA_GRAVITY * pow(maxf(tt - 0.05, 0.0), 2))
		ci.draw_line(before, p, S.c(Materials.v(0.88), 0.7), s * 0.18, true)
		S.chunk(ci, p, s * (0.14 + S.h(key + 2.0) * 0.1), tt * 7.0 + key, key, pal, 1.0, 1.0 - tt / flight)

## Where lava lands: a flattened splash and a short-lived puddle.
func _landing(ci: CanvasItem, at: Vector2, s: float, t: float, squash: float) -> void:
	if t < 0.0 or t > 0.5: return
	var spread := S.back_out(t / 0.08)
	var heat := 1.0 - t / 0.5
	S.blob(ci, at, s * 0.45 * spread, 0.22, 0.0, 0, Vector2.RIGHT, 1.0, squash * 1.6)
	S.blob(ci, at, s * 0.38 * spread, 0.9, heat, 5, Vector2.RIGHT, 1.0, squash * 1.6)

## 熔岩地裂: the main cracks open into a river of lava with dark crusted banks.
func _fissure(ci: CanvasItem, crack: Dictionary) -> void:
	var pts: PackedVector2Array = crack.pts
	var bank := PackedVector2Array()
	var heat_at := PackedFloat32Array()
	var widths := PackedFloat32Array()
	var span := float(spec.unit_time) + float(spec.crack_time)
	for i in pts.size():
		var t := age - float(crack.arr[i])
		if t < 0.0: break
		bank.append(ground(pts[i]))
		var u := float(i) / (pts.size() - 1)
		widths.append(radius * 0.55 * S.back_out(t / 0.15) * (0.55 + 0.45 * sin(PI * clampf(u * 1.1, 0.0, 1.0))) * (1.0 - smoothstep(span * 0.7, span, t)))
		heat_at.append(clampf(1.0 - smoothstep(0.2, span, t) * 0.85, 0.05, 1.0))
	if bank.size() < 2: return
	for pass_ in 2:
		for i in bank.size() - 1:
			var d := (bank[i + 1] - bank[i]).normalized().orthogonal()
			var w0 := widths[i] * (1.25 if pass_ == 0 else 1.0)
			var w1 := widths[i + 1] * (1.25 if pass_ == 0 else 1.0)
			var quad := PackedVector2Array([bank[i] + Vector2(d.x, d.y * 0.4) * w0, bank[i + 1] + Vector2(d.x, d.y * 0.4) * w1,
				bank[i + 1] - Vector2(d.x, d.y * 0.4) * w1, bank[i] - Vector2(d.x, d.y * 0.4) * w0])
			if pass_ == 0:
				ci.draw_primitive(quad, PackedColorArray([pal.deep, pal.deep, pal.deep, pal.deep]), quad)
			else:
				var c0 := Materials.v(0.9, 1.0, 5, heat_at[i])
				var c1 := Materials.v(0.9, 1.0, 5, heat_at[i + 1])
				ci.draw_primitive(quad, PackedColorArray([c0, c1, c1, c0]), quad)

## Light thrown by the lava (additive layer).
func _magma_light(ci: CanvasItem, body: Dictionary, at: Vector2, s: float, t: float, span: float) -> void:
	var fade := 1.0 - smoothstep(span * 0.4, span, t)
	match String(spec.form):
		"fountain":
			if S.h(float(body.seed) + 0.9) > 0.7: return
			S.glow(ci, at + Vector2(0, -s * 0.9), Vector2(s * 3.0, s * 4.0), S.c(pal.glow, 0.4 * fade))
		"eruption":
			if not body.strike: return
			S.glow(ci, at + Vector2(0, -s * 2.0), Vector2(s * 5.0, s * 8.0), S.c(pal.glow, 0.5 * fade))
			S.glow(ci, at, Vector2(s * 6.0, s * 6.0 * float(spec.perspective) * 1.4), S.c(pal.glow, 0.7 * exp(-t * 5.0)))
		"scorch":
			var heat := _scorch_heat(t)
			S.glow(ci, at, Vector2(s * 3.6, s * 3.6 * float(spec.perspective) * 1.5), S.c(pal.glow, 0.55 * heat * heat))
			S.glow(ci, at + Vector2(0, -s * 0.5), Vector2(s * 2.4, s * 1.6), S.c(pal.glow, 0.18 * heat))
		_:
			S.glow(ci, at, Vector2(s * 3.0, s * 3.0 * float(spec.perspective) * 1.4), S.c(pal.glow, 0.45 * fade))

# --- 灼地熔化 ----------------------------------------------------------------------------------

## Heat of a scorched patch over its local time: blackens, glows through, melts, then cools
## back into a crust with glowing seams.
func _scorch_heat(t: float) -> float:
	if t < 0.0: return 0.0
	var span := float(spec.unit_time) + float(spec.crack_time)
	return smoothstep(0.1, 0.55, t) * (1.0 - 0.9 * smoothstep(span * 0.25, span * 0.8, t))

## Outline of a patch on the ground: a wobbly circle `r` around ground point `p`.
func _patch(p: Vector2, r: float, seed: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 22:
		var a := TAU * i / 22.0
		var k := 1.0 + 0.18 * sin(3.0 * a + seed) + 0.1 * sin(5.0 * a + seed * 2.0) + 0.06 * sin(9.0 * a + seed * 3.0)
		pts.append(ground(p + Vector2.from_angle(a) * r * k))
	return pts
func _shimmer(ci: CanvasItem) -> void:
	if kind != "lava" or spec.form != "scorch": return
	for body: Dictionary in bodies:
		var heat := _scorch_heat(age - float(body.birth))
		if heat < 0.1: continue
		var at := ground(body.p)
		var s := float(body.size)
		var seed := float(body.seed)
		var sway := Vector2(sin(age * 19.0 + seed), cos(age * 13.0 + seed * 1.7)) * 0.5
		var tone := Color(0.5 + sway.x * 0.5, 0.5 + sway.y * 0.5, 0.0, heat * 0.55)
		var w := s * 1.1
		var tall := s * 1.8
		ci.draw_primitive(PackedVector2Array([at + Vector2(-w, -tall), at + Vector2(w, -tall), at + Vector2(w, 0), at + Vector2(-w, 0)]),
			PackedColorArray([tone, tone, tone, tone]), PackedVector2Array([Vector2(0, -1), Vector2(0, 1), Vector2(0, 1), Vector2(0, -1)]))

# --- Solid rock (GPU) ----------------------------------------------------------------------------

## Rock bodies as one static mesh animated by shaders/solid.gdshader: built once here, then
## only the clock moves. Sits just under the body layer so flying chunks draw over it.
func _build_solids() -> void:
	var builder := Solid.new()
	builder.angle = deg_to_rad(float(spec.angle))
	var soil := Materials.v(0.14, 1.0, 6, 1.0)
	var stone := Materials.v(0.11, 1.0, 6, 0.0)
	var crust := Materials.v(0.06, 1.0, 6, 0.0)
	var pit := Materials.v(0.0, 0.9)
	if kind == "crystal":
		_build_crystals(builder)
	elif spec.form == "surge":
		_build_surge(builder, stone, rng_surge())
	else:
		for body: Dictionary in bodies:
			var s := float(body.size)
			var seed := float(body.seed)
			var p: Vector2 = body.p
			var heading := _ground_heading(p) + (S.h(seed + 3.0) - 0.5) * 0.5
			var birth := float(body.birth)
			builder.heading = heading
			match String(spec.form):
				"boulder":
					if S.h(seed + 1.5) > 0.55: continue
					builder.boulder(ground(p), s * (0.5 + S.h(seed) * 0.35), seed, birth, PI * 0.5, stone)
				"spike":
					# A main spike with shorter ones around it, the farthest drawn first.
					var parts := []
					for k in 3:
						var off := Vector2(0, 0) if k == 0 else Vector2((S.h(seed + k) - 0.5) * s * 0.6, (k - 1.5) * s * 0.55)
						parts.append([off, k])
					parts.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector2).rotated(builder.angle + heading).y < (b[0] as Vector2).rotated(builder.angle + heading).y)
					for part: Array in parts:
						var k: int = part[1]
						var tall := s * ((1.25 + S.h(seed + 7.0) * 0.6) if k == 0 else (0.5 + S.h(seed + k * 3.0) * 0.4))
						var lean := Vector2(tall * (0.18 + S.h(seed + k + 11.0) * 0.22), (S.h(seed + k + 13.0) - 0.5) * tall * 0.2)
						builder.spike(ground(p + (part[0] as Vector2).rotated(heading)), s * (0.34 if k == 0 else 0.22), tall, lean, 5 + int(S.h(seed + k) * 2.0), seed + k * 17.0, birth + k * 0.025, stone)
				_:
					# 地皮掀板: a few thick plates of ground hinged on their back edge, over dark pits.
					if S.h(seed + 1.5) > 0.5: continue
					var length := s * (1.7 + S.h(seed) * 0.6)
					var depth := s * (1.1 + S.h(seed + 2.0) * 0.5)
					var hinge := p - Vector2.from_angle(heading) * length * 0.5
					builder.face(ground(hinge), [Vector3(0, -depth * 0.5, 0), Vector3(length, -depth * 0.5, 0), Vector3(length, depth * 0.5, 0), Vector3(0, depth * 0.5, 0)],
						Vector3(length * 0.5, 0, -1), birth, PI * 0.5, Solid.SLAB, 0.0, pit)
					builder.slab(ground(hinge), Vector3(length, depth, s * 0.4), birth, PI * 0.5, 0.6 + S.h(seed + 4.0) * 0.5, crust, soil)
	_mesh_layer("solids", builder.mesh(), SOLID).set_shader_parameter("span", float(spec.unit_time))

## Ground direction (radians, before the effect's rotation) the front moves in at `p`.
func _ground_heading(p: Vector2) -> float:
	return _trail_dir(p).angle()

## 土浪: a grid over the footprint whose ground swells as the front rolls under it.
func rng_surge() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed) + 991
	return rng

func _build_surge(builder: Solid, tone: Color, rng: RandomNumberGenerator) -> void:
	# Big enough tiles that the swell reads as ground breaking into plates.
	var cell := clampf(radius * 0.2, 14.0, 26.0)
	var left := -reach() if spec.mode == "cone" else -extent()
	var right := reach() if spec.mode == "cone" else extent()
	var top := -reach() if spec.mode == "cone" else -radius
	var bottom := -top
	var height := clampf(radius * 0.35, 18.0, 60.0) * float(spec.unit_size)
	var columns := ceili((right - left) / cell)
	var rows := ceili((bottom - top) / cell)
	var nodes := {}
	var node_at := func(i: int, j: int) -> Array:
		var key := Vector2i(i, j)
		if nodes.has(key): return nodes[key]
		var g := Vector2(left + i * cell, top + j * cell)
		var step := cell * 0.5
		var gradient := Vector2(arrival(g + Vector2(step, 0)) - arrival(g - Vector2(step, 0)), arrival(g + Vector2(0, step)) - arrival(g - Vector2(0, step))) / (step * 2.0)
		var d := distance_at(g)
		var value := [ground(g), arrival(g), gradient, height * sqrt(maxf(Profile.gain(spec, d), 0.05)) * Profile.body_scale(spec, d), inside(g)]
		nodes[key] = value
		return value
	var cells := []
	for j in rows:
		for i in columns:
			var corners: Array = [node_at.call(i, j), node_at.call(i + 1, j), node_at.call(i + 1, j + 1), node_at.call(i, j + 1)]
			if not corners.all(func(c: Array) -> bool: return c[4]): continue
			var middle := Vector2(left + (i + 0.5) * cell, top + (j + 0.5) * cell).rotated(builder.angle)
			cells.append([middle.y, corners])
	cells.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for item: Array in cells:
		var screens: Array[Vector2] = []
		var births: Array[float] = []
		var gradients: Array[Vector2] = []
		var heights: Array[float] = []
		# Each tile rides the swell at its own height and tilt, so seams open between them.
		var lift := rng.randf_range(0.55, 1.35)
		var tilt := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		var k := 0
		for c: Array in item[1]:
			screens.append(c[0])
			births.append(float(c[1]) + rng.randf_range(-0.01, 0.01))
			gradients.append(c[2])
			heights.append(float(c[3]) * lift * (1.0 + tilt.x * (1.0 if k in [1, 2] else -1.0) + tilt.y * (1.0 if k in [2, 3] else -1.0)))
			k += 1
		builder.surge_cell(screens, births, gradients, heights, Materials.v(tone.r + rng.randf_range(-0.04, 0.05), 1.0, 6, 0.0))

# --- Crystals (GPU) ------------------------------------------------------------------------------

## Ice and shadow crystals: clusters (default), tall spires, or a low fringe on frozen ground.
func _build_crystals(builder: Solid) -> void:
	var tone := Materials.v(0.3, 0.92, 7)
	var form := String(spec.form) if spec.unit == "ice" else "cluster"
	for body: Dictionary in bodies:
		var s := float(body.size)
		var seed := float(body.seed)
		var p: Vector2 = body.p
		var heading := _ground_heading(p)
		var birth := float(body.birth)
		builder.heading = heading
		var parts := []
		match form:
			"spires":
				for k in 3:
					var off := Vector2((S.h(seed + k) - 0.5) * s * 0.7, (k - 1.0) * s * 0.4)
					var tall := s * (1.9 + S.h(seed + k * 3.0) * 1.3)
					parts.append([off, s * (0.1 + S.h(seed + k * 5.0) * 0.05), tall, Vector2((S.h(seed + k * 7.0) - 0.3) * tall * 0.12, 0.0), birth + k * 0.03])
			"freeze":
				if S.h(seed + 2.0) > 0.6: continue
				for k in 3:
					var off := Vector2((S.h(seed + k) - 0.5) * s * 1.6, (S.h(seed + k + 4.0) - 0.5) * s * 1.0)
					var tall := s * (0.35 + S.h(seed + k * 3.0) * 0.4)
					parts.append([off, s * 0.1, tall, Vector2.from_angle(S.h(seed + k * 9.0) * TAU) * tall * 0.4, birth + 0.12 + k * 0.04])
			_:
				var count := 3 + int(S.h(seed) * 2.99)
				for k in count:
					var side := 0.0 if k == 0 else (-1.0 if k % 2 == 1 else 1.0)
					var tall := s * ((1.5 + S.h(seed + 1.0) * 0.5) if k == 0 else (0.55 + S.h(seed + k * 2.3) * 0.5))
					# Side crystals fan out to the left and right of the screen, not towards the viewer.
					var spread := Vector2(side * (0.6 + S.h(seed + k) * 0.6), (S.h(seed + k * 1.7) - 0.5) * 0.5)
					var lean := Vector2.ZERO if k == 0 else spread.normalized() * tall * (0.35 + S.h(seed + k * 1.9) * 0.4)
					var off := Vector2(0, 0) if k == 0 else spread.normalized() * s * 0.15
					parts.append([off, s * (0.2 if k == 0 else 0.13), tall, lean + Vector2(0.15 * tall, 0) * float(k == 0), birth + k * 0.02])
		parts.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector2).rotated(builder.angle + heading).y < (b[0] as Vector2).rotated(builder.angle + heading).y)
		for part: Array in parts:
			builder.crystal(ground(p + (part[0] as Vector2).rotated(heading)), part[1], part[2], part[3], seed + float(part[2]), part[4], tone)

# --- GPU mesh layers -----------------------------------------------------------------------------

## Adds a static mesh drawn with `shader` just under the body layer (inside the pixel lens
## when the style is pixel) and registers it as a layer, so it follows the clock and look.
func _mesh_layer(key: String, mesh: ArrayMesh, shader: Shader) -> ShaderMaterial:
	var node := MeshInstance2D.new()
	node.name = key.to_pascal_case()
	node.mesh = mesh
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shading := ShaderMaterial.new()
	shading.shader = shader
	shading.set_shader_parameter("ramp", Materials.ramp(String(spec.unit), spec.ramp))
	shading.set_shader_parameter("perspective", float(spec.perspective))
	node.material = shading
	add_child(node)
	if _pixel.is_empty(): move_child(node, (layers.body as Node).get_index())
	else: node.reparent(_pixel[1], false)
	layers[key] = node
	set_look(style, detail)
	return shading

## Stone and ice debris fly as one GPU mesh; embers, sparks and motes stay as light.
func _build_chunks() -> void:
	var builder := Chunks.new()
	builder.angle = deg_to_rad(float(spec.angle))
	for part: Dictionary in debris:
		if not part.kind in ["stone", "ice"]: continue
		var ice: bool = part.kind == "ice"
		builder.chunk(ground(part.p), float(part.size) * (1.4 if ice else 1.8), float(part.seed), float(part.birth), part.drift, float(part.v), float(part.spin), ice)
	if builder.starts.is_empty(): return
	var shading := _mesh_layer("chunks", builder.mesh(), CHUNKS)
	shading.set_shader_parameter("gravity", Profile.GRAVITY)
	shading.set_shader_parameter("stone_value", 0.12 if kind == "rock" else 0.06)
	# Solids sit under the chunks: put the chunks after them.
	if layers.has("solids") and _pixel.is_empty():
		move_child(layers.chunks, (layers.solids as Node).get_index() + 1)

## Everything that only needs the clock, as GPU meshes: ground stains, cracks (gap, lip,
## glow), dust, light particles, and the molten / frozen ground of 灼地熔化 and 冰封大地.
func _build_gpu_layers() -> void:
	var squash := float(spec.perspective)
	var stains := GpuLayers.Sprites.new()
	var stain_a := float(pal.stain_alpha)
	if spec.mode == "radial" and not bool(spec.reverse):
		stains.add(Vector2.ZERO, 0.0, life, minf(extent(), radius * 1.4) * 2.6, 6, Vector4(squash, 0, 0, 0), S.c(pal.stain, stain_a))
	for body: Dictionary in bodies:
		stains.add(ground(body.p), float(body.birth), life, float(body.size) * 2.4, 6, Vector4(squash * 1.2, 0, 0, 0), S.c(pal.stain, stain_a * 0.8))
	_gpu_node("stains", stains.mesh(), SPRITES, -3, Tex.soft())
	_build_patches()
	if not cracks.is_empty():
		var strips := GpuLayers.Strips.new()
		for crack: Dictionary in cracks:
			var pts := PackedVector2Array()
			for p in (crack.pts as PackedVector2Array): pts.append(ground(p))
			strips.crack(pts, crack.w, crack.arr)
		var mesh := strips.mesh()
		_crack_pass("cracks", mesh, CRACKS, -3, 0, 1.0, float(pal.deep.r), 0.92)
		if kind in ["rock", "crystal"]: _crack_pass("crack_lips", mesh, CRACKS, -3, 2, 1.0, 0.68, 0.45)
		var strength := float(pal.crack_glow) * float(spec.crack_glow)
		if strength > 0.0:
			_crack_pass("crack_glow", mesh, CRACKS_ADD, -2, 1, 0.55, float(pal.glow.r), strength)
			_crack_pass("crack_halo", mesh, CRACKS_ADD, -2, 1, 2.4, float(pal.glow.r), strength * 0.35)
	var back := GpuLayers.Sprites.new()
	var front := GpuLayers.Sprites.new()
	for puff: Dictionary in puffs:
		var out: Vector2 = puff.out
		(front if puff.fg else back).add(ground(puff.p), float(puff.birth), float(puff.span), float(puff.size), 1 if puff.skirt else 0,
			Vector4(out.x, out.y, float(puff.rise), float(puff.seed)), Color(1.0, 0.0, 0.0, float(pal.dust_alpha) * 1.25))
	for item: Array in [["dust_back", back, -1], ["dust_front", front, 1]]:
		var shading := _gpu_node(item[0], (item[1] as GpuLayers.Sprites).mesh(), SPRITES, item[2], Tex.puff_atlas())
		shading.set_shader_parameter("tiles", 3.0)
		shading.set_shader_parameter("mode", 1)
		shading.set_shader_parameter("tint", pal.dust_tint)
		shading.set_shader_parameter("dust_height", float(spec.dust_height))
		shading.set_shader_parameter("dust_spread", float(spec.dust_spread))
	var lights := GpuLayers.Sprites.new()
	for part: Dictionary in debris:
		var at := ground(part.p)
		var drift := ground(part.drift)
		var s := float(part.size)
		match part.kind:
			"mote":
				var params := Vector4(drift.x * 0.4, drift.y * 0.4, float(part.v) * 0.18, float(part.seed))
				lights.add(at, float(part.birth), 0.9, s * 3.0, 2, params, Materials.v(float(pal.glow.r), 0.7, 0, 0.15))
				lights.add(at, float(part.birth), 0.9, s * 0.5, 3, params, Materials.v(float(pal.light.r), 1.0, 0, 0.15))
			"ember":
				var span := 2.0 * float(part.v) / Profile.GRAVITY + 0.2
				var params := Vector4(drift.x, drift.y, float(part.v), 0.04)
				lights.add(at, float(part.birth), span, s * 0.6, 4, params, Materials.v(float(pal.glow.r), 0.6))
				lights.add(at, float(part.birth), span, s * 3.0, 5, params, Materials.v(float(pal.glow.r), 0.8))
				lights.add(at, float(part.birth), span, s * 0.7, 5, params, Materials.v(0.97, 1.0))
			"spark":
				var params := Vector4(drift.x, drift.y, float(part.v), 0.03)
				lights.add(at, float(part.birth), 0.35, maxf(1.2, s * 0.3), 4, params, Materials.v(float(pal.light.r), 1.0))
				lights.add(at, float(part.birth), 0.35, s * 2.0, 5, params, Materials.v(float(pal.glow.r), 0.6))
	if kind == "lava" and spec.form == "scorch":
		# Ash glowing as it drifts up off the molten ground.
		var count := maxi(1, roundi(4.0 * _detail_scale()))
		for body: Dictionary in bodies:
			var seed := float(body.seed)
			var s := float(body.size)
			for k in count:
				var start := ground(body.p) + Vector2((S.h(seed + k * 5.0) - 0.5) * s * 1.6, 0)
				var params := Vector4(0, 0, s * (1.2 + S.h(seed + k) * 1.2), seed + k)
				var born := float(body.birth) + 0.15 + S.h(seed + k * 3.0) * 0.6
				lights.add(start, born, 1.1, 7.0, 2, params, Materials.v(float(pal.glow.r), 0.8, 0, s * 0.25 / 40.0))
				lights.add(start, born, 1.1, 2.8, 3, params, Materials.v(0.97, 1.0, 0, s * 0.25 / 40.0))
	_gpu_node("lights", lights.mesh(), SPRITES_ADD, 2, Tex.soft()).set_shader_parameter("gravity", Profile.GRAVITY)

func _crack_pass(key: String, mesh: ArrayMesh, shader: Shader, z: int, pass_kind: int, width: float, value: float, gain: float) -> void:
	var shading := _gpu_node(key, mesh, shader, z)
	shading.set_shader_parameter("layer_pass", pass_kind)
	shading.set_shader_parameter("width_scale", width)
	shading.set_shader_parameter("value", value)
	shading.set_shader_parameter("gain", gain)
	shading.set_shader_parameter("keep", float(pal.crack_keep))
	shading.set_shader_parameter("hold", float(spec.unit_time))
	shading.set_shader_parameter("linger", float(spec.crack_time))

## 灼地熔化 / 冰封大地: wobbly ground patches that spread from each break point.
func _build_patches() -> void:
	var scorch: bool = kind == "lava" and spec.form == "scorch"
	var frost: bool = kind == "crystal" and spec.form == "freeze"
	if not scorch and not frost: return
	var patches := GpuLayers.Patches.new()
	for body: Dictionary in bodies:
		var s := float(body.size)
		var seed := float(body.seed)
		var r := s * ((1.15 + S.h(seed + 3.0) * 0.55) if scorch else (1.2 + S.h(seed + 3.0) * 0.5))
		patches.patch(ground(body.p), _patch(body.p, r * (1.3 if scorch else 1.12), seed), _patch(body.p, r, seed + 0.5), float(body.birth))
	var shading := _gpu_node("patches", patches.mesh(), PATCHES, -3)
	shading.set_shader_parameter("kind", 0 if scorch else 1)
	shading.set_shader_parameter("hold", float(spec.unit_time) + (float(spec.crack_time) if scorch else 0.0))

## A GPU mesh layer at depth `z`; registered like the drawn layers so it follows the clock,
## the 画风 / 精细度 and the pixel lens.
func _gpu_node(key: String, mesh: ArrayMesh, shader: Shader, z: int, texture: Texture2D = null) -> ShaderMaterial:
	var node := MeshInstance2D.new()
	node.name = key.to_pascal_case()
	node.mesh = mesh
	node.texture = texture
	node.z_index = z
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shading := ShaderMaterial.new()
	shading.shader = shader
	shading.set_shader_parameter("ramp", Materials.ramp(String(spec.unit), spec.ramp))
	shading.set_shader_parameter("perspective", float(spec.perspective))
	shading.set_shader_parameter("life", life)
	node.material = shading
	add_child(node)
	if not _pixel.is_empty(): node.reparent(_pixel[1], false)
	layers[key] = node
	set_look(style, detail)
	return shading

# --- Shader warm-up ------------------------------------------------------------------------------

## Draws one nearly invisible impact of every kind under `parent` for a couple of frames so
## all ground-impact shaders are compiled before the first real one (no hitch on first use).
static func warm_up(parent: Node) -> void:
	if Engine.is_editor_hint() or not parent.is_inside_tree(): return
	var samples: Array[Node2D] = []
	for event: Dictionary in [{"unit": "earth"}, {"unit": "earth", "form": "surge"}, {"unit": "ice"}, {"unit": "magma"},
			{"unit": "magic"}, {"unit": "thunder"}]:
		var sample: Node2D = (load("res://vfx/quake_effect.gd") as GDScript).new().configure(event.merged({"x": 640.0, "y": 520.0, "shake": 0.0}))
		sample.modulate = Color(1, 1, 1, 0.004)
		parent.add_child(sample)
		sample.advance(0.25)
		samples.append(sample)
	var tree := parent.get_tree()
	for i in 2: await tree.process_frame
	for sample in samples: if is_instance_valid(sample): sample.queue_free()
