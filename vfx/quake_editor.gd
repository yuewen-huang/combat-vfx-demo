extends Control
## 地震特效编辑器: a dedicated editor for ground impacts (landing slams, earthquakes,
## ground waves). Big live preview you can scrub and drag the impact around in; scenario
## templates, material and propagation pickers, compact stage table; saves ordinary combos
## (res://combos/<name>/) that the gallery and the combo editor open as well.
##
## Keys: Space play from the start, ← / → step a frame while paused, Q 画风, W 精细度,
## Ctrl+Z / Ctrl+Y undo / redo, Ctrl+S save, Esc back to the gallery.
const Quake = preload("res://vfx/quake_effect.gd")
const Profile = preload("res://vfx/quake/propagation.gd")
const Materials = preload("res://vfx/quake/materials.gd")
const COMBOS := "res://combos"
const GALLERY := "res://main.tscn"
const STEP := 1.0 / 60.0
const MODES := [["radial", "圆心扩散", "向心收拢"], ["sweep", "单向推进", "反向推进"],
	["split", "中心向两端", "两端向中心"], ["cone", "扇形扩散", "扇形收拢"]]
const SPEEDS := [1.0, 0.5, 0.25, 0.1]
const DEBRIS_NAMES := {"auto": "跟随材质", "none": "无", "stone": "碎石", "ice": "冰屑", "ember": "熔滴", "spark": "火花", "mote": "光点"}
## Scenario templates: shape and timing for the three uses this editor is for.
const TEMPLATES := [
	["落地攻击", "从落点向四周爆开：短促、强烈、震屏重", {"mode": "radial", "reverse": false, "width": 300.0, "length": 0.0,
		"rhythm": "continuous", "travel": 0.32, "ease": 0.8, "strength": 1.25, "spacing": 55.0, "unit_time": 0.9,
		"shake": 10.0, "flash": 1.2, "x": 640.0}],
	["地震攻击", "沿地面一路推进，分三段震—停—震", {"mode": "sweep", "reverse": false, "width": 180.0, "length": 560.0,
		"rhythm": "staged", "stages": Profile.STAGES, "strength": 1.0, "spacing": 60.0, "unit_time": 0.85, "shake": 7.0,
		"flash": 1.0, "x": 640.0}],
]

class Host extends Node2D:
	## Parent of the preview stage: provides the screen shake ComboPlayer normally gives.
	var left := 0.0
	var span := 0.0
	var strength := 0.0
	var clock := 0.0
	var enabled := true
	func request_screen_shake(duration: float, amount: float) -> void:
		if not enabled: return
		left = duration
		span = duration
		strength = amount
	func tick(delta: float) -> Vector2:
		clock += delta
		left = maxf(0.0, left - delta)
		return Vector2(sin(clock * 137.0), cos(clock * 173.0)) * strength * left / maxf(span, 0.001)

class Scrubber extends Control:
	## Time ruler under the preview: push / pause segments of the front, playhead, drag to seek.
	signal seek(t: float)
	var editor: Control
	var dragging := false
	func _seconds() -> float: return editor.total_time()
	func _x(t: float) -> float: return 10.0 + t / _seconds() * (size.x - 20.0)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("141920"))
		var font := ThemeDB.fallback_font
		var seconds := _seconds()
		for i in int(seconds / 0.1) + 1:
			var x := _x(i * 0.1)
			var major := i % 5 == 0
			draw_line(Vector2(x, size.y - (12 if major else 6)), Vector2(x, size.y), Color(1, 1, 1, 0.25 if major else 0.1))
			if major: draw_string(font, Vector2(x + 3, size.y - 4), "%.1fs" % (i * 0.1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("6b7785"))
		var e: Dictionary = editor.event()
		if not e.is_empty():
			var spec := Profile.normalized(e)
			var start := float(e.get("t", 0.0))
			var y := 14.0
			var colour: Color = Materials.swatch(String(spec.unit), spec.ramp)
			draw_rect(Rect2(Vector2(_x(start), y + 14), Vector2(_x(start + Profile.lifetime(spec)) - _x(start), 4)), Color(colour, 0.25))
			if spec.rhythm == "staged":
				var clock := start
				for step: Dictionary in spec.stages:
					draw_rect(Rect2(Vector2(_x(clock), y), Vector2(maxf(_x(clock + float(step.time)) - _x(clock), 2.0), 12)), colour)
					clock += float(step.time)
					draw_rect(Rect2(Vector2(_x(clock), y + 4), Vector2(_x(clock + float(step.pause)) - _x(clock), 4)), Color(colour, 0.35))
					clock += float(step.pause)
			else:
				draw_rect(Rect2(Vector2(_x(start), y), Vector2(maxf(_x(start + float(spec.travel)) - _x(start), 2.0), 12)), colour)
			draw_string(font, Vector2(_x(start) + 4, y + 11), "推进", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.7))
		var head := _x(editor.now())
		draw_line(Vector2(head, 0), Vector2(head, size.y), Color("ffe36b"), 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(head - 6, 0), Vector2(head + 6, 0), Vector2(head, 8)]), Color("ffe36b"))
	func _gui_input(input: InputEvent) -> void:
		if input is InputEventMouseButton and input.button_index == MOUSE_BUTTON_LEFT:
			dragging = input.pressed
			if input.pressed: seek.emit(_time(input.position.x))
		elif input is InputEventMouseMotion and dragging:
			seek.emit(_time(input.position.x))
	func _time(x: float) -> float:
		return clampf((x - 10.0) / (size.x - 20.0), 0.0, 1.0) * _seconds()

