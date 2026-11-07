extends LevelBase
## Milestone 1 "feel test": a flat track with ramps, curbs, slopes and a
## tight slalom for the car, plus a test room for on-foot movement (steps,
## stair rises, mantle ledges, crouch tunnel, slide lane, slopes, gaps).
## F1 opens the tuning panel.

func build_world() -> void:
	Palette.set_dusk(0.2)
	var b := Builder.new()
	# Ground.
	b.box(P.CONCRETE_PALE, Vector3(0, -0.5, 0), Vector3(420, 1, 420))
	b.box(P.ROAD, Vector3(0, 0.005, 0), Vector3(16, 0.01, 300), false)
	b.box(P.ROAD, Vector3(0, 0.005, -150), Vector3(220, 0.01, 16), false)
	b.box(P.ROAD, Vector3(0, 0.005, 150), Vector3(220, 0.01, 16), false)
	b.box(P.ROAD, Vector3(-110, 0.005, 0), Vector3(16, 0.01, 300), false)
	b.box(P.ROAD, Vector3(110, 0.005, 0), Vector3(16, 0.01, 300), false)
	# Ramps of increasing height down the main straight.
	b.ramp(P.CONCRETE, Vector3(0, 0, -40), Vector3(8, 1.0, 8), 0.0)
	b.ramp(P.CONCRETE, Vector3(0, 0, -70), Vector3(8, 2.2, 10), 0.0)
	b.ramp(P.CONCRETE, Vector3(0, 0, -105), Vector3(8, 1.6, 6), 0.0)
	b.ramp(P.CONCRETE, Vector3(0, 0, -96), Vector3(8, 1.6, 6), PI)
	# Curbs: rumble strips across the back straight.
	for i in 14:
		b.box(P.CONCRETE_DARK if i % 2 == 0 else P.CONCRETE_PALE, Vector3(-110, 0.06, -40 + i * 1.2), Vector3(16, 0.12, 0.6))
	for i in 6:
		b.box(P.CONCRETE_DARK, Vector3(110, 0.1, -60 + i * 6), Vector3(16, 0.2, 0.5))
	# Banked slope and a hill.
	b.ramp(P.CONCRETE, Vector3(60, 0, 150), Vector3(14, 3.0, 30), -PI / 2)
	b.box(P.CONCRETE, Vector3(85, 1.5, 150), Vector3(20, 3.0, 14))
	b.ramp(P.CONCRETE, Vector3(110, 0, 150), Vector3(14, 3.0, 30), PI / 2)
	b.commit(self, "Track")

	# Slalom: cones on the front straight.
	var cones := []
	var cb := Builder.new()
	for i in 12:
		var z := 30.0 + i * 9.0
		var x := 3.2 if i % 2 == 0 else -3.2
		cones.append(Transform3D(Basis(), Vector3(x, 0, z)))
		cb.kit.add_collider(Builder.xf(Vector3(x, 0.4, z)), Vector3(0.4, 0.8, 0.4))
	cb.commit(self, "ConeColliders")
	Builder.scatter(self, Builder.cone(), cones, 200.0, false)

	_build_test_room()
	_build_markers()
	car = spawn_car(Vector3(0, 1.0, 14), 0.0)

func _build_test_room() -> void:
	var b := Builder.new()
	var o := Vector3(-50, 0, 0)
	b.box(P.CONCRETE_DARK, o + Vector3(0, 0.05, 0), Vector3(40, 0.1, 50))
	# Step-up blocks: 0.20, 0.30, 0.42 (default limit), 0.55 (too high: mantle).
	var hs := [0.2, 0.3, 0.42, 0.55]
	for i in hs.size():
		b.block(P.CONCRETE_PALE, o + Vector3(-15 + i * 4, 0.1, -18), Vector3(3, hs[i], 3))
	# Stairs with different rises.
	b.stairs(P.CONCRETE, o + Vector3(-15, 0.1, -10), 3, 0.18, 0.32, 10, 0.0)
	b.stairs(P.CONCRETE, o + Vector3(-11, 0.1, -10), 3, 0.25, 0.3, 8, 0.0)
	b.stairs(P.CONCRETE, o + Vector3(-7, 0.1, -10), 3, 0.38, 0.35, 6, 0.0)
	# Mantle ledges: 1.0, 1.3, 1.6 (out of reach by default).
	for i in 3:
		b.block(P.CONCRETE_PALE, o + Vector3(4 + i * 5, 0.1, -18), Vector3(4, 1.0 + i * 0.3, 3))
	# Crouch tunnel 1.2 m high.
	b.block(P.CONCRETE, o + Vector3(14, 1.3, -4), Vector3(4, 1.6, 8))
	b.block(P.CONCRETE, o + Vector3(11.75, 0.1, -4), Vector3(0.5, 1.2, 8))
	b.block(P.CONCRETE, o + Vector3(16.25, 0.1, -4), Vector3(0.5, 1.2, 8))
	# Slopes: 20, 35, 45 (walkable), 55 degrees (not).
	var angs := [20.0, 35.0, 45.0, 55.0]
	for i in angs.size():
		var len := 6.0
		var h := tan(deg_to_rad(angs[i])) * len
		b.ramp(P.CONCRETE_PALE, o + Vector3(-15 + i * 5, 0.1, 6), Vector3(4, h, len), PI)
	# Jump gaps.
	for i in 4:
		b.block(P.CONCRETE, o + Vector3(6 + i * 3.6, 0.1, 12), Vector3(2, 1.2, 4))
	# Slide lane under a low beam.
	b.box(P.STEEL, o + Vector3(0, 1.05, 20), Vector3(6, 0.3, 0.6))
	b.commit(self, "TestRoom")

func _build_markers() -> void:
	var lamps := []
	for i in 10:
		lamps.append(Transform3D(Basis(), Vector3(9.5, 0, -120 + i * 26)))
		lamps.append(Transform3D(Basis(Vector3.UP, PI), Vector3(-9.5, 0, -120 + i * 26)))
	Builder.scatter(self, Builder.lamp_post(), lamps, 180.0)
	var lb := Builder.new()
	for i in 6:
		var x := -200 + i * 80.0
		lb.block(P.CONCRETE_DARK, Vector3(x, 0, -230), Vector3(30, 25 + (i % 3) * 18, 20), false)
		lb.box(P.WINDOWS, Vector3(x, 14, -219.9), Vector3(26, 20, 0.1), false)
	lb.commit(self, "Skyline")

func player_spawn() -> Array:
	return [Vector3(-6, 0.2, 18), 0.0]
