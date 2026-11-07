extends Node3D
## The endless expressway, after refs/expressway.jfif. [INVENTED: the road,
## its "A1 Mauryan Way" signs and every building on it.]
##
## The road runs along Z and is streamed in 96 m chunks around a focus
## point. A chunk is a handful of prebuilt pieces (road core, one building
## row per side, a far skyline per side, sometimes an overpass). Pieces are
## built once as prototypes and duplicated, so meshes, collision shapes and
## multimeshes are shared and spawning a chunk costs almost nothing. Which
## pieces a chunk gets is a hash of its index, so a stretch of road looks
## the same when you drive back to it.
##
## Cross-section (x in metres). Traffic keeps left: -Z bound runs at x < 0.
##   -92..-28    building row (left), on a paved pad
##   -28..-14.7  plaza walk, under the promenade deck (-27.6..-16.5, 6.5 m up)
##   -14.4..14.4 carriageway: 3 + 3 lanes, shoulders, median barrier
##   14.7..19    walk          19..23  pier island (Y piers, overpass stairs)
##   23..31      service road  31..36  walk          36..92  building row
##   14..28      viaduct deck, 10.5 m up
## Floating origin: the level shifts the world back toward 0 and calls
## rebase(); origin_z (a 64-bit float) keeps the true position.

const P = preload("res://scripts/palette.gd")

const L := 96.0
const RADIUS := 4
const MED := 0.6
const LANE0 := 1.6
const LANE_W := 3.6
const EDGE := 12.4
const ROAD_X := 14.4
const WALK_R := 19.0
const ISLAND := 23.0
const SVC_X1 := 31.0
const BLD_R := 36.0
const BLD_L := -28.0
const PAD := 92.0
const PROM_X0 := -27.6
const PROM_X1 := -16.5
const PROM_Y := 6.5
const VIA_X := 21.0
const VIA_W := 14.0
const VIA_Y := 10.5
const OZ0 := 29.0
const OZ1 := 35.0
## Ramp lane beside the viaduct (up and down), and its flat merge length.
const RAMP_X0 := 28.3
const RAMP_X1 := 33.7
const RAMP_FLAT := 24.0

## World z of local z = 0.
var origin_z := 0.0
## Called as extra.call(index, chunk_node) after a chunk is built.
var extra := Callable()
var chunks := {}
var _proto := {}

# Build state for the piece under construction.
var _b: Builder
var _h: Node3D
var _pr := {}
var _s := 1
var _fx := 0.0
var _rng := RandomNumberGenerator.new()

# ============================================================== streaming

func build_all(focus_z: float) -> void:
	_build_protos()
	var ci := _index(focus_z)
	for k in range(-RADIUS, RADIUS + 1):
		_spawn(ci + k)

func update(focus_z: float) -> void:
	var ci := _index(focus_z)
	var made := 0
	for k in RADIUS + 1:
		for i in [ci - k, ci + k]:
			if not chunks.has(i) and made < 2:
				_spawn(i)
				made += 1
	for i in chunks.keys():
		if absi(i - ci) > RADIUS + 1:
			chunks[i].queue_free()
			chunks.erase(i)

func _exit_tree() -> void:
	for k in _proto:
		_proto[k].free()
	_proto.clear()

func rebase(s: float) -> void:
	origin_z += s
	for i in chunks:
		chunks[i].position.z -= s

func _index(local_z: float) -> int:
	return int(floor((local_z + origin_z) / L))

func _spawn(i: int) -> void:
	var c := Node3D.new()
	c.name = "Chunk%d" % i
	c.position = Vector3(0, 0, i * L - origin_z)
	var core := "core"
	if posmod(i, 4) == 2:
		core = "core_over"
	elif posmod(i, 8) == 5:
		core = "core_gap"
	elif posmod(i, 8) == 7:
		core = "core_up"
	elif posmod(i, 8) == 3:
		core = "core_down"
	c.add_child(_proto[core].duplicate())
	if core == "core_over":
		c.add_child(_proto["over"].duplicate())
	var left := "left%d" % posmod(i * 3 + _hash(i >> 2, 7), 4)
	if i == -1:
		left = "yard_a"
	elif i == 0:
		left = "yard_b"
	c.add_child(_proto[left].duplicate())
	c.add_child(_proto["right%d" % posmod(i + _hash(i >> 2, 3), 4)].duplicate())
	c.add_child(_proto["farl%d" % (_hash(i, 11) % 3)].duplicate())
	c.add_child(_proto["farr%d" % (_hash(i, 13) % 3)].duplicate())
	add_child(c)
	if extra.is_valid():
		extra.call(i, c)
	chunks[i] = c

static func _hash(i: int, salt: int) -> int:
	var x := i * 73856093 ^ salt * 19349663
	x = (x ^ (x >> 13)) * 1274126177
	return absi(x ^ (x >> 16))

# ============================================================== prototypes

func _build_protos() -> void:
	_proto["core"] = _piece("Core", func(): _core(""))
	_proto["core_gap"] = _piece("Core", func(): _core("gap"))
	_proto["core_over"] = _piece("Core", func(): _core("over"))
	_proto["core_up"] = _piece("Core", func(): _core("up"))
	_proto["core_down"] = _piece("Core", func(): _core("down"))
	_proto["over"] = _piece("Overpass", _overpass)
	for k in 4:
		_proto["left%d" % k] = _piece("Left", func(): _left(k))
		_proto["right%d" % k] = _piece("Right", func(): _right(k))
	_proto["yard_a"] = _piece("Yard", func(): _yard(0.0))
	_proto["yard_b"] = _piece("Yard", func(): _yard(L))
	for k in 3:
		_proto["farl%d" % k] = _piece("FarL", func(): _far(-1, 100 + k), true)
		_proto["farr%d" % k] = _piece("FarR", func(): _far(1, 200 + k), true)

func _piece(name: String, f: Callable, far := false) -> Node3D:
	_h = Node3D.new()
	_h.name = name
	_b = Builder.new(0.0 if far else 0.25)
	_pr = {}
	f.call()
	var mi := _b.commit(_h, "Mesh")
	if far:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for key in _pr:
		var spec: Array = PROPS[key]
		Builder.scatter(_h, _prop_mesh(key), _pr[key], spec[0], spec[1])
	return _h

## Prop key: [visibility range, casts shadows].
const PROPS := {
	"lamp": [200.0, true], "mlamp": [280.0, true], "bollard": [80.0, true],
	"banner": [300.0, false], "tank": [320.0, true], "antenna": [320.0, false],
	"tree": [170.0, true], "planter": [110.0, true], "bench": [80.0, true],
	"stall": [130.0, true], "hedge": [120.0, true], "booth": [110.0, true],
	"kiosk": [140.0, true], "bin": [70.0, true], "ac": [140.0, false],
	"crate": [120.0, true], "cone": [120.0, false],
}