var data: Dictionary = {"events": []}
var style: Dictionary = {}
var combo_path := ""
var index := -1
var stage: ComboStage
var dirty := false
var playing := true
var looping := true
var speed := 1.0
var zoom := 1.0
var _paths: PackedStringArray = []
var _undo: Array[String] = []
var _redo: Array[String] = []
var _last_tag := ""
var _last_time := 0.0
var _rebuild_in := -1.0
var _rest := -1.0
var _filling := false
var _leave_armed := false
var _dragging_preview := false

var _picker: OptionButton
var _status: Label
var _save_as: LineEdit
var _viewport: SubViewport
var _host: Host
var _preview: TextureRect
var _scrubber: Control
var _inspector: VBoxContainer
var _play_button: Button
var _time_label: Label
var _style_picker: OptionButton
var _detail_picker: OptionButton

# --- Build ------------------------------------------------------------------------------------

func _ready() -> void:
	RenderCaps.detect()
	var background := ColorRect.new()
	background.color = Color("1a1f26")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 6
	root.offset_right = -8
	root.offset_bottom = -6
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	root.add_child(_top_bar())
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	split.add_child(left)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_host = Host.new()
	_viewport.add_child(_host)
	_preview = TextureRect.new()
	_preview.texture = _viewport.get_texture()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(560, 315)
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.tooltip_text = "在画面里按住左键拖动：移动冲击中心"
	_preview.gui_input.connect(_preview_input)
	left.add_child(_preview)
	left.add_child(_transport())
	_scrubber = Scrubber.new()
	_scrubber.editor = self
	_scrubber.custom_minimum_size = Vector2(0, 48)
	_scrubber.seek.connect(func(t: float) -> void: _seek(t))
	left.add_child(_scrubber)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_constant_override("separation", 3)
	scroll.add_child(_inspector)
	_fill_picker()
	var wanted := String(get_tree().root.get_meta("quake_editor_open", "")) if get_tree() != null else ""
	if get_tree() != null and get_tree().root.has_meta("quake_editor_open"): get_tree().root.remove_meta("quake_editor_open")
	if _paths.has(wanted): _open(_paths.find(wanted))
	elif _paths.size() > 0: _open(0)
	else: _new_from_template(0)
	if RenderCaps.fallback and RenderCaps.reason != "手动开启":
		_status.text = "兜底模式：%s（未检测到显卡，特效已简化）" % RenderCaps.reason

func _button(text: String, action: Callable, tip := "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button

func _top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var heading := Label.new()
	heading.text = "地震特效编辑器"
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color("ffcf8a"))
	bar.add_child(heading)
	_picker = OptionButton.new()
	_picker.custom_minimum_size = Vector2(250, 0)
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.item_selected.connect(func(i: int) -> void:
		if i < _paths.size(): _open(i)
		else: _new_from_template(0))
	bar.add_child(_picker)
	bar.add_child(_button("保存", _save, "Ctrl+S；原文件备份为 .bak"))
	_save_as = LineEdit.new()
	_save_as.placeholder_text = "新名字（英文小写_）"
	_save_as.custom_minimum_size = Vector2(150, 0)
	bar.add_child(_save_as)
	bar.add_child(_button("另存为", _save_new))
	bar.add_child(_button("撤销", _undo_step, "Ctrl+Z"))
	bar.add_child(_button("重做", _redo_step, "Ctrl+Y"))
	bar.add_child(_button("返回", _leave, "Esc"))
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("ffe36b"))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	bar.add_child(_status)
	return bar

