extends LevelBase
## Saptavarta Governorate [INVENTED]: the vertical slice.
## Grey atompunk compound and boulevard outside; 1980s executive interiors
## inside; cassette-tech everywhere. The governor follows his routine from
## data/missions.ron; the player scouts, then kills, poisons, or frames him.

const COMPOUND := AABB(Vector3(-39.5, -2, -44.5), Vector3(79, 60, 74))

var gov: Npc
var courier: Npc
var guards: Array[Npc] = []
var nodes := {}
var locations := {}
var gov_activity := ""
var gov_car: Node3D
var _gov_tw: Tween
var alarm_player: AudioStreamPlayer3D
var ambience: AudioStreamPlayer
var beacons: Array[MeshInstance3D] = []
var _tea_timer := -1.0
var _finished := false
var _arrest_timer := -1.0
var _info := {}
var dirigible: Node3D
## Governor to replay in free play ("" = the first playable one).
var replay_gov := ""

# ============================================================== build

func build_world() -> void:
	if not Game.sim.mission_active():
		Game.sim.start_mission()
	_info = Game.sim.mission_info()
	_build_ground_and_streets()
	_build_boulevard()
	_build_compound_walls()
	_build_residence()
	_build_interiors()
	_build_grounds()
	_build_skyline()
	_build_detail()
	_build_nav()
	_build_interactables()
	_build_audio()

func player_spawn() -> Array:
	return [Vector3(13, 0.3, 128), 0.0]

func after_spawn() -> void:
	car = spawn_car(Vector3(7, 0.8, 122), 0.0)
	_spawn_npcs()
	hud.message("SAPTAVARTA. %s. Evening." % _info.get("title", ""))
	hud.message("Target: %s. TAB for the dossier." % _info.get("governor", "the governor"))

func _occluder(pos: Vector3, size: Vector3) -> void:
	var oi := OccluderInstance3D.new()
	var bo := BoxOccluder3D.new()
	bo.size = size
	oi.occluder = bo
	oi.position = pos
	add_child(oi)

func _build_ground_and_streets() -> void:
	var b := Builder.new()
	b.box(P.CONCRETE, Vector3(0, -0.5, 0), Vector3(700, 1, 700))
	# Boulevard road + raised sidewalks (curbs exercise step-up and suspension).
	b.box(P.ROAD, Vector3(0, 0.01, 100), Vector3(20, 0.02, 140), false)
	for s in [-1, 1]:
		b.box(P.CONCRETE, Vector3(13 * s, 0.075, 100), Vector3(6, 0.15, 140))
		b.box(P.CONCRETE_DARK, Vector3(10.1 * s, 0.09, 100), Vector3(0.25, 0.18, 140))
	# Ring road around the compound.
	b.box(P.ROAD, Vector3(0, 0.01, 39), Vector3(132, 0.02, 12), false)
	b.box(P.ROAD, Vector3(0, 0.01, -64), Vector3(132, 0.02, 12), false)
	b.box(P.ROAD, Vector3(-60, 0.01, -12.5), Vector3(12, 0.02, 115), false)
	b.box(P.ROAD, Vector3(60, 0.01, -12.5), Vector3(12, 0.02, 115), false)
	# Median with a monument: atompunk obelisk with saucer rings.
	b.block(P.CONCRETE_PALE, Vector3(0, 0, 95), Vector3(4, 0.15, 30))
	b.block(P.CONCRETE_PALE, Vector3(0, 0.15, 95), Vector3(5, 1.2, 5))
	b.cyl(P.CONCRETE, Vector3(0, 9.0, 95), 1.6, 0.9, 16, 8, true)
	b.cyl(P.STEEL, Vector3(0, 13.5, 95), 4.2, 4.2, 0.35, 24)
	b.cyl(P.STEEL, Vector3(0, 16.0, 95), 2.8, 2.8, 0.3, 24)
	b.cyl(P.BRASS, Vector3(0, 17.4, 95), 0.6, 0.0, 1.6, 12)
	b.cyl(P.AMBER, Vector3(0, 13.75, 95), 4.0, 4.0, 0.12, 24, false, false)
	# World boundary.
	for w in [[Vector3(0, 10, 175), Vector3(400, 20, 1)], [Vector3(0, 10, -110), Vector3(400, 20, 1)],
			[Vector3(105, 10, 30), Vector3(1, 20, 300)], [Vector3(-105, 10, 30), Vector3(1, 20, 300)]]:
		b.kit.add_collider(Builder.xf(w[0]), w[1])
	b.commit(self, "Streets")

func _facade_block(b: Builder, base: Vector3, size: Vector3, fins: Array, side: int) -> void:
	# Podium + tower with a glazing grid and repeated structural fins.
	var pod_h := 5.0
	b.block(P.CONCRETE_DARK, base, Vector3(size.x, pod_h, size.z))
	b.block(P.CONCRETE, base + Vector3(0, pod_h, 0), Vector3(size.x - 2.0, size.y - pod_h, size.z - 2.0))
	b.block(P.CONCRETE_PALE, base + Vector3(0, size.y, 0), Vector3(size.x - 1.0, 0.8, size.z - 1.0), false)
	var face_x := base.x - side * (size.x * 0.5 - 1.0) - side * 0.06
	b.box(P.WINDOWS, Vector3(face_x, base.y + pod_h + (size.y - pod_h) * 0.5, base.z), Vector3(0.1, size.y - pod_h - 2.0, size.z - 4.0), false)
	b.box(P.WINDOWS, Vector3(base.x - side * size.x * 0.5 - side * 0.05, base.y + 2.6, base.z), Vector3(0.1, 2.6, size.z - 6.0), false)
	# Sweeping canopy over the entrance.
	b.box(P.CONCRETE_PALE, Vector3(base.x - side * (size.x * 0.5 + 1.5), base.y + 4.6, base.z), Vector3(3.0, 0.3, size.z * 0.5), false)
	var n := int((size.z - 4.0) / 2.4)
	for i in n:
		var z := base.z - (size.z - 4.0) * 0.5 + 1.2 + i * 2.4
		fins.append(Transform3D(Basis().scaled(Vector3(1.0, size.y - pod_h - 1.0, 1.0)),
			Vector3(face_x - side * 0.3, base.y + pod_h + (size.y - pod_h) * 0.5, z)))
	_occluder(base + Vector3(0, size.y * 0.5, 0), Vector3(size.x - 2.2, size.y, size.z - 2.2))

func _build_boulevard() -> void:
	var b := Builder.new()
	var fins := []
	var lamps := []
	var banners := []
	var trees := []
	var stalls := []
	var heights := [18.0, 26.0, 14.0, 32.0, 20.0]
	for side in [-1, 1]:
		for i in 4:
			var z := 58.0 + i * 30.0
			var h: float = heights[(i + (1 if side > 0 else 0)) % heights.size()]
			_facade_block(b, Vector3(side * 30.0, 0, z), Vector3(24, h, 24), fins, side)
		for i in 9:
			var z := 50.0 + i * 13.0
			lamps.append(Transform3D(Basis(Vector3.UP, 0.0 if side < 0 else PI), Vector3(side * 10.6, 0.15, z)))
			if i % 2 == 0:
				banners.append(Transform3D(Basis(Vector3.UP, PI / 2 * -side), Vector3(side * 15.6, 0.15, z + 6.5)))
			else:
				trees.append(Transform3D(Basis(Vector3.UP, randf() * TAU), Vector3(side * 14.5, 0.15, z + 6.5)))
		for i in 3:
			stalls.append(Transform3D(Basis(Vector3.UP, PI / 2 * side), Vector3(side * 14.2, 0.15, 66.0 + i * 30.0)))
	b.commit(self, "Boulevard")
	Builder.scatter(self, Builder.facade_fin(), fins, 260.0)
	Builder.scatter(self, Builder.lamp_post(), lamps, 160.0)
	Builder.scatter(self, Builder.banner_pole(), banners, 140.0, false)
	Builder.scatter(self, Builder.tree(), trees, 150.0)
	Builder.scatter(self, Builder.stall(), stalls, 90.0)
	# Stall colliders.
	var sc := Builder.new()
	for t in stalls:
		sc.kit.add_collider(Transform3D(t.basis, t.origin + Vector3(0, 0.5, 0)), Vector3(2.4, 1.0, 1.0))
	sc.commit(self, "StallCol")

