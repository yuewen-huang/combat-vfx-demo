extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func wait_frames() -> void:
	for i in 5: await process_frame

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("SKIP: native window required")
		quit()
		return
	change_scene_to_file("res://flow_editor.tscn")
	await scene_changed
	await wait_frames()
	var old_size := root.size
	var old_position := root.position
	var controls := root.get_node("AppWindow")
	controls.toggle_fullscreen()
	await wait_frames()
	expect(root.mode==Window.MODE_FULLSCREEN,"Window enters native fullscreen")
	expect(root.size.x>=old_size.x and root.size.y>=old_size.y,"Fullscreen uses the available screen area")
	controls.toggle_fullscreen()
	await wait_frames()
	expect(root.mode==Window.MODE_WINDOWED,"Window returns from fullscreen")
	expect(root.size==old_size and root.position==old_position,"Window size and placement restore")
	var key := InputEventKey.new()
	key.keycode = KEY_F11
	key.pressed = true
	root.push_input(key,true)
	await wait_frames()
	expect(root.mode==Window.MODE_FULLSCREEN,"F11 reaches the global fullscreen command")
	key = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.alt_pressed = true
	key.pressed = true
	root.push_input(key,true)
	await wait_frames()
	expect(root.mode==Window.MODE_WINDOWED,"Alt+Enter restores window mode")
	print("%s: %d native fullscreen checks, %d failures" % ["PASS" if failures==0 else "FAIL",checks,failures])
	quit(0 if failures==0 else 1)
