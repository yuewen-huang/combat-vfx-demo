extends SceneTree
## Actual renderer capture: three natural materials and the public flow editor.
const Swarm = preload("res://vfx/swarm_effect.gd")
var stage: Node2D
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Use a native graphics backend to capture")
		quit(1)
		return
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://verification/public")
	ComboStyle.load_data({"language":"zh","quake_style":"real","quake_detail":"fine"})
	stage = preload("res://vfx/flow_stage.gd").new()
	root.add_child(stage)
	stage.set_process(false)
	stage.help.hide()
	stage.quality_label.hide()
	stage.attacker.hide()
	stage.target.hide()
	for i in 3:
		var material: String = Swarm.PieceMaterials.KEYS[i]
		var effect: Node2D = Swarm.new().configure({"material":material,"form":"cloud","at":[235+i*405,330],"count":2500 if material=="sand" else 430,"radius":150,"height":220,"size":1.35,"seed":17},stage)
		stage.near_fx.add_child(effect)
		effect.advance(.7)
		var label := Label.new()
		label.text = Swarm.PieceMaterials.NAMES[material]
		label.position = Vector2(180+i*405,145)
		label.add_theme_font_size_override("font_size",30)
		stage.screen_fx.add_child(label)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://verification/public/materials.png")
	stage.free()
	await process_frame
	var flow: Control = load("res://flow_editor.tscn").instantiate()
	root.add_child(flow)
	flow.load_document("res://combos/public_multiskill/combo.json")
	flow.redraw_graph()
	flow.graph.zoom = .8
	flow.seek(1.7)
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://verification/public/flow.png")
	flow.edit_move("leaves")
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://verification/public/node.png")
	flow.free()
	print("PASS: saved public material, flow and node screenshots")
	quit()
