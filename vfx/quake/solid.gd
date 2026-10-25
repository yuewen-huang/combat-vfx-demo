extends RefCounted
## Solid bodies (rock spikes, slabs, boulders, the ground surge) as one static mesh per
## effect. Each vertex carries its 3D position around its body's pivot, its face normal,
## its body's birth time and how the body moves; shaders/solid.gdshader raises, tilts,
## rolls and sinks every body on the GPU, lights it and culls faces turned away. The CPU
## builds the mesh once and afterwards only sets the time.
##
## Ground frame: x along the ground, y towards the viewer, z up. The screen offset of a
## point is (x, y × perspective − z) from its pivot's screen position.
##
## Per vertex: VERTEX pivot on screen; CUSTOM0 (x, y, z, birth); CUSTOM1 (normal, axis angle);
## UV (kind, magnitude); COLOR (value bias, pattern / 8, pattern parameter, alpha).
## Kinds: 0 spike (grows from the ground), 1 slab (tips up on its back edge), 2 boulder
## (pushes up, rolls, sinks), 3 surge (ground swell following the front; CUSTOM1.xy is the
## arrival-time gradient instead of a normal), 4 crystal (sprouts, glints, bursts into facets).
const SPIKE := 0
const SLAB := 1
const BOULDER := 2
const SURGE := 3
const CRYSTAL := 4

var pivots := PackedVector2Array()
var custom0 := PackedFloat32Array()
var custom1 := PackedFloat32Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()
## Ground rotation of the effect (radians), baked into every position and normal.
var angle := 0.0
## Ground rotation of the body being added: its local x points this way (radians).
var heading := 0.0

func _flat(v: Vector3) -> Vector3:
	var xy := Vector2(v.x, v.y).rotated(angle + heading)
	return Vector3(xy.x, xy.y, v.z)

func _vertex(pivot: Vector2, p: Vector3, n: Vector3, birth: float, axis: float, kind: int, magnitude: float, tone: Color) -> void:
	pivots.append(pivot)
	custom0.append_array(PackedFloat32Array([p.x, p.y, p.z, birth]))
	custom1.append_array(PackedFloat32Array([n.x, n.y, n.z, axis + angle + heading]))
	uvs.append(Vector2(kind, magnitude))
	colors.append(tone)

