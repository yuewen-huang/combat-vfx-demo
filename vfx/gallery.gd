extends Control
## Lists every combo scene in res://combos/ (one folder each) as cards, a page at a time,
## and opens the one you pick. Esc in a combo comes back here, to the same page.
## Tabs across the top show one renderer's combos; ← / → (or Page Up / Down, or the
## mouse wheel) turn the page; the 删除 button on a card (or Delete on the focused card)
## moves that combo's folder to the system recycle bin, after asking.

const COMBOS := "res://combos"
const Loading = preload("res://vfx/screen_loading.gd")
const COLUMNS := 3
const ROWS := 3
const CARD := Vector2(384, 136)
## Renderer (style.json "renderer") → name and accent.
const RENDERERS := {"": ["月牙", Color("8fb7ff")], "ribbon": ["轨迹刀光", Color("6fd6e8")], "claw": ["爪痕", Color("ff8a6a")],
	"ink": ["水墨", Color("c9c2b0")], "magic": ["魔法", Color("e8c060")], "quake": ["地震", Color("dca777")]}

## The page and tab to come back to.
static var _page := 0
static var _tab := "all"

var _combos: Array[Dictionary] = []
var _grid: GridContainer
var _tabs: HBoxContainer
var _page_label: Label
var _previous: Button
var _next: Button
var _confirm: ConfirmationDialog
var _doomed := ""

func _ready() -> void:
	_tab = "all"
	RenderCaps.detect()
	var background := ColorRect.new()
	background.color = Color("1a1f26")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var column := VBoxContainer.new()
	column.position = Vector2(48, 28)
	column.size = Vector2(1184, 664)
	column.add_theme_constant_override("separation", 9 if RenderCaps.fallback else 14)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var heading := Label.new()
	heading.text = "Combat VFX · 演出作品库"
	heading.add_theme_font_size_override("font_size", 30)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(_button("多技能",18))
	(header.get_child(header.get_child_count()-1) as Button).pressed.connect(func() -> void: Loading.open_scene(self,"res://flow_editor.tscn","正在打开多技能流程图"))
	var fullscreen := _button("全屏 F11",18)
	fullscreen.pressed.connect(func() -> void: get_node("/root/AppWindow").toggle_fullscreen())
	header.add_child(fullscreen)
	if RenderCaps.fallback:
		var note := Label.new()
		note.text = "兜底模式：%s（未检测到显卡，特效已简化）" % RenderCaps.reason
		note.add_theme_font_size_override("font_size", 14)
		column.add_child(note)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	column.add_child(_tabs)
	_tabs.hide()
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	_grid.custom_minimum_size = Vector2(0, CARD.y * ROWS + 16 * (ROWS - 1))
	column.add_child(_grid)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 24)
	column.add_child(footer)
	_previous = _button("← 上一页", 20)
	_previous.pressed.connect(func() -> void: _turn(-1))
	footer.add_child(_previous)
	_page_label = Label.new()
	_page_label.add_theme_font_size_override("font_size", 20)
	footer.add_child(_page_label)
	_next = _button("下一页 →", 20)
	_next.pressed.connect(func() -> void: _turn(1))
	footer.add_child(_next)
	var hint := Label.new()
	hint.text = "Enter 打开　←/→ 翻页　Delete 删除　Esc（在连招里）回到这里"
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "删除连招"
	_confirm.ok_button_text = "移到回收站"
	_confirm.cancel_button_text = "取消"
	_confirm.confirmed.connect(_delete)
	add_child(_confirm)
	_load()

