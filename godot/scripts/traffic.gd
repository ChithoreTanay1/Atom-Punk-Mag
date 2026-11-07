extends Node3D
## Expressway traffic [INVENTED]: boxy 80s saloons and box vans on the six
## carriageway lanes. Kinematic bodies: they shove the player's car, it
## can't shove them. Simple car-following, a lane change when stuck behind
## something slow, and a window that wraps round the focus so the road is
## never empty. Traffic keeps left: -Z bound at x < 0.

const P = preload("res://scripts/palette.gd")
const WINDOW := 420.0
## Lane: x centre, direction of travel along z, preferred speed (m/s).
const LANES := [
	[-3.4, -1.0, 25.0], [-7.0, -1.0, 20.0], [-10.6, -1.0, 15.5],
	[3.4, 1.0, 25.0], [7.0, 1.0, 20.0], [10.6, 1.0, 15.5],
]
const PAINTS := ["#2B2F31", "#2F6E73", "#C9B88F", "#24414F", "#A2512F", "#8E8A82", "#6E1F24", "#B9B6AC", "#3D4A3A", "#5A5F61"]

## Where the camera is (local coordinates); set by the level every frame.
var focus := Vector3.ZERO
## Things traffic queues behind instead of driving through (player, car).
var obstacles: Array[Node3D] = []
var cars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
static var _paints := {}

func setup(per_lane: int, seed_: int) -> void:
	_rng.seed = seed_
	var step := WINDOW * 2.0 / per_lane
	for li in LANES.size():
		for k in per_lane:
			_spawn(li, focus.z - WINDOW + (k + _rng.randf_range(0.1, 0.7)) * step)

func _spawn(li: int, z: float) -> void:
	var van := _rng.randf() < 0.2
	var body := AnimatableBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.1, 2.5, 5.7) if van else Vector3(1.9, 1.3, 4.7)
	cs.shape = bs
	cs.position = Vector3(0, bs.size.y * 0.5 + 0.15, 0)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = van_mesh() if van else saloon_mesh()
	mi.visibility_range_end = 340.0
	var paint := _painted(Color(PAINTS[_rng.randi() % PAINTS.size()]))
	for i in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_material(i) == P.mats()[P.CAR_PAINT]:
			mi.set_surface_override_material(i, paint)
	body.add_child(mi)
	var lane: Array = LANES[li]
	var c := {"body": body, "lane": li, "x": float(lane[0]), "z": z, "v": float(lane[2]) * 0.9,
		"pref": float(lane[2]) * _rng.randf_range(0.85, 1.12), "len": bs.size.z, "cd": _rng.randf_range(0.0, 4.0)}
	body.position = Vector3(c.x, 0.0, z)
	body.rotation.y = _yaw(float(lane[1]), 0.0, 1.0)
	add_child(body)
	cars.append(c)

static func _yaw(dir: float, vx: float, vz_abs: float) -> float:
	# Front is -Z; yaw so that forward = (vx, 0, dir * vz).
	return atan2(-vx, -dir * maxf(vz_abs, 0.5))

func _physics_process(dt: float) -> void:
	for c in cars:
		var lane: Array = LANES[c.lane]
		var dir: float = lane[1]
		var lead := _leader(c, int(c.lane), dir)
		var gap: float = lead[0]
		var lead_v: float = lead[1]
		var safe: float = 6.0 + c.v * 1.1
		var target: float = c.pref
		if gap < safe * 2.0:
			target = minf(target, lead_v + (gap - safe) * 0.6)
		target = maxf(target, 0.0)
		c.v += clampf(target - c.v, -10.0 * dt, 3.0 * dt)
		# Stuck behind something slow: look for a gap in the next lane.
		c.cd -= dt
		if c.cd <= 0.0 and gap < safe * 1.8 and lead_v < c.pref - 3.0:
			c.cd = 1.0
			for nl in [int(c.lane) - 1, int(c.lane) + 1]:
				if nl >= 0 and nl < LANES.size() and LANES[nl][1] == dir and _free(c, nl, dir):
					c.lane = nl
					c.cd = 6.0
					break
		var tx: float = LANES[c.lane][0]
		var vx := clampf((tx - c.x) * 1.5, -1.8, 1.8)
		c.x += vx * dt
		c.z += dir * c.v * dt
		var body: AnimatableBody3D = c.body
		var dz: float = c.z - focus.z
		if absf(dz) > WINDOW:
			c.z -= signf(dz) * WINDOW * 2.0
			c.v = c.pref
			c.x = tx
			_teleport(c)
		else:
			body.position = Vector3(c.x, 0.0, c.z)
			body.rotation.y = _yaw(dir, vx, c.v)