## One flat face (convex, any winding): its normal is turned to point away from `inside`.
func face(pivot: Vector2, corners: Array[Vector3], inside: Vector3, birth: float, axis: float, kind: int, magnitude: float, tone: Color) -> void:
	var pts: Array[Vector3] = []
	for c in corners: pts.append(_flat(c))
	var inner := _flat(inside)
	var n := (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	var middle := Vector3.ZERO
	for p in pts: middle += p
	middle /= pts.size()
	if n.dot(middle - inner) < 0.0: n = -n
	for i in range(1, pts.size() - 1):
		for p in [pts[0], pts[i], pts[i + 1]]: _vertex(pivot, p, n, birth, axis, kind, magnitude, tone)

## A convex solid from its corner list and faces (index lists into the corners).
func solid(pivot: Vector2, corners: Array[Vector3], faces: Array, birth: float, axis: float, kind: int, magnitude: float, tone_of: Callable) -> void:
	var middle := Vector3.ZERO
	for c in corners: middle += c
	middle /= corners.size()
	for f: Array in faces:
		var pts: Array[Vector3] = []
		for i: int in f: pts.append(corners[i])
		face(pivot, pts, middle, birth, axis, kind, magnitude, tone_of.call(pts))

## A box `size` (x, y, z) whose top face lies at z = 0 and whose −x edge is at x = 0 (the hinge).
func slab(pivot: Vector2, size: Vector3, birth: float, axis: float, tilt: float, top: Color, side: Color) -> void:
	var c: Array[Vector3] = []
	for z in [0.0, -size.z]:
		for y in [-size.y * 0.5, size.y * 0.5]:
			for x in [0.0, size.x]: c.append(Vector3(x, y, z))
	# 0..3 top (z = 0), 4..7 bottom; x fastest, then y.
	var faces := [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]
	solid(pivot, c, faces, birth, axis, SLAB, tilt, func(pts: Array[Vector3]) -> Color:
		var flat := pts.all(func(p: Vector3) -> bool: return is_zero_approx(p.z))
		return top if flat else side)

## A faceted spike: `sides` around the base, a waist ring, a tip leaning by `lean` (x, y).
func spike(pivot: Vector2, radius: float, tall: float, lean: Vector2, sides: int, seed: float, birth: float, tone: Color) -> void:
	var c: Array[Vector3] = []
	var turn := _h(seed) * TAU
	for i in sides:
		var a := turn + TAU * i / sides
		c.append(Vector3(cos(a), sin(a), 0.0) * radius * (0.8 + 0.4 * _h(seed + i)))
	for i in sides:
		var a := turn + TAU * (i + 0.5) / sides
		var ring := Vector3(cos(a), sin(a), 0.0) * radius * (0.45 + 0.2 * _h(seed + i + 9.0))
		c.append(ring + Vector3(lean.x, lean.y, 0.0) * 0.4 + Vector3(0, 0, tall * (0.42 + 0.15 * _h(seed + i + 5.0))))
	c.append(Vector3(lean.x, lean.y, tall))
	var faces := []
	for i in sides:
		var j := (i + 1) % sides
		faces.append([i, j, sides + i])
		faces.append([j, sides + j, sides + i])
		faces.append([sides + i, sides + j, sides * 2])
	solid(pivot, c, faces, birth, 0.0, SPIKE, tall, func(_pts: Array[Vector3]) -> Color: return tone)

## A crystal: a six-sided prism with a pointed tip, leaning by `lean` (x, y) at the top.
func crystal(pivot: Vector2, radius: float, tall: float, lean: Vector2, seed: float, birth: float, tone: Color) -> void:
	var c: Array[Vector3] = []
	var turn := _h(seed) * TAU
	var shoulder := tall * (0.66 + 0.12 * _h(seed + 1.0))
	for i in 6:
		var a := turn + TAU * i / 6.0
		c.append(Vector3(cos(a), sin(a), 0.0) * radius)
	for i in 6:
		var a := turn + TAU * i / 6.0
		c.append(Vector3(cos(a), sin(a), 0.0) * radius * (0.9 + 0.1 * _h(seed + i)) + Vector3(lean.x, lean.y, 0.0) * (shoulder / tall) + Vector3(0, 0, shoulder))
	c.append(Vector3(lean.x, lean.y, tall))
	var faces := []
	for i in 6:
		var j := (i + 1) % 6
		faces.append([i, j, 6 + j, 6 + i])
		faces.append([6 + i, 6 + j, 12])
	solid(pivot, c, faces, birth, 0.0, CRYSTAL, tall, func(_pts: Array[Vector3]) -> Color: return tone)

## A lumpy boulder: an icosahedron with jittered corners, flattened a little.
func boulder(pivot: Vector2, radius: float, seed: float, birth: float, axis: float, tone: Color) -> void:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var raw := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var c: Array[Vector3] = []
	for i in raw.size():
		var p: Vector3 = (raw[i] as Vector3).normalized() * radius * (0.82 + 0.3 * _h(seed + i * 1.3))
		c.append(Vector3(p.x, p.y, p.z * 0.82))
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	solid(pivot, c, faces, birth, axis, BOULDER, radius, func(_pts: Array[Vector3]) -> Color: return tone)

## One cell of the ground surge: a quad of ground points, each with its own arrival time
## (birth) and arrival-time gradient, swelling by `height` as the front rolls under it.
func surge_cell(screens: Array[Vector2], births: Array[float], gradients: Array[Vector2], heights: Array[float], tone: Color) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		var g := gradients[i].rotated(angle)
		pivots.append(screens[i])
		custom0.append_array(PackedFloat32Array([0.0, 0.0, 0.0, births[i]]))
		custom1.append_array(PackedFloat32Array([g.x, g.y, 0.0, 0.0]))
		uvs.append(Vector2(SURGE, heights[i]))
		colors.append(tone)

func mesh() -> ArrayMesh:
	var result := ArrayMesh.new()
	if pivots.is_empty(): return result
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pivots
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return result

static func _h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)
