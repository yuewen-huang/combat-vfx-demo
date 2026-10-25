extends Control
## Visual helpers only: no saved data and no input interception.
var editor: Control

func _draw() -> void:
	if editor == null or not editor.guides: return
	var geometry: Dictionary = editor.canvas_geometry()
	var line: PackedVector2Array = geometry.get("line", PackedVector2Array())
	var screen := PackedVector2Array()
	for point in line: screen.append(editor.to_preview(point))
	if screen.size() > 1: draw_polyline(screen, Color(0.55, 0.8, 1, 0.65), 1.5, true)
	var font := ThemeDB.fallback_font
	for handle: Dictionary in geometry.get("handles", []):
		var p: Vector2 = editor.to_preview(handle.point)
		var colour := Color("ffd58b") if String(handle.key) == editor.drag_handle else Color("8dd5ef")
		draw_circle(p, 7, Color("17232e"))
		draw_arc(p, 7, 0, TAU, 20, colour, 2, true)
		draw_line(p - Vector2(3, 0), p + Vector2(3, 0), colour)
		draw_line(p - Vector2(0, 3), p + Vector2(0, 3), colour)
		if p.x >= 0 and p.x < size.x - 40 and p.y >= 0 and p.y < size.y - 20:
			var offset := Vector2(11, -8)
			if handle.key == "center": offset.y = 18
			if handle.key == "ground_length": offset = Vector2(-28, 20)
			draw_string(font, p + offset, String(handle.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colour)
