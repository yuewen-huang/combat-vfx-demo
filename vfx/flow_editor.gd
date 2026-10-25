extends Control
## The public editing entrance: an editable DAG of moves, plus a shared full-show preview.
const Model = preload("res://vfx/flow_document.gd")
const Catalog = preload("res://vfx/editor_catalog.gd")
const Stage = preload("res://vfx/flow_stage.gd")
const Loading = preload("res://vfx/screen_loading.gd")
static var sessions: Dictionary = {}
var document: Dictionary = {}
var look := {"title":"新多技能演出","language":"zh","renderer":"flow","flow_stage":"melee"}
var combo_path := ""
var dirty := false
var selected := ""
var graph: GraphEdit
var stage: Node2D
var _viewport: SubViewport
var _host: Node2D
var _preview: TextureRect
var _title: LineEdit
var _status: Label
var _selection: VBoxContainer
var _node_editor: Control
var _workspace: HSplitContainer
var _new_dialog: ConfirmationDialog
var _category: OptionButton
var _templates: OptionButton
var _save_dialog: ConfirmationDialog
var _save_name: LineEdit
var _import_dialog: ConfirmationDialog
var _import_list: ItemList
var _import_paths: Array[String] = []
var _leave_dialog: ConfirmationDialog
var _leave_after_save := false
var _compiled: Dictionary = {}
var _slider: HSlider
var _time: Label
var _playing := false
var _updating := false
var _history: Array[String] = []
var _redo: Array[String] = []
var _last_edit := ""

func _ready() -> void:
	RenderCaps.detect()
	var bg := ColorRect.new()
	bg.color = Color("141c26")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 12
	column.offset_right = -12
	column.offset_top = 10
	column.offset_bottom = -8
	add_child(column)
	var bar := HFlowContainer.new()
	bar.add_child(_label("多技能 · 流程编排",22))
	_title = LineEdit.new()
	_title.custom_minimum_size.x = 230
	_title.text_changed.connect(func(value: String) -> void:
		_remember("title")
		document.name = value
		look.title = value
		_mark(false))
	bar.add_child(_title)
	bar.add_child(_button("＋ 招式",func() -> void: _new_dialog.popup_centered()))
	bar.add_child(_button("导入招式",_show_import))
	bar.add_child(_button("保存",save_document))
	bar.add_child(_button("另存为",func() -> void: _save_dialog.popup_centered()))
	bar.add_child(_button("撤销",undo))
	bar.add_child(_button("重做",redo))
	bar.add_child(_button("全屏 F11",func() -> void: get_node("/root/AppWindow").toggle_fullscreen()))
	bar.add_child(_button("作品库",_leave))
	column.add_child(bar)
	if RenderCaps.fallback:
		column.add_child(_label("兜底模式：%s（未检测到显卡，特效已简化）" % RenderCaps.reason,13))
	column.add_child(_label("连线决定衔接；同一前招可连出并行分支，多条前招汇入时等待全部到齐。双击节点或点击「编辑单招」。",13))
	_workspace = HSplitContainer.new()
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_workspace)
	graph = GraphEdit.new()
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size = Vector2(480,380)
	graph.minimap_enabled = true
	graph.connection_request.connect(connect_moves)
	graph.disconnection_request.connect(disconnect_moves)
	graph.node_selected.connect(func(node: Node) -> void: select_move(String(node.name)))
	graph.delete_nodes_request.connect(func(ids: Array) -> void:
		for id: StringName in ids: remove_move(String(id)))
	_workspace.add_child(graph)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 390
	_workspace.add_child(right)
	right.add_child(_label("整段演出预览",18))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280,720)
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_host = preload("res://vfx/quake_editor.gd").Host.new()
	_viewport.add_child(_host)
	_preview = TextureRect.new()
	_preview.texture = _viewport.get_texture()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.custom_minimum_size = Vector2(390,220)
	right.add_child(_preview)
	var playback := HBoxContainer.new()
	playback.add_child(_button("重播",replay))
	playback.add_child(_button("播放 / 暂停",func() -> void: _playing = not _playing))
	_time = _label("0.00s",14)
	playback.add_child(_time)
	right.add_child(playback)
	_slider = HSlider.new()
	_slider.step = .01
	_slider.value_changed.connect(func(value: float) -> void:
		if not _updating: seek(value))
	right.add_child(_slider)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_selection = VBoxContainer.new()
	_selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_selection)
	_status = _label("",13)
	column.add_child(_status)
	_dialogs()
	var wanted := String(get_tree().root.get_meta("flow_open",""))
	get_tree().root.remove_meta("flow_open")
	if sessions.has(wanted):
		var saved: Dictionary = sessions[wanted]
		document = saved.document.duplicate(true)
		look = saved.look.duplicate(true)
		combo_path = wanted
		dirty = bool(saved.dirty)
	elif not wanted.is_empty(): load_document(wanted)
	else: document = Model.empty()
	_title.text = String(document.get("name","多技能演出"))
	redraw_graph()

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button

