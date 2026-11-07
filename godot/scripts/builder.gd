class_name Builder
## Thin GDScript DSL over the Rust KitBuilder, plus factories for reusable
## kit pieces (characters, the car, props). Geometry is batched per chunk:
## one MeshInstance3D with one surface per material, one StaticBody3D.

const P = preload("res://scripts/palette.gd")

var kit: KitBuilder

func _init(ao := 0.3) -> void:
	kit = KitBuilder.new()
	kit.set_ao_strength(ao)

static func xf(pos: Vector3, rot_y := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot_y), pos)

## Box centred at pos.
func box(slot: int, pos: Vector3, size: Vector3, solid := true, rot_y := 0.0) -> void:
	var t := xf(pos, rot_y)
	kit.add_box(slot, t, size)
	if solid:
		kit.add_collider(t, size)

## Box from a bottom-corner style: base centre on the ground.
func block(slot: int, base: Vector3, size: Vector3, solid := true, rot_y := 0.0) -> void:
	box(slot, base + Vector3(0, size.y * 0.5, 0), size, solid, rot_y)

func box_xf(slot: int, t: Transform3D, size: Vector3, solid := false) -> void:
	kit.add_box(slot, t, size)
	if solid:
		kit.add_collider(t, size)

func cyl(slot: int, pos: Vector3, r_bot: float, r_top: float, h: float, seg := 16, solid := false, caps := true) -> void:
	kit.add_cylinder(slot, xf(pos), r_bot, r_top, h, seg, caps)
	if solid:
		var r := maxf(r_bot, r_top) * 0.82
		kit.add_collider(xf(pos), Vector3(r * 2.0, h, r * 2.0))
		kit.add_collider(xf(pos, PI / 4.0), Vector3(r * 2.0, h, r * 2.0))

func cyl_xf(slot: int, t: Transform3D, r_bot: float, r_top: float, h: float, seg := 16, caps := true) -> void:
	kit.add_cylinder(slot, t, r_bot, r_top, h, seg, caps)

## Ramp rising toward +Z (in its own yaw frame). Collider is a rotated slab.
func ramp(slot: int, pos: Vector3, size: Vector3, rot_y := 0.0, solid := true) -> void:
	kit.add_ramp(slot, xf(pos, rot_y), size)
	if solid:
		var ang := atan2(size.y, size.z)
		var len := sqrt(size.y * size.y + size.z * size.z)
		var th := 0.4
		var b := Basis(Vector3.UP, rot_y) * Basis(Vector3.RIGHT, -ang)
		var centre := pos + Basis(Vector3.UP, rot_y) * Vector3(0, size.y * 0.5, 0) - b.y * th * 0.5
		kit.add_collider(Transform3D(b, centre), Vector3(size.x, th, len))
		# Fill under the ramp so nothing slips beneath.
		kit.add_collider(xf(pos + Basis(Vector3.UP, rot_y) * Vector3(0, size.y * 0.25, size.z * 0.25), rot_y), Vector3(size.x, size.y * 0.5, size.z * 0.5))

## Stairs from pos rising along +Z (yaw frame), `steps` treads. With
## `ramp_collider` the treads are visual only and a smooth slab collides,
## so NPCs (no step-up) can climb them too.
func stairs(slot: int, pos: Vector3, width: float, rise: float, run: float, steps: int, rot_y := 0.0, ramp_collider := false) -> void:
	var b := Basis(Vector3.UP, rot_y)
	for i in steps:
		var h := rise * (i + 1)
		var c := pos + b * Vector3(0, h * 0.5, run * (i + 0.5))
		box(slot, c, Vector3(width, h, run), not ramp_collider, rot_y)
	if ramp_collider:
		var total_h := rise * steps
		var total_l := run * steps
		var ang := atan2(total_h, total_l)
		var len := sqrt(total_h * total_h + total_l * total_l)
		var th := 0.3
		var rb := b * Basis(Vector3.RIGHT, -ang)
		var centre := pos + b * Vector3(0, total_h * 0.5, total_l * 0.5) - rb.y * th * 0.5
		kit.add_collider(Transform3D(rb, centre), Vector3(width, th, len))

