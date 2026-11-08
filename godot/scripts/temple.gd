extends "res://scripts/province.gd"
## The Great Temple of the Hiranyavaha Circle [INVENTED]: "Nothing Unobserved",
## Mission2.md. Built to refs/kexterior, kstaircase, kinterior and kcarving: a
## rock-cut temple of dark basalt, climbing from the pilgrim road by two great
## stairs to a colonnade and a carved nave. Everything the crowd and the eyes
## decide lives in core/; this script is geometry, staging and wiring.
##
## Plan view (-Z is north, into the cliff):
##   z 192+    the A1 Mauryan Way (Expressway)
##   z 130     south gate
##   z 130..40 forecourt, y = 0
##   z 40..22  grand stair in its trench, rising to y = 9, under the ring arch
##   z 22..-14 middle terrace, y = 9: lamp pedestals, gantries, balloons
##   z -14..-26 second stair, rising to y = 15
##   z -26..-46 upper terrace and colonnade, y = 15
##   z -46..-94 the nave and sanctum; east wing Reception, west wing Monitoring

const Expressway = preload("res://scripts/expressway.gd")
const Traffic = preload("res://scripts/traffic.gd")

const Y1 := 9.0
const Y2 := 15.0
const GATE_Z := 130.0
const ROAD_START_Z := 192.0

const ZONE_NAMES := {"forecourt": "the forecourt", "grand_stair": "the grand stair", "terrace": "the middle terrace",
	"upper": "the upper terrace", "nave": "the nave", "reception": "the reception wing"}
## Restricted rooms: x0, x1, y0, y1, z0, z1.
const RESTRICTED := [[11.2, 60.0, 14.0, 30.0, -90.0, -47.0], [-34.5, -11.2, 14.0, 30.0, -78.0, -47.0], [-11.0, 11.0, 14.0, 30.0, -94.0, -80.0]]
const INDOORS := [[-34.5, 34.5, 14.0, 32.0, -94.0, -46.5], [20.0, 30.0, 14.0, 30.0, -86.0, -76.0]]
## Governor's route, there and back.
const PROCESSION := ["rec_door", "nave_mid", "nave_s", "col_c", "t2_c", "s2_top", "s2_bot", "t1_c", "s1_top", "s1_bot", "fc_mid", "fc_turn",
	"fc_mid", "s1_bot", "s1_top", "t1_c", "s2_bot", "s2_top", "t2_c", "col_c", "nave_s", "nave_mid"]

var eyes := {}
var zones_of := {}
var crowd: CrowdField
var road: Expressway
var traffic: Traffic
var safehouse: AABB
var retinue: Array[Npc] = []
var liaison: Npc
var operators: Array[Npc] = []
var pursuers: Array[BikeController] = []
var hunter_drones: Array[Eye] = []
var _slots: Array[Dictionary] = []
var _slot_t := 0.0
var _report_t := 0.0
var _reports := 0
var _proc_i := -1
var _reset_timers := {}
var _pursuit_started := false
var _road_on := false
var _crush_reported := false
var _lose_note := false
var _shot_t := 0.0
var _params := {}
var _tt_t := 0.0
var _tt_step := 0

# ============================================================== build

func build_world() -> void:
	replay_gov = "gov_hiranyavaha"
	if not Game.sim.mission_active() or Game.sim.mission_scene() != scene_file_path:
		Game.sim.start_mission_for("gov_hiranyavaha")
	_info = Game.sim.mission_info()
	_params = Game.sim.pursuit_params()
	P.load_relief()
	_build_ground()
	_build_cliffs()
	_build_lower()
	_build_stair()
	_build_terrace()
	_build_upper()
	_build_nave()
	_build_wings()
	_build_pit()
	_build_road()
	_build_props()
	_build_nav()
	_build_interactables()
	_build_audio()
	_build_crowd()

func player_spawn() -> Array:
	return [Vector3(3.5, 0.3, 150.0), 0.0]

func after_spawn() -> void:
	bike = spawn_bike(Vector3(7.0, 0.6, 148.0), 0.0)
	_build_eyes()
	_spawn_npcs()
	traffic_obstacles()
	hud.message("HIRANYAVAHA CIRCLE. %s. Festival day." % _info.get("title", ""))
	hud.message("Target: %s. TAB for the dossier." % _info.get("governor", "the governor"))

func traffic_obstacles() -> void:
	if traffic:
		traffic.obstacles = [bike, player]

# ---- helpers

func _rock(b: Builder, c: Vector3, s: Vector3, sd: int, seg := 6, rough := 1.0) -> void:
	b.kit.add_rock(P.ROCK, Transform3D(Basis(Vector3.UP, sd * 0.31), c), s, sd, seg, rough)

func _collider(b: Builder, c: Vector3, s: Vector3) -> void:
	b.kit.add_collider(Builder.xf(c), s)

func _light(p: Vector3, r: float, e: float, col: String) -> void:
	var o := OmniLight3D.new()
	o.position = p
	o.omni_range = r
	o.light_energy = e
	o.light_color = Color(col)
	o.shadow_enabled = false
	o.distance_fade_enabled = true
	o.distance_fade_begin = 60.0
	o.distance_fade_length = 20.0
	add_child(o)

## A carved face: a thin relief plate on a wall.
func _relief_x(b: Builder, x: float, y0: float, y1: float, z0: float, z1: float) -> void:
	b.box(P.RELIEF, Vector3(x, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(0.12, y1 - y0, absf(z1 - z0)), false)

func _relief_z(b: Builder, z: float, x0: float, x1: float, y0: float, y1: float) -> void:
	b.box(P.RELIEF, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z), Vector3(absf(x1 - x0), y1 - y0, 0.12), false)

## A bulging ribbed column on a square base, as in kinterior.
func _ribbed(b: Builder, slot: int, c: Vector3, h: float, r: float, plinth := -1) -> void:
	if plinth >= 0:
		b.box(plinth, c + Vector3(0, 0.55, 0), Vector3(r * 2.8, 1.1, r * 2.8), false)
		b.box(P.BRASS, c + Vector3(0, 1.12, 0), Vector3(r * 2.9, 0.05, r * 2.9), false)
	var y := 1.1 if plinth >= 0 else 0.0
	var n := 7
	var sec := (h - y) / n
	for i in n:
		var k := sin((i + 0.5) / n * PI)
		var rr := r * (0.78 + 0.34 * k)
		b.cyl(slot, c + Vector3(0, y + sec * (i + 0.5), 0), rr, rr * 0.97, sec * 0.8, 12)
		b.cyl(slot, c + Vector3(0, y + sec * (i + 0.95), 0), rr * 1.05, rr * 1.05, sec * 0.14, 12)
	b.box(slot, c + Vector3(0, h - 0.2, 0), Vector3(r * 3.0, 0.4, r * 3.0), false)
	_collider(b, c + Vector3(0, h * 0.5, 0), Vector3(r * 1.9, h, r * 1.9))

## A caparisoned stone elephant on a plinth, facing `dir` along z.
func _elephant_statue(b: Builder, c: Vector3, s: float, dir: float) -> void:
	b.box(P.STONE, c + Vector3(0, 1.0, 0), Vector3(3.6 * s, 2.0, 6.2 * s))
	b.box(P.STONE, c + Vector3(0, 2.1, 0), Vector3(3.9 * s, 0.25, 6.5 * s), false)
	var y := c.y + 2.2
	var k := Basis(Vector3.BACK, 0.0)
	for lx in [-0.8, 0.8]:
		for lz in [-1.5, 1.5]:
			b.cyl(P.ROCK, Vector3(c.x + lx * s, y + 0.9 * s, c.z + lz * s * dir), 0.5 * s, 0.56 * s, 1.8 * s, 10)
	b.box_xf(P.ROCK, Transform3D(k, Vector3(c.x, y + 2.5 * s, c.z)), Vector3(2.3 * s, 2.2 * s, 4.2 * s))
	b.box_xf(P.ROCK, Transform3D(k, Vector3(c.x, y + 2.9 * s, c.z + 2.6 * dir * s)), Vector3(1.8 * s, 1.9 * s, 1.5 * s))
	# Ears, trunk in segments, tusks.
	for e in [-1.0, 1.0]:
		b.box(P.ROCK, Vector3(c.x + e * 1.2 * s, y + 3.0 * s, c.z + 2.4 * dir * s), Vector3(0.2 * s, 1.5 * s, 1.2 * s), false)
		b.box_xf(P.IVORY, Transform3D(Basis(Vector3.RIGHT, dir * 0.9), Vector3(c.x + e * 0.5 * s, y + 2.0 * s, c.z + 3.4 * dir * s)), Vector3(0.14 * s, 0.14 * s, 1.1 * s))
	for i in 5:
		var fi := float(i)
		b.cyl(P.ROCK, Vector3(c.x, y + (2.1 - fi * 0.42) * s, c.z + (3.4 + fi * 0.07) * dir * s), (0.32 - fi * 0.03) * s, (0.26 - fi * 0.03) * s, 0.5 * s, 8)
	# Burgundy caparison with a brass hem, and a stone howdah base.
	b.box(P.BURGUNDY, Vector3(c.x, y + 2.5 * s, c.z - 0.2 * dir * s), Vector3(2.42 * s, 1.9 * s, 2.5 * s), false)
	b.box(P.BRASS, Vector3(c.x, y + 1.55 * s, c.z - 0.2 * dir * s), Vector3(2.46 * s, 0.14 * s, 2.54 * s), false)
	b.box(P.STONE, Vector3(c.x, y + 3.75 * s, c.z - 0.2 * dir * s), Vector3(1.7 * s, 0.4 * s, 2.0 * s), false)

## Square lamp pedestal: stone, an amber lantern on top, a green CRT in its face.
static func _pedestal() -> Mesh:
	return Builder.cached("temple_pedestal", func():
		var b := Builder.new(0.25)
		b.box(P.STONE, Vector3(0, 0.15, 0), Vector3(1.1, 0.3, 1.1), false)
		b.box(P.STONE, Vector3(0, 1.1, 0), Vector3(0.8, 1.7, 0.8), false)
		b.box(P.STONE, Vector3(0, 2.0, 0), Vector3(1.0, 0.14, 1.0), false)
		b.box(P.CHARCOAL, Vector3(0, 1.3, 0.405), Vector3(0.56, 0.46, 0.02), false)
		b.box(P.CRT, Vector3(0, 1.3, 0.418), Vector3(0.44, 0.34, 0.01), false)
		b.box(P.BRASS, Vector3(0, 2.1, 0), Vector3(0.5, 0.06, 0.5), false)
		for x in [-0.2, 0.2]:
			for z in [-0.2, 0.2]:
				b.box(P.BRASS, Vector3(x, 2.4, z), Vector3(0.03, 0.56, 0.03), false)
		b.cyl(P.LAMP, Vector3(0, 2.4, 0), 0.19, 0.19, 0.5, 8)
		b.cyl(P.BRASS, Vector3(0, 2.74, 0), 0.34, 0.06, 0.16, 8)
		return b.mesh())

static func _banner_arch() -> Mesh:
	return Builder.cached("temple_banner", func():
		var b := Builder.new(0.0)
		b.box(P.BANNER, Vector3(0, -3.0, 0), Vector3(2.0, 6.0, 0.06), false)
		b.box(P.BRASS, Vector3(0, -0.05, 0), Vector3(2.2, 0.1, 0.1), false)
		b.box(P.BRASS, Vector3(0, -6.0, 0), Vector3(2.0, 0.06, 0.08), false)
		# A plain spoked wheel, as in kstaircase.
		var t := Basis(Vector3.RIGHT, PI / 2)
		b.cyl_xf(P.BRASS, Transform3D(t, Vector3(0, -2.6, 0.04)), 0.62, 0.62, 0.02, 20)
		b.cyl_xf(P.BANNER, Transform3D(t, Vector3(0, -2.6, 0.05)), 0.52, 0.52, 0.02, 20)
		for i in 4:
			b.box_xf(P.BRASS, Transform3D(Basis(Vector3.BACK, i * PI / 4), Vector3(0, -2.6, 0.06)), Vector3(1.04, 0.05, 0.01))
		return b.mesh())

# ---- ground and rock

func _build_ground() -> void:
	var b := Builder.new()
	# Forecourt, x +-48, and everything under it.
	b.box(P.STONE, Vector3(0, -0.5, 85), Vector3(96, 1, 90))
	b.box(P.ROCK, Vector3(0, -0.5, -60), Vector3(240, 1, 200), true)
	b.box(P.ROAD, Vector3(0, 0.01, 85), Vector3(9, 0.02, 90), false)
	# Processional paving, kerbs of dressed stone.
	for s in [-1, 1]:
		b.box(P.STONE, Vector3(s * 4.9, 0.08, 85), Vector3(0.7, 0.16, 90))
	b.box(P.ROAD, Vector3(0, -0.02, 161), Vector3(32, 0.04, 62))
	# World edge.
	for w in [[Vector3(0, 30, 1500), Vector3(600, 80, 1)]]:
		_collider(b, w[0], w[1])
	b.commit(self, "Ground")

