extends RefCounted
## Pure event data: defaults, bounds and the time/distance mapping that every layer of a
## ground impact (front, cracks, bodies, debris, dust) is scheduled from.
const STAGES := [
	{"distance": 1.0, "time": 0.14, "pause": 0.12, "strength": 1.0},
	{"distance": 1.0, "time": 0.14, "pause": 0.26, "strength": 1.1},
	{"distance": 1.0, "time": 0.18, "pause": 0.0, "strength": 1.5},
]
## radial: from the centre outwards. sweep: from one end of the long axis to the other.
## split: from the centre to both ends of the long axis. cone: a fan opening from the origin.
## `reverse` runs any of them backwards (radial reversed is an implosion).
const MODES := ["radial", "sweep", "split", "cone"]
const UNITS := ["earth", "ice", "magma", "magic", "thunder", "shadow", "holy"]
const DEBRIS := ["auto", "none", "stone", "ice", "ember", "spark", "mote"]
const DEFAULTS := {
	"x": 640.0, "y": 520.0, "width": 220.0, "length": 0.0, "angle": 0.0,
	"perspective": 0.3, "mode": "radial", "reverse": false, "cone": 70.0,
	"rhythm": "continuous", "travel": 0.5, "ease": 1.0, "stages": STAGES,
	"unit": "earth", "body": true, "unit_size": 1.0, "spacing": 60.0,
	"unit_time": 0.8, "strength": 1.0, "ramp": "", "form": "", "body_growth": 1.0,
	"cracks": true, "crack_amount": 1.0, "crack_glow": 1.0, "crack_time": 0.6,
	"wave": true, "wave_height": 1.0, "flash": 1.0, "shake": 6.0,
	"debris": "auto", "debris_density": 1.0, "debris_height": 110.0,
	"dust": true, "dust_density": 1.0, "dust_height": 90.0, "dust_spread": 80.0,
	"dust_time": 1.1, "dust_color": "", "dust_growth": 1.0, "seed": 17,
}
const BOUNDS := [["width", 8.0, 900.0], ["length", 0.0, 1800.0], ["perspective", 0.08, 1.0],
	["cone", 10.0, 180.0], ["travel", 0.02, 10.0], ["ease", 0.2, 4.0], ["unit_size", 0.1, 4.0],
	["spacing", 20.0, 300.0], ["unit_time", 0.15, 5.0], ["strength", 0.0, 3.0],
	["crack_amount", 0.0, 3.0], ["crack_glow", 0.0, 3.0], ["crack_time", 0.0, 6.0],
	["wave_height", 0.0, 3.0], ["flash", 0.0, 3.0], ["shake", 0.0, 30.0],
	["debris_density", 0.0, 4.0], ["debris_height", 0.0, 800.0],
	["dust_density", 0.0, 4.0], ["dust_height", 0.0, 600.0], ["dust_spread", 0.0, 600.0],
	["dust_time", 0.1, 10.0], ["dust_growth", 0.1, 5.0], ["body_growth", 0.2, 4.0]]
const GRAVITY := 1800.0
const Materials = preload("res://vfx/quake/materials.gd")

static func finite(value: Variant, fallback: float) -> float:
	if not (value is int or value is float): return fallback
	return float(value) if is_finite(float(value)) else fallback

