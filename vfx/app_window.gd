extends Node
## One window command shared by gallery, flow, node editor and playback.
var saved_size := Vector2i(1280,720)
var saved_position := Vector2i.ZERO
var was_maximized := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless": return
	get_window().unresizable = false
	get_window().min_size = Vector2i(960,600)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER)):
		get_viewport().set_input_as_handled()
		toggle_fullscreen.call_deferred()

func toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless": return
	var window := get_window()
	if window.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = Window.MODE_MAXIMIZED if was_maximized else Window.MODE_WINDOWED
		if not was_maximized:
			window.size = saved_size
			window.position = saved_position
	else:
		was_maximized = window.mode == Window.MODE_MAXIMIZED
		saved_size = window.size
		saved_position = window.position
		window.mode = Window.MODE_FULLSCREEN