func _prop_mesh(key: String) -> Mesh:
	match key:
		"lamp": return Builder.lamp_post()
		"mlamp": return _median_lamp()
		"bollard": return Builder.bollard()
		"banner": return _banner_mesh()
		"tank": return Builder.water_tank()
		"antenna": return Builder.antenna()
		"tree": return Builder.tree()
		"planter": return Builder.planter()
		"bench": return Builder.bench()
		"stall": return Builder.stall()
		"hedge": return Builder.hedge()
		"booth": return Builder.phone_booth()
		"kiosk": return Builder.kiosk()
		"bin": return Builder.bin()
		"ac": return Builder.ac_unit()
		"crate": return Builder.crate()
		"cone": return Builder.cone()
	return null

func _prop(key: String, t: Transform3D) -> void:
	if not _pr.has(key):
		_pr[key] = []
	_pr[key].append(t)

func _at(key: String, pos: Vector3, rot_y := 0.0) -> void:
	_prop(key, Transform3D(Basis(Vector3.UP, rot_y), pos))

# ============================================================== road core

func _core(kind: String) -> void:
	var b := _b
	var zc := L * 0.5
	# Carriageway and service road.
	b.box(P.ASPHALT, Vector3(0, -0.15, zc), Vector3(ROAD_X * 2.0, 0.3, L))
	b.box(P.ASPHALT, Vector3((ISLAND + SVC_X1) * 0.5, -0.15, zc), Vector3(SVC_X1 - ISLAND, 0.3, L))
	# Median: raised kerb and a stepped concrete barrier. The gap lets you
	# turn round.
	var segs := [[0.0, L]]
	if kind == "gap":
		segs = [[0.0, 44.0], [64.0, L]]
	for sg in segs:
		var a: float = sg[0]
		var e: float = sg[1]
		var m := (a + e) * 0.5
		var n := e - a
		b.box(P.CONCRETE_PALE, Vector3(0, 0.0, m), Vector3(MED * 2.0, 0.36, n))
		b.box(P.CONCRETE, Vector3(0, 0.29, m), Vector3(0.84, 0.22, n), false)
		b.box(P.CONCRETE, Vector3(0, 0.49, m), Vector3(0.6, 0.18, n), false)
		b.box(P.CONCRETE, Vector3(0, 0.85, m), Vector3(0.34, 0.54, n), false)
		b.kit.add_collider(Builder.xf(Vector3(0, 0.65, m)), Vector3(0.84, 0.94, n))
		# Reflector strip along the barrier face.
		for sx: float in [-1.0, 1.0]:
			b.box(P.CHARCOAL, Vector3(sx * 0.43, 0.3, m), Vector3(0.02, 0.06, n), false)
	if kind == "gap":
		for z: float in [44.0, 64.0]:
			for sx: float in [-0.4, 0.4]:
				_at("bollard", Vector3(sx, 0.18, z + (-0.8 if z < 50.0 else 0.8)))
			b.box(P.AMBER, Vector3(0, 1.0, z + (-0.05 if z < 50.0 else 0.05)), Vector3(0.3, 0.12, 0.02), false)
	for z: float in [8.0, 40.0, 72.0]:
		_at("mlamp", Vector3(0, 0.18, z))
	# Paint: edge lines, lane dashes, cat's eyes, gutters, grates, manholes,
	# an expansion joint. Just proud of the asphalt so snow can bury it.
	var py := 0.012
	for sx: float in [-1.0, 1.0]:
		b.box(P.PAINT, Vector3(sx * LANE0, py, zc), Vector3(0.15, 0.012, L), false)
		b.box(P.PAINT, Vector3(sx * EDGE, py, zc), Vector3(0.2, 0.012, L), false)
		for k: float in [1.0, 2.0]:
			for j in 12:
				b.box(P.PAINT, Vector3(sx * (LANE0 + LANE_W * k), py, j * 8.0 + 1.5), Vector3(0.14, 0.012, 3.0), false)
		for j in 6:
			b.box(P.AMBER, Vector3(sx * (EDGE + 0.3), 0.02, j * 16.0 + 6.0), Vector3(0.12, 0.03, 0.14), false)
			b.box(P.AMBER, Vector3(sx * (LANE0 - 0.25), 0.02, j * 16.0 + 14.0), Vector3(0.12, 0.03, 0.14), false)
		b.box(P.CONCRETE_DARK, Vector3(sx * (ROAD_X - 0.25), 0.004, zc), Vector3(0.5, 0.01, L), false)
		for j in 6:
			b.box(P.CHARCOAL, Vector3(sx * (ROAD_X - 0.25), 0.012, j * 16.0 + 10.0), Vector3(0.42, 0.012, 0.9), false)
			for r in 4:
				b.box(P.BLACK, Vector3(sx * (ROAD_X - 0.25), 0.02, j * 16.0 + 9.7 + r * 0.2), Vector3(0.36, 0.006, 0.05), false)
	b.box(P.STEEL, Vector3(0, 0.008, 0.25), Vector3(ROAD_X * 2.0, 0.012, 0.3), false)
	for mh in [Vector3(-7.0, 0.01, 26.0), Vector3(3.4, 0.01, 70.0), Vector3(27.0, 0.01, 50.0), Vector3(-10.6, 0.01, 84.0)]:
		b.cyl(P.CHARCOAL, mh, 0.42, 0.42, 0.02, 14)
		b.cyl(P.STEEL, mh + Vector3(0, 0.006, 0), 0.3, 0.3, 0.02, 14)
	# Service road paint.
	b.box(P.PAINT, Vector3(ISLAND + 0.35, py, zc), Vector3(0.14, 0.012, L), false)
	b.box(P.PAINT, Vector3(SVC_X1 - 0.35, py, zc), Vector3(0.14, 0.012, L), false)
	for j in 12:
		b.box(P.PAINT, Vector3((ISLAND + SVC_X1) * 0.5, py, j * 8.0 + 1.5), Vector3(0.14, 0.012, 3.0), false)
	# Kerbs, walks, the pier island and the left plaza.
	_kerb(ROAD_X, 0.3)
	_kerb(-ROAD_X, -0.3)
	_walk(ROAD_X + 0.3, WALK_R)
	_kerb(WALK_R, 0.3)
	b.box(P.CONCRETE, Vector3((WALK_R + ISLAND) * 0.5, -0.06, zc), Vector3(ISLAND - WALK_R - 0.6, 0.48, L))
	_kerb(ISLAND, -0.3)
	_kerb(SVC_X1, 0.3)
	_walk(SVC_X1 + 0.3, BLD_R)
	_walk(BLD_L, -ROAD_X - 0.3)
	# Tactile strip and a kerb-side lamp/bollard line on both walks.
	for sx: float in [-1.0, 1.0]:
		b.box(P.CONCRETE_DARK, Vector3(sx * (ROAD_X + 0.95), 0.185, zc), Vector3(0.5, 0.012, L), false)
		for z: float in [0.0, 32.0, 64.0]:
			_at("lamp", Vector3(sx * (ROAD_X + 0.6), 0.18, z + 4.0), 0.0 if sx < 0.0 else PI)
		for j in 24:
			var z := j * 4.0 + 2.0
			if fmod(z + 28.0, 32.0) > 3.0:
				_at("bollard", Vector3(sx * (ROAD_X + 0.6), 0.18, z))
	# Island hedges between the piers (clear of the overpass stairs).
	var hz := [2.5, 6.7, 54.0, 58.2, 62.4, 66.6, 70.8, 75.0, 85.0, 89.2]
	if kind != "over":
		hz.append_array([22.0, 26.2, 30.4, 34.6, 38.8, 43.0])
	for z in hz:
		_at("hedge", Vector3(VIA_X, 0.18, z), PI / 2)
	_viaduct(kind)
	_promenade(kind == "over")

