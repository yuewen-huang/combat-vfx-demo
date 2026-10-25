extends SceneTree
const Model = preload("res://vfx/flow_document.gd")
const Catalog = preload("res://vfx/editor_catalog.gd")
const Profile = preload("res://vfx/quake/propagation.gd")
const Materials = preload("res://vfx/quake/materials.gd")
const Swarm = preload("res://vfx/swarm_effect.gd")
const Context = preload("res://vfx/preview_context.gd")
const Stage = preload("res://vfx/flow_stage.gd")
var checks := 0
var failures := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func _initialize() -> void: call_deferred("run")

func run() -> void:
	expect(Profile.UNITS.size()==7, "Seven ground materials")
	expect(Materials.COLORWAYS.size()==10, "Ten published colour presets")
	expect(Swarm.PieceMaterials.KEYS==["leaf","feather","sand"], "Three natural materials")
	expect(Swarm.FORMS.size()==7, "Seven independent formations")
	for unit: String in Profile.UNITS:
		for mode: String in Profile.MODES:
			for reverse: bool in [false,true]:
				var spec := Profile.normalized({"unit":unit,"mode":mode,"reverse":reverse})
				expect(Profile.arrival(spec,0)<=Profile.arrival(spec,1), "Arrival is monotone: "+unit+"/"+mode)
				var effect: Node2D = preload("res://vfx/quake_effect.gd").new().configure(spec)
				root.add_child(effect)
				effect.advance(.3)
				expect(effect.bodies.size()>0 and effect.layers.size()>0, "Ground mesh built: "+unit+"/"+mode)
				expect(is_finite(effect.life), "Finite lifetime")
				effect.free()
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	for material: String in Swarm.PieceMaterials.KEYS:
		for form: String in Swarm.FORMS:
			var effect: Node2D = Swarm.new().configure({"material":material,"form":form,"count":500,"seed":73},stage)
			stage.near_fx.add_child(effect)
			effect.advance(.5)
			expect(effect.spec.material==material and effect.capacity>=50, "Natural material configured: "+material+"/"+form)
			expect(int(effect._material.get_shader_parameter("piece_material"))==Swarm.PieceMaterials.KEYS.find(material), "Material shader indices agree")
			effect.free()
	var feather: Node2D = Swarm.new().configure({"material":"feather","count":700,"radius":240},stage)
	stage.near_fx.add_child(feather)
	feather.morph({"form":"vortex"})
	expect(feather.spec.material=="feather" and feather.spec.ramp=="ivory" and feather.spec.count==700 and feather.spec.radius==240, "Sparse transitions retain material, palette and geometry")
	feather.morph({"form":"gone","time":.2})
	feather.advance(.3)
	expect(feather.is_done(), "Explicit dismissal completes")
	feather.free()
	RenderCaps.fallback = true
	var fallback: Node2D = Swarm.new().configure({"material":"sand","count":16000},stage)
	stage.near_fx.add_child(fallback)
	expect(fallback.capacity<=Swarm.FALLBACK_COUNT,"Fallback caps instance count")
	fallback.free()
	RenderCaps.fallback = false
	stage.free()
	# Existing public works survive compilation with their complete original event fields.
	for folder: String in DirAccess.get_directories_at("res://combos"):
		var path := "res://combos/"+folder
		if not FileAccess.file_exists(path+"/combo.json"):continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path+"/combo.json"))
		var look: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path+"/style.json"))
		var compiled := Model.compile(Model.from_combo(data,look))
		expect(compiled.get("error","")=="" and compiled.events.size()==data.events.size(),"Work converts: "+folder)
		for original: Dictionary in data.events:
			var match_found := false
			for event: Dictionary in compiled.events:
				if event.do!=original.do or absf(float(event.t)-float(original.t))>.00001: continue
				var equal := true
				for key: String in original:
					if key!="t" and not key.begins_with("_flow_") and JSON.stringify(event.get(key))!=JSON.stringify(original[key]): equal=false
				if equal: match_found=true
			expect(match_found,"Event retains authored fields: "+folder)
	# Every public template opens in the real node editor and can rebuild a preview.
	for category: String in Catalog.KEYS:
		for i in Catalog.presets(category).size():
			var template := Catalog.create(category,i)
			var editor: Control = load("res://node_editor.tscn").instantiate()
			editor.node_mode = true
			editor.node_document = {"id":"test","category":category,"data":template.data,"style":template.style}
			root.add_child(editor)
			editor.set_process(false)
			await frames()
			expect(editor.stage!=null and editor._category_buttons.is_empty(),"Node editor opens: "+category+"/"+str(i))
			if category=="swarm":
				editor.set_field("at",[600,320],true)
				editor.set_field("at","target",true)
				expect(editor.event().at=="target","Anchor accepts array and string")
			if category=="swarm" and template.data.events[0].form=="gone":
				expect(editor._context_notice.visible and editor.stage.actors.size()>0,"Isolated dismissal is visible")
			editor.free()
			await frames()
	var flow: Control = load("res://flow_editor.tscn").instantiate()
	root.add_child(flow)
	flow.set_process(false)
	await frames()
	var a: String = flow.add_template("quake",0)
	var b: String = flow.add_template("swarm",5)
	var c: String = flow.add_template("magic",0)
	var d: String = flow.add_template("show",3)
	flow.connect_moves(a,0,b,0)
	flow.connect_moves(a,0,c,0)
	flow.connect_moves(b,0,d,0)
	flow.connect_moves(c,0,d,0)
	await frames()
	var schedule := Model.schedule(flow.document)
	expect(is_equal_approx(float(schedule.starts[b]),float(schedule.starts[c])),"Fork starts in parallel")
	expect(float(schedule.starts[d])>=float(schedule.starts[b])+Model.span(flow._node(b))-.00001,"Join waits for both branches")
	flow.connect_moves(d,0,a,0)
	expect(flow.document.edges.size()==4,"Cycle rejected")
	flow.undo()
	expect(flow.document.edges.size()==3,"Undo graph edit")
	flow.redo()
	expect(flow.document.edges.size()==4,"Redo graph edit")
	flow.edit_move(b)
	await frames()
	flow._node_editor.set_field("count",850)
	flow._node_editor._save()
	await frames()
	expect(flow._node_editor==null and flow._node(b).data.events[0].count==850,"Apply move and return to graph")
	# Save under the ignored verification folder, never overwrite a published example.
	DirAccess.make_dir_recursive_absolute("res://verification/public_saved")
	flow.combo_path = "res://verification/public_saved/combo.json"
	flow.save_document()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(flow.combo_path))
	expect(not flow.dirty and saved.has("_flow") and saved.events.size()>0,"Graph saves together with playable timeline")
	flow.load_document(flow.combo_path)
	expect(flow.document.nodes.size()==4,"Saved graph loads")
	flow.free()
	# Each authored example runs its complete timeline, including scenes without hits.
	for folder: String in DirAccess.get_directories_at("res://combos"):
		if not (folder.begins_with("public_") or folder.begins_with("quake_")):continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combos/"+folder+"/combo.json"))
		ComboStyle.load_file("res://combos/"+folder+"/style.json")
		var player := Stage.new()
		root.add_child(player)
		player.set_process(false)
		player.TIMELINE = ComboStage.parse_events(data.events)
		player.play()
		for i in 1500:
			player.playing = true
			player.advance(1.0/60.0)
			if i%90==0:await process_frame
		expect(player._next==player.TIMELINE.size(),"Full timeline plays: "+folder)
		expect(player.hits==player.expected_hits(),"Expected hits: "+folder)
		player.free()
		await frames()
	print("PASS: %d public checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