## Wall along X from x0..x1 at z, with door/window gaps [[a, b, gap_bottom, gap_top]].
func wall_x(slot: int, x0: float, x1: float, z: float, y0: float, h: float, t: float, gaps := []) -> void:
	_wall(slot, x0, x1, z, y0, h, t, gaps, false)

func wall_z(slot: int, z0: float, z1: float, x: float, y0: float, h: float, t: float, gaps := []) -> void:
	_wall(slot, z0, z1, x, y0, h, t, gaps, true)

func _wall(slot: int, a0: float, a1: float, c: float, y0: float, h: float, t: float, gaps: Array, along_z: bool) -> void:
	var cuts := gaps.duplicate()
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var cur := a0
	for g in cuts:
		if g[0] > cur:
			_wseg(slot, cur, g[0], c, y0, h, t, along_z)
		var gb: float = g[2] if g.size() > 2 else 0.0
		var gt: float = g[3] if g.size() > 3 else h
		if gb > 0.0:
			_wseg(slot, g[0], g[1], c, y0, gb, t, along_z)
		if gt < h:
			_wseg(slot, g[0], g[1], c, y0 + gt, h - gt, t, along_z)
		cur = g[1]
	if cur < a1:
		_wseg(slot, cur, a1, c, y0, h, t, along_z)

func _wseg(slot: int, a: float, b: float, c: float, y0: float, h: float, t: float, along_z: bool) -> void:
	var mid := (a + b) * 0.5
	var len := b - a
	if along_z:
		box(slot, Vector3(c, y0 + h * 0.5, mid), Vector3(t, h, len))
	else:
		box(slot, Vector3(mid, y0 + h * 0.5, c), Vector3(len, h, t))

func commit(parent: Node3D, name: String, vis_range := 0.0) -> MeshInstance3D:
	var mi := kit.commit(parent, P.mats(), name, 1)
	if vis_range > 0.0:
		mi.visibility_range_end = vis_range
	return mi

func mesh() -> ArrayMesh:
	var m := kit.build_mesh(P.mats())
	kit.clear()
	return m

# ------------------------------------------------------------- multimesh

static func scatter(parent: Node3D, m: Mesh, xforms: Array, vis_range := 0.0, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if vis_range > 0.0:
		mmi.visibility_range_end = vis_range
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi

# ------------------------------------------------------------- prop meshes

static var _cache := {}

static func cached(key: String, f: Callable) -> Mesh:
	if not _cache.has(key):
		_cache[key] = f.call()
	return _cache[key]

static func lamp_post() -> Mesh:
	return cached("lamp", func():
		var b := Builder.new(0.2)
		b.cyl(P.CHARCOAL, Vector3(0, 0.2, 0), 0.22, 0.18, 0.4, 8)
		b.cyl(P.STEEL, Vector3(0, 2.6, 0), 0.08, 0.06, 4.8, 8)
		b.box(P.CHARCOAL, Vector3(0.45, 5.0, 0), Vector3(1.1, 0.12, 0.18), false)
		b.cyl(P.CHARCOAL, Vector3(0.9, 4.9, 0), 0.32, 0.14, 0.22, 12)
		b.cyl(P.LAMP, Vector3(0.9, 4.76, 0), 0.24, 0.24, 0.06, 12)
		return b.mesh())

static func banner_pole() -> Mesh:
	return cached("banner", func():
		var b := Builder.new(0.15)
		b.cyl(P.STEEL, Vector3(0, 3.5, 0), 0.06, 0.05, 7.0, 6)
		b.box(P.CHARCOAL, Vector3(0.45, 6.9, 0), Vector3(1.0, 0.08, 0.08), false)
		b.box(P.BANNER, Vector3(0.45, 5.4, 0), Vector3(0.9, 2.9, 0.03), false)
		b.cyl(P.BRASS, Vector3(0.45, 5.9, 0.02), 0.2, 0.2, 0.02, 12)
		return b.mesh())

static func tree() -> Mesh:
	return cached("tree", func():
		var b := Builder.new(0.35)
		b.cyl(P.WALNUT, Vector3(0, 1.4, 0), 0.18, 0.12, 2.8, 6)
		b.cyl(P.FOLIAGE, Vector3(0, 3.3, 0), 1.6, 1.1, 1.6, 7)
		b.cyl(P.FOLIAGE, Vector3(0.3, 4.4, 0.2), 1.2, 0.5, 1.4, 7)
		b.cyl(P.FOLIAGE, Vector3(-0.2, 2.6, -0.3), 1.3, 1.5, 0.8, 7)
		return b.mesh())

static func planter() -> Mesh:
	return cached("planter", func():
		var b := Builder.new(0.3)
		b.box(P.CONCRETE_PALE, Vector3(0, 0.35, 0), Vector3(0.9, 0.7, 0.9), false)
		for i in 5:
			var a := i * TAU / 5.0
			var t := Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.5), Vector3(cos(a) * 0.15, 1.1, sin(a) * 0.15))
			b.box_xf(P.FOLIAGE, t, Vector3(0.16, 1.1, 0.02))
		b.cyl(P.FOLIAGE, Vector3(0, 1.0, 0), 0.35, 0.5, 0.8, 6)
		return b.mesh())