func _kerb(x: float, w: float) -> void:
	_b.box(P.CONCRETE_PALE, Vector3(x + w * 0.5, 0.0, L * 0.5), Vector3(absf(w), 0.42, L))

func _walk(x0: float, x1: float) -> void:
	_b.box(P.PAVING, Vector3((x0 + x1) * 0.5, -0.06, L * 0.5), Vector3(absf(x1 - x0), 0.48, L))

## Ramp chunk kind for the viaduct: "up" climbs toward -Z (the merge is at
## local z 0..RAMP_FLAT), "down" climbs toward +Z (merge at the far end).
static func ramp_span(kind: String) -> Vector2:
	if kind == "up":
		return Vector2(0.0, RAMP_FLAT)
	if kind == "down":
		return Vector2(L - RAMP_FLAT, L)
	return Vector2(-1.0, -1.0)

func _viaduct(kind: String) -> void:
	var b := _b
	var zc := L * 0.5
	var gap := ramp_span(kind)
	for pz: float in [16.0, 48.0, 80.0]:
		b.box(P.CONCRETE_DARK, Vector3(VIA_X, 0.48, pz), Vector3(3.0, 0.6, 3.0))
		b.box(P.CONCRETE, Vector3(VIA_X, 2.9, pz), Vector3(1.9, 4.24, 1.9))
		for sx: float in [-1.0, 1.0]:
			b.box(P.CONCRETE_DARK, Vector3(VIA_X + sx * 0.96, 2.9, pz), Vector3(0.04, 3.9, 0.5), false)
			# Y arms up to the cap beam.
			var top := Vector3(VIA_X, 4.9, pz)
			var end := Vector3(VIA_X + sx * 4.0, 8.7, pz)
			var dv := end - top
			var basis := Basis(Vector3.BACK, -atan2(dv.x, dv.y))
			b.box_xf(P.CONCRETE, Transform3D(basis, (top + end) * 0.5), Vector3(1.5, dv.length() + 0.9, 1.7))
		b.box(P.CONCRETE_PALE, Vector3(VIA_X, 8.85, pz), Vector3(10.2, 0.5, 2.2), false)
		for sx: float in [-3.5, -1.2, 1.2, 3.5]:
			b.box(P.CHARCOAL, Vector3(VIA_X + sx, 9.15, pz), Vector3(0.7, 0.1, 0.7), false)
	# Box girder under a wider slab: the overhang throws a long shadow line.
	b.box(P.CONCRETE, Vector3(VIA_X, 9.55, zc), Vector3(9.0, 0.5, L), false)
	b.box(P.CONCRETE, Vector3(VIA_X, VIA_Y - 0.35, zc), Vector3(VIA_W, 0.7, L))
	for sx: float in [-1.0, 1.0]:
		var ex := VIA_X + sx * VIA_W * 0.5
		b.box(P.CONCRETE_PALE, Vector3(ex + sx * 0.12, VIA_Y - 0.4, zc), Vector3(0.24, 0.95, L), false)
		# Parapet and rail, open on the right where a ramp merges.
		var spans := [[0.0, L]]
		if sx > 0.0 and gap.x >= 0.0:
			spans = [[0.0, gap.x], [gap.y, L]]
		for sp in spans:
			var a: float = sp[0]
			var e: float = sp[1]
			if e - a < 0.1:
				continue
			b.box(P.CONCRETE_PALE, Vector3(ex - sx * 0.2, VIA_Y + 0.5, (a + e) * 0.5), Vector3(0.4, 1.0, e - a))
			b.box(P.STEEL, Vector3(ex - sx * 0.2, VIA_Y + 1.58, (a + e) * 0.5), Vector3(0.1, 0.08, e - a), false)
			var pz := a + 1.0
			while pz < e:
				b.box(P.STEEL, Vector3(ex - sx * 0.2, VIA_Y + 1.3, pz), Vector3(0.08, 0.6, 0.08), false)
				pz += 4.0
		b.box(P.PAINT, Vector3(VIA_X + sx * (VIA_W * 0.5 - 0.9), VIA_Y + 0.05, zc), Vector3(0.15, 0.012, L), false)
	b.box(P.ASPHALT, Vector3(VIA_X, VIA_Y + 0.02, zc), Vector3(VIA_W - 0.8, 0.04, L), false)
	for j in 12:
		b.box(P.PAINT, Vector3(VIA_X, VIA_Y + 0.05, j * 8.0 + 1.5), Vector3(0.14, 0.012, 3.0), false)
	for z: float in [0.0, 32.0, 64.0]:
		if z < gap.x - 1.0 or z > gap.y + 1.0:
			_at("lamp", Vector3(VIA_X + VIA_W * 0.5 - 0.7, VIA_Y + 0.04, z), PI)
	if gap.x >= 0.0:
		_ramp(kind)