## Cliffs close the site on three sides, like the cut in kexterior.
func _build_cliffs() -> void:
	var b := Builder.new(0.2)
	var sd := 3
	# West wall of the cut, east wall past the pit, and the north face.
	for z in [120.0, 88.0, 56.0, 24.0, -8.0, -40.0, -72.0, -104.0]:
		sd += 1
		_rock(b, Vector3(-68, 21, z), Vector3(42, 58, 40), sd, 7, 1.6)
		_collider(b, Vector3(-68, 20, z), Vector3(40, 60, 40))
		sd += 1
		_rock(b, Vector3(84, 22, z), Vector3(42, 62, 40), sd, 7, 1.6)
		_collider(b, Vector3(84, 20, z), Vector3(40, 60, 40))
	for x in [-60.0, -22.0, 16.0, 54.0]:
		sd += 1
		_rock(b, Vector3(x, 28, -124), Vector3(44, 74, 44), sd, 8, 2.0)
		_collider(b, Vector3(x, 28, -124), Vector3(42, 74, 42))
	# The road gorge south of the gate.
	for z in [146.0, 176.0]:
		for s in [-1, 1]:
			sd += 1
			_rock(b, Vector3(s * 36, 12, z), Vector3(36, 30, 34), sd, 5, 1.2)
			_collider(b, Vector3(s * 36, 10, z), Vector3(38, 30, 34))
	# Far mountains, fogged, over the rim. No colliders.
	for m in [[Vector3(-170, 40, -120), Vector3(180, 110, 140)], [Vector3(0, 55, -240), Vector3(300, 140, 120)],
			[Vector3(180, 44, -90), Vector3(170, 120, 160)], [Vector3(-210, 30, 90), Vector3(160, 90, 220)],
			[Vector3(220, 30, 110), Vector3(170, 90, 220)]]:
		sd += 1
		_rock(b, m[0], m[1], sd, 6, 5.0)
	var mi := b.commit(self, "Cliffs")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_occluder(Vector3(0, 28, -112), Vector3(120, 56, 8))

# ---- forecourt

func _build_lower() -> void:
	var b := Builder.new()
	# South gate: two battered pylons with burgundy hangings and a lintel.
	for s in [-1, 1]:
		b.block(P.STONE, Vector3(s * 14.5, 0, GATE_Z), Vector3(9, 15, 7))
		b.block(P.ROCK, Vector3(s * 14.5, 15, GATE_Z), Vector3(10, 1.0, 8), false)
		_relief_z(b, GATE_Z - 3.56, s * 14.5 - 4, s * 14.5 + 4, 1.5, 13.5)
		_relief_z(b, GATE_Z + 3.56, s * 14.5 - 4, s * 14.5 + 4, 1.5, 13.5)
		b.box(P.BANNER, Vector3(s * 10.0, 7.5, GATE_Z - 2.0), Vector3(0.08, 10, 2.2), false)
		# Walls from the gate to the cut.
		b.block(P.STONE, Vector3(s * 34, 0, GATE_Z), Vector3(30, 7.0, 3))
		b.box(P.CHARCOAL, Vector3(s * 34, 7.2, GATE_Z), Vector3(30, 0.4, 3.3), false)
	b.box(P.STONE, Vector3(0, 13.2, GATE_Z), Vector3(11.0, 2.4, 4.2))
	b.box(P.BRASS, Vector3(0, 11.9, GATE_Z - 2.15), Vector3(11.0, 0.18, 0.1), false)
	b.box(P.AMBER, Vector3(0, 13.3, GATE_Z - 2.15), Vector3(6.0, 0.24, 0.05), false)
	# Stalls and offering tables along the forecourt.
	var stalls := []
	for z in [60.0, 78.0, 96.0, 114.0]:
		stalls.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-27, 0, z)))
		stalls.append(Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(27, 0, z)))
		_collider(b, Vector3(-27, 0.5, z), Vector3(1.0, 1.0, 2.4))
		_collider(b, Vector3(27, 0.5, z), Vector3(1.0, 1.0, 2.4))
	b.commit(self, "Forecourt")
	Builder.scatter(self, Builder.stall(), stalls, 130.0)
	# Lamp pedestals line the pilgrim road.
	var lamps := []
	var lb := Builder.new()
	for z in [52.0, 68.0, 84.0, 100.0, 116.0]:
		for s in [-1, 1]:
			lamps.append(Transform3D(Basis(Vector3.UP, PI / 2 * -s), Vector3(s * 7.0, 0, z)))
			_collider(lb, Vector3(s * 7.0, 1.0, z), Vector3(0.8, 2.0, 0.8))
	for x in [-30.0, -18.0, 18.0, 30.0]:
		for z in [4.0, 18.0]:
			lamps.append(Transform3D(Basis(Vector3.UP, 0.0), Vector3(x, Y1, z)))
			_collider(lb, Vector3(x, Y1 + 1.0, z), Vector3(0.8, 2.0, 0.8))
	for x in [-26.0, -10.0, 10.0, 26.0]:
		lamps.append(Transform3D(Basis(), Vector3(x, Y2, -33)))
		_collider(lb, Vector3(x, Y2 + 1.0, -33), Vector3(0.8, 2.0, 0.8))
	lb.commit(self, "LampCol")
	Builder.scatter(self, _pedestal(), lamps, 170.0)

# ---- the great stair in its trench

func _build_stair() -> void:
	var b := Builder.new()
	var run := 0.6
	var rise := 0.3
	# The block the terrace stands on, with the stair cut through it.
	for s in [-1, 1]:
		b.block(P.STONE, Vector3(s * 22.0, 0, 31), Vector3(28, Y1, 18))
		_relief_z(b, 40.07, s * 8.0, s * 36.0, 0.0, Y1 - 0.5)
		_relief_x(b, s * 7.94, 0.0, Y1, 22.0, 40.0)
		b.box(P.CHARCOAL, Vector3(s * 22.0, Y1 + 0.5, 39.6), Vector3(28, 1.0, 0.7))
		b.box(P.BRASS, Vector3(s * 22.0, Y1 + 1.05, 39.6), Vector3(28, 0.06, 0.08), false)
		b.box(P.STONE, Vector3(s * 7.8, Y1 + 0.5, 30.5), Vector3(0.5, 1.0, 17))
	b.stairs(P.STONE, Vector3(0, 0, 40), 16.0, rise, run, 30, PI, true)
	# Central ramp and rails, brass on the stone.
	for x in [-2.6, 2.6]:
		var ang := atan2(Y1, 18.0)
		var t := Transform3D(Basis(Vector3.RIGHT, ang), Vector3(x, 5.3, 31))
		b.box_xf(P.BRASS, t, Vector3(0.1, 0.08, 20.1))
		for i in 7:
			var fi := float(i)
			b.box(P.BRASS, Vector3(x, 1.0 + fi * 1.37, 38.5 - fi * 2.75), Vector3(0.06, 1.0, 0.06), false)
	# Pipes and cables along the trench, as in kstaircase: black mains with
	# brass collars, pulled up the wall.
	var pipe_slot := [P.BLACK, P.BLACK, P.BRASS]
	for s in [-1, 1]:
		for k in 3:
			var r := 0.42 - k * 0.1
			var off := float(k) * 0.95
			var a := atan2(Y1, 18.0)
			var bs := Basis(Vector3.RIGHT, PI / 2 + a)
			var c := Vector3(s * (7.45 - off * 0.05), 3.7 + off * 1.1, 31)
			b.cyl_xf(pipe_slot[k], Transform3D(bs, c), r, r, 20.5, 10)
			for i in 5:
				var u := -8.0 + i * 4.0
				b.cyl_xf(P.BRASS, Transform3D(bs, c + bs.y * u), r + 0.07, r + 0.07, 0.16, 10)
	# Stone elephants at the foot of the stair.
	for s in [-1, 1]:
		_elephant_statue(b, Vector3(s * 11.5, 0, 46), 1.2, 1.0)
	b.commit(self, "GrandStair")
	# Ring arch viaduct over the stair, a curved beam on two towers.
	var a := Builder.new()
	var R := 27.0
	var cy := 11.0
	var segs := 22
	for i in segs:
		var t0 := (float(i) + 0.5) / segs * PI
		var c := Vector3(cos(t0) * R, cy + sin(t0) * R * 0.62, 26.0)
		var tang := atan2(cos(t0) * R * 0.62, -sin(t0) * R)
		var basis := Basis(Vector3.BACK, tang)
		a.box_xf(P.CONCRETE_DARK, Transform3D(basis, c), Vector3(PI * R / segs * 1.15, 1.4, 3.0))
		a.box_xf(P.BRASS, Transform3D(basis, c + Vector3(0, 0, 1.56)), Vector3(PI * R / segs * 1.15, 0.1, 0.06))
		a.box_xf(P.WINDOWS, Transform3D(basis, c + Vector3(0, 0.2, -1.52)), Vector3(PI * R / segs * 0.8, 0.4, 0.04))
	for s in [-1, 1]:
		a.block(P.STONE, Vector3(s * R, Y1, 26), Vector3(4, 12, 4))
	a.commit(self, "RingArch")
	var banners := []
	for x in [-16.0, -11.0, -6.0, 6.0, 11.0, 16.0]:
		var yy := cy + sqrt(maxf(0.0, 1.0 - x * x / (R * R))) * R * 0.62 - 0.8
		banners.append(Transform3D(Basis(), Vector3(x, yy, 27.7)))
	Builder.scatter(self, _banner_arch(), banners, 180.0, false)

# ---- middle terrace

func _build_terrace() -> void:
	var b := Builder.new()
	# Terrace body, and the wall with the second stair cut through it.
	b.block(P.STONE, Vector3(-22, 0, 4), Vector3(28.0, Y1, 36))
	b.block(P.STONE, Vector3(22, 0, 4), Vector3(28.0, Y1, 36))
	b.block(P.STONE, Vector3(0, 0, 4), Vector3(16, Y1, 36))
	b.box(P.STONE, Vector3(0, Y1 + 0.01, 4), Vector3(72, 0.02, 36), false)
	b.box(P.ROAD, Vector3(0, Y1 + 0.02, 4), Vector3(9, 0.02, 36), false)
	# Parapets at the sides.
	for s in [-1, 1]:
		b.box(P.STONE, Vector3(s * 36, Y1 + 0.5, 13), Vector3(0.6, 1.0, 54))
		b.box(P.BRASS, Vector3(s * 36, Y1 + 1.03, 13), Vector3(0.7, 0.06, 54), false)
	# The upper block: y up to Y2, stair trench through the middle.
	for s in [-1, 1]:
		b.block(P.STONE, Vector3(s * 21, 0, -20), Vector3(30, Y2, 12))
		_relief_z(b, -13.94, s * 6.0, s * 36.0, Y1, Y2)
		_relief_x(b, s * 5.94, Y1, Y2, -26.0, -14.0)
	b.stairs(P.STONE, Vector3(0, Y1, -14), 12.0, 0.3, 0.6, 20, PI, true)
	# Giant green screens framed in the wall, as at the head of the stair in kstaircase.
	for s in [-1, 1]:
		var x: float = s * 20.0
		b.box(P.CONCRETE_DARK, Vector3(x, Y1 + 3.1, -13.75), Vector3(11.0, 5.4, 0.3), false)
		b.box(P.CRT, Vector3(x, Y1 + 3.1, -13.58), Vector3(9.8, 4.4, 0.04), false)
		b.box(P.BEIGE, Vector3(x, Y1 + 0.6, -13.4), Vector3(9.8, 0.5, 0.6))
	b.commit(self, "Terrace")
	_occluder(Vector3(0, Y1 * 0.5, 22.5), Vector3(70, Y1 - 0.5, 1))

# ---- upper terrace, colonnade, flanking towers, gopuram

