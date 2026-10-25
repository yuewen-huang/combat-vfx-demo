extends RefCounted
## Static meshes for the parts of a ground impact that can be laid out once and moved by the
## clock alone: cracks (shaders/cracks.gdshader), dust and light particles
## (shaders/sprites.gdshader) and molten / frozen ground patches (shaders/patches.gdshader).
## Each builder records everything a vertex needs; the CPU never touches them again.

## Shared mesh assembly for the builders below.
class Builder:
	static func _mesh(points: PackedVector2Array, uvs: PackedVector2Array, colors: PackedColorArray, custom0: PackedFloat32Array, custom1: PackedFloat32Array) -> ArrayMesh:
		var result := ArrayMesh.new()
		if points.is_empty(): return result
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		if not uvs.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = uvs
		if not colors.is_empty(): arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_CUSTOM0] = custom0
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if not custom1.is_empty():
			arrays[Mesh.ARRAY_CUSTOM1] = custom1
			flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		return result

## Crack strips: every point carries its arrival time; the shader opens the crack as the
## front passes and lets it glow and cool.
## Per vertex: VERTEX on the crack's centre line; CUSTOM0 (normal x, y, width, arrival);
## CUSTOM1 (side −1 / 1, 0, 0, 0).
class Strips extends Builder:
	var points := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()

	func crack(pts: PackedVector2Array, widths: PackedFloat32Array, arrivals: PackedFloat32Array) -> void:
		var n := pts.size()
		if n < 2: return
		var normals := PackedVector2Array()
		for i in n:
			var d := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
			normals.append(d.orthogonal().normalized() if d.length() > 0.0001 else Vector2.UP)
		for i in n - 1:
			for k: Array in [[i, -1.0], [i + 1, -1.0], [i + 1, 1.0], [i, -1.0], [i + 1, 1.0], [i, 1.0]]:
				var j: int = k[0]
				points.append(pts[j])
				custom0.append_array(PackedFloat32Array([normals[j].x, normals[j].y, widths[j], arrivals[j]]))
				custom1.append_array(PackedFloat32Array([k[1], 0.0, 0.0, 0.0]))

	func mesh() -> ArrayMesh:
		return _mesh(points, PackedVector2Array(), PackedColorArray(), custom0, custom1)

## Sprites: camera-facing quads, each moving by a formula of its kind.
## Per vertex: VERTEX start point; UV corner 0–1; CUSTOM0 (birth, span, size, kind);
## CUSTOM1 kind parameters; COLOR value-encoded tone (alpha = strength).
## Kinds: 0 dust billow, 1 dust skirt (CUSTOM1: out direction x, y, rise, seed);
## 2 rising light halo, 3 its bright core (CUSTOM1: drift x, y px/s, rise px/s, phase;
## COLOR.b: sideways sway px / 40); 4 ballistic streak, 5 its halo (CUSTOM1: drift x, y,
## upward speed, tail seconds); 6 ground stain (grows in over 0.1 s).
## (CUSTOM1: drift x, y px/s, orbit radius, seed).
class Sprites extends Builder:
	var points := PackedVector2Array()
	var corners := PackedVector2Array()
	var colors := PackedColorArray()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()

	func add(at: Vector2, birth: float, span: float, size: float, kind: int, params: Vector4, tone: Color) -> void:
		for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			points.append(at)
			corners.append(c)
			colors.append(tone)
			custom0.append_array(PackedFloat32Array([birth, span, size, kind]))
			custom1.append_array(PackedFloat32Array([params.x, params.y, params.z, params.w]))

	func mesh() -> ArrayMesh:
		return _mesh(points, corners, colors, custom0, custom1)

## Ground patches (scorched lava pools, frozen sheets): a wobbly outline fanned from its
## centre, growing from the centre after its birth. Rims first, so neighbours merge.
## Per vertex: VERTEX patch centre; CUSTOM0 (offset x, y at full size, birth, 0 rim / 1 pool).
class Patches extends Builder:
	var rims := []
	var pools := []

	func patch(center: Vector2, rim: PackedVector2Array, pool: PackedVector2Array, birth: float) -> void:
		rims.append([center, rim, birth])
		pools.append([center, pool, birth])

	func mesh() -> ArrayMesh:
		var points := PackedVector2Array()
		var custom0 := PackedFloat32Array()
		for group: Array in [[rims, 0.0], [pools, 1.0]]:
			for item: Array in group[0]:
				var center: Vector2 = item[0]
				var outline: PackedVector2Array = item[1]
				for i in outline.size():
					var a := outline[i] - center
					var b := outline[(i + 1) % outline.size()] - center
					for o in [Vector2.ZERO, a, b]:
						points.append(center)
						custom0.append_array(PackedFloat32Array([o.x, o.y, item[2], group[1]]))
		return _mesh(points, PackedVector2Array(), PackedColorArray(), custom0, PackedFloat32Array())
