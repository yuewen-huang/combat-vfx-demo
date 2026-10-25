extends SceneTree
## Screenshot of the quake editor mid-effect (needs a window):
##   godot --path . --script res://tools/capture_quake_editor.gd -- --out=FILE [--combo=quake_earth] [--at=0.6] [--size=1600x900]
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var out := "user://quake_editor.png"
	var combo := "quake_earth"
	var at := 0.6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--combo="): combo = arg.trim_prefix("--combo=")
		elif arg.begins_with("--at="): at = float(arg.trim_prefix("--at="))
		elif arg.begins_with("--size="):
			var wh := arg.trim_prefix("--size=").split("x")
			DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	root.set_meta("flow_open", "res://combos/%s/combo.json" % combo)
	var editor: Control = load("res://quake_editor.tscn").instantiate()
	root.add_child(editor)
	for i in 5: await process_frame
	editor._seek(at)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