static func facade_fin() -> Mesh:
	return cached("fin", func():
		var b := Builder.new(0.2)
		b.box(P.CONCRETE_PALE, Vector3(0, 0, 0), Vector3(0.5, 1.0, 1.2), false)
		return b.mesh())

static func stall() -> Mesh:
	return cached("stall", func():
		var b := Builder.new(0.3)
		b.box(P.WALNUT, Vector3(0, 0.5, 0), Vector3(2.4, 1.0, 1.0), false)
		for x in [-1.15, 1.15]:
			for z in [-0.45, 0.45]:
				b.cyl(P.STEEL, Vector3(x, 1.3, z), 0.04, 0.04, 2.6, 6)
		var t := Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 2.55, 0.1))
		b.box_xf(P.BANNER, t, Vector3(2.7, 0.05, 1.6))
		b.box(P.BEIGE, Vector3(-0.6, 1.15, 0), Vector3(0.5, 0.3, 0.4), false)
		b.box(P.TERRACOTTA, Vector3(0.4, 1.12, 0.1), Vector3(0.6, 0.25, 0.5), false)
		b.cyl(P.BRASS, Vector3(0.9, 1.1, -0.1), 0.14, 0.12, 0.2, 8)
		return b.mesh())

static func crate() -> Mesh:
	return cached("crate", func():
		var b := Builder.new(0.25)
		b.box(P.WARM_GREY, Vector3(0, 0.55, 0), Vector3(1.1, 1.1, 1.1), false)
		b.box(P.CHARCOAL, Vector3(0, 0.55, 0), Vector3(1.14, 0.12, 1.14), false)
		return b.mesh())

static func cone() -> Mesh:
	return cached("cone", func():
		var b := Builder.new(0.1)
		b.box(P.CHARCOAL, Vector3(0, 0.03, 0), Vector3(0.5, 0.06, 0.5), false)
		b.cyl(P.TERRACOTTA, Vector3(0, 0.4, 0), 0.2, 0.04, 0.7, 8)
		return b.mesh())

static func chair() -> Mesh:
	return cached("chair", func():
		var b := Builder.new(0.25)
		b.box(P.LEATHER, Vector3(0, 0.45, 0), Vector3(0.8, 0.22, 0.75), false)
		b.box(P.LEATHER, Vector3(0, 0.85, 0.32), Vector3(0.8, 0.65, 0.16), false)
		b.box(P.LEATHER, Vector3(-0.38, 0.65, 0), Vector3(0.12, 0.3, 0.7), false)
		b.box(P.LEATHER, Vector3(0.38, 0.65, 0), Vector3(0.12, 0.3, 0.7), false)
		b.cyl(P.CHROME, Vector3(0, 0.17, 0), 0.32, 0.05, 0.3, 10)
		return b.mesh())

static func bench() -> Mesh:
	return cached("bench", func():
		var b := Builder.new(0.25)
		for x in [-0.8, 0.8]:
			b.box(P.CHARCOAL, Vector3(x, 0.22, 0), Vector3(0.08, 0.44, 0.5), false)
		for i in 3:
			b.box(P.WALNUT, Vector3(0, 0.46, -0.16 + i * 0.16), Vector3(1.9, 0.05, 0.13), false)
		for i in 2:
			b.box(P.WALNUT, Vector3(0, 0.7 + i * 0.18, 0.27), Vector3(1.9, 0.12, 0.04), false)
		return b.mesh())