## A drivable ramp on an embankment beside the viaduct: an incline from the
## service road, then a flat run level with the deck where the parapet is
## open, so you can move across onto the viaduct (or off it).
func _ramp(kind: String) -> void:
	var b := _b
	var up := kind == "up"
	var w := RAMP_X1 - RAMP_X0
	var cx := (RAMP_X0 + RAMP_X1) * 0.5
	var run := L - RAMP_FLAT
	var flat := ramp_span(kind)
	# Incline: ground end and top end along z.
	var z_low := L if up else 0.0
	var z_high := RAMP_FLAT if up else L - RAMP_FLAT
	b.ramp(P.CONCRETE, Vector3(cx, 0, (z_low + z_high) * 0.5), Vector3(w, VIA_Y, run), PI if up else 0.0)
	var p0 := Vector3(cx, 0.0, z_low)
	var p1 := Vector3(cx, VIA_Y, z_high)
	var basis := Basis.looking_at(p1 - p0)
	var mid := (p0 + p1) * 0.5
	var slope_len := p0.distance_to(p1)
	b.box_xf(P.ASPHALT, Transform3D(basis, mid + basis.y * 0.03), Vector3(w - 0.7, 0.06, slope_len))
	for sx: float in [-1.0, 1.0]:
		var off := Vector3(sx * (w * 0.5 - 0.2), 0, 0)
		b.box_xf(P.CONCRETE_PALE, Transform3D(basis, mid + off + basis.y * 0.5), Vector3(0.4, 1.0, slope_len), true)
		b.box_xf(P.PAINT, Transform3D(basis, mid + Vector3(sx * (w * 0.5 - 0.75), 0, 0) + basis.y * 0.065), Vector3(0.14, 0.012, slope_len))
		b.box(P.CONCRETE_PALE, Vector3(cx + sx * (w * 0.5 + 0.05), VIA_Y * 0.25, (z_low + z_high) * 0.5), Vector3(0.1, 0.3, run), false)
	# Flat merge run, level with the deck; outer parapet only.
	var fz := (flat.x + flat.y) * 0.5
	b.box(P.CONCRETE, Vector3((VIA_X + VIA_W * 0.5 + RAMP_X1) * 0.5, VIA_Y * 0.5, fz), Vector3(RAMP_X1 - VIA_X - VIA_W * 0.5, VIA_Y, RAMP_FLAT))
	b.box(P.ASPHALT, Vector3((VIA_X + VIA_W * 0.5 + RAMP_X1) * 0.5, VIA_Y + 0.02, fz), Vector3(RAMP_X1 - VIA_X - VIA_W * 0.5 - 0.4, 0.04, RAMP_FLAT), false)
	b.box(P.CONCRETE_PALE, Vector3(RAMP_X1 - 0.2, VIA_Y + 0.5, fz), Vector3(0.4, 1.0, RAMP_FLAT))
	# Nose barrier at the far end of the merge, with amber chevrons.
	var nz := flat.x + 0.3 if up else flat.y - 0.3
	b.box(P.CONCRETE_PALE, Vector3(cx + 0.2, VIA_Y + 0.5, nz), Vector3(w - 0.4, 1.0, 0.5))
	for k in 4:
		b.box(P.AMBER, Vector3(RAMP_X0 + 1.0 + k * 1.3, VIA_Y + 0.7, nz + (0.27 if up else -0.27)), Vector3(0.6, 0.18, 0.02), false)
	# Retaining-wall bands on the outer face.
	for k in 3:
		var y := 2.4 + k * 2.8
		b.box(P.CONCRETE_DARK, Vector3(RAMP_X1 + 0.06, y, fz), Vector3(0.08, 0.2, RAMP_FLAT), false)
	# Sign at the foot of the ramp.
	var sz := z_low + (-6.0 if up else 6.0)
	b.box(P.CHARCOAL, Vector3(RAMP_X1 + 1.2, 1.6, sz), Vector3(0.14, 3.2, 0.14))
	var f := 1.0 if up else -1.0
	b.box(P.SIGN, Vector3(RAMP_X1 + 1.2, 3.6, sz + f * 0.1), Vector3(3.0, 1.0, 0.1), false)
	var lb := Label3D.new()
	lb.text = "VIADUCT  ^"
	lb.font_size = 72
	lb.pixel_size = 0.006
	lb.modulate = Color("#E8E6DC")
	lb.position = Vector3(RAMP_X1 + 1.2, 3.6, sz + f * 0.17)
	lb.rotation.y = 0.0 if up else PI
	lb.double_sided = false
	_h.add_child(lb)

func _promenade(stair_gap: bool) -> void:
	var b := _b
	var zc := L * 0.5
	var w := PROM_X1 - PROM_X0
	var cx := (PROM_X0 + PROM_X1) * 0.5
	b.box(P.CONCRETE, Vector3(cx, PROM_Y - 0.35, zc), Vector3(w, 0.7, L))
	b.box(P.PAVING, Vector3(cx, PROM_Y + 0.02, zc), Vector3(w, 0.04, L), false)
	b.box(P.CONCRETE_PALE, Vector3(PROM_X1 + 0.12, PROM_Y - 0.4, zc), Vector3(0.24, 1.0, L), false)
	b.box(P.CONCRETE, Vector3(PROM_X1 - 0.7, PROM_Y - 1.05, zc), Vector3(1.4, 0.7, L), false)
	# Balustrade: low wall, posts, rail. Open where the overpass lands.
	var spans := [[0.0, L]]
	if stair_gap:
		spans = [[0.0, OZ0], [OZ1, L]]
	var rx := PROM_X1 - 0.25
	for sp in spans:
		var a: float = sp[0]
		var e: float = sp[1]
		var m := (a + e) * 0.5
		b.box(P.CONCRETE_PALE, Vector3(rx, PROM_Y + 0.3, m), Vector3(0.3, 0.6, e - a), false)
		b.box(P.CONCRETE_PALE, Vector3(rx, PROM_Y + 1.16, m), Vector3(0.36, 0.14, e - a), false)
		b.kit.add_collider(Builder.xf(Vector3(rx, PROM_Y + 0.6, m)), Vector3(0.36, 1.2, e - a))
		var z := a + 1.0
		while z < e - 0.5:
			b.box(P.CONCRETE_PALE, Vector3(rx, PROM_Y + 0.85, z), Vector3(0.22, 0.5, 0.22), false)
			z += 2.0
	# Mushroom columns along the road edge.
	for k in 8:
		var z := 6.0 + k * 12.0
		b.cyl(P.CONCRETE, Vector3(-18.0, 2.6, z), 0.42, 0.42, 4.84, 12, true)
		b.cyl(P.CONCRETE_PALE, Vector3(-18.0, 5.4, z), 0.42, 1.3, 0.76, 12)
		b.box(P.CONCRETE_DARK, Vector3(-18.0, 0.3, z), Vector3(1.1, 0.24, 1.1), false)
	for z: float in [16.0, 48.0, 80.0]:
		_at("lamp", Vector3(PROM_X1 - 0.9, PROM_Y + 0.04, z))
	for z: float in [8.0, 24.0, 40.0, 56.0, 72.0, 88.0]:
		_at("planter", Vector3(PROM_X0 + 1.3, PROM_Y + 0.04, z))
	for z: float in [32.0, 64.0]:
		_at("bench", Vector3(PROM_X0 + 1.2, PROM_Y + 0.04, z), -PI / 2)

## Twin-armed mast for the median, lamps over both carriageways.
static func _median_lamp() -> Mesh:
	return Builder.cached("xw_mlamp", func():
		var b := Builder.new(0.2)
		b.cyl(P.CHARCOAL, Vector3(0, 0.3, 0), 0.3, 0.25, 0.6, 8)
		b.cyl(P.STEEL, Vector3(0, 4.8, 0), 0.14, 0.08, 9.0, 8)
		for sx: float in [-1.0, 1.0]:
			b.box(P.CHARCOAL, Vector3(sx * 1.1, 9.2, 0), Vector3(2.2, 0.12, 0.18), false)
			b.cyl(P.CHARCOAL, Vector3(sx * 2.15, 9.1, 0), 0.38, 0.16, 0.26, 12)
			b.cyl(P.LAMP, Vector3(sx * 2.15, 8.95, 0), 0.3, 0.3, 0.06, 12)
		b.cyl(P.AMBER, Vector3(0, 9.45, 0), 0.06, 0.06, 0.1, 6)
		return b.mesh())

# ============================================================== overpass

