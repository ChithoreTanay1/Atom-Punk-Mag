extends LevelBase
## Milestone 1 "feel test", rebuilt as an endless expressway after
## refs/expressway.jfif: six lanes under a Y-pier viaduct, a promenade, an
## atompunk street wall, traffic and airships at blue hour. See
## scripts/expressway.gd for the road and scripts/traffic.gd for the cars.
## The feel-test kit sits in the yard beside the spawn: the on-foot test
## room (steps, stair rises, mantle ledges, crouch tunnel, slide lane,
## slopes, gaps) and a handling pad (slalom, jumps, rumble strips, a hill).
## Ramps beside the viaduct (every 8th chunk, up and down) let you drive
## onto the top road; the second Kestrel waits at the first one.
## F1 opens the tuning panel. Debug: --dusk=0..1.

const Expressway = preload("res://scripts/expressway.gd")
const Traffic = preload("res://scripts/traffic.gd")
const Minimap = preload("res://scripts/minimap.gd")
## Re-centre the world when the focus gets this far from 0 (float precision).
const REBASE := 2048.0

var road: Expressway
var traffic: Traffic
var ships: Array[Node3D] = []
var _ship_speed: Array[float] = []

func build_world() -> void:
	_apply_dusk(float(Game.debug.get("dusk", "0.55")))
	road = Expressway.new()
	road.name = "Expressway"
	road.extra = _feel_kit
	add_child(road)
	road.build_all(60.0)
	traffic = Traffic.new()
	traffic.name = "Traffic"
	traffic.focus = Vector3(0, 0, 60)
	add_child(traffic)
	traffic.setup(4, 326)
	_build_ships()
	var amb := AudioStreamPlayer.new()
	amb.stream = Game.sfx["ambience"]
	amb.volume_db = -12
	add_child(amb)
	amb.play()
	# A second Kestrel on the service road, lined up with the on-ramp up to
	# the viaduct (chunk -1 is a ramp-up chunk; its foot is at z = 0).
	spawn_car(Vector3(31.0, 1.0, 34.0), 0.0, Color("#2F6E73"))
	car = spawn_car(Vector3(-13.3, 1.0, 60.0), 0.0)
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var mm := Minimap.new()
	mm.level = self
	layer.add_child(mm)

func after_spawn() -> void:
	traffic.obstacles = [car, player]

func player_spawn() -> Array:
	return [Vector3(-17.0, 0.4, 66.0), 0.0]

# ------------------------------------------------------------- feel kit

## Built into chunks -1 and 0 (the yard) whenever they stream in.
func _feel_kit(i: int, chunk: Node3D) -> void:
	if i == 0:
		_build_test_room(chunk, Vector3(-56, 0, 40))
	elif i == -1:
		_build_handling_pad(chunk)

func _build_test_room(parent: Node3D, o: Vector3) -> void:
	var b := Builder.new()
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
	b.commit(parent, "TestRoom")

## Chunk -1's yard (local z 0..96 = world -96..0). The car runs toward -Z.
func _build_handling_pad(parent: Node3D) -> void:
	var b := Builder.new()
	var z0 := Expressway.L
	# Jumps of increasing height.
	b.ramp(P.CONCRETE, Vector3(-70, 0, z0 - 20), Vector3(8, 1.0, 8), PI)
	b.ramp(P.CONCRETE, Vector3(-70, 0, z0 - 46), Vector3(8, 2.2, 10), PI)
	b.ramp(P.CONCRETE, Vector3(-70, 0, z0 - 72), Vector3(8, 1.6, 6), PI)
	b.ramp(P.CONCRETE, Vector3(-70, 0, z0 - 81), Vector3(8, 1.6, 6), 0.0)
	# Rumble strips, then square kerbs.
	for i in 14:
		b.box(P.CONCRETE_DARK if i % 2 == 0 else P.CONCRETE_PALE, Vector3(-38, 0.06, z0 - 14 - i * 1.2), Vector3(12, 0.12, 0.6))
	for i in 6:
		b.box(P.CONCRETE_DARK, Vector3(-38, 0.1, z0 - 50 - i * 6), Vector3(12, 0.2, 0.5))
	# A hill: up, plateau, down.
	b.ramp(P.CONCRETE, Vector3(-85, 0, z0 - 27), Vector3(10, 3.0, 30), PI)
	b.box(P.CONCRETE, Vector3(-85, 1.5, z0 - 52), Vector3(10, 3.0, 20))
	b.ramp(P.CONCRETE, Vector3(-85, 0, z0 - 77), Vector3(10, 3.0, 30), 0.0)
	# Slalom.
	var cones := []
	for i in 12:
		var z := z0 - 10.0 - i * 6.5
		var x := -55.0 + (3.2 if i % 2 == 0 else -3.2)
		cones.append(Transform3D(Basis(), Vector3(x, 0, z)))
		b.kit.add_collider(Builder.xf(Vector3(x, 0.4, z)), Vector3(0.4, 0.8, 0.4))
	b.commit(parent, "HandlingPad")
	Builder.scatter(parent, Builder.cone(), cones, 150.0, false)

