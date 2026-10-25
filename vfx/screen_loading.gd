extends CanvasLayer
## Shared, root-owned transition: paint first, load in the background, then initialize.
## The originating scene survives until loading succeeds, and input is blocked meanwhile.
signal completed(success: bool)
static var _active: WeakRef
var busy := false
var phase := "idle"
var last_duration_ms := 0
var _source: WeakRef
var _source_mode := Node.PROCESS_MODE_INHERIT
var _path := ""
var _context: Dictionary = {}
var _action: Callable
var _started := 0
var _title: Label
var _detail: Label
var _elapsed: Label
var _progress: ProgressBar
var _back: Button

class Spinner extends Control:
	var angle := 0.0
	func _process(delta: float) -> void:
		angle += delta * 4.5
		queue_redraw()
	func _draw() -> void:
		var center := size * 0.5
		draw_arc(center, 22, 0, TAU, 48, Color("283a4a"), 4, true)
		draw_arc(center, 22, angle, angle + TAU * 0.7, 40, Color("ffd58b"), 4, true)

static func for_node(source: Node) -> CanvasLayer:
	if source == null or not source.is_inside_tree(): return null
	var current: Node = _active.get_ref() if _active != null else null
	if is_instance_valid(current) and current.get_tree() == source.get_tree(): return current
	var script: GDScript = load("res://vfx/screen_loading.gd")
	var overlay: CanvasLayer = script.new()
	overlay.name = "ScreenLoading"
	_active = weakref(overlay)
	source.get_tree().root.add_child(overlay)
	return overlay

static func open_scene(source: Node, path: String, title: String, context: Dictionary = {}) -> bool:
	var overlay := for_node(source)
	if overlay == null or overlay.busy: return false
	overlay._path = path
	overlay._context = context.duplicate(true)
	overlay._action = Callable()
	overlay._begin(source, title)
	overlay._load_scene.call_deferred()
	return true

static func run_action(source: Node, action: Callable, title: String) -> bool:
	var overlay := for_node(source)
	if overlay == null or overlay.busy or not action.is_valid(): return false
	overlay._path = ""
	overlay._context = {}
	overlay._action = action
	overlay._begin(source, title)
	overlay._run_action.call_deferred()
	return true

func _ready() -> void:
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color("111a25")
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 460
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c2938")
	style.border_color = Color("3c536a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var spinner := Spinner.new()
	spinner.custom_minimum_size = Vector2(64, 64)
	column.add_child(spinner)
	var heading := Label.new()
	heading.text = "LOADING"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 13)
	heading.modulate = Color("8fabc3")
	column.add_child(heading)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	_title.modulate = Color("ffe0a3")
	column.add_child(_title)
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 15)
	column.add_child(_detail)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 6
	_progress.show_percentage = false
	column.add_child(_progress)
	_elapsed = Label.new()
	_elapsed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elapsed.add_theme_font_size_override("font_size", 12)
	_elapsed.modulate = Color("8fabc3")
	column.add_child(_elapsed)
	_back = Button.new()
	_back.text = "返回原画面"
	_back.pressed.connect(func() -> void: visible = false)
	column.add_child(_back)
	visible = false

func _begin(source: Node, title: String) -> void:
	_source = weakref(source)
	_source_mode = source.process_mode
	# A popup can be the viewport currently dispatching this click. Hide it, never detach it.
	for window in source.find_children("*", "Window", true, false): window.hide()
	source.process_mode = Node.PROCESS_MODE_DISABLED
	_started = Time.get_ticks_msec()
	busy = true
	phase = "preparing"
	visible = true
	_title.text = title
	_detail.text = "正在准备加载…"
	_elapsed.text = ""
	_progress.value = 0
	_progress.visible = true
	_back.hide()

func _paint() -> void:
	# One frame can resume before its draw; two frames ensure the loading UI has been shown.
	await get_tree().process_frame
	await get_tree().process_frame