static func normalized(event: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	for key: String in out:
		if event.has(key): out[key] = event[key]
	for key: String in DEFAULTS:
		if DEFAULTS[key] is float: out[key] = finite(out[key], DEFAULTS[key])
	for item in BOUNDS: out[item[0]] = clampf(float(out[item[0]]), item[1], item[2])
	for key: String in ["body", "dust", "reverse", "cracks", "wave"]:
		out[key] = out[key] if out[key] is bool else DEFAULTS[key]
	if not out.mode in MODES: out.mode = "radial"
	out.rhythm = "staged" if out.rhythm == "staged" else "continuous"
	# Older presets called the arcane material "magic"; any unknown name falls back to earth.
	if not out.unit in UNITS: out.unit = "earth"
	if not out.debris in DEBRIS: out.debris = "auto"
	out.form = Materials.form(String(out.unit), String(out.form) if out.form is String else "")
	out.dust_color = String(out.dust_color) if out.dust_color is String and Color.html_is_valid(String(out.dust_color)) else ""
	# 配色: "" (the material's own), a named colourway, or five hex colours deep → glow.
	var recolour: Variant = out.ramp
	if recolour is Array:
		var valid := (recolour as Array).size() == 5 and (recolour as Array).all(func(x: Variant) -> bool: return x is String and Color.html_is_valid(String(x)))
		out.ramp = (recolour as Array).duplicate() if valid else ""
	elif not (recolour is String and (String(recolour).is_empty() or Materials.COLORWAYS.has(String(recolour)))):
		out.ramp = ""
	out.seed = int(finite(out.seed, 17))
	var stages: Array = []
	if out.stages is Array:
		for raw: Variant in (out.stages as Array).slice(0, 8):
			if not raw is Dictionary: continue
			stages.append({"distance": clampf(finite(raw.get("distance", 1.0), 1.0), 0.01, 10.0),
				"time": clampf(finite(raw.get("time", 0.15), 0.15), 0.02, 3.0),
				"pause": clampf(finite(raw.get("pause", 0.0), 0.0), 0.0, 3.0),
				"strength": clampf(finite(raw.get("strength", 1.0), 1.0), 0.0, 3.0)})
	out.stages = stages if not stages.is_empty() else STAGES.duplicate(true)
	return out

static func duration(spec: Dictionary) -> float:
	if spec.rhythm != "staged": return float(spec.travel)
	var total := 0.0
	for i in spec.stages.size():
		total += float(spec.stages[i].time)
		if i < spec.stages.size() - 1: total += float(spec.stages[i].pause)
	return total

static func total_weight(spec: Dictionary) -> float:
	var total := 0.0
	for step: Dictionary in spec.stages: total += float(step.distance)
	return total

## How far (0–1) the front has travelled `age` seconds after the event.
static func progress(spec: Dictionary, age: float) -> float:
	if age < 0.0: return 0.0
	if spec.rhythm != "staged": return pow(clampf(age / float(spec.travel), 0.0, 1.0), float(spec.ease))
	var clock := 0.0
	var at := 0.0
	var weight := total_weight(spec)
	for step: Dictionary in spec.stages:
		var span := float(step.distance) / weight
		if age < clock + float(step.time): return at + span * (age - clock) / float(step.time)
		at += span
		clock += float(step.time)
		if age < clock + float(step.pause): return minf(at, 1.0)
		clock += float(step.pause)
	return 1.0

## When the front reaches `distance` (0–1).
static func arrival(spec: Dictionary, distance: float) -> float:
	var d := clampf(distance, 0.0, 1.0)
	if spec.rhythm != "staged": return float(spec.travel) * pow(d, 1.0 / float(spec.ease))
	var clock := 0.0
	var at := 0.0
	var weight := total_weight(spec)
	for step: Dictionary in spec.stages:
		var span := float(step.distance) / weight
		if d <= at + span + 0.000001: return clock + clampf((d - at) / span, 0.0, 1.0) * float(step.time)
		clock += float(step.time) + float(step.pause)
		at += span
	return duration(spec)

## Strength at a travelled distance: the event strength times its stage's strength.
static func gain(spec: Dictionary, distance: float) -> float:
	if spec.rhythm != "staged": return float(spec.strength)
	var at := 0.0
	var weight := total_weight(spec)
	for step: Dictionary in spec.stages:
		at += float(step.distance) / weight
		if distance <= at + 0.000001: return float(spec.strength) * float(step.strength)
	return float(spec.strength)

## Start time and strength of every push of the front (one for continuous propagation).
static func pulses(spec: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if spec.rhythm != "staged":
		out.append({"t": 0.0, "d": 0.0, "gain": float(spec.strength)})
		return out
	var clock := 0.0
	var at := 0.0
	var weight := total_weight(spec)
	for step: Dictionary in spec.stages:
		out.append({"t": clock, "d": at, "gain": float(spec.strength) * float(step.strength)})
		clock += float(step.time) + float(step.pause)
		at += float(step.distance) / weight
	return out

## 远端放大: bodies grow with the distance travelled, 1 at the start
## to `body_growth` at the far end.
static func body_scale(spec: Dictionary, distance: float) -> float:
	return lerpf(1.0, float(spec.body_growth), clampf(distance, 0.0, 1.0))

static func dust_scale(spec: Dictionary, distance: float) -> float:
	return lerpf(1.0, float(spec.dust_growth), clampf(distance, 0.0, 1.0))

static func flight(height: float) -> float:
	return 2.0 * sqrt(2.0 * GRAVITY * maxf(height, 0.0)) / GRAVITY

## Everything an event draws is gone by this many seconds after it fires.
static func lifetime(spec: Dictionary) -> float:
	var tail := float(spec.unit_time) + float(spec.crack_time)
	tail = maxf(tail, float(spec.dust_time) * 1.15)
	tail = maxf(tail, flight(float(spec.debris_height) * 1.25) + 0.45)
	return duration(spec) + tail + 0.1