func _build_compound_walls() -> void:
	var b := Builder.new()
	var h := 4.5
	b.wall_x(P.CONCRETE, -40, 40, 30, 0, h, 1.0, [[-4.5, 4.5]])
	b.wall_x(P.CONCRETE, -40, 40, -45, 0, h, 1.0)
	b.wall_z(P.CONCRETE, -45, 30, -40, 0, h, 1.0, [[-6.0, -4.6, 0.0, 1.2]])
	b.wall_z(P.CONCRETE, -45, 30, 40, 0, h, 1.0, [[-38.0, -32.0, 2.4, h]])
	# Coping and buttress bays along the walls.
	for x in range(-36, 40, 8):
		for z in [30.0, -45.0]:
			if absf(x) > 6:
				b.box(P.CONCRETE_DARK, Vector3(x, 2.4, z + (0.9 if z > 0 else -0.9)), Vector3(1.2, 4.8, 0.8))
	for z in range(-41, 30, 8):
		for x in [-40.0, 40.0]:
			if not (x > 0 and z > -39 and z < -31):
				b.box(P.CONCRETE_DARK, Vector3(x + (0.9 if x > 0 else -0.9), 2.4, z), Vector3(0.8, 4.8, 1.2))
	# Gate: pylons with amber beacons and a barrier arm.
	for s in [-1, 1]:
		b.block(P.CONCRETE_PALE, Vector3(5.6 * s, 0, 30.5), Vector3(2.2, 8.0, 2.4))
		b.cyl(P.STEEL, Vector3(5.6 * s, 8.4, 30.5), 1.4, 1.4, 0.25, 16)
		b.box(P.CHARCOAL, Vector3(5.6 * s, 4.5, 31.75), Vector3(1.2, 2.6, 0.1), false)
	b.box(P.CHARCOAL, Vector3(-2.0, 1.1, 31.4), Vector3(7.0, 0.14, 0.14), false)
	b.box(P.AMBER, Vector3(-4.8, 1.1, 31.4), Vector3(0.3, 0.2, 0.2), false)
	# Culvert channel outside the west wall.
	b.box(P.CONCRETE_DARK, Vector3(-42.5, 0.01, -5.3), Vector3(4, 0.02, 1.6), false)
	b.box(P.CHARCOAL, Vector3(-40, 1.25, -5.3), Vector3(1.1, 0.1, 1.5), false)
	# Crates outside the low east section: the mantle route.
	b.box(P.WARM_GREY, Vector3(41.3, 0.55, -35), Vector3(1.1, 1.1, 1.1))
	b.box(P.WARM_GREY, Vector3(42.5, 0.55, -36.2), Vector3(1.1, 1.1, 1.1))
	b.commit(self, "Walls")
	_occluder(Vector3(-22.5, 2.2, 30), Vector3(35, 4.4, 0.9))
	_occluder(Vector3(22.5, 2.2, 30), Vector3(35, 4.4, 0.9))
	_occluder(Vector3(0, 2.2, -45), Vector3(79, 4.4, 0.9))
	_occluder(Vector3(-40, 2.2, -25), Vector3(0.9, 4.4, 38))
	_occluder(Vector3(40, 2.2, 0), Vector3(0.9, 4.4, 58))
	for s in [-1, 1]:
		var bm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.22
		cm.height = 0.35
		cm.radial_segments = 10
		cm.material = P.mats()[P.AMBER]
		bm.mesh = cm
		bm.position = Vector3(5.6 * s, 8.7, 30.5)
		add_child(bm)
		beacons.append(bm)

func _build_residence() -> void:
	var b := Builder.new()
	var y1 := 4.8   # upper floor level
	var y2 := 9.6   # roof level
	var t := 0.6
	# Ground floor shell.
	b.wall_x(P.CONCRETE, -18, 18, -8, 0, 4.5, t, [[-3, 3, 0, 3.6], [-14, -11, 1.0, 3.4], [11, 14, 1.0, 3.4]])
	b.wall_x(P.CONCRETE, -18, 18, -30, 0, 4.5, t, [[-11, -9.6, 0, 2.5]])
	b.wall_z(P.CONCRETE, -30, -8, -18, 0, 4.5, t, [[-22, -16, 1.0, 3.4]])
	b.wall_z(P.CONCRETE, -30, -8, 18, 0, 4.5, t, [[-16, -12, 1.0, 3.4]])
	# Upper floor slab with the stair void (x -2..2, z -19.6..-13.2).
	b.box(P.CONCRETE_DARK, Vector3(-10, 4.65, -19), Vector3(16, 0.3, 22))
	b.box(P.CONCRETE_DARK, Vector3(10, 4.65, -19), Vector3(16, 0.3, 22))
	b.box(P.CONCRETE_DARK, Vector3(0, 4.65, -24.8), Vector3(4, 0.3, 10.4))
	b.box(P.CONCRETE_DARK, Vector3(0, 4.65, -10.6), Vector3(4, 0.3, 5.2))
	# Upper floor shell (strip windows on the south face).
	b.wall_x(P.CONCRETE, -18, 18, -8, y1, 4.8, t, [[-8, -6.4, 0, 2.6], [6.4, 8, 0, 2.6], [-16, -9, 0.9, 3.4], [-5, 5, 0.9, 3.4], [9.5, 16, 0.9, 3.4]])
	b.wall_x(P.CONCRETE, -18, 18, -30, y1, 4.8, t, [[-15, -6, 1.0, 3.2], [6, 15, 1.0, 3.2]])
	b.wall_z(P.CONCRETE, -30, -8, -18, y1, 4.8, t, [[-26, -12, 1.0, 3.2]])
	b.wall_z(P.CONCRETE, -30, -8, 18, y1, 4.8, t, [[-26, -12, 1.0, 3.2]])
	# Roof, with a deep sweeping cornice.
	b.box(P.CONCRETE_PALE, Vector3(0, y2 + 0.2, -19), Vector3(38.5, 0.5, 24.5))
	b.box(P.CONCRETE_PALE, Vector3(0, y2 + 0.55, -19), Vector3(40.5, 0.2, 26.5), false)
	# Central tower with saucer rings and a spire (the province's landmark).
	b.block(P.CONCRETE, Vector3(0, y2 + 0.45, -19), Vector3(10, 12, 10))
	b.block(P.WINDOWS, Vector3(0, y2 + 2.0, -13.95), Vector3(6, 8, 0.1), false)
	b.cyl(P.CONCRETE_PALE, Vector3(0, y2 + 12.8, -19), 7.0, 7.0, 0.7, 28)
	b.cyl(P.STEEL, Vector3(0, y2 + 13.5, -19), 9.5, 9.0, 0.4, 32)
	b.cyl(P.WINDOWS, Vector3(0, y2 + 14.4, -19), 6.0, 6.0, 1.4, 24, false, false)
	b.cyl(P.CONCRETE_PALE, Vector3(0, y2 + 15.4, -19), 6.6, 4.0, 0.8, 28)
	b.cyl(P.STEEL, Vector3(0, y2 + 17.5, -19), 3.0, 3.0, 0.3, 24)
	b.cyl(P.STEEL, Vector3(0, y2 + 21.0, -19), 0.25, 0.05, 7.0, 8)
	b.cyl(P.AMBER, Vector3(0, y2 + 24.6, -19), 0.25, 0.25, 0.3, 8)
	# Front: terrace slab on columns over the portico, parapet.
	b.box(P.CONCRETE_PALE, Vector3(1.5, 4.65, -5), Vector3(27, 0.3, 6))
	for x in [-12.0, -6.0, 6.0, 12.0]:
		b.cyl(P.CONCRETE_PALE, Vector3(x, 2.25, -2.6), 0.42, 0.5, 4.5, 12, true)
	b.box(P.CONCRETE_PALE, Vector3(-11.75, 5.3, -2.15), Vector3(0.5, 1.0, 0.3))
	b.box(P.CONCRETE_PALE, Vector3(0.3, 5.3, -2.15), Vector3(24.6, 1.0, 0.3))
	b.box(P.CONCRETE_PALE, Vector3(-12.0, 5.3, -5), Vector3(0.3, 1.0, 6))
	b.box(P.BRASS, Vector3(0.3, 5.82, -2.15), Vector3(24.6, 0.06, 0.34), false)
	b.box(P.CONCRETE_PALE, Vector3(15.1, 5.3, -5), Vector3(0.3, 1.0, 6))
	# Exterior stair from the courtyard to the east end of the terrace.
	b.stairs(P.CONCRETE_PALE, Vector3(14, 0, 4.0), 2.4, 0.25, 0.3, 19, PI, true)
	b.box(P.CONCRETE_PALE, Vector3(15.35, 2.6, 1.15), Vector3(0.25, 5.2, 5.9), false)
	# Banners on the facade.
	for x in [-15.0, 15.0]:
		b.box(P.BANNER, Vector3(x, 6.5, -7.6), Vector3(2.0, 5.0, 0.06), false)
		b.cyl_xf(P.BRASS, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(x, 7.2, -7.55)), 0.6, 0.6, 0.04, 16)
	# Glazing in the upper strip windows (smoked glass, few panes).
	b.box(P.GLASS, Vector3(-12.5, y1 + 2.15, -8), Vector3(7, 2.5, 0.05), false)
	b.box(P.GLASS, Vector3(12.75, y1 + 2.15, -8), Vector3(6.5, 2.5, 0.05), false)
	b.box(P.WINDOWS, Vector3(0, y1 + 2.15, -30.33), Vector3(9, 2.2, 0.05), false)
	b.box(P.WINDOWS, Vector3(-10.5, y1 + 2.15, -30.33), Vector3(9, 2.2, 0.05), false)
	b.box(P.WINDOWS, Vector3(10.5, y1 + 2.15, -30.33), Vector3(9, 2.2, 0.05), false)
	b.commit(self, "Residence")
	_occluder(Vector3(0, y2 + 6.5, -19), Vector3(9.8, 12, 9.8))

