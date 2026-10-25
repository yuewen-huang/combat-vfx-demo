extends SceneTree
## Targeted contract checks for coordinate casts, mixed materials and their manual editor.

const Magic = preload("res://vfx/magic_stage.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var spec := Magic.cast_spec({"element": "fire", "shape": "beam", "mix": ["sand", "ice"], "start": [[20, 30], "hand"], "end": [500, 450], "linger": 2.0, "burst": true})
	assert(spec.start == "at" and spec.starts == [[20, 30], "hand"])
	assert(spec.end == "at" and spec.ends == [[500, 450]])
	assert(spec.mix == ["sand", "ice"] and spec.burst)
	var fx = load("res://vfx/magic/shapes/comet.gd").new()
	fx.start = "at"
	fx.starts = [[100, 100]]
	fx.end = "at"
	fx.ends = [[600, 400]]
	fx.materials = [Magic.ELEMENTS.ice]
	fx.path = "spiral"
	fx.ease = 1.0
	assert(fx.path_at(0, 0.5).is_equal_approx(Vector2(350, 250)), "Ice must stay straight")
	fx.free()
	var editor = load("res://node_editor.tscn").instantiate()
	root.add_child(editor)
	var index: int = editor._paths.find("res://combos/element_master/combo.json")
	assert(index >= 0)
	editor._open(index)
	var before: String = JSON.stringify(editor.data)
	for i in editor.data.events.size(): editor.select_event(i)
	assert(JSON.stringify(editor.data) == before, "Inspecting events must preserve coordinate lists")
	var first_cast := -1
	for i in editor.data.events.size():
		if editor.data.events[i].do == "cast":
			first_cast = i
			break
	editor.select_event(first_cast)
	editor.set_field("burst", true)
	assert(editor.data.events[first_cast].burst and not editor.data.events[first_cast].has("finisher"))
	editor._undo_step()
	assert(JSON.stringify(editor.data) == before)
	var validator = load("res://vfx/combo_editor.gd").new()
	assert(validator._valid_points([[20, 30], "hand"], ["hand"]))
	assert(not validator._valid_points([[20], "hand"], ["hand"]))
	validator.free()
	# Exercise a real retained body and a nearby burst, rather than just counting hits.
	var stage: Node = editor.stage
	stage.set_process(false)
	stage.reset()
	stage._fire({"t": 0.0, "do": "cast", "element": "ice", "start": [700, 300], "end": [800, 450], "charge": 0.0, "travel": 0.1, "linger": 5.0, "burst": true})
	var retained: Node = stage.fx.get_child(0)
	retained.advance(0.2)
	assert(retained.lingering())
	stage._next = 1
	stage._fire({"t": 0.0, "do": "cast", "element": "fire", "start": [700, 300], "end": [800, 450], "charge": 0.0, "travel": 0.1, "radius": 80.0, "burst": true})
	var trigger: Node = stage.fx.get_child(1)
	trigger.advance(0.2)
	assert(not retained.lingering(), "Nearby burst must cut the retained body's linger short")
	retained.advance(0.0)
	assert(stage._bursts == 2, "Both the trigger and the retained crystal must burst")
	editor.free()
	print("PASS: coordinate lists, ice straightness, mixed casts, editor undo and chain detonation")
	quit()