func _build_upper() -> void:
	var b := Builder.new()
	b.block(P.STONE, Vector3(0, 0, -36), Vector3(72, Y2, 20))
	b.box(P.STONE, Vector3(0, Y2 + 0.01, -36), Vector3(72, 0.02, 20), false)
	for s in [-1, 1]:
		b.box(P.STONE, Vector3(s * 36, Y2 + 0.5, -32), Vector3(0.6, 1.0, 14))
	# Colonnade: tall carved pillars with a beam across them.
	var ph := 15.0
	for x in [-14.0, -9.0, -4.5, 4.5, 9.0, 14.0]:
		_ribbed(b, P.STONE, Vector3(x, Y2, -43.5), ph, 1.05, P.STONE)
	b.box(P.STONE, Vector3(0, Y2 + ph + 0.8, -43.5), Vector3(36, 1.6, 4.0))
	b.box(P.BRASS, Vector3(0, Y2 + ph - 0.05, -41.46), Vector3(36, 0.1, 0.1), false)
	# The rock facade behind, with the great door. The door is the nave's mouth.
	var fy := 25.0
	var door := 9.0
	for s in [-1, 1]:
		b.block(P.STONE, Vector3(s * (door + 17.0 * 0.5 + 8.5), Y2, -46.5), Vector3(34.0 - 17.0 + 17.0, fy, 1.5))
		_relief_z(b, -45.68, s * door, s * 34.5, Y2 + 0.5, Y2 + fy - 2.0)
	b.block(P.STONE, Vector3(0, Y2 + 13.0, -46.5), Vector3(door * 2.0, fy - 13.0, 1.5))
	_relief_z(b, -45.68, -door, door, Y2 + 13.0, Y2 + fy - 2.0)
	# Flanking towers with giant relief panels (kexterior).
	for s in [-1, 1]:
		var tx: float = s * 34.0
		b.block(P.STONE, Vector3(tx, Y2, -40), Vector3(12, 40, 10))
		_relief_z(b, -34.94, tx - 5.2, tx + 5.2, Y2 + 2.0, Y2 + 26.0)
		b.box(P.CHARCOAL, Vector3(tx, Y2 + 27.0, -34.9), Vector3(10.6, 0.4, 0.2), false)
		_relief_z(b, -34.94, tx - 5.2, tx + 5.2, Y2 + 28.0, Y2 + 38.0)
		b.block(P.ROCK, Vector3(tx, Y2 + 40, -40), Vector3(10, 1.4, 8), false)
		for k in 3:
			b.block(P.STONE, Vector3(tx, Y2 + 41.4 + k * 3.2, -40), Vector3(8.0 - k * 2.0, 3.2, 6.5 - k * 1.6), false)
		b.cyl(P.BRASS, Vector3(tx, Y2 + 52.0, -40), 0.2, 0.05, 3.0, 8)
		b.cyl(P.AMBER, Vector3(tx, Y2 + 53.6, -40), 0.3, 0.3, 0.3, 8, false, true)
	# Gopuram: seven receding tiers, each with a row of little pillars and a
	# lit strip. Antennas and dishes crowd the top, as if the temple had been
	# wired by whoever was paying for it.
	var w := 34.0
	var d := 26.0
	var y := Y2 + fy
	var pilx := []
	for k in 7:
		var fk := float(k)
		var h := 5.0 - fk * 0.28
		b.block(P.STONE, Vector3(0, y, -60), Vector3(w, h, d), false)
		_relief_z(b, -60 + d * 0.5 + 0.07, -w * 0.5 + 1.0, w * 0.5 - 1.0, y + 0.6, y + h - 0.8)
		b.box(P.ROCK, Vector3(0, y + h, -60), Vector3(w + 1.0, 0.45, d + 1.0), false)
		b.box(P.AMBER if k % 2 == 1 else P.WINDOWS, Vector3(0, y + h - 0.3, -60 + d * 0.5 + 0.08), Vector3(w * 0.7, 0.2, 0.05), false)
		var n := int(w / 3.2)
		for i in n:
			pilx.append(Transform3D(Basis().scaled(Vector3(0.7, h * 0.33, 0.7)), Vector3(-w * 0.5 + (i + 0.5) * w / n, y, -60 + d * 0.5 + 0.5)))
		y += h + 0.45
		w -= 4.2
		d -= 2.6
	var top := y
	b.block(P.CONCRETE_DARK, Vector3(0, top, -60), Vector3(w + 1.0, 2.0, d + 1.0), false)
	b.cyl(P.BRASS, Vector3(0, top + 5.0, -60), 0.8, 0.0, 8.0, 12)
	b.commit(self, "Upper")
	Builder.scatter(self, Builder.cached("temple_minipil", func():
		var p := Builder.new(0.0)
		p.cyl(P.STONE, Vector3(0, 1.5, 0), 0.34, 0.26, 3.0, 8)
		p.box(P.STONE, Vector3(0, 3.05, 0), Vector3(0.9, 0.2, 0.9), false)
		return p.mesh()), pilx, 240.0, false)
	# Antenna forest.
	var masts := []
	var dishes := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 326
	for i in 26:
		var pos := Vector3(rng.randf_range(-w * 0.5, w * 0.5), top + 2.0, -60 + rng.randf_range(-d * 0.5, d * 0.5))
		masts.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.2, rng.randf_range(1.2, 2.8), 1.2)), pos))
	for i in 9:
		var ang := rng.randf() * TAU
		dishes.append(Transform3D(Basis(Vector3.UP, ang).scaled(Vector3.ONE * rng.randf_range(1.0, 1.8)),
			Vector3(rng.randf_range(-w * 0.6, w * 0.6), top + 2.0, -60 + rng.randf_range(-d * 0.6, d * 0.6))))
	Builder.scatter(self, Builder.antenna(), masts, 400.0, false)
	Builder.scatter(self, Builder.cached("temple_dish", func():
		var p := Builder.new(0.0)
		p.cyl(P.CHARCOAL, Vector3(0, 0.6, 0), 0.08, 0.08, 1.2, 6)
		p.cyl_xf(P.CONCRETE_PALE, Transform3D(Basis(Vector3.RIGHT, 1.0), Vector3(0, 1.4, 0)), 0.15, 1.1, 0.5, 14)
		return p.mesh()), dishes, 400.0, false)

# ---- nave and sanctum

func _build_nave() -> void:
	var b := Builder.new(0.25)
	var cz := -70.0
	var dz := 48.0
	# The rock everything north of the facade is cut into: it is the floor.
	b.block(P.ROCK, Vector3(0, 0, -72), Vector3(72, Y2, 52))
	b.box(P.MARBLE, Vector3(0, Y2 + 0.02, cz), Vector3(22, 0.04, dz), false)
	b.box(P.CARPET, Vector3(0, Y2 + 0.05, cz + 2.0), Vector3(7, 0.02, 34), false)
	b.box(P.ROCK, Vector3(0, Y2 + 17.0, cz), Vector3(24, 1.0, dz + 1.0))
	# Side walls with doors into the wings.
	for s in [-1, 1]:
		b.wall_z(P.STONE, -94, -47, s * 11.0, Y2, 16.0, 0.8, [[-66, -62, 0, 3.4]])
		_relief_x(b, s * 10.54, Y2 + 5.0, Y2 + 16.0, -92.0, -49.0)
		b.box(P.WALNUT, Vector3(s * 10.5, Y2 + 1.5, -80), Vector3(0.06, 3.0, 26), false)
		b.box(P.WALNUT, Vector3(s * 10.5, Y2 + 1.5, -55), Vector3(0.06, 3.0, 14), false)
		b.box(P.BRASS, Vector3(s * 10.46, Y2 + 3.03, -80), Vector3(0.08, 0.05, 26), false)
		b.box(P.BRASS, Vector3(s * 10.46, Y2 + 3.03, -55), Vector3(0.08, 0.05, 14), false)
	b.box(P.STONE, Vector3(0, Y2 + 8.0, -94.5), Vector3(24, 16, 1.0))
	_relief_z(b, -93.94, -11, 11, Y2 + 7.5, Y2 + 16.0)
	# Bulging ribbed columns on walnut plinths.
	for z in [-52.0, -60.0, -68.0, -76.0]:
		for s in [-1, 1]:
			_ribbed(b, P.STONE, Vector3(s * 6.8, Y2, z), 16.0, 0.95, P.WALNUT)
	# The sanctum: a raised dais behind a brass rail, a seated guardian figure
	# in gold, lamps. A plain court figure; see LORE.md rule 3.
	b.block(P.MARBLE, Vector3(0, Y2, -88), Vector3(14, 0.8, 8))
	b.stairs(P.MARBLE, Vector3(0, Y2, -83.0), 6.0, 0.2, 0.25, 4, PI, true)
	for x in [-7.0, -5.0, -3.0, 3.0, 5.0, 7.0]:
		b.box(P.BRASS, Vector3(x, Y2 + 0.55, -80.5), Vector3(0.07, 1.1, 0.07))
	b.box(P.BRASS, Vector3(-5.0, Y2 + 1.1, -80.5), Vector3(4.2, 0.06, 0.08), false)
	b.box(P.BRASS, Vector3(5.0, Y2 + 1.1, -80.5), Vector3(4.2, 0.06, 0.08), false)
	_collider(b, Vector3(-5.0, Y2 + 0.5, -80.5), Vector3(4.2, 1.0, 0.2))
	_collider(b, Vector3(5.0, Y2 + 0.5, -80.5), Vector3(4.2, 1.0, 0.2))
	var gold := P.BRASS
	var c := Vector3(0, Y2 + 0.8, -91)
	b.block(P.WALNUT, c, Vector3(3.8, 1.1, 2.6))
	b.box(gold, c + Vector3(0, 1.55, 0.3), Vector3(3.0, 0.8, 1.9), false)
	b.cyl(gold, c + Vector3(0, 2.95, 0), 0.72, 0.82, 2.1, 12)
	b.cyl(gold, c + Vector3(0, 4.35, 0), 0.42, 0.42, 0.72, 12)
	b.cyl(gold, c + Vector3(0, 4.85, 0), 0.44, 0.2, 0.5, 12)
	for s in [-1, 1]:
		b.box_xf(gold, Transform3D(Basis(Vector3.RIGHT, -0.9), c + Vector3(s * 0.95, 2.5, 0.5)), Vector3(0.28, 0.28, 1.6))
	for x in [-5.5, -3.5, 3.5, 5.5]:
		b.cyl(P.BRASS, Vector3(x, Y2 + 1.4, -86.5), 0.12, 0.2, 1.2, 8)
		b.cyl(P.LAMP, Vector3(x, Y2 + 2.05, -86.5), 0.15, 0.09, 0.24, 8)
	b.commit(self, "Nave", 260.0)
	_occluder(Vector3(0, Y2 + 8, -47), Vector3(68, 16, 1))
	# Brass ring chandeliers.
	for z in [-54.0, -66.0, -78.0]:
		_chandelier(Vector3(0, Y2 + 9.0, z), 3.0)
	_light(Vector3(0, Y2 + 8.0, -56), 22.0, 1.8, "#F0A850")
	_light(Vector3(0, Y2 + 8.0, -72), 22.0, 1.8, "#F0A850")
	_light(Vector3(0, Y2 + 3.0, -86), 14.0, 2.4, "#F2B060")

func _apply_dusk(t: float) -> void:
	super(t)
	# A cut in the rock under overcast: less direct sun than an open plain.
	sun.light_energy *= 0.7

func _chandelier(p: Vector3, r: float) -> void:
	var lb := Builder.new(0.0)
	lb.cyl(P.BRASS, Vector3.ZERO, r, r, 0.1, 24, false, false)
	lb.cyl(P.LAMP, Vector3(0, -0.08, 0), r * 0.92, r * 0.92, 0.05, 24, false, false)
	lb.cyl(P.BRASS, Vector3(0, -0.8, 0), r * 0.55, r * 0.55, 0.07, 18, false, false)
	lb.cyl(P.LAMP, Vector3(0, -0.86, 0), r * 0.5, r * 0.5, 0.04, 18, false, false)
	lb.cyl(P.BRASS, Vector3(0, 3.5, 0), 0.04, 0.04, 7.0, 6)
	var mi := MeshInstance3D.new()
	mi.mesh = lb.mesh()
	mi.position = p
	add_child(mi)

# ---- the two wings

func _sofa(b: Builder, c: Vector3, rot: float) -> void:
	var bs := Basis(Vector3.UP, rot)
	b.box_xf(P.LEATHER, Transform3D(bs, c + Vector3(0, 0.26, 0)), Vector3(2.4, 0.42, 0.9))
	b.box_xf(P.LEATHER, Transform3D(bs, c + bs * Vector3(0, 0.66, -0.36)), Vector3(2.4, 0.56, 0.2))
	for s in [-1, 1]:
		b.box_xf(P.LEATHER, Transform3D(bs, c + bs * Vector3(s * 1.1, 0.46, 0)), Vector3(0.22, 0.32, 0.9))
	b.kit.add_collider(Transform3D(bs, c + Vector3(0, 0.4, 0)), Vector3(2.4, 0.8, 0.9))

func _console(b: Builder, c: Vector3, rot: float) -> void:
	var bs := Basis(Vector3.UP, rot)
	b.box_xf(P.BEIGE, Transform3D(bs, c + Vector3(0, 0.55, 0)), Vector3(1.2, 1.1, 0.7))
	b.kit.add_collider(Transform3D(bs, c + Vector3(0, 0.55, 0)), Vector3(1.2, 1.1, 0.7))
	b.box_xf(P.BEIGE, Transform3D(bs, c + bs * Vector3(0, 1.32, -0.1)), Vector3(0.82, 0.52, 0.5))
	b.box_xf(P.CRT, Transform3D(bs, c + bs * Vector3(0, 1.32, 0.16)), Vector3(0.66, 0.42, 0.02))
	b.box_xf(P.CHARCOAL, Transform3D(bs, c + bs * Vector3(0, 0.82, 0.36)), Vector3(1.0, 0.3, 0.02))