func _build_interiors() -> void:
	var b := Builder.new(0.22)
	var y1 := 4.8
	# --- Ground floor lobby: marble, brass, walnut.
	b.box(P.MARBLE, Vector3(0, 0.02, -19), Vector3(35, 0.04, 21), false)
	b.box(P.IVORY, Vector3(0, 4.45, -19), Vector3(35, 0.1, 21), false)
	b.wall_z(P.WALNUT, -30, -8, -8, 0, 4.5, 0.3, [[-20, -18.4, 0, 2.6]])
	b.wall_z(P.WALNUT, -30, -8, 8, 0, 4.5, 0.3, [[-15, -13.4, 0, 2.6]])
	b.wall_x(P.STEEL, 8, 18, -21, 0, 4.5, 0.5, [[12, 13.6, 0, 2.4]])
	for x in [-5.0, 5.0]:
		for z in [-12.0, -25.0]:
			b.cyl(P.BRASS, Vector3(x, 2.25, z), 0.3, 0.3, 4.5, 12, true)
	b.box(P.WALNUT, Vector3(-4.5, 0.55, -26.5), Vector3(4, 1.1, 1.0))
	b.box(P.MARBLE, Vector3(-4.5, 1.12, -26.5), Vector3(4.2, 0.06, 1.1), false)
	b.box(P.CRT, Vector3(-4.0, 1.4, -26.7), Vector3(0.5, 0.4, 0.02), false)
	b.box(P.BEIGE, Vector3(-4.0, 1.4, -26.95), Vector3(0.6, 0.5, 0.45), false)
	b.box(P.CARPET, Vector3(0, 0.05, -10.5), Vector3(6, 0.02, 4), false)
	b.box(P.BANNER, Vector3(0, 3.0, -29.6), Vector3(3.0, 2.8, 0.05), false)
	b.cyl(P.CONCRETE_PALE, Vector3(5.5, 0.6, -18.5), 0.7, 0.7, 1.2, 12, true)
	b.cyl(P.BRASS, Vector3(5.5, 1.9, -18.5), 0.0, 0.0, 0.01, 4)
	b.cyl(P.BRASS, Vector3(5.5, 1.55, -18.5), 0.5, 0.15, 0.7, 12)
	b.cyl(P.BRASS, Vector3(5.5, 2.2, -18.5), 0.45, 0.45, 0.06, 16)
	# Stairs to the upper floor (visual treads, smooth ramp collider).
	b.stairs(P.MARBLE, Vector3(0, 0, -13.9), 3.8, 0.25, 0.3, 19, PI, true)
	b.box(P.BRASS, Vector3(-1.95, 2.9, -16.2), Vector3(0.06, 0.06, 6.4), false)
	b.box(P.BRASS, Vector3(1.95, 2.9, -16.2), Vector3(0.06, 0.06, 6.4), false)
	b.box(P.WALNUT, Vector3(-2.1, 5.3, -16.4), Vector3(0.2, 1.0, 6.4))
	b.box(P.WALNUT, Vector3(2.1, 5.3, -16.4), Vector3(0.2, 1.0, 6.4))
	b.box(P.WALNUT, Vector3(0, 5.3, -13.1), Vector3(4.4, 1.0, 0.2))
	# --- Strongroom: steel, cassette banks, cold.
	b.box(P.STEEL, Vector3(14, 0.03, -25.5), Vector3(8, 0.04, 8.5), false)
	for i in 4:
		b.block(P.BEIGE, Vector3(10.6 + i * 1.6, 0, -29.3), Vector3(1.4, 2.2, 0.8))
		b.box(P.CRT, Vector3(10.6 + i * 1.6, 1.5, -28.88), Vector3(0.9, 0.6, 0.02), false)
		b.box(P.CHARCOAL, Vector3(10.6 + i * 1.6, 0.7, -28.88), Vector3(1.1, 0.4, 0.03), false)
	# --- West wing: service rooms.
	b.block(P.WARM_GREY, Vector3(-15, 0, -28), Vector3(4, 1.8, 2))
	b.block(P.BEIGE, Vector3(-12, 0, -28.6), Vector3(1.8, 2.0, 0.8))
	b.box(P.CRT, Vector3(-12, 1.4, -28.18), Vector3(0.8, 0.5, 0.02), false)
	# --- Upper floor: the governor's office (west half).
	b.box(P.CARPET, Vector3(-10, y1 + 0.02, -19), Vector3(15.4, 0.04, 21), false)
	b.box(P.IVORY, Vector3(0, y1 + 4.45, -19), Vector3(35, 0.1, 21), false)
	b.wall_z(P.WALNUT, -30, -8, -2, y1, 4.5, 0.3, [[-22.4, -20.8, 0, 2.6], [-13.2, -10.0, 0, 4.5]])
	# Lining inside the concrete shell: walnut wainscot, ivory fascia, brass rail.
	for fl in [0.0, y1]:
		for seg in [[Vector3(0, 0, -29.68), Vector3(35.4, 0, 0.04)], [Vector3(0, 0, -8.32), Vector3(35.4, 0, 0.04)],
				[Vector3(-17.68, 0, -19), Vector3(0.04, 0, 21.4)], [Vector3(17.68, 0, -19), Vector3(0.04, 0, 21.4)]]:
			var c: Vector3 = seg[0]
			var sz: Vector3 = seg[1]
			b.box(P.WALNUT, Vector3(c.x, fl + 0.5, c.z), Vector3(maxf(sz.x, 0.04), 1.0, maxf(sz.z, 0.04)), false)
			b.box(P.BRASS, Vector3(c.x, fl + 1.02, c.z), Vector3(maxf(sz.x, 0.06), 0.04, maxf(sz.z, 0.06)), false)
			b.box(P.IVORY, Vector3(c.x, fl + 3.85, c.z), Vector3(maxf(sz.x, 0.04), 1.2, maxf(sz.z, 0.04)), false)
	# Desk: walnut slab, brass edge, leather inset.
	b.box(P.WALNUT, Vector3(-12, y1 + 0.76, -22), Vector3(3.2, 0.08, 1.4))
	b.box(P.BRASS, Vector3(-12, y1 + 0.72, -22), Vector3(3.24, 0.03, 1.44), false)
	b.box(P.LEATHER, Vector3(-12, y1 + 0.805, -22), Vector3(1.6, 0.01, 0.8), false)
	b.box(P.WALNUT, Vector3(-13.3, y1 + 0.36, -22), Vector3(0.5, 0.72, 1.3))
	b.box(P.WALNUT, Vector3(-10.7, y1 + 0.36, -22), Vector3(0.5, 0.72, 1.3))
	b.box(P.WALNUT, Vector3(-12, y1 + 0.4, -22.6), Vector3(2.4, 0.6, 0.1), false)
	# Desk terminal (CRT) and dispatch tray.
	b.box(P.BEIGE, Vector3(-11.2, y1 + 1.05, -22.35), Vector3(0.55, 0.45, 0.5), false)
	b.box(P.CRT, Vector3(-11.2, y1 + 1.08, -22.09), Vector3(0.42, 0.32, 0.02), false)
	b.box(P.BEIGE, Vector3(-11.2, y1 + 0.84, -21.85), Vector3(0.6, 0.05, 0.22), false)
	b.box(P.BRASS, Vector3(-12.7, y1 + 0.84, -21.9), Vector3(0.45, 0.06, 0.32), false)
	b.box(P.IVORY, Vector3(-12.7, y1 + 0.875, -21.9), Vector3(0.36, 0.02, 0.26), false)
	b.cyl(P.BRASS, Vector3(-13.3, y1 + 1.05, -22.3), 0.08, 0.05, 0.4, 8)
	b.cyl(P.LAMP, Vector3(-13.3, y1 + 1.3, -22.3), 0.18, 0.1, 0.18, 10)
	# Telex machine on its own stand.
	b.block(P.WARM_GREY, Vector3(-16.4, y1, -25), Vector3(1.0, 0.75, 0.8))
	b.box(P.BEIGE, Vector3(-16.4, y1 + 0.95, -25), Vector3(0.9, 0.4, 0.7), false)
	b.box(P.CHARCOAL, Vector3(-16.4, y1 + 1.05, -24.7), Vector3(0.7, 0.12, 0.2), false)
	b.box(P.IVORY, Vector3(-16.4, y1 + 1.35, -25.1), Vector3(0.5, 0.4, 0.02), false)
	b.box(P.AMBER, Vector3(-16.0, y1 + 1.12, -24.66), Vector3(0.05, 0.05, 0.02), false)
	# Bookshelves along the west wall, leather seating, plants, curtains.
	for z in [-28.0, -25.5, -15.0, -12.5]:
		b.block(P.WALNUT, Vector3(-17.4, y1, z), Vector3(0.6, 3.2, 2.2))
		for k in 4:
			b.box(P.BURGUNDY if k % 2 == 0 else P.IVORY, Vector3(-17.1, y1 + 0.6 + k * 0.75, z), Vector3(0.1, 0.4, 1.8), false)
	b.box(P.WALNUT, Vector3(-8, y1 + 0.4, -14), Vector3(1.6, 0.06, 1.0))
	b.cyl(P.CHROME, Vector3(-8, y1 + 0.2, -14), 0.1, 0.1, 0.4, 8)
	b.box(P.BURGUNDY, Vector3(-10.5, y1 + 2.4, -8.5), Vector3(0.8, 4.0, 0.15), false)
	b.box(P.BURGUNDY, Vector3(-4.3, y1 + 2.4, -8.5), Vector3(0.8, 4.0, 0.15), false)
	# East hall (archive).
	b.box(P.MARBLE, Vector3(10, y1 + 0.02, -19), Vector3(15.4, 0.04, 21), false)
	for x in [6.0, 10.0, 14.0]:
		b.block(P.WALNUT, Vector3(x, y1, -28.6), Vector3(3.0, 2.6, 0.8))
	b.block(P.BEIGE, Vector3(15.5, y1, -18), Vector3(1.6, 1.6, 0.9))
	b.box(P.CRT, Vector3(15.5, y1 + 1.2, -17.53), Vector3(0.9, 0.6, 0.02), false)
	# Terrace furniture: tea table.
	b.cyl(P.WALNUT, Vector3(6, y1 + 0.7, -4.0), 0.55, 0.55, 0.06, 16)
	b.cyl(P.CHROME, Vector3(6, y1 + 0.35, -4.0), 0.06, 0.2, 0.7, 8)
	b.commit(self, "Interiors", 70.0)
	# Furniture via multimesh.
	var chairs := [
		Transform3D(Basis(Vector3.UP, PI), Vector3(-12, y1, -23.4)),
		Transform3D(Basis(Vector3.UP, 0.0), Vector3(-12.6, y1, -20.6)),
		Transform3D(Basis(Vector3.UP, 0.0), Vector3(-11.4, y1, -20.6)),
		Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-9.6, y1, -14)),
		Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-6.4, y1, -14)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(6, y1, -3.0)),
		Transform3D(Basis(Vector3.UP, 0.0), Vector3(-2.5, 0, -24)),
		Transform3D(Basis(Vector3.UP, 0.0), Vector3(2.5, 0, -24)),
	]
	Builder.scatter(self, Builder.chair(), chairs, 60.0)
	var plants := []
	for p in [Vector3(-16.8, y1, -9), Vector3(-3, y1, -29), Vector3(-7, 0, -9), Vector3(7, 0, -9), Vector3(-7, 0, -29), Vector3(17, y1, -9), Vector3(-11, y1, -2.8), Vector3(11, y1, -2.8)]:
		plants.append(Transform3D(Basis().scaled(Vector3.ONE * 1.3), p))
	Builder.scatter(self, Builder.planter(), plants, 70.0)
	# Warm interior lights (no shadows), a cold strongroom light.
	for l in [[Vector3(-11, y1 + 3.6, -21), 13.0, 2.2, "#E9B86A"], [Vector3(-9, y1 + 3.4, -12), 10.0, 1.6, "#E9B86A"],
			[Vector3(0, 3.6, -19), 16.0, 2.0, "#E9B86A"], [Vector3(-13, 3.4, -20), 9.0, 1.2, "#E9B86A"],
			[Vector3(8, y1 + 3.6, -20), 12.0, 1.4, "#E9B86A"], [Vector3(14, 3.4, -25.5), 8.0, 1.6, "#9FCFC0"]]:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.omni_range = l[1]
		o.light_energy = l[2]
		o.light_color = Color(l[3])
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 50.0
		o.distance_fade_length = 15.0
		add_child(o)
	for p in [Vector3(-11, y1 + 4.35, -20), Vector3(0, 4.35, -20), Vector3(8, y1 + 4.35, -20)]:
		var lb := Builder.new(0.0)
		lb.cyl(P.BRASS, Vector3.ZERO, 0.9, 0.9, 0.06, 20)
		lb.cyl(P.LAMP, Vector3(0, -0.05, 0), 0.8, 0.8, 0.04, 20)
		lb.cyl(P.BRASS, Vector3(0, -0.35, 0), 0.5, 0.5, 0.04, 16)
		var mi := MeshInstance3D.new()
		mi.mesh = Builder.cached("chandelier", func(): return lb.mesh())
		mi.position = p
		add_child(mi)