func _button(text: String, px: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", px)
	button.custom_minimum_size = Vector2(0, 40)
	return button

## Reads every combo's name and renderer.
func _load() -> void:
	_combos.clear()
	for path in find_combos():
		var folder := path.get_base_dir()
		var style := _json(folder.path_join("style.json"))
		var combo := _json(folder.path_join("combo.json"))
		var name := _name(String(style.get("title", "")), String(combo.get("name", "")))
		if name.is_empty(): name = folder.get_file().capitalize()
		_combos.append({"path": path, "folder": folder, "name": name, "renderer": String(style.get("renderer", ""))})
	_build_tabs()
	_show()

## "Title · subtitle": the style's title, its subtitle dropped when it only names the
## renderer ("魔法绘制器") — the combo's own subtitle takes its place when it shares the title.
static func _name(title: String, combo_name: String) -> String:
	var parts := Array(title.split("·")).map(func(p: String) -> String: return p.strip_edges())
	if parts.size() > 1 and String(parts[1]).ends_with("绘制器"): parts.resize(1)
	var own := Array(combo_name.split("·")).map(func(p: String) -> String: return p.strip_edges())
	if parts.size() == 1 and own.size() > 1 and own[0] == parts[0] and not String(own[1]).ends_with("绘制器"): parts.append(own[1])
	if String(parts[0]).is_empty(): return combo_name
	return " · ".join(PackedStringArray(parts))

static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _build_tabs() -> void:
	for child in _tabs.get_children(): child.free()
	var group := ButtonGroup.new()
	var counts := {}
	for c in _combos: counts[c.renderer] = int(counts.get(c.renderer, 0)) + 1
	if _tab != "all" and not counts.has(_tab): _tab = "all"
	var keys: Array = ["all"]
	for key: String in RENDERERS: if counts.has(key): keys.append(key)
	for key: String in keys:
		var tab := _button(("全部" if key == "all" else String(RENDERERS[key][0])) + "  %d" % (_combos.size() if key == "all" else int(counts[key])), 18)
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = key == _tab
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(func() -> void:
			_tab = key
			_page = 0
			_show())
		_tabs.add_child(tab)

func _shown() -> Array[Dictionary]:
	return _combos.filter(func(c: Dictionary) -> bool: return _tab == "all" or c.renderer == _tab)

func _pages() -> int: return maxi(1, ceili(_shown().size() / float(COLUMNS * ROWS)))

func _show(focus_last := false) -> void:
	for child in _grid.get_children(): child.free()
	var shown := _shown()
	_page = clampi(_page, 0, _pages() - 1)
	var first := _page * COLUMNS * ROWS
	for i in range(first, mini(first + COLUMNS * ROWS, shown.size())): _grid.add_child(_card(shown[i]))
	_page_label.text = "第 %d / %d 页" % [_page + 1, _pages()]
	_previous.disabled = _page == 0
	_next.disabled = _page >= _pages() - 1
	if _grid.get_child_count() > 0:
		(_grid.get_child(_grid.get_child_count() - 1 if focus_last else 0) as Control).grab_focus()

func _card(c: Dictionary) -> Button:
	var info: Array = RENDERERS.get(c.renderer, RENDERERS[""])
	var accent: Color = info[1]
	var card := Button.new()
	card.custom_minimum_size = CARD
	card.tooltip_text = c.path
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("262d36") if state == "normal" else Color("303946")
		style.border_color = accent if state in ["hover", "focus"] else Color(accent, 0.25)
		style.set_border_width_all(2)
		style.border_width_left = 6
		style.set_corner_radius_all(10)
		card.add_theme_stylebox_override(state, style)
	card.pressed.connect(func() -> void: Loading.open_scene(self, c.path, "正在打开「%s」" % c.name))
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
			_ask(c)
			card.accept_event())
	var parts := String(c.name).split(" · ", true, 1)
	var title := _text(parts[0], 26, Color.WHITE)
	title.position = Vector2(22, 16)
	title.size = Vector2(CARD.x - 44, 36)
	title.clip_text = true
	card.add_child(title)
	var detail := _text((parts[1] + "　" if parts.size() > 1 else "") + String(c.folder).get_file(), 16, Color(1, 1, 1, 0.55))
	detail.position = Vector2(22, 56)
	detail.size = Vector2(CARD.x - 44, 24)
	detail.clip_text = true
	card.add_child(detail)
	var tag := _text(String(info[0]), 16, accent)
	tag.position = Vector2(22, CARD.y - 38)
	card.add_child(tag)
	var edit := Button.new()
	edit.text = "编排"
	edit.position = Vector2(CARD.x - 158, CARD.y - 42)
	edit.size = Vector2(68, 30)
	edit.pressed.connect(func() -> void:
		Loading.open_scene(self, "res://flow_editor.tscn", "正在编排「%s」" % c.name, {"flow_open": String(c.path).get_base_dir().path_join("combo.json")}))
	card.add_child(edit)
	var delete := Button.new()
	delete.text = "删除"
	delete.flat = true
	delete.focus_mode = Control.FOCUS_NONE
	delete.add_theme_font_size_override("font_size", 15)
	delete.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	delete.add_theme_color_override("font_hover_color", Color("ff7a7a"))
	delete.position = Vector2(CARD.x - 66, CARD.y - 42)
	delete.size = Vector2(54, 32)
	delete.pressed.connect(_ask.bind(c))
	card.add_child(delete)
	return card

func _text(text: String, px: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _ask(c: Dictionary) -> void:
	_doomed = c.folder
	_confirm.dialog_text = "把「%s」整个文件夹移到回收站？\n%s\n（可以从回收站还原）" % [c.name, ProjectSettings.globalize_path(c.folder)]
	_confirm.popup_centered()

func _delete() -> void:
	if _doomed.is_empty(): return
	var error := OS.move_to_trash(ProjectSettings.globalize_path(_doomed))
	if error != OK: push_error("Could not move %s to the recycle bin: %s" % [_doomed, error_string(error)])
	_doomed = ""
	_load()

func _turn(by: int) -> void:
	var to := clampi(_page + by, 0, _pages() - 1)
	if to == _page: return
	_page = to
	_show(by < 0)

func _unhandled_input(event: InputEvent) -> void:
	if _confirm.visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_PAGEDOWN: _turn(1)
			KEY_PAGEUP: _turn(-1)
			_: return
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _turn(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: _turn(-1)

func _gui_input_arrows(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT, KEY_RIGHT]

## ← / → past the edge of the page turn it.
func _input(event: InputEvent) -> void:
	if _confirm.visible or not _gui_input_arrows(event): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or focused.get_parent() != _grid: return
	var index := focused.get_index()
	if event.keycode == KEY_RIGHT and (index % COLUMNS == COLUMNS - 1 or index == _grid.get_child_count() - 1) and _page < _pages() - 1:
		_turn(1)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_LEFT and index % COLUMNS == 0 and _page > 0:
		_turn(-1)
		get_viewport().set_input_as_handled()

## Every res://combos/<name>/<name>.tscn, sorted.
static func find_combos() -> PackedStringArray:
	var found := PackedStringArray()
	for folder in DirAccess.get_directories_at(COMBOS):
		var scene := COMBOS.path_join(folder).path_join(folder + ".tscn")
		if ResourceLoader.exists(scene): found.append(scene)
	found.sort()
	return found
