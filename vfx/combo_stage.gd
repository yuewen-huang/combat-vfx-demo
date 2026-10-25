@tool
class_name ComboStage
extends Node2D
## Fighting-game sword combo: an abstract attacker point strikes a target block. Every cut
## is a crescent smear grown from the attacker (it follows the attacker and never flies
## off); each hit lands on the target with a star spark, a white flash, a shared hit-stop
## with the target shaking in place, knockback / launch and a hit counter. The events
## come from combo.json. Keys: 1 / Space play, 2 slow motion, R reset. In the editor it
## draws the stage at rest, so a combo scene shows what it is before you run it.

const GROUND_Y := 520.0
const ATTACKER_START := Vector2(430, GROUND_Y - 70)
const TARGET_START := Vector2(575, GROUND_Y)
const TARGET_SIZE := Vector2(44, 96)
const GRAVITY := 1500.0
const SLOW_SPEED := 0.25
const COUNTER_POP := 0.14

## Timeline in combo seconds; the combo clock stops during hit-stop.
## slash: crescent anchored on the attacker (degrees, y down, facing right); a very flat
## one (squash ~0.16) through 0° is the thrust. move: attacker glides by `by`.
## hit: target reaction. charge: glint on the attacker. flash_step: instant move with a
## smear left behind. cut: a straight cut drawn across the target. camera: the view eases
## over `time` s to `zoom` (1 = the whole stage, 2 = twice as close) centred on `at` [x, y]
## (kept inside the stage).
## Read from the combo's combo.json (references/combo_events.md), sorted by time.
var TIMELINE: Array = []
## The combo.json this stage plays (set by ComboPlayer before it enters the tree).
var combo_file := ""

## Values an event may leave out.
const EVENT_DEFAULTS := {
	"slash": {"radius": 140.0, "from": -70.0, "to": 70.0, "width": 44.0},
	"move": {"by": [0, 0], "time": 0.08},
	"hit": {"push": 60.0, "stop": 0.05, "shake": 2.5, "spark": 46.0},
	"flash_step": {"past": 140.0},
	"cut": {"angle": 0.0},
	"camera": {"zoom": 1.0, "at": [640, 360], "time": 0.5},
}

## Reads the events; `by` becomes a Vector2 and `palette` a StringName.
static func load_timeline(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary or not (parsed as Dictionary).get("events") is Array:
		push_error("combo.json needs an \"events\" array")
		return []
	return parse_events(parsed.events)

## The same for an events array already in memory (the manual editor's live preview).
static func parse_events(raw_events: Array) -> Array:
	var events: Array = []
	for raw: Variant in raw_events:
		var e: Dictionary = (raw as Dictionary).duplicate()
		e.t = float(e.get("t", 0.0))
		var defaults: Dictionary = EVENT_DEFAULTS.get(e.get("do", ""), {})
		for key: String in defaults: if not e.has(key): e[key] = defaults[key]
		if e.has("by"): e.by = Vector2(float(e.by[0]), float(e.by[1]))
		if e.has("palette"): e.palette = StringName(e.palette)
		elif e.get("do") in ["slash", "hit", "cut"]: e.palette = &"normal"
		events.append(e)
	events.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.t < y.t)
	return events

## Combo end including long ground-propagation tails (used by the verification deadline).
func clock_end() -> float:
	var last := 0.0 if TIMELINE.is_empty() else float(TIMELINE[-1].t)
	for event: Dictionary in TIMELINE:
		if event.do == "quake":
			var profile := preload("res://vfx/quake/propagation.gd")
			last = maxf(last, float(event.t) + profile.lifetime(profile.normalized(event)))
		elif event.do == "swarm":
			last = maxf(last, float(event.t) + preload("res://vfx/swarm_effect.gd").tail(event))
		elif event.do == "caption":
			last = maxf(last, float(event.t) + preload("res://vfx/caption_effect.gd").lifetime(event))
		elif event.do == "impact":
			last = maxf(last, float(event.t) + preload("res://vfx/impact_effect.gd").lifetime(event))
	return last

func expected_hits() -> int:
	return TIMELINE.filter(func(e: Dictionary) -> bool: return e.do == "hit").size()
## Combo seconds after the last event until everything has settled.
const SETTLE := 1.1