func _overpass() -> void:
	var b := _b
	var zc := (OZ0 + OZ1) * 0.5
	var x0 := PROM_X1
	var x1 := ISLAND
	var cx := (x0 + x1) * 0.5
	var w := x1 - x0
	b.box(P.CONCRETE, Vector3(cx, PROM_Y - 0.5, zc), Vector3(w, 1.0, OZ1 - OZ0))
	b.box(P.PAVING, Vector3(cx, PROM_Y + 0.02, zc), Vector3(w, 0.04, OZ1 - OZ0), false)
	for z in [OZ0 - 0.12, OZ1 + 0.12]:
		b.box(P.CONCRETE_PALE, Vector3(cx, PROM_Y - 0.5, z), Vector3(w, 1.2, 0.24), false)
	for z in [OZ0 + 1.0, OZ1 - 1.0]:
		b.box(P.CONCRETE, Vector3(cx, PROM_Y - 1.3, z), Vector3(w, 0.6, 0.8), false)
	# Balustrades; the near side opens onto the island stairs.
	for side in [[OZ0 + 0.2, [[x0, VIA_X - 1.4], [VIA_X + 1.4, x1]]], [OZ1 - 0.2, [[x0, x1]]]]:
		var z: float = side[0]
		for sp in side[1]:
			var a: float = sp[0]
			var e: float = sp[1]
			var m := (a + e) * 0.5
			b.box(P.CONCRETE_PALE, Vector3(m, PROM_Y + 0.3, z), Vector3(e - a, 0.6, 0.3), false)
			b.box(P.CONCRETE_PALE, Vector3(m, PROM_Y + 1.16, z), Vector3(e - a, 0.14, 0.36), false)
			b.kit.add_collider(Builder.xf(Vector3(m, PROM_Y + 0.6, z)), Vector3(e - a, 1.2, 0.36))
			var x := a + 1.0
			while x < e - 0.5:
				b.box(P.CONCRETE_PALE, Vector3(x, PROM_Y + 0.85, z), Vector3(0.22, 0.5, 0.22), false)
				x += 2.0
	# Piers on the median and the island.
	b.box(P.CONCRETE, Vector3(0, 2.6, zc), Vector3(1.0, 4.84, 4.0))
	b.box(P.CONCRETE, Vector3(VIA_X, 2.6, zc), Vector3(2.0, 4.84, 4.0))
	# Stairs down to the island.
	var steps := 36
	var rise := (PROM_Y - 0.18) / steps
	var run := 0.3
	var sz := OZ0 - steps * run
	b.stairs(P.CONCRETE_PALE, Vector3(VIA_X, 0.18, sz), 2.4, rise, run, steps, 0.0, true)
	for sx: float in [-1.0, 1.0]:
		var p0 := Vector3(VIA_X + sx * 1.3, 1.18, sz)
		var p1 := Vector3(VIA_X + sx * 1.3, PROM_Y + 1.0, OZ0)
		b.box_xf(P.STEEL, Transform3D(Basis.looking_at(p1 - p0), (p0 + p1) * 0.5), Vector3(0.07, 0.07, p0.distance_to(p1)))
		for k in 6:
			var t := (k + 0.5) / 6.0
			var p := p0.lerp(p1, t)
			b.box(P.STEEL, p - Vector3(0, 0.5, 0), Vector3(0.06, 1.0, 0.06), false)
	# Direction signs on both faces (teal-green plates, ivory text).
	_sign(Vector3(-7.0, PROM_Y - 1.75, OZ1 + 0.3), 0.0, "A1   MAURYAN WAY")
	_sign(Vector3(7.0, PROM_Y - 1.75, OZ0 - 0.3), PI, "A1   PATALIPUTRA")

func _sign(c: Vector3, rot: float, text: String) -> void:
	var f := 1.0 if rot == 0.0 else -1.0
	_b.box(P.PAINT, c - Vector3(0, 0, f * 0.07), Vector3(8.6, 1.6, 0.08), false)
	_b.box(P.SIGN, c, Vector3(8.4, 1.4, 0.12), false)
	for sx: float in [-3.2, 3.2]:
		_b.box(P.CHARCOAL, c + Vector3(sx, 0.85, -f * 0.1), Vector3(0.1, 0.3, 0.3), false)
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = 104
	lb.pixel_size = 0.0065
	lb.modulate = Color("#E8E6DC")
	lb.outline_size = 0
	lb.position = c + Vector3(0, 0, f * 0.07)
	lb.rotation.y = rot
	lb.double_sided = false
	_h.add_child(lb)

# ============================================================== buildings

## Side frame: u is depth from the facade line into the block.
func _row(side: int) -> void:
	_s = side
	_fx = BLD_R if side > 0 else BLD_L
	var w := PAD - absf(_fx)
	_b.box(P.PAVING, Vector3(_fx + side * w * 0.5, -0.06, L * 0.5), Vector3(w, 0.48, L))

