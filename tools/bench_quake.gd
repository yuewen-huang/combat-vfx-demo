extends SceneTree
## Frame cost of ground impacts (needs a window; vsync is turned off to measure):
##   godot --path . --script res://tools/bench_quake.gd [-- --case=quake_slam,quake_holy] [--style=real] [--detail=explosive]
##     [--budget=3] (fail when any case adds more than this many ms per frame) [--fallback]
## For each preset: average and worst frame time over its busiest second, minus an empty stage.
const FRAMES := 150
const Quake = preload("res://vfx/quake_effect.gd")

func _initialize() -> void:
	call_deferred("_run")

func _measure(events: Array, renderer := "quake") -> Array:
	var stage: ComboStage = ComboStage.new() if renderer.is_empty() else load("res://vfx/%s_stage.gd" % renderer).new()
	root.add_child(stage)
	stage.help.visible = false
	stage.TIMELINE = ComboStage.parse_events(events)
	stage.play()
	var start := 0.0
	for e: Dictionary in events: if e.do == "quake": start = float(e.get("t", 0.0)); break
	if renderer != "quake": start = 0.0
	stage.set_process(false)
	while stage.clock < start + 0.05: stage.advance(1.0 / 60.0)
	Quake.Layer.spent.clear()
	var advance_us := 0
	var times: Array[float] = []
	var before := Time.get_ticks_usec()
	for i in FRAMES:
		var tick := Time.get_ticks_usec()
		stage.advance(1.0 / 60.0)
		advance_us += Time.get_ticks_usec() - tick
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - before) / 1000.0)
		before = now
	stage.free()
	times.sort()
	# Trimmed mean: the few slowest frames are usually the OS, not the effect.
	var kept := times.slice(0, times.size() - 3)
	var total := 0.0
	for t in kept: total += t
	var layers := {}
	for key: String in Quake.Layer.spent: layers[key] = snappedf(float(Quake.Layer.spent[key]) / FRAMES / 1000.0, 0.01)
	return [total / kept.size(), times[int(times.size() * 0.95)], snappedf(advance_us / float(FRAMES) / 1000.0, 0.01), layers]

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var names := PackedStringArray()
	var look := {}
	var budget := -1.0
	var over: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): names = arg.trim_prefix("--case=").split(",")
		elif arg.begins_with("--style="): look.quake_style = arg.trim_prefix("--style=")
		elif arg.begins_with("--detail="): look.quake_detail = arg.trim_prefix("--detail=")
		elif arg.begins_with("--budget="): budget = float(arg.trim_prefix("--budget="))
	if names.is_empty():
		for folder in DirAccess.get_directories_at("res://combos"):
			if folder.begins_with("quake_") or "--all" in OS.get_cmdline_user_args(): names.append(folder)
	ComboStyle.load_file("res://styles/default.json")
	ComboStyle.data.merge(look, true)
	Quake.Layer.profile = true
	for i in 30: await process_frame
	var empty := await _measure([{"t": 0.0, "do": "move", "by": [0, 0]}])
	print("empty stage: avg %.2f ms, p95 %.2f ms" % [empty[0], empty[1]])
	for name in names:
		# "preset:key=value:key=value" overrides fields of its quake events.
		var parts := name.split(":")
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combos/%s/combo.json" % parts[0]))
		for extra in parts.slice(1):
			var kv := extra.split("=")
			for e: Dictionary in parsed.events:
				if e.do == "quake": e[kv[0]] = JSON.parse_string(kv[1]) if kv[1].is_valid_float() or kv[1] in ["true", "false"] else kv[1]
		var style_path := "res://combos/%s/style.json" % parts[0]
		ComboStyle.load_file(style_path)
		ComboStyle.data.merge(look, true)
		RenderCaps.detect()
		var result := await _measure(parsed.events, String(ComboStyle.data.get("renderer", "")))
		print("%-16s avg %.2f ms (+%.2f), p95 %.2f ms | advance %.2f ms | draw %s" % [name, result[0], result[0] - empty[0], result[1], result[2], result[3]])
		if budget > 0.0 and result[0] - empty[0] > budget: over.append(name)
	if not over.is_empty():
		print("OVER BUDGET (%.1f ms): %s" % [budget, ", ".join(over)])
		quit(1)
		return
	if budget > 0.0: print("PASS: every case within %.1f ms per frame" % budget)
	quit()