static func bin() -> Mesh:
	return cached("bin", func():
		var b := Builder.new(0.25)
		b.cyl(P.CHARCOAL, Vector3(0, 0.45, 0), 0.26, 0.28, 0.9, 10)
		b.cyl(P.STEEL, Vector3(0, 0.92, 0), 0.3, 0.3, 0.05, 10)
		b.box(P.AMBER, Vector3(0, 0.7, 0.27), Vector3(0.12, 0.04, 0.02), false)
		return b.mesh())

## Cassette-age public phone: beige booth, charcoal hood, amber call lamp.
static func phone_booth() -> Mesh:
	return cached("phone", func():
		var b := Builder.new(0.3)
		b.box(P.CHARCOAL, Vector3(0, 1.2, -0.42), Vector3(1.0, 2.4, 0.08), false)
		b.box(P.BEIGE, Vector3(0, 1.3, -0.33), Vector3(0.5, 0.7, 0.12), false)
		b.box(P.BLACK, Vector3(0, 1.45, -0.26), Vector3(0.3, 0.16, 0.02), false)
		b.box(P.CRT, Vector3(0, 1.45, -0.255), Vector3(0.24, 0.1, 0.01), false)
		b.box(P.CHARCOAL, Vector3(-0.18, 1.18, -0.24), Vector3(0.08, 0.28, 0.08), false)
		for x in [-0.5, 0.5]:
			b.box(P.STEEL, Vector3(x, 1.2, 0), Vector3(0.05, 2.4, 0.9), false)
		b.box(P.CHARCOAL, Vector3(0, 2.45, 0), Vector3(1.15, 0.12, 1.0), false)
		b.box(P.AMBER, Vector3(0, 2.55, 0.0), Vector3(0.3, 0.08, 0.3), false)
		return b.mesh())

static func bollard() -> Mesh:
	return cached("bollard", func():
		var b := Builder.new(0.2)
		b.cyl(P.CONCRETE_PALE, Vector3(0, 0.45, 0), 0.16, 0.13, 0.9, 8)
		b.cyl(P.CHARCOAL, Vector3(0, 0.78, 0), 0.14, 0.14, 0.06, 8)
		return b.mesh())

static func kiosk() -> Mesh:
	return cached("kiosk", func():
		var b := Builder.new(0.3)
		b.box(P.TEAL, Vector3(0, 1.1, 0), Vector3(2.2, 2.2, 1.6), false)
		b.box(P.CHARCOAL, Vector3(0, 2.3, 0.2), Vector3(2.6, 0.12, 2.2), false)
		b.box(P.WINDOWS, Vector3(0, 1.4, 0.81), Vector3(1.8, 0.8, 0.02), false)
		b.box(P.IVORY, Vector3(-0.5, 0.75, 0.83), Vector3(0.6, 0.5, 0.02), false)
		b.box(P.BURGUNDY, Vector3(0.4, 0.75, 0.83), Vector3(0.5, 0.5, 0.02), false)
		b.box(P.BEIGE, Vector3(0, 2.6, 0.2), Vector3(1.6, 0.4, 0.1), false)
		return b.mesh())

static func ac_unit() -> Mesh:
	return cached("ac", func():
		var b := Builder.new(0.3)
		b.box(P.BEIGE, Vector3(0, 0, 0), Vector3(0.9, 0.6, 0.55), false)
		b.cyl_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.12, 0, 0.28)), 0.22, 0.22, 0.02, 12)
		for i in 4:
			b.box(P.CHARCOAL, Vector3(-0.32, -0.18 + i * 0.12, 0.28), Vector3(0.18, 0.03, 0.02), false)
		return b.mesh())