func _label(text: String, size := 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 210 if size>=20 else 140
	return label

func _dialogs() -> void:
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "添加招式节点"
	_new_dialog.ok_button_text = "添加到流程图"
	var box := VBoxContainer.new()
	_category = OptionButton.new()
	for name: String in Catalog.NAMES: _category.add_item(name)
	_category.item_selected.connect(func(_i: int) -> void: _fill_templates())
	box.add_child(_category)
	_templates = OptionButton.new()
	box.add_child(_templates)
	_new_dialog.add_child(box)
	_new_dialog.confirmed.connect(func() -> void: add_template(Catalog.KEYS[_category.selected],_templates.selected))
	add_child(_new_dialog)
	_fill_templates()
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.title = "保存多技能演出"
	_save_dialog.dialog_hide_on_ok = false
	_save_dialog.ok_button_text = "保存"
	_save_name = LineEdit.new()
	_save_name.placeholder_text = "文件标识，例如 my_skill_flow"
	_save_dialog.add_child(_save_name)
	_save_dialog.confirmed.connect(_save_as)
	add_child(_save_dialog)
	_import_dialog = ConfirmationDialog.new()
	_import_dialog.title = "从作品库导入一招"
	_import_list = ItemList.new()
	_import_list.custom_minimum_size = Vector2(500,300)
	_import_dialog.add_child(_import_list)
	_import_dialog.confirmed.connect(func() -> void:
		var picked := _import_list.get_selected_items()
		if picked.size()>0: import_move(_import_paths[picked[0]]))
	add_child(_import_dialog)
	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.title = "流程图尚未保存"
	_leave_dialog.dialog_text = "保存演出后返回作品库，或保留草稿稍后继续。"
	_leave_dialog.ok_button_text = "保存并返回"
	_leave_dialog.add_button("保留草稿并返回",false,"draft")
	_leave_dialog.confirmed.connect(func() -> void:
		_leave_after_save = true
		save_document())
	_leave_dialog.custom_action.connect(func(action: StringName) -> void:
		if action==&"draft": _return_gallery())
	add_child(_leave_dialog)

func _fill_templates() -> void:
	_templates.clear()
	for preset: Array in Catalog.presets(Catalog.KEYS[_category.selected]): _templates.add_item(preset[0])

func _node(id: String) -> Dictionary:
	for node: Dictionary in document.get("nodes",[]):
		if String(node.id)==id: return node
	return {}

func _remember(key := "") -> void:
	if key.is_empty() or key!=_last_edit:
		_history.append(JSON.stringify(document))
		if _history.size()>100: _history.pop_front()
		_redo.clear()
	_last_edit = key

func _mark(rebuild := true) -> void:
	dirty = true
	if rebuild: _compile_preview()

func add_template(category: String, which: int) -> String:
	var preset := Catalog.create(category,which)
	if category in ["blade","magic"]:
		# Reuse the single-move editor's contact alignment and heavy-finisher defaults.
		var composer: Control = preload("res://vfx/studio_editor.gd").new()
		composer.category = category
		composer.data = preset.data
		composer.style = preset.style
		composer.index = 0
		composer._sync_linked_hits(true)
		composer.free()
	return add_move(String(preset.style.title),category,preset.data,preset.style)

func add_move(title: String, category: String, data: Dictionary, style: Dictionary) -> String:
	_remember()
	var i := 1
	while not _node("move_%d" % i).is_empty(): i+=1
	var id := "move_%d" % i
	# New moves start with separate actor names; intentionally shared names remain editable.
	var local := data.duplicate(true)
	var names := {}
	for e: Dictionary in local.get("events",[]):
		if e.get("do") in ["swarm"] and e.has("id"): names[String(e.id)] = String(e.id)+"_"+str(i)
	for e: Dictionary in local.get("events",[]):
		for field: String in ["id","from","swarm"]:
			if e.get(field) is String and names.has(String(e[field])): e[field] = names[String(e[field])]
	document.nodes.append({"id":id,"title":title,"category":category,"data":local,"style":style.duplicate(true),"position":[80+((i-1)%3)*310,80+((i-1)/3)*230],"delay":0.0,"join":"after","span":-1.0})
	selected = id
	_mark(false)
	redraw_graph.call_deferred()
	return id

func connect_moves(from: StringName, _from_port: int, to: StringName, _to_port: int) -> void:
	for edge: Dictionary in document.edges:
		if String(edge.from)==String(from) and String(edge.to)==String(to):return
	var edge := {"from":String(from),"to":String(to)}
	var trial := document.duplicate(true)
	trial.edges.append(edge)
	var result := Model.schedule(trial)
	if not String(result.get("error","")).is_empty():
		_status.text = String(result.error)
		return
	_remember()
	document.edges.append(edge)
	_mark(false)
	redraw_graph.call_deferred()

func disconnect_moves(from: StringName, _from_port: int, to: StringName, _to_port: int) -> void:
	_remember()
	document.edges = document.edges.filter(func(e: Dictionary)->bool:return not (String(e.from)==String(from) and String(e.to)==String(to)))
	_mark(false)
	redraw_graph.call_deferred()

func remove_move(id: String) -> void:
	_remember()
	document.nodes = document.nodes.filter(func(n: Dictionary)->bool:return String(n.id)!=id)
	document.edges = document.edges.filter(func(e: Dictionary)->bool:return String(e.from)!=id and String(e.to)!=id)
	selected = ""
	_mark(false)
	redraw_graph.call_deferred()

func redraw_graph() -> void:
	_title.set_block_signals(true)
	_title.text = String(document.get("name","多技能演出"))
	_title.set_block_signals(false)
	graph.clear_connections()
	for child in graph.get_children():
		if child is GraphNode: child.free()
	_compile_preview()
	for move: Dictionary in document.get("nodes",[]):
		var id := String(move.id)
		var node := GraphNode.new()
		node.name = id
		node.title = String(move.title)
		node.position_offset = Vector2(float(move.position[0]),float(move.position[1]))
		node.custom_minimum_size = Vector2(260,155)
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color("233242")
		panel.border_color = Color("4b6980")
		panel.set_border_width_all(1)
		panel.set_corner_radius_all(6)
		node.add_theme_stylebox_override("panel",panel)
		var picked := panel.duplicate()
		picked.border_color = Color("91cfea")
		picked.set_border_width_all(2)
		node.add_theme_stylebox_override("panel_selected",picked)
		node.add_child(_label(Catalog.NAMES[maxi(0,Catalog.KEYS.find(String(move.category)))],15))
		node.add_child(_label("开始 %.2fs  ·  衔接 %.2fs" % [float(_compiled.get("starts",{}).get(id,0)),Model.span(move)],14))
		node.add_child(_button("编辑单招",func() -> void: _request_edit_move.call_deferred(id)))
		node.set_slot(0,true,0,Color("8fd0e8"),true,0,Color("b3dc8c"))
		node.position_offset_changed.connect(func() -> void:
			move.position = [node.position_offset.x,node.position_offset.y]
			dirty = true)
		node.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
				_remember("drag:"+id)
				if event.double_click: _request_edit_move.call_deferred(id))
		graph.add_child(node)
	for edge: Dictionary in document.get("edges",[]): graph.connect_node(StringName(edge.from),0,StringName(edge.to),0)
	select_move(selected)