func _build_grounds() -> void:
	var b := Builder.new()
	# Courtyard paving and reflecting pool.
	b.box(P.CONCRETE_PALE, Vector3(0, 0.02, 11), Vector3(30, 0.04, 22), false)
	b.box(P.CONCRETE_PALE, Vector3(0, 0.2, 4.2), Vector3(16.4, 0.4, 0.4))
	b.box(P.CONCRETE_PALE, Vector3(0, 0.2, 17.8), Vector3(16.4, 0.4, 0.4))
	b.box(P.CONCRETE_PALE, Vector3(-8, 0.2, 11), Vector3(0.4, 0.4, 13.6))
	b.box(P.CONCRETE_PALE, Vector3(8, 0.2, 11), Vector3(0.4, 0.4, 13.6))
	b.box(P.WATER, Vector3(0, 0.22, 11), Vector3(15.6, 0.02, 13.2), false)
	b.kit.add_collider(Builder.xf(Vector3(0, 0.1, 11)), Vector3(15.6, 0.2, 13.2))
	# Garden pavilion: low plinth, steel columns, saucer roof.
	b.cyl(P.MARBLE, Vector3(-25, 0.04, 10.5), 6.0, 6.0, 0.08, 28, false)
	b.kit.add_collider(Builder.xf(Vector3(-25, 0.04, 10.5)), Vector3(8.4, 0.08, 8.4))
	for i in 8:
		var a := i * TAU / 8.0
		b.cyl(P.STEEL, Vector3(-25 + cos(a) * 5.2, 2.1, 10.5 + sin(a) * 5.2), 0.14, 0.14, 4.2, 8, true)
	b.cyl(P.CONCRETE_PALE, Vector3(-25, 4.35, 10.5), 7.2, 6.2, 0.5, 32)
	b.cyl(P.CONCRETE_PALE, Vector3(-25, 4.9, 10.5), 4.0, 1.5, 0.6, 24)
	b.cyl(P.WALNUT, Vector3(-25, 0.8, 10.5), 0.9, 0.9, 0.06, 16)
	b.cyl(P.CHROME, Vector3(-25, 0.4, 10.5), 0.1, 0.3, 0.8, 8, true)
	b.cyl(P.LAMP, Vector3(-25, 4.07, 10.5), 1.2, 1.2, 0.04, 16, false, false)
	# Gate booth: cassette-tech guard post.
	b.block(P.CONCRETE_DARK, Vector3(8.5, 0, 26), Vector3(3.4, 3.0, 3.0))
	b.box(P.CONCRETE_PALE, Vector3(8.5, 3.15, 26), Vector3(4.0, 0.3, 3.6), false)
	b.box(P.GLASS, Vector3(6.78, 1.8, 26), Vector3(0.05, 1.0, 2.4), false)
	b.box(P.CRT, Vector3(6.77, 1.2, 25.2), Vector3(0.02, 0.4, 0.5), false)
	# Barracks and motor court.
	b.block(P.CONCRETE_DARK, Vector3(30, 0, -36), Vector3(14, 6, 12))
	b.box(P.CHARCOAL, Vector3(30, 1.4, -29.95), Vector3(2.4, 2.8, 0.1), false)
	b.box(P.WINDOWS, Vector3(30, 4.2, -29.95), Vector3(11, 1.2, 0.1), false)
	b.box(P.ROAD, Vector3(28, 0.02, 10), Vector3(16, 0.04, 22), false)
	b.box(P.CONCRETE_PALE, Vector3(28, 3.2, 14), Vector3(10, 0.25, 7), false)
	for x in [23.5, 32.5]:
		b.cyl(P.STEEL, Vector3(x, 1.6, 17), 0.12, 0.12, 3.2, 8, true)
	# Service yard: crates, a generator with dials, cable drums.
	b.block(P.BEIGE, Vector3(-4, 0, -40), Vector3(3.0, 2.2, 1.6))
	for i in 3:
		b.cyl_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(-5 + i, 1.4, -39.18)), 0.25, 0.25, 0.04, 12)
	b.box(P.AMBER, Vector3(-2.9, 1.9, -39.18), Vector3(0.12, 0.12, 0.03), false)
	b.cyl(P.WALNUT, Vector3(4, 0.6, -40), 0.6, 0.6, 1.2, 12, true)
	b.commit(self, "Grounds")
	_occluder(Vector3(30, 3, -36), Vector3(13.6, 6, 11.6))
	# Crates as multimesh (with colliders).
	var crates := []
	var cc := Builder.new()
	for p in [Vector3(-12, 0, -38), Vector3(-13.2, 0, -38.3), Vector3(-12.5, 1.1, -38.1), Vector3(12, 0, -41), Vector3(13.2, 0, -40.6),
			Vector3(-34, 0, -20), Vector3(-34, 0, -18.8), Vector3(34, 0, 22), Vector3(22, 0, -26)]:
		crates.append(Transform3D(Basis(Vector3.UP, randf() * 0.3), p))
		cc.kit.add_collider(Builder.xf(p + Vector3(0, 0.55, 0)), Vector3(1.1, 1.1, 1.1))
	cc.commit(self, "CrateCol")
	Builder.scatter(self, Builder.crate(), crates, 90.0)
	# Trees and planters in the garden; lamps; banners.
	var trees := []
	for p in [Vector3(-33, 0, 20), Vector3(-30, 0, -2), Vector3(-34, 0, 4), Vector3(-17, 0, 22), Vector3(-34, 0, -30), Vector3(-26, 0, -26),
			Vector3(33, 0, -16), Vector3(20, 0, 24), Vector3(-15, 0, 4)]:
		trees.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(0.9, 1.3)), p))
	Builder.scatter(self, Builder.tree(), trees, 160.0)
	var lamps := []
	for p in [Vector3(-12, 0, 2), Vector3(12, 0, 2), Vector3(-12, 0, 20), Vector3(12, 0, 20), Vector3(-20, 0, -40), Vector3(20, 0, -40), Vector3(23, 0, 4)]:
		lamps.append(Transform3D(Basis(Vector3.UP, 0.0 if p.x < 0 else PI), p))
	Builder.scatter(self, Builder.lamp_post(), lamps, 120.0)
	var banners := []
	for x in [-20.0, -12.0, 12.0, 20.0]:
		banners.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(x, 0, 27)))
	Builder.scatter(self, Builder.banner_pole(), banners, 140.0, false)
	# Governor's car: a black Kestrel, drivable like the rest. It is driven
	# away on a script at 19:00 (frozen for the tween, physical again after).
	gov_car = spawn_car(Vector3(27, 0.8, 12), PI, Color("#141618"))
	for p in [Vector3(-25, 3.7, 10.5), Vector3(8.5, 2.6, 26)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = 9.0
		o.light_energy = 0.9
		o.light_color = Color("#E9B86A")
		o.distance_fade_enabled = true
		o.distance_fade_begin = 60.0
		o.distance_fade_length = 15.0
		add_child(o)

func _build_skyline() -> void:
	var b := Builder.new(0.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = 326
	for i in 26:
		var a := i * TAU / 26.0 + rng.randf_range(-0.08, 0.08)
		var r := rng.randf_range(190, 320)
		var c := Vector3(cos(a) * r, 0, sin(a) * r * 0.85)
		var h := rng.randf_range(30, 95)
		var w := rng.randf_range(14, 30)
		b.block(P.CONCRETE_DARK if i % 3 == 0 else P.CONCRETE, c, Vector3(w, h, w), false)
		b.box(P.WINDOWS, c + Vector3(0, h * 0.55, w * 0.5 + 0.06), Vector3(w * 0.8, h * 0.8, 0.1), false)
		b.box(P.WINDOWS, c + Vector3(w * 0.5 + 0.06, h * 0.55, 0), Vector3(0.1, h * 0.8, w * 0.8), false)
		if i % 4 == 0:
			b.cyl(P.STEEL, c + Vector3(0, h + 1.0, 0), w * 0.9, w * 0.9, 1.2, 24)
			b.cyl(P.CONCRETE_PALE, c + Vector3(0, h + 3.0, 0), w * 0.5, w * 0.2, 3.0, 16)
			b.cyl(P.STEEL, c + Vector3(0, h + 9.0, 0), 0.4, 0.1, 10.0, 6)
	var sky_mi := b.commit(self, "Skyline")
	sky_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Dirigible on a slow circuit.
	dirigible = Node3D.new()
	var dm := MeshInstance3D.new()
	dm.mesh = Builder.dirigible()
	dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dirigible.add_child(dm)
	add_child(dirigible)

func _build_detail() -> void:
	var b := Builder.new(0.0)
	# Road paint: lane dashes, edge lines, crossings. Concrete-pale so snow covers it.
	for x in [-5.0, 5.0]:
		var z := 33.0
		while z < 168.0:
			if z < 79.0 or z > 111.0 or absf(x) > 3.0:
				b.box(P.CONCRETE_PALE, Vector3(x, 0.024, z + 1.5), Vector3(0.14, 0.008, 3.0), false)
			z += 7.0
	for x in [-9.3, 9.3]:
		b.box(P.CONCRETE_PALE, Vector3(x, 0.024, 107.0), Vector3(0.12, 0.008, 118.0), false)
	for i in 9:
		b.box(P.CONCRETE_PALE, Vector3(-8.0 + i * 2.0, 0.024, 48.5), Vector3(0.9, 0.008, 3.2), false)
	var xr := -64.0
	while xr < 64.0:
		if absf(xr) > 10.0:
			b.box(P.CONCRETE_PALE, Vector3(xr + 1.5, 0.024, 39.0), Vector3(3.0, 0.008, 0.14), false)
		xr += 7.0
	# Facade rhythm: floor bands across every tower face.
	var heights := [18.0, 26.0, 14.0, 32.0, 20.0]
	var tanks := []
	var masts := []
	var acs := []
	for side in [-1, 1]:
		for i in 4:
			var z := 58.0 + i * 30.0
			var h: float = heights[(i + (1 if side > 0 else 0)) % heights.size()]
			var face: float = side * 19.0 - side * 0.25
			var y := 8.6
			while y < h - 1.0:
				b.box(P.CONCRETE_PALE, Vector3(face, y, z), Vector3(0.5, 0.16, 20.0), false)
				y += 3.6
			tanks.append(Transform3D(Basis(Vector3.UP, i * 0.7), Vector3(side * 30.0 + 3.5, h + 0.8, z - 4.0)))
			masts.append(Transform3D(Basis(Vector3.UP, i * 1.3), Vector3(side * 30.0 - 4.0, h + 0.8, z + 5.0)))
			var rng := RandomNumberGenerator.new()
			rng.seed = i * 17 + (side + 1) * 5
			for k in 5:
				var ay := rng.randf_range(7.0, h - 2.0)
				ay = 8.6 + floor((ay - 8.6) / 3.6) * 3.6 + 0.55
				acs.append(Transform3D(Basis(Vector3.UP, -PI / 2 * side), Vector3(face - side * 0.55, ay, z + rng.randf_range(-8.5, 8.5))))
	# Barracks and booth roofs.
	tanks.append(Transform3D(Basis(), Vector3(33, 6.0, -37)))
	masts.append(Transform3D(Basis(), Vector3(26, 6.0, -33)))
	masts.append(Transform3D(Basis(), Vector3(9.5, 3.3, 26.5)))
	masts.append(Transform3D(Basis().scaled(Vector3(1.4, 1.6, 1.4)), Vector3(-6, 10.1, -26)))
	b.commit(self, "Detail", 260.0)
	Builder.scatter(self, Builder.water_tank(), tanks, 300.0)
	Builder.scatter(self, Builder.antenna(), masts, 300.0, false)
	Builder.scatter(self, Builder.ac_unit(), acs, 120.0, false)
	# Street furniture.
	var benches := []
	var bins := []
	var booths := []
	var bollards := []
	var kiosks := []
	for side in [-1, 1]:
		for i in 5:
			var z := 56.0 + i * 26.0
			benches.append(Transform3D(Basis(Vector3.UP, -PI / 2 * side), Vector3(side * 15.3, 0.15, z)))
			bins.append(Transform3D(Basis(), Vector3(side * 15.0, 0.15, z + 1.7)))
		for z in [78.0, 138.0]:
			booths.append(Transform3D(Basis(Vector3.UP, PI / 2 * side), Vector3(side * 15.2, 0.15, z + (4.0 if side > 0 else 0.0))))
		kiosks.append(Transform3D(Basis(Vector3.UP, PI / 2 * side), Vector3(side * 14.4, 0.15, 104.0 + side * 18.0)))
		for k in 5:
			bollards.append(Transform3D(Basis(), Vector3(side * (10.6 + k * 1.2), 0.15, 46.0)))
	for k in 7:
		bollards.append(Transform3D(Basis(), Vector3(-6.0 + k * 2.0, 0.0, 33.6)))
	booths.append(Transform3D(Basis(Vector3.UP, PI), Vector3(13.0, 0.0, 34.5)))
	Builder.scatter(self, Builder.bench(), benches, 90.0)
	Builder.scatter(self, Builder.bin(), bins, 80.0)
	Builder.scatter(self, Builder.phone_booth(), booths, 110.0)
	Builder.scatter(self, Builder.bollard(), bollards, 80.0)
	Builder.scatter(self, Builder.kiosk(), kiosks, 140.0)
	var col := Builder.new()
	for t in booths:
		col.kit.add_collider(Transform3D(t.basis, t.origin + Vector3(0, 1.25, -0.1)), Vector3(1.1, 2.5, 0.9))
	for t in kiosks:
		col.kit.add_collider(Transform3D(t.basis, t.origin + Vector3(0, 1.1, 0)), Vector3(2.2, 2.2, 1.6))
	for t in bollards:
		col.kit.add_collider(Transform3D(t.basis, t.origin + Vector3(0, 0.45, 0)), Vector3(0.3, 0.9, 0.3))
	for t in benches:
		col.kit.add_collider(Transform3D(t.basis, t.origin + Vector3(0, 0.3, 0)), Vector3(1.9, 0.6, 0.5))
	col.commit(self, "DetailCol")
	# Parked cars along both curbs: every one a drivable Kestrel 80, in a few
	# period colours. Idle cars sleep in the physics engine, so they are cheap.
	var paints := [Color("#2B2F31"), Color("#2F6E73"), Color("#C9B88F"), Color("#24414F"), Color("#A2512F"), Color("#8E8A82"), Color("#6E1F24")]
	var spots := [[-8.2, 60.0, 0.0], [-8.2, 74.0, 0.0], [-8.2, 128.0, 0.0], [8.2, 66.0, PI], [8.2, 98.0, PI], [8.2, 146.0, PI], [-8.2, 156.0, 0.0]]
	for i in spots.size():
		spawn_car(Vector3(spots[i][0], 0.8, spots[i][1]), spots[i][2], paints[i % paints.size()])
	# Compound: hedges around the court, wire on the walls, camera eyes.
	var hedges := []
	for z in [6.0, 10.5, 15.0]:
		for x in [-13.0, 13.0]:
			hedges.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(x, 0, z)))
	for x in [-20.0, -16.0, 16.0, 20.0]:
		hedges.append(Transform3D(Basis(), Vector3(x, 0, 2.0)))
	Builder.scatter(self, Builder.hedge(), hedges, 110.0)
	var wire := []
	var wx := -38.0
	while wx < 39.0:
		if absf(wx) > 7.0:
			wire.append(Transform3D(Basis(), Vector3(wx, 4.5, 30.0)))
		wire.append(Transform3D(Basis(), Vector3(wx, 4.5, -45.0)))
		wx += 4.0
	var wz := -43.0
	while wz < 29.0:
		wire.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-40.0, 4.5, wz)))
		if wz < -39.0 or wz > -31.0:
			wire.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(40.0, 4.5, wz)))
		wz += 4.0
	Builder.scatter(self, Builder.wire_coil(), wire, 120.0, false)
	var cams := [
		Transform3D(Basis(Vector3.UP, 0.4), Vector3(-4.5, 6.0, 31.2)),
		Transform3D(Basis(Vector3.UP, -0.4), Vector3(4.5, 6.0, 31.2)),
		Transform3D(Basis(Vector3.UP, PI * 0.75), Vector3(-17.7, 4.0, -8.0)),
		Transform3D(Basis(Vector3.UP, -PI * 0.75), Vector3(17.7, 4.0, -8.0)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 3.8, -30.4)),
		Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(17.9, 3.6, -25.0)),
		Transform3D(Basis(Vector3.UP, PI / 2 + 0.5), Vector3(-39.3, 4.0, -38.0)),
		Transform3D(Basis(Vector3.UP, -PI / 2 - 0.5), Vector3(39.3, 4.0, 22.0)),
	]
	Builder.scatter(self, Builder.wall_camera(), cams, 70.0, false)
	# A reflection probe over the boulevard and one over the court, so wet
	# stone mirrors the lit windows (captured once; free at runtime).
	for pr in [[Vector3(0, 6, 100), Vector3(40, 30, 140)], [Vector3(0, 4, 8), Vector3(70, 16, 50)]]:
		var probe := ReflectionProbe.new()
		probe.position = pr[0]
		probe.size = pr[1]
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.box_projection = true
		probe.max_distance = 220.0
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		add_child(probe)

