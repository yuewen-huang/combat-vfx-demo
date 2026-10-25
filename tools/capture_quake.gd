extends SceneTree
## Renders contact sheets of ground impacts for visual review (needs a window, not --headless):
##   godot --path . --script res://tools/capture_quake.gd -- --out=DIR [--case=name,name] [--times=0.1,0.2]
##     [--style=real|cel|pixel] [--detail=balanced|fine|ultimate|explosive] [--crop=x,y,w,h] [--shrink=2]
## Presets play in their own style.json and renderer.
## Each case is one row of frames at the given event times, cropped around the effect.
## Cases: every preset in res://combos/quake_*, plus "<unit>:<mode>" built on the fly.
const Quake = preload("res://vfx/quake_effect.gd")
var checker := false

## A checkerboard helps inspect ground heat distortion.
class Checker extends Node2D:
	func _draw() -> void:
		for y in range(0, 720, 32):
			for x in range(0, 1280, 32):
				if (x / 32 + y / 32) % 2 == 0: draw_rect(Rect2(x, y, 32, 32), Color(1, 1, 1, 0.13))
var CROP := Rect2i(200, 200, 880, 420)
var shrink := 2

func _initialize() -> void:
	call_deferred("_run")

## A case is a preset folder name or "<unit>:<mode>", either followed by ":reverse" or
## ":key=value" overrides, e.g. "thunder:sweep:ramp=violet" or "quake_holy:ramp=gold".
func _cases(names: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name in names:
		var parts := name.split(":")
		var events: Array = []
		var rest := 1
		if DirAccess.dir_exists_absolute("res://combos/" + parts[0]):
			var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combos/%s/combo.json" % parts[0]))
			events = parsed.events
		else:
			var event := {"t": 0.0, "do": "quake", "unit": parts[0], "mode": parts[1]}
			if parts[1] in ["sweep", "split"]: event.merge({"width": 160.0, "length": 600.0, "travel": 0.55})
			if parts[1] == "cone": event.merge({"x": 380.0, "width": 520.0, "cone": 60.0})
			events = [event]
			rest = 2
		for extra in parts.slice(rest):
			for e: Dictionary in events:
				if e.do != "quake": continue
				if extra == "reverse": e.reverse = true
				elif extra.contains("="):
					var kv := extra.split("=")
					var literal: bool = kv[1].is_valid_float() or kv[1] in ["true", "false"] or kv[1].begins_with("[")
					e[kv[0]] = JSON.parse_string(kv[1]) if literal else kv[1]
		var style_path := "res://combos/%s/style.json" % parts[0] if rest == 1 else "res://styles/default.json"
		out.append({"name": name.replace(":", "_").replace("=", "-").replace("\"", ""), "events": events, "style": style_path})
	return out

func _run() -> void:
	var out_dir := "user://quake_capture"
	var names := PackedStringArray()
	var look := {}
	var colourway := ""
	var times := PackedFloat32Array([0.05, 0.12, 0.22, 0.35, 0.5, 0.75, 1.05, 1.5])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--case="): names = arg.trim_prefix("--case=").split(",")
		elif arg.begins_with("--crop="):
			var v := arg.trim_prefix("--crop=").split(",")
			CROP = Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
		elif arg.begins_with("--shrink="): shrink = int(arg.trim_prefix("--shrink="))
		elif arg == "--checker": checker = true
		elif arg.begins_with("--style="): look.quake_style = arg.trim_prefix("--style=")
		elif arg.begins_with("--detail="): look.quake_detail = arg.trim_prefix("--detail=")
		elif arg.begins_with("--colorway="): colourway = arg.trim_prefix("--colorway=")
		elif arg.begins_with("--times="):
			times.clear()
			for part in arg.trim_prefix("--times=").split(","): times.append(float(part))
	if names.is_empty():
		for folder in DirAccess.get_directories_at("res://combos"):
			if folder.begins_with("quake_"): names.append(folder)
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	for case in _cases(names):
		ComboStyle.load_file(String(case.style))
		ComboStyle.data.merge(look, true)
		var renderer := String(ComboStyle.data.get("renderer", ""))
		var events: Array = case.events
		if not colourway.is_empty():
			for event: Dictionary in events:
				if event.get("do")=="quake":event.ramp=colourway
		var start := 0.0
		for e: Dictionary in events: if e.do == "quake": start = float(e.get("t", 0.0)); break
		var frames: Array[Image] = []
		for time in times:
			var stage: ComboStage = ComboStage.new() if renderer.is_empty() else load("res://vfx/%s_stage.gd" % renderer).new()
			root.add_child(stage)
			stage.set_process(false)
			stage.help.visible = false
			if checker:
				var board := Checker.new()
				board.z_index = 1
				stage.add_child(board)
			stage.TIMELINE = ComboStage.parse_events(events)
			stage.play()
			var clock := 0.0
			while clock < start + time - 0.0001:
				var step := minf(1.0 / 60.0, start + time - clock)
				stage.advance(step)
				clock += step
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			frames.append(image.get_region(CROP))
			stage.free()
		var sheet := Image.create(CROP.size.x * 4, CROP.size.y * ceili(frames.size() / 4.0), false, frames[0].get_format())
		for i in frames.size():
			sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, CROP.size), Vector2i((i % 4) * CROP.size.x, (i / 4) * CROP.size.y))
		if shrink > 1: sheet.resize(sheet.get_width() / shrink, sheet.get_height() / shrink, Image.INTERPOLATE_BILINEAR)
		sheet.save_png(out_dir.path_join(String(case.name) + ".png"))
		print("saved ", case.name)
	quit()