func _build_wings() -> void:
	var b := Builder.new(0.22)
	var hh := 8.0
	# ---- East wing: Reception. Walnut, burgundy, brass.
	var x0 := 11.4
	var x1 := 34.0
	b.box(P.MARBLE, Vector3((x0 + x1) * 0.5, Y2 + 0.02, -61.5), Vector3(x1 - x0, 0.04, 29), false)
	b.box(P.ROCK, Vector3((x0 + x1) * 0.5, Y2 + hh + 0.3, -61.5), Vector3(x1 - x0 + 1, 0.6, 30))
	b.wall_x(P.WALNUT, x0, x1, -76, Y2, hh, 0.6, [[23.5, 26.5, 0, 3.0]])
	b.wall_z(P.WALNUT, -76, -47, x1, Y2, hh, 0.6, [[-66, -62, 0, 3.4]])
	b.box(P.BRASS, Vector3((x0 + x1) * 0.5, Y2 + 1.03, -75.66), Vector3(x1 - x0, 0.05, 0.05), false)
	# South glass onto the terrace; a service door at the west end of it.
	b.wall_x(P.STONE, x0, x1, -47.6, Y2, hh, 0.5, [[24, 26, 0, 2.8]])
	b.box(P.CARPET, Vector3(22, Y2 + 0.05, -60), Vector3(12, 0.02, 10), false)
	_sofa(b, Vector3(19.0, Y2, -56.0), PI)
	_sofa(b, Vector3(25.0, Y2, -56.0), PI)
	_sofa(b, Vector3(22.0, Y2, -63.5), 0.0)
	b.box(P.WALNUT, Vector3(22, Y2 + 0.4, -59.5), Vector3(2.4, 0.08, 1.2))
	b.cyl(P.CHROME, Vector3(22, Y2 + 0.2, -59.5), 0.1, 0.1, 0.4, 8)
	# Desk, tray, reception telex, tea sideboard.
	b.box(P.WALNUT, Vector3(29.5, Y2 + 0.78, -70.5), Vector3(3.4, 0.08, 1.5))
	b.box(P.BRASS, Vector3(29.5, Y2 + 0.74, -70.5), Vector3(3.44, 0.03, 1.54), false)
	b.box(P.WALNUT, Vector3(28.1, Y2 + 0.37, -70.5), Vector3(0.5, 0.74, 1.4))
	b.box(P.WALNUT, Vector3(30.9, Y2 + 0.37, -70.5), Vector3(0.5, 0.74, 1.4))
	b.box(P.BRASS, Vector3(28.6, Y2 + 0.86, -70.2), Vector3(0.46, 0.06, 0.34), false)
	b.box(P.IVORY, Vector3(28.6, Y2 + 0.89, -70.2), Vector3(0.36, 0.02, 0.26), false)
	_console(b, Vector3(32.8, Y2, -72.5), -PI / 2)
	b.box(P.BEIGE, Vector3(15, Y2 + 0.95, -74.6), Vector3(0.9, 0.4, 0.7))
	b.box(P.WARM_GREY, Vector3(15, Y2 + 0.37, -74.6), Vector3(1.0, 0.74, 0.8))
	b.box(P.CHARCOAL, Vector3(15, Y2 + 1.05, -74.3), Vector3(0.7, 0.12, 0.2), false)
	b.box(P.IVORY, Vector3(15, Y2 + 1.35, -74.7), Vector3(0.5, 0.4, 0.02), false)
	b.box(P.AMBER, Vector3(15.4, Y2 + 1.12, -74.26), Vector3(0.05, 0.05, 0.02), false)
	b.box(P.WALNUT, Vector3(20, Y2 + 0.45, -74.8), Vector3(3.2, 0.9, 0.7))
	b.box(P.BRASS, Vector3(20, Y2 + 0.91, -74.8), Vector3(3.3, 0.03, 0.74), false)
	b.cyl(P.IVORY, Vector3(19.6, Y2 + 1.04, -74.8), 0.1, 0.07, 0.22, 10)
	b.cyl(P.IVORY, Vector3(20.1, Y2 + 0.96, -74.7), 0.05, 0.04, 0.06, 8)
	# Amber rack along the north wall (kinterior).
	for i in 4:
		var rx := 13.0 + i * 1.5 + 11.0
		b.block(P.CHARCOAL, Vector3(rx, Y2, -75.6), Vector3(1.3, 2.4, 0.4), false)
		for k in 5:
			b.box(P.AMBER, Vector3(rx, Y2 + 0.5 + k * 0.38, -75.38), Vector3(0.9, 0.05, 0.02), false)
	# Vault behind the reception room.
	b.box(P.STEEL, Vector3(25, Y2 + 0.03, -81), Vector3(10, 0.04, 10), false)
	b.wall_z(P.STEEL, -86, -76, 20.0, Y2, hh, 0.6)
	b.wall_z(P.STEEL, -86, -76, 30.0, Y2, hh, 0.6)
	b.wall_x(P.STEEL, 20, 30, -86, Y2, hh, 0.6)
	b.box(P.ROCK, Vector3(25, Y2 + hh + 0.3, -81), Vector3(11, 0.6, 11))
	# East court / motor pool: a rock shelf with a roller door into the cliff.
	b.block(P.ROCK, Vector3(46, 0, -64), Vector3(24, Y2, 30))
	b.box(P.ROAD, Vector3(46, Y2 + 0.02, -64), Vector3(23, 0.04, 28), false)
	b.wall_z(P.STONE, -79, -49, 58.0, Y2, 8.0, 1.0, [[-68, -60, 0, 4.2]])
	b.wall_x(P.STONE, 34, 58, -49.0, Y2, 3.0, 0.8)
	b.wall_x(P.STONE, 34, 58, -79.0, Y2, 3.0, 0.8)
	b.box(P.CHARCOAL, Vector3(58.4, Y2 + 2.1, -64), Vector3(0.2, 4.2, 8.0), false)
	_collider(b, Vector3(58.4, Y2 + 2.1, -64), Vector3(0.2, 4.2, 8.0))
	# ---- West wing: Avekṣā's Monitoring room, cold green.
	x0 = -34.0
	x1 = -11.4
	b.box(P.STEEL, Vector3((x0 + x1) * 0.5, Y2 + 0.02, -61.5), Vector3(x1 - x0, 0.04, 29), false)
	b.box(P.ROCK, Vector3((x0 + x1) * 0.5, Y2 + hh + 0.3, -61.5), Vector3(x1 - x0 + 1, 0.6, 30))
	b.wall_x(P.CONCRETE_DARK, x0, x1, -76, Y2, hh, 0.6)
	b.wall_z(P.CONCRETE_DARK, -76, -47, x0, Y2, hh, 0.6)
	b.wall_x(P.STONE, x0, x1, -47.6, Y2, hh, 0.5, [[-26, -24, 0, 2.8]])
	# The wall of screens: every feed, one room.
	for i in 6:
		for k in 3:
			var sx := -29.0 + i * 2.6
			var sy := Y2 + 1.3 + k * 1.75
			b.box(P.CHARCOAL, Vector3(sx, sy, -75.55), Vector3(2.4, 1.6, 0.3), false)
			b.box(P.CRT, Vector3(sx, sy, -75.38), Vector3(2.0, 1.3, 0.02), false)
	_console(b, Vector3(-24.0, Y2, -71.5), PI)
	_console(b, Vector3(-20.0, Y2, -71.5), PI)
	# Recorder racks: one per zone, plus the order-slip telex.
	for i in ZONE_NAMES.size():
		var rz := -55.0 - i * 3.0
		b.block(P.BEIGE, Vector3(-33.2, Y2, rz), Vector3(0.9, 2.2, 1.9))
		for t: float in [-0.44, 0.44]:
			var bs := Basis(Vector3.BACK, PI / 2)
			b.cyl_xf(P.CHARCOAL, Transform3D(bs, Vector3(-32.72, Y2 + 1.7, rz + t)), 0.34, 0.34, 0.03, 16)
			b.cyl_xf(P.CHROME, Transform3D(bs, Vector3(-32.7, Y2 + 1.7, rz + t)), 0.08, 0.08, 0.03, 8)
		b.box(P.AMBER, Vector3(-32.73, Y2 + 0.95, rz), Vector3(0.02, 0.06, 0.3), false)
		b.box(P.CRT, Vector3(-32.73, Y2 + 0.62, rz), Vector3(0.02, 0.32, 1.0), false)
	b.commit(self, "Wings", 240.0)
	_light(Vector3(22, Y2 + 6.6, -60), 18.0, 1.8, "#F0A850")
	_light(Vector3(24, Y2 + 5.0, -71), 11.0, 1.2, "#E9B86A")
	_light(Vector3(25, Y2 + 5.0, -81), 9.0, 1.4, "#9FCFC0")
	_light(Vector3(-23, Y2 + 6.6, -62), 20.0, 1.3, "#7FE0A0")
	_chandelier(Vector3(22, Y2 + 6.6, -60), 1.8)
	gov_car = spawn_car(Vector3(52, Y2 + 0.8, -64), PI / 2, Color("#141618"))
	(gov_car as ArcadeCar).freeze = true

# ---- quarry pit, excavators

func _excavator(c: Vector3, rot: float) -> void:
	var b := Builder.new(0.2)
	b.box(P.CHARCOAL, Vector3(-2.2, 0.8, 0), Vector3(1.5, 1.6, 8.0))
	b.box(P.CHARCOAL, Vector3(2.2, 0.8, 0), Vector3(1.5, 1.6, 8.0))
	b.box(P.CAPE, Vector3(0, 3.0, 0.5), Vector3(5.4, 2.8, 6.4))
	b.box(P.CAPE, Vector3(0, 5.1, 2.0), Vector3(3.6, 1.4, 3.2))
	b.box(P.GLASS, Vector3(-1.2, 4.8, -2.0), Vector3(1.8, 1.5, 0.05), false)
	b.box(P.AMBER, Vector3(2.6, 4.1, -2.75), Vector3(0.2, 0.2, 0.05), false)
	b.box_xf(P.CAPE, Transform3D(Basis(Vector3.RIGHT, 0.85), Vector3(0, 6.6, -6.8)), Vector3(1.2, 1.2, 11.0))
	b.box_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 4.2, -13.0)), Vector3(0.9, 0.9, 6.0))
	b.box(P.STEEL, Vector3(0, 1.2, -15.5), Vector3(3.2, 2.4, 2.8))
	for i in 4:
		b.box(P.CHROME, Vector3(-1.2 + i * 0.8, 0.1, -17.0), Vector3(0.28, 0.6, 0.5), false)
	var mi := b.commit(self, "Excavator")
	mi.get_parent().remove_child(mi)
	var holder := Node3D.new()
	holder.position = c
	holder.rotation.y = rot
	add_child(holder)
	holder.add_child(mi)
	# Colliders were committed as a sibling body: keep them with the mesh.
	for ch in get_children():
		if ch is StaticBody3D and ch.name.begins_with("Excavator"):
			ch.get_parent().remove_child(ch)
			holder.add_child(ch)

func _build_pit() -> void:
	var b := Builder.new(0.2)
	# Open cut east of the terraces, still being worked for stone.
	b.box(P.STONE, Vector3(36.2, Y1 * 0.5, 13), Vector3(0.4, Y1, 54), true)
	b.box(P.ROCK, Vector3(36.4, Y2 * 0.5, -20), Vector3(0.6, Y2, 40), true)
	# Rubble heaps.
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 12:
		var c := Vector3(rng.randf_range(42.0, 60.0), 0.0, rng.randf_range(-40.0, 36.0))
		var s := Vector3(rng.randf_range(4.0, 11.0), rng.randf_range(1.5, 5.0), rng.randf_range(4.0, 11.0))
		_rock(b, c + Vector3(0, s.y * 0.35, 0), s, 100 + i, 3, 0.8)
		_collider(b, c + Vector3(0, s.y * 0.35, 0), s * 0.8)
	# West service ramp from the forecourt to the terrace.
	b.ramp(P.ROCK, Vector3(-42.0, 0, 42.0), Vector3(9, Y1, 40), PI)
	b.block(P.ROCK, Vector3(-42.0, 0, 8.0), Vector3(12, Y1, 28))
	b.box(P.PAVING, Vector3(-42.0, Y1 + 0.01, 8), Vector3(12, 0.02, 28), false)
	b.commit(self, "Pit")
	_excavator(Vector3(54, 0, 8), 0.5)
	_excavator(Vector3(50, 0, -26), -0.9)

# ---- the road out

func _build_road() -> void:
	road = Expressway.new()
	road.name = "Expressway"
	road.min_index = int(_params.get("road_first_chunk", 2))
	var yard := int(_params.get("safehouse_chunk", 14))
	road.left_override = {yard: "yard_a", yard + 1: "yard_b"}
	road.extra = func(i: int, c: Node3D):
		if i == yard:
			_mark_safehouse(c)
	add_child(road)
	road.build_all(ROAD_START_Z + 96.0)
	road.visible = false
	var L := Expressway.L
	safehouse = AABB(Vector3(-92, -3, yard * L), Vector3(92 - 15.0, 16, L * 2.0))

## The network's yard: a lit shed and a lantern mast you can see from the road.
func _mark_safehouse(c: Node3D) -> void:
	var b := Builder.new(0.2)
	b.block(P.CONCRETE_DARK, Vector3(-50, 0, 60), Vector3(14, 5.0, 18))
	b.box(P.WINDOWS, Vector3(-42.94, 2.4, 60), Vector3(0.1, 2.4, 12), false)
	b.block(P.CHARCOAL, Vector3(-36, 0, 40), Vector3(0.5, 22, 0.5), false)
	for k in 3:
		b.box(P.AMBER, Vector3(-36, 21.0 - k * 2.4, 40), Vector3(2.4, 0.5, 0.5), false)
	b.commit(c, "Safehouse")
	var o := OmniLight3D.new()
	o.position = Vector3(-37, 19, 40)
	o.omni_range = 36.0
	o.light_energy = 2.6
	o.light_color = Color("#F09A28")
	c.add_child(o)

# ---- scattered props and probes

func _build_props() -> void:
	# Saucer-roofed towers beyond the rim, windows lit, as in kstaircase.
	var b := Builder.new(0.1)
	for t in [[Vector3(-74, 0, -30), 54.0, 11.0], [Vector3(92, 0, 30), 62.0, 12.0], [Vector3(-92, 0, 70), 44.0, 10.0]]:
		var c: Vector3 = t[0]
		var h: float = t[1]
		var r: float = t[2]
		b.cyl(P.CONCRETE_DARK, c + Vector3(0, h * 0.5, 0), r * 0.6, r * 0.5, h, 14)
		b.cyl(P.WINDOWS, c + Vector3(0, h * 0.75, 0), r * 0.62, r * 0.55, h * 0.4, 14, false, false)
		b.cyl(P.STEEL, c + Vector3(0, h + 1.0, 0), r * 1.5, r * 1.3, 1.2, 24)
		b.cyl(P.CONCRETE_PALE, c + Vector3(0, h + 2.6, 0), r * 0.9, r * 0.4, 2.2, 20)
		b.cyl(P.STEEL, c + Vector3(0, h + 7.0, 0), 0.3, 0.06, 8.0, 6)
	var mi := b.commit(self, "Towers")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for pr in [[Vector3(0, 6, 85), Vector3(90, 30, 100)], [Vector3(0, 14, 0), Vector3(80, 26, 80)]]:
		var probe := ReflectionProbe.new()
		probe.position = pr[0]
		probe.size = pr[1]
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.box_projection = true
		probe.max_distance = 200.0
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		add_child(probe)
	for p in [Vector3(-14, 12, 50), Vector3(14, 12, 50), Vector3(0, Y1 + 4, 8), Vector3(0, Y2 + 6, -38)]:
		_light(p, 22.0, 1.1, "#F0A850")

