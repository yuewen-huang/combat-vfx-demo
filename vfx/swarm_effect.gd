extends Node2D
## GPU groups of leaves, feathers or sand, animated by a reproducible action clock.
const Materials = preload("res://vfx/quake/materials.gd")
const SHADER := preload("res://vfx/swarm/swarm.gdshader")
const PieceMaterials = preload("res://vfx/swarm/materials.gd")
const FORMS := ["cloud", "stream", "vortex", "sphere", "burst", "fall", "gone"]
const FORM_NAMES := {"cloud":"云团", "stream":"路径流动", "vortex":"旋涡", "sphere":"球形聚集", "burst":"爆散", "fall":"飘落", "gone":"消散"}
const MAX_COUNT := 16000
const FALLBACK_COUNT := 3000
const DEFAULTS := {"id": "group", "form": "cloud", "at": "target", "offset_x": 0.0, "offset_y": 0.0,
	"count": 6000, "ramp": "autumn", "size": 1.0,
	"radius": 160.0, "height": 220.0, "time": 0.6, "travel": 1.2, "length": 0.45, "width": 34.0,
	"path": [], "swirl": 2.2, "turbulence": 20.0, "tumble": 0.35, "linger": 1.2, "seed": 17}

var stage: Node2D
var spec: Dictionary
var clock := 0.0
var capacity := 0
## Current forms: {form, at, size, path, since0 (clock when the form began), travel}.
var _a: Dictionary
var _b: Dictionary = {}
var _morph_start := 0.0
var _morph_time := 0.6
var _end := INF
var _material: ShaderMaterial
var _quad: QuadMesh
## 配色 blends over a morph too: [deep, body, light, glint] before and after.
var _colours_from: Array = []
var _colours_to: Array = []
const COLOUR_KEYS := ["col_deep", "col_body", "col_light", "col_glint"]

