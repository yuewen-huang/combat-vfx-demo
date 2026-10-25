extends Control
## Large phase blocks; top ruler seeks, blocks select/move events, ends trim phases.
signal seek(t: float)
var editor: Control
var _drag := ""
var _origin := 0.0
var _time := 0.0
var _phase: Array = []
var _blocks: Array[Dictionary] = []
var _drag_seconds := 1.0

func _x(t: float) -> float: return 12.0 + t / editor.total_time() * maxf(1.0, size.x - 24.0)
func _t(x: float) -> float: return clampf((x - 12.0) / maxf(1.0, size.x - 24.0), 0.0, 1.0) * editor.total_time()

func _draw() -> void:
	draw_style_box(editor.panel_style(), Rect2(Vector2.ZERO, size))
	_blocks.clear()
	var font := ThemeDB.fallback_font
	var seconds: float = editor.total_time()
	var spacing := 0.25 if seconds < 6.0 else maxf(0.5, ceilf(seconds / 12.0))
	for i in range(int(seconds / spacing) + 1):
		var x := _x(i * spacing)
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.07))
		draw_string(font, Vector2(x + 3, 15), "%.1f" % (i * spacing), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8996a8"))
	var e: Dictionary = editor.event()
	if not e.is_empty():
		var t := float(e.get("t", 0.0))
		var palette := [Color("508bc5"), Color("9f7947"), Color("7867ad"), Color("4a8c79"), Color("647082")]
		var phases: Array = editor.phase_blocks()
		for i in phases.size():
			var p: Array = phases[i]
			var w := maxf(2.0, _x(t + float(p[1])) - _x(t))
			var rect := Rect2(_x(t), 25.0, w, 26.0)
			draw_style_box(editor.panel_style(palette[i % palette.size()]), rect)
			if w > 32: draw_string(font, rect.position + Vector2(6, 18), String(p[0]), HORIZONTAL_ALIGNMENT_LEFT, w - 10, 12, Color.WHITE)
			if not String(p[2]).is_empty(): draw_line(rect.end - Vector2(3, 22), rect.end - Vector2(3, 4), Color(1, 1, 1, 0.7), 2)
			_blocks.append({"rect": rect, "phase": p})
			t += float(p[1])
	for i in editor.data.events.size():
		var item: Dictionary = editor.data.events[i]
		var x := _x(float(item.get("t", 0.0)))
		var colour: Color = editor.event_colour(item)
		draw_circle(Vector2(x, 66), 5 if i == editor.index else 3, colour)
		if i == editor.index: draw_arc(Vector2(x, 66), 8, 0, TAU, 20, Color.WHITE)
	var head := _x(editor.now())
	draw_line(Vector2(head, 0), Vector2(head, size.y), Color("ffe18b"), 2)
	draw_colored_polygon(PackedVector2Array([Vector2(head - 5, 0), Vector2(head + 5, 0), Vector2(head, 7)]), Color("ffe18b"))

func _gui_input(input: InputEvent) -> void:
	if input is InputEventMouseButton and input.button_index == MOUSE_BUTTON_LEFT:
		if not input.pressed:
			_drag = ""
			editor.end_gesture()
			return
		editor.begin_gesture("timeline")
		_origin = input.position.x
		_drag_seconds = editor.total_time()
		_time = float(editor.event().get("t", 0.0))
		_drag = "seek"
		if input.position.y > 55:
			var best := 11.0
			for i in editor.data.events.size():
				var d := absf(_x(float(editor.data.events[i].get("t", 0.0))) - input.position.x)
				if d < best:
					best = d
					editor.select_event(i)
					_time = float(editor.event().get("t", 0.0))
					_drag = "event"
		elif input.position.y >= 25:
			for block: Dictionary in _blocks:
				if block.rect.has_point(input.position):
					_phase = block.phase
					_drag = "phase" if block.rect.end.x - input.position.x < 10 and not String(_phase[2]).is_empty() else "event"
					break
		if _drag == "seek": seek.emit(_t(input.position.x))
	elif input is InputEventMouseMotion:
		var offset: float = (input.position.x - _origin) / maxf(1.0, size.x - 24) * _drag_seconds
		match _drag:
			"seek": seek.emit(_t(input.position.x))
			"event": editor.set_field("t", snappedf(maxf(0.0, _time + offset), 0.01))
			"phase": editor.set_phase(String(_phase[2]), snappedf(maxf(0.02, float(_phase[1]) + offset), 0.01))