# ---- crowd

func _build_crowd() -> void:
	crowd = CrowdField.new()
	crowd.name = "Crowd"
	add_child(crowd)
	crowd.setup(326)
	var y1 := Y1
	var y2 := Y2
	var loop := [Vector3(-12, 0, 122), Vector3(-12, 0, 46), Vector3(-5, 0, 41), Vector3(-5, y1, 22), Vector3(-5, y1, 6), Vector3(-22, y1, 6),
		Vector3(-22, y1, -8), Vector3(22, y1, -8), Vector3(22, y1, 6), Vector3(5, y1, 6), Vector3(5, y1, 22), Vector3(5, 0, 41), Vector3(12, 0, 46), Vector3(12, 0, 122)]
	crowd.add_lane(PackedVector3Array(loop), 6.0, true, 1.5)
	crowd.add_lane(PackedVector3Array([Vector3(-22, 0, 126), Vector3(22, 0, 126), Vector3(22, 0, 50), Vector3(-22, 0, 50)]), 12.0, true, 1.0)
	var queue := [Vector3(-3, y1, -12), Vector3(-3, y2, -26), Vector3(-3, y2, -44), Vector3(-3, y2, -76), Vector3(3, y2, -76), Vector3(3, y2, -44), Vector3(3, y2, -26), Vector3(3, y1, -12)]
	crowd.add_lane(PackedVector3Array(queue), 3.5, true, 1.2)
	crowd.add_exit(Vector3(0, 0, GATE_Z), 9.0)
	crowd.add_exit(Vector3(-42, 0, 62), 7.0)
	crowd.populate(Builder.pilgrim(), 210.0)

# ==============================================================  eyes

func _gantry_mast(b: Builder, base: Vector3, h: float) -> void:
	b.cyl(P.CHARCOAL, base + Vector3(0, h * 0.5, 0), 0.22, 0.14, h, 8)
	b.box(P.STEEL, base + Vector3(0, h, 0), Vector3(2.0, 0.16, 2.0))
	b.box(P.CHARCOAL, base + Vector3(0, h + 0.65, 0.9), Vector3(1.6, 1.0, 0.06), false)
	_collider(b, base + Vector3(0, h * 0.5, 0), Vector3(0.5, h, 0.5))

func _add_eye(id: String, zone: String, kind: String, pos: Vector3, yaw_deg: float, pitch_deg: float) -> Eye:
	var e := Eye.new()
	e.name = "Eye_" + id
	e.feed_id = id
	e.kind = kind
	e.position = pos
	var head := Node3D.new()
	head.name = "Head"
	head.rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)
	e.add_child(head)
	var mi := MeshInstance3D.new()
	mi.mesh = _eye_head_mesh(kind)
	head.add_child(mi)
	# The camera's cone, faint and readable: amber as it starts to record.
	var cone := MeshInstance3D.new()
	cone.name = "Cone"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 7.0 if kind != "balloon" else 13.0
	var ln := 22.0 if kind != "balloon" else 34.0
	cm.height = ln
	cm.radial_segments = 12
	cm.cap_top = false
	cm.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.9, 0.7, 0.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	cm.material = mat
	cone.mesh = cm
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.rotation.x = -PI / 2
	cone.visible = false
	cone.position = Vector3(0, 0, -ln * 0.5)
	head.add_child(cone)
	# Shooting one is possible, and loud.
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.set_meta("shootable", "eye")
	body.set_meta("feed", id)
	body.name = "Hit"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 0.8, 1.0) if kind == "gantry" else Vector3(3.0, 2.0, 3.0)
	cs.shape = bs
	body.add_child(cs)
	e.add_child(body)
	add_child(e)
	e.set_player(player)
	e.recorded.connect(func(fid): Game.sim.sv_record(fid, false))
	eyes[id] = e
	zones_of[id] = zone
	if kind != "drone" or zone != "":
		Game.sim.sv_add_feed(id, zone)
	return e

static func _eye_head_mesh(kind: String) -> Mesh:
	return Builder.cached("eye_" + kind, func():
		var b := Builder.new(0.0)
		var fwd := Basis(Vector3.RIGHT, PI / 2)
		match kind:
			"balloon":
				# An aerostat lying along its axis: tapered rings, three fins.
				var along := Basis(Vector3.RIGHT, PI / 2)
				var rs := [0.5, 1.5, 2.2, 2.5, 2.5, 2.3, 1.9, 1.3, 0.5]
				for i in rs.size() - 1:
					var z := -4.8 + i * 1.2
					b.cyl_xf(P.CAR_ORANGE if i == 3 else P.IVORY, Transform3D(along, Vector3(0, 3.6, z + 0.6)), rs[i + 1], rs[i], 1.2, 14)
				for fin in [0.0, TAU / 3.0, -TAU / 3.0]:
					b.box_xf(P.BANNER, Transform3D(Basis(Vector3.BACK, fin), Vector3(0, 3.6, 4.0)) * Transform3D(Basis(), Vector3(0, 2.2, 0)), Vector3(0.08, 2.4, 2.0))
				b.box(P.BLACK, Vector3(0, 1.1, 0), Vector3(0.05, 1.4, 0.05), false)
				b.box(P.CHARCOAL, Vector3(0, 0.3, 0), Vector3(1.2, 0.8, 1.2), false)
				b.cyl_xf(P.BLACK, Transform3D(fwd, Vector3(0, 0.3, -0.75)), 0.2, 0.22, 0.5, 10)
				b.cyl_xf(P.AMBER, Transform3D(fwd, Vector3(0, 0.3, -1.02)), 0.14, 0.14, 0.02, 8)
			"drone":
				b.cyl(P.STEEL, Vector3(0, 0.2, 0), 1.25, 0.5, 0.3, 18)
				b.cyl(P.STEEL, Vector3(0, -0.02, 0), 0.5, 1.25, 0.16, 18)
				b.cyl(P.AMBER, Vector3(0, 0.07, 0), 1.3, 1.3, 0.05, 18, false, false)
				b.cyl_xf(P.BLACK, Transform3D(fwd, Vector3(0, -0.15, -0.55)), 0.13, 0.15, 0.4, 8)
				b.cyl_xf(P.AMBER, Transform3D(fwd, Vector3(0, -0.15, -0.76)), 0.09, 0.09, 0.02, 8)
			_:
				b.box(P.BEIGE, Vector3(0, 0, 0), Vector3(0.36, 0.34, 0.74), false)
				b.box(P.CHARCOAL, Vector3(0, 0.2, 0), Vector3(0.42, 0.04, 0.86), false)
				b.cyl_xf(P.BLACK, Transform3D(fwd, Vector3(0, 0, -0.46)), 0.14, 0.16, 0.2, 10)
				b.cyl_xf(P.AMBER, Transform3D(fwd, Vector3(0, 0, -0.57)), 0.09, 0.09, 0.02, 8)
		return b.mesh())

func _build_eyes() -> void:
	var b := Builder.new(0.15)
	# [id, zone, position, facing yaw (0 looks north), tilt].
	var gantries := [
		["g_f1", "forecourt", Vector3(-20, 0, 100), -30.0, -22.0], ["g_f2", "forecourt", Vector3(20, 0, 66), 150.0, -22.0],
		["g_s1", "grand_stair", Vector3(-27, Y1 + 12.0, 26), 240.0, -28.0], ["g_s2", "grand_stair", Vector3(27, Y1 + 12.0, 26), 120.0, -28.0],
		["g_t1", "terrace", Vector3(-30, Y1, 12), -60.0, -18.0], ["g_t2", "terrace", Vector3(30, Y1, -4), 60.0, -18.0],
		["g_t3", "terrace", Vector3(-30, Y1, -10), -110.0, -18.0],
		["g_u1", "upper", Vector3(-26, Y2, -30), 250.0, -18.0], ["g_u2", "upper", Vector3(26, Y2, -41), 40.0, -14.0],
	]
	for g in gantries:
		_gantry_mast(b, g[2], 6.0 if g[2].y < Y1 + 10.0 else 0.2)
		_add_eye(g[0], g[1], "gantry", g[2] + Vector3(0, 6.9 if g[2].y < Y1 + 10.0 else 1.0, 0), g[3], g[4])
		_junction(g[0], g[2] + Vector3(0, 6.5 if g[2].y < Y1 + 10.0 else 0.6, 0.0))
	# Wall-hung, indoors.
	_add_eye("g_n1", "nave", "gantry", Vector3(-9.8, Y2 + 9.0, -49.0), 200.0, -22.0)
	_add_eye("g_n2", "nave", "gantry", Vector3(9.8, Y2 + 9.0, -78.0), 40.0, -22.0)
	_add_eye("g_r1", "reception", "gantry", Vector3(12.3, Y2 + 6.5, -49.0), 215.0, -24.0)
	# Tethered balloons; the tether runs to a winch box on the ground.
	for t in [["b_f", "forecourt", Vector3(-30, 0, 110), Vector3(-6, 34, 86)], ["b_t", "terrace", Vector3(33, Y1, 18), Vector3(22, Y1 + 30, 0)], ["b_u", "upper", Vector3(-33, Y2, -28), Vector3(-20, Y2 + 28, -28)]]:
		_add_eye(t[0], t[1], "balloon", t[3], 0.0, -52.0)
		var base: Vector3 = t[2]
		var top: Vector3 = t[3]
		var d := top - base
		var c := base + d * 0.5
		b.box_xf(P.BLACK, Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.BACK), c), Vector3(0.05, 0.05, d.length()))
		b.block(P.CHARCOAL, base, Vector3(1.6, 1.2, 1.6))
		_junction(t[0], base + Vector3(0, 1.1, 0.0))
	# Drones on a circuit.
	var d1 := _add_eye("d_1", "forecourt", "drone", Vector3(-20, 12, 90), 0.0, -30.0)
	d1.set_path(PackedVector3Array([Vector3(-20, 12, 90), Vector3(20, 12, 90), Vector3(20, 12, 60), Vector3(-20, 12, 60)]))
	var d2 := _add_eye("d_2", "terrace", "drone", Vector3(-22, Y1 + 8, 10), 0.0, -30.0)
	d2.set_path(PackedVector3Array([Vector3(-22, Y1 + 8, 10), Vector3(22, Y1 + 8, 10), Vector3(22, Y2 + 7, -30), Vector3(-22, Y2 + 7, -30)]))
	b.commit(self, "Masts")
	# Breaker panels: one per zone, noticed faster than a tape.
	var breakers := {"forecourt": Vector3(-33.6, 1.3, 128.2), "grand_stair": Vector3(-7.6, 1.5, 41.0), "terrace": Vector3(35.4, Y1 + 1.4, 8.0),
		"upper": Vector3(-35.4, Y2 + 1.3, -32.0), "nave": Vector3(-9.8, Y2 + 1.5, -56.0), "reception": Vector3(-10.4, Y2 + 1.5, -70.0)}
	var pb := Builder.new(0.0)
	for z: String in breakers:
		pb.box(P.CHARCOAL, breakers[z], Vector3(0.7, 0.9, 0.7), false)
		pb.box(P.AMBER, breakers[z] + Vector3(0, 0.35, 0.36), Vector3(0.1, 0.06, 0.01), false)
		_breaker(z, breakers[z])
	pb.commit(self, "Breakers")

func _junction(id: String, at: Vector3) -> void:
	Interactable.make(self, at, Vector3(1.0, 1.0, 1.0),
		func(): return ("E  Pull this feed at its junction box" if Game.sim.sv_feed_live(id) else "Junction box (feed dead)"),
		func():
			if Game.sim.sv_feed_live(id):
				Game.sim.sv_pull(id)
				Game.play_3d("beep_low", at, -6)
				hud.message("Feed pulled. The room will notice in time."))

func _breaker(zone: String, at: Vector3) -> void:
	Interactable.make(self, at, Vector3(0.9, 1.1, 0.9),
		func(): return "E  %s the breaker for %s" % ["Restore" if Game.sim.sv_zone_dark(zone) else "Pull", ZONE_NAMES[zone]],
		func():
			var dark: bool = Game.sim.sv_toggle_power(zone)
			Game.play_3d("beep_low", at, -4)
			hud.message("%s is dark. The breaker rings on the room's desk." % ZONE_NAMES[zone].capitalize() if dark else "Power restored."))

# ============================================================== navigation

