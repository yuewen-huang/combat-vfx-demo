extends "res://vfx/quake_editor.gd"
## Unified workspace. Ground controls and preview primitives are shared with the quake editor.
const Catalog = preload("res://vfx/editor_catalog.gd")
const Timeline = preload("res://vfx/editor_timeline.gd")
const Canvas = preload("res://vfx/editor_canvas.gd")
const Legacy = preload("res://vfx/combo_editor.gd")
const Magic = preload("res://vfx/magic_stage.gd")
const MagicSkeleton = preload("res://vfx/magic/magic_fx.gd")
const Loading = preload("res://vfx/screen_loading.gd")
@export var initial_category := "blade"
signal node_committed(data: Dictionary, style: Dictionary)
signal node_closed
var node_mode := false
var node_document: Dictionary = {}
var preview_context: Array = []
var preview_start := 0.0
var preview_with_context := true
var _context_notice: Label

# Survive visits to the gallery. No document files are touched until Save.
static var sessions: Dictionary = {}
static var category_sessions: Dictionary = {}
static var recent_paths: Array[String] = []
var category := "blade"
var session_key := ""
var guides := true
var drag_handle := ""
var _gesture := ""
var _gesture_recorded := false
var _folds: Dictionary = {}
var _category_buttons: Array[Button] = []
var _library: VBoxContainer
var _library_list: ItemList
var _search: LineEdit
var _template_list: ItemList
var _template_picker: OptionButton
var _event_picker: OptionButton
var _event_list: ItemList
var _composition: VBoxContainer
var _canvas: Control
var _title: LineEdit
var _save_dialog: ConfirmationDialog
var _leave_dialog: ConfirmationDialog
var _replace_dialog: ConfirmationDialog
var _pending_template := 0
var _after_save: Callable
var _saved_state := ""
var _library_paths: Array[String] = []
var _dirty_label: Label
var _building_panel := false
var _preview_elapsed := 0.0
var _remembered_drag_geometry: Dictionary = {}
var _inspector_scroll: ScrollContainer
var _open_group: VBoxContainer
var _camera_position := Vector2(640, 360)
var _camera_zoom := Vector2.ONE
var _fallback_notice: Label
var _thumbnail_cache: Dictionary = {}
var _duration_cache := -1.0
var _checker_button: CheckBox

func panel_style(colour := Color("202a36")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(5)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box

func _ready() -> void:
	RenderCaps.detect()
	category = initial_category if initial_category in Catalog.KEYS else "blade"
	category = String(get_tree().root.get_meta("studio_category", category))
	get_tree().root.remove_meta("studio_category")
	var background := ColorRect.new()
	background.color = Color("141c26")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_right = -10
	root.offset_top = 8
	root.offset_bottom = -6
	root.add_theme_constant_override("separation", 7)
	add_child(root)
	root.add_child(_navigation())
	_fallback_notice = _label("")
	_fallback_notice.add_theme_font_size_override("font_size", 12)
	root.add_child(_fallback_notice)
	_update_fallback_notice()
	root.add_child(_top_bar())
	_context_notice = _label("")
	_context_notice.add_theme_font_size_override("font_size",12)
	_context_notice.modulate = Color("d8bc86")
	_context_notice.hide()
	root.add_child(_context_notice)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_library = _make_library()
	_library.visible = false
	body.add_child(_library)
	var workspace := HSplitContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(workspace)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	workspace.add_child(center)
	var create_bar := HFlowContainer.new()
	if not node_mode: create_bar.add_child(_button("模板 / 作品库", func() -> void: _library.visible = not _library.visible))
	create_bar.add_child(_label("替换本招模板" if node_mode else "从模板开始"))
	_template_picker = OptionButton.new()
	_template_picker.custom_minimum_size.x = 130
	create_bar.add_child(_template_picker)
	if not node_mode: create_bar.add_child(_button("＋ 新建", func() -> void: Loading.run_action(self, new_template.bind(_template_picker.selected), "正在创建特效")))
	create_bar.add_child(_button("应用模板", _ask_template, "把左边选择的模板应用到当前特效，修改可以撤销"))
	center.add_child(create_bar)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_host = Host.new()
	_viewport.add_child(_host)
	_preview = TextureRect.new()
	_preview.texture = _viewport.get_texture()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(440, 250)
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.clip_contents = true
	_preview.tooltip_text = "拖动圆形手柄调整；空白处不移动特效。时间轴上方可拖动定格。"
	_preview.gui_input.connect(_preview_input)
	center.add_child(_preview)
	_canvas = Canvas.new()
	_canvas.editor = self
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview.add_child(_canvas)
	center.add_child(_transport())
	_scrubber = Timeline.new()
	_scrubber.editor = self
	_scrubber.custom_minimum_size.y = 80
	_scrubber.seek.connect(_seek)
	center.add_child(_scrubber)
	var composition := _make_composition()
	var selection_row := composition.get_child(0)
	composition.remove_child(selection_row)
	center.add_child(composition)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 356
	right.add_child(selection_row)
	workspace.add_child(right)
	_inspector_scroll = ScrollContainer.new()
	_inspector_scroll.custom_minimum_size.x = 356
	_inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_inspector_scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_constant_override("separation", 5)
	_inspector_scroll.add_child(_inspector)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("a9bdcf"))
	_status.add_theme_font_size_override("font_size", 13)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_status)
	_dialogs()
	if node_mode:
		category = String(node_document.get("category","blade"))
		data = (node_document.get("data",{}) as Dictionary).duplicate(true)
		style = (node_document.get("style",{}) as Dictionary).duplicate(true)
		session_key = "node:"+String(node_document.get("id","move"))
		_fill_picker()
		_after_load("编辑单招；应用后返回多技能流程图")
		dirty = false
		return
	_fill_picker()
	var wanted := String(get_tree().root.get_meta("studio_open", get_tree().root.get_meta("quake_editor_open", "")))
	get_tree().root.remove_meta("studio_open")
	get_tree().root.remove_meta("quake_editor_open")
	if not wanted.is_empty(): open_path(wanted)
	elif category_sessions.has(category) and sessions.has(category_sessions[category]): _load_session(String(category_sessions[category]))
	else: new_template(0)

func _navigation() -> Control:
	var row := HBoxContainer.new()
	if node_mode:
		row.add_child(_label("单招参数"))
		row.add_child(_button("返回流程图",_leave))
		row.add_child(_button("全屏 F11",func() -> void: get_node("/root/AppWindow").toggle_fullscreen()))
		return row
	var heading := _label("特效工作室")
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", Color("ffe0a3"))
	heading.custom_minimum_size.x = 170
	row.add_child(heading)
	var group := ButtonGroup.new()
	for i in Catalog.KEYS.size():
		var key: String = Catalog.KEYS[i]
		var button := _button(Catalog.NAMES[i], func() -> void:
			if key != category: Loading.run_action(self, switch_category.bind(key), "正在进入%s编辑" % Catalog.NAMES[Catalog.KEYS.find(key)]))
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(100, 35)
		button.add_theme_stylebox_override("pressed", panel_style(Color("49627b")))
		_category_buttons.append(button)
		row.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button("返回画廊", _leave))
	return row

func _top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	_title = LineEdit.new()
	_title.placeholder_text = "作品名称（支持中文）"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_changed.connect(func(value: String) -> void:
		_remember("title")
		style.title = value
		data.name = value
		_mark_changed(false))
	bar.add_child(_title)
	_dirty_label = _label("")
	_dirty_label.custom_minimum_size.x = 62
	_dirty_label.add_theme_color_override("font_color", Color("ffd58b"))
	bar.add_child(_dirty_label)
	bar.add_child(_button("应用并返回流程图" if node_mode else "保存", _save, "Ctrl+S"))
	if not node_mode: bar.add_child(_button("另存为…", _save_new))
	bar.add_child(_button("撤销", _undo_step, "Ctrl+Z"))
	bar.add_child(_button("重做", _redo_step, "Ctrl+Shift+Z / Ctrl+Y"))
	return bar

func _transport() -> Container:
	var bar := HFlowContainer.new()
	if node_mode:
		var context := CheckBox.new()
		context.text = "带前置状态"
		context.button_pressed = preview_with_context
		context.toggled.connect(func(on: bool) -> void:
			preview_with_context = on
			_schedule())
		bar.add_child(context)
	bar.add_theme_constant_override("h_separation", 5)
	bar.add_child(_button("↻ 重播", _replay))
	_play_button = _button("暂停", _toggle_play, "空格：播放 / 暂停")
	bar.add_child(_play_button)
	bar.add_child(_button("◀", func() -> void: _step(-1), "后退一帧"))
	bar.add_child(_button("▶", func() -> void: _step(1), "前进一帧"))
	var speeds := OptionButton.new()
	for value in SPEEDS: speeds.add_item("%s×" % value)
	speeds.item_selected.connect(func(i: int) -> void: speed = SPEEDS[i])
	bar.add_child(speeds)
	for config in [["循环", true], ["辅助线", true], ["震屏", true], ["棋盘格", false], ["兜底预览", RenderCaps.fallback]]:
		var check := CheckBox.new()
		var key: String = config[0]
		check.text = key
		if key == "棋盘格": _checker_button = check
		check.button_pressed = bool(config[1])
		check.focus_mode = Control.FOCUS_NONE
		check.toggled.connect(func(on: bool) -> void:
			match key:
				"循环": looping = on
				"辅助线": guides = on
				"震屏": _host.enabled = on
				"棋盘格":
					_preview.set_meta("checker", on)
					_reseek()
				"兜底预览":
					RenderCaps.fallback = on
					RenderCaps.reason = "预览" if on else ""
					_update_fallback_notice()
					_reseek()
		)
		bar.add_child(check)
	var zooms := OptionButton.new()
	for value in ["全景", "1.5×", "2×"]: zooms.add_item(value)
	zooms.item_selected.connect(func(i: int) -> void: zoom = [1.0, 1.5, 2.0][i])
	bar.add_child(zooms)
	_time_label = _label("")
	_time_label.add_theme_color_override("font_color", Color("aab9c9"))
	bar.add_child(_time_label)
	return bar