func _sb(slot: int, u0: float, u1: float, y0: float, y1: float, z0: float, z1: float, solid := false) -> void:
	_b.box(slot, Vector3(_fx + _s * (u0 + u1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5),
		Vector3(absf(u1 - u0), y1 - y0, z1 - z0), solid)

func _p(u: float, y: float, z: float) -> Vector3:
	return Vector3(_fx + _s * u, y, z)

func _face() -> float:
	return 0.0 if _s < 0 else PI

## A block: colonnaded podium, then a tier with a skin, crown on top.
## o: podium, setback, floor, slot, skin (windows|jali|slab), fins,
## banners, crown (plant|saucer|needle|chhatri|none).
func _block(z0: float, z1: float, h: float, d: float, o := {}) -> void:
	var ph: float = o.get("podium", 5.0)
	var sb: float = o.get("setback", 1.4)
	var slot: int = o.get("slot", P.CONCRETE)
	var fins: float = o.get("fins", 0.0)
	var w := z1 - z0
	if ph > 0.0:
		_sb(P.CONCRETE_DARK, 2.0, d, 0.0, ph, z0, z1, true)
		_sb(P.WINDOWS, 1.94, 2.0, 0.6, ph - 0.4, z0 + 0.8, z1 - 0.8)
		_sb(P.CONCRETE_PALE, -0.2, 2.6, ph, ph + 0.55, z0 - 0.4, z1 + 0.4, true)
		var n := maxi(roundi(w / 6.0), 1)
		for k in n + 1:
			var zc := z0 + 0.6 + k * (w - 1.2) / n
			_sb(P.CONCRETE_PALE, 0.4, 1.1, 0.0, ph, zc - 0.35, zc + 0.35, true)
	var y0 := ph + (0.55 if ph > 0.0 else 0.0)
	var za := z0 + 0.6
	var zb := z1 - 0.6
	_tier(sb, d - 0.8, y0, h, za, zb, o.get("skin", "windows"), slot, o.get("floor", 3.6), fins)
	if o.get("banners", false):
		_banners(sb, y0, h, za, zb, fins if fins > 0.0 else 6.0)
	var roof := h + 0.45
	var cu := sb + (d - 0.8 - sb) * 0.5
	match o.get("crown", "plant"):
		"plant":
			_plant(sb, d - 0.8, roof, za, zb)
		"saucer":
			var R := clampf(minf(w, d - sb) * 0.62, 7.0, 17.0)
			_b.cyl(P.CONCRETE, _p(cu, roof + 2.5, (za + zb) * 0.5), R * 0.24, R * 0.2, 5.0, 16)
			var top := _saucer(_p(cu, roof + 5.0, (za + zb) * 0.5), R)
			_b.cyl(P.STEEL, _p(cu, top + 4.0, (za + zb) * 0.5), 0.12, 0.04, 8.0, 6)
			_b.cyl(P.AMBER, _p(cu, top + 8.1, (za + zb) * 0.5), 0.1, 0.1, 0.16, 6)
			if h > 18.0:
				# Smaller rings cantilevered off a round shaft at the end.
				var r2 := R * 0.5
				var su := sb + 2.2
				var szz := zb - 2.2
				_b.cyl(P.CONCRETE, _p(su, (y0 + h) * 0.5, szz), 1.7, 1.7, h - y0, 14)
				_saucer(_p(su, h * 0.68, szz), r2)
				_saucer(_p(su, h * 0.44, szz), r2 * 0.8)
		"needle":
			_plant(sb, d - 0.8, roof, za, zb, false)
			var c := _p(cu, roof, (za + zb) * 0.5)
			_b.cyl(P.STEEL, c + Vector3(0, 11.0, 0), 1.0, 0.12, 22.0, 8)
			_saucer(c + Vector3(0, 7.0, 0), 3.6)
			_b.cyl(P.AMBER, c + Vector3(0, 22.1, 0), 0.12, 0.12, 0.2, 6)
		"chhatri":
			for zc in [za + 3.0, zb - 3.0]:
				_chhatri(_p(sb + 2.6, roof, zc), 1.0)
			_chhatri(_p(cu, roof, (za + zb) * 0.5), 2.0)

## Body of a building between u0..u1 (u0 faces the road).
func _tier(u0: float, u1: float, y0: float, y1: float, za: float, zb: float, skin: String, slot: int, fl: float, fins: float) -> void:
	_sb(slot, u0, u1, y0, y1, za, zb, true)
	if skin == "windows":
		var y := y0
		while y + fl <= y1 + 0.01:
			_sb(P.WINDOWS, u0 - 0.06, u0, y + 0.5, y + fl - 0.8, za + 0.9, zb - 0.9)
			_sb(P.WINDOWS, u0 + 1.0, u1 - 1.0, y + 0.5, y + fl - 0.8, za - 0.06, za)
			_sb(P.WINDOWS, u0 + 1.0, u1 - 1.0, y + 0.5, y + fl - 0.8, zb, zb + 0.06)
			y += fl
	elif skin == "jali":
		_sb(P.JALI, u0 - 0.4, u0, y0 + 0.8, y1 - 1.6, za + 1.0, zb - 1.0)
		_sb(P.WINDOWS, u0 + 1.2, u1 - 1.2, y1 - 3.4, y1 - 1.0, za - 0.06, za)
		_sb(P.WINDOWS, u0 + 1.2, u1 - 1.2, y1 - 3.4, y1 - 1.0, zb, zb + 0.06)
	# Floor slabs wrap round the block: deep horizontal shadow lines.
	if skin != "jali":
		var y := y0 + fl
		while y < y1 - 0.5:
			_sb(P.CONCRETE_PALE, u0 - 0.75, u1 + 0.3, y - 0.32, y, za - 0.45, zb + 0.45)
			y += fl
	else:
		_sb(P.CONCRETE_PALE, u0 - 0.8, u1 + 0.3, y0, y0 + 0.6, za - 0.4, zb + 0.4)
	# Vertical fins (brise-soleil) or pilasters for a jali hall.
	if fins > 0.0:
		var n := maxi(roundi((zb - za) / fins), 1)
		for k in range(1, n):
			var zc := za + k * (zb - za) / n
			if skin == "jali":
				_sb(slot, u0 - 0.9, u0, y0, y1 - 0.2, zc - 0.45, zc + 0.45)
			else:
				_sb(P.CONCRETE_PALE, u0 - 0.8, u0, y0, y1 - 0.2, zc - 0.16, zc + 0.16)
	# Corner piers standing proud of the roofline.
	for zc in [za + 0.7, zb - 0.7]:
		_sb(slot, u0 - 0.95, u0 + 1.2, y0, y1 + 1.0, zc - 0.7, zc + 0.7)
	# Cornice and parapet.
	_sb(P.CONCRETE_PALE, u0 - 1.0, u1 + 0.4, y1, y1 + 0.45, za - 0.5, zb + 0.5)
	_sb(slot, u0 - 0.2, u0 + 0.1, y1 + 0.45, y1 + 1.3, za, zb)
	_sb(slot, u0, u1, y1 + 0.45, y1 + 1.3, za, za + 0.3)
	_sb(slot, u0, u1, y1 + 0.45, y1 + 1.3, zb - 0.3, zb)

func _plant(u0: float, u1: float, roof: float, za: float, zb: float, tanks := true) -> void:
	var w := zb - za
	var d := u1 - u0
	_sb(P.CONCRETE, u0 + d * 0.35, u0 + d * 0.75, roof, roof + 3.4, za + w * 0.3, zb - w * 0.3)
	for k in 5:
		_sb(P.CHARCOAL, u0 + d * 0.35 - 0.05, u0 + d * 0.35, roof + 0.6 + k * 0.5, roof + 0.8 + k * 0.5, za + w * 0.33, zb - w * 0.33)
	if tanks:
		_at("tank", _p(u0 + d * 0.2, roof, za + 4.0))
		if w > 24.0:
			_at("tank", _p(u0 + d * 0.2, roof, zb - 4.0), 0.7)
	_at("antenna", _p(u0 + d * 0.85, roof, (za + zb) * 0.5 + 3.0), float(_hash(int(za), 5) % 6))

## Flying-saucer roof ring with a glowing rim. Returns the top height.
func _saucer(c: Vector3, R: float) -> float:
	_b.cyl(P.STEEL, c + Vector3(0, 1.0, 0), R * 0.3, R, 2.0, 24)
	_b.cyl(P.CONCRETE_PALE, c + Vector3(0, 2.45, 0), R, R * 0.86, 0.9, 24)
	_b.cyl(P.LAMP, c + Vector3(0, 2.02, 0), R + 0.05, R + 0.05, 0.22, 24, false, false)
	_b.cyl(P.STEEL, c + Vector3(0, 3.3, 0), R * 0.4, R * 0.18, 0.8, 16)
	return c.y + 3.7

## Domed roof pavilion on four posts.
func _chhatri(c: Vector3, s: float) -> void:
	_b.box(P.CONCRETE_PALE, c + Vector3(0, 0.12 * s, 0), Vector3(2.8 * s, 0.25 * s, 2.8 * s), false)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			_b.cyl(P.CONCRETE_PALE, c + Vector3(cx * 1.05 * s, 1.45 * s, cz * 1.05 * s), 0.15 * s, 0.13 * s, 2.4 * s, 6)
	_b.box(P.CONCRETE_PALE, c + Vector3(0, 2.8 * s, 0), Vector3(3.1 * s, 0.3 * s, 3.1 * s), false)
	_b.cyl(P.CONCRETE_PALE, c + Vector3(0, 3.2 * s, 0), 1.35 * s, 1.2 * s, 0.5 * s, 12)
	_b.cyl(P.CONCRETE_PALE, c + Vector3(0, 3.65 * s, 0), 1.2 * s, 0.85 * s, 0.45 * s, 12)
	_b.cyl(P.CONCRETE_PALE, c + Vector3(0, 4.05 * s, 0), 0.85 * s, 0.3 * s, 0.4 * s, 12)
	_b.cyl(P.BRASS, c + Vector3(0, 4.6 * s, 0), 0.07 * s, 0.03 * s, 0.75 * s, 6)

func _banners(u0: float, y0: float, y1: float, za: float, zb: float, bay: float) -> void:
	if y1 - y0 < 11.0:
		return
	var n := maxi(roundi((zb - za) / bay), 1)
	for k in n:
		if bay < 6.0 and k % 2 == 1:
			continue
		var z := za + (k + 0.5) * (zb - za) / n
		_at("banner", _p(u0 - 1.0, y0 + 0.9, z), _face())

## Burgundy banner with a brass wheel, authored facing +X.
static func _banner_mesh() -> Mesh:
	return Builder.cached("xw_banner", func():
		var b := Builder.new(0.0)
		b.box(P.BANNER, Vector3(0, 4.5, 0), Vector3(0.05, 9.0, 2.4), false)
		b.box(P.CHARCOAL, Vector3(0, 9.06, 0), Vector3(0.12, 0.12, 2.8), false)
		b.box(P.BRASS, Vector3(0.02, 0.08, 0), Vector3(0.06, 0.14, 2.4), false)
		var c := Vector3(0.04, 6.4, 0)
		var axis := Basis(Vector3.FORWARD, PI / 2)
		b.cyl_xf(P.BRASS, Transform3D(axis, c), 0.95, 0.95, 0.04, 20)
		b.cyl_xf(P.BANNER, Transform3D(axis, c + Vector3(0.015, 0, 0)), 0.82, 0.82, 0.04, 20)
		b.cyl_xf(P.BRASS, Transform3D(axis, c + Vector3(0.04, 0, 0)), 0.16, 0.16, 0.04, 10)
		for k in 8:
			b.box_xf(P.BRASS, Transform3D(Basis(Vector3.RIGHT, k * PI / 8.0), c + Vector3(0.04, 0, 0)), Vector3(0.03, 1.62, 0.05))
		return b.mesh())

## Concave quarter-circle buttress sweeping out from a tower end to the ground.
func _fillet(u0: float, u1: float, zf: float, dir: float, R: float) -> void:
	var n := 14
	for k in n:
		var ya := R * k / n
		var yb := R * (k + 1) / n
		var ym := (ya + yb) * 0.5
		var ext := R - sqrt(maxf(R * R - (R - ym) * (R - ym), 0.0))
		if dir > 0.0:
			_sb(P.CONCRETE, u0, u1, ya, yb + 0.02, zf, zf + ext, k < 4)
		else:
			_sb(P.CONCRETE, u0, u1, ya, yb + 0.02, zf - ext, zf, k < 4)

## Stone elephant on a plinth, facing the road.
func _elephant(z: float, u: float) -> void:
	var b := _b
	var p := _p(u, 0.0, z)
	var f := -float(_s)  # toward the road
	b.box(P.CONCRETE_DARK, p + Vector3(0, 1.6, 0), Vector3(7.0, 3.2, 4.6))
	b.box(P.CONCRETE_PALE, p + Vector3(0, 3.3, 0), Vector3(7.4, 0.3, 5.0), false)
	var s := p + Vector3(0, 3.45, 0)
	for lx: float in [-1.5, 1.5]:
		for lz: float in [-0.75, 0.75]:
			b.cyl(P.CONCRETE_PALE, s + Vector3(lx, 1.0, lz), 0.5, 0.45, 2.0, 10)
	b.box(P.CONCRETE_PALE, s + Vector3(0, 2.0, 0), Vector3(3.6, 0.6, 2.2), false)
	b.box(P.CONCRETE_PALE, s + Vector3(0, 2.9, 0), Vector3(4.4, 2.2, 2.5), false)
	b.box(P.CONCRETE_PALE, s + Vector3(-0.3 * f, 4.1, 0), Vector3(3.2, 0.4, 2.0), false)
	b.box(P.CONCRETE_PALE, s + Vector3(2.55 * f, 3.3, 0), Vector3(1.3, 1.7, 1.9), false)
	for ez: float in [-1.0, 1.0]:
		b.box(P.CONCRETE_PALE, s + Vector3(2.05 * f, 3.4, ez * 1.25), Vector3(0.25, 1.9, 1.15), false)
		b.cyl_xf(P.CONCRETE_PALE, Transform3D(Basis(Vector3.BACK, -1.1 * f), s + Vector3(3.3 * f, 2.5, ez * 0.45)), 0.08, 0.12, 0.9, 6)
	b.cyl_xf(P.CONCRETE_PALE, Transform3D(Basis(Vector3.BACK, 0.18 * f), s + Vector3(3.3 * f, 1.95, 0)), 0.22, 0.42, 2.5, 10)
	b.box(P.BANNER, s + Vector3(-0.2 * f, 3.25, 0), Vector3(2.0, 1.5, 2.58), false)
	b.box(P.BRASS, s + Vector3(-0.2 * f, 2.48, 0), Vector3(2.0, 0.1, 2.62), false)

func _stalls(x: float, zs: Array, rot: float) -> void:
	for z in zs:
		_at("stall", Vector3(x, 0.18, z), rot)
		_b.kit.add_collider(Transform3D(Basis(Vector3.UP, rot), Vector3(x, 0.68, z)), Vector3(2.4, 1.0, 1.0))
		_at("crate", Vector3(x + (1.3 if x > 0 else -1.3), 0.18, z + 1.6), float(z))

# --------------------------------------------------------------- left row

func _left(k: int) -> void:
	_row(-1)
	match k:
		0:  # Saucer hall with a jali screen and banners, small office beside.
			_block(4.0, 68.0, 24.0, 40.0, {"skin": "jali", "fins": 6.4, "banners": true, "crown": "saucer", "podium": 6.0})
			_block(74.0, 94.0, 15.0, 26.0, {"fins": 3.0, "crown": "plant"})
			_stalls(-21.5, [20.0, 26.0, 52.0], -PI / 2)
		1:  # Tower on curved buttresses between two halls.
			_block(36.0, 56.0, 74.0, 22.0, {"floor": 3.2, "crown": "needle", "setback": 1.0})
			for zf in [[36.6, -1.0], [55.4, 1.0]]:
				_fillet(2.0, 3.4, zf[0], zf[1], 16.0)
				_fillet(18.0, 19.4, zf[0], zf[1], 16.0)
			_block(2.0, 18.0, 12.0, 30.0, {"skin": "jali", "fins": 5.0, "banners": true, "crown": "none"})
			_block(74.0, 94.0, 14.0, 30.0, {"fins": 3.0, "crown": "chhatri"})
			_stalls(-21.5, [64.0, 70.0], -PI / 2)
		2:  # Stepped ministry: a temple-mountain of setbacks.
			_block(6.0, 90.0, 16.0, 46.0, {"skin": "slab", "fins": 4.0, "banners": true, "crown": "none"})
			_tier(10.0, 40.0, 16.45, 28.0, 18.0, 78.0, "windows", P.CONCRETE, 3.6, 4.0)
			_tier(18.0, 34.0, 28.45, 38.0, 32.0, 64.0, "slab", P.CONCRETE_DARK, 3.2, 3.2)
			_chhatri(_p(26.0, 39.4, 48.0), 2.4)
			for zc: float in [21.0, 75.0]:
				_chhatri(_p(13.0, 28.9, zc), 1.0)
			_stalls(-21.5, [14.0, 46.0, 52.0, 84.0], -PI / 2)
		3:  # Two towers around a plaza with the stone elephant.
			_block(4.0, 34.0, 40.0, 26.0, {"fins": 3.0, "crown": "saucer"})
			_block(60.0, 94.0, 30.0, 24.0, {"skin": "jali", "fins": 6.0, "banners": true, "crown": "chhatri"})
			_elephant(47.0, 14.0)
			for z: float in [38.0, 56.0]:
				for u: float in [4.0, 24.0]:
					_at("tree", _p(u, 0.18, z), z)
			for z: float in [40.0, 54.0]:
				_at("bench", _p(6.5, 0.18, z), -PI / 2 * _s)
			for u: float in [3.0, 8.0, 20.0, 25.0]:
				_at("planter", _p(u, 0.18, 47.0))
			_stalls(-21.5, [40.0, 46.0], -PI / 2)

# -------------------------------------------------------------- right row

func _right(k: int) -> void:
	_row(1)
	match k:
		0:
			_block(4.0, 58.0, 30.0, 30.0, {"fins": 2.4, "crown": "plant"})
			_block(64.0, 92.0, 58.0, 24.0, {"crown": "needle"})
			_stalls(17.0, [26.0, 32.0, 60.0], PI / 2)
		1:
			_block(4.0, 26.0, 22.0, 24.0, {"fins": 3.0, "crown": "plant"})
			_block(32.0, 62.0, 38.0, 28.0, {"crown": "saucer"})
			_block(68.0, 94.0, 18.0, 22.0, {"skin": "slab", "fins": 4.0, "crown": "plant"})
			_stalls(17.0, [6.0, 64.0, 70.0], PI / 2)
		2:
			_block(14.0, 40.0, 84.0, 26.0, {"floor": 3.4, "crown": "needle"})
			_block(48.0, 94.0, 10.0, 20.0, {"fins": 0.0, "crown": "plant"})
			_stalls(17.0, [36.0, 42.0], PI / 2)
			_at("kiosk", Vector3(33.6, 0.18, 8.0), PI / 2)
		3:
			_block(4.0, 44.0, 26.0, 30.0, {"fins": 4.0, "crown": "chhatri"})
			_block(52.0, 92.0, 44.0, 26.0, {"fins": 2.4, "crown": "saucer"})
			_stalls(17.0, [10.0, 56.0, 62.0, 68.0], PI / 2)
	for z: float in [12.0, 44.0, 76.0]:
		_at("booth", Vector3(34.6, 0.18, z), -PI / 2)
		_at("bin", Vector3(34.8, 0.18, z + 2.0))
	for z: float in [24.0, 88.0]:
		_at("bench", Vector3(34.9, 0.18, z), PI / 2)

# --------------------------------------------------------- feel-test yard

## The open yard beside the spawn (chunks -1 and 0): asphalt, a back wall,
## floodlight masts. The level adds the test room and handling pad.
func _yard(end_z: float) -> void:
	var b := _b
	_s = -1
	_fx = BLD_L
	var cx := (BLD_L - PAD) * 0.5
	b.box(P.ASPHALT, Vector3(cx, -0.15, L * 0.5), Vector3(PAD + BLD_L, 0.3, L))
	b.box(P.CONCRETE, Vector3(-PAD + 0.3, 1.5, L * 0.5), Vector3(0.6, 3.0, L))
	b.box(P.CONCRETE, Vector3(cx, 1.1, end_z), Vector3(PAD + BLD_L, 2.2, 0.5))
	for j in 16:
		b.box(P.CONCRETE_PALE, Vector3(-PAD + 0.75, 1.6, j * 6.0 + 3.0), Vector3(0.4, 3.2, 0.6), false)
	b.box(P.CONCRETE_PALE, Vector3(-PAD + 0.3, 3.1, L * 0.5), Vector3(0.9, 0.2, L), false)
	for x: float in [-46.0, -63.0, -78.0]:
		for j in 12:
			b.box(P.PAINT, Vector3(x, 0.012, j * 8.0 + 2.0), Vector3(0.14, 0.012, 3.0), false)
	for z: float in [12.0, 44.0, 76.0]:
		_at("antenna", Vector3(-PAD + 1.6, 0.0, z))
		_at("lamp", Vector3(-PAD + 1.2, 0.0, z + 16.0))

# ============================================================== skyline

func _far(side: int, seed_: int) -> void:
	var b := _b
	_rng.seed = seed_
	b.box(P.CONCRETE_DARK, Vector3(side * (PAD + 200.0), -0.1, L * 0.5), Vector3(400.0, 0.1, L), false)
	for pass_ in 2:
		var z := _rng.randf_range(0.0, 14.0)
		while z < L - 10.0:
			var w := _rng.randf_range(16.0, 30.0)
			var d := _rng.randf_range(16.0, 30.0)
			var h := _rng.randf_range(32.0, 75.0) if pass_ == 0 else _rng.randf_range(60.0, 140.0)
			var u := _rng.randf_range(10.0, 45.0) if pass_ == 0 else _rng.randf_range(80.0, 190.0)
			var x := side * (PAD + u + d * 0.5)
			var zc := minf(z + w * 0.5, L - w * 0.5)
			var near := x - side * (d * 0.5 + 0.06)
			b.block(P.CONCRETE_DARK if _rng.randf() < 0.4 else P.CONCRETE, Vector3(x, 0, zc), Vector3(d, h, w), false)
			b.box(P.WINDOWS, Vector3(near, h * 0.5 + 2.0, zc), Vector3(0.1, h - 6.0, w * 0.8), false)
			b.box(P.WINDOWS, Vector3(x, h * 0.5 + 2.0, zc - w * 0.5 - 0.06), Vector3(d * 0.8, h - 6.0, 0.1), false)
			b.box(P.WINDOWS, Vector3(x, h * 0.5 + 2.0, zc + w * 0.5 + 0.06), Vector3(d * 0.8, h - 6.0, 0.1), false)
			var y := 7.2
			while y < h - 3.0:
				b.box(P.CONCRETE_PALE, Vector3(x, y, zc), Vector3(d + 0.9, 0.45, w + 0.9), false)
				y += 7.2
			b.box(P.CONCRETE_PALE, Vector3(x, h + 0.3, zc), Vector3(d + 1.2, 0.6, w + 1.2), false)
			var r := _rng.randf()
			if r < 0.25:
				_b.cyl(P.CONCRETE, Vector3(x, h + 3.0, zc), 3.0, 2.6, 5.0, 12)
				_saucer(Vector3(x, h + 5.5, zc), minf(w, d) * 0.7)
			elif r < 0.45:
				_b.cyl(P.STEEL, Vector3(x, h + 10.0, zc), 0.8, 0.1, 20.0, 6)
			elif r < 0.6:
				_b.block(P.CONCRETE_DARK, Vector3(x, h, zc), Vector3(d * 0.6, 8.0, w * 0.6), false)
			z += w + _rng.randf_range(5.0, 24.0)
