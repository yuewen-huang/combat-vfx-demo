extends RefCounted
## Editing categories are navigation, independent of the document's renderer.
const Legacy = preload("res://vfx/combo_editor.gd")
const Magic = preload("res://vfx/magic_stage.gd")
const Ground = preload("res://vfx/quake_editor.gd")
const KEYS := ["blade", "magic", "quake", "swarm", "show", "other"]
const NAMES := ["刀光", "魔法", "地震", "群体", "演出", "其他"]
const Caption = preload("res://vfx/caption_effect.gd")
const Impact = preload("res://vfx/impact_effect.gd")
const Swarm = preload("res://vfx/swarm_effect.gd")
const BLADE_RENDERERS := ["", "ribbon", "ink", "claw"]
const BLADE_NAMES := ["月牙", "轨迹刀光", "水墨", "爪痕"]
const PALETTE_NAMES := ["钢蓝", "紫", "赤红", "金", "翠绿"]
const PRESETS := {
	"blade": [
		["横斩", "横向挥刀，快速扫过目标", "", {"from": -65.0, "to": 65.0, "radius": 160.0, "squash": 0.5}],
		["竖劈", "从高处劈落，强调刀刃轮廓", "", {"from": -145.0, "to": 45.0, "radius": 165.0, "squash": 1.0}],
		["上挑", "反向挥动，命中时将目标挑起", "", {"from": 65.0, "to": -85.0, "radius": 165.0}],
		["回旋", "轨迹绕身一周，留下连续拖尾", "ribbon", {"from": -180.0, "to": 180.0, "duration": 0.3, "tail": 0.24}],
		["突刺", "压扁的月牙，形成向前刺出的细刃", "", {"from": -55.0, "to": 55.0, "radius": 190.0, "squash": 0.16, "width": 30.0}],
		["交叉爪斩", "两道交错爪痕，带撕裂残留", "claw", {"claw": "cross", "angle": 40.0, "length": 240.0, "duration": 0.2, "cross_delay": 0.07}],
		["水墨挥斩", "保留水墨绘制器的飞白与墨滴", "ink", {"from": -70.0, "to": 70.0, "radius": 165.0}],
	],
	"magic": [
		["飞弹", "从手中凝聚，沿弧线飞向目标", "magic", {"element": "fire", "shape": "comet", "path": "arc", "charge": 0.22, "travel": 0.4}],
		["射线", "短暂蓄力后射出直线光束", "magic", {"element": "thunder", "shape": "beam", "path": "straight", "charge": 0.2, "travel": 0.25, "hold": 0.35}],
		["落雷", "从高空落到目标身上", "magic", {"element": "thunder", "shape": "pillar", "start": "sky", "path": "straight", "charge": 0.18, "travel": 0.25}],
		["法阵", "在目标脚下展开持续法阵", "magic", {"element": "ice", "shape": "circle", "start": [840, 516], "end": "ground", "path": "stay", "charge": 0.22, "travel": 0.6, "hold": 0.5}],
		["持续风场", "原地维持旋风，结束时扩散", "magic", {"element": "wind", "shape": "vortex", "start": "target", "path": "stay", "charge": 0.2, "travel": 0.8, "hold": 0.4}],
		["三连飞弹", "连续发射三枚弹体，自动关联落点命中", "magic", {"element": "fire", "shape": "comet", "path": "arc", "count": 3, "interval": 0.16, "spread": 45.0, "travel": 0.4}],
	],
	# 群体 templates: [name, note, renderer, fields, extra events played with it].
	"swarm": [
		["群体云团", "落叶在中心周围形成云团", "", {"material":"leaf", "form":"cloud", "ramp":"autumn"}, []],
		["路径流动", "落叶沿可编辑路径运动", "", {"material":"leaf", "form":"stream", "ramp":"autumn"}, []],
		["球形聚集", "羽毛在中心周围旋转聚集", "", {"material":"feather", "form":"sphere", "ramp":"ivory"}, []],
		["爆散", "落叶从中心向外散开", "", {"material":"leaf", "form":"burst", "ramp":"autumn"}, []],
		["消散", "既有群体逐渐消失；孤立编辑提供临时来源", "", {"material":"feather", "form":"gone", "ramp":"ivory"}, []],
		["落叶 · 秋风回旋", "卷边、叶脉和透光的枯叶，随风摇摆翻落", "", {"material": "leaf", "form": "fall", "at": [640,300], "count": 900, "ramp": "autumn", "radius": 600.0, "height": 360.0, "look": "mirror", "linger": 3.0}, []],
		["羽毛 · 轻羽漫落", "羽轴与分叉羽枝，柔软弯曲、缓慢摆落", "", {"material": "feather", "form": "fall", "at": [640,280], "count": 600, "ramp": "ivory", "radius": 570.0, "height": 340.0, "look": "mirror", "linger": 3.0}, []],
		["沙漠 · 扬沙风暴", "细尘遮蔽与砂砾共存；粒径控制轻重，贴地沉降", "", {"material": "sand", "form": "vortex", "at": "target", "count": 11000, "ramp": "dune", "radius": 230.0, "height": 330.0, "look": "mirror", "swirl": 3.0, "turbulence": 24.0, "linger": 3.0}, []],
	],
	# 演出: screen-level presentation; each template names its own event kind.
	"show": [
		["标题字幕", "画面中央淡入的招式名", "", {"do": "caption", "text": "效果演示", "place": "title", "time": 1.2}],
		["下方字幕", "画面下方的一句台词", "", {"do": "caption", "text": "自定义字幕", "place": "subtitle", "time": 1.4}],
		["负片冲击帧", "重击瞬间的一帧负片定格", "", {"do": "impact", "kind": "invert", "time": 0.06, "fade": 0.1}],
		["闪白", "重击瞬间画面短暂泛白", "", {"do": "impact", "kind": "flash", "time": 0.04, "fade": 0.25, "strength": 0.7}],
	],
	"other": [
		["命中火花", "火花、顿帧与击退的一次完整命中", "", {"do": "hit", "spark": 90.0, "push": 50.0, "stop": 0.05}],
		["刀痕", "在目标位置留下切割痕迹", "", {"do": "cut", "angle": -35.0}],
		["蓄力闪光", "攻击者身上的短促蓄力提示", "", {"do": "charge"}],
	],
}