func _make_library() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 192
	column.add_child(_label("模板与作品"))
	_template_list = ItemList.new()
	_template_list.custom_minimum_size = Vector2(180, 160)
	_template_list.item_activated.connect(func(i: int) -> void: Loading.run_action(self, new_template.bind(i), "正在创建特效"))
	column.add_child(_template_list)
	var hint := _label("双击模板新建 · 单击作品打开")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	column.add_child(hint)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索作品名称…"
	_search.text_changed.connect(func(_text: String) -> void: _fill_picker())
	column.add_child(_search)
	_library_list = ItemList.new()
	_library_list.fixed_icon_size = Vector2i(64, 36)
	_library_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library_list.item_selected.connect(func(i: int) -> void: Loading.run_action(self, open_path.bind(_library_paths[i]), "正在打开作品"))
	column.add_child(_library_list)
	return column

func _make_composition() -> Control:
	var column := VBoxContainer.new()
	_event_picker = OptionButton.new()
	_event_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_picker.item_selected.connect(func(i: int) -> void: select_event(i))
	var row := HBoxContainer.new()
	row.add_child(_event_picker)
	row.add_child(_button("编排 ▾", func() -> void: _composition.visible = not _composition.visible))
	column.add_child(row)
	_composition = VBoxContainer.new()
	_composition.visible = false
	column.add_child(_composition)
	_event_list = ItemList.new()
	_event_list.custom_minimum_size.y = 82
	_event_list.item_selected.connect(select_event)
	_composition.add_child(_event_list)
	var actions := HFlowContainer.new()
	var kinds := OptionButton.new()
	for kind: String in Legacy.DOS: kinds.add_item(Legacy.DO_NAMES[kind])
	actions.add_child(kinds)
	actions.add_child(_button("添加", func() -> void: add_event(Legacy.DOS[kinds.selected])))
	actions.add_child(_button("复制", duplicate_event))
	actions.add_child(_button("删除", delete_event))
	_composition.add_child(actions)
	return column

func _dialogs() -> void:
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.title = "另存为新作品"
	_save_dialog.ok_button_text = "保存"
	_save_dialog.cancel_button_text = "取消"
	var column := VBoxContainer.new()
	column.add_child(_label("作品名支持中文；文件标识使用英文小写、数字和下划线。"))
	_save_as = LineEdit.new()
	_save_as.placeholder_text = "例如 my_fire_spell"
	column.add_child(_save_as)
	_save_dialog.add_child(column)
	_save_dialog.register_text_enter(_save_as)
	_save_dialog.dialog_hide_on_ok = false
	_save_dialog.confirmed.connect(_commit_new)
	_save_dialog.canceled.connect(func() -> void: _after_save = Callable())
	add_child(_save_dialog)
	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.title = "作品尚未保存"
	_leave_dialog.dialog_text = "可以保存后返回，或放弃当前修改。其他入口的草稿会保留。"
	_leave_dialog.ok_button_text = "保存并返回"
	_leave_dialog.cancel_button_text = "继续编辑"
	_leave_dialog.add_button("放弃并返回", false, "discard")
	_leave_dialog.confirmed.connect(func() -> void:
		_after_save = _return_gallery
		_save())
	_leave_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			sessions.erase(session_key)
			category_sessions.erase(category)
			session_key = ""
			_return_gallery())
	add_child(_leave_dialog)
	_replace_dialog = ConfirmationDialog.new()
	_replace_dialog.title = "应用模板"
	_replace_dialog.ok_button_text = "应用形状与节奏"
	_replace_dialog.cancel_button_text = "取消"
	_replace_dialog.add_button("仅应用外观", false, "look")
	_replace_dialog.confirmed.connect(func() -> void: apply_preset(_pending_template, false))
	_replace_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"look":
			apply_preset(_pending_template, true)
			_replace_dialog.hide())
	add_child(_replace_dialog)

# --- Sessions and navigation -----------------------------------------------------------------

func _snapshot() -> String:
	return JSON.stringify({"data": data, "style": style})

func _stash() -> void:
	if session_key.is_empty(): return
	sessions[session_key] = {"data": data.duplicate(true), "style": style.duplicate(true), "path": combo_path, "index": index,
		"undo": _undo.duplicate(), "redo": _redo.duplicate(), "saved": _saved_state, "dirty": dirty, "time": now(), "playing": playing,
		"checker": bool(_preview.get_meta("checker", false))}
	category_sessions[category] = session_key

func _exit_tree() -> void:
	if not node_mode: _stash()

func switch_category(key: String) -> void:
	if key == category: return
	_stash()
	category = key
	if category_sessions.has(key) and sessions.has(category_sessions[key]): _load_session(String(category_sessions[key]))
	else: new_template(0)
	_fill_picker()

func _load_session(key: String) -> void:
	var state: Dictionary = sessions[key]
	session_key = key
	combo_path = state.path
	data = state.data.duplicate(true)
	style = state.style.duplicate(true)
	_duration_cache = -1.0
	index = clampi(int(state.index), -1, data.events.size() - 1)
	_undo.assign(state.undo)
	_redo.assign(state.redo)
	_saved_state = state.saved
	dirty = state.dirty
	_checker_button.set_pressed_no_signal(bool(state.get("checker", false)))
	_preview.set_meta("checker", bool(state.get("checker", false)))
	_last_tag = ""
	_sync_document_ui()
	_seek(float(state.time))
	_set_playing(bool(state.playing))
	_status.text = "已恢复草稿；切换入口不会改变作品的表现方式"