# ============================================================== navigation

func _n(id: String, p: Vector3) -> void:
	nodes[id] = Game.sim.nav_add(p)
	locations[id] = p

func _l(a: String, b: String) -> void:
	Game.sim.nav_link(nodes[a], nodes[b])

func _build_nav() -> void:
	Game.sim.nav_clear()
	var y1 := 4.8
	var pts := {
		"o_s1": Vector3(13, 0, 132), "o_s2": Vector3(13, 0, 100), "o_s3": Vector3(13, 0, 70), "o_s4": Vector3(13, 0, 48),
		"o_w1": Vector3(-13, 0, 132), "o_w2": Vector3(-13, 0, 100), "o_w3": Vector3(-13, 0, 70), "o_w4": Vector3(-13, 0, 48),
		"o_gate": Vector3(0, 0, 38), "gate_in": Vector3(0, 0, 26), "gate_post": Vector3(4, 0, 24.5),
		"court_s": Vector3(0, 0, 21.5), "cs_w": Vector3(-11, 0, 21.5), "cs_e": Vector3(11, 0, 21.5),
		"pool_w": Vector3(-11, 0, 11), "pool_e": Vector3(11, 0, 11), "cn_w": Vector3(-11, 0, 1.5), "cn_e": Vector3(11, 0, 1.5),
		"court_n": Vector3(0, 0, 1.5), "portico": Vector3(0, 0, -4.5), "lobby_s": Vector3(0, 0, -10),
		"lobby_w": Vector3(-5, 0, -10.5), "lobby_e": Vector3(5, 0, -10.5), "stair_foot": Vector3(0, 0, -12.6),
		"stair_top": Vector3(0, y1, -20.0), "up_land": Vector3(0, y1, -21.8), "up_ne": Vector3(4, y1, -21.8),
		"office_door": Vector3(-2, y1, -21.6), "office_in": Vector3(-5, y1, -21.6), "desk": Vector3(-12, y1, -23.6),
		"office_s": Vector3(-7.2, y1, -11), "office_tdoor": Vector3(-7.2, y1, -8.0), "terrace_w": Vector3(-7.2, y1, -5),
		"terrace_c": Vector3(0, y1, -5), "terrace_he": Vector3(7.2, y1, -5), "terrace_tea": Vector3(6, y1, -3.2),
		"terrace_e": Vector3(13.5, y1, -5), "ext_top": Vector3(14, y1, -2.2), "ext_bottom": Vector3(14, 0, 5.0),
		"hall_c": Vector3(8, y1, -15), "hall_tdoor": Vector3(7.2, y1, -8.0),
		"w_door": Vector3(-8, 0, -19.2), "w_wing": Vector3(-13, 0, -19), "svc_in": Vector3(-10.3, 0, -28.2), "svc_out": Vector3(-10.3, 0, -32),
		"e_door": Vector3(8, 0, -14.2), "e_hall": Vector3(13, 0, -14), "sr_door": Vector3(12.8, 0, -21), "strongroom": Vector3(14.5, 0, -26),
		"yard_w": Vector3(-25, 0, -38), "yard_c": Vector3(0, 0, -36), "yard_e": Vector3(22, 0, -32),
		"side_w": Vector3(-25, 0, -15), "side_e": Vector3(25, 0, -15), "garden": Vector3(-25, 0, 0),
		"pavilion": Vector3(-25, 0, 8.6), "pavilion_c": Vector3(-25, 0, 12.4), "sw": Vector3(-28, 0, 24), "se": Vector3(28, 0, 24),
		"culvert_in": Vector3(-37, 0, -5.3), "culvert_out": Vector3(-43, 0, -5.3),
		"motor": Vector3(24, 0, 4), "motor_court": Vector3(24.6, 0, 12),
	}
	for k in pts:
		_n(k, pts[k])
	for pair in [["o_s1", "o_s2"], ["o_s2", "o_s3"], ["o_s3", "o_s4"], ["o_w1", "o_w2"], ["o_w2", "o_w3"], ["o_w3", "o_w4"],
			["o_s4", "o_gate"], ["o_w4", "o_gate"], ["o_s2", "o_w2"], ["o_s3", "o_w3"], ["o_gate", "gate_in"],
			["gate_in", "gate_post"], ["gate_in", "court_s"], ["court_s", "cs_w"], ["court_s", "cs_e"],
			["cs_w", "pool_w"], ["cs_e", "pool_e"], ["pool_w", "cn_w"], ["pool_e", "cn_e"], ["cn_w", "court_n"], ["cn_e", "court_n"],
			["court_n", "portico"], ["portico", "lobby_s"], ["lobby_s", "lobby_w"], ["lobby_s", "lobby_e"], ["lobby_s", "stair_foot"],
			["stair_foot", "stair_top"], ["stair_top", "up_land"], ["up_land", "office_door"], ["office_door", "office_in"],
			["office_in", "desk"], ["office_in", "office_s"], ["office_s", "office_tdoor"], ["office_tdoor", "terrace_w"],
			["terrace_w", "terrace_c"], ["terrace_c", "terrace_he"], ["terrace_he", "terrace_tea"], ["terrace_he", "terrace_e"],
			["terrace_e", "ext_top"], ["ext_top", "ext_bottom"], ["ext_bottom", "pool_e"], ["ext_bottom", "cn_e"],
			["up_land", "up_ne"], ["up_ne", "hall_c"], ["hall_c", "hall_tdoor"], ["hall_tdoor", "terrace_he"],
			["lobby_w", "w_door"], ["w_door", "w_wing"], ["w_wing", "svc_in"], ["svc_in", "svc_out"], ["svc_out", "yard_w"], ["svc_out", "yard_c"],
			["yard_w", "yard_c"], ["yard_c", "yard_e"], ["yard_w", "side_w"], ["yard_e", "side_e"],
			["lobby_e", "e_door"], ["e_door", "e_hall"], ["e_hall", "sr_door"], ["sr_door", "strongroom"],
			["side_w", "garden"], ["garden", "pavilion"], ["pavilion", "pavilion_c"], ["garden", "culvert_in"], ["culvert_in", "culvert_out"],
			["pavilion", "cs_w"], ["garden", "cn_w"], ["sw", "cs_w"], ["sw", "pavilion"],
			["side_e", "motor"], ["motor", "cn_e"], ["motor", "motor_court"], ["motor", "se"], ["se", "cs_e"], ["side_w", "cn_w"], ["side_e", "cn_e"]]:
		_l(pair[0], pair[1])
	# Location facings for the routine (yaw in radians, 0 faces -Z).
	locations["desk_face"] = PI
	locations["pavilion_face"] = PI
	locations["terrace_tea_face"] = PI
	locations["gate_post_face"] = 0.0
	locations["motor_court_face"] = -PI / 2
	locations["strongroom_face"] = 0.0

