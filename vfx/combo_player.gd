@tool
class_name ComboPlayer
extends Node2D
## Root of a combo scene: plays `combo_file` (an event timeline, references/combo_events.md)
## in the look of `style_file`, on loop. In the editor it shows the stage at rest.
##
## Run flags (after `--`): --verify (headless self-test), --capture=FILE [--capture-at=S]
## (one screenshot, then quit; several times S,S,… save FILE_S.png each), --frames=DIR [--duration=S] (every frame, then quit).
## For recording a clip with Godot's movie maker: --start-at=S (begin S seconds into the
## combo) and --clean (no on-screen text), e.g.
##   godot --path . SCENE --write-movie clip.avi --fixed-fps 60 --quit-after 300 -- --start-at=14 --clean

@export_file("*.json") var combo_file := "":
	set(value):
		combo_file = value
		_rebuild()
@export_file("*.json") var style_file := "":
	set(value):
		style_file = value
		_rebuild()
## Start playing as soon as the scene runs.
@export var autoplay := true
## Seconds of rest before the combo plays again; negative plays it once.
@export var loop_pause := 1.0

const GALLERY := "res://main.tscn"
const Loading = preload("res://vfx/screen_loading.gd")

var demo: ComboStage
var shake_left := 0.0
var shake_duration := 0.0
var shake_strength := 0.0
var capture_path := ""
var capture_at := 0.5
## Seconds still to capture at, with --capture-at=S,S,…
var capture_times: Array[float] = []
var _many_captures := false
## Seconds of the combo skipped before the first frame (--start-at=S), and whether the
## on-screen text (help, captions, title, hit counter) is hidden (--clean): for recording.
var start_at := 0.0
var clean := false
var frames_dir := ""
var frames_duration := 4.0
var _frame_index := 0
var elapsed := 0.0
var capturing := false
var verify := false
var verify_age := 0.0
var _rest := -1.0
var _overlay: CanvasLayer

func _ready() -> void:
	RenderCaps.detect()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--capture-at="):
			for part in arg.trim_prefix("--capture-at=").split(","): capture_times.append(float(part))
			capture_at = capture_times[0]
			_many_captures = capture_times.size() > 1
		elif arg == "--verify": verify = true
		elif arg.begins_with("--frames="): frames_dir = arg.trim_prefix("--frames=")
		elif arg.begins_with("--duration="): frames_duration = float(arg.trim_prefix("--duration="))
		elif arg.begins_with("--start-at="): start_at = float(arg.trim_prefix("--start-at="))
		elif arg == "--clean": clean = true
	_rebuild()
	if Engine.is_editor_hint(): return
	DisplayServer.window_set_title(ComboStyle.title)
	if not frames_dir.is_empty(): DirAccess.make_dir_recursive_absolute(frames_dir)
	var recording := verify or not capture_path.is_empty() or not frames_dir.is_empty() or OS.get_cmdline_args().has("--write-movie")
	if recording: loop_pause = -1.0
	if autoplay or recording: demo.play()
	# Everything is a function of time, so stepping ahead quietly lands on the same frame.
	var skipped := 0.0
	while skipped < start_at:
		demo.advance(1.0 / 60.0)
		skipped += 1.0 / 60.0
	if clean:
		demo.overlay.visible = false
		_overlay.visible = false
		demo.counter.self_modulate = Color(1, 1, 1, 0)

func _notification(what: int) -> void:
	# Several combo scenes can be open in the editor and the style is static: reload ours
	# whenever this scene's tab comes back.
	if what == NOTIFICATION_ENTER_TREE and Engine.is_editor_hint() and demo != null: _rebuild()

## Builds the stage for the current files (again, when they change in the inspector).
func _rebuild() -> void:
	if not is_inside_tree(): return
	ComboStyle.load_file(style_file)
	for node: Node in [demo, _overlay]:
		if node != null: node.free()
	_overlay = CanvasLayer.new()
	_overlay.layer = 50
	add_child(_overlay)
	var hint := Label.new()
	hint.text = ComboStyle.title
	hint.position = Vector2(24, 675)
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", ComboStyle.c("text"))
	_overlay.add_child(hint)
	# "renderer": "<name>" in style.json picks res://vfx/<name>_stage.gd (a ComboStage subclass);
	# no renderer means the stock pixel smears.
	var renderer := String(ComboStyle.data.get("renderer", ""))
	if renderer.is_empty():
		demo = ComboStage.new()
	else:
		var stage_path := "res://vfx/%s_stage.gd" % renderer
		assert(ResourceLoader.exists(stage_path), "Unknown renderer '%s': %s is missing" % [renderer, stage_path])
		demo = load(stage_path).new()
	demo.combo_file = combo_file
	add_child(demo)

func request_screen_shake(duration: float, strength: float) -> void:
	shake_left = duration
	shake_duration = duration
	shake_strength = strength

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE \
			and ResourceLoader.exists(GALLERY) and get_tree().current_scene == self \
			and scene_file_path != GALLERY:
		get_viewport().set_input_as_handled()
		Loading.open_scene(self, GALLERY, "正在返回画廊")

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	shake_left = maxf(0.0, shake_left - delta)
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		var amount := shake_strength * shake_left / maxf(shake_duration, 0.001)
		camera.offset = Vector2(sin(elapsed * 137.0), cos(elapsed * 173.0)) * amount
	elapsed += delta
	_loop(delta)
	if not frames_dir.is_empty():
		_save_frame()
	if not capture_path.is_empty() and elapsed >= capture_at and not capturing:
		capturing = true
		_capture()
	if verify:
		verify_age += delta
		if verify_age > 30.0 + demo.clock_end():
			push_error("Combo did not settle")
			get_tree().quit(1)
		elif demo.is_settled():
			var expected: int = demo.expected_hits()
			if demo.hits != expected or (expected == 0 and not _has_quake()):
				push_error("Expected %d hits, landed %d" % [expected, demo.hits])
				get_tree().quit(1)
			else:
				print("PASS: %d hits landed" % demo.hits)
				get_tree().quit()
			verify = false

## Plays the combo again after a rest once it has settled.
func _loop(delta: float) -> void:
	if loop_pause < 0.0 or demo.playing or not demo.is_settled() or (demo.hits == 0 and not _has_quake()):
		_rest = -1.0
		return
	if _rest < 0.0: _rest = loop_pause
	_rest -= delta
	if _rest <= 0.0:
		_rest = -1.0
		demo.play()

func _has_quake() -> bool:
	return demo.TIMELINE.any(func(e: Dictionary) -> bool: return e.do in ["quake","swarm","caption","impact","slash","cast","cut","charge"])

func _save_frame() -> void:
	var index := _frame_index
	_frame_index += 1
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(frames_dir.path_join("frame_%04d.png" % index))
	if elapsed >= frames_duration: get_tree().quit()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var path := capture_path
	if _many_captures:
		path = capture_path.get_basename() + "_%.2f.png" % capture_at
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK: push_error("Capture failed: %s" % error)
	if capture_times.size() > 1 and error == OK:
		capture_times.pop_front()
		capture_at = capture_times[0]
		capturing = false
		return
	get_tree().quit(0 if error == OK else 1)