func _transport() -> Container:
	# Wraps onto a second line on narrow windows instead of squeezing the inspector.
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 4)
	bar.add_child(_button("⟲ 重播", func() -> void: _replay(), "空格"))
	_play_button = _button("暂停", _toggle_play)
	_play_button.custom_minimum_size = Vector2(56, 0)
	bar.add_child(_play_button)
	bar.add_child(_button("◀", func() -> void: _step(-1), "后退一帧 ←"))
	bar.add_child(_button("▶", func() -> void: _step(1), "前进一帧 →"))
	var loop := CheckBox.new()
	loop.text = "循环"
	loop.button_pressed = looping
	loop.focus_mode = Control.FOCUS_NONE
	loop.toggled.connect(func(on: bool) -> void: looping = on)
	bar.add_child(loop)
	var shake := CheckBox.new()
	shake.text = "震屏"
	shake.button_pressed = true
	shake.focus_mode = Control.FOCUS_NONE
	shake.toggled.connect(func(on: bool) -> void: _host.enabled = on)
	bar.add_child(shake)
	bar.add_child(_label("速度"))
	var speeds := OptionButton.new()
	for s in SPEEDS: speeds.add_item("%s×" % str(s))
	speeds.focus_mode = Control.FOCUS_NONE
	speeds.item_selected.connect(func(i: int) -> void:
		speed = SPEEDS[i]
		if stage != null: stage.speed = speed)
	bar.add_child(speeds)
	bar.add_child(_label("画风"))
	_style_picker = OptionButton.new()
	for key: String in Materials.STYLES: _style_picker.add_item(Materials.STYLE_NAMES[key])
	_style_picker.focus_mode = Control.FOCUS_NONE
	_style_picker.tooltip_text = "Q 切换；整个连招统一"
	_style_picker.item_selected.connect(func(i: int) -> void: set_look("quake_style", Materials.STYLES[i]))
	bar.add_child(_style_picker)
	bar.add_child(_label("精细度"))
	_detail_picker = OptionButton.new()
	for key: String in Materials.DETAILS: _detail_picker.add_item(Materials.DETAIL_NAMES[key])
	_detail_picker.focus_mode = Control.FOCUS_NONE
	_detail_picker.tooltip_text = "W 切换；炸裂 = 极致 + 冲击波热扭曲"
	_detail_picker.item_selected.connect(func(i: int) -> void: set_look("quake_detail", Materials.DETAILS[i]))
	bar.add_child(_detail_picker)
	bar.add_child(_label("镜头"))
	var zooms := OptionButton.new()
	for z in ["全景", "1.5× 跟随", "2× 跟随"]: zooms.add_item(z)
	zooms.focus_mode = Control.FOCUS_NONE
	zooms.item_selected.connect(func(i: int) -> void: zoom = [1.0, 1.5, 2.0][i])
	bar.add_child(zooms)
	var fallback := CheckBox.new()
	fallback.text = "预览兜底"
	fallback.tooltip_text = "按没有显卡时的兜底效果预览（只影响预览，不保存）"
	fallback.focus_mode = Control.FOCUS_NONE
	fallback.button_pressed = RenderCaps.fallback
	fallback.toggled.connect(func(on: bool) -> void:
		RenderCaps.fallback = on
		RenderCaps.reason = "预览" if on else ""
		_status.text = "兜底预览：开（写实 + 均衡，简化着色）" if on else "兜底预览：关"
		_reseek())
	bar.add_child(fallback)
	_time_label = Label.new()
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_color_override("font_color", Color("9aa7b4"))
	bar.add_child(_time_label)
	return bar

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

# --- Data -------------------------------------------------------------------------------------

## The quake event being edited (the first one in the combo).
func event() -> Dictionary:
	return data.events[index] if index >= 0 and index < (data.events as Array).size() else {}

func spec() -> Dictionary:
	return Profile.normalized(event())

func total_time() -> float:
	var last := 1.0
	for e: Dictionary in data.events:
		var t := float(e.get("t", 0.0))
		last = maxf(last, t + (Profile.lifetime(Profile.normalized(e)) if e.get("do") == "quake" else 0.5))
	return last + 0.1

func now() -> float:
	return stage.clock if stage != null else 0.0

func _fill_picker() -> void:
	_picker.clear()
	_paths.clear()
	var folders := DirAccess.get_directories_at(COMBOS)
	folders.sort()
	for folder in folders:
		var path := COMBOS.path_join(folder).path_join("combo.json")
		if not FileAccess.file_exists(path): continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not (parsed.get("events", []) as Array).any(func(e: Variant) -> bool: return e is Dictionary and e.get("do") == "quake"): continue
		_paths.append(path)
		var title := folder
		var style_path := path.get_base_dir().path_join("style.json")
		if FileAccess.file_exists(style_path):
			var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(style_path))
			if s is Dictionary: title = "%s  (%s)" % [String(s.get("title", folder)), folder]
		_picker.add_item(title)
	_picker.add_item("＋ 新建地震特效")

func _open(i: int) -> void:
	combo_path = _paths[i]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(combo_path))
	data = parsed if parsed is Dictionary else {"events": []}
	var style_path := combo_path.get_base_dir().path_join("style.json")
	var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(style_path)) if FileAccess.file_exists(style_path) else null
	style = s if s is Dictionary else {"title": combo_path.get_base_dir().get_file(), "language": "zh", "renderer": "quake"}
	_picker.select(i)
	_after_load("已打开 " + combo_path.get_base_dir().get_file())

func _new_from_template(which: int) -> void:
	combo_path = ""
	var e := {"t": 0.2, "do": "quake", "unit": "earth", "x": 640.0, "y": 520.0}
	e.merge((TEMPLATES[which][2] as Dictionary).duplicate(true), true)
	data = {"name": "新地震特效", "events": [e]}
	style = {"title": "新地震特效", "language": "zh", "renderer": "quake"}
	_picker.select(_picker.item_count - 1)
	_after_load("新建：选一个场景模板和材质，调好后「另存为」")