func _fill_picker() -> void:
	if _library_list == null: return
	var picked_template := ""
	if _template_picker != null and _template_picker.selected >= 0: picked_template = _template_picker.get_item_text(_template_picker.selected)
	_paths.clear()
	_library_paths.clear()
	_library_list.clear()
	var entries: Array[Dictionary] = []
	for folder in DirAccess.get_directories_at(COMBOS):
		var path := COMBOS.path_join(folder).path_join("combo.json")
		if not FileAccess.file_exists(path): continue
		var document := _read_document(path)
		if document.is_empty(): continue
		_paths.append(path)
		var look := _read_dictionary(path.get_base_dir().path_join("style.json"))
		if Catalog.document_category(document, look) != category: continue
		var title := String(look.get("title", document.get("name", folder)))
		if not _search.text.is_empty() and not (title + folder).to_lower().contains(_search.text.to_lower()): continue
		entries.append({"path": path, "title": title, "folder": folder, "recent": recent_paths.find(path)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.recent >= 0 or b.recent >= 0:
			if a.recent < 0: return false
			if b.recent < 0: return true
			return a.recent < b.recent
		return String(a.title).naturalnocasecmp_to(String(b.title)) < 0)
	for entry: Dictionary in entries:
		_library_paths.append(entry.path)
		_library_list.add_item(("◷ " if entry.recent >= 0 else "") + entry.title, _thumbnail(entry.path))
		_library_list.set_item_tooltip(_library_list.item_count - 1, entry.path)
		if entry.path == combo_path: _library_list.select(_library_list.item_count - 1)
	_template_list.clear()
	if _template_picker != null: _template_picker.clear()
	for preset: Array in Catalog.presets(category):
		_template_list.add_item(preset[0])
		_template_list.set_item_tooltip(_template_list.item_count - 1, preset[1])
		if _template_picker != null: _template_picker.add_item(preset[0])
	if _template_picker != null:
		for i in _template_picker.item_count:
			if _template_picker.get_item_text(i) == picked_template: _template_picker.select(i)
	for i in _category_buttons.size(): _category_buttons[i].button_pressed = Catalog.KEYS[i] == category

func _update_fallback_notice() -> void:
	_fallback_notice.visible = RenderCaps.fallback
	_fallback_notice.text = "兜底模式：%s（未检测到显卡，特效已简化）" % RenderCaps.reason if RenderCaps.fallback else ""

func _thumbnail(path: String) -> Texture2D:
	if _thumbnail_cache.has(path): return _thumbnail_cache[path]
	var name := path.get_base_dir().get_file()
	for candidate in ["res://.local-data/editor_thumbnails/%s.png" % name, path.get_base_dir().path_join("preview.png"), "res://verification/%s/combo.png" % name]:
		if FileAccess.file_exists(candidate):
			var picture := Image.load_from_file(candidate)
			if picture != null and not picture.is_empty():
				picture.resize(128, 72, Image.INTERPOLATE_LANCZOS)
				var texture := ImageTexture.create_from_image(picture)
				_thumbnail_cache[path] = texture
				return texture
	return null

func _capture_thumbnail() -> void:
	if DisplayServer.get_name() == "headless" or stage == null: return
	var picture := _viewport.get_texture().get_image()
	if picture == null or picture.is_empty(): return
	var directory := "res://.local-data/editor_thumbnails"
	DirAccess.make_dir_recursive_absolute(directory)
	picture.resize(256, 144, Image.INTERPOLATE_LANCZOS)
	picture.save_png(directory.path_join(combo_path.get_base_dir().get_file() + ".png"))
	_thumbnail_cache.erase(combo_path)

func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _read_document(path: String) -> Dictionary:
	var document := _read_dictionary(path)
	if not document.get("events") is Array: return {}
	for e: Variant in document.events:
		if not e is Dictionary or not e.get("do") is String or not (e.get("t", 0.0) is float or e.get("t", 0.0) is int): return {}
	return document

func _open(i: int) -> void:
	if i >= 0 and i < _paths.size(): open_path(_paths[i])

func open_path(path: String) -> void:
	var document := _read_document(path)
	if document.is_empty():
		_status.text = "无法打开：作品数据无效，当前草稿已保留"
		return
	_stash()
	var look := _read_dictionary(path.get_base_dir().path_join("style.json"))
	category = Catalog.document_category(document, look)
	if sessions.has(path): _load_session(path)
	else:
		session_key = path
		combo_path = path
		data = document
		style = look
		_after_load("已打开 " + String(style.get("title", path.get_base_dir().get_file())))
	recent_paths.erase(path)
	recent_paths.push_front(path)
	if recent_paths.size() > 20: recent_paths.resize(20)
	category_sessions[category] = session_key
	_fill_picker()

func _new_from_template(which: int) -> void:
	new_template(which)

func new_template(which: int) -> void:
	_stash()
	var preset := Catalog.create(category, maxi(0, which))
	session_key = "draft:%s:%d" % [category, Time.get_ticks_usec()]
	combo_path = ""
	data = preset.data
	style = preset.style
	index = 0
	_sync_linked_hits(true)
	_after_load("新建「%s」：拖动圆形手柄，或在右侧调整；草稿会在入口之间保留" % style.title)
	dirty = true
	category_sessions[category] = session_key
	_fill_picker()
	_template_picker.select(maxi(0, which))

func _after_load(message: String) -> void:
	_duration_cache = -1.0
	index = -1
	for i in data.events.size():
		if Catalog.kind_category(String(data.events[i].get("do", ""))) == category:
			index = i
			break
	if index < 0 and not data.events.is_empty(): index = 0
	var checker := false
	_checker_button.set_pressed_no_signal(checker)
	_preview.set_meta("checker", checker)
	_undo.clear()
	_redo.clear()
	_saved_state = _snapshot()
	dirty = false
	_last_tag = ""
	_sync_document_ui()
	_replay()
	_status.text = message

func _sync_document_ui() -> void:
	_title.set_text(String(style.get("title", data.get("name", "未命名特效"))))
	_refresh_event_list()
	_refresh_inspector()
	for i in _category_buttons.size(): _category_buttons[i].button_pressed = Catalog.KEYS[i] == category

func _refresh_event_list() -> void:
	_event_picker.clear()
	_event_list.clear()
	for i in data.events.size():
		var e: Dictionary = data.events[i]
		var name := "%02d · %s  %.2fs" % [i + 1, Legacy.DO_NAMES.get(String(e.get("do", "")), String(e.get("do", ""))), float(e.get("t", 0.0))]
		_event_picker.add_item(name)
		_event_list.add_item(name)
	if index >= 0 and index < data.events.size():
		_event_picker.select(index)
		_event_list.select(index)

func select_event(which: int) -> void:
	if which < 0 or which >= data.events.size(): return
	index = which
	_last_tag = ""
	_refresh_event_list()
	_refresh_inspector()
	_scrubber.queue_redraw()

# --- One transaction per gesture; unrelated events retain all unknown fields -----------------

func begin_gesture(tag: String) -> void:
	_gesture = tag
	_gesture_recorded = false
	_last_tag = ""

func end_gesture() -> void:
	var changed := _gesture_recorded
	_gesture = ""
	_gesture_recorded = false
	_last_tag = ""
	if changed: _refresh_inspector.call_deferred()

func _remember(tag: String) -> void:
	if _filling: return
	if not _gesture.is_empty():
		if _gesture_recorded: return
		_gesture_recorded = true
		tag = _gesture
	else:
		var seconds := Time.get_ticks_msec() / 1000.0
		if tag == _last_tag and seconds - _last_time < 0.7:
			_last_time = seconds
			return
		_last_time = seconds
	_last_tag = tag
	_undo.append(_snapshot())
	if _undo.size() > 200: _undo.pop_front()
	_redo.clear()

func _restore(snapshot: String) -> void:
	var state: Dictionary = JSON.parse_string(snapshot)
	data = state.data
	style = state.style
	_duration_cache = -1.0
	index = clampi(index, -1, data.events.size() - 1)
	dirty = _snapshot() != _saved_state or combo_path.is_empty()
	_sync_document_ui()
	_schedule()

func _mark_changed(rebuild := true) -> void:
	_duration_cache = -1.0
	dirty = _snapshot() != _saved_state or combo_path.is_empty()
	if rebuild: _schedule()
	_refresh_event_list()

func set_field(key: String, value: Variant, refresh := false) -> void:
	if _filling or index < 0 or index >= data.events.size(): return
	if event().has(key):
		var current: Variant = event()[key]
		# Anchors and endpoints may change from names to coordinate arrays (and back).
		var comparable := typeof(current) == typeof(value) or ((current is int or current is float) and (value is int or value is float))
		if comparable and current == value: return
	_remember("%d:%s" % [index, key])
	if value == null: event().erase(key)
	else: event()[key] = value
	_sync_linked_hits()
	_mark_changed()
	if refresh: _refresh_inspector.call_deferred()

func set_look(key: String, value: String) -> void:
	if style.get(key) == value: return
	_remember("style:" + key)
	style[key] = value
	_mark_changed()

func _style_number(key: String, value: float) -> void:
	_remember("style:" + key)
	style[key] = value
	_mark_changed()

func spec() -> Dictionary:
	return Catalog.defaults(event(), _renderer())

func _sync_look() -> void:
	pass # Pickers are recreated with the selected event's panel.

func _renderer() -> String:
	return String(style.get("renderer", ""))

func _contact_times(e: Dictionary) -> Array:
	if e.get("do") == "cast": return Magic.contact_times(e)
	var delay := 0.04
	if _renderer() in ["ribbon", "claw"]: delay = float(e.get("duration", 0.16)) * (float(e.get("contact", 0.5)) if _renderer() == "claw" else 0.5)
	elif _renderer().is_empty(): delay = float(e.get("duration", 0.045)) * 0.89
	return [float(e.get("t", 0.0)) + delay]

func _sync_linked_hits(create := false) -> void:
	var source := event()
	if not String(source.get("do", "")) in ["slash", "cast"]: return
	if create:
		if not source.has("_editor_id"): source["_editor_id"] = "fx_%d" % Time.get_ticks_usec()
		source["_editor_follow"] = true
	if not source.get("_editor_follow", false): return
	var id := String(source.get("_editor_id", ""))
	if id.is_empty(): return
	var linked: Array[Dictionary] = []
	for e: Dictionary in data.events:
		if e.get("_editor_source") == id: linked.append(e)
	var times := _contact_times(source)
	for i in times.size():
		if i >= linked.size():
			var hit := {"do": "hit", "t": 0.0, "push": 0.0, "stop": 0.04, "shake": 2.5, "spark": 46.0, "_editor_source": id}
			if category == "blade" and style.get("title") == "上挑": hit["launch"] = -420.0
			data.events.append(hit)
			linked.append(hit)
		linked[i]["t"] = snappedf(float(times[i]), 0.001)
		linked[i]["palette"] = source.get("palette", "normal")
	for i in range(times.size(), linked.size()): data.events.erase(linked[i])

func _set_follow(on: bool) -> void:
	_remember("follow")
	if on: _sync_linked_hits(true)
	else: event()["_editor_follow"] = false
	_mark_changed()
	_refresh_inspector.call_deferred()

func add_event(kind: String) -> void:
	if kind == "cast" and _renderer() != "magic":
		_status.text = "施法需要魔法作品；点击「魔法」入口新建，可保留当前草稿"
		return
	_remember("add")
	var e := {"do": kind, "t": snappedf(now(), 0.01)}
	if kind == "slash": e.merge({"from": -70.0, "to": 70.0, "width": 44.0, "radius": 160.0})
	if kind == "cast": e["element"] = "fire"
	if kind == "quake": e.merge({"unit": "earth", "x": 640.0, "y": 520.0})
	if kind == "swarm": e.merge({"id": _actor_ids("swarm")[0] if not _actor_ids("swarm").is_empty() else "group", "form": "cloud"})
	data.events.append(e)
	index = data.events.size() - 1
	_sync_linked_hits(true)
	_mark_changed()
	_refresh_inspector.call_deferred()

func duplicate_event() -> void:
	if event().is_empty(): return
	_remember("duplicate")
	var copy := event().duplicate(true)
	copy.t = float(copy.get("t", 0.0)) + 0.15
	copy.erase("_editor_id")
	copy.erase("_editor_source")
	data.events.append(copy)
	index = data.events.size() - 1
	_sync_linked_hits(bool(copy.get("_editor_follow", false)))
	_mark_changed()
	_refresh_inspector.call_deferred()

func delete_event() -> void:
	if event().is_empty(): return
	_remember("delete")
	var id := String(event().get("_editor_id", ""))
	data.events.remove_at(index)
	if not id.is_empty():
		for i in range(data.events.size() - 1, -1, -1):
			if data.events[i].get("_editor_source") == id: data.events.remove_at(i)
	index = mini(index, data.events.size() - 1)
	_mark_changed()
	_refresh_inspector.call_deferred()

func _ask_template() -> void:
	_pending_template = maxi(0, _template_picker.selected)
	_replace_dialog.dialog_text = "将「%s」模板应用到当前特效。\n可以应用形状与节奏，或只应用颜色、材质等外观。\n发生时间和其他特效保持不变，修改可以撤销。" % Catalog.presets(category)[_pending_template][0]
	_replace_dialog.popup_centered()

func apply_template(which: int) -> void:
	apply_preset(which, false)

func apply_preset(which: int, look_only: bool) -> void:
	var preset := Catalog.create(category, which)
	var source: Dictionary = preset.data.events[0]
	if event().get("do") != source.get("do") or String(preset.style.renderer) != _renderer():
		_status.text = "此模板需要不同的效果类型或表现方式；用「＋ 新建」创建，当前草稿会保留"
		return
	_remember("template")
	if look_only:
		var keys := ["element", "shape", "palette", "unit", "form", "ramp", "ink_kind"]
		if source.do == "slash": keys.append("width")
		for key: String in keys:
			if source.has(key): event()[key] = source[key]
	else:
		var old := event().duplicate(true)
		for field: Array in Legacy.FIELDS.get(String(old.do), []):
			if field[0] != "t": event().erase(field[0])
		if old.do == "quake":
			for key: String in Quake.DEFAULTS: event().erase(key)
		for key: String in source:
			if key not in ["t", "do"]: event()[key] = source[key]
		if source.do == "quake" and not (TEMPLATES[which][2] as Dictionary).has("unit"):
			event().unit = old.get("unit", "earth")
			if old.has("ramp"): event().ramp = old.ramp
	_sync_linked_hits()
	_mark_changed()
	_refresh_inspector.call_deferred()
	_status.text = "已套用「%s」%s；可撤销" % [preset.style.title, "的外观" if look_only else "的形状与节奏"]

# --- Category panels ------------------------------------------------------------------------

func _clear_inspector() -> void:
	for child in _inspector.get_children():
		_inspector.remove_child(child)
		child.queue_free()
	_open_group = null

func _refresh_inspector() -> void:
	if _building_panel or _inspector == null: return
	_building_panel = true
	_clear_inspector()
	_filling = true
	if event().is_empty():
		_inspector.add_child(_label("暂无效果，请选模板新建或展开编排添加"))
		_filling = false
		_building_panel = false
		return
	var kind := String(event().get("do", ""))
	var subtitle := ""
	if kind == "slash": subtitle = Legacy.RENDERER_NAMES[maxi(0, Legacy.RENDERERS.find(_renderer()))]
	elif kind == "cast": subtitle = Legacy.ELEMENT_NAMES[maxi(0, Legacy.ELEMENTS.find(String(event().get("element", "fire"))))]
	elif kind == "quake": subtitle = Materials.NAMES[String(spec().unit)]
	elif kind == "swarm": subtitle = "%s · %s" % [String(spec().id), Catalog.Swarm.FORM_NAMES[String(spec().form)]]
	var heading := _label(String(Legacy.DO_NAMES.get(kind, kind)) + (" · " + subtitle if not subtitle.is_empty() else ""))
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("ffe0a3"))
	_inspector.add_child(heading)
	if kind == "quake":
		_quake_panel()
	else:
		generic_panel(kind)
	_filling = false
	_building_panel = false