static func water_tank() -> Mesh:
	return cached("tank", func():
		var b := Builder.new(0.3)
		for x in [-0.9, 0.9]:
			for z in [-0.9, 0.9]:
				b.box(P.CHARCOAL, Vector3(x, 0.9, z), Vector3(0.12, 1.8, 0.12), false)
		b.cyl(P.STEEL, Vector3(0, 2.9, 0), 1.3, 1.3, 2.2, 14)
		b.cyl(P.CONCRETE_PALE, Vector3(0, 4.3, 0), 1.4, 0.2, 0.6, 14)
		return b.mesh())

static func antenna() -> Mesh:
	return cached("antenna", func():
		var b := Builder.new(0.1)
		b.cyl(P.STEEL, Vector3(0, 3.0, 0), 0.06, 0.03, 6.0, 5)
		for i in 4:
			b.box(P.STEEL, Vector3(0, 2.5 + i * 0.9, 0), Vector3(1.6 - i * 0.3, 0.04, 0.04), false)
		b.cyl(P.STEEL, Vector3(0.5, 4.2, 0), 0.5, 0.5, 0.06, 14)
		b.cyl(P.AMBER, Vector3(0, 6.05, 0), 0.08, 0.08, 0.1, 6)
		return b.mesh())

static func hedge() -> Mesh:
	return cached("hedge", func():
		var b := Builder.new(0.35)
		b.box(P.CONCRETE_PALE, Vector3(0, 0.2, 0), Vector3(4.0, 0.4, 0.9), false)
		b.box(P.FOLIAGE, Vector3(0, 0.75, 0), Vector3(3.8, 0.7, 0.75), false)
		return b.mesh())

## "Cassette eye": wall-mounted camera on a bracket, amber tally lamp.
static func wall_camera() -> Mesh:
	return cached("wallcam", func():
		var b := Builder.new(0.2)
		b.box(P.CHARCOAL, Vector3(0, 0, 0.15), Vector3(0.06, 0.06, 0.3), false)
		var t := Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, -0.06, 0.38))
		b.box_xf(P.BEIGE, t, Vector3(0.18, 0.16, 0.36))
		b.cyl_xf(P.BLACK, Transform3D(Basis(Vector3.RIGHT, PI / 2 - 0.35), Vector3(0, -0.13, 0.57)), 0.06, 0.06, 0.04, 10)
		b.box(P.AMBER, Vector3(0.07, -0.0, 0.5), Vector3(0.025, 0.025, 0.025), false)
		return b.mesh())

## Coil of wire for wall tops (rings of thin cylinders), 4 m long.
static func wire_coil() -> Mesh:
	return cached("wire", func():
		var b := Builder.new(0.0)
		for i in 14:
			var t := Transform3D(Basis(Vector3.FORWARD, PI / 2).rotated(Vector3.UP, 0.25), Vector3(-2.0 + i * 0.29, 0.25, 0))
			b.cyl_xf(P.STEEL, t, 0.26, 0.26, 0.012, 10, false)
		return b.mesh())

# ------------------------------------------------------------- characters

## An animated humanoid body (NpcBody: library skeleton, BodyKit parts).
## kind: guard, governor, courier, civilian.
static func humanoid(kind: String, tint := 0) -> Node3D:
	return NpcBody.create(kind, tint)

static func make_npc(kind: String, pos: Vector3, tint := 0) -> Npc:
	var n := Npc.new()
	n.role = kind
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	n.add_child(shape)
	n.add_child(humanoid(kind, tint))
	n.set_meta("tint", tint)
	n.position = pos
	return n

# ------------------------------------------------------------- vehicle

## 1980s boxy executive sedan, cassette-futurist trim. ~2k tris.
## The drivable car: the Kestrel 80, a mid-engined wedge (INVENTED make;
## the shape is inspired by the 1968 Bertone Carabo concept). Body in car
## space: front is -Z, ground at y = -0.23, wheels at x +-0.8, z +-1.38.
static var _paints := {}

## Kestrel body paint in another colour: the CAR_PAINT surfaces get a
## per-colour copy of the lacquer (shared between cars of that colour).
static func paint_car(car: Node3D, paint: Color) -> void:
	var mi := car.get_node_or_null("Body") as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var base: Material = P.mats()[P.CAR_PAINT]
	if not _paints.has(paint):
		var m := base.duplicate() as ShaderMaterial
		m.set_shader_parameter("albedo", paint)
		_paints[paint] = m
	for i in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_material(i) == base:
			mi.set_surface_override_material(i, _paints[paint])