var attacker: Node2D
var target: Node2D
var fx: Node2D
var counter: Label
var help: Label
var speed := 1.0
var playing := false
var clock := 0.0
var hits := 0
var _next := 0
var _stop := 0.0
var _moves: Array[Dictionary] = []
var _target_velocity := Vector2.ZERO
var _target_flash := 0.0
var _counter_age := 99.0
var _camera: Camera2D
## {from_zoom, to_zoom, from, to, age, time} while the camera eases somewhere.
var _view := {}
## Text that stays put on screen whatever the camera does (help, captions).
var overlay: CanvasLayer
## Depth layers. 中景 is the stage itself (`fx`, the attacker and the target). 近景 (`near_fx`)
## draws over it and follows the camera with extra parallax, so it lines up with the stage
## at rest and slides past faster when the camera moves. 屏幕层 (`screen_fx`) is fixed to the
## screen (captions, impact frames). 远景 belongs to the game's own background.
const NEAR_PARALLAX := 1.3
var near_layer: CanvasLayer
var near_fx: Node2D
var screen_layer: CanvasLayer
var screen_fx: Node2D
## Effects drawn behind the attacker and target.
var back_fx: Node2D
## Persistent groups indexed by their event id.
var actors := {}
## 黑边: cinema bars in 屏幕层, style.json "letterbox" (share of the screen height, each).
var _bars: Array[ColorRect] = []

class Marker extends Node2D:
	## The abstract attacker: a diamond core with a ground shadow.
	var ground := 0.0
	func _draw() -> void:
		var shadow_y := ground - position.y
		draw_rect(Rect2(-14, shadow_y - 2, 28, 4), Color(0, 0, 0, 0.35))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -16), Vector2(11, 0), Vector2(0, 16), Vector2(-11, 0)]), ComboStyle.c("outline"))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -12), Vector2(8, 0), Vector2(0, 12), Vector2(-8, 0)]), ComboStyle.c("blade"))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -6), Vector2(4, 0), Vector2(0, 6), Vector2(-4, 0)]), ComboStyle.c("marker_core"))

class Block extends Node2D:
	## The target: a padded block whose origin is its feet.
	var flash := 0.0
	var shake := 0.0
	func _draw() -> void:
		var size := ComboStage.TARGET_SIZE
		var at := Vector2(-size.x / 2.0 + shake, -size.y)
		draw_rect(Rect2(at - Vector2(3, 3), size + Vector2(6, 6)), ComboStyle.c("outline"))
		draw_rect(Rect2(at, size), ComboStyle.c("flash") if flash > 0.0 else ComboStyle.c("dummy"))
		if flash <= 0.0:
			draw_rect(Rect2(at + Vector2(0, size.y * 0.3), Vector2(size.x, 8)), ComboStyle.c("dummy_band"))
			draw_rect(Rect2(at + Vector2(0, size.y * 0.66), Vector2(size.x, 8)), ComboStyle.c("dummy_band"))

func _ready() -> void:
	# The manual editor builds stages without a file and fills TIMELINE itself.
	TIMELINE = load_timeline(combo_file) if not combo_file.is_empty() else []
	_camera = Camera2D.new()
	_camera.position = Vector2(640, 360)
	add_child(_camera)
	if not Engine.is_editor_hint(): _camera.make_current()
	back_fx = Node2D.new()
	add_child(back_fx)
	target = Block.new()
	add_child(target)
	attacker = Marker.new()
	attacker.ground = GROUND_Y
	add_child(attacker)
	fx = Node2D.new()
	fx.z_index = 5
	add_child(fx)
	near_layer = CanvasLayer.new()
	near_layer.layer = 2
	add_child(near_layer)
	near_fx = Node2D.new()
	near_layer.add_child(near_fx)
	screen_layer = CanvasLayer.new()
	screen_layer.layer = 15
	add_child(screen_layer)
	screen_fx = Node2D.new()
	screen_layer.add_child(screen_fx)
	for i in 2:
		var bar := ColorRect.new()
		bar.color = Color("040207")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen_layer.add_child(bar)
		_bars.append(bar)
	counter = Label.new()
	counter.add_theme_font_size_override("font_size", 40)
	counter.add_theme_color_override("font_outline_color", ComboStyle.c("outline"))
	counter.add_theme_constant_override("outline_size", 10)
	counter.z_index = 10
	add_child(counter)
	overlay = CanvasLayer.new()
	overlay.layer = 20
	add_child(overlay)
	help = Label.new()
	help.text = ComboStyle.t("combo_help") % ComboStyle.t("slow_off")
	help.position = Vector2(24, 20)
	help.add_theme_font_size_override("font_size", 22)
	help.add_theme_color_override("font_color", ComboStyle.c("text"))
	overlay.add_child(help)
	reset()