func _fold(title: String, expanded: bool, note := "") -> VBoxContainer:
	var key := String(event().get("do", "")) + ":" + title
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 3)
	var button := _button("", func() -> void: pass)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 32
	button.add_theme_stylebox_override("normal", panel_style())
	button.add_theme_color_override("font_color", Color("d5e6f2"))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.visible = bool(_folds.get(key, expanded))
	button.text = ("▾ " if content.visible else "▸ ") + title
	button.pressed.connect(func() -> void:
		content.visible = not content.visible
		_folds[key] = content.visible
		button.text = ("▾ " if content.visible else "▸ ") + title)
	wrapper.add_child(button)
	wrapper.add_child(content)
	_inspector.add_child(wrapper)
	if not note.is_empty():
		var label := _label(note)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 12)
		label.modulate = Color("8fabbf")
		content.add_child(label)
	_open_group = content
	return content

func _section(title: String, note := "") -> void:
	# The existing ground editor writes flat sections. Tag them for regrouping below.
	var offset := _inspector.get_child_count()
	super._section(title, note)
	_inspector.get_child(offset + 1).set_meta("editor_section", title)

func _quake_panel() -> void:
	var destination := _inspector
	var flat := VBoxContainer.new()
	_inspector = flat
	super._refresh_inspector()
	_inspector = destination
	_open_group = null
	var group: VBoxContainer
	for child in flat.get_children():
		flat.remove_child(child)
		if child.has_meta("editor_section"):
			var title := String(child.get_meta("editor_section"))
			if title == "场景模板": group = null
			else: group = _fold(title, title in ["材质", "范围"], "")
			child.queue_free()
		elif group != null: group.add_child(child)
		else: child.queue_free()
	flat.free()
	_filling = true
	var look := _fold("画风与精细度", false)
	_style_picker = _option(Materials.STYLE_NAMES.values(), Materials.STYLES, String(style.get("quake_style", "real")), func(value: String) -> void: set_look("quake_style", value))
	_group_row(look, "画风", _style_picker)
	_detail_picker = _option(Materials.DETAIL_NAMES.values(), Materials.DETAILS, String(style.get("quake_detail", "explosive")), func(value: String) -> void: set_look("quake_detail", value))
	_group_row(look, "精细度", _detail_picker)
	_open_group = null

func _row(text: String, control: Control) -> HBoxContainer:
	return _group_row(_open_group if _open_group != null and _inspector.get_parent() != null else _inspector, text, control)

