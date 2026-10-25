extends SceneTree
## Exercise real control signals, including callbacks that rebuild their own panel.

var editor: Control

func _initialize() -> void:
	call_deferred("_check")

func _control(panel: Control, label: String) -> Control:
	for row in panel.get_children():
		if row is HBoxContainer and row.get_child(0).text == label:
			return row.get_child(1)
	return null

func _pick(panel: Control, label: String, index: int) -> bool:
	var control := _control(panel, label) as OptionButton
	assert(control != null, "Missing option: " + label)
	control.select(index)
	control.item_selected.emit(index)
	if not is_instance_valid(control):
		push_error("Signal emitter was freed during item_selected: " + label)
		quit(1)
		return false
	await process_frame
	await process_frame
	assert(not is_instance_valid(control), "Replaced controls must be released")
	assert(_control(panel, label) != null, "Replacement control missing")
	return true

func _check() -> void:
	editor = load("res://vfx/combo_editor.gd").new()
	root.add_child(editor)
	editor._open(editor._paths.find("res://combos/thunder_bolt/combo.json"))
	editor.data = {"events": [{"t": 0.0, "do": "cast", "element": "fire"}]}
	editor._select(0)
	for i in editor.ELEMENTS.size():
		if not await _pick(editor._inspector, "元素", i): return
		assert(editor.data.events[0].element == editor.ELEMENTS[i])
	for field in ["shape", "start", "end", "path"]:
		var label: String = {"shape": "形状", "start": "起点", "end": "终点", "path": "路径"}[field]
		var values: Array = editor.CAST_OPTIONS[field][0]
		for i in values.size():
			if not await _pick(editor._inspector, label, i): return
			assert(editor.data.events[0][field] == values[i])
		# Coordinate mode also changes the inspector's row layout.
		if field in ["start", "end"]:
			if not await _pick(editor._inspector, label, values.size()): return
			assert(editor.data.events[0][field] == [640, 360])
			assert(_control(editor._inspector, "坐标列表") is LineEdit)
	if not await _pick(editor._inspector, "路径", 1): return
	assert(_control(editor._inspector, "弧度") is SpinBox)
	if not await _pick(editor._inspector, "路径", 3): return
	assert(_control(editor._inspector, "弧度") == null)
	assert(_control(editor._inspector, "摆幅") is SpinBox)
	if not await _pick(editor._style_box, "绘制器", editor.RENDERERS.find("claw")): return
	editor.data = {"events": [{"t": 0.0, "do": "slash"}]}
	editor._select(0)
	for i in editor.CLAW_KINDS.size():
		if not await _pick(editor._inspector, "爪痕形状", i): return
		assert(editor.data.events[0].claw == editor.CLAW_KINDS[i])
	# Optional toggles rebuild from inside CheckBox.toggled too.
	editor.data = {"events": [{"t": 0.0, "do": "hit"}]}
	editor._select(0)
	for enabled in [true, false]:
		var row := _control(editor._inspector, "挑飞 / 砸地")
		var toggle := row.get_child(0) as CheckBox
		toggle.button_pressed = enabled
		assert(is_instance_valid(toggle))
		assert(editor.data.events[0].has("launch") == enabled)
		await process_frame
		await process_frame
		assert(not is_instance_valid(toggle))
	editor.queue_free()
	await process_frame
	print("PASS: real element/shape/start/end/path/claw/renderer/optional signals, dynamic rows and safe control lifetime")
	quit()