static func presets(category: String) -> Array:
	if category == "quake": return Ground.TEMPLATES
	return PRESETS.get(category, PRESETS.blade)

static func kind_category(kind: String) -> String:
	match kind:
		"slash": return "blade"
		"cast": return "magic"
		"quake": return "quake"
		"swarm": return "swarm"
		"caption", "impact": return "show"
	return "other"

static func document_category(document: Dictionary, look: Dictionary) -> String:
	var renderer := String(look.get("renderer", ""))
	if renderer == "magic": return "magic"
	if renderer == "quake": return "quake"
	for e: Dictionary in document.get("events", []):
		if e.get("do") == "slash": return "blade"
	for kind: String in ["quake", "swarm"]:
		for e: Dictionary in document.get("events", []):
			if e.get("do") == kind: return kind
	for e: Dictionary in document.get("events", []):
		if e.get("do") in ["caption", "impact"]: return "show"
	return "other"

static func create(category: String, which: int) -> Dictionary:
	var kind: String = {"blade":"slash", "magic":"cast", "quake":"quake", "swarm":"swarm", "show":"caption", "other":"hit"}[category]
	var p: Array = presets(category)[which]
	var fields: Dictionary = p[2] if category == "quake" else p[3]
	var e := {"t": 0.2, "do": kind}
	if category == "swarm":
		e.id = "group"
		e.merge(fields.duplicate(true), true)
		var events: Array = [e]
		for extra: Dictionary in p[4]:
			var next := {"do": kind, "id": e.id}
			next.merge(extra.duplicate(true), true)
			next.t = float(extra.t) + 0.2
			events.append(next)
		return {"data": {"name": p[0], "events": events}, "style": {"title": p[0], "language": "zh", "renderer": String(p[2])}}
	if category == "quake": e.merge({"unit": "earth", "x": 640.0, "y": 520.0})
	if category == "blade": e.merge({"from": -70.0, "to": 70.0, "width": 44.0})
	e.merge(fields.duplicate(true), true)
	var renderer := "quake" if category == "quake" else String(p[2])
	var look := {"title": p[0], "language": "zh", "renderer": renderer}
	return {"data": {"name": p[0], "events": [e]}, "style": look}