func _after_load(message: String) -> void:
	index = -1
	for i in (data.events as Array).size():
		if data.events[i] is Dictionary and data.events[i].get("do") == "quake":
			index = i
			break
	if index < 0:
		(data.events as Array).append({"t": 0.2, "do": "quake"})
		index = data.events.size() - 1
	_undo.clear()
	_redo.clear()
	dirty = false
	_status.text = message
	_sync_look()
	_refresh_inspector()
	_replay()

func _remember(tag: String) -> void:
	var clock := Time.get_ticks_msec() / 1000.0
	if tag == _last_tag and clock - _last_time < 0.8:
		_last_time = clock
		return
	_last_tag = tag
	_last_time = clock
	_undo.append(JSON.stringify({"data": data, "style": style}))
	if _undo.size() > 200: _undo.pop_front()
	_redo.clear()

func _restore(snapshot: String) -> void:
	var state: Dictionary = JSON.parse_string(snapshot)
	data = state.data
	style = state.style
	dirty = true
	_sync_look()
	_refresh_inspector()
	_schedule()

func _undo_step() -> void:
	if _undo.is_empty():
		_status.text = "没有可撤销的修改"
		return
	_redo.append(JSON.stringify({"data": data, "style": style}))
	_restore(_undo.pop_back())
	_last_tag = ""
	_status.text = "已撤销"

func _redo_step() -> void:
	if _redo.is_empty():
		_status.text = "没有可重做的修改"
		return
	_undo.append(JSON.stringify({"data": data, "style": style}))
	_restore(_redo.pop_back())
	_last_tag = ""
	_status.text = "已重做"

## Writes one field of the quake event; `refresh` rebuilds the panel (for fields that
## show or hide others).
func set_field(key: String, value: Variant, refresh := false) -> void:
	if _filling or index < 0: return
	_remember(key)
	if value == null: (data.events[index] as Dictionary).erase(key)
	else: data.events[index][key] = value
	dirty = true
	_leave_armed = false
	if refresh: _refresh_inspector.call_deferred()
	_schedule()

## 画风 / 精细度 belong to the whole combo (style.json); the preview keeps its moment.
func set_look(key: String, value: String) -> void:
	if String(style.get(key, "")) == value: return
	_remember(key)
	style[key] = value
	dirty = true
	_leave_armed = false
	_sync_look()
	_reseek()

func _sync_look() -> void:
	if _style_picker == null: return
	_style_picker.select(maxi(0, Materials.STYLES.find(String(style.get("quake_style", "real")))))
	_detail_picker.select(maxi(0, Materials.DETAILS.find(String(style.get("quake_detail", "explosive")))))

func _cycle_look(key: String, values: Array, fallback: String) -> void:
	var at := values.find(String(style.get(key, fallback)))
	set_look(key, values[(at + 1) % values.size()])
	_status.text = "画风：%s　精细度：%s" % [Materials.STYLE_NAMES[String(style.get("quake_style", "real"))], Materials.DETAIL_NAMES[String(style.get("quake_detail", "explosive"))]]

func _reseek() -> void:
	var was := playing
	_seek(now())
	_set_playing(was)

func apply_template(which: int) -> void:
	_remember("template")
	var fields: Dictionary = (TEMPLATES[which][2] as Dictionary).duplicate(true)
	var e: Dictionary = data.events[index]
	e.merge(fields, true)
	if fields.rhythm == "continuous": e.erase("stages")
	if e.get("mode") != "cone": e.erase("cone")
	if not fields.has("body_growth"): e.erase("body_growth")
	if not fields.has("form"): e.erase("form")
	dirty = true
	_status.text = "已套用「%s」模板" % TEMPLATES[which][0]
	_refresh_inspector.call_deferred()
	_replay()

# --- Inspector --------------------------------------------------------------------------------

func _section(title: String, note := "") -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	_inspector.add_child(gap)
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", Color("ffcf8a"))
	label.add_theme_font_size_override("font_size", 16)
	_inspector.add_child(label)
	if not note.is_empty():
		var hint := Label.new()
		hint.text = note
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color("7f8b97"))
		hint.add_theme_font_size_override("font_size", 12)
		_inspector.add_child(hint)

func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(130, 0)
	label.clip_text = true
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	_inspector.add_child(row)
	return row

## A slider with a number box: drag for feel, type for exact values.
func _slider(text: String, key: String, low: float, high: float, step: float, refresh := false) -> void:
	var current := spec()
	var value := float(current[key]) if current.has(key) else float(event().get(key, 0.0))
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(84, 0)
	spin.allow_greater = true
	spin.allow_lesser = true
	var integer := step >= 1.0 and key == "seed"
	slider.value_changed.connect(func(v: float) -> void:
		if not is_equal_approx(spin.value, v): spin.set_value_no_signal(v)
		set_field(key, int(v) if integer else v, refresh))
	spin.value_changed.connect(func(v: float) -> void:
		if not is_equal_approx(slider.value, v): slider.set_value_no_signal(v)
		set_field(key, int(v) if integer else v, refresh))
	box.add_child(slider)
	box.add_child(spin)
	_row(text, box)