func reset() -> void:
	playing = false
	clock = 0.0
	hits = 0
	_next = 0
	_stop = 0.0
	_moves.clear()
	_target_velocity = Vector2.ZERO
	_target_flash = 0.0
	_counter_age = 99.0
	for holder in effect_holders(): for child in holder.get_children(): child.free()
	actors.clear()
	var bar := clampf(float(ComboStyle.data.get("letterbox", 0.0)), 0.0, 0.3) * 720.0
	for i in 2:
		_bars[i].visible = bar > 0.0
		_bars[i].position = Vector2(0, 0 if i == 0 else 720.0 - bar)
		_bars[i].size = Vector2(1280, bar)
	attacker.position = ATTACKER_START
	target.position = TARGET_START
	_view = {}
	_camera.zoom = Vector2.ONE
	_camera.position = Vector2(640, 360)
	counter.visible = false
	_refresh()

func play() -> void:
	reset()
	playing = true

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_1, KEY_KP_1, KEY_SPACE: play()
		KEY_2, KEY_KP_2:
			speed = SLOW_SPEED if speed == 1.0 else 1.0
			help.text = ComboStyle.t("combo_help") % ComboStyle.t("slow_on" if speed < 1.0 else "slow_off")
		KEY_R: reset()

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	advance(delta * speed)
	update_layers()

## Every node whose children are running effects, in drawing order.
func effect_holders() -> Array[Node]:
	return [back_fx, fx, attacker, near_fx, screen_fx]

## Places 近景 from the stage camera (zoom, centre, shake offset) with extra parallax.
func update_layers() -> void:
	var zoom := _camera.zoom.x
	var centre := _camera.get_screen_center_position()
	var near_zoom := 1.0 + (zoom - 1.0) * NEAR_PARALLAX
	var near_centre := Vector2(640, 360) + (centre - Vector2(640, 360)) * NEAR_PARALLAX
	near_layer.transform = Transform2D(0.0, Vector2.ONE * near_zoom, 0.0, Vector2(640, 360) - near_centre * near_zoom)

## Steps the whole demo; tests call this directly.
func advance(delta: float) -> void:
	if delta <= 0.0: return
	_counter_age += delta
	_target_flash = maxf(_target_flash - delta, 0.0)
	if _stop > 0.0:
		# Hit-stop: the combo, the attacker, every effect and the target hold still; the
		# target only shudders in place.
		_stop -= delta
		(target as Block).shake = 3.0 if int(_stop / 0.02) % 2 == 0 else -3.0
		_refresh()
		return
	(target as Block).shake = 0.0
	if playing:
		clock += delta
		while _next < TIMELINE.size() and TIMELINE[_next].t <= clock:
			_fire(TIMELINE[_next])
			_next += 1
			if _stop > 0.0: break
		if _next >= TIMELINE.size() and (TIMELINE.is_empty() or clock > maxf(float(TIMELINE[-1].t) + SETTLE, clock_end())): playing = false
	_update_moves(delta)
	_update_view(delta)
	_update_target(delta)
	for holder in effect_holders():
		for part in holder.get_children():
			if not part.has_method("advance"): continue
			part.advance(delta)
			if part.is_done(): part.queue_free()
	_refresh()

func is_settled() -> bool:
	if playing or target.position.y < GROUND_Y or not is_zero_approx(_target_velocity.x): return false
	for holder in effect_holders():
		for part in holder.get_children():
			if not part.is_queued_for_deletion(): return false
	return true

