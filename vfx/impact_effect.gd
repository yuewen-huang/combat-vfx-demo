extends Node2D
## 冲击帧 (`impact` event), in 屏幕层: a held moment on a big hit. kind invert 负片 turns the
## frame into a stark negative (dark shapes on a white ground, tinted by `color`); flash 闪白
## washes it towards `color`. Holds for `time`, then eases out over `fade`.

const KINDS := ["invert", "flash"]
const KIND_NAMES := {"invert": "负片", "flash": "闪白"}
const DEFAULTS := {"kind": "invert", "time": 0.06, "fade": 0.12, "strength": 1.0, "color": "fff0f6"}
const SHADER := preload("res://vfx/impact.gdshader")

var spec: Dictionary
var age := 0.0
var _rect: ColorRect

static func normalized(event: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	out.merge(event, true)
	if not String(out.kind) in KINDS: out.kind = "invert"
	return out

func configure(event: Dictionary) -> Node2D:
	spec = normalized(event)
	_rect = ColorRect.new()
	_rect.size = Vector2(1280, 720)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("invert", String(spec.kind) == "invert")
	material.set_shader_parameter("tint", Color(String(spec.color)))
	_rect.material = material
	add_child(_rect)
	_update()
	return self

func _update() -> void:
	var fade := maxf(float(spec.fade), 0.001)
	var amount := float(spec.strength) * (1.0 if age <= float(spec.time) else clampf(1.0 - (age - float(spec.time)) / fade, 0.0, 1.0))
	(_rect.material as ShaderMaterial).set_shader_parameter("amount", amount)

func advance(delta: float) -> void:
	age += delta
	_update()

func is_done() -> bool:
	return age > float(spec.time) + float(spec.fade)

static func lifetime(event: Dictionary) -> float:
	var s := normalized(event)
	return float(s.time) + float(s.fade)