func _check(text: String, key: String, refresh := false) -> void:
	var check := CheckBox.new()
	check.text = "开启"
	check.button_pressed = bool(spec()[key])
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void: set_field(key, on, refresh))
	_row(text, check)

func _colour(text: String, key: String, fallback: Color) -> void:
	var box := HBoxContainer.new()
	var picker := ColorPickerButton.new()
	var current := String(spec()[key])
	picker.color = Color(current) if not current.is_empty() else fallback
	picker.custom_minimum_size = Vector2(60, 26)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.color_changed.connect(func(colour: Color) -> void: set_field(key, colour.to_html(false)))
	box.add_child(picker)
	var reset := _button("材质默认" if not current.is_empty() else "（材质默认）", func() -> void: set_field(key, null, true))
	reset.disabled = current.is_empty()
	box.add_child(reset)
	_row(text, box)

func _choices(names: Array, current: int, columns: int, chosen: Callable, colours: Array = []) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	var picked := StyleBoxFlat.new()
	picked.bg_color = Color("3b3024")
	picked.border_color = Color("ffcf8a")
	picked.set_border_width_all(2)
	picked.set_corner_radius_all(3)
	for i in names.size():
		var button := Button.new()
		button.text = names[i]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == current
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 30)
		button.add_theme_stylebox_override("pressed", picked)
		button.add_theme_stylebox_override("hover_pressed", picked)
		button.add_theme_color_override("font_pressed_color", Color("ffe9c7"))
		if i < colours.size():
			var swatch := Image.create(12, 12, false, Image.FORMAT_RGBA8)
			swatch.fill(colours[i])
			button.icon = ImageTexture.create_from_image(swatch)
		var at := i
		button.pressed.connect(func() -> void: chosen.call(at))
		grid.add_child(button)
	_inspector.add_child(grid)
	return grid

