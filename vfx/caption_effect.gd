extends Node2D
## 字幕 (`caption` event), in 屏幕层: text that fades in, holds for `time` and fades out.
## place: title 标题 (large, centred), subtitle 下方字幕 (lower third), corner 角标 (top left,
## like a move name). Serif for titles; `size` scales the type.

const PLACES := ["title", "subtitle", "corner"]
const PLACE_NAMES := {"title": "标题", "subtitle": "下方字幕", "corner": "角标"}
const DEFAULTS := {"text": "效果演示", "place": "title", "time": 1.2, "fade": 0.18, "size": 1.0, "color": "fff2f8"}
const SIZES := {"title": 96, "subtitle": 40, "corner": 24}

var spec: Dictionary
var age := 0.0
var _label: Label

static func normalized(event: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	out.merge(event, true)
	if not String(out.place) in PLACES: out.place = "title"
	return out

func configure(event: Dictionary) -> Node2D:
	spec = normalized(event)
	_label = Label.new()
	_label.text = String(spec.text)
	var place := String(spec.place)
	if place != "corner":
		var serif := SystemFont.new()
		serif.font_names = PackedStringArray(["Yu Mincho", "MS Mincho", "SimSun", "serif"])
		serif.font_weight = 600
		_label.add_theme_font_override("font", serif)
	_label.add_theme_font_size_override("font_size", int(SIZES[place] * float(spec.size)))
	_label.add_theme_color_override("font_color", Color(String(spec.color)))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_label.add_theme_constant_override("shadow_offset_y", 3)
	_label.add_theme_constant_override("shadow_outline_size", 8)
	add_child(_label)
	var box := _label.get_minimum_size()
	match place:
		"title": _label.position = Vector2(640, 330) - box * 0.5
		"subtitle": _label.position = Vector2(640, 590) - box * 0.5
		"corner": _label.position = Vector2(40, 70)
	_update()
	return self

func _update() -> void:
	var fade := maxf(float(spec.fade), 0.01)
	var hold := float(spec.time)
	_label.modulate.a = clampf(age / fade, 0.0, 1.0) * clampf((hold + fade - age) / fade, 0.0, 1.0)

func advance(delta: float) -> void:
	age += delta
	_update()

func is_done() -> bool:
	return age > float(spec.time) + float(spec.fade) * 2.0

static func lifetime(event: Dictionary) -> float:
	var s := normalized(event)
	return float(s.time) + float(s.fade) * 2.0