static func make_car(_body_slot := P.CAR_PAINT) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.name = "Car"
	car.add_to_group("cars")
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.74, 0.5, 4.3)
	col.shape = bs
	col.position = Vector3(0, 0.38, 0)
	car.add_child(col)
	var col2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(1.4, 0.36, 1.7)
	col2.shape = bs2
	col2.position = Vector3(0, 0.8, 0.15)
	car.add_child(col2)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = wedge_body_mesh()
	car.add_child(mi)
	var wheel_mesh := car_wheel_mesh()
	for n in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var w := Node3D.new()
		w.name = n
		var x := -0.8 if n.ends_with("L") else 0.8
		var z := -1.38 if n.contains("F") else 1.38
		w.position = Vector3(x, 0.55, z)
		var wm := MeshInstance3D.new()
		wm.mesh = wheel_mesh
		w.add_child(wm)
		car.add_child(w)
	var cockpit := CarCockpit.new()
	cockpit.name = "Cockpit"
	car.add_child(cockpit)
	return car

## Loft helper: profile points are (z, y, half_width).
func loft(slot: int, pts: Array, t := Transform3D(), open_edge := -1) -> void:
	var a := PackedVector3Array()
	for p in pts:
		a.append(p)
	kit.add_loft(slot, t, a, open_edge)