func _refresh_inspector() -> void:
	_filling = true
	for child in _inspector.get_children(): child.free()
	if index < 0:
		_filling = false
		return
	var s := spec()

	_section("场景模板", "一键套用形状与节奏（保持当前材质）")
	_choices(TEMPLATES.map(func(t: Array) -> String: return t[0]), -1, 3, apply_template)
	var title := LineEdit.new()
	title.text = String(style.get("title", ""))
	title.text_changed.connect(func(text: String) -> void:
		_remember("title")
		style["title"] = text
		data["name"] = text
		dirty = true)
	_row("标题", title)

	_section("材质")
	var units: Array = Profile.UNITS
	_choices(units.map(func(u: String) -> String: return Materials.NAMES[u]), units.find(s.unit), 4,
		func(i: int) -> void: set_field("unit", units[i], true),
		units.map(func(u: String) -> Color: return Materials.swatch(u)))
	_colourway(s)

	_section("传播方式")
	var current := -1
	for i in MODES.size(): if MODES[i][0] == s.mode: current = i
	_choices(MODES.map(func(m: Array) -> String: return m[2] if bool(s.reverse) else m[1]), current, 2,
		func(i: int) -> void: set_field("mode", MODES[i][0], true))
	var reverse := CheckBox.new()
	reverse.text = "反向（%s）" % MODES[maxi(current, 0)][2]
	reverse.button_pressed = bool(s.reverse)
	reverse.focus_mode = Control.FOCUS_NONE
	reverse.toggled.connect(func(on: bool) -> void: set_field("reverse", on, true))
	_row("方向", reverse)

	_section("范围", "也可以直接在预览画面里拖动冲击中心")
	_slider("发生时间", "t", 0.0, 5.0, 0.01)
	_slider("中心 X", "x", 0.0, 1280.0, 1.0)
	_slider("中心 Y（地面）", "y", 300.0, 700.0, 1.0)
	if s.mode == "cone":
		_slider("扇形半径", "width", 40.0, 900.0, 1.0)
		_slider("扇形角度", "cone", 10.0, 180.0, 1.0)
		_slider("额外距离", "length", 0.0, 1200.0, 1.0)
	else:
		_slider("宽度 / 直径", "width", 20.0, 900.0, 1.0)
		_slider("长度（0=圆形）" if s.mode == "radial" else "推进长度", "length", 0.0, 1400.0, 1.0)
	_slider("方向角度", "angle", -180.0, 180.0, 1.0)
	_slider("地面透视", "perspective", 0.08, 1.0, 0.01)

	_section("节奏")
	_choices(["一口气推进", "分段：震 → 停 → 震"], 1 if s.rhythm == "staged" else 0, 2,
		func(i: int) -> void: set_field("rhythm", "staged" if i == 1 else "continuous", true))
	if s.rhythm == "staged": _stage_table(s)
	else:
		_slider("推进用时", "travel", 0.05, 3.0, 0.01)
		_slider("速度曲线（<1 先快后慢）", "ease", 0.3, 3.0, 0.05)
	_slider("整体强度", "strength", 0.1, 3.0, 0.05)

	_section("本体：%s" % Materials.NAMES[s.unit], {"rock": "破土而出的岩刺与岩板", "crystal": "瞬间长出的晶簇，结束时碎裂",
		"lava": "熔岩：喷泉、地裂、火山或灼地熔化", "beam": "地面法阵与光柱", "bolt": "雷电沿推进路线落下"}[Materials.DATA[s.unit].body])
	if Materials.FORMS.has(String(s.unit)):
		var forms: Array = Materials.FORMS[String(s.unit)]
		var keys: Array = forms.map(func(f: Array) -> String: return f[0])
		_choices(forms.map(func(f: Array) -> String: return f[1]), keys.find(s.form), forms.size(),
			func(i: int) -> void: set_field("form", keys[i], true))
	_check("显示本体", "body")
	_slider("大小", "unit_size", 0.3, 3.0, 0.05)
	_slider("间距（越小越密）", "spacing", 25.0, 200.0, 1.0)
	_slider("停留时长", "unit_time", 0.2, 3.0, 0.05)
	_slider("远端放大（越远越大）", "body_growth", 0.3, 4.0, 0.05)

	_section("裂地 · 冲击波 · 震屏")
	_check("地面裂缝", "cracks", true)
	if bool(s.cracks):
		_slider("裂缝数量", "crack_amount", 0.2, 3.0, 0.05)
		_slider("裂缝发光", "crack_glow", 0.0, 3.0, 0.05)
		_slider("裂缝残留", "crack_time", 0.0, 4.0, 0.05)
	_check("冲击波前沿", "wave", true)
	if bool(s.wave): _slider("冲击波高度", "wave_height", 0.0, 3.0, 0.05)
	_slider("冲击闪光", "flash", 0.0, 3.0, 0.05)
	_slider("震屏强度", "shake", 0.0, 30.0, 0.5)

	_section("碎屑")
	var kinds: Array = Profile.DEBRIS
	var names := kinds.map(func(k: String) -> String: return DEBRIS_NAMES[k])
	var debris := OptionButton.new()
	for n: String in names: debris.add_item(n)
	debris.select(kinds.find(s.debris))
	debris.focus_mode = Control.FOCUS_NONE
	debris.item_selected.connect(func(i: int) -> void: set_field("debris", kinds[i], true))
	_row("类型", debris)
	if s.debris != "none":
		_slider("数量", "debris_density", 0.0, 4.0, 0.05)
		_slider("抛起高度", "debris_height", 0.0, 500.0, 1.0)

	_section("烟尘")
	_check("显示烟尘", "dust", true)
	if bool(s.dust):
		_slider("密度", "dust_density", 0.0, 3.0, 0.05)
		_slider("上升高度", "dust_height", 0.0, 400.0, 1.0)
		_slider("向外扩散", "dust_spread", 0.0, 400.0, 1.0)
		_slider("消散时间", "dust_time", 0.2, 5.0, 0.05)
		_slider("远端放大", "dust_growth", 0.2, 4.0, 0.05)
		_colour("烟尘颜色", "dust_color", Materials.palette(s.unit).dust_tint)

	_section("随机")
	var seed_box := HBoxContainer.new()
	var seed_spin := SpinBox.new()
	seed_spin.min_value = 0
	seed_spin.max_value = 99999
	seed_spin.value = int(s.seed)
	seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_spin.value_changed.connect(func(v: float) -> void: set_field("seed", int(v)))
	seed_box.add_child(seed_spin)
	seed_box.add_child(_button("🎲 换一个", func() -> void: set_field("seed", randi() % 100000, true)))
	_row("随机种子", seed_box)
	_filling = false

## 配色: the material's own colours, a named colourway, or five custom ramp colours.
func _colourway(s: Dictionary) -> void:
	_section("配色", "整条色带一起换：深 → 暗 → 中 → 亮 → 发光，最亮处自动到白热")
	var names: Array = ["材质原色"]
	var keys: Array = [""]
	for key: String in Materials.COLORWAYS:
		names.append(Materials.COLORWAYS[key][0])
		keys.append(key)
	names.append("自定义")
	var custom: bool = s.ramp is Array
	var current := names.size() - 1 if custom else maxi(0, keys.find(String(s.ramp)))
	var swatches: Array = keys.map(func(k: String) -> Color: return Materials.swatch(String(s.unit), k))
	swatches.append(Materials.swatch(String(s.unit), s.ramp) if custom else Color("9aa7b4"))
	_choices(names, current, 4, func(i: int) -> void:
		if i == names.size() - 1: set_field("ramp", Materials.stops(String(spec().unit), spec().ramp).duplicate(), true)
		else: set_field("ramp", keys[i], true), swatches)
	if not custom: return
	var row := HBoxContainer.new()
	var colours: Array = (s.ramp as Array).duplicate()
	for i in 5:
		var picker := ColorPickerButton.new()
		picker.color = Color(String(colours[i]))
		picker.custom_minimum_size = Vector2(44, 28)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.tooltip_text = ["深", "暗", "中", "亮", "发光"][i]
		var at := i
		picker.color_changed.connect(func(colour: Color) -> void:
			var changed: Array = (spec().ramp as Array).duplicate()
			changed[at] = colour.to_html(false)
			set_field("ramp", changed))
		row.add_child(picker)
	_row("深 → 发光", row)