func _load_scene() -> void:
	await _paint()
	if not _source_alive():
		_finish(false)
		return
	phase = "resources"
	_detail.text = "正在读取场景资源…"
	if not ResourceLoader.exists(_path, "PackedScene"):
		_fail("找不到目标画面，当前作品仍保留。")
		return
	# Script preloads include Compatibility shader objects. Initialize that graph on the
	# main thread, under the painted loading screen, before handing scene I/O to a worker.
	_detail.text = "正在准备特效脚本…"
	_progress.hide()
	await _paint()
	for entry: String in ResourceLoader.get_dependencies(_path):
		var dependency := entry.get_slice("::", entry.get_slice_count("::") - 1)
		if dependency.ends_with(".gd") and not ResourceLoader.has_cached(dependency):
			if ResourceLoader.load(dependency, "GDScript") == null:
				_fail("特效脚本加载失败，当前作品仍保留。")
				return
			await get_tree().process_frame
	_progress.show()
	var error := ResourceLoader.load_threaded_request(_path, "PackedScene")
	if error != OK:
		_fail("无法读取目标画面，请稍后重试。")
		return
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(_path, progress)
		if not progress.is_empty():
			_progress.value = float(progress[0]) * 100
			_detail.text = "正在读取场景资源 · %d%%" % roundi(_progress.value)
		if status == ResourceLoader.THREAD_LOAD_LOADED: break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_fail("场景资源加载失败，当前作品仍保留。")
			return
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(_path) as PackedScene
	if packed == null or not _source_alive():
		_fail("无法打开目标画面，当前作品仍保留。")
		return
	phase = "initializing"
	_progress.hide()
	_detail.text = "正在初始化界面与预览…"
	await _paint()
	if not _source_alive():
		_finish(false)
		return
	var tree := get_tree()
	for key: String in _context: tree.root.set_meta(key, _context[key])
	var next := packed.instantiate()
	var mode := next.process_mode
	next.process_mode = Node.PROCESS_MODE_DISABLED
	error = tree.change_scene_to_node(next)
	if error != OK:
		next.free()
		_fail("切换画面失败，当前作品仍保留。")
		return
	await tree.scene_changed
	phase = "preview"
	_detail.text = "正在准备第一帧…"
	# Leave time for deferred ground-shader warmup and first-frame layout/rendering.
	for i in 4: await tree.process_frame
	if is_instance_valid(next) and next.is_inside_tree(): next.process_mode = mode
	_finish(true)

func _run_action() -> void:
	await _paint()
	if not _source_alive() or not _action.is_valid():
		_finish(false)
		return
	phase = "initializing"
	_progress.hide()
	_detail.text = "正在准备编辑内容与预览…"
	await _paint()
	_action.call()
	for i in 4: await get_tree().process_frame
	_finish(true)

func _source_alive() -> bool:
	var source: Node = _source.get_ref() if _source != null else null
	return is_instance_valid(source) and source.is_inside_tree()

func _restore_source() -> void:
	if _source_alive(): (_source.get_ref() as Node).process_mode = _source_mode

func _finish(success: bool) -> void:
	_restore_source()
	last_duration_ms = Time.get_ticks_msec() - _started
	busy = false
	phase = "ready" if success else "cancelled"
	visible = false
	_action = Callable()
	completed.emit(success)

func _fail(message: String) -> void:
	_restore_source()
	last_duration_ms = Time.get_ticks_msec() - _started
	busy = false
	phase = "failed"
	_title.text = "未能打开画面"
	_detail.text = message
	_progress.hide()
	_back.show()
	_action = Callable()
	completed.emit(false)

func _process(_delta: float) -> void:
	if busy: _elapsed.text = "已用时 %.1f 秒" % ((Time.get_ticks_msec() - _started) / 1000.0)

func _input(_event: InputEvent) -> void:
	if visible and busy: get_viewport().set_input_as_handled()