static func wedge_body_mesh() -> Mesh:
	return cached("wedge", func():
		var b := Builder.new(0.2)
		# Orange knife-edge nose.
		b.loft(P.CAR_ORANGE, [Vector3(-2.22, 0.24, 0.76), Vector3(-1.9, 0.312, 0.8), Vector3(-1.9, 0.169, 0.8), Vector3(-2.12, 0.16, 0.78)])
		# Main wedge: one straight line from the nose to the tail, split so the
		# cabin is open: bonnet, two door pods, rear quarter.
		b.loft(P.CAR_PAINT, [Vector3(-1.9, 0.312, 0.8), Vector3(-0.8, 0.56, 0.86), Vector3(-0.8, 0.221, 0.86), Vector3(-1.9, 0.169, 0.8)])
		for sx in [-1.0, 1.0]:
			b.loft(P.CAR_PAINT, [Vector3(-0.8, 0.56, 0.12), Vector3(0.55, 0.625, 0.12), Vector3(0.55, 0.285, 0.12), Vector3(-0.8, 0.221, 0.12)],
				Transform3D(Basis(), Vector3(sx * 0.74, 0, 0)))
			# Sill under the door.
			b.box(P.CAR_PAINT, Vector3(sx * 0.74, 0.1, -0.12), Vector3(0.24, 0.26, 1.34), false)
		b.loft(P.CAR_PAINT, [Vector3(0.55, 0.625, 0.85), Vector3(2.1, 0.7, 0.84), Vector3(2.14, 0.36, 0.86), Vector3(0.55, 0.285, 0.85)])
		# Valances: chin under the nose, diffuser behind the rear wheels.
		b.loft(P.CAR_ORANGE, [Vector3(-2.12, 0.17, 0.78), Vector3(-1.76, 0.2, 0.8), Vector3(-1.76, 0.0, 0.76), Vector3(-2.02, 0.03, 0.72)])
		b.box(P.BLACK, Vector3(0, 0.07, -2.0), Vector3(1.2, 0.03, 0.12), false)
		b.loft(P.BLACK, [Vector3(1.76, 0.36, 0.84), Vector3(2.14, 0.37, 0.86), Vector3(2.08, 0.03, 0.8), Vector3(1.76, 0.03, 0.8)])
		for sx in [-0.3, -0.1, 0.1, 0.3]:
			b.box(P.CHARCOAL, Vector3(sx, 0.12, 2.1), Vector3(0.025, 0.16, 0.08), false)
		# Floor pan and dark underside.
		b.box(P.BLACK, Vector3(0, -0.03, 0), Vector3(1.24, 0.1, 4.0), false)
		# Canopy: copper-tinted glass running almost flush with the bonnet line.
		b.loft(P.CAR_GLASS, [Vector3(-0.8, 0.555, 0.84), Vector3(0.05, 0.97, 0.66), Vector3(0.55, 0.99, 0.64), Vector3(0.55, 0.62, 0.85)], Transform3D(), 3)
		# Roof panel and canopy frame.
		var roof_ang := atan2(0.02, 0.5)
		b.box_xf(P.CAR_PAINT, Transform3D(Basis(Vector3.RIGHT, -roof_ang), Vector3(0, 0.99, 0.3)), Vector3(1.2, 0.025, 0.5))
		for sx in [-1.0, 1.0]:
			var p0 := Vector3(0.84 * sx, 0.56, -0.8)
			var p1 := Vector3(0.66 * sx, 0.975, 0.05)
			b.box_xf(P.BLACK, Transform3D(Basis.looking_at(p1 - p0), (p0 + p1) * 0.5), Vector3(0.035, 0.035, p0.distance_to(p1)))
			var q0 := Vector3(0.85 * sx, 0.62, 0.55)
			var q1 := Vector3(0.64 * sx, 0.99, 0.55)
			b.box_xf(P.CAR_PAINT, Transform3D(Basis.looking_at(q1 - q0), (q0 + q1) * 0.5), Vector3(0.06, 0.06, q0.distance_to(q1)))
		# Engine cover with black louvres.
		b.loft(P.CAR_PAINT, [Vector3(0.55, 0.62, 0.85), Vector3(0.55, 0.99, 0.62), Vector3(1.0, 0.92, 0.66),
			Vector3(2.1, 0.72, 0.82), Vector3(2.1, 0.66, 0.84)])
		var slope := 0.2 / 1.1
		for i in 7:
			var z := 1.05 + i * 0.15
			var y := 0.92 - slope * (z - 1.0) + 0.012
			b.box_xf(P.BLACK, Transform3D(Basis(Vector3.RIGHT, atan(slope)), Vector3(0, y, z)), Vector3(1.0, 0.012, 0.07))
		# Bonnet louvres (the twin vents ahead of the canopy).
		var hs := (0.56 - 0.312) / 1.1
		for sx in [-0.42, 0.42]:
			for i in 4:
				var z := -1.55 + i * 0.12
				var y := 0.312 + hs * (z + 1.9) + 0.008
				b.box_xf(P.BLACK, Transform3D(Basis(Vector3.RIGHT, -atan(hs)), Vector3(sx, y, z)), Vector3(0.42, 0.01, 0.05))
		# Lamp slot across the nose, orange tail panel with square lamps.
		b.box(P.BLACK, Vector3(0, 0.23, -2.14), Vector3(1.3, 0.035, 0.06), false)
		for sx in [-0.55, 0.55]:
			b.box(P.LAMP, Vector3(sx, 0.232, -2.165), Vector3(0.3, 0.025, 0.02), false)
			b.box(P.AMBER, Vector3(sx * 1.38, 0.2, -2.1), Vector3(0.1, 0.03, 0.04), false)
		b.box(P.BLACK, Vector3(0, 0.53, 2.15), Vector3(1.64, 0.28, 0.04), false)
		for i in 9:
			b.box(P.CHARCOAL, Vector3(0, 0.42 + i * 0.026, 2.172), Vector3(0.9, 0.01, 0.01), false)
		for sx in [-1.0, 1.0]:
			for k in 2:
				b.box(P.BURGUNDY, Vector3(sx * (0.56 + k * 0.14), 0.55, 2.175), Vector3(0.11, 0.11, 0.02), false)
				b.box(P.LAMP if k == 0 else P.AMBER, Vector3(sx * (0.56 + k * 0.14), 0.55, 2.188), Vector3(0.07, 0.07, 0.01), false)
		b.box(P.CAR_ORANGE, Vector3(0, 0.33, 2.15), Vector3(1.7, 0.06, 0.05), false)
		# Side intake and orange pinstripe.
		for sx in [-1.0, 1.0]:
			b.box(P.BLACK, Vector3(sx * 0.86, 0.5, 0.95), Vector3(0.02, 0.1, 0.5), false)
			b.box_xf(P.CAR_ORANGE, Transform3D(Basis.looking_at(Vector3(0, 0.39, 4.0)), Vector3(sx * 0.845, 0.38, 0.1)), Vector3(0.012, 0.025, 4.0))
			# Mirror.
			b.box(P.BLACK, Vector3(sx * 0.9, 0.66, -0.55), Vector3(0.12, 0.06, 0.03), false)
		return b.mesh())