# ============================================================== NPCs

func _spawn_npc(kind: String, at: String, patrol: Array = [], tint := 0) -> Npc:
	var n := Builder.make_npc(kind, locations[at] + Vector3(0, 0.1, 0), tint)
	add_child(n)
	n.set_player(player)
	n.health = float(_info.get("guard_health", 100.0)) if kind == "guard" else 60.0
	if not patrol.is_empty():
		var pv := PackedVector3Array()
		for p in patrol:
			pv.append(locations[p])
		n.set_patrol(pv)
	n.died.connect(func(silent: bool): _on_npc_died(n, silent))
	if kind == "guard":
		guards.append(n)
		n.alarm_call.connect(func(): _on_alarm_call(n))
		n.body_discovered.connect(func(_at): _on_body_found(n))
		n.shot_at_player.connect(_on_shot_at_player)
		n.spotted_player.connect(func(): Game.play_3d("beep_low", n.global_position + Vector3(0, 1.7, 0), 0, 6.0))
	return n

func _spawn_npcs() -> void:
	_spawn_npc("guard", "gate_post", ["gate_post", "gate_in"])
	_spawn_npc("guard", "court_s", ["cs_w", "pool_w", "cn_w", "court_n", "cn_e", "pool_e", "cs_e", "court_s"])
	_spawn_npc("guard", "garden", ["garden", "pavilion", "sw", "pavilion", "garden", "side_w", "culvert_in"])
	_spawn_npc("guard", "lobby_w", ["lobby_w", "lobby_s", "lobby_e", "stair_foot"], 1)
	_spawn_npc("guard", "up_land", ["up_land", "up_ne", "hall_c", "hall_tdoor", "terrace_he", "terrace_c", "terrace_he", "hall_tdoor", "hall_c"])
	_spawn_npc("guard", "e_hall", ["e_hall", "sr_door"], 1)
	_spawn_npc("guard", "yard_c", ["yard_w", "yard_c", "yard_e", "yard_c"])
	_spawn_npc("guard", "motor", ["motor", "se", "motor", "side_e"])
	var extra := int(_info.get("extra_guards", 0))
	var extra_posts := [["terrace_c", ["terrace_c", "terrace_w"]], ["office_in", ["office_in", "office_s"]], ["side_w", ["side_w", "yard_w"]], ["pool_e", ["pool_e", "motor"]]]
	for i in mini(extra, extra_posts.size()):
		_spawn_npc("guard", extra_posts[i][0], extra_posts[i][1])
	# Civilians on the boulevard.
	var civ := [["o_s1", "o_s3"], ["o_s2", "o_s4"], ["o_w1", "o_w3"], ["o_w2", "o_w4"], ["o_s3", "o_s1"], ["o_w3", "o_w1"], ["o_s4", "o_s2"], ["o_w4", "o_w2"]]
	for i in civ.size():
		var c := _spawn_npc("civilian", civ[i][0], civ[i], i)
		c.walk_speed = randf_range(1.1, 1.6)
		c.patrol_wait = randf_range(1.0, 6.0)
	# The governor and his courier.
	gov = _spawn_npc("governor", "desk")
	gov.health = float(_info.get("governor_health", 70.0))
	gov.walk_speed = 1.2
	gov.run_speed = 3.6
	gov.reached_goal.connect(_on_gov_arrived)
	gov.alarm_call.connect(func(): _on_alarm_call(gov))
	gov.body_discovered.connect(func(_at): _on_body_found(gov))
	courier = _spawn_npc("courier", "o_s3")
	courier.walk_speed = 1.5