# ------------------------------------------------------------- sky

func _apply_dusk(t: float) -> void:
	P.set_dusk(t)
	sun.light_energy = lerpf(0.62, 0.16, t)
	sun.light_color = Color("#E3DACB").lerp(Color("#B9AE9E"), t)
	# Keep the sun high: the reference is overcast, with no long hard shadows.
	sun.rotation_degrees.x = lerpf(-32.0, -48.0, t)
	sun.shadow_blur = 3.0
	env.ambient_light_energy = lerpf(0.62, 0.38, t)
	sky_mat.sky_top_color = Color("#5C6669").lerp(Color("#25333B"), t)
	sky_mat.sky_horizon_color = Color("#8E9699").lerp(Color("#5A6A74"), t)
	sky_mat.ground_horizon_color = Color("#8C9091").lerp(Color("#4A5760"), t)
	base_fog_color = Color("#848D90").lerp(Color("#53616A"), t)
	env.fog_light_color = base_fog_color

func _build_ships() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for spec in [[-150.0, 95.0], [70.0, 70.0], [230.0, 120.0]]:
		var n := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = Builder.dirigible()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		n.position = Vector3(spec[0], spec[1], rng.randf_range(-500.0, 300.0))
		n.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
		add_child(n)
		ships.append(n)
		_ship_speed.append(rng.randf_range(3.0, 7.0))

# ------------------------------------------------------------- per frame

func _focus() -> Vector3:
	return car.global_position if driving and car else player.global_position

func _process(dt: float) -> void:
	super(dt)
	var f := _focus()
	road.update(f.z)
	traffic.focus = f
	for k in ships.size():
		var s := ships[k]
		s.position.z -= _ship_speed[k] * dt
		if s.position.z - f.z < -700.0:
			s.position.z += 1400.0
		elif s.position.z - f.z > 700.0:
			s.position.z -= 1400.0
	if weather:
		# No rain under the viaduct or the promenade.
		var cam := get_viewport().get_camera_3d()
		var cp := cam.global_position if cam else f
		var under := (cp.x > 14.0 and cp.x < 28.0 and cp.y < 9.0) \
			or (cp.x > Expressway.PROM_X0 and cp.x < Expressway.PROM_X1 and cp.y < 5.8)
		weather.indoor = under
		rain.emitting = not under and weather.mode != "clear"

func _physics_process(dt: float) -> void:
	super(dt)
	var f := _focus()
	if absf(f.z) > REBASE:
		_rebase(Expressway.L * roundf(f.z / Expressway.L))

## Floating origin: move everything back by s along Z.
func _rebase(s: float) -> void:
	var d := Vector3(0, 0, -s)
	road.rebase(s)
	traffic.rebase(s)
	for c in get_tree().get_nodes_in_group("cars"):
		var ac := c as ArcadeCar
		if ac:
			ac.global_position += d
			if ac.has_method("shift_origin"):
				ac.shift_origin(d)
	player.global_position += d
	for sh in ships:
		sh.position += d
	if weather and weather.particles:
		weather.particles.restart()