func select_move(id: String) -> void:
	selected = id
	for child in _selection.get_children(): child.free()
	var move := _node(id)
	if move.is_empty():
		_selection.add_child(_label("点击「＋ 招式」建立节点，拖动端口连接。空白处的招式会从演出开头并行开始。",15))
		return
	_selection.add_child(_label(String(move.title),20))
	_selection.add_child(_button("编辑单招参数",func() -> void: _request_edit_move.call_deferred(id)))
	var title := LineEdit.new()
	title.text = String(move.title)
	title.text_submitted.connect(func(value: String) -> void:
		_remember("name:"+id)
		move.title = value
		move.style.title = value
		move.data.name = value
		_mark(false)
		redraw_graph.call_deferred())
	_selection.add_child(title)
	var join := OptionButton.new()
	join.add_item("接在前招之后")
	join.add_item("与前招同时开始")
	join.select(1 if move.get("join")=="with" else 0)
	join.item_selected.connect(func(i: int) -> void:
		_remember("join:"+id)
		move.join = "with" if i==1 else "after"
		_mark(false)
		redraw_graph.call_deferred())
	_selection.add_child(join)
	_number("开始偏移 / s",float(move.get("delay",0)),0,120,func(value: float) -> void:
		_remember("delay:"+id)
		move.delay = value
		_mark())
	var auto := CheckBox.new()
	auto.text = "自动计算衔接时长"
	auto.button_pressed = float(move.get("span",-1))<0
	auto.toggled.connect(func(on: bool) -> void:
		_remember("span:"+id)
		move.span = -1.0 if on else Model.span(move)
		_mark(false)
		redraw_graph.call_deferred())
	_selection.add_child(auto)
	if not auto.button_pressed:
		_number("衔接间隔 / s",Model.span(move),0,120,func(value: float) -> void:
			_remember("span:"+id)
			move.span = value
			_mark())
	_selection.add_child(_label("衔接间隔决定下一招何时启动；本招的残留效果可继续存在。",13))
	_selection.add_child(_button("删除此招",func() -> void: remove_move(id)))