## [gap to whatever is ahead in this lane, its speed along dir].
func _leader(c: Dictionary, li: int, dir: float) -> Array:
	var lx: float = LANES[li][0]
	var gap := INF
	var lead_v: float = c.pref
	for o in cars:
		if o == c or absf(o.x - lx) > 2.4 or (o.z - c.z) * dir < 0.0:
			continue
		var d: float = (o.z - c.z) * dir - (o.len + c.len) * 0.5
		if d < gap:
			gap = d
			lead_v = o.v
	for ob in obstacles:
		if not is_instance_valid(ob) or not ob.is_inside_tree():
			continue
		var p := ob.global_position
		if absf(p.x - lx) > 2.2 or p.y > 4.0:
			continue
		var d2: float = (p.z - c.z) * dir - c.len * 0.5 - 2.4
		if d2 > -2.0 and d2 < gap:
			gap = d2
			var v := Vector3.ZERO
			if ob is RigidBody3D:
				v = (ob as RigidBody3D).linear_velocity
			elif ob is CharacterBody3D:
				v = (ob as CharacterBody3D).velocity
			lead_v = maxf(v.z * dir, 0.0)
	return [gap, lead_v]

func _free(c: Dictionary, li: int, dir: float) -> bool:
	var lx: float = LANES[li][0]
	for o in cars:
		if o != c and absf(o.x - lx) < 2.4:
			var d: float = (o.z - c.z) * dir
			if d > -14.0 and d < 20.0:
				return false
	for ob in obstacles:
		if is_instance_valid(ob) and absf(ob.global_position.x - lx) < 2.4:
			var d2: float = (ob.global_position.z - c.z) * dir
			if d2 > -14.0 and d2 < 20.0:
				return false
	return true

## Re-adding the body places it fresh, with no kinematic sweep (no launch
## of anything it touched on the way).
func _teleport(c: Dictionary) -> void:
	var body: AnimatableBody3D = c.body
	remove_child(body)
	body.position = Vector3(c.x, 0.0, c.z)
	body.rotation.y = _yaw(float(LANES[c.lane][1]), 0.0, 1.0)
	add_child(body)

func rebase(s: float) -> void:
	focus.z -= s
	for c in cars:
		c.z -= s
		_teleport(c)