func _build_nav() -> void:
	Game.sim.nav_clear()
	var y1 := Y1
	var y2 := Y2
	var pts := {
		"fc_gate": Vector3(0, 0, 124), "fc_mid": Vector3(0, 0, 84), "fc_turn": Vector3(0, 0, 66), "fc_w": Vector3(-20, 0, 80), "fc_e": Vector3(20, 0, 80),
		"s1_bot": Vector3(0, 0, 41.5), "s1_top": Vector3(0, y1, 21.0), "t1_c": Vector3(0, y1, 3), "t1_w": Vector3(-28, y1, 2), "t1_e": Vector3(28, y1, 2),
		"s2_bot": Vector3(0, y1, -13), "s2_top": Vector3(0, y2, -27), "t2_c": Vector3(0, y2, -34), "t2_w": Vector3(-25, y2, -36), "t2_e": Vector3(25, y2, -36),
		"col_c": Vector3(0, y2, -41), "nave_s": Vector3(0, y2, -49), "nave_mid": Vector3(0, y2, -64), "sanctum_rail": Vector3(0, y2, -79.5),
		"rec_door_n": Vector3(9, y2, -64), "rec_door": Vector3(13, y2, -64), "rec_c": Vector3(16, y2, -65),
		"rec_desk": Vector3(29.5, y2, -68.8), "rec_sofa": Vector3(22, y2, -62.0), "rec_tea": Vector3(20, y2, -73.4), "rec_e": Vector3(32.5, y2, -64),
		"rec_v": Vector3(25, y2, -74), "strongroom": Vector3(25, y2, -81), "rec_side": Vector3(25, y2, -50), "rec_side_o": Vector3(25, y2, -44.5),
		"motor_pool": Vector3(40, y2, -64), "motor_car": Vector3(49, y2, -64),
		"mon_door_n": Vector3(-9, y2, -64), "mon_door": Vector3(-13, y2, -64), "mon_c": Vector3(-22, y2, -66), "mon_racks": Vector3(-30, y2, -62),
		"mon_side": Vector3(-25, y2, -50), "mon_side_o": Vector3(-25, y2, -44.5),
		"ramp_bot": Vector3(-42, 0, 62), "ramp_top": Vector3(-42, y1, 22), "ramp_land": Vector3(-42, y1, 5), "gate_out": Vector3(0, 0, 140),
	}
	for k in pts:
		_n(k, pts[k])
	for pair in [["gate_out", "fc_gate"], ["fc_gate", "fc_mid"], ["fc_mid", "fc_turn"], ["fc_mid", "fc_w"], ["fc_mid", "fc_e"], ["fc_turn", "s1_bot"], ["fc_w", "s1_bot"], ["fc_e", "s1_bot"],
			["s1_bot", "s1_top"], ["s1_top", "t1_c"], ["t1_c", "t1_w"], ["t1_c", "t1_e"], ["t1_c", "s2_bot"], ["s2_bot", "s2_top"], ["s2_top", "t2_c"], ["t2_c", "t2_w"], ["t2_c", "t2_e"],
			["t2_c", "col_c"], ["col_c", "nave_s"], ["nave_s", "nave_mid"], ["nave_mid", "sanctum_rail"], ["nave_mid", "rec_door_n"], ["rec_door_n", "rec_door"], ["rec_door", "rec_c"],
			["rec_c", "rec_sofa"], ["rec_c", "rec_tea"], ["rec_sofa", "rec_e"], ["rec_e", "rec_desk"], ["rec_tea", "rec_v"], ["rec_v", "strongroom"], ["rec_c", "rec_v"], ["rec_e", "motor_pool"], ["motor_pool", "motor_car"],
			["rec_sofa", "rec_side"], ["rec_side", "rec_side_o"], ["rec_side_o", "t2_e"], ["nave_mid", "mon_door_n"], ["mon_door_n", "mon_door"], ["mon_door", "mon_c"], ["mon_c", "mon_racks"],
			["mon_c", "mon_side"], ["mon_side", "mon_side_o"], ["mon_side_o", "t2_w"], ["fc_w", "ramp_bot"], ["ramp_bot", "ramp_top"], ["ramp_top", "ramp_land"], ["ramp_land", "t1_w"]]:
		_l(pair[0], pair[1])
	locations["rec_desk_face"] = PI
	locations["rec_sofa_face"] = 0.0
	locations["rec_tea_face"] = 0.0
	locations["strongroom_face"] = 0.0
	locations["sanctum_rail_face"] = 0.0
	locations["proc_start"] = locations["rec_door"]
	locations["far_post"] = locations["ramp_land"]

# ============================================================== NPCs

func _guard(at: String, patrol: Array, zone: String, tint := 2) -> Npc:
	var g := _spawn_npc("guard", at, patrol, tint)
	g.set_meta("zone", zone)
	g.set_meta("patrol", patrol)
	return g

func _spawn_npcs() -> void:
	_guard("fc_w", ["fc_w", "fc_mid", "fc_turn"], "forecourt")
	_guard("fc_e", ["fc_e", "fc_gate", "fc_mid"], "forecourt")
	_guard("s1_bot", ["s1_bot", "s1_top"], "grand_stair")
	_guard("s1_top", ["s1_top", "t1_c", "s1_top"], "grand_stair", 0)
	_guard("t1_w", ["t1_w", "t1_c"], "terrace")
	_guard("t1_e", ["t1_e", "t1_c"], "terrace")
	_guard("s2_bot", ["s2_bot", "t1_c"], "terrace", 0)
	_guard("t2_w", ["t2_w", "t2_c"], "upper")
	_guard("t2_e", ["t2_e", "col_c"], "upper")
	_guard("nave_s", ["nave_s", "nave_mid"], "nave", 0)
	_guard("sanctum_rail", ["sanctum_rail", "nave_mid"], "nave", 0)
	_guard("rec_c", ["rec_c", "rec_sofa", "rec_e"], "reception", 1)
	# The room: two Avekṣā operators at their consoles.
	for spot in ["mon_c", "mon_racks"]:
		var o := _guard(spot, [], "room")
		o.died.connect(func(_s): _operator_down())
		operators.append(o)
	var extra := int(_info.get("extra_guards", 0))
	var extra_posts := [["t1_c", ["t1_c", "t1_w"]], ["col_c", ["col_c", "t2_e"]], ["fc_gate", ["fc_gate", "fc_w"]], ["rec_v", ["rec_v", "rec_c"]]]
	for i in mini(extra, extra_posts.size()):
		_guard(extra_posts[i][0], extra_posts[i][1], "terrace")
	gov = _spawn_npc("governor", "rec_desk")
	gov.health = float(_info.get("governor_health", 70.0))
	gov.walk_speed = 1.15
	gov.run_speed = 3.0
	gov.reached_goal.connect(_on_gov_arrived)
	gov.alarm_call.connect(func(): _on_alarm_call(gov))
	gov.body_discovered.connect(func(_at): _on_body_found(gov))
	# His liaison from Avekṣā: the courier's slot, in petrol.
	courier = _spawn_npc("courier", "rec_sofa")
	liaison = courier
	liaison.walk_speed = 1.15
	# Retinue: four elite guards walking a close ring.
	for i in 4:
		var g := _spawn_npc("guard", "rec_c", [], 1)
		retinue.append(g)
	# The crowd's full NPCs: a pool, parked until needed.
	for i in crowd.full_npc_budget():
		var c := _spawn_npc("civilian", "fc_turn", [], 100 + i % 5)
		c.position = Vector3(0, -40, 200 + i)
		c.visible = false
		c.set_physics_process(false)
		c.died.connect(func(_s): _on_civilian_down(i))
		_slots.append({"npc": c, "agent": -1, "tint": i % 5})

## Swap pilgrims near the player for full NPCs, and back.
func _update_slots() -> void:
	var at := player.global_position
	var r := crowd.near_radius()
	var wanted := crowd.nearest(at, r, _slots.size())
	var held := {}
	for s in _slots:
		var n: Npc = s.npc
		if s.agent < 0 or not n.alive:
			continue
		var d := n.global_position.distance_to(at)
		if d > r * 1.4 or crowd.agent_gone(s.agent):
			crowd.set_promoted(s.agent, false)
			s.agent = -1
			n.position = Vector3(0, -40, 200)
			n.visible = false
			n.set_physics_process(false)
		else:
			held[s.agent] = true
			n.steer_to(crowd.agent_ahead(s.agent, 3.0), 1.2)
	for a in wanted:
		if held.has(a):
			continue
		for s in _slots:
			var n: Npc = s.npc
			if s.agent >= 0 or not n.alive:
				continue
			s.agent = a
			crowd.set_agent_tint(a, s.tint)
			crowd.set_promoted(a, true)
			n.global_position = crowd.agent_pos(a) + Vector3(0, 0.1, 0)
			n.visible = true
			n.set_physics_process(true)
			n.steer_to(crowd.agent_ahead(a, 3.0), 1.2)
			break

func _on_civilian_down(i: int) -> void:
	var s: Dictionary = _slots[i]
	if s.agent >= 0:
		crowd.kill_agent(s.agent)
	Game.sim.report_bystander()

func _operator_down() -> void:
	if operators.all(func(o): return not o.alive):
		Game.sim.sv_set_staffed(false)
		hud.message("Nobody is watching the wall. The room will miss its next check-in.")

# ============================================================== interactables

func _gadget_id(kind: String) -> String:
	return str(_gadget_of(kind).get("id", ""))

func _build_interactables() -> void:
	var tea := Vector3(19.8, Y2 + 1.0, -74.8)
	Interactable.make(self, tea, Vector3(1.6, 0.6, 0.8),
		func():
			if Game.mstate().get("tea_poisoned", false):
				return "Ceremonial tea (dosed)"
			return "E  Dose the tea  [Datura Ampoule]" if _gadget_of("poison").get("count", 0) > 0 else "Ceremonial tea",
		func():
			var id := _gadget_id("poison")
			if id == "":
				return
			var err: String = Game.sim.poison_tea(id)
			if err != "":
				hud.message(err)
			else:
				Game.play_3d("pour", tea, -6)
				rig.refresh_gadgets(),
		"poison")
	var tray := Vector3(28.6, Y2 + 0.9, -70.2)
	Interactable.make(self, tray, Vector3(0.7, 0.4, 0.6),
		func():
			if Game.mstate().get("forgery_planted", false):
				return "Dispatch tray (forgery planted)"
			return "E  Plant forged dispatch" if _gadget_of("forgery").get("count", 0) > 0 else "Dispatch tray",
		func():
			var id := _gadget_id("forgery")
			if id == "":
				return
			var err: String = Game.sim.plant_forgery(id)
			hud.message(err if err != "" else "Dispatch planted, sealed with the elephant goad.")
			rig.refresh_gadgets(),
		"forgery")
	Interactable.make(self, Vector3(15, Y2 + 1.1, -74.4), Vector3(1.0, 0.8, 0.9),
		func(): return "E  Telex the capital",
		func():
			var err: String = Game.sim.send_telex()
			if err != "":
				hud.message(err)
			else:
				Game.play_3d("telex", Vector3(15, Y2 + 1, -74.6), 0)
				_arrest_timer = 2.0)
	Interactable.make(self, Vector3(32.4, Y2 + 1.3, -72.5), Vector3(0.9, 0.7, 0.9),
		func(): return "E  Read the appointment terminal",
		func():
			Game.play_3d("beep", Vector3(32.4, Y2 + 1.3, -72.5), -6)
			for id in ["a2", "a4", "w1"]:
				Game.sim.hear_line(id)
			hud.message("Terminal: 16:41 PROCESSION. 17:17 TEA. 17:36 CAR."))
	# Monitoring room: one recorder and one order-slip key per zone.
	var i := 0
	for zone: String in ZONE_NAMES:
		var at := Vector3(-32.4, Y2 + 1.4, -55.0 - i * 3.0)
		Interactable.make(self, at, Vector3(0.9, 1.4, 1.0),
			func():
				if Game.sim.sv_zone_dark(zone):
					return "E  Put %s back on the air" % ZONE_NAMES[zone]
				return "E  Loop the tape for %s  [Murmur Cassette]" % ZONE_NAMES[zone],
			func(): _use_recorder(zone, at),
			"tape_bug")
		var key := at + Vector3(0.1, -0.8, 0.0)
		Interactable.make(self, key, Vector3(0.9, 0.5, 1.0),
			func(): return "E  Send a patrol order for %s  [Forged Dispatch]" % ZONE_NAMES[zone],
			func(): _send_order(zone, key),
			"forgery")
		i += 1

func _use_recorder(zone: String, at: Vector3) -> void:
	if Game.sim.sv_zone_dark(zone):
		Game.sim.sv_restore_zone(zone)
		Game.play_3d("tape", at, -6)
		hud.message("%s is live again. The clock on it starts over." % ZONE_NAMES[zone].capitalize())
		return
	var id := _gadget_id("tape_bug")
	if id == "" or not Game.sim.consume_gadget(id):
		hud.message("No cassette left to loop.")
		return
	Game.sim.sv_loop_zone(zone)
	Game.play_3d("tape", at, -4)
	rig.refresh_gadgets()
	hud.message("%s shows an empty loop. Reset it before the room notices." % ZONE_NAMES[zone].capitalize())

func _send_order(zone: String, at: Vector3) -> void:
	var id := _gadget_id("forgery")
	if id == "" or not Game.sim.consume_gadget(id):
		hud.message("No forged slips left.")
		return
	Game.sim.sv_reassign(zone)
	Game.play_3d("telex", at, -4)
	rig.refresh_gadgets()

# ============================================================== level hooks

func on_gunshot(at: Vector3, _noise: float, suppressed: bool) -> void:
	if suppressed:
		return
	# Open gunfire in a crowd: the panic starts where the shot was.
	crowd.start_panic(at)
	crowd.witness(at)

func on_lure_active(at: Vector3, radius: float, duration: float) -> void:
	for id: String in eyes:
		if eyes[id].global_position.distance_to(at) < radius * 1.6:
			Game.sim.sv_jam(id, duration)

func on_shootable_hit(col: Object, dmg: float) -> void:
	match str(col.get_meta("shootable")):
		"eye":
			var fid := str(col.get_meta("feed"))
			var e: Eye = eyes.get(fid)
			if e and e.kind == "drone":
				_hit_drone(e, dmg)
			else:
				Game.sim.sv_destroy(fid)
		"pursuer":
			_hit_pursuer(col as BikeController, dmg)

# ---- saucer drones: shoot them down, or rope them into something

