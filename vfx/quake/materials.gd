extends RefCounted
## Ground-impact materials. Shapes are drawn in values (0 darkest … 1 white-hot); each
## material's ramp turns values into its colours, and any `ramp` recolour (配色) swaps the
## whole range at once — purple lightning, golden lava — without touching the shapes.
##
## body: rock (spikes and slabs), crystal (faceted shards), lava (basalt spikes with molten
## fountains), beam (pillars of light on a sigil), bolt (lightning strikes).
## deep / dark / mid / light / glow: the ramp's colours from shadow to emissive; the ramp ends
## in white-hot. stain: ground mark value. dust: dust colour (dust is tinted, not ramped).
const NAMES := {
	"earth": "岩土", "ice": "冰晶", "magma": "熔岩", "magic": "奥术",
	"thunder": "雷霆", "shadow": "暗影", "holy": "圣光",
}
const DATA := {
	"earth": {"body": "rock", "deep": "1e1712", "dark": "4c3a2c", "mid": "8f7257", "light": "cfb18b", "glow": "ffc27a",
		"crack_glow": 0.35, "crack_keep": 0.0, "stain": 0.0, "stain_alpha": 0.45,
		"dust": "a8967f", "dust_alpha": 0.75, "debris": "stone", "wave": 0.55},
	"ice": {"body": "crystal", "deep": "123553", "dark": "4b97c2", "mid": "9fdcf2", "light": "f2fdff", "glow": "8fe9ff",
		"crack_glow": 0.9, "crack_keep": 0.35, "stain": 0.75, "stain_alpha": 0.32,
		"dust": "dff3fb", "dust_alpha": 0.5, "debris": "ice", "wave": 0.8},
	"magma": {"body": "lava", "deep": "0b0605", "dark": "2a1a14", "mid": "6a1d0c", "light": "d4400f", "glow": "ff8c1a",
		"rock": {"light": 0.42, "rock_lit": 0.36, "rock_hi": 0.46, "dark": 0.2},
		"crack_glow": 1.5, "crack_keep": 0.7, "stain": 0.0, "stain_alpha": 0.55,
		"dust": "3a2f2b", "dust_alpha": 0.7, "debris": "ember", "wave": 0.9},
	"magic": {"body": "beam", "deep": "1c0c40", "dark": "7444dc", "mid": "c59bff", "light": "f6ecff", "glow": "a56cff",
		"crack_glow": 1.2, "crack_keep": 0.45, "stain": 0.06, "stain_alpha": 0.35,
		"dust": "8c6fd6", "dust_alpha": 0.3, "debris": "mote", "wave": 1.0},
	"thunder": {"body": "bolt", "deep": "0b1230", "dark": "26449e", "mid": "4f86f0", "light": "b8d4ff", "glow": "6aa2ff",
		"crack_glow": 1.4, "crack_keep": 0.3, "stain": 0.0, "stain_alpha": 0.4,
		"dust": "8d9ab2", "dust_alpha": 0.4, "debris": "spark", "wave": 1.0},
	"shadow": {"body": "crystal", "deep": "07030c", "dark": "26143a", "mid": "4a2a6c", "light": "8a5bbb", "glow": "c04dff",
		"crack_glow": 1.2, "crack_keep": 0.5, "stain": 0.0, "stain_alpha": 0.6,
		"dust": "2b1a3a", "dust_alpha": 0.6, "debris": "mote", "wave": 0.9},
	"holy": {"body": "beam", "deep": "4a2c06", "dark": "e8a83a", "mid": "ffe58f", "light": "fffbea", "glow": "ffc94a",
		"crack_glow": 1.2, "crack_keep": 0.4, "stain": 0.75, "stain_alpha": 0.18,
		"dust": "f4e3b2", "dust_alpha": 0.35, "debris": "mote", "wave": 1.0},
}
## Where each named colour sits on the ramp; shapes draw with these values.
const VALUES := {"deep": 0.06, "dark": 0.3, "mid": 0.52, "light": 0.75, "glow": 0.88, "white": 1.0}
## 配色: recolours that replace a material's ramp (deep, dark, mid, light, glow).
const COLORWAYS := {
	"gold": ["金", ["1a0d00", "6b3a00", "d9851a", "ffe7a3", "ffc13d"]],
	"violet": ["紫", ["12052a", "431a8a", "9a5cff", "e2ccff", "b77dff"]],
	"crimson": ["赤红", ["1a0306", "6e0d16", "e0302a", "ffb09a", "ff5a3a"]],
	"azure": ["冰蓝", ["06142a", "1d4f8f", "4fa8ff", "d6f0ff", "7cc8ff"]],
	"jade": ["翠绿", ["041a0e", "0f5a2e", "3fcf6a", "ccffd8", "6dff9a"]],
	"silver": ["白银", ["0b0d10", "3b424c", "8a96a3", "e4ebf2", "c8d8ea"]],
	"abyss": ["暗黑", ["020104", "1a1020", "4a3358", "a68fc0", "8a4dff"]],
	"autumn": ["秋叶", ["21150a", "634321", "ad7835", "e6bd6a", "fff0b3"]],
	"ivory": ["羽白", ["25232d", "6d6474", "b9adb9", "eee5e5", "fffaf0"]],
	"dune": ["沙漠", ["241b12", "665036", "b48b52", "e4c38b", "fff0cb"]],
}
## 形态: alternative body designs a material offers (the first is its default).
const FORMS := {
	"earth":[["spike","岩刺阵"]], "ice":[["cluster","冰晶簇"]],
	"magma":[["scorch","灼地熔化"]], "thunder":[["sky","天雷"]],
}