func _stage_table(s: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	for head in ["段", "距离", "推进", "停顿", "强度"]:
		var label := _label(head)
		label.add_theme_color_override("font_color", Color("7f8b97"))
		grid.add_child(label)
	var steps: Array = s.stages
	for i in steps.size():
		grid.add_child(_label(str(i + 1)))
		for field in [["distance", 0.1, 10.0], ["time", 0.02, 3.0], ["pause", 0.0, 3.0], ["strength", 0.0, 3.0]]:
			var spin := SpinBox.new()
			spin.min_value = field[1]
			spin.max_value = field[2]
			spin.step = 0.01
			spin.value = float(steps[i][field[0]])
			spin.custom_minimum_size = Vector2(70, 0)
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.editable = not (field[0] == "pause" and i == steps.size() - 1)
			var at := i
			var key: String = field[0]
			spin.value_changed.connect(func(v: float) -> void:
				var changed: Array = spec().stages
				changed[at][key] = v
				set_field("stages", changed))
			grid.add_child(spin)
	_inspector.add_child(grid)
	var actions := HBoxContainer.new()
	var add := _button("＋ 加一段", func() -> void:
		var changed: Array = spec().stages
		changed.append({"distance": 1.0, "time": 0.15, "pause": 0.0, "strength": 1.0})
		if changed.size() > 1 and float(changed[-2].pause) <= 0.0: changed[-2].pause = 0.15
		set_field("stages", changed, true))
	add.disabled = steps.size() >= 8
	actions.add_child(add)
	var remove := _button("－ 删末段", func() -> void:
		var changed: Array = spec().stages
		changed.pop_back()
		set_field("stages", changed, true))
	remove.disabled = steps.size() <= 1
	actions.add_child(remove)
	var total := Label.new()
	total.text = "  共 %.2fs" % Profile.duration(s)
	total.add_theme_color_override("font_color", Color("9aa7b4"))
	actions.add_child(total)
	_inspector.add_child(actions)

# --- Preview ----------------------------------------------------------------------------------

func _schedule() -> void:
	_rebuild_in = 0.12

## Builds a fresh stage for the current data (not yet advanced).
func _build() -> void:
	_rebuild_in = -1.0
	for child in _host.get_children(): child.free()
	ComboStyle.load_data(style.duplicate(true))
	stage = load("res://vfx/quake_stage.gd").new()
	_host.add_child(stage)
	stage.set_process_unhandled_input(false)
	stage.set_process(false)
	stage.help.visible = false
	stage.TIMELINE = ComboStage.parse_events(data.events)
	stage.reset()
	stage.play()
	stage.speed = speed

func _replay() -> void:
	_build()
	_rest = -1.0
	_set_playing(true)

## Rebuilds and steps the deterministic clock to `t` (the effect has no hidden state).
func _seek(t: float) -> void:
	_build()
	_set_playing(false)
	var target := clampf(t, 0.0, total_time())
	var shake := _host.enabled
	_host.enabled = false
	while stage.clock < target - 0.0001 and stage.playing:
		stage.advance(minf(STEP, target - stage.clock))
	_host.enabled = shake
	_scrubber.queue_redraw()

func _step(frames: int) -> void:
	_seek(maxf(0.0, now() + frames * STEP))

func _toggle_play() -> void:
	if playing: _set_playing(false)
	elif stage == null or not stage.playing: _replay()
	else: _set_playing(true)

func _set_playing(on: bool) -> void:
	playing = on
	if _play_button != null: _play_button.text = "暂停" if on else "播放"

func _process(delta: float) -> void:
	if _rebuild_in >= 0.0:
		_rebuild_in -= delta
		if _rebuild_in < 0.0:
			# Keep a paused frame where it was; otherwise replay the change from the start.
			if playing: _replay()
			else: _seek(now())
	if stage != null and playing:
		stage.advance(delta * speed)
		if not stage.playing and stage.is_settled() and looping:
			if _rest < 0.0: _rest = 0.45
			_rest -= delta
			if _rest <= 0.0: _replay()
		elif not stage.playing and stage.is_settled(): _set_playing(false)
	_update_camera(delta)
	if _time_label != null: _time_label.text = "%.2fs / %.2fs" % [now(), total_time()]
	_scrubber.queue_redraw()

func _update_camera(delta: float) -> void:
	var camera := _viewport.get_camera_2d()
	if camera == null: return
	var e := event()
	var focus := Vector2(float(e.get("x", 640.0)), float(e.get("y", 520.0)) - 90.0)
	var half := Vector2(640, 360) / zoom
	camera.zoom = Vector2.ONE * zoom
	camera.position = Vector2(clampf(focus.x, half.x, 1280.0 - half.x), clampf(focus.y, half.y, 720.0 - half.y)) if zoom > 1.0 else Vector2(640, 360)
	camera.offset = _host.tick(delta if playing else 0.0)

## Converts a point on the preview widget to stage coordinates.
func _to_stage(at: Vector2) -> Vector2:
	var area := _preview.size
	var scale := minf(area.x / 1280.0, area.y / 720.0)
	var shown := Vector2(1280, 720) * scale
	var local := (at - (area - shown) * 0.5) / scale
	var camera := _viewport.get_camera_2d()
	if camera == null: return local
	return camera.position + (local - Vector2(640, 360)) / camera.zoom.x

func _preview_input(input: InputEvent) -> void:
	if input is InputEventMouseButton and input.button_index == MOUSE_BUTTON_LEFT:
		_dragging_preview = input.pressed
		if input.pressed: _move_to(_to_stage(input.position))
		elif not _filling: _refresh_inspector()
	elif input is InputEventMouseMotion and _dragging_preview:
		_move_to(_to_stage(input.position))

func _move_to(at: Vector2) -> void:
	_remember("drag")
	data.events[index]["x"] = roundf(clampf(at.x, 0.0, 1280.0))
	data.events[index]["y"] = roundf(clampf(at.y, 300.0, 700.0))
	dirty = true
	_status.text = "冲击中心 (%d, %d)" % [int(data.events[index].x), int(data.events[index].y)]
	_schedule()

# --- Saving -----------------------------------------------------------------------------------

func _write(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status.text = "写入失败：%s" % path
		return false
	file.store_string(JSON.stringify(value, "  ", false) + "\n")
	return true

func _sorted() -> Dictionary:
	var out := data.duplicate(true)
	(out.events as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	return out

func _save() -> void:
	if combo_path.is_empty():
		_save_new()
		return
	var folder := combo_path.get_base_dir()
	for file in ["combo.json", "style.json"]:
		var path := folder.path_join(file)
		if FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
	style["renderer"] = String(style.get("renderer", "quake"))
	if _write(combo_path, _sorted()) and _write(folder.path_join("style.json"), style):
		dirty = false
		_status.text = "已保存 %s" % folder.get_file()

func _save_new() -> void:
	var name := _save_as.text.strip_edges()
	if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(name) == null:
		_status.text = "先在「新名字」里填英文小写名字，例如 my_quake"
		return
	var folder := COMBOS.path_join(name)
	if DirAccess.dir_exists_absolute(folder):
		_status.text = "%s 已存在，换个名字（或打开它再按「保存」）" % name
		return
	DirAccess.make_dir_recursive_absolute(folder)
	style["renderer"] = "quake"
	_write(folder.path_join("combo.json"), _sorted())
	_write(folder.path_join("style.json"), style)
	var scene := FileAccess.open(folder.path_join(name + ".tscn"), FileAccess.WRITE)
	scene.store_string("[gd_scene format=3]\n\n[ext_resource type=\"Script\" path=\"res://vfx/combo_player.gd\" id=\"1\"]\n\n[node name=\"ComboPlayer\" type=\"Node2D\"]\nscript = ExtResource(\"1\")\ncombo_file = \"res://combos/%s/combo.json\"\nstyle_file = \"res://combos/%s/style.json\"\n" % [name, name])
	scene.close()
	var prompt := FileAccess.open(folder.path_join("prompt.md"), FileAccess.WRITE)
	prompt.store_string("# %s\n\n在「地震特效编辑器」里制作。\n" % String(style.get("title", name)))
	prompt.close()
	_fill_picker()
	combo_path = folder.path_join("combo.json")
	_picker.select(_paths.find(combo_path))
	dirty = false
	_save_as.text = ""
	_status.text = "已另存为 %s（画廊里也能打开）" % name

func _leave() -> void:
	if dirty and not _leave_armed:
		_leave_armed = true
		_status.text = "有未保存的修改：再按一次「返回」/ Esc 放弃修改"
		return
	get_tree().change_scene_to_file(GALLERY)

func _unhandled_input(input: InputEvent) -> void:
	if not input is InputEventKey or not input.pressed: return
	var command: bool = input.is_command_or_control_pressed()
	match input.keycode:
		KEY_S when command: _save()
		KEY_Z when command:
			if input.shift_pressed: _redo_step()
			else: _undo_step()
		KEY_Y when command: _redo_step()
		KEY_ESCAPE: _leave()
		KEY_SPACE: _replay()
		KEY_Q when not command: _cycle_look("quake_style", Materials.STYLES, "real")
		KEY_W when not command: _cycle_look("quake_detail", Materials.DETAILS, "explosive")
		KEY_LEFT: _step(-1)
		KEY_RIGHT: _step(1)
		_: return
	get_viewport().set_input_as_handled()