# ============================================================== interactables

func _gadget_of(kind: String) -> Dictionary:
	for g in Game.mstate().get("gadgets", []):
		if g.kind == kind:
			return g
	return {}

func _build_interactables() -> void:
	var y1 := 4.8
	# Tea trolley on the terrace.
	var tb := Builder.new(0.2)
	tb.box(P.BRASS, Vector3(0, 0.75, 0), Vector3(0.9, 0.04, 0.5), false)
	tb.box(P.BRASS, Vector3(0, 0.35, 0), Vector3(0.9, 0.04, 0.5), false)
	for x in [-0.42, 0.42]:
		for z in [-0.22, 0.22]:
			tb.cyl(P.CHROME, Vector3(x, 0.4, z), 0.02, 0.02, 0.8, 6)
	tb.cyl(P.IVORY, Vector3(-0.15, 0.88, 0), 0.1, 0.07, 0.22, 10)
	tb.cyl(P.IVORY, Vector3(0.2, 0.8, 0.1), 0.05, 0.04, 0.06, 8)
	tb.cyl(P.IVORY, Vector3(0.2, 0.8, -0.1), 0.05, 0.04, 0.06, 8)
	var tm := MeshInstance3D.new()
	tm.mesh = tb.mesh()
	tm.position = Vector3(7.4, y1, -3.9)
	add_child(tm)
	Interactable.make(self, Vector3(7.4, y1 + 0.8, -3.9), Vector3(1.0, 0.6, 0.7),
		func():
			var st := Game.mstate()
			if st.get("tea_poisoned", false):
				return "Tea service (dosed)"
			if _gadget_of("poison").get("count", 0) > 0:
				return "E  Dose the tea  [Datura Ampoule]"
			return "Tea service",
		func():
			var g := _gadget_of("poison")
			if g.is_empty():
				return
			var err: String = Game.sim.poison_tea(g.id)
			if err != "":
				hud.message(err)
			else:
				Game.play_3d("pour", Vector3(7.4, y1 + 1, -3.9), -6)
				rig.refresh_gadgets(),
		"poison")
	# Dispatch tray on the desk.
	Interactable.make(self, Vector3(-12.7, y1 + 0.9, -21.9), Vector3(0.6, 0.3, 0.5),
		func():
			var st := Game.mstate()
			if st.get("forgery_planted", false):
				return "Dispatch tray (forgery planted)"
			if _gadget_of("forgery").get("count", 0) > 0:
				return "E  Plant forged dispatch"
			return "Dispatch tray",
		func():
			var g := _gadget_of("forgery")
			if g.is_empty():
				return
			var err: String = Game.sim.plant_forgery(g.id)
			hud.message(err if err != "" else "Dispatch planted, sealed with the ram's head.")
			rig.refresh_gadgets(),
		"forgery")
	# Office telex.
	Interactable.make(self, Vector3(-16.4, y1 + 1.0, -24.8), Vector3(1.0, 0.7, 0.9),
		func(): return "E  Telex the capital",
		func():
			var err: String = Game.sim.send_telex()
			if err != "":
				hud.message(err)
			else:
				Game.play_3d("telex", Vector3(-16.4, y1 + 1, -25), 0)
				_arrest_timer = 2.0)
	# Desk terminal: reads his appointments (intel without listening).
	Interactable.make(self, Vector3(-11.2, y1 + 1.05, -22.2), Vector3(0.6, 0.5, 0.5),
		func(): return "E  Read the appointment terminal",
		func():
			Game.play_3d("beep", Vector3(-11.2, y1 + 1.05, -22.2), -6)
			for id in ["w3", "m4"]:
				Game.sim.hear_line(id)
			hud.message("Terminal: 18:20 TEA (TERRACE). 19:00 CAR (MOTOR COURT)."))

func _build_audio() -> void:
	ambience = AudioStreamPlayer.new()
	ambience.stream = Game.sfx["ambience"]
	ambience.volume_db = -10
	add_child(ambience)
	ambience.play()
	alarm_player = AudioStreamPlayer3D.new()
	alarm_player.stream = Game.sfx["alarm"]
	alarm_player.unit_size = 30.0
	alarm_player.max_distance = 220.0
	alarm_player.position = Vector3(0, 12, -10)
	add_child(alarm_player)

# ============================================================== mission flow

func _process(dt: float) -> void:
	super(dt)
	if get_tree().paused:
		return
	Game.sim.mission_tick(dt)
	for e in Game.sim.mission_events():
		_on_event(e)
	var st := Game.mstate()
	if st.is_empty():
		return
	var t := _dusk_amount(st)
	if Game.debug.has("dusk"):
		t = float(Game.debug.dusk)
	_apply_dusk(t)
	_update_zones(t)
	# Tea.
	if _tea_timer > 0.0:
		_tea_timer -= dt
		if _tea_timer <= 0.0:
			Game.play_3d("pour", gov.global_position + Vector3(0, 1, 0), -8)
			Game.sim.governor_drinks_tea()
	# Arrest after the telex.
	if _arrest_timer > 0.0:
		_arrest_timer -= dt
		if _arrest_timer <= 0.0 and gov.alive:
			hud.message("Two royal inspectors arrive and walk the governor out in silence.")
			gov.go_to(locations[_arrest_exit()], false, NAN)
	# Exfiltration.
	if st.removed != "" and not _finished:
		_check_exfil()
	# Speaking indicator: governor's lines.
	if beacons.size() > 0:
		var on: bool = st.alarm and fmod(Time.get_ticks_msec() * 0.003, 1.0) < 0.5
		for bm in beacons:
			bm.visible = on or not st.alarm
	if dirigible:
		dirigible.position = Vector3(cos(Time.get_ticks_msec() * 0.00002) * 160.0, 85.0, sin(Time.get_ticks_msec() * 0.00002) * 120.0 - 20.0)
		dirigible.rotation.y = -Time.get_ticks_msec() * 0.00002