static func defaults(e: Dictionary, renderer := "") -> Dictionary:
	if e.get("do") == "quake": return Ground.Profile.normalized(e)
	if e.get("do") == "swarm": return Swarm.normalized(e)
	if e.get("do") == "caption": return Caption.normalized(e)
	if e.get("do") == "impact": return Impact.normalized(e)
	if e.get("do") == "cast":
		var result := Magic.cast_spec(e)
		result.merge(e, true)
		return result
	var result: Dictionary = {}
	for field: Array in Legacy.FIELDS.get(String(e.get("do", "")), []): result[field[0]] = field[5]
	if e.get("do") == "slash" and renderer.is_empty(): result.merge({"duration": 0.045, "fade": 0.13}, true)
	if e.get("do") == "slash" and renderer == "claw": result.merge(preload("res://vfx/claw_stage.gd").DEFAULTS, true)
	result.merge(e, true)
	return result

static func stationary(e: Dictionary) -> bool:
	if e.get("do") != "cast": return false
	var s := Magic.cast_spec(e)
	var element: GDScript = Magic.ELEMENTS.get(String(e.get("element", "fire")), Magic.ELEMENTS.fire)
	return Magic.shape_of(s, element) in ["ring", "pillar", "vortex", "circle"]

static func effective_path(e: Dictionary) -> String:
	if stationary(e): return "stay"
	var s := Magic.cast_spec(e)
	if e.get("element") == "ice" and s.path != "stay": return "straight"
	return String(s.path)

static func duration(e: Dictionary, renderer: String) -> float:
	var s := defaults(e, renderer)
	match String(e.get("do", "")):
		"quake": return Ground.Profile.lifetime(s)
		"cast": return float(s.charge) + float(s.travel) + float(s.interval) * (int(s.count) - 1) + float(s.hold) + float(s.linger) + float(s.fuse) + 1.5
		"slash":
			if renderer in ["ribbon", "claw"]: return float(s.duration) + float(s.tail) + 0.5
			return 0.68 if renderer == "ink" else float(s.duration) + 0.04 + float(s.get("fade", 0.13))
		"move", "camera": return float(s.time)
		"swarm": return Swarm.tail(e)
		"caption": return Caption.lifetime(e)
		"impact": return Impact.lifetime(e)
	return 1.5

static func phases(e: Dictionary, renderer: String) -> Array:
	var s := defaults(e, renderer)
	var result: Array = []
	match String(e.get("do", "")):
		"quake":
			if s.rhythm == "staged":
				for i in s.stages.size():
					result.append(["推进 %d" % (i + 1), float(s.stages[i].time), "stages:%d:time" % i])
					if i < s.stages.size() - 1: result.append(["停顿", float(s.stages[i].pause), "stages:%d:pause" % i])
			else: result.append(["推进", float(s.travel), "travel"])
			result.append(["残留", maxf(0.05, duration(e, renderer) - Ground.Profile.duration(s)), ""])
		"cast":
			result = [["凝聚", float(s.charge), "charge"], ["飞行" if effective_path(e) != "stay" else "维持", float(s.travel), "travel"]]
			if int(s.count) > 1: result.append(["连发", float(s.interval) * (int(s.count) - 1), ""])
			result.append(["落点停留", float(s.linger), "linger"])
			result.append(["消散", float(s.hold) + 0.5, ""])
		"slash":
			if renderer in ["ribbon", "claw"]: result = [["挥动", float(s.duration), "duration"], ["拖尾", float(s.tail), "tail"]]
			elif renderer == "ink": result = [["落笔", 0.065, ""], ["墨迹残留", 0.615, ""]]
			else: result = [["挥动", float(s.duration), "duration"], ["停留", 0.04, ""], ["消散", float(s.fade), "fade"]]
		"swarm":
			result = [["变换", float(s.time), "time"]]
			if s.form == "stream": result.append(["流动", float(s.travel), "travel"])
			result.append(["停留", float(s.linger), "linger"])
		"caption": result = [["淡入", float(s.fade), "fade"], ["停留", float(s.time), "time"], ["淡出", float(s.fade), ""]]
		"impact": result = [["定格", float(s.time), "time"], ["淡出", float(s.fade), "fade"]]
		_: result = [[Legacy.DO_NAMES.get(String(e.get("do", "")), "效果"), duration(e, renderer), ""]]
	return result