func drone_of(col: Object) -> Eye:
	if col == null or not col.has_meta("feed"):
		return null
	var e: Eye = eyes.get(str(col.get_meta("feed")))
	return e if e and e.kind == "drone" and e.live else null

func _hit_drone(e: Eye, dmg: float) -> void:
	if not e.live:
		return
	rig.hit_t = 0.16
	rig.hit_kill = false
	rig.hit_head = false
	Game.play_2d("hitmark", -6)
	var down := e.hit(dmg)
	if Game.debug.has("tt"):
		print("tt: drone hit, hull %.2f" % e.get_hull())
	if down:
		hud.message("The saucer is going down.")
		slam_drone(e, Vector3.INF)
	elif e.get_hull() < 0.5 and not e.has_node("DamageSmoke"):
		var smoke := Builder.damage_smoke(Vector3.ZERO)
		e.add_child(smoke)
		smoke.emitting = true

## Replaces the drone with a falling wreck, aimed at `at` if a line is pulling it.
func slam_drone(e: Eye, at: Vector3) -> DroneWreck:
	var id := str(e.feed_id)
	Game.sim.sv_destroy(id)
	_set_eye_live(id, false)
	e.visible = false
	e.get_node("Hit").queue_free()
	var w := DroneWreck.new()
	add_child(w)
	w.launch(_eye_head_mesh("drone"), Transform3D(Basis(), e.global_position), Vector3.ZERO, at, _wreck_landed)
	if at != Vector3.INF:
		w.gravity_scale = 0.3
	return w

## A saucer has hit something. Anyone under it is dead, and nobody missed that.
func _wreck_landed(at: Vector3, speed: float) -> void:
	if Game.debug.has("tt"):
		print("tt: wreck landed at %s speed %.1f" % [str(at), speed])
	Game.play_3d("crash", at, 6, 18.0, 0.65)
	Game.play_3d("thud", at, 4, 12.0, 0.7)
	rig._burst("sparks", at, Vector3.UP)
	rig._burst("dust", at, Vector3.UP)
	if player.global_position.distance_to(at) < 14.0:
		rig.jolt(10.0)
	for n in get_tree().get_nodes_in_group("npc"):
		if n is Npc and n.alive and n.global_position.distance_to(at) < 3.2:
			n.apply_damage(400.0, at, false)
	if player.enabled and player.global_position.distance_to(at) < 2.2:
		rig.hurt.emit(40.0)
		Game.sim.damage_player(40.0)
	if not _indoors(at):
		crowd.start_panic(at)
	Game.sim.raise_alarm()

func _on_npc_died(n: Npc, silent: bool) -> void:
	# A witness or a camera must act before the kill is scored: seen = loud.
	var at := n.global_position + Vector3(0, 1.0, 0)
	if n == gov or not n.get_meta("parked", false):
		for id: String in eyes:
			if eyes[id].live and eyes[id].sees_point(at):
				Game.sim.sv_record(id, n == gov)
				break
		var outdoors := not _indoors(at)
		var seen: int = crowd.witness(at) if outdoors else 0
		if seen > 0 and not silent:
			crowd.start_panic(at)
			Game.sim.raise_alarm()
	super(n, silent)

func _indoors(p: Vector3) -> bool:
	return _in_boxes(INDOORS, p)

func _in_boxes(boxes: Array, p: Vector3) -> bool:
	for r in boxes:
		if p.x > r[0] and p.x < r[1] and p.y > r[2] and p.y < r[3] and p.z > r[4] and p.z < r[5]:
			return true
	return false

func _dusk_amount(st: Dictionary) -> float:
	return 0.12 + clampf((float(st.minute) - 985.0) / 71.0, 0.0, 1.0) * 0.45

func _update_zones(_t: float) -> void:
	var p := player.global_position + Vector3(0, 0.5, 0)
	player.restricted = 1 if _in_boxes(RESTRICTED, p) else 0
	var indoor := _indoors(p)
	# The press of the crowd hides you, from cameras and guards alike.
	var press := clampf(crowd.density_at(p) / crowd.press_density(), 0.0, 1.0)
	player.exposure = lerpf(0.85 if indoor else 1.0, 0.4, press)
	if weather:
		var cam := get_viewport().get_camera_3d()
		var cp := cam.global_position if cam else p
		var inside := _indoors(cp)
		weather.indoor = inside
		rain.emitting = not inside and weather.mode != "clear"

func _arrest_exit() -> String:
	return "fc_gate"

func _alarm_origin() -> Vector3:
	return player.global_position

func _speaker_node(who: String) -> Npc:
	match who:
		"Governor":
			return gov
		"Liaison":
			return liaison
	return super(who)

func _on_activity(e: Dictionary) -> void:
	_proc_i = -1
	if e.activity == "procession":
		_next_procession_point()
	elif gov.alive:
		_route_to(gov, e.location)
	if liaison.alive and e.activity != "procession":
		_route_to(liaison, "rec_c" if e.activity != "meeting" else "rec_sofa")

func _next_procession_point() -> void:
	_proc_i += 1
	if gov.alive and _proc_i < PROCESSION.size():
		_route_to(gov, PROCESSION[_proc_i])

func _on_gov_arrived() -> void:
	if gov_activity == "procession" and not Game.mstate().get("alarm", false):
		_next_procession_point()
		return
	super()

func _drive_away() -> void:
	gov.visible = false
	var gc := gov_car as ArcadeCar
	gc.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	gc.freeze = true
	_gov_tw = create_tween()
	_gov_tw.tween_property(gc, "position", Vector3(60, gc.position.y, -64), 4.0)
	_gov_tw.tween_callback(func(): gc.visible = false)

func _on_event(e: Dictionary) -> void:
	match e.type:
		"feed_changed":
			_set_eye_live(e.id, e.live)
		"feed_noticed":
			_on_noticed(e.zone)
		"feed_destroyed":
			hud.message("A feed has gone down hard. Avekṣā is on the radio.")
			Game.play_2d("beep_low", -2, 0.7)
			_send_guards(e.zone, 3)
		"recorded":
			hud.message("ON TAPE: %s." % ("a killing" if e.kill else "you, in %s" % ZONE_NAMES.get(e.zone, "the frame")))
			Game.play_2d("beep_low", -3, 1.3)
			_send_guards(e.zone, 2)
		"record_alarm":
			Game.sim.raise_alarm()
		"reassigned":
			_order_patrols_away(e.zone)
			hud.message("Patrols in %s have been ordered elsewhere." % ZONE_NAMES.get(e.zone, e.zone))
		"reassign_ended":
			_restore_patrols(e.zone)
			hud.message("The room has queried the order. Patrols are back in %s." % ZONE_NAMES.get(e.zone, e.zone))
		"pursuit_over":
			pass
		"alarm":
			crowd.start_panic(player.global_position)
			super(e)
		"finished":
			crowd.clear_retinue()
			super(e)
		_:
			super(e)

func _set_eye_live(id: String, live: bool) -> void:
	if not eyes.has(id):
		return
	var e: Eye = eyes[id]
	e.live = live
	var head: Node3D = e.get_node("Head")
	if not live:
		head.rotation.x = deg_to_rad(-70.0)

func _on_noticed(zone: String) -> void:
	if zone == "room":
		hud.message("The room has missed a check-in. Avekṣā is sending someone up.")
		_send_guards("nave", 2, locations["mon_c"])
		return
	hud.message("The room has noticed %s is dark. Guards are on the way." % ZONE_NAMES.get(zone, zone))
	_send_guards(zone, 2)
	_reset_timers[zone] = 25.0

func _send_guards(zone: String, n: int, to = null) -> void:
	var dest: Vector3 = to if to != null else player.global_position
	if to == null and not _in_zone_of_player(zone):
		dest = _zone_point(zone)
	var sent := 0
	for g in guards:
		if sent >= n:
			break
		if g.alive and g.get_meta("zone", "") == zone:
			g.alert(dest, false)
			sent += 1

func _in_zone_of_player(_zone: String) -> bool:
	return true

func _zone_point(zone: String) -> Vector3:
	match zone:
		"forecourt":
			return locations["fc_mid"]
		"grand_stair":
			return locations["s1_top"]
		"terrace":
			return locations["t1_c"]
		"upper":
			return locations["t2_c"]
		"nave":
			return locations["nave_mid"]
		"reception":
			return locations["rec_c"]
	return locations["t1_c"]

func _order_patrols_away(zone: String) -> void:
	for g in guards:
		if g.alive and g.get_meta("zone", "") == zone:
			var pv := PackedVector3Array([locations["far_post"], locations["ramp_top"]])
			g.set_patrol(pv)

func _restore_patrols(zone: String) -> void:
	for g in guards:
		if g.alive and g.get_meta("zone", "") == zone and not (g.get_meta("patrol", []) as Array).is_empty():
			var pv := PackedVector3Array()
			for p in g.get_meta("patrol"):
				pv.append(locations[p])
			g.set_patrol(pv)

func hud_lines() -> Array:
	var out := []
	var s: Dictionary = Game.sim.sv_state()
	if s.is_empty():
		return out
	var feeds := "FEEDS %d/%d  ON TAPE %d" % [int(s.live), int(s.total), int(s.recorded)]
	if str(s.next_zone) != "":
		feeds += "  %s DARK: %ds" % [str(s.next_zone).to_upper(), int(s.next_secs)]
	out.append(feeds)
	if Game.sim.pursuit_active():
		out.append("PURSUIT  %d riders  unseen %ds / %ds" % [pursuers.size(), int(Game.sim.pursuit_unseen()), int(_params.get("lose_seconds", 0.0))])
	elif riding:
		out.append("A1 MAURYAN WAY  KM %.2f" % (maxf(player.global_position.z - ROAD_START_Z, 0.0) / 1000.0))
	return out

func _process(dt: float) -> void:
	super(dt)
	if get_tree().paused or _finished or gov == null:
		return
	var st := Game.mstate()
	# The crowd parts for him when he is out among them.
	if gov.alive and gov_activity == "procession" or (gov.alive and gov.global_position.z > -46.0):
		crowd.set_retinue(gov.global_position, 5.5)
	else:
		crowd.clear_retinue()
	_update_retinue()
	_slot_t -= dt
	if _slot_t <= 0.0:
		_slot_t = 0.4
		_update_slots()
	_report_t -= dt
	if _report_t <= 0.0:
		_report_t = 1.0
		_update_reports(st)
	for z in _reset_timers.keys():
		_reset_timers[z] -= dt
		if _reset_timers[z] <= 0.0:
			_reset_timers.erase(z)
			if not st.get("alarm", false):
				Game.sim.sv_restore_zone(z)
				hud.message("Avekṣā's technicians have reset %s." % ZONE_NAMES.get(z, z))
	_update_road(dt, st)
	_update_cones()
	if Game.debug.has("tt"):
		_debug_scenario(dt)

func _update_retinue() -> void:
	if gov == null or not gov.alive:
		return
	var at := gov.global_position
	var f := -gov.global_basis.z
	var side := f.cross(Vector3.UP)
	var offs := [f * 2.2 + side * 1.6, f * 2.2 - side * 1.6, -f * 2.2 + side * 1.6, -f * 2.2 - side * 1.6]
	for i in retinue.size():
		var g := retinue[i]
		if g.alive and not g.in_combat():
			var dest: Vector3 = at + offs[i]
			if g.global_position.distance_to(dest) > 1.0:
				g.steer_to(dest, 1.6 if g.global_position.distance_to(dest) > 3.0 else 1.25)

func _update_reports(st: Dictionary) -> void:
	var near := PackedVector3Array()
	for g in guards:
		if g.alive:
			near.append(g.global_position)
	for at in crowd.take_reports(near):
		_reports += 1
		hud.message("A pilgrim is pointing you out to the guards.")
		for g in guards:
			if g.alive and g.global_position.distance_to(at) < 30.0:
				g.alert(at, false)
		if _reports >= 2 or st.get("removed", "") != "":
			Game.sim.raise_alarm()
	var crushed: int = crowd.crushed()
	if crushed > 0:
		Game.sim.report_crushed(crushed)
		if not _crush_reported:
			_crush_reported = true
			Game.sim.market_event("crush", 1.0)
			hud.message("There are people down on the stair.")

func _update_cones() -> void:
	if Engine.get_process_frames() % 6 != 0:
		return
	for id: String in eyes:
		var e: Eye = eyes[id]
		var mat: StandardMaterial3D = (e.get_node("Head/Cone") as MeshInstance3D).mesh.material
		var k := e.get_level()
		# Invisible until a camera starts to take an interest.
		mat.albedo_color = Color(0.6, 0.9, 0.7, 0.0).lerp(Color(1.0, 0.45, 0.15, 0.16), k)
		e.get_node("Head/Cone").visible = k > 0.01

# ============================================================== road, pursuit

func _focus_pos() -> Vector3:
	return bike.global_position if riding and bike else player.global_position

func _update_road(dt: float, st: Dictionary) -> void:
	var f := _focus_pos()
	if not _road_on and f.z > 104.0:
		_road_on = true
		road.visible = true
		traffic = Traffic.new()
		traffic.name = "Traffic"
		traffic.focus = f
		add_child(traffic)
		traffic.min_z = ROAD_START_Z
		traffic.setup(4, 326)
		traffic_obstacles()
	if _road_on:
		road.update(maxf(f.z, ROAD_START_Z))
		if traffic:
			traffic.focus = Vector3(f.x, f.y, maxf(f.z, ROAD_START_Z + 40.0))
	if st.get("removed", "") == "":
		return
	# Asked every frame until it answers: a clean exit that turns loud at the
	# gate still gets chased.
	if not _pursuit_started and f.z > GATE_Z - 6.0:
		_start_pursuit(f)
	_update_pursuers(dt)
	if safehouse.has_point(f):
		Game.sim.reach_safehouse()

