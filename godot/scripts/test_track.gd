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
	# The Shikra, for tuning the two-stroke on the same road.
	spawn_bike(Vector3(-16.6, 0.6, 58.0), 0.0)
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
	sun.light_energy = lerpf(0.72, 0.2, t)
	sun.light_color = Color("#EFCFA8").lerp(Color("#D9A880"), t)
	# Keep the sun high: the reference is overcast, with no long hard shadows.
	sun.rotation_degrees.x = lerpf(-32.0, -48.0, t)
	sun.shadow_blur = 3.0
	env.ambient_light_energy = lerpf(0.58, 0.48, t)
	sky_mat.sky_top_color = Color("#3E4D55").lerp(Color("#22333D"), t)
	sky_mat.sky_horizon_color = Color("#7A8A91").lerp(Color("#566B75"), t)
	sky_mat.ground_horizon_color = Color("#63737A").lerp(Color("#44555F"), t)
	base_fog_color = Color("#66767E").lerp(Color("#44596A"), t)
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
	if riding and bike:
		return bike.global_position
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

## `--vt=glass0|glass1|glass2|ride|crash|carcrash`: drives the vehicle flows with
## no input and prints what happened. Used to check them; not reachable in play.
var _vt_t := 0.0
var _vt_step := 0

func _vt(dt: float) -> void:
	_vt_t += dt
	var kind := str(Game.debug.vt)
	if _vt_step == 0 and _vt_t > 1.0:
		_vt_step = 1
		if kind.begins_with("crash") or kind == "carcrash":
			var w := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(30, 8, 2)
			cs.shape = bs
			w.add_child(cs)
			w.position = Vector3(-13, 4, -80)
			add_child(w)
		if kind.begins_with("glass") or kind == "carcrash":
			enter_car(car)
		elif not kind.begins_with("tyre") and kind != "dent" and kind != "traffic" and kind != "parked":
			var bs2: BikeController = get_tree().get_nodes_in_group("bikes")[0]
			enter_bike(bs2)
		if kind == "ride" or kind.begins_with("crash") or kind == "carcrash":
			Input.action_press("move_forward")
		if kind.begins_with("glass") or kind == "ride":
			rig.set_drawn(true)
	if kind == "parked" and _vt_step == 1:
		_vt_step = 2
		player.global_position = car.global_position + Vector3(-2.4, 0.3, -3.2)
		var seen: Vector3 = car.global_position - player.global_position
		player.set_look(atan2(-seen.x, -seen.z), -0.12)
	elif kind == "dent":
		_vt_dent()
	elif kind == "traffic":
		_vt_traffic()
	elif kind.begins_with("tyre"):
		_vt_tyre(kind, dt)
	if kind.begins_with("glass") and _vt_step >= 1 and _vt_step <= int(kind.substr(5)) and _vt_t > 1.5 + _vt_step * 0.6:
		_vt_step += 1
		rig._fire()
		print("vt: fired, glass state ", car.windshield_state())
	if kind == "ride" and _vt_t > 2.0 and fmod(_vt_t, 2.0) < dt:
		print("vt: true speed %.1f km/h, rpm %d gear %d, hud '%s'" % [bike.linear_velocity.length() * 3.6, int(bike.get_rpm()), bike.get_gear(), hud._drive.text])
		if _vt_t > 4.0 and rig.drawn:
			rig._fire()
	if (kind.begins_with("crash") or kind == "carcrash") and fmod(_vt_t, 1.0) < dt:
		var v: RigidBody3D = car if driving or bike == null else bike
		print("vt: t=%d z=%.0f speed %.1f riding=%s driving=%s thrown=%s player=%s hull=%.2f glass=%d" % [int(_vt_t), v.global_position.z, v.linear_velocity.length() * 3.6, str(riding), str(driving), str(_thrown != null), str(player.enabled), v.get_hull(), car.windshield_state()])