func _fire(event: Dictionary) -> void:
	match event.do:
		"caption": screen_fx.add_child(preload("res://vfx/caption_effect.gd").new().configure(event))
		"impact": screen_fx.add_child(preload("res://vfx/impact_effect.gd").new().configure(event))
		"swarm":
			# 群体 in 近景: the first event with an id creates the swarm, later ones morph it.
			var id := String(event.get("id", "group"))
			var swarm: Variant = actors.get(id)
			if swarm != null and is_instance_valid(swarm) and not swarm.is_queued_for_deletion() and not swarm.is_done():
				swarm.morph(event)
			else:
				swarm = preload("res://vfx/swarm_effect.gd").new()
				near_fx.add_child(swarm)
				swarm.configure(event, self)
				actors[id] = swarm
		"quake":
			fx.add_child(preload("res://vfx/quake_effect.gd").new().configure(event))
		"slash":
			attacker.add_child(PixelSlash.new().configure({"shape": &"crescent", "radius": float(event.radius),
				"squash": float(event.get("squash", 1.0)), "tilt": deg_to_rad(float(event.get("tilt", 0.0))),
				"start_angle": deg_to_rad(float(event.from)), "end_angle": deg_to_rad(float(event.to)),
				"width": float(event.width), "duration": float(event.get("duration", 0.045)), "hold": 0.04, "fade": float(event.get("fade", 0.13)),
				"line_gap": 6.0, "line_width": 5.0, "palette": event.palette}))
		"move":
			_moves.append({"from": attacker.position, "to": attacker.position + event.by, "age": 0.0, "time": float(event.time)})
		"hit": _hit(event)
		"charge":
			attacker.add_child(PixelSlash.new().configure({"shape": &"star", "radius": 80.0, "width": 14.0,
				"duration": 0.06, "hold": 0.16, "fade": 0.06, "burst_spikes": 4, "spark_dir": PI / 4.0, "palette": &"gold"}))
			attacker.add_child(PixelSlash.new().configure({"shape": &"sparks", "spark_count": 16, "spark_spread": PI,
				"spark_speed": Vector2(300, 480), "spark_life": Vector2(0.2, 0.2), "spark_gravity": 0.0, "spark_converge": true,
				"spark_seed": 3, "palette": &"gold"}))
		"flash_step":
			var from := attacker.position
			var to := Vector2(target.position.x + float(event.past), ATTACKER_START.y)
			attacker.position = to
			_moves.clear()
			fx.add_child(PixelSlash.new().configure({"shape": &"line", "from_point": from + Vector2(-40, 0),
				"to_point": to + Vector2(30, 0), "width": 30.0, "duration": 0.035, "tail": 0.3,
				"line_gap": 5.0, "line_width": 3.0, "palette": &"gold", "arrow_head": false}))
			_stop = 0.1  # the stillness after 一闪, before the cuts appear
			_shake(3.0, 0.08)
		"camera":
			var at: Array = event.at
			_view = {"from_zoom": _camera.zoom.x, "to_zoom": maxf(float(event.zoom), 1.0), "from": _camera.position,
				"to": Vector2(float(at[0]), float(at[1])), "age": 0.0, "time": maxf(float(event.time), 0.001)}
		"cut":
			var middle := target.position + Vector2(0, -TARGET_SIZE.y * 0.5)
			var along := Vector2.from_angle(deg_to_rad(float(event.angle))) * 95.0
			fx.add_child(PixelSlash.new().configure({"shape": &"line", "from_point": middle - along,
				"to_point": middle + along, "width": 22.0, "duration": 0.03, "tail": 0.16,
				"line_gap": 4.0, "line_width": 3.0, "palette": event.palette, "arrow_head": false}))