func _check_exfil() -> void:
	pass  # Only the yard, or losing them, ends this mission.

func _start_pursuit(f: Vector3) -> void:
	var r: Dictionary = Game.sim.pursuit_start()
	var nb := int(r.get("bikes", 0))
	var nd := int(r.get("drones", 0))
	if nb + nd == 0:
		return
	_pursuit_started = true
	if nb + nd > 0:
		hud.message("Avekṣā riders behind you, and a saucer overhead. Lose them, or make the yard.")
	var back := float(_params.get("spawn_behind", 70.0))
	for i in nb:
		# They come down from the temple behind you, never out of thin air.
		var z := maxf(f.z - back - i * 7.0, 48.0 + i * 3.0)
		var b := spawn_pursuer(Vector3(-5.0 + i * 5.0, 0.6, z))
		pursuers.append(b)
	for i in nd:
		var d := _add_eye("h_%d" % i, "pursuit", "drone", f + Vector3(-12.0 + i * 24.0, 22.0, -back), 0.0, -30.0)
		d.chasing = true
		d.fired.connect(_on_shot_at_player)
		hunter_drones.append(d)

func spawn_pursuer(pos: Vector3) -> BikeController:
	var b := Builder.make_bike(P.CARBON)
	b.position = pos
	b.rotation.y = PI
	add_child(b)
	b.set_engine_stream(Game.sfx["ringding"])
	b.get_node("Visual/Rider").visible = true
	b.ai_max_speed = float(_params.get("bike_speed", 44.0))
	b.set_ai(true)
	b.set_meta("shootable", "pursuer")
	b.set_meta("hp", 60.0)
	b.set_meta("shot_t", randf_range(1.0, 2.0))
	# The bike's own box stops at the tank: this one is the rider, to be shot.
	var torso := CollisionShape3D.new()
	torso.name = "RiderBox"
	var tb := BoxShape3D.new()
	tb.size = Vector3(0.5, 0.75, 0.5)
	torso.shape = tb
	torso.position = Vector3(0, 1.45, 0.05)
	b.add_child(torso)
	# They hold station around you; only you can knock them off.
	for other in pursuers:
		b.add_collision_exception_with(other)
	if bike:
		b.add_collision_exception_with(bike)
	# Riders crash too; that is one way to lose them.
	b.crashed.connect(func(_dv, _injury, eject):
		if Game.debug.has("tt"):
			print("tt: rider crash dv=%.1f at %s eject=%s" % [_dv, str(b.global_position), str(eject)])
		Game.play_3d("crash", b.global_position, -4, 8.0, randf_range(1.05, 1.25))
		if eject or b.get_hull() <= 0.0:
			_hit_pursuer(b, 1000.0))
	return b

func _hit_pursuer(b: BikeController, dmg: float) -> void:
	if b == null or not b.ai_active:
		return
	var hp := float(b.get_meta("hp", 60.0)) - dmg
	b.set_meta("hp", hp)
	if hp <= 0.0:
		b.set_ai(false)
		_throw_off_rider(b)
		b.fall_over()
		pursuers.erase(b)
		Game.play_3d("thud", b.global_position, 0)
		hud.message("A rider is down.")

## The rider leaves the saddle at the speed they were doing, and tumbles.
func _throw_off_rider(b: BikeController) -> void:
	var rider: MeshInstance3D = b.get_node("Visual/Rider")
	rider.visible = false
	var box := b.get_node_or_null("RiderBox")
	if box:
		box.queue_free()
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 75.0
	body.linear_damp = 0.15
	body.angular_damp = 0.7
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.22
	shape.height = 1.5
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = rider.mesh
	mi.position = Vector3(0, -1.05, 0)
	body.add_child(mi)
	add_child(body)
	body.global_position = b.global_position + Vector3(0, 1.05, 0)
	body.global_basis = b.global_basis
	body.linear_velocity = b.linear_velocity * 0.85 + Vector3(randf_range(-1.5, 1.5), 2.5, 0)
	body.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))
	get_tree().create_timer(30.0).timeout.connect(body.queue_free)

func _line_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## A car in the rider's lane, close ahead: aim past its nearer side instead.
func _round_traffic(p: Vector3, target: Vector3) -> Vector3:
	if traffic == null:
		return target
	var dir := signf(target.z - p.z)
	for c in traffic.cars:
		var at: Vector3 = c.body.global_position
		var ahead := (at.z - p.z) * dir
		if ahead > 0.0 and ahead < 32.0 and absf(at.x - p.x) < 1.9:
			return Vector3(at.x + (2.8 if p.x >= at.x else -2.8), target.y, at.z)
	return target

func _focus_speed() -> float:
	if riding and bike:
		return bike.get_speed()
	if driving and car:
		return car.get_speed()
	return 0.0

func _update_pursuers(dt: float) -> void:
	if not Game.sim.pursuit_active():
		return
	var f := _focus_pos()
	var aim := f + Vector3(0, 1.0, 0)
	var sight := float(_params.get("sight_range", 90.0))
	var seen := false
	for b in pursuers:
		var p := b.global_position
		var d := p.distance_to(f)
		var eye := p + Vector3(0, 1.4, 0)
		var clear := d < sight and _line_clear(eye, aim)
		seen = seen or clear
		# Stay on the road: head for a point on the player's line, ahead of here.
		var target := f
		if p.z > GATE_Z:
			target.x = clampf(f.x, -12.0, 12.0)
		target = _round_traffic(p, target)
		var to := target - p
		to.y = 0.0
		var fwd := -b.global_basis.z
		var err := Vector3(fwd.x, 0, fwd.z).signed_angle_to(to, Vector3.UP)
		b.ai_steer = clampf(err * 1.8, -1.0, 1.0)
		b.ai_throttle = 1.0 if absf(err) < 0.7 else 0.55
		# Enough room to actually stop: a rider does not ram you from 150 km/h.
		var close := d < 10.0 + maxf(b.get_speed() - _focus_speed(), 0.0) * 0.8
		b.ai_brake = 1.0 if close else 0.0
		if close:
			b.ai_throttle = 0.0
		var t := float(b.get_meta("shot_t")) - dt
		if t <= 0.0:
			t = float(_params.shot_interval) * randf_range(0.8, 1.4)
			if clear and d < float(_params.shot_range):
				var hit := randf() < float(_params.shot_hit_chance)
				_on_shot_at_player(eye, aim, hit, float(_params.shot_damage))
				Game.play_3d("shot_far", eye, -4)
		b.set_meta("shot_t", t)
	for dr in hunter_drones:
		if dr.live and dr.global_position.distance_to(f) < sight and _line_clear(dr.global_position, aim):
			seen = true
	Game.sim.pursuit_tick(dt, seen)
	if Game.sim.pursuit_active() and not _lose_note and Game.sim.pursuit_unseen() > 5.0:
		_lose_note = true
		hud.message("They have lost sight of you. Keep going.")
	if not seen:
		return
	_lose_note = false

# ============================================================== debug scenario

## `--tt=loud|quiet|poison|chase`: runs a mission path with no input and
## prints what happened. Used to check the wiring; not reachable in play.
func _debug_scenario(dt: float) -> void:
	_tt_t += dt
	if str(Game.debug.tt).begins_with("ufo"):
		_tt_ufo()
		return
	if str(Game.debug.tt) == "chase" and _tt_t > 16.0 and not pursuers.is_empty() and not has_meta("tt_down"):
		var down: BikeController = pursuers[0]
		set_meta("tt_down", true)
		print("tt: rider shot at %.1f m/s" % down.get_speed())
		_hit_pursuer(down, 1000.0)
		get_tree().create_timer(8.0).timeout.connect(func():
			print("tt: 8 s later the bike's up.y=%.2f y=%.2f speed=%.1f fallen=%s" % [down.global_basis.y.y, down.global_position.y, down.linear_velocity.length(), str(down.is_fallen())]))
	var st := Game.mstate()
	if _tt_step == 0 and _tt_t > 2.0:
		_tt_step = 1
		print("tt: start crowd=%d guards=%d feeds=%s" % [crowd.agent_count(), guards.size(), str(Game.sim.sv_state())])
		match str(Game.debug.tt):
			"loud":
				player.global_position = locations["t1_c"] + Vector3(4, 1, 0)
				gov.global_position = locations["t1_c"] + Vector3(0, 0.2, 0)
				on_gunshot(player.global_position, 90.0, false)
				gov.apply_damage(9999.0, player.global_position, false)
			"quiet":
				gov.global_position = locations["rec_tea"] + Vector3(0, 0.2, 0)
				for id in ["g_r1"]:
					Game.sim.sv_pull(id)
				gov.take_down()
			"poison":
				Game.sim.poison_tea(_gadget_id("poison"))
				Game.sim.governor_drinks_tea()
			"loop":
				Game.sim.sv_loop_zone("terrace")
				Game.sim.sv_toggle_power("nave")
				Game.sim.sv_destroy("g_f1")
				print("tt: after disable ", Game.sim.sv_state())
	elif _tt_step == 1 and _tt_t > 6.0:
		_tt_step = 2
		print("tt: t=6 removed=%s alarm=%s panic=%s" % [str(st.get("removed", "")), str(st.get("alarm", "")), str(crowd.panicking())])
		print("tt: sv ", Game.sim.sv_state())
		if st.get("removed", "") != "" or str(Game.debug.tt) == "chase":
			if str(Game.debug.tt) == "chase":
				Game.sim.raise_alarm()
				gov.apply_damage(9999.0, player.global_position, false)
			bike.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(5, 0.8, 136))
			enter_bike(bike)
			Input.action_press("move_forward")
	elif _tt_step == 2 and _focus_pos().z > 1000.0:
		_tt_step = 3
		print("tt: reached km 1 at t=%d, calling the yard" % int(_tt_t))
		Game.sim.reach_safehouse()
	elif _tt_step == 2 and int(_tt_t) % 5 == 0 and fmod(_tt_t, 5.0) < dt:
		print("tt: x=%.1f y=%.2f" % [_focus_pos().x, _focus_pos().y])
		print("tt: t=%d z=%.0f speed=%.1f gear=%d pursuers=%d pursuit=%s hp=%.0f" % [int(_tt_t), _focus_pos().z, bike.get_speed() if bike else 0.0, bike.get_gear() if bike else 0, pursuers.size(), str(Game.sim.pursuit_active()), float(st.get("health", 0.0))])
		if float(st.get("health", 100.0)) <= 0.0 or _finished:
			print("tt: finished")

## Through the real rig: shoot a drone down, or rope it and slam it at a point.
func _tt_ufo() -> void:
	var kind := str(Game.debug.tt)
	var d: Eye = eyes["d_1"]
	if _tt_step == 0 and _tt_t > 2.0:
		_tt_step = 1
		player.global_position = Vector3(d.global_position.x + 6.0, 1.0, d.global_position.z + 6.0)
		print("tt: drone at ", d.global_position)
	if _tt_step < 1 or _tt_step >= 9:
		return
	if d.live:
		var to := d.global_position - rig.cam.global_position
		player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	if _tt_step == 1 and _tt_t > 3.0:
		_tt_step = 2
		if kind == "uforope":
			for i in rig.loadout.size():
				if str(rig.loadout[i].def.get("kind", "gun")) == "grapple":
					rig._equip(i, true)
			rig._fire_grapple()
	if kind == "ufo" and _tt_step == 2 and d.live and fmod(_tt_t, 0.4) < get_physics_process_delta_time():
		rig._fire()
		var look: Vector3 = player.get_look_dir()
		var want: Vector3 = (d.global_position - rig.cam.global_position).normalized()
		print("tt: shot; look error %.1f deg, ammo %s, dist %.0f" % [rad_to_deg(look.angle_to(want)), str(rig.loadout[rig.slot].get("ammo", "?")), rig.cam.global_position.distance_to(d.global_position)])
	if kind == "uforope" and _tt_step == 2 and rig._latched_drone:
		_tt_step = 3
		print("tt: line in the saucer; live=%s" % str(d.live))
		var t := d.global_position + Vector3(14, -d.global_position.y + 0.2, 0)
		rig._latched_drone = d
		rig._slam_drone(t, false)
		print("tt: slamming at ", t)
	if not d.live and _tt_step < 9:
		_tt_step = 9
		print("tt: drone down, hull %.2f, feeds %s" % [d.get_hull(), str(Game.sim.sv_state().live)])

## A rider on a blown tyre at chase speed does not stay on for long.
func on_tyre_shot(v: Node3D, i: int) -> void:
	super(v, i)
	if v is BikeController and pursuers.has(v):
		get_tree().create_timer(0.9).timeout.connect(func():
			if is_instance_valid(v):
				Game.play_3d("crash", v.global_position, -2, 8.0, 1.15)
				_hit_pursuer(v, 1000.0))

func _on_bike_crash(b: BikeController, dv: float, injury: float, eject: bool) -> void:
	if Game.debug.has("tt"):
		print("tt: bike crash dv=%.1f injury=%.1f eject=%s hull=%.2f" % [dv, injury, str(eject), b.get_hull()])
	super(b, dv, injury, eject)

func _on_finished(method: String) -> void:
	if Game.debug.has("tt"):
		print("tt: finish; player health %s, alarm %s" % [str(Game.mstate().get("health", "?")), str(Game.mstate().get("alarm", "?"))])
	if Game.debug.has("tt"):
		print("tt: FINISHED method=%s dispatch=%s extra_sv=%s" % [method, Game.sim.mission_dispatch(method), str(Game.sim.sv_state())])
	await super(method)