func _number(label: String, value: float, low: float, high: float, action: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label(label,14))
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = .01
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(action)
	row.add_child(spin)
	_selection.add_child(row)

func _request_edit_move(id: String) -> void:
	Loading.run_action(self,edit_move.bind(id),"正在加载单招与前置状态")

func edit_move(id: String) -> void:
	if _node_editor!=null: return
	var move := _node(id)
	if move.is_empty(): return
	selected = id
	_playing = false
	_workspace.hide()
	_node_editor = load("res://node_editor.tscn").instantiate()
	_node_editor.node_mode = true
	_node_editor.node_document = move.duplicate(true)
	_node_editor.preview_context = _compiled.get("events",[]).duplicate(true)
	_node_editor.preview_start = float(_compiled.get("starts",{}).get(id,0))
	_node_editor.node_committed.connect(func(data: Dictionary, style: Dictionary) -> void:
		_remember("edit:"+id)
		move.data = data.duplicate(true)
		move.style = style.duplicate(true)
		move.title = String(style.get("title",move.title))
		_mark(false)
		_finish_edit.call_deferred())
	_node_editor.node_closed.connect(func() -> void: _finish_edit.call_deferred())
	add_child(_node_editor)
	_node_editor.set_anchors_preset(Control.PRESET_FULL_RECT)

func _finish_edit() -> void:
	if _node_editor!=null:
		_node_editor.free()
		_node_editor = null
	_workspace.show()
	redraw_graph()

func _compile_preview() -> void:
	_compiled = Model.compile(document)
	if not String(_compiled.get("error","")).is_empty():
		_status.text = String(_compiled.error)
		return
	_rebuild_stage()
	for move: Dictionary in document.get("nodes",[]):
		var node := graph.get_node_or_null(String(move.id))
		if node is GraphNode and node.get_child_count()>1 and node.get_child(1) is Label:
			node.get_child(1).text = "开始 %.2fs  ·  衔接 %.2fs" % [float(_compiled.get("starts",{}).get(String(move.id),0)),Model.span(move)]
	_status.text = "%s · %d 招 · 连线支持顺序 / 并行" % ["未保存" if dirty else "已保存",document.get("nodes",[]).size()]

func _rebuild_stage() -> void:
	if stage!=null: stage.free()
	ComboStyle.load_data(look)
	stage = Stage.new()
	_host.add_child(stage)
	stage.set_process(false)
	stage.set_process_unhandled_input(false)
	stage.help.hide()
	stage.quality_label.hide()
	stage.TIMELINE = ComboStage.parse_events(_compiled.get("events",[]))
	stage.reset()
	stage.play()
	_slider.max_value = maxf(1.0,stage.clock_end()+1.1)

func replay() -> void:
	_rebuild_stage()
	_playing = true

func seek(value: float) -> void:
	_playing = false
	_rebuild_stage()
	var steps := 0
	while stage.clock<value-.00001 and steps<36000:
		stage.playing = true
		stage.advance(minf(1.0/60.0,value-stage.clock))
		for holder: Node in stage.effect_holders():
			for child in holder.get_children():
				if child.is_queued_for_deletion():child.free()
		steps+=1

func _process(delta: float) -> void:
	if stage==null or _node_editor!=null:return
	if _playing:
		stage.advance(minf(delta,.1))
		if not stage.playing and stage.is_settled(): _playing = false
	_updating = true
	_slider.value = stage.clock
	_updating = false
	_time.text = "%.2fs" % stage.clock

func _show_import() -> void:
	_import_list.clear()
	_import_paths.clear()
	for path: String in preload("res://vfx/gallery.gd").find_combos():
		var folder := path.get_base_dir()
		var style := _read(folder.path_join("style.json"))
		_import_paths.append(folder.path_join("combo.json"))
		_import_list.add_item(String(style.get("title",folder.get_file())))
	_import_dialog.popup_centered()