static func form(unit: String, wanted: String) -> String:
	var forms: Array = FORMS.get(unit, [])
	if forms.is_empty(): return ""
	for item: Array in forms: if item[0] == wanted: return wanted
	return forms[0][0]


## 画风 and 精细度, saved in style.json as "quake_style" / "quake_detail".
const STYLES := ["real", "cel", "pixel"]
const STYLE_NAMES := {"real": "写实", "cel": "赛璐璐", "pixel": "像素"}
const DETAILS := ["balanced", "fine", "ultimate", "explosive"]
const DETAIL_NAMES := {"balanced": "均衡", "fine": "精细", "ultimate": "极致", "explosive": "炸裂"}
## Share of particles (debris, dust, sparks, echoes) each tier keeps.
const DETAIL_SCALE := {"balanced": 0.35, "fine": 0.6, "ultimate": 1.0, "explosive": 1.0}

static var _ramps := {}

## Value-encoded palette for drawing: every colour is Color(value, pattern, param, alpha).
static func palette(unit: String, dust_override := "") -> Dictionary:
	var raw: Dictionary = DATA.get(unit, DATA.earth)
	var out := raw.duplicate()
	for key: String in VALUES: out[key] = Color(VALUES[key], 0.0, 0.0, 1.0)
	# Rock faces: lit face and fresh-break highlight; a material may pull its rock darker
	# (magma's basalt) where its ramp's upper range is reserved for heat.
	out.rock_lit = Color(0.69, 0.0, 0.0, 1.0)
	out.rock_hi = Color(0.82, 0.0, 0.0, 1.0)
	var rock: Dictionary = raw.get("rock", {})
	for key: String in rock: out[key] = Color(float(rock[key]), 0.0, 0.0, 1.0)
	out.stain = Color(float(raw.stain), 0.0, 0.0, 1.0)
	out.dust = Color(1.0, 0.0, 0.0, 1.0)
	out.dust_tint = Color(String(raw.dust)) if dust_override.is_empty() else Color(dust_override)
	return out

## A value with an optional pattern (see quake.gdshaderinc) and pattern parameter.
static func v(value: float, alpha := 1.0, pattern := 0, param := 0.0) -> Color:
	return Color(value, pattern / 8.0, param, alpha)

## The five ramp colours (deep … glow) for a material and an optional recolour: a
## COLORWAYS name or an array of five hex colours.
static func stops(unit: String, recolour: Variant = "") -> Array:
	if recolour is Array and (recolour as Array).size() == 5:
		return (recolour as Array).map(func(hex: Variant) -> String: return String(hex))
	if recolour is String and COLORWAYS.has(recolour): return COLORWAYS[recolour][1]
	var raw: Dictionary = DATA.get(unit, DATA.earth)
	return [raw.deep, raw.dark, raw.mid, raw.light, raw.glow]

## The material's glow colour for UI swatches.
static func swatch(unit: String, recolour: Variant = "") -> Color:
	return Color(String(stops(unit, recolour)[4]))

static func ramp(unit: String, recolour: Variant = "") -> GradientTexture1D:
	var colours := stops(unit, recolour)
	var key := "%s|%s" % [unit, ",".join(PackedStringArray(colours))]
	if _ramps.has(key): return _ramps[key]
	var c: Array[Color] = []
	for hex: String in colours: c.append(Color(hex))
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.06, 0.3, 0.52, 0.75, 0.88, 1.0])
	gradient.colors = PackedColorArray([c[0].darkened(0.55), c[0], c[1], c[2], c[3], c[4], c[4].lerp(Color.WHITE, 0.85)])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	_ramps[key] = texture
	return texture