static func _painted(col: Color) -> Material:
	if not _paints.has(col):
		var m := (P.mats()[P.CAR_PAINT] as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("albedo", col)
		_paints[col] = m
	return _paints[col]

static func _tail_mat() -> Material:
	var m := P._kit("#6E1F24", 0, 0.4)
	m.set_shader_parameter("emission_color", Color("#B3363F"))
	m.set_shader_parameter("emission_energy", 1.6)
	return m

## Tail lamps are built as BURGUNDY, then given a glowing red.
static func _finish(m: ArrayMesh) -> ArrayMesh:
	for i in m.get_surface_count():
		if m.surface_get_material(i) == P.mats()[P.BURGUNDY]:
			m.surface_set_material(i, _tail_mat())
	return m

static func _wheels(b: Builder, zf: float, zr: float) -> void:
	var axis := Basis(Vector3.FORWARD, PI / 2)
	for x in [-0.8, 0.8]:
		for z in [zf, zr]:
			b.cyl_xf(P.TYRE, Transform3D(axis, Vector3(x, 0.33, z)), 0.33, 0.33, 0.24, 10)
			b.cyl_xf(P.CHROME, Transform3D(axis, Vector3(x * 1.01, 0.33, z)), 0.19, 0.19, 0.25, 8)

## Three-box 80s saloon. Ground at y = 0, front -Z, about 4.7 m.
static func saloon_mesh() -> Mesh:
	return Builder.cached("xw_saloon", func():
		var b := Builder.new(0.2)
		_wheels(b, -1.42, 1.42)
		b.box(P.CAR_PAINT, Vector3(0, 0.66, 0), Vector3(1.82, 0.56, 4.6), false)
		b.box(P.BLACK, Vector3(0, 0.36, 0), Vector3(1.66, 0.14, 4.1), false)
		b.box(P.BLACK, Vector3(0, 0.68, 0), Vector3(1.85, 0.05, 4.0), false)
		b.kit.add_ramp(P.BLACK, Transform3D(Basis(), Vector3(0, 0.94, -0.75)), Vector3(1.6, 0.48, 0.6))
		b.kit.add_ramp(P.BLACK, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.94, 1.05)), Vector3(1.6, 0.48, 0.5))
		b.box(P.BLACK, Vector3(0, 1.18, 0.18), Vector3(1.6, 0.48, 1.26), false)
		b.box(P.CAR_PAINT, Vector3(0, 1.45, 0.18), Vector3(1.64, 0.07, 1.32), false)
		for sx in [-1.0, 1.0]:
			b.box(P.CAR_PAINT, Vector3(sx * 0.79, 1.18, 0.22), Vector3(0.05, 0.5, 0.12), false)
		b.box(P.CHROME, Vector3(0, 0.48, -2.34), Vector3(1.86, 0.14, 0.1), false)
		b.box(P.CHROME, Vector3(0, 0.48, 2.34), Vector3(1.86, 0.14, 0.1), false)
		b.box(P.CHARCOAL, Vector3(0, 0.72, -2.31), Vector3(0.8, 0.2, 0.04), false)
		for sx in [-1.0, 1.0]:
			b.box(P.LAMP, Vector3(sx * 0.66, 0.73, -2.31), Vector3(0.38, 0.16, 0.04), false)
			b.box(P.AMBER, Vector3(sx * 0.82, 0.52, -2.32), Vector3(0.14, 0.06, 0.04), false)
			b.box(P.BURGUNDY, Vector3(sx * 0.62, 0.76, 2.31), Vector3(0.46, 0.18, 0.04), false)
		return _finish(b.mesh()))

## Box van: cab with a beige cargo body. Ground at y = 0, front -Z.
static func van_mesh() -> Mesh:
	return Builder.cached("xw_van", func():
		var b := Builder.new(0.2)
		_wheels(b, -1.9, 1.7)
		b.box(P.CAR_PAINT, Vector3(0, 1.05, -2.0), Vector3(1.95, 1.3, 1.6), false)
		b.kit.add_ramp(P.BLACK, Transform3D(Basis(), Vector3(0, 1.3, -2.55)), Vector3(1.8, 0.75, 0.45))
		b.box(P.BLACK, Vector3(0, 0.45, -2.0), Vector3(1.8, 0.2, 1.5), false)
		b.box(P.BEIGE, Vector3(0, 1.55, 0.75), Vector3(2.05, 2.1, 3.9), false)
		b.box(P.CHARCOAL, Vector3(0, 0.42, 0.75), Vector3(1.8, 0.22, 3.9), false)
		for k in 5:
			for sx in [-1.0, 1.0]:
				b.box(P.WARM_GREY, Vector3(sx * 1.035, 1.55, -0.95 + k * 0.85), Vector3(0.03, 2.0, 0.08), false)
		b.box(P.CHROME, Vector3(0, 0.45, -2.84), Vector3(1.95, 0.16, 0.1), false)
		b.box(P.CHARCOAL, Vector3(0, 0.8, -2.81), Vector3(0.9, 0.3, 0.04), false)
		for sx in [-1.0, 1.0]:
			b.box(P.LAMP, Vector3(sx * 0.7, 0.85, -2.81), Vector3(0.3, 0.2, 0.04), false)
			b.box(P.BURGUNDY, Vector3(sx * 0.85, 0.7, 2.71), Vector3(0.2, 0.3, 0.04), false)
			b.box(P.AMBER, Vector3(sx * 0.85, 2.55, 2.71), Vector3(0.12, 0.06, 0.04), false)
		return _finish(b.mesh()))
