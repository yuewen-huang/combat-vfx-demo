@tool
extends "res://vfx/magic_stage.gd"
## One battlefield and action clock. Specialized melee strokes retain their own renderers.
var _delegates: Dictionary = {}

func reset() -> void:
	# Preserve authored ordering for overlays and hit-stop events on the same timestamp.
	TIMELINE.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.t)<float(b.t) if not is_equal_approx(float(a.t),float(b.t)) else int(a.get("_flow_order",0))<int(b.get("_flow_order",0)))
	for delegate: Node in _delegates.values(): delegate.free()
	_delegates.clear()
	super.reset()
	if ComboStyle.data.get("flow_stage","melee")!="magic":
		attacker.position = ATTACKER_START
		target.position = TARGET_START

func _delegate(renderer: String) -> Node2D:
	if not _delegates.has(renderer): _delegates[renderer] = load("res://vfx/%s_stage.gd" % renderer).new()
	var helper: Node2D = _delegates[renderer]
	for key: String in ["attacker","target","fx","clock","hits","_stop","_moves","_target_velocity","_target_flash","_counter_age","_next"]: helper.set(key,get(key))
	return helper

func _copy_back(helper: Node2D) -> void:
	for key: String in ["hits","_stop","_moves","_target_velocity","_target_flash","_counter_age"]: set(key,helper.get(key))

func _fire(event: Dictionary) -> void:
	var previous: Dictionary = ComboStyle.data
	if event.get("_flow_style") is Dictionary: ComboStyle.load_data(event._flow_style)
	var renderer := String(event.get("_flow_renderer",""))
	if event.do=="slash" and renderer in ["ribbon","claw","ink"]:
		var helper := _delegate(renderer)
		helper._fire(event)
		_copy_back(helper)
	else: super._fire(event)
	ComboStyle.load_data(previous)

func _hit(event: Dictionary) -> void:
	var renderer := String(event.get("_flow_renderer",""))
	if renderer in ["ink","claw"]:
		var helper := _delegate(renderer)
		helper._hit(event)
		_copy_back(helper)
		_shake(float(event.shake),.22 if event.get("finisher",false) else .09)
	else: super._hit(event)

func _exit_tree() -> void:
	for delegate: Node in _delegates.values(): delegate.free()
	_delegates.clear()