func _vt_dent() -> void:
	if _vt_step == 1:
		_vt_step = 2
		var w := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.2, 4, 1.2)
		cs.shape = bs
		w.add_child(cs)
		w.position = Vector3(-14.4, 2, 40)
		add_child(w)
		car.global_position = Vector3(-13.3, 0.6, 58)
		car.linear_velocity = Vector3(0, 0, -24)
		car.sleeping = false
	if _vt_step == 2 and car.get_hull() < 1.0:
		_vt_step = 3
		print("vt: dent at %s push %s hull %.2f" % [str(car.get_impact_point()), str(car.get_impact_push()), car.get_hull()])
		print("vt: dent frame time %.1f ms" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))
	if _vt_step == 3 and _vt_t > 4.0:
		_vt_step = 4
		var at: Vector3 = car.tyre_pos(0)
		rig._check_tyres(at + Vector3(-6, 0.1, 0), at + Vector3(1, 0, 0))
		print("vt: tyre shot flats=%d; car at %s" % [car.flat_tyres(), str(car.global_position)])
		player.global_position = car.global_position + Vector3(-2.4, 0.3, -3.2)
		var to: Vector3 = car.global_position - player.global_position
		player.set_look(atan2(-to.x, -to.z), -0.12)

func _vt_traffic() -> void:
	if traffic.cars.is_empty():
		return
	var c: Dictionary = traffic.cars[0]
	if _vt_step == 1:
		_vt_step = 2
		var body: Node3D = c.body
		var at: Vector3 = body.global_transform * Vector3(0.8, 0.32, 1.38)
		var hit: Vector3 = traffic.shoot_tyres(at + Vector3(6, 0, 0), at - Vector3(1, 0, 0))
		print("vt: traffic shot hit=%s pref=%.1f" % [str(not is_nan(hit.x)), c.pref])
	if fmod(_vt_t, 1.5) < get_physics_process_delta_time():
		print("vt: traffic v=%.1f" % c.v)

func _vt_tyre(kind: String, _dt: float) -> void:
	var v: Node3D = car if kind.ends_with("car") else get_tree().get_nodes_in_group("bikes")[0]
	if _vt_step == 1:
		_vt_step = 2
		if kind.begins_with("tyres"):
			# Through the real shot path: a line straight at the left front wheel.
			var at: Vector3 = v.tyre_pos(1 if v == car else 0)
			rig._check_tyres(at + Vector3(6, 0.1, 0), at - Vector3(1, 0, 0))
			print("vt: shot; flats=%d pressure=%.2f" % [v.flat_tyres(), v.tyre_pressure(0)])
	if _vt_step == 2 and _vt_t > 3.0:
		_vt_step = 3
		if driving:
			pass
		elif v == car:
			enter_car(car)
		else:
			enter_bike(v)
		Input.action_press("move_forward")
	if fmod(_vt_t, 1.5) < get_physics_process_delta_time():
		print("vt: t=%.0f speed %.0f km/h x=%.2f pressure=%.2f y=%.2f" % [_vt_t, v.get_speed() * 3.6, v.global_position.x, v.tyre_pressure(1 if v == car else 0), v.global_position.y])

func _on_bike_crash(b: BikeController, dv: float, injury: float, eject: bool) -> void:
	if Game.debug.has("vt"):
		print("vt: BIKE CRASH dv=%.1f injury=%.1f eject=%s" % [dv, injury, str(eject)])
	super(b, dv, injury, eject)

func _on_car_crash(c: ArcadeCar, dv: float, injury: float, glass: int) -> void:
	if Game.debug.has("vt"):
		print("vt: CAR CRASH dv=%.1f injury=%.1f glass_hits=%d" % [dv, injury, glass])
	super(c, dv, injury, glass)

func _physics_process(dt: float) -> void:
	super(dt)
	if Game.debug.has("vt"):
		_vt(dt)
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