func _group_row(parent: Control, text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label(text)
	label.custom_minimum_size.x = 108
	label.tooltip_text = text
	label.clip_text = true
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	parent.add_child(row)
	return row

func _slider(text: String, key: String, low: float, high: float, step: float, refresh := false) -> void:
	var box := HBoxContainer.new()
	var current := spec()
	var value := float(current.get(key, event().get(key, 0.0)))
	var slider := HSlider.new()
	slider.min_value = minf(low, value)
	slider.max_value = maxf(high, value)
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.drag_started.connect(func() -> void: begin_gesture(key))
	slider.drag_ended.connect(func(_changed: bool) -> void: end_gesture())
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 82
	var integer := key in ["seed", "count", "fingers", "rings", "level"]
	slider.value_changed.connect(func(v: float) -> void:
		var bounded := clampf(v, low, high)
		spin.set_value_no_signal(bounded)
		set_field(key, int(bounded) if integer else bounded, refresh))
	spin.value_changed.connect(func(v: float) -> void:
		var bounded := clampf(v, low, high)
		spin.set_value_no_signal(bounded)
		slider.set_value_no_signal(bounded)
		set_field(key, int(bounded) if integer else bounded, refresh))
	box.add_child(slider)
	box.add_child(spin)
	box.add_child(_button("↺", func() -> void: set_field(key, null, true), "恢复该参数默认值"))
	_row(text, box)

func _option(names: Array, values: Array, value: Variant, changed: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.fit_to_longest_item = false
	picker.focus_mode = Control.FOCUS_NONE
	for name: Variant in names: picker.add_item(String(name))
	var selected := values.find(value)
	if selected < 0:
		picker.add_item("保留：%s" % str(value))
		selected = names.size()
	picker.select(selected)
	picker.item_selected.connect(func(i: int) -> void:
		if i < values.size(): changed.call(values[i]))
	return picker

func _field_option(label: String, key: String, names: Array, values: Array, fallback: Variant) -> void:
	_row(label, _option(names, values, spec().get(key, fallback), func(value: Variant) -> void: set_field(key, value, true)))

func generic_panel(kind: String) -> void:
	if kind == "swarm":
		_actor_panel(kind)
		return
	if kind in ["caption", "impact"]:
		_show_panel(kind)
		return
	var appearance := _fold("外观", true)
	if kind == "slash":
		_row("表现（整套）", _option(Catalog.BLADE_NAMES, Catalog.BLADE_RENDERERS, _renderer(), _change_blade_renderer))
		if _renderer() == "ink":
			_field_option("笔势", "ink_kind", ["干笔横扫", "折腕", "点刺", "回卷", "下落"], ["dry", "elbow", "dot", "coil", "fall"], "dry")
		elif _renderer() == "claw": _field_option("爪痕形状", "claw", Legacy.CLAW_NAMES, Legacy.CLAW_KINDS, "arc")
	if kind == "cast":
		_field_option("元素", "element", Legacy.ELEMENT_NAMES, Legacy.ELEMENTS, "fire")
		_field_option("形态", "shape", Legacy.CAST_OPTIONS.shape[1], Legacy.CAST_OPTIONS.shape[0], "")
		_row("精细度", _option(Magic.QUALITY_NAMES.values(), Magic.QUALITIES, String(style.get("magic_quality", "explosive")), func(value: String) -> void: set_look("magic_quality", value)))
	if kind in ["slash", "hit", "cut"] and _renderer() != "ink":
		_field_option("配色", "palette", Catalog.PALETTE_NAMES, Legacy.PALETTES, "normal")
	var groups := {"外观": appearance}
	for title in ["范围与路径", "节奏", "冲击", "高级细节"]:
		groups[title] = _fold(title, title in ["范围与路径", "节奏"])
	for field: Array in Legacy.FIELDS.get(kind, []):
		var key: String = field[0]
		if key in ["element", "shape", "palette", "claw", "mix", "start", "end", "path", "at"]: continue
		if not _visible_field(field, kind): continue
		var title := "高级细节"
		if key in ["width", "size", "tint", "fingers", "spread", "thickness", "finisher", "red"]: title = "外观"
		if key in ["from", "to", "radius", "squash", "tilt", "angle", "length", "arc", "wave", "turns", "offset_x", "offset_y", "by_x", "by_y", "at_x", "at_y", "past"]: title = "范围与路径"
		if key in ["t", "duration", "tail", "charge", "travel", "time", "interval", "count", "hold", "cross_delay"]: title = "节奏"
		if key in ["push", "launch", "stop", "shake", "spark", "strength", "contact"]: title = "冲击"
		_open_group = groups[title]
		if key in ["by_x", "by_y", "at_x", "at_y"]:
			_vector_field(field)
		elif String(field[6]) == "bool" or key == "burst":
			_boolean_field(field)
		elif key == "tint":
			var picker := ColorPickerButton.new()
			picker.color = Color.from_string(String(spec().get(key, field[5])), Color.WHITE)
			picker.color_changed.connect(func(value: Color) -> void: set_field(key, value.to_html(false)))
			_row(field[1], picker)
		elif String(field[6]) == "optional":
			var check := CheckBox.new()
			check.text = "启用"
			check.button_pressed = event().has(key)
			check.toggled.connect(func(on: bool) -> void: set_field(key, field[5] if on else null, true))
			_row(field[1], check)
			if event().has(key): _slider("数值", key, field[2], field[3], field[4])
		else: _slider(_friendly_label(key, String(field[1])), key, field[2], field[3], field[4])
	if kind == "cast":
		_open_group = groups["范围与路径"]
		if not Catalog.stationary(event()):
			if event().get("element") == "ice":
				_row("飞行路径", _option(["直线（冰元素）", "原地"], ["straight", "stay"], Catalog.effective_path(event()), func(value: String) -> void: set_field("path", value, true)))
			else: _field_option("飞行路径", "path", Legacy.CAST_OPTIONS.path[1], Legacy.CAST_OPTIONS.path[0], "arc")
		_point_editor("中心" if Catalog.stationary(event()) else "起点", "start")
		if not Catalog.stationary(event()): _point_editor("落点", "end")
		_open_group = groups["高级细节"]
		var grid := GridContainer.new()
		grid.columns = 3
		for i in Legacy.ELEMENTS.size():
			var element: String = Legacy.ELEMENTS[i]
			var check := CheckBox.new()
			check.text = Legacy.ELEMENT_NAMES[i]
			check.disabled = element == String(event().get("element", "fire"))
			check.button_pressed = element in spec().mix
			check.toggled.connect(func(on: bool) -> void:
				var values: Array = (event().get("mix", []) as Array).duplicate()
				if on and not element in values: values.append(element)
				if not on: values.erase(element)
				set_field("mix", values))
			grid.add_child(check)
		_open_group.add_child(_label("混合元素"))
		_open_group.add_child(grid)
	if kind == "slash" and _renderer().is_empty():
		_open_group = groups["节奏"]
		_slider("挥动用时 / s", "duration", 0.015, 0.6, 0.005)
		_slider("消散用时 / s", "fade", 0.02, 1.5, 0.01)
	if kind in ["slash", "cast"]:
		_open_group = groups["冲击"]
		var follow := CheckBox.new()
		follow.text = "命中跟随本效果的节奏"
		follow.button_pressed = bool(event().get("_editor_follow", false))
		follow.toggled.connect(_set_follow)
		_open_group.add_child(follow)
		_open_group.add_child(_button("创建 / 对齐关联命中", func() -> void: _set_follow(true), "只更新本效果关联的命中，不移动其他招式的命中"))
	if _renderer() != "magic":
		_open_group = groups["高级细节"]
		if kind == "slash" and _renderer() != "ink":
			_style_slider("整体粗细", "thickness", 0.2, 3.0, 0.05, 1.0)
			_style_slider("像素颗粒", "pixel", 1.0, 8.0, 1.0, 3.0)
	_open_group = null
	# Empty groups have no editable parameters and need no header.
	for group: VBoxContainer in groups.values():
		if group.get_child_count() == 0: group.get_parent().hide()
	_document_details()

func _document_details() -> void:
	if _renderer() not in ["magic", "claw"]: return
	var group := _fold("作品字幕", false, "每行填写：时间 文字。")
	var captions := TextEdit.new()
	captions.custom_minimum_size.y = 100
	var lines := PackedStringArray()
	for entry: Variant in data.get("captions", []):
		if entry is Array and entry.size() >= 2: lines.append("%s %s" % [entry[0], entry[1]])
	captions.text = "\n".join(lines)
	captions.text_changed.connect(func() -> void:
		var changed: Array = []
		for line: String in captions.text.split("\n"):
			if line.strip_edges().is_empty(): continue
			var pair := line.strip_edges().split(" ", false, 1)
			if pair.size() != 2 or not pair[0].is_valid_float():
				_status.text = "字幕格式：每行先写秒数，再空格加文字；当前输入暂未应用"
				return
			changed.append([float(pair[0]), pair[1]])
		_remember("captions")
		data.captions = changed
		_mark_changed())
	group.add_child(captions)
	_open_group = null

func _friendly_label(key: String, fallback: String) -> String:
	if key in ["t", "duration", "tail", "charge", "travel", "time", "interval", "hold", "linger", "fuse", "stop", "cross_delay"]: return fallback.split("（")[0] + " / s"
	return fallback

func _visible_field(field: Array, kind: String) -> bool:
	var key: String = field[0]
	var shown: String = field[6]
	var renderer := _renderer()
	if kind == "slash" and renderer == "ink": return key in ["t", "width"] or (key == "tilt" and event().get("ink_kind", "dry") == "dot")
	if kind == "slash" and renderer == "claw" and key in ["from", "to", "squash", "tilt"] and event().get("claw", "arc") != "arc": return false
	if shown == "stock" and not renderer.is_empty(): return false
	if shown == "timed" and not renderer in ["ribbon", "claw"]: return false
	if shown == "claw" and renderer != "claw": return false
	if shown.begins_with("k:") and (renderer != "claw" or not String(event().get("claw", "arc")) in shown.trim_prefix("k:").split("|")): return false
	if shown.begins_with("e:") and not String(event().get("element", "fire")) in shown.trim_prefix("e:").split("|"): return false
	if shown.begins_with("f:") and not Catalog.effective_path(event()) in shown.trim_prefix("f:").split("|"): return false
	if shown.begins_with("tr:") and not String(spec().layout) in shown.trim_prefix("tr:").split("|"): return false
	if shown.begins_with("sw:") and not String(spec().form) in shown.trim_prefix("sw:").split("|"): return false
	return true

# --- 地形 and 群体 ---------------------------------------------------------------------------

func _actor_ids(kind: String) -> Array:
	var ids: Array = []
	for e: Dictionary in data.get("events", []):
		if e.get("do") == kind and not String(e.get("id", "")) in ids: ids.append(String(e.get("id", "")))
	if node_mode:
		for e: Dictionary in preview_context:
			if e.get("do")==kind and float(e.get("t",0))<=preview_start and not String(e.get("id","")) in ids:ids.append(String(e.get("id","")))
	return ids

func _free_id(kind: String, base: String) -> String:
	var ids := _actor_ids(kind)
	if not base in ids: return base
	var n := 2
	while "%s%d" % [base, n] in ids: n += 1
	return "%s%d" % [base, n]

func _actor_panel(kind: String) -> void:
	var look := _fold("外观", true)
	_open_group = look
	var name_edit := LineEdit.new()
	name_edit.text = String(spec().id)
	name_edit.tooltip_text = "同名的事件控制同一个%s：第一次出现时进场，之后变换" % ("群体")
	name_edit.text_submitted.connect(func(value: String) -> void:
		if not value.strip_edges().is_empty(): set_field("id", value.strip_edges(), true))
	name_edit.focus_exited.connect(func() -> void:
		var value := name_edit.text.strip_edges()
		if not value.is_empty() and value != String(spec().id): set_field("id", value, true))
	_row("名称", name_edit)
	var ramps: Array = ["材质默认"]
	var ramp_values: Array = [""]
	for key: String in Materials.COLORWAYS:
		ramps.append(Materials.COLORWAYS[key][0])
		ramp_values.append(key)
	var swarm := Catalog.Swarm
	_field_option("队形", "form", swarm.FORM_NAMES.values(), swarm.FORMS, "cloud")
	_field_option("材质", "material", swarm.PieceMaterials.NAMES.values(), swarm.PieceMaterials.KEYS, "leaf")
	ramps.remove_at(0)
	ramp_values.remove_at(0)
	_field_option("配色", "ramp", ramps, ramp_values, "autumn")
	_row("画风", _option(Materials.STYLE_NAMES.values(), Materials.STYLES, String(style.get("quake_style", "real")), func(value: String) -> void: set_look("quake_style", value)))
	_row("精细度", _option(Materials.DETAIL_NAMES.values(), Materials.DETAILS, String(style.get("quake_detail", "explosive")), func(value: String) -> void: set_look("quake_detail", value)))
	if kind == "swarm" and spec().material in ["leaf", "feather", "sand"]:
		_open_group = _fold("材质特性", true)
		for field: Array in Catalog.Swarm.PieceMaterials.FIELDS[String(spec().material)]:
			_slider(field[1], field[0], field[2], field[3], field[4])
	var groups := {"外观": look}
	for title in ["范围与位置", "节奏", "高级细节"]: groups[title] = _fold(title, title != "高级细节")
	_open_group = groups["范围与位置"]
	var at: Variant = event().get("at", "target")
	_row("中心", _option(["攻击者", "目标", "画面坐标"], ["attacker", "target", "point"], "point" if at is Array else at,
		func(value: String) -> void: set_field("at", [640, 400] if value == "point" else value, true)))
	if at is Array: _coordinate_row("坐标", "at", -1, at)
	for field: Array in Legacy.FIELDS[kind]:
		var key: String = field[0]
		if String(field[6]) == "sel" or not _visible_field(field, kind): continue
		var title := "范围与位置"
		if key in ["t", "time", "travel", "linger", "turn"]: title = "节奏"
		if key in ["size", "guard", "count", "swarm_count"]: title = "外观"
		if key in ["seed", "swirl", "turbulence", "tumble"]: title = "高级细节"
		_open_group = groups[title]
		_slider(_friendly_label(key, String(field[1])), key, field[2], field[3], field[4])
	if kind == "swarm" and spec().form == "stream":
		_open_group = groups["范围与位置"]
		var row := HBoxContainer.new()
		row.add_child(_button("自动路径", func() -> void: set_field("path", null, true), "从攻击者身后越顶扑向中心"))
		row.add_child(_button("＋ 路径点", func() -> void:
			var points: Array = (spec().path as Array).duplicate(true)
			if points.size() < 2: points = _default_stream_path()
			points.insert(points.size() - 1, [640.0, 260.0])
			set_field("path", points, true)))
		_open_group.add_child(row)
	_open_group = null
	for group: VBoxContainer in groups.values():
		if group.get_child_count() == 0: group.get_parent().hide()

func _show_panel(kind: String) -> void:
	var look := _fold("外观", true)
	_open_group = look
	if kind == "caption":
		var text := LineEdit.new()
		text.text = String(spec().text)
		text.text_changed.connect(func(value: String) -> void: set_field("text", value))
		_row("文字", text)
		_field_option("位置", "place", Catalog.Caption.PLACE_NAMES.values(), Catalog.Caption.PLACES, "title")
	else:
		_field_option("方式", "kind", Catalog.Impact.KIND_NAMES.values(), Catalog.Impact.KINDS, "invert")
	var picker := ColorPickerButton.new()
	picker.color = Color.from_string(String(spec().color), Color.WHITE)
	picker.color_changed.connect(func(value: Color) -> void: set_field("color", value.to_html(false)))
	_row("颜色", picker)
	var rhythm := _fold("节奏", true)
	for field: Array in Legacy.FIELDS[kind]:
		if String(field[6]) == "sel": continue
		_open_group = rhythm if field[0] in ["t", "time", "fade"] else look
		_slider(_friendly_label(String(field[0]), String(field[1])), String(field[0]), field[2], field[3], field[4])
	_open_group = _fold("画面", false, "黑边属于整部作品：上下两条，占画面高度的比例。")
	_style_slider("黑边", "letterbox", 0.0, 0.2, 0.005, 0.0)
	_open_group = null

## The stream path the swarm uses when none is set, as editable points.
func _default_stream_path() -> Array:
	var swarm: Node2D = Catalog.Swarm.new()
	swarm.stage = stage
	var s: Dictionary = Catalog.Swarm.normalized(event())
	var points: Array = []
	for p in swarm._path(s, swarm._anchor(s)): points.append([roundf(p.x), roundf(p.y)])
	swarm.free()
	return points

## Where a group is anchored on the stage now.
func _actor_anchor(kind: String) -> Vector2:
	var s := spec()
	var at: Variant = s.at
	var point := Vector2(640, 400)
	if at is Array: point = Vector2(float(at[0]), float(at[1]))
	elif String(at) == "attacker": point = stage.attacker.position
	elif String(at) == "target": point = stage.target.position + Vector2(0, -stage.TARGET_SIZE.y * 0.5)
	return point + Vector2(float(s.offset_x), float(s.offset_y))

func _boolean_field(field: Array) -> void:
	var check := CheckBox.new()
	check.text = "开启"
	check.button_pressed = bool(spec().get(field[0], field[5]))
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void: set_field(field[0], on, field[0] == "auto_tilt"))
	_row(field[1], check)

func _style_slider(label: String, key: String, low: float, high: float, step: float, fallback: float) -> void:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = float(style.get(key, fallback))
	spin.value_changed.connect(func(value: float) -> void: _style_number(key, value))
	_row(label, spin)

func _change_blade_renderer(value: String) -> void:
	if value == _renderer(): return
	if (data.events as Array).any(func(e: Dictionary) -> bool: return e.get("do") == "cast"):
		_status.text = "当前作品含施法效果，不能直接切换整套表现方式；请从刀光入口新建"
		_refresh_inspector.call_deferred()
		return
	_remember("blade_renderer")
	style.renderer = value
	_sync_linked_hits()
	_mark_changed()
	_refresh_inspector.call_deferred()
	_status.text = "已更改整套刀光表现；其他参数保留，可撤销"

func _vector_field(field: Array) -> void:
	var key: String = field[0]
	var array_key := "by" if key.begins_with("by") else "at"
	var axis := 0 if key.ends_with("x") else 1
	var fallback: Array = [0, 0] if array_key == "by" else [640, 360]
	var values: Array = event().get(array_key, fallback)
	var spin := SpinBox.new()
	spin.min_value = field[2]
	spin.max_value = field[3]
	spin.step = field[4]
	spin.value = float(values[axis])
	spin.value_changed.connect(func(value: float) -> void:
		var changed: Array = (event().get(array_key, fallback) as Array).duplicate()
		changed[axis] = value
		set_field(array_key, changed))
	_row(field[1], spin)

func _point_editor(label: String, key: String) -> void:
	var choices: Array = Legacy.CAST_OPTIONS[key]
	var value: Variant = spec().get(key, "hand" if key == "start" else "target")
	_row(label, _option(choices[1] + ["画面坐标 / 多点"], choices[0] + ["point"], "point" if value is Array else value, func(selected: String) -> void:
		if selected == "point": set_field(key, [380, 446] if key == "start" else [840, 470], true)
		else: set_field(key, selected, true)))
	if not value is Array: return
	var points := _point_list(value)
	for i in points.size():
		var item: Variant = points[i]
		if item is Array: _coordinate_row("%s %d" % [label, i + 1], key, i, item)
		else:
			var row := HBoxContainer.new()
			row.add_child(_label("%s %d" % [label, i + 1]))
			var at: int = i
			row.add_child(_option(choices[1] + ["画面坐标"], choices[0] + ["point"], item, func(selected: String) -> void:
				var changed := _point_list(event()[key])
				changed[at] = [640, 450] if selected == "point" else selected
				set_field(key, changed, true)))
			_open_group.add_child(row)
	var actions := HBoxContainer.new()
	actions.add_child(_button("＋ 增加%s" % label, func() -> void:
		var changed := _point_list(event()[key])
		changed.append([640 + changed.size() * 30, 450])
		set_field(key, changed, true)))
	if points.size() > 1:
		actions.add_child(_button("－ 删除末点", func() -> void:
			var changed := _point_list(event()[key])
			changed.pop_back()
			set_field(key, changed, true)))
	_open_group.add_child(actions)

func _point_list(value: Array) -> Array:
	if value.size() == 2 and (value[0] is int or value[0] is float): return [value.duplicate()]
	return value.duplicate(true)

func _coordinate_row(label: String, key: String, point: int, value: Array) -> void:
	var row := HBoxContainer.new()
	for axis in 2:
		var spin := SpinBox.new()
		spin.min_value = -2000
		spin.max_value = 3000
		spin.step = 1
		spin.value = float(value[axis])
		spin.prefix = "X " if axis == 0 else "Y "
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var component := axis
		spin.value_changed.connect(func(number: float) -> void:
			if point < 0:
				var changed: Array = (event()[key] as Array).duplicate()
				changed[component] = number
				set_field(key, changed)
			else:
				var changed := _point_list(event()[key])
				(changed[point] as Array)[component] = number
				set_field(key, changed))
		row.add_child(spin)
	_row(label, row)

func _stage_table(s: Dictionary) -> void:
	# Each propagation segment is a readable card rather than a five-column spreadsheet.
	for i in s.stages.size():
		var card := VBoxContainer.new()
		card.add_child(_label("第 %d 段推进" % (i + 1)))
		var fields := [["distance", "距离比例", 0.1, 10.0], ["time", "推进 / s", 0.02, 3.0], ["strength", "强度", 0.0, 3.0]]
		if i < s.stages.size() - 1: fields.append(["pause", "随后停顿 / s", 0.0, 3.0])
		for field: Array in fields:
			var spin := SpinBox.new()
			spin.min_value = field[2]
			spin.max_value = field[3]
			spin.step = 0.01
			spin.value = float(s.stages[i][field[0]])
			var at: int = i
			var key: String = field[0]
			spin.value_changed.connect(func(value: float) -> void:
				var changed: Array = spec().stages.duplicate(true)
				changed[at][key] = value
				set_field("stages", changed))
			_group_row(card, field[1], spin)
		_inspector.add_child(card)
	var actions := HBoxContainer.new()
	var add := _button("＋ 加一段", func() -> void:
		var changed: Array = spec().stages.duplicate(true)
		changed[-1].pause = maxf(0.15, float(changed[-1].pause))
		changed.append({"distance": 1.0, "time": 0.15, "pause": 0.0, "strength": 1.0})
		set_field("stages", changed, true))
	add.disabled = s.stages.size() >= 8
	actions.add_child(add)
	var remove := _button("－ 删末段", func() -> void:
		var changed: Array = spec().stages.duplicate(true)
		changed.pop_back()
		set_field("stages", changed, true))
	remove.disabled = s.stages.size() <= 1
	actions.add_child(remove)
	_inspector.add_child(actions)

# --- Deterministic preview and a shared phase timeline ----------------------------------------

func total_time() -> float:
	if _duration_cache >= 0: return _duration_cache
	var last := 1.0
	for e: Dictionary in data.get("events", []): last = maxf(last, float(e.get("t", 0.0)) + Catalog.duration(e, _renderer()))
	_duration_cache = last + 0.15
	return _duration_cache

func phase_blocks() -> Array:
	return Catalog.phases(event(), _renderer()) if not event().is_empty() else []

func set_phase(key: String, value: float) -> void:
	if key.begins_with("stages:"):
		var parts := key.split(":")
		var stages: Array = spec().stages.duplicate(true)
		stages[int(parts[1])][parts[2]] = clampf(value, 0.0 if parts[2] == "pause" else 0.02, 3.0)
		set_field("stages", stages)
	else: set_field(key, value)

func event_colour(e: Dictionary) -> Color:
	return Legacy.DO_COLOURS.get(String(e.get("do", "")), Color("94a7bb"))

func _build() -> void:
	_rebuild_in = -1.0
	_duration_cache = -1.0
	for child in _host.get_children(): child.free()
	_host.left = 0.0
	_host.clock = 0.0
	ComboStyle.load_data(style.duplicate(true))
	var script: GDScript = ComboStage
	var renderer := _renderer()
	if not renderer.is_empty() and ResourceLoader.exists("res://vfx/%s_stage.gd" % renderer): script = load("res://vfx/%s_stage.gd" % renderer)
	if node_mode: script = preload("res://vfx/flow_stage.gd")
	stage = script.new()
	_host.add_child(stage)
	stage.set_process_unhandled_input(false)
	stage.set_process(false)
	stage.help.visible = false
	if "quality_label" in stage and stage.quality_label != null: stage.quality_label.visible = false
	if renderer in ["ribbon", "ink"]:
		if "caption" in stage: stage.caption.visible = false
		if "rhythm" in stage: stage.rhythm.visible = false
	stage.TIMELINE = ComboStage.parse_events(data.events)
	if "captions" in stage: stage.captions = data.get("captions", []).duplicate(true)
	stage.reset()
	stage.play()
	# reset() is responsible for the simulation, including magic's wall clock.
	if "real_clock" in stage: stage.real_clock = 0.0
	_camera_position = Vector2(640, 360)
	_camera_zoom = Vector2.ONE
	_preview_elapsed = 0.0
	if bool(_preview.get_meta("checker", false)):
		var checker := preload("res://vfx/combo_editor.gd").Checker.new()
		stage.add_child(checker)
		stage.move_child(checker, 0)
	if node_mode and preview_with_context:
		var local: Array = data.events.duplicate(true)
		for e: Dictionary in local:
			e["_flow_renderer"] = e.get("_flow_renderer",renderer)
			e["_flow_style"] = e.get("_flow_style",style).duplicate(true)
		var context: Array = preview_context.filter(func(e: Dictionary)->bool:return String(e.get("_flow_node",""))!=String(node_document.get("id","")))
		var prepared := preload("res://vfx/preview_context.gd").prepare(local,context,preview_start)
		stage.TIMELINE = ComboStage.parse_events(prepared.timeline)
		stage.play()
		var steps := 0
		var prime_end := maxf(0.0,float(prepared.lead)-.0001)
		while stage.clock<prime_end-.00001 and steps<36000:
			stage.advance(minf(STEP,prime_end-stage.clock))
			for holder: Node in stage.effect_holders(): _prune_effects(holder)
			steps+=1
		stage.clock = 0.0
		stage._next = 0
		stage._stop = 0.0
		stage.TIMELINE = ComboStage.parse_events(prepared.local)
		if "_arrivals" in stage:
			for arrival: Dictionary in stage._arrivals: arrival.time = float(arrival.time)-float(prepared.lead)
		_context_notice.text = String(prepared.note)
		_context_notice.visible = not _context_notice.text.is_empty()
	elif _context_notice!=null: _context_notice.hide()

func _advance_stage(delta: float) -> void:
	var camera: Camera2D = stage._camera
	camera.zoom = _camera_zoom
	camera.position = _camera_position
	camera.offset = Vector2.ZERO
	# Keep the document clock moving through long residual effects. The editor owns the end.
	stage.playing = true
	stage.advance(delta)
	_preview_elapsed += delta
	_camera_position = camera.position
	_camera_zoom = camera.zoom
	# Rebuilding many simulation steps in one frame must not accumulate deferred deletions.
	for holder: Node in stage.effect_holders(): _prune_effects(holder)
	if "under" in stage and stage.under != null: _prune_effects(stage.under)
	stage.update_layers()

func _prune_effects(parent: Node) -> void:
	for child in parent.get_children():
		if child.is_queued_for_deletion(): child.free()

func _seek(t: float) -> void:
	var target := clampf(t, 0.0, total_time())
	_build()
	_set_playing(false)
	var shake := _host.enabled
	_host.enabled = false
	var steps := 0
	while stage.clock < target - 0.00001 and steps < 36000:
		_advance_stage(minf(STEP, target - stage.clock))
		steps += 1
	_host.enabled = shake
	_update_camera(0.0)
	_scrubber.queue_redraw()
	_canvas.queue_redraw()

func _process(delta: float) -> void:
	if _rebuild_in >= 0.0:
		_rebuild_in -= delta
		if _rebuild_in < 0.0:
			if playing: _replay()
			else: _seek(now())
	if stage != null and playing:
		var remaining := minf(delta, 0.1) * speed
		while remaining > 0.00001 and now() < total_time():
			var step := minf(STEP, remaining)
			_advance_stage(step)
			remaining -= step
		if now() >= total_time():
			if looping:
				if _rest < 0.0: _rest = 0.45
				_rest -= delta
				if _rest <= 0.0: _replay()
			else: _set_playing(false)
	_update_camera(delta)
	_time_label.text = "%.2f / %.2fs" % [now(), total_time()]
	_dirty_label.text = "未保存" if dirty else "已保存"
	_scrubber.queue_redraw()
	_canvas.queue_redraw()

func _update_camera(delta: float) -> void:
	if stage == null: return
	var camera: Camera2D = stage._camera
	var has_camera := (data.events as Array).any(func(e: Dictionary) -> bool: return e.get("do") == "camera")
	if has_camera:
		camera.position = _camera_position
		camera.zoom = _camera_zoom * zoom
	else:
		camera.zoom = Vector2.ONE * zoom
		var focus := Vector2(640, 360)
		if event().get("do") == "quake": focus = Vector2(float(spec().x), float(spec().y) - 90)
		elif stage.attacker != null: focus = stage.attacker.position.lerp(stage.target.position + Vector2(0, -48), 0.5)
		var half := Vector2(640, 360) / zoom
		camera.position = Vector2(clampf(focus.x, half.x, 1280 - half.x), clampf(focus.y, half.y, 720 - half.y)) if zoom > 1 else Vector2(640, 360)
	camera.offset = _host.tick(delta if playing else 0.0) if playing else Vector2.ZERO

func to_preview(world: Vector2) -> Vector2:
	var ratio := minf(_preview.size.x / 1280.0, _preview.size.y / 720.0)
	var margin := (_preview.size - Vector2(1280, 720) * ratio) * 0.5
	var camera: Camera2D = stage._camera
	return margin + ((world - camera.position - camera.offset) * camera.zoom + Vector2(640, 360)) * ratio

func _to_stage(at: Vector2) -> Vector2:
	var point := super._to_stage(at)
	return point + stage._camera.offset if stage != null else point

# --- Canvas helpers map to actual renderer fields --------------------------------------------

func _handle(key: String, point: Vector2, label: String) -> Dictionary:
	return {"key": key, "point": point, "label": label}

func _ground_point(point: Vector2, s: Dictionary) -> Vector2:
	var rotated := point.rotated(deg_to_rad(float(s.angle)))
	return Vector2(float(s.x) + rotated.x, float(s.y) + rotated.y * float(s.perspective))

func _magic_skeleton() -> Node2D:
	var values := Magic.cast_spec(event())
	var element: GDScript = Magic.ELEMENTS.get(String(event().get("element", "fire")), Magic.ELEMENTS.fire)
	var shape := Magic.shape_of(values, element)
	var script: GDScript = element.SIGNATURES.get(shape)
	if script == null or (not (values.mix as Array).is_empty() and not script.get_script_constant_map().has("TAKES_MIX")): script = Magic.SHAPES[shape]
	var skeleton: Node2D = script.new()
	skeleton.stage = stage
	skeleton.materials = [element]
	for name: String in values.mix: skeleton.materials.append(Magic.ELEMENTS[name])
	for key: String in values:
		if key in skeleton: skeleton.set(key, values[key])
	return skeleton

func canvas_geometry() -> Dictionary:
	var result := {"line": PackedVector2Array(), "handles": []}
	if stage == null or event().is_empty(): return result
	var e := event()
	var s := spec()
	var handles: Array = []
	var line := PackedVector2Array()
	match String(e.get("do", "")):
		"quake":
			var center := Vector2(float(s.x), float(s.y))
			handles.append(_handle("center", center, "中心"))
			var radius := float(s.width) * 0.5
			var extent := radius + float(s.length) * 0.5
			if s.mode == "cone":
				line.append(center)
				for i in 49:
					var angle := deg_to_rad(lerpf(-float(s.cone) * 0.5, float(s.cone) * 0.5, i / 48.0))
					line.append(_ground_point(Vector2.from_angle(angle) * (float(s.width) + float(s.length)), s))
				line.append(center)
				handles.append(_handle("cone_width", _ground_point(Vector2(float(s.width) + float(s.length), 0), s), "半径"))
				handles.append(_handle("cone_angle", line[1], "扇形角度"))
			else:
				for i in 65:
					var angle := TAU * i / 64.0
					var point := Vector2.from_angle(angle) * radius
					point.x += signf(cos(angle)) * float(s.length) * 0.5
					line.append(_ground_point(point, s))
				handles.append(_handle("ground_width", _ground_point(Vector2(0, -radius), s), "宽度"))
				handles.append(_handle("ground_length", _ground_point(Vector2(extent, 0), s), "长度"))
			handles.append(_handle("ground_angle", _ground_point(Vector2(maxf(extent, 100) + 65, 0), s), "方向"))
		"cast":
			var skeleton := _magic_skeleton()
			var stationary := Catalog.stationary(e)
			if stationary:
				var center: Vector2 = skeleton.start_point(0)
				for i in 65: line.append(center + Vector2.from_angle(i * TAU / 64) * float(s.radius))
				handles.append(_handle("magic_radius", center + Vector2(float(s.radius), 0), "打击范围"))
			else:
				for i in 41: line.append(skeleton.path_at(0, i / 40.0))
			for key: String in ["start", "end"]:
				if stationary and key == "end": continue
				var raw: Variant = s[key]
				var count := _point_list(raw).size() if raw is Array else 1
				for i in count:
					var point: Vector2 = skeleton.start_point(i) if key == "start" else skeleton.end_point(i)
					handles.append(_handle("%s:%d" % [key, i], point, ("中心" if stationary else ("起点" if key == "start" else "落点")) + (" %d" % (i + 1) if count > 1 else "")))
			if Catalog.effective_path(e) == "arc": handles.append(_handle("magic_arc", skeleton.path_at(0, pow(0.5, 1.0 / float(s.ease))), "弧线"))
			skeleton.free()
		"slash":
			var origin: Vector2 = stage.attacker.position
			var renderer := _renderer()
			if renderer == "ink":
				handles.append(_handle("ink_width", stage.target.position + Vector2(0, -50 - float(s.width)), "笔触粗细"))
			elif renderer == "claw" and s.get("claw", "arc") in ["rake", "swipe", "cross"]:
				var middle: Vector2 = stage.target.position + Vector2(-13.2, -52.8)
				var direction := Vector2.from_angle(deg_to_rad(float(s.angle))) * float(s.length) * 0.5
				line = PackedVector2Array([middle - direction, middle + direction])
				handles.append(_handle("claw_end", middle + direction, "方向 / 长度"))
			else:
				var radius := float(s.get("radius", 140.0))
				var rotation := deg_to_rad(float(s.tilt))
				var aim_angle := 0.0
				if renderer in ["ribbon", "claw"]:
					var aim: Vector2 = (stage.target.position + Vector2(-13.2, -52.8) - origin).rotated(-rotation) / Vector2(1, maxf(0.05, float(s.squash)))
					radius = aim.length() + float(s.width) * 0.42
					aim_angle = aim.angle() - deg_to_rad((float(s.from) + float(s.to)) * 0.5)
				for i in 49:
					var angle := deg_to_rad(lerpf(float(s.from), float(s.to), i / 48.0)) + aim_angle
					line.append(origin + (Vector2.from_angle(angle) * Vector2(radius, radius * float(s.squash))).rotated(rotation))
				if renderer.is_empty(): handles.append(_handle("blade_radius", line[24], "半径"))
				handles.append(_handle("blade_from", line[0], "起始角"))
				handles.append(_handle("blade_to", line[-1], "结束角"))
				result["blade_origin"] = origin
				result["aim_angle"] = aim_angle
		"cut":
			var center: Vector2 = stage.target.position + Vector2(0, -48)
			var tip := center + Vector2.from_angle(deg_to_rad(float(s.angle))) * 95
			line = PackedVector2Array([center * 2 - tip, tip])
			handles.append(_handle("cut_angle", tip, "方向"))
		"swarm":
			var at := _actor_anchor("swarm")
			handles.append(_handle("actor_at", at, "中心"))
			if s.form == "stream":
				var points: Array = s.path if (s.path as Array).size() >= 2 else _default_stream_path()
				for i in points.size():
					var p := Vector2(float(points[i][0]), float(points[i][1]))
					line.append(p)
					handles.append(_handle("path:%d" % i, p, "路径 %d" % (i + 1)))
			elif s.form in ["cloud", "vortex", "sphere", "burst", "fall"]:
				var r := float(s.radius)
				var h := r
				var centre := at
				if s.form in ["cloud", "fall"]: h = float(s.height) * 0.5
				if s.form == "vortex":
					h = float(s.height) * 0.5
					centre = Vector2(at.x, stage.GROUND_Y - h)
				for i in 65: line.append(centre + Vector2(cos(i * TAU / 64) * r, sin(i * TAU / 64) * h))
				handles.append(_handle("swarm_radius", centre + Vector2(r, 0), "范围半径"))
				if s.form in ["cloud", "vortex", "fall"]: handles.append(_handle("swarm_height", centre + Vector2(0, -h), "范围高度"))
	result.line = line
	result.handles = handles
	return result

func _preview_input(input: InputEvent) -> void:
	if input is InputEventMouseButton and input.button_index == MOUSE_BUTTON_LEFT:
		if not input.pressed:
			drag_handle = ""
			_remembered_drag_geometry = {}
			end_gesture()
			return
		if not guides: return
		drag_handle = ""
		var geometry := canvas_geometry()
		var best := 15.0
		for handle: Dictionary in geometry.handles:
			var distance := to_preview(handle.point).distance_to(input.position)
			if distance < best:
				best = distance
				drag_handle = handle.key
		if not drag_handle.is_empty():
			_set_playing(false)
			begin_gesture("canvas:" + drag_handle)
			_remembered_drag_geometry = geometry
	elif input is InputEventMouseMotion and not drag_handle.is_empty():
		move_handle(drag_handle, _to_stage(input.position))

func move_handle(key: String, point: Vector2) -> void:
	var s := spec()
	var e := event()
	if String(e.get("do", "")) == "quake":
		var vector := point - Vector2(float(s.x), float(s.y))
		var unprojected := Vector2(vector.x, vector.y / float(s.perspective))
		var local := unprojected.rotated(-deg_to_rad(float(s.angle)))
		match key:
			"center":
				set_field("x", roundf(clampf(point.x, 0, 1280)))
				set_field("y", roundf(clampf(point.y, 300, 700)))
			"ground_width": set_field("width", clampf(absf(local.y) * 2, 8, 900))
			"ground_length": set_field("length", clampf((absf(local.x) - float(s.width) * 0.5) * 2, 0, 1800))
			"ground_angle": set_field("angle", rad_to_deg(unprojected.angle()))
			"cone_width": set_field("width", clampf(local.length() - float(s.length), 8, 900))
			"cone_angle": set_field("cone", clampf(absf(local.angle()) * 360 / PI, 10, 180))
	elif key.begins_with("start:") or key.begins_with("end:"):
		var parts := key.split(":")
		var field: String = parts[0]
		var raw: Variant = e.get(field, "hand" if field == "start" else "target")
		var points := _point_list(raw) if raw is Array else [[point.x, point.y]]
		points[int(parts[1])] = [roundf(point.x), roundf(point.y)]
		set_field(field, points[0] if points.size() == 1 else points)
	elif key == "magic_radius":
		var skeleton := _magic_skeleton()
		set_field("radius", clampf(point.distance_to(skeleton.start_point(0)), 10, 400))
		skeleton.free()
	elif key == "magic_arc":
		var skeleton := _magic_skeleton()
		var a: Vector2 = skeleton.start_point(0)
		var b: Vector2 = skeleton.end_point(0)
		var up := (b - a).orthogonal().normalized()
		if up.y > 0: up = -up
		set_field("arc", clampf((point - (a + b) * 0.5).dot(up) * 2, -400, 400))
		skeleton.free()
	elif key in ["blade_from", "blade_to", "blade_radius"]:
		var geometry := _remembered_drag_geometry if not _remembered_drag_geometry.is_empty() else canvas_geometry()
		var origin: Vector2 = geometry.blade_origin
		var vector := (point - origin).rotated(-deg_to_rad(float(s.tilt))) / Vector2(1, maxf(0.05, float(s.squash)))
		if key == "blade_radius": set_field("radius", clampf(vector.length(), 20, 600))
		else:
			var field := "from" if key == "blade_from" else "to"
			var angle := rad_to_deg(vector.angle() - float(geometry.aim_angle))
			var old := float(s[field])
			angle += roundf((old - angle) / 360) * 360
			set_field(field, angle)
	elif key == "ink_width": set_field("width", clampf(absf(point.y - (stage.target.position.y - 50)), 2, 240))
	elif key == "claw_end":
		var vector := point - (stage.target.position + Vector2(-13.2, -52.8))
		set_field("angle", rad_to_deg(vector.angle()))
		set_field("length", clampf(vector.length() * 2, 40, 800))
	elif key == "cut_angle": set_field("angle", rad_to_deg((point - (stage.target.position + Vector2(0, -48))).angle()))
	elif key == "actor_at":
		var lift := 0.0
		set_field("offset_x", 0.0)
		set_field("offset_y", 0.0)
		set_field("at", [roundf(point.x), roundf(point.y + lift)])
	elif key == "swarm_radius": set_field("radius", clampf(absf(point.x - _actor_anchor("swarm").x), 20, 1200))
	elif key == "swarm_height":
		var base := _actor_anchor("swarm").y if s.form != "vortex" else stage.GROUND_Y
		set_field("height", clampf(absf(base - point.y) * (1.0 if s.form == "vortex" else 2.0), 20, 800))
	elif key.begins_with("path:"):
		var points: Array = (s.path as Array).duplicate(true) if (s.path as Array).size() >= 2 else _default_stream_path()
		points[int(key.split(":")[1])] = [roundf(point.x), roundf(point.y)]
		set_field("path", points)

# --- Save and leave -------------------------------------------------------------------------

func _save() -> void:
	if node_mode:
		dirty = false
		node_committed.emit(_sorted(),style.duplicate(true))
		return
	if combo_path.is_empty():
		_save_new()
		return
	var folder := combo_path.get_base_dir()
	for filename in ["combo.json", "style.json"]:
		var path := folder.path_join(filename)
		if FileAccess.file_exists(path):
			var error := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
			if error != OK:
				_status.text = "备份失败，未保存：%s" % error_string(error)
				return
	if not _write_pair(folder): return
	_saved_state = _snapshot()
	dirty = false
	_capture_thumbnail()
	_stash()
	_fill_picker()
	_status.text = "已保存「%s」" % String(style.get("title", folder.get_file()))
	_run_after_save()

func _write_pair(folder: String) -> bool:
	# Stage both JSON files before replacing either destination. Backups permit recovery.
	if not _write(folder.path_join("combo.json.tmp"), _sorted()): return false
	if not _write(folder.path_join("style.json.tmp"), style): return false
	for filename in ["combo.json", "style.json"]:
		var error := DirAccess.rename_absolute(folder.path_join(filename + ".tmp"), folder.path_join(filename))
		if error != OK:
			_status.text = "保存失败，原数据备份保留：%s" % error_string(error)
			return false
	return true

func _save_new() -> void:
	_save_dialog.dialog_text = ""
	if _save_as.text.strip_edges().is_empty():
		var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
		var suggestion := "%s_%s" % [category, stamp]
		var number := 2
		while DirAccess.dir_exists_absolute(COMBOS.path_join(suggestion)):
			suggestion = "%s_%s_%d" % [category, stamp, number]
			number += 1
		_save_as.text = suggestion
	_save_dialog.popup_centered(Vector2i(490, 140))
	_save_as.grab_focus()

func _commit_new() -> void:
	var name := _save_as.text.strip_edges()
	if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(name) == null:
		_save_dialog.dialog_text = "文件标识请用英文小写开头，例如 my_fire_spell"
		return
	var folder := COMBOS.path_join(name)
	if DirAccess.dir_exists_absolute(folder):
		_save_dialog.dialog_text = "该标识已存在，请换一个；已有作品可以直接保存"
		return
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		_save_dialog.dialog_text = "无法创建作品文件夹"
		return
	if not _write_pair(folder): return
	var scene := FileAccess.open(folder.path_join(name + ".tscn"), FileAccess.WRITE)
	if scene == null:
		_save_dialog.dialog_text = "场景写入失败；草稿仍保留"
		return
	scene.store_string("[gd_scene format=3]\n\n[ext_resource type=\"Script\" path=\"res://vfx/combo_player.gd\" id=\"1\"]\n\n[node name=\"ComboPlayer\" type=\"Node2D\"]\nscript = ExtResource(\"1\")\ncombo_file = \"res://combos/%s/combo.json\"\nstyle_file = \"res://combos/%s/style.json\"\n" % [name, name])
	scene.close()
	var prompt := FileAccess.open(folder.path_join("prompt.md"), FileAccess.WRITE)
	if prompt != null:
		prompt.store_string("# %s\n\n在特效工作室中制作。\n" % String(style.get("title", name)))
		prompt.close()
	sessions.erase(session_key)
	combo_path = folder.path_join("combo.json")
	session_key = combo_path
	category_sessions[category] = session_key
	_saved_state = _snapshot()
	dirty = false
	_capture_thumbnail()
	_stash()
	_fill_picker()
	_save_dialog.hide()
	_status.text = "已另存为「%s」，可从画廊打开" % String(style.get("title", name))
	_run_after_save()

func _run_after_save() -> void:
	if _after_save.is_valid():
		var action := _after_save
		_after_save = Callable()
		action.call_deferred()

func _leave() -> void:
	if dirty: _leave_dialog.popup_centered()
	else: _return_gallery()

func _return_gallery() -> void:
	if node_mode:
		node_closed.emit()
		return
	Loading.open_scene(self, GALLERY, "正在返回画廊")

func _unhandled_input(input: InputEvent) -> void:
	if not is_inside_tree() or not input is InputEventKey or not input.pressed or input.echo: return
	var viewport := get_viewport()
	var focus := viewport.gui_get_focus_owner()
	var command: bool = input.is_command_or_control_pressed()
	if command and input.keycode == KEY_S:
		viewport.set_input_as_handled()
		_save()
		return
	if focus is LineEdit or focus is TextEdit: return
	if _save_dialog.visible or _leave_dialog.visible or _replace_dialog.visible: return
	if input.keycode not in [KEY_SPACE, KEY_LEFT, KEY_RIGHT, KEY_ESCAPE, KEY_DELETE] and not (command and input.keycode in [KEY_Z, KEY_Y, KEY_D]): return
	viewport.set_input_as_handled()
	match input.keycode:
		KEY_SPACE: _toggle_play()
		KEY_LEFT: _step(-1)
		KEY_RIGHT: _step(1)
		KEY_Z when command:
			if input.shift_pressed: _redo_step()
			else: _undo_step()
		KEY_Y when command: _redo_step()
		KEY_D when command: duplicate_event()
		KEY_DELETE: delete_event()
		KEY_ESCAPE: _leave()
		_: return
