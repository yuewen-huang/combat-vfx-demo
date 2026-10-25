extends RefCounted
## Flying chunks (stone, ice shards) as one static mesh per effect, thrown, spun, landed and
## faded by shaders/chunks.gdshader from the event clock. Built once; the CPU only sets time.
##
## Per vertex: VERTEX start point on screen; CUSTOM0 (x, y, z around the chunk centre, birth);
## CUSTOM1 (drift x, drift y on the ground in px/s, upward speed px/s, spin rad/s);
## COLOR (normal × 0.5 + 0.5, kind: 0 stone, 1 ice). Material look comes from
## uniforms.

var starts := PackedVector2Array()
var custom0 := PackedFloat32Array()
var custom1 := PackedFloat32Array()
var colors := PackedColorArray()
## Ground rotation of the effect (radians), baked into drift, positions and normals.
var angle := 0.0

## An irregular eight-faced lump `size` across; `ice` makes it a long thin shard.
func chunk(start: Vector2, size: float, seed: float, birth: float, drift: Vector2, rise: float, spin: float, ice: bool) -> void:
	# Ice is a long shard, stone a lump.
	var stretch := Vector3(0.45, 0.45, 1.6) if ice else Vector3(1.0, 0.85, 0.8)
	var c: Array[Vector3] = []
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var jitter := 0.7 + 0.5 * _h(seed + c.size() * 1.7)
		var p: Vector3 = d * stretch * size * 0.5 * jitter
		var xy := Vector2(p.x, p.y).rotated(angle + _h(seed) * TAU)
		c.append(Vector3(xy.x, xy.y, p.z))
	var faces := [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]]
	var flow := drift.rotated(angle)
	for f: Array in faces:
		var a: Vector3 = c[f[0]]
		var b: Vector3 = c[f[1]]
		var e: Vector3 = c[f[2]]
		var n := (b - a).cross(e - a).normalized()
		if n.dot((a + b + e) / 3.0) < 0.0:
			n = -n
			var swap := b
			b = e
			e = swap
		var tone := Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0 if ice else 0.0)
		for p in [a, b, e]:
			starts.append(start)
			custom0.append_array(PackedFloat32Array([p.x, p.y, p.z, birth]))
			custom1.append_array(PackedFloat32Array([flow.x, flow.y, rise, spin]))
			colors.append(tone)

func mesh() -> ArrayMesh:
	var result := ArrayMesh.new()
	if starts.is_empty(): return result
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = starts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return result

static func _h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)
