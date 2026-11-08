class_name CarDent
extends Node
## Crash damage you can see: the panels around the point of impact bend inward.
## Every car shares one body mesh until its first crash; then it gets its own,
## cut finer so that a fender can crumple rather than tilt as one big triangle.

const MAX_EDGE := 0.24

## Finely cut copy of the shared body, built once: one dictionary per surface.
static var _base: Array[Dictionary] = []

var _car: ArcadeCar
var _body: MeshInstance3D
var _surfaces: Array[Dictionary] = []
var _mesh: ArrayMesh
var _total := 0.0

func _ready() -> void:
	_car = get_parent() as ArcadeCar
	_body = _car.get_node("Body")
	_car.crashed.connect(_on_crash)

func _on_crash(delta_v: float, _injury: float, _glass: int) -> void:
	var k := clampf(inverse_lerp(4.0, 26.0, delta_v), 0.0, 1.0)
	var depth := lerpf(0.05, float(Game.sim.get_tuning("crash", "dent_depth")), k)
	var radius := lerpf(0.5, float(Game.sim.get_tuning("crash", "dent_radius")), k)
	# Past a point the structure has already gone where it can go.
	depth = minf(depth, maxf(0.9 - _total, 0.03))
	_total += depth
	dent(_car.get_impact_point(), _car.get_impact_push(), depth, radius)

## Push the panels within `radius` of `at` along `push`, all in car space.
func dent(at: Vector3, push: Vector3, depth: float, radius: float) -> void:
	if _mesh == null:
		_prepare()
	var r2 := radius * radius
	for s in _surfaces:
		var verts: PackedVector3Array = s.verts
		var normals: PackedVector3Array = s.normals
		var moved := false
		var tri := 0
		while tri < verts.size():
			var hit := false
			for j in 3:
				var p := verts[tri + j]
				var d2 := p.distance_squared_to(at)
				if d2 < r2:
					var w := 1.0 - sqrt(d2) / radius
					w *= w
					# A function of position only, so joined vertices stay joined.
					var n := sin(p.x * 19.0 + p.z * 13.0) * sin(p.y * 27.0 + p.z * 9.0)
					verts[tri + j] = p + push * (depth * w * (0.72 + 0.5 * n)) + Vector3.UP * (depth * w * n * 0.3)
					hit = true
			if hit:
				moved = true
				var fn := (verts[tri + 1] - verts[tri]).cross(verts[tri + 2] - verts[tri])
				if fn.length_squared() > 1e-10:
					fn = fn.normalized()
					if fn.dot(normals[tri]) < 0.0:
						fn = -fn
					normals[tri] = fn
					normals[tri + 1] = fn
					normals[tri + 2] = fn
			tri += 3
		if moved:
			s.verts = verts
			s.normals = normals
	_rebuild()

func _prepare() -> void:
	if _base.is_empty():
		_base = _cut(_body.mesh)
	for s in _base:
		_surfaces.append(s.duplicate())
	_mesh = ArrayMesh.new()
	_rebuild()
	_body.mesh = _mesh

func _rebuild() -> void:
	_mesh.clear_surfaces()
	for s in _surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_COLOR] = s.colors
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_mesh.surface_set_material(_mesh.get_surface_count() - 1, s.material)

## Unindexed copy of a mesh with no triangle edge longer than MAX_EDGE.
static func _cut(m: Mesh) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var iv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var inn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var ic: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var c := PackedColorArray()
		var stack: Array = []
		var i := 0
		while i + 2 < idx.size():
			stack.append([iv[idx[i]], iv[idx[i + 1]], iv[idx[i + 2]], ic[idx[i]], ic[idx[i + 1]], ic[idx[i + 2]], inn[idx[i]]])
			i += 3
			while not stack.is_empty():
				var t: Array = stack.pop_back()
				var p0: Vector3 = t[0]
				var p1: Vector3 = t[1]
				var p2: Vector3 = t[2]
				var e0 := p0.distance_squared_to(p1)
				var e1 := p1.distance_squared_to(p2)
				var e2 := p2.distance_squared_to(p0)
				var longest := maxf(e0, maxf(e1, e2))
				if longest <= MAX_EDGE * MAX_EDGE:
					v.append(p0); v.append(p1); v.append(p2)
					c.append(t[3]); c.append(t[4]); c.append(t[5])
					n.append(t[6]); n.append(t[6]); n.append(t[6])
					continue
				# Split the longest edge in two, keeping the winding.
				var k := 0 if longest == e0 else (1 if longest == e1 else 2)
				var a0: Vector3 = t[k]
				var a1: Vector3 = t[(k + 1) % 3]
				var a2: Vector3 = t[(k + 2) % 3]
				var c0: Color = t[3 + k]
				var c1: Color = t[3 + (k + 1) % 3]
				var c2: Color = t[3 + (k + 2) % 3]
				var mid := (a0 + a1) * 0.5
				var cm := c0.lerp(c1, 0.5)
				stack.append([a0, mid, a2, c0, cm, c2, t[6]])
				stack.append([mid, a1, a2, cm, c1, c2, t[6]])
		out.append({"verts": v, "normals": n, "colors": c, "material": m.surface_get_material(si)})
	return out