func import_move(path: String) -> String:
	var data := _read(path)
	var style := _read(path.get_base_dir().path_join("style.json"))
	return add_move(String(style.get("title",data.get("name","导入招式"))),Catalog.document_category(data,style),data,style)

func load_document(path: String) -> void:
	var data := _read(path)
	if not data.get("events") is Array:
		document = Model.empty()
		_status.text = "无法打开作品，原文件保留"
		return
	look = _read(path.get_base_dir().path_join("style.json"))
	document = Model.from_combo(data,look)
	if look.get("renderer")!="flow": look["flow_stage"] = "magic" if look.get("renderer")=="magic" else "melee"
	look.renderer = "flow"
	combo_path = path
	dirty = false

func save_document() -> void:
	if document.get("nodes",[]).is_empty():
		_status.text = "请先添加招式节点，再保存演出"
		return
	if combo_path.is_empty():
		_save_dialog.popup_centered()
		return
	var result := Model.compile(document)
	if not String(result.get("error","")).is_empty():
		_status.text = String(result.error)
		return
	result.erase("starts")
	result.erase("error")
	var folder := combo_path.get_base_dir()
	look.title = String(document.name)
	look.renderer = "flow"
	for name: String in ["combo.json","style.json",folder.get_file()+".tscn"]:
		var file := folder.path_join(name)
		if FileAccess.file_exists(file):
			var error := DirAccess.copy_absolute(file,file+".bak")
			if error!=OK:
				_status.text = "备份失败，未保存："+error_string(error)
				return
	if not _write(folder.path_join("combo.json"),JSON.stringify(result,"  ")) or not _write(folder.path_join("style.json"),JSON.stringify(look,"  ")):return
	var scene := "[gd_scene format=3]\n\n[ext_resource type=\"Script\" path=\"res://vfx/combo_player.gd\" id=\"1\"]\n\n[node name=\"ComboPlayer\" type=\"Node2D\"]\nscript = ExtResource(\"1\")\ncombo_file = \"%s\"\nstyle_file = \"%s\"\n" % [combo_path,folder.path_join("style.json")]
	if not _write(folder.path_join(folder.get_file()+".tscn"),scene):return
	dirty = false
	_status.text = "已保存「%s」" % document.name
	if _leave_after_save:_return_gallery()

func _save_as() -> void:
	if document.get("nodes",[]).is_empty():
		_save_dialog.dialog_text = "请先添加招式节点"
		return
	var name := _save_name.text.strip_edges()
	if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(name)==null:
		_save_dialog.dialog_text = "文件标识请用英文小写开头，例如 my_skill_flow"
		return
	var folder := "res://combos/"+name
	if DirAccess.dir_exists_absolute(folder):
		_save_dialog.dialog_text = "该标识已存在，请换一个，避免覆盖其他作品"
		return
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return
	combo_path = folder.path_join("combo.json")
	save_document()
	if not dirty:_save_dialog.hide()

func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:
		_status.text = "写入失败，草稿仍保留"
		return false
	file.store_string(text)
	file.close()
	var error := DirAccess.rename_absolute(path+".tmp",path)
	if error!=OK: _status.text = "保存失败："+error_string(error)
	return error==OK

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func undo() -> void:
	if _history.is_empty():return
	_redo.append(JSON.stringify(document))
	document = JSON.parse_string(_history.pop_back())
	_last_edit = ""
	_mark(false)
	redraw_graph.call_deferred()

func redo() -> void:
	if _redo.is_empty():return
	_history.append(JSON.stringify(document))
	document = JSON.parse_string(_redo.pop_back())
	_last_edit = ""
	_mark(false)
	redraw_graph.call_deferred()

func _leave() -> void:
	if dirty:_leave_dialog.popup_centered()
	else:_return_gallery()

func _return_gallery() -> void:
	Loading.open_scene(self,"res://main.tscn","正在返回作品库")

func _exit_tree() -> void:
	if not document.is_empty(): sessions[combo_path] = {"document":document.duplicate(true),"look":look.duplicate(true),"dirty":dirty}

func _unhandled_input(event: InputEvent) -> void:
	if _node_editor!=null or not event is InputEventKey or not event.pressed or event.echo:return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:return
	if event.is_command_or_control_pressed() and event.keycode==KEY_S:
		get_viewport().set_input_as_handled()
		save_document()
	elif event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_leave()