static func car_wheel_mesh() -> Mesh:
	return cached("wheel", func():
		var b := Builder.new(0.0)
		var t := Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3.ZERO)
		b.cyl_xf(P.TYRE, t, 0.36, 0.36, 0.26, 14)
		b.cyl_xf(P.STEEL, t, 0.22, 0.22, 0.28, 8)
		return b.mesh())

## Static parked car: body plus wheels at rest height, one node.
static func car_prop(body_slot := P.CHARCOAL) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = car_body_mesh(body_slot)
	n.add_child(mi)
	for x in [-0.8, 0.8]:
		for z in [-1.38, 1.38]:
			var wm := MeshInstance3D.new()
			wm.mesh = car_wheel_mesh()
			wm.position = Vector3(x, 0.13, z)
			n.add_child(wm)
	return n

static func car_body_mesh(body_slot: int) -> Mesh:
	return cached("car_%d" % body_slot, func():
		var b := Builder.new(0.25)
		b.box(body_slot, Vector3(0, 0.55, 0), Vector3(1.86, 0.55, 4.45), false)
		b.box(body_slot, Vector3(0, 0.88, -1.55), Vector3(1.84, 0.12, 1.3), false)
		b.box(body_slot, Vector3(0, 0.88, 1.75), Vector3(1.84, 0.12, 0.95), false)
		# Cabin: windscreen and rear screen as ramps, flat roof.
		b.kit.add_ramp(P.GLASS, Transform3D(Basis(), Vector3(0, 0.94, -0.65)), Vector3(1.62, 0.48, 0.55))
		b.kit.add_ramp(P.GLASS, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.94, 1.15)), Vector3(1.62, 0.48, 0.45))
		b.box(body_slot, Vector3(0, 1.45, 0.25), Vector3(1.62, 0.08, 1.35), false)
		b.box(P.GLASS, Vector3(-0.8, 1.18, 0.25), Vector3(0.03, 0.46, 1.32), false)
		b.box(P.GLASS, Vector3(0.8, 1.18, 0.25), Vector3(0.03, 0.46, 1.32), false)
		for x in [-0.79, 0.79]:
			b.box(P.CHARCOAL, Vector3(x, 1.18, 0.25), Vector3(0.05, 0.5, 0.08), false)
		# Chrome bumpers, black rubbing strip, grille, lamps.
		b.box(P.CHROME, Vector3(0, 0.42, -2.26), Vector3(1.9, 0.16, 0.12), false)
		b.box(P.CHROME, Vector3(0, 0.42, 2.26), Vector3(1.9, 0.16, 0.12), false)
		b.box(P.BLACK, Vector3(0, 0.6, 0), Vector3(1.9, 0.06, 3.9), false)
		b.box(P.CHARCOAL, Vector3(0, 0.66, -2.23), Vector3(0.9, 0.22, 0.04), false)
		for x in [-0.68, 0.68]:
			b.cyl_xf(P.LAMP, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(x, 0.68, -2.24)), 0.12, 0.12, 0.04, 12)
			b.box(P.AMBER, Vector3(x * 1.2, 0.48, -2.22), Vector3(0.14, 0.07, 0.04), false)
			b.box(P.BURGUNDY, Vector3(x, 0.7, 2.24), Vector3(0.36, 0.14, 0.04), false)
		b.box(P.CHARCOAL, Vector3(0, 0.95, 0.9), Vector3(0.05, 0.05, 0.05), false)
		# Roof aerial and a tape deck glow through the windscreen.
		b.cyl(P.STEEL, Vector3(0.7, 1.75, 1.2), 0.01, 0.005, 0.6, 4)
		b.box(P.CRT, Vector3(0, 1.0, -0.42), Vector3(0.2, 0.08, 0.02), false)
		return b.mesh())