func _hit(event: Dictionary) -> void:
	hits += 1
	_counter_age = 0.0
	_target_flash = 0.06
	var finisher: bool = event.get("finisher", false)
	var at := target.position + Vector2(-TARGET_SIZE.x * 0.3, -TARGET_SIZE.y * 0.55)
	if finisher: at = target.position + Vector2(0, -TARGET_SIZE.y * 0.5)
	var spark := float(event.spark)
	fx.add_child(PixelSlash.new().configure({"shape": &"star", "center": at, "radius": spark, "width": spark * 0.22,
		"duration": 0.03, "hold": 0.03 if not finisher else 0.08, "fade": 0.12 if not finisher else 0.2,
		"burst_spikes": 8 if not finisher else 12, "spark_dir": deg_to_rad(15.0 * hits), "palette": event.palette}))
	fx.add_child(PixelSlash.new().configure({"shape": &"sparks", "center": at, "spark_count": 10 if not finisher else 28,
		"spark_dir": 0.0, "spark_spread": deg_to_rad(60.0) if not finisher else PI, "spark_speed": Vector2(260, 620) if not finisher else Vector2(300, 900),
		"spark_life": Vector2(0.16, 0.3), "spark_seed": hits, "palette": event.palette}))
	if finisher:
		fx.add_child(PixelSlash.new().configure({"shape": &"burst", "center": at, "radius": 170.0, "width": 12.0,
			"duration": 0.12, "tail": 0.2, "burst_spikes": 0, "palette": event.palette}))
		fx.add_child(PixelSlash.new().configure({"shape": &"burst", "center": Vector2(at.x, GROUND_Y), "radius": 240.0, "width": 8.0,
			"squash": 0.14, "duration": 0.22, "tail": 0.18, "burst_spikes": 0, "palette": event.palette}))
	_target_velocity.x += float(event.push)
	if event.has("launch"): _target_velocity.y = float(event.launch)
	_stop = float(event.stop)
	_shake(float(event.shake), 0.22 if finisher else 0.09)

func _shake(strength: float, duration: float) -> void:
	var feedback := get_parent()
	if feedback != null and feedback.has_method("request_screen_shake"):
		feedback.request_screen_shake(duration, strength)

func _update_moves(delta: float) -> void:
	for move in _moves:
		move.age = minf(move.age + delta, move.time)
		var t := PixelSlash.ease_swing(move.age / move.time)
		attacker.position = (move.from as Vector2).lerp(move.to, t)
	_moves = _moves.filter(func(m: Dictionary) -> bool: return m.age < m.time)

## Eases the camera towards the last camera event's view, never showing past the stage.
func _update_view(delta: float) -> void:
	if _view.is_empty(): return
	_view.age = minf(float(_view.age) + delta, float(_view.time))
	var t := smoothstep(0.0, 1.0, float(_view.age) / float(_view.time))
	var zoom := lerpf(float(_view.from_zoom), float(_view.to_zoom), t)
	var half := Vector2(640, 360) / zoom
	var at := (_view.from as Vector2).lerp(_view.to, t)
	_camera.zoom = Vector2.ONE * zoom
	_camera.position = Vector2(clampf(at.x, half.x, 1280.0 - half.x), clampf(at.y, half.y, 720.0 - half.y))

func _update_target(delta: float) -> void:
	var airborne := target.position.y < GROUND_Y - 0.5 or _target_velocity.y < 0.0
	if airborne:
		_target_velocity.y += GRAVITY * delta
	target.position += _target_velocity * delta
	if target.position.y >= GROUND_Y:
		target.position.y = GROUND_Y
		# Slammed targets bounce once; others settle.
		_target_velocity.y = -_target_velocity.y * 0.45 if _target_velocity.y > 500.0 else 0.0
	# Ground friction slides the target to a stop; air keeps its drift.
	if not airborne: _target_velocity.x = move_toward(_target_velocity.x, 0.0, 1600.0 * delta)
	target.position.x = clampf(target.position.x, 80.0, 1200.0)

func _refresh() -> void:
	(target as Block).flash = _target_flash
	target.queue_redraw()
	attacker.queue_redraw()
	counter.visible = hits > 0
	counter.text = ComboStyle.t("hits") % hits
	var finished := hits >= expected_hits()
	counter.add_theme_color_override("font_color", ComboStyle.c("text_gold") if finished else ComboStyle.c("blade"))
	var pop := 1.0 + 0.45 * clampf(1.0 - _counter_age / COUNTER_POP, 0.0, 1.0)
	counter.scale = Vector2.ONE * pop
	counter.position = Vector2(target.position.x + 40.0, 170.0)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), ComboStyle.c("background"))
	for x in range(0, 1281, 64): draw_line(Vector2(x, 0), Vector2(x, 720), Color(1, 1, 1, 0.04))
	for y in range(0, 721, 64): draw_line(Vector2(0, y), Vector2(1280, y), Color(1, 1, 1, 0.04))
	draw_line(Vector2(0, GROUND_Y), Vector2(1280, GROUND_Y), ComboStyle.c("ground"), 2.0)