static func normalized(event: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	out.merge(PieceMaterials.merge_defaults(event), true)
	if not event.has("ramp"): out.ramp = {"leaf":"autumn", "feather":"ivory", "sand":"dune"}[out.material]
	if not String(out.form) in FORMS: out.form = "cloud"
	return out

## Seconds the swarm with this event's id stays on screen after `event`.
static func tail(event: Dictionary) -> float:
	var s := normalized(event)
	return float(s.time) + (float(s.travel) if s.form == "stream" else 0.0) + float(s.linger) + 0.6

func configure(event: Dictionary, on_stage: Node2D) -> Node2D:
	stage = on_stage
	spec = normalized(event)
	name = "Swarm_" + String(spec.id)
	RenderCaps.detect()
	var detail := String(ComboStyle.data.get("quake_detail", "explosive"))
	var share := float(Materials.DETAIL_SCALE.get(detail, 1.0))
	var most := int(spec.count)
	var last := float(event.get("t", 0.0)) + tail(event) - 0.6
	for e: Dictionary in stage.TIMELINE:
		# Allocate once for the largest event of this group.
		var own: bool = e.get("do") == "swarm" and String(e.get("id", DEFAULTS.id)) == String(spec.id)
		if not own: continue
		most = maxi(most, int(e.get("count", DEFAULTS.count)))
		last = maxf(last, float(e.get("t", 0.0)) + tail(e) - 0.6)
	_end = last - float(event.get("t", 0.0))
	capacity = clampi(int(most * share), 50, FALLBACK_COUNT if RenderCaps.fallback else MAX_COUNT)
	_build()
	_a = _form_state(spec)
	_apply_look()
	_update()
	return self

func _build() -> void:
	var swarm := MultiMesh.new()
	swarm.transform_format = MultiMesh.TRANSFORM_2D
	swarm.use_custom_data = true
	var quad := QuadMesh.new()
	_quad = quad
	quad.size = Vector2.ONE
	if spec.material in ["leaf", "feather"]:
		quad.subdivide_width = 6
		quad.subdivide_depth = 2
	swarm.mesh = quad
	swarm.custom_aabb = AABB(Vector3(-4000, -4000, -1), Vector3(9280, 8720, 2))
	swarm.instance_count = capacity
	var random := RandomNumberGenerator.new()
	random.seed = int(spec.get("seed", hash(String(spec.id)) & 0xffff))
	for i in capacity:
		swarm.set_instance_transform_2d(i, Transform2D.IDENTITY)
		swarm.set_instance_custom_data(i, Color(random.randf(), random.randf(), random.randf(), random.randf()))
	var node := MultiMeshInstance2D.new()
	node.multimesh = swarm
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	node.material = _material
	add_child(node)

## The next event for this swarm: become `event`'s form over its `time`.
func morph(event: Dictionary) -> void:
	var next := normalized(spec.merged(event,true))
	var shown := _colours_now()
	if not _b.is_empty(): _a = _b
	_b = _form_state(next)
	_morph_start = clock
	_morph_time = maxf(float(next.time), 0.01)
	_end = maxf(_end, clock + tail(next) - 0.6)
	spec = next
	_apply_look()
	if not shown.is_empty(): _colours_from = shown

func _anchor(s: Dictionary) -> Vector2:
	var at: Variant = s.at
	var point := Vector2(640, 400)
	if at is Array and (at as Array).size() == 2: point = Vector2(float(at[0]), float(at[1]))
	elif String(at) == "attacker": point = stage.attacker.position
	elif String(at) == "target": point = stage.target.position + Vector2(0, -stage.TARGET_SIZE.y * 0.5)
	return point + Vector2(float(s.offset_x), float(s.offset_y))

func _form_state(s: Dictionary) -> Dictionary:
	var form := String(s.form)
	var at := _anchor(s)
	var radius := float(s.radius)
	var height := float(s.height)
	var size := Vector3(radius, height * 0.5, radius)
	match form:
		"vortex":
			at.y = stage.GROUND_Y
			size = Vector3(radius, height, radius)
		"fall": size = Vector3(radius, height, 300.0)
	var state := {"form": form, "at": Vector3(at.x, at.y, 0.0), "size": size, "since0": clock, "travel": maxf(float(s.travel), 0.01),
		"path": _path(s, at)}
	return state

## A stream's path: the event's points, or an arc from the attacker to the anchor.
func _path(s: Dictionary, at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Variant in s.path:
		if p is Array and (p as Array).size() == 2: out.append(Vector2(float(p[0]), float(p[1])))
	if out.size() < 2:
		# Up from behind the attacker, over the top, down through the anchor and on past it.
		var from: Vector2 = stage.attacker.position
		var ahead := signf(at.x - from.x) if at.x != from.x else 1.0
		out = PackedVector2Array([from + Vector2(-90 * ahead, 60), from + Vector2(-60 * ahead, -200), from.lerp(at, 0.5) + Vector2(0, -320),
			at + Vector2(170 * ahead, -200), at, at + Vector2(-150 * ahead, 40), at + Vector2(-260 * ahead, -120)])
	while out.size() > 12: out.remove_at(out.size() - 2)
	return out

## Switches 画风 live (the stage's Q key); the look is read from the style each time.
var detail: String:
	get: return String(ComboStyle.data.get("quake_detail", "explosive"))

func set_look(_style: String, _detail: String) -> void:
	_apply_look()

func _apply_look() -> void:
	var flexible := String(spec.material) in ["leaf", "feather"]
	_quad.subdivide_width = 6 if flexible else 0
	_quad.subdivide_depth = 2 if flexible else 0
	var stops: Array = Materials.stops("earth", spec.ramp)
	var colours := [Color(String(stops[1])).darkened(0.25), Color(String(stops[2])), Color(String(stops[3])), Color(String(stops[4])).lerp(Color.WHITE, 0.8)]
	_colours_from = _colours_now() if not _colours_to.is_empty() else colours
	_colours_to = colours
	var style := String(ComboStyle.data.get("quake_style", "real"))
	var detail := String(ComboStyle.data.get("quake_detail", "explosive"))
	if RenderCaps.fallback: style = "real"
	_material.set_shader_parameter("style", maxi(0, Materials.STYLES.find(style)))
	_material.set_shader_parameter("grain", maxf(ComboStyle.pixel, 1.0))
	_material.set_shader_parameter("piece_material", maxi(0, PieceMaterials.KEYS.find(String(spec.material))))
	for fields: Array in PieceMaterials.FIELDS.values():
		for field: Array in fields: _material.set_shader_parameter(field[0], float(spec[field[0]]))
	_material.set_shader_parameter("size_scale", float(spec.size))
	_material.set_shader_parameter("swirl", float(spec.swirl))
	_material.set_shader_parameter("turbulence", float(spec.turbulence))
	_material.set_shader_parameter("tumble", float(spec.tumble))
	_material.set_shader_parameter("stream_length", float(spec.length))
	_material.set_shader_parameter("stream_width", float(spec.width))
	_material.set_shader_parameter("count_fraction", clampf(float(spec.count) / maxf(capacity / maxf(float(Materials.DETAIL_SCALE.get(detail, 1.0)), 0.01), 1.0), 0.0, 1.0))

func _send(prefix: String, state: Dictionary) -> void:
	var since := clock - float(state.since0)
	_material.set_shader_parameter("form_" + prefix, FORMS.find(String(state.form)))
	_material.set_shader_parameter("at_" + prefix, state.at)
	_material.set_shader_parameter("size_" + prefix, state.size)
	var path: PackedVector2Array = state.path
	_material.set_shader_parameter("path_" + prefix, path)
	_material.set_shader_parameter("path_n_" + prefix, path.size())
	_material.set_shader_parameter("head_" + prefix, since / float(state.travel))
	_material.set_shader_parameter("since_" + prefix, since)

func _colours_now() -> Array:
	if _colours_to.is_empty(): return []
	var k := clampf((clock - _morph_start) / _morph_time, 0.0, 1.0) if not _b.is_empty() else 1.0
	var out: Array = []
	for i in 4: out.append((_colours_from[i] as Color).lerp(_colours_to[i], k))
	return out

func _update() -> void:
	_material.set_shader_parameter("time", clock)
	var colours := _colours_now()
	for i in 4: _material.set_shader_parameter(COLOUR_KEYS[i], colours[i])
	_send("a", _a)
	if _b.is_empty():
		_material.set_shader_parameter("form_b", -1)
	else:
		_send("b", _b)
		_material.set_shader_parameter("blend", clampf((clock - _morph_start) / _morph_time, 0.0, 1.0))
		_material.set_shader_parameter("blend_rate", 1.0 / _morph_time if clock - _morph_start < _morph_time else 0.0)
	var fade := clampf((_end - clock) / 0.6, 0.0, 1.0) * clampf(clock / 0.12, 0.0, 1.0)
	_material.set_shader_parameter("opacity", fade)

func advance(delta: float) -> void:
	clock += delta
	_update()

func is_done() -> bool:
	if clock >= _end: return true
	return not _b.is_empty() and _b.form == "gone" and clock - _morph_start >= _morph_time
