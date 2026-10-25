@tool
extends ComboStage
## Pure ground-impact scenes: the shared stage with nothing but `quake` events in it.
## Q cycles 画风 (写实 / 赛璐璐 / 像素) live; W cycles 精细度 and replays.
const Materials = preload("res://vfx/quake/materials.gd")

func _ready() -> void:
	super._ready()
	help.text += "    Q：画风　W：精细度"
	_warm_up.call_deferred()

## Compiles every ground-impact shader at load, outside `fx` so the combo's settle and loop
## logic never sees the samples. Deferred calls die with the node, so freeing early is safe.
func _warm_up() -> void:
	if is_inside_tree(): preload("res://vfx/quake_effect.gd").warm_up(self)

func _unhandled_input(event: InputEvent) -> void:
	if not Engine.is_editor_hint() and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_Q, KEY_W]:
		var key := "quake_style" if event.keycode == KEY_Q else "quake_detail"
		var values: Array = Materials.STYLES if event.keycode == KEY_Q else Materials.DETAILS
		var current := values.find(String(ComboStyle.data.get(key, values[0] if event.keycode == KEY_Q else "explosive")))
		ComboStyle.data[key] = values[(current + 1) % values.size()]
		if event.keycode == KEY_Q:
			for holder in effect_holders():
				for effect in holder.get_children():
					if effect.has_method("set_look"): effect.set_look(String(ComboStyle.data.quake_style), effect.detail)
		else: play()
		help.text = help.text.get_slice("    Q", 0) + "    Q：画风 %s　W：精细度 %s" % [Materials.STYLE_NAMES[String(ComboStyle.data.get("quake_style", "real"))], Materials.DETAIL_NAMES[String(ComboStyle.data.get("quake_detail", "explosive"))]]
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)