# Level hooks: another mission's level overrides these.

func _dusk_amount(st: Dictionary) -> float:
	return clampf((float(st.minute) - 1070.0) / 75.0, 0.0, 1.0)

## Restricted zones, exposure, and rain indoors.
func _update_zones(t: float) -> void:
	# Restricted zone by position (works on foot and in cars).
	player.restricted = 1 if COMPOUND.has_point(player.global_position + Vector3(0, 0.5, 0)) else 0
	var indoor := absf(player.global_position.x) < 18 and player.global_position.z > -30 and player.global_position.z < -8
	player.exposure = 0.85 if indoor else lerpf(1.0, 0.55, t)
	if weather:
		var cam := get_viewport().get_camera_3d()
		var cp := cam.global_position if cam else player.global_position
		var inside := absf(cp.x) < 18.5 and cp.z > -30.5 and cp.z < -7.5 and cp.y < 9.6
		weather.indoor = inside
		rain.emitting = not inside and weather.mode != "clear"

func _check_exfil() -> void:
	var p := player.global_position
	if p.z > 100.0 or p.length() > 120.0:
		Game.sim.player_exfiltrated()

## Where the king's inspectors walk the arrested governor to.
func _arrest_exit() -> String:
	return "o_gate"

## The centre of the noise civilians run from when the alarm sounds.
func _alarm_origin() -> Vector3:
	return Vector3(0, 0, 30)

func _on_activity(e: Dictionary) -> void:
	if gov.alive:
		_route_to(gov, e.location)
	if e.activity == "meeting":
		_route_to(courier, "pavilion_c")
	elif courier.alive and gov_activity == "tea":
		_route_to(courier, "o_s2")

## The governor reached his car at the end of the routine.
func _drive_away() -> void:
	var gc := gov_car as ArcadeCar
	if driving and car == gc:
		return
	var y := gc.position.y
	gc.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	gc.freeze = true
	_gov_tw = create_tween()
	_gov_tw.tween_property(gov, "position", gc.position, 0.6)
	_gov_tw.tween_callback(func(): gov.visible = false)
	_gov_tw.tween_property(gc, "position", Vector3(0, y, 12), 3.0)
	_gov_tw.parallel().tween_property(gc, "rotation:y", PI * 0.5, 1.2)
	_gov_tw.tween_property(gc, "rotation:y", PI, 0.8)
	_gov_tw.parallel().tween_property(gc, "position", Vector3(0, y, 60), 4.0)
	_gov_tw.tween_callback(func(): gc.freeze = false)

func _apply_dusk(t: float) -> void:
	P.set_dusk(t)
	sun.light_energy = lerpf(0.72, 0.18, t)
	sun.light_color = Color("#EFCFA8").lerp(Color("#E09A60"), t)
	sun.rotation_degrees.x = lerpf(-32.0, -9.0, t)
	env.ambient_light_energy = lerpf(0.58, 0.36, t)
	sky_mat.sky_top_color = Color("#3E4D55").lerp(Color("#172732"), t)
	sky_mat.sky_horizon_color = Color("#7A8A91").lerp(Color("#475A64"), t)
	sky_mat.ground_horizon_color = Color("#63737A").lerp(Color("#33434C"), t)
	base_fog_color = Color("#66767E").lerp(Color("#293B46"), t)

func _route_to(n: Npc, loc: String, run := false) -> void:
	if not locations.has(loc):
		return
	var face: float = locations.get(loc + "_face", NAN)
	n.go_to(locations[loc], run, face)

func _on_event(e: Dictionary) -> void:
	match e.type:
		"activity":
			gov_activity = e.activity
			_on_activity(e)
		"line":
			_deliver_line(e)
		"intel":
			hud.message("INTEL: " + e.title)
			Game.play_2d("beep", -6, 1.2)
		"alarm":
			alarm_player.play()
			Game.sim.market_event("alarm", 1.0)
			for g in guards:
				g.alert(player.global_position, false)
			if gov.alive:
				_route_to(gov, "strongroom", true)
			for n in get_tree().get_nodes_in_group("npc"):
				if n.role == "civilian":
					n.hear_noise(_alarm_origin(), 200.0)
		"target_dying":
			pass
		"target_down":
			if e.method == "poison" and gov.alive:
				gov.take_down()
			Game.play_2d("beep_low", -2, 0.8)
		"message":
			hud.message(e.text)
		"finished":
			_on_finished(e.method)

func _speaker_node(name: String) -> Npc:
	match name:
		"Governor":
			return gov
		"Courier":
			return courier
	var best: Npc = null
	var bd := 1e9
	for g in guards:
		if g.alive:
			var d := g.global_position.distance_to(gov.global_position)
			if d < bd:
				bd = d
				best = g
	return best

func _deliver_line(e: Dictionary) -> void:
	var sp := _speaker_node(e.speaker)
	if sp == null or not sp.alive:
		return
	var pos := sp.global_position + Vector3(0, 1.6, 0)
	var ppos := player.get_eye_position()
	var heard := pos.distance_to(ppos) < 9.0 and absf(pos.y - ppos.y) < 3.5
	var taped := false
	if not heard:
		for bug in get_tree().get_nodes_in_group("tape_bug"):
			if bug.global_position.distance_to(pos) < float(bug.get_meta("radius", 11.0)):
				taped = true
				break
	if heard or taped:
		hud.subtitle(e.speaker, e.text, taped and not heard)
		Game.sim.hear_line(e.id)

func _on_gov_arrived() -> void:
	if not gov.alive:
		return
	var st := Game.mstate()
	if st.get("target", "") == "arrested":
		gov.queue_free.call_deferred()
		return
	if st.alarm:
		return
	match gov_activity:
		"tea":
			_tea_timer = 6.0
		"depart":
			Game.sim.governor_escaped()
			_drive_away()

func enter_car(c: ArcadeCar) -> void:
	if c == gov_car and _gov_tw and _gov_tw.is_running():
		_gov_tw.kill()
	super(c)

func _on_npc_died(n: Npc, silent: bool) -> void:
	if n == gov:
		Game.sim.governor_killed()
	else:
		Game.sim.npc_killed()
	if not silent:
		Game.play_3d("thud", n.global_position, -4)
	spawn_ragdoll(n)

func on_npc_killed(_n: Npc) -> void:
	pass  # Kills are reported through Npc.died.

func _on_alarm_call(n: Npc) -> void:
	if n.alive and not Game.sim.is_alarm():
		Game.sim.raise_alarm()

func _on_body_found(n: Npc) -> void:
	hud.message("A body has been found.")
	Game.sim.body_found()
	n.alert(player.global_position, false)

func _on_shot_at_player(from: Vector3, to: Vector3, hit: bool, dmg: float) -> void:
	rig.incoming_shot(from, to, hit, dmg)
	if hit:
		Game.sim.damage_player(dmg)
	for g in guards:
		if g.global_position.distance_to(from) < 40.0:
			g.alert(player.global_position, true)

func abandon() -> void:
	Game.sim.abort_mission()

func _on_finished(method: String) -> void:
	if _finished:
		return
	_finished = true
	alarm_player.stop()
	Game.sim.market_event("method:" + method, 1.0)
	var titles := {"quiet_kill": "REMOVED QUIETLY", "loud_kill": "REMOVED UNDER FIRE", "poison": "REMOVED BY POISON",
		"frame": "REMOVED BY THE KING'S OWN HAND", "failed": "THE GOVERNOR SURVIVES THE NIGHT"}
	var report := ""
	var buttons := []
	# Read the state first: applying the result closes the mission.
	var st := Game.mstate()
	var dispatch: String = Game.sim.mission_dispatch(method)
	if Game.mode == "campaign" and Game.sim.has_campaign():
		report = Game.sim.apply_mission_result(method)
		Game.save_campaign()
		buttons.append(["Return to the war room", func(): Game.goto("res://scenes/war_room.tscn")])
	else:
		report = "Free play: the campaign is not affected."
		buttons.append(["Replay", func():
			if replay_gov != "":
				Game.sim.start_mission_for(replay_gov)
			else:
				Game.sim.start_mission()
			Game.goto(scene_file_path)])
		buttons.append(["Main menu", func(): Game.goto("res://scenes/main_menu.tscn")])
	var t := "[b][color=#D9962B]%s[/color][/b]\n\n" % titles.get(method, method)
	if dispatch != "":
		t += "[i]%s[/i]\n\n" % dispatch
	t += "%s\n\n" % report
	t += "[color=#7FCF8A]Clock %s   Intel %d/%d   Kills %d   Alarm %s[/color]\n" % [st.get("clock", "--"), st.get("intel", []).size(), int(st.get("intel_total", 0)), int(st.get("kills", 0)), "YES" if st.get("alarm", false) else "no"]
	if method == "loud_kill":
		t += "\nA loud killing frightens the governors into the king's arms. Quiet methods cut deeper."
	elif method == "frame":
		t += "\nThe king did the work himself. Nothing turns governors against a throne faster."
	await get_tree().create_timer(1.2).timeout
	player.set_active(false)
	if driving:
		car.set_driver(false)
	if riding:
		bike.set_driver(false)
	hud.show_debrief(t, buttons)
