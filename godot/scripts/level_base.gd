class_name LevelBase
extends Node3D
## Shared level plumbing: environment and sun, rain, player + rig + HUD,
## the player's car with fast enter/exit, pause / notebook input.

const P = preload("res://scripts/palette.gd")

var player: FpsController
var rig: PlayerRig
var hud: Hud
var car: ArcadeCar
## The motorcycle being ridden (or the last one ridden).
var bike: BikeController
var riding := false
## A rider thrown off, while they are in the air and on the ground.
var _rim_sparks: Array[Dictionary] = []
var _thrown: RigidBody3D
var _thrown_cam: Camera3D
var _thrown_t := 0.0
var _thrown_rest := 0.0
var _thrown_yaw := 0.0
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var rain: GPUParticles3D
var weather: Weather
var base_fog_color := Color("#66767E")
var base_fog_density := 0.0065
var driving := false
## Driving view: true = first-person cockpit, false = chase camera (V).
var cockpit_view := true

func _ready() -> void:
	add_to_group("mouse_owner")
	add_to_group("quality_listener")
	P.mats()
	build_environment()
	build_world()
	var spawn := player_spawn()
	spawn_player(spawn[0], spawn[1])
	after_spawn()
	if Game.debug.has("pos"):
		var c: PackedStringArray = Game.debug.pos.split(",")
		player.global_position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		player.set_look(deg_to_rad(float(Game.debug.get("yaw", "0"))), deg_to_rad(float(Game.debug.get("pitch", "0"))))
	if Game.debug.has("draw"):
		rig.set_drawn(true)
	if Game.debug.has("ragdoll"):
		_debug_ragdoll.call_deferred()
	if Game.debug.has("market"):
		Game.sim.market_trade("pcem", 40)
		Game.sim.market_event("death:gov_saptavarta", 1.0)
		hud.toggle_market.call_deferred()
	if Game.debug.has("drive") and car:
		car.global_position = player.global_position + Vector3(0, 1.0, 0)
		car.rotation.y = player.get_yaw()
		enter_car(car)
		for a in str(Game.debug.drive).split("+"):
			Input.action_press(a)
	on_quality_changed()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Overridden by levels.
func build_world() -> void:
	pass

func player_spawn() -> Array:
	return [Vector3.ZERO, 0.0]

func after_spawn() -> void:
	pass

# ------------------------------------------------------------- environment

func build_environment(rainy := true) -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3E4D55")
	sky_mat.sky_horizon_color = Color("#7A8A91")
	sky_mat.ground_horizon_color = Color("#63737A")
	sky_mat.ground_bottom_color = Color("#27343A")
	sky_mat.sky_curve = 0.12
	sky_mat.sun_angle_max = 40.0
	sky_mat.sun_curve = 0.25
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.58
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.fog_enabled = true
	env.fog_light_color = Color("#66767E")
	env.fog_density = 0.0065
	env.fog_sky_affect = 0.55
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -145, 0)
	sun.light_color = Color("#EFCFA8")
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	add_child(sun)
	if rainy:
		_build_rain()

func _build_rain() -> void:
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	rain = weather.particles

func on_quality_changed() -> void:
	var q := Game.q()
	if sun:
		sun.shadow_enabled = q.shadows
		sun.directional_shadow_max_distance = q.shadow_dist
	if player:
		player.get_camera().far = q.far
	if car:
		car.get_node("ChaseCam").far = q.far
	if bike:
		bike.get_node("Visual/RiderCam").far = q.far
	base_fog_density = 0.0065 if float(q.far) > 300 else 0.011
	env.fog_density = base_fog_density
	env.glow_enabled = q.name == "HIGH"

# ------------------------------------------------------------- player / car

func spawn_player(pos: Vector3, yaw: float) -> void:
	player = FpsController.new()
	player.name = "Player"
	player.position = pos
	add_child(player)
	player.set_look(yaw, 0.0)
	player.get_camera().make_current()
	rig = PlayerRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup(player, self)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self, rig, player)

func spawn_car(pos: Vector3, yaw: float, paint := Color(0, 0, 0, 0)) -> ArcadeCar:
	var c := Builder.make_car()
	if paint.a > 0.0:
		Builder.paint_car(c, paint)
	c.position = pos
	c.rotation.y = yaw
	add_child(c)
	c.crashed.connect(func(dv, injury, glass): _on_car_crash(c, dv, injury, glass))
	Interactable.make(c, Vector3(0, 0.9, 0), Vector3(2.4, 1.6, 4.6),
		func(): return "E  Drive" if not driving else "",
		func(): enter_car(c))
	return c

func spawn_bike(pos: Vector3, yaw: float, paint := P.TEAL) -> BikeController:
	var b := Builder.make_bike(paint)
	b.position = pos
	b.rotation.y = yaw
	add_child(b)
	b.set_engine_stream(Game.sfx["ringding"])
	b.crashed.connect(func(dv, injury, eject): _on_bike_crash(b, dv, injury, eject))
	Interactable.make(b, Vector3(0, 0.8, 0), Vector3(1.0, 1.4, 2.4),
		func():
			if riding or driving or _thrown:
				return ""
			return "Shikra (wrecked)" if b.get_hull() <= 0.0 else "E  Ride the Shikra",
		func():
			if b.get_hull() > 0.0:
				enter_bike(b))
	return b

func enter_bike(b: BikeController) -> void:
	if riding or driving:
		return
	bike = b
	riding = true
	if rig.drawn:
		rig.set_drawn(false)
	player.set_active(false)
	b.set_driver(true)
	var view: Camera3D = b.get_node("Visual/RiderCam")
	view.far = Game.q().far
	(b.get_node("Visual/Front") as BikeCockpit).activate(true)
	rig.enter_vehicle(b, view, b, true)
	Game.play_3d("door", b.global_position, -8, 3.0, 1.6)

func exit_bike() -> void:
	if not riding:
		return
	var chosen: Vector3 = bike.get_exit_point()
	var space := get_world_3d().direct_space_state
	for s: Vector3 in [chosen, bike.global_transform * Vector3(1.1, 0.3, 0.0), bike.global_position + Vector3(0, 1.8, 0)]:
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.32
		cap.height = 1.78
		q.shape = cap
		q.transform = Transform3D(Basis(), s + Vector3(0, 0.95, 0))
		q.collision_mask = 1 | 8
		if space.intersect_shape(q, 1).is_empty():
			chosen = s
			break
	rig.leave_vehicle()
	bike.set_driver(false)
	(bike.get_node("Visual/Front") as BikeCockpit).activate(false)
	riding = false
	player.global_position = chosen
	player.velocity = bike.linear_velocity * 0.3
	player.set_look(bike.rotation.y, 0.0)
	player.set_active(true)

# ---- tyres

## A tyre was just punctured: the bang, and sparks for when it is on the rim.
func on_tyre_shot(v: Node3D, i: int) -> void:
	Game.play_3d("tyre_pop", v.tyre_pos(i), 0, 12.0)
	var sparks := CPUParticles3D.new()
	sparks.amount = 22
	sparks.lifetime = 0.45
	sparks.emitting = false
	sparks.local_coords = false
	sparks.direction = Vector3(0, 0.5, 1)
	sparks.spread = 34.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 7.0
	sparks.gravity = Vector3(0, -9.8, 0)
	sparks.scale_amount_min = 0.4
	sparks.scale_amount_max = 1.0
	var q := BoxMesh.new()
	q.size = Vector3(0.018, 0.018, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.72, 0.32)
	q.material = m
	sparks.mesh = q
	add_child(sparks)
	_rim_sparks.append({"v": v, "i": i, "node": sparks})
	if (driving and v == car) or (riding and v == bike):
		hud.message("Tyre gone.")
		rig.jolt(5.0)

func _update_rim_sparks() -> void:
	for s in _rim_sparks:
		var v: Node3D = s.v
		if not is_instance_valid(v):
			continue
		var node: CPUParticles3D = s.node
		var at: Vector3 = v.tyre_pos(s.i)
		node.global_position = at - Vector3(0, 0.18, 0)
		node.emitting = v.get_speed() > 5.0 and v.tyre_pressure(s.i) < 0.15

# ---- crashes

## A crash in a car: the windshield, the driver, the engine.
func _on_car_crash(c: ArcadeCar, dv: float, injury: float, glass: int) -> void:
	Game.play_3d("crash", c.global_position, clampf(dv * 0.5 - 8.0, -12.0, 2.0), 8.0, randf_range(0.9, 1.1))
	var ws := c.get_node_or_null("Windshield") as Windshield
	if ws:
		for i in glass:
			ws.strike_anywhere()
	(c.get_node("DamageSmoke") as CPUParticles3D).emitting = c.get_hull() < 0.35
	if not (driving and c == car):
		return
	rig.jolt(dv)
	_hurt_by_crash(injury)
	if c.get_hull() <= 0.0:
		hud.message("The engine is dead.")
	elif c.get_hull() < 0.35:
		hud.message("The engine is failing.")

## A crash on a bike: hard enough, and the rider comes off.
func _on_bike_crash(b: BikeController, dv: float, injury: float, eject: bool) -> void:
	Game.play_3d("crash", b.global_position, clampf(dv * 0.5 - 8.0, -12.0, 2.0), 8.0, randf_range(1.05, 1.25))
	(b.get_node("DamageSmoke") as CPUParticles3D).emitting = b.get_hull() < 0.35
	if not (riding and b == bike):
		return
	rig.jolt(dv)
	_hurt_by_crash(injury)
	if eject or b.get_hull() <= 0.0 and dv > 8.0:
		_throw_rider(b)
	elif b.get_hull() <= 0.0:
		hud.message("The engine is dead.")
	elif b.get_hull() < 0.35:
		hud.message("The engine is failing.")

func _hurt_by_crash(injury: float) -> void:
	if injury <= 0.0:
		return
	rig.hurt.emit(injury)
	if rig.mission_on():
		Game.sim.damage_player(injury)

## Off the bike: the rider flies on with what speed they had, as a small body
## with its own view, then lies there a moment before getting up.
func _throw_rider(b: BikeController) -> void:
	var v: Vector3 = b.get_impact_velocity()
	rig.leave_vehicle()
	b.set_driver(false)
	(b.get_node("Visual/Front") as BikeCockpit).activate(false)
	b.fall_over()
	riding = false
	var body := RigidBody3D.new()
	body.mass = 75.0
	body.collision_layer = 0
	body.collision_mask = 1 | 8
	body.linear_damp = 0.25
	body.angular_damp = 1.2
	var phys := PhysicsMaterial.new()
	phys.friction = 0.7
	phys.bounce = 0.25
	body.physics_material_override = phys
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.35
	cs.shape = sph
	body.add_child(cs)
	add_child(body)
	body.global_position = b.global_position + Vector3(0, 1.3, 0)
	body.linear_velocity = v * 0.8 + Vector3(0, 3.0, 0)
	body.angular_velocity = Vector3(randf_range(-5, 5), randf_range(-2, 2), randf_range(-5, 5))
	var cam := Camera3D.new()
	cam.top_level = true
	cam.near = 0.05
	cam.far = Game.q().far
	cam.fov = 80.0
	body.add_child(cam)
	cam.make_current()
	_thrown = body
	_thrown_cam = cam
	_thrown_t = 0.0
	_thrown_yaw = atan2(-v.x, -v.z) if v.length() > 1.0 else b.rotation.y
	hud.message("Thrown clear.")
	Game.play_2d("flesh", 0, 0.7)

func _update_thrown(dt: float) -> void:
	_thrown_t += dt
	var settled := _thrown.linear_velocity.length() < 1.2
	if settled:
		_thrown_rest += dt
	else:
		_thrown_rest = 0.0
	var at := _thrown.global_position
	player.global_position = at
	# Tumbling view; once it stops, lying on one side.
	var spin := _thrown.global_basis.get_euler()
	var roll: float = lerpf(spin.z, 1.35, clampf(_thrown_rest * 2.0, 0.0, 1.0))
	var pitch: float = lerpf(spin.x * 0.7, -0.1, clampf(_thrown_rest * 2.0, 0.0, 1.0))
	_thrown_cam.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, _thrown_yaw, roll)), at + Vector3(0, 0.05, 0))
	if _thrown_rest >= float(Game.sim.get_tuning("crash", "thrown_seconds")) or _thrown_t > 9.0:
		var yaw := _thrown_yaw
		_thrown.queue_free()
		_thrown = null
		_thrown_cam = null
		_thrown_rest = 0.0
		player.global_position = at + Vector3(0, 0.2, 0)
		player.set_look(yaw, 0.0)
		player.set_active(true)

func _debug_ragdoll() -> void:
	await get_tree().create_timer(float(Game.debug.get("ragdoll_delay", "0.6"))).timeout
	var best: Npc = null
	var want_role := str(Game.debug.get("ragdoll_role", ""))
	for n in get_tree().get_nodes_in_group("npc"):
		var npc := n as Npc
		if npc and want_role != "" and npc.role != want_role:
			continue
		if npc and Game.debug.has("ragdoll_tint") and int(npc.get_meta("tint", 0)) != int(Game.debug.ragdoll_tint):
			continue
		if npc and npc.alive and (best == null or npc.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = npc
	if best and Game.debug.has("ragdoll_role"):
		# Stand 4 m in front of the target, looking at it, then wait a beat.
		var f := -best.global_basis.z
		var dist := float(Game.debug.get("ragdoll_dist", "4"))
		player.global_position = best.global_position + f * dist + f.cross(Vector3.UP) * dist * 0.3
		var d := best.global_position + Vector3(0, 0.9, 0) - player.get_eye_position()
		player.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
		best.set_physics_process(false)
		await get_tree().create_timer(float(Game.debug.get("ragdoll_wait", "0.3"))).timeout
	if best:
		var mode := str(Game.debug.get("ragdoll"))
		print("ragdoll test (%s): " % mode, best.role, " at ", best.global_position)
		var from := player.global_position
		match mode:
			"leg":  # shot in the foot: drops to a knee, then limps
				best.apply_hit(20.0, from, "foot_l")
				best.set_physics_process(true)
			"arm":
				best.apply_hit(15.0, from, "forearm_r")
				best.set_physics_process(true)
			"down":  # legs shot out: on the ground, writhing
				for z in ["thigh_l", "shin_r", "foot_l"]:
					best.apply_hit(10.0, from, z)
				best.set_physics_process(true)
			"takedown":
				best.set_meta("knock", 5.0)
				best.set_meta("knock_how", "takedown")
				best.take_down()
			"yank", "tether":
				rig._equip(rig.loadout.find_custom(func(e): return e.def.get("kind") == "grapple"), true)
				rig.set_drawn(true)
				rig._latched = best.get_node("Visual")
				rig._hook_bone = "UpperChest"
				await get_tree().create_timer(0.3).timeout
				if mode == "yank":
					rig._yank()
				else:
					# Turn to the nearest wall on the left and tie him to it.
					player.set_look(player.get_yaw() + deg_to_rad(float(Game.debug.get("tether_turn", "70"))), 0.0)
					await get_tree().process_frame
					rig._tether_to_aim()
			_:
				best.apply_damage(9999.0, from, mode == "head")
		if Game.debug.has("exfil"):  # walk out after the kill to reach the debrief
			await get_tree().create_timer(float(Game.debug.exfil)).timeout
			player.global_position = Vector3(0, 1, 110)
			if Game.debug.has("press"):  # then press the first debrief button
				await get_tree().create_timer(3.0).timeout
				print("pressing debrief button")
				for b in get_tree().root.find_children("*", "Button", true, false):
					if b.is_visible_in_tree() and b.text in ["Return to the war room", "Replay"]:
						b.pressed.emit()
						break

## Physical death: the NpcBody's own skeleton goes ragdoll (Active Ragdoll
## addon), knocked along the killing blow: bullet (by body part), knife,
## takedown or a car.
func spawn_ragdoll(n: Npc) -> void:
	var body := n.get_node_or_null("Visual") as NpcBody
	if body == null:
		return
	for c in get_tree().get_nodes_in_group("cars"):
		var ac := c as ArcadeCar
		if ac and ac.global_position.distance_to(n.global_position) < 5.0 and ac.linear_velocity.length() > 3.0:
			var v := ac.linear_velocity
			body.die(v * 9.0 + Vector3.UP * v.length() * 3.0, "Hips", "limp")
			return
	var from: Vector3 = n.get_last_hit_from()
	if from == Vector3.ZERO:
		from = player.global_position
	var dir := n.global_position - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else -n.global_basis.z
	var knock := float(n.get_meta("knock", 26.0))
	var how := str(n.get_meta("knock_how", "die"))
	var zone := str(n.get_last_hit_zone())
	if zone == "head" and how == "die":
		how = "head"
	if how == "takedown":
		dir = -dir  # slumps back onto the attacker
	body.die((dir + Vector3.UP * 0.15) * knock, str(NpcBody.ZONE_BONE.get(zone, "UpperChest")), how)

func enter_car(c: ArcadeCar) -> void:
	c.freeze = false
	if driving:
		return
	car = c
	driving = true
	if rig.drawn:
		rig.set_drawn(false)
	player.set_active(false)
	c.set_driver(true)
	if cockpit_view and c.has_node("Cockpit"):
		c.get_node("Cockpit").activate(true)
	_car_view()
	Game.play_3d("door", c.global_position, -4)

## Hand the rig whichever view the car is in, for shooting from the seat.
func _car_view() -> void:
	var ck: CarCockpit = car.get_node("Cockpit")
	if cockpit_view:
		rig.enter_vehicle(car, ck.cam, ck, true)
	else:
		rig.enter_vehicle(car, car.get_node("ChaseCam"), car, false)

func exit_car() -> void:
	if not driving:
		return
	rig.leave_vehicle()
	var spot := car.get_exit_point()
	var sides := [spot, car.global_transform * Vector3(1.6, 0.4, -0.2), car.global_position + Vector3(0, 2.2, 0)]
	var space := get_world_3d().direct_space_state
	var chosen: Vector3 = sides[-1]
	for s in sides:
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.32
		cap.height = 1.78
		q.shape = cap
		q.transform = Transform3D(Basis(), s + Vector3(0, 0.95, 0))
		q.collision_mask = 1 | 8
		if space.intersect_shape(q, 1).is_empty():
			chosen = s
			break
	if car.has_node("Cockpit"):
		car.get_node("Cockpit").activate(false)
	car.set_driver(false)
	driving = false
	player.global_position = chosen
	player.velocity = car.linear_velocity * 0.3
	player.set_look(car.rotation.y, 0.0)
	player.set_active(true)
	Game.play_3d("door", car.global_position, -4)

func debug_relook() -> void:
	if Game.debug.has("pos") and player:
		player.set_look(deg_to_rad(float(Game.debug.get("yaw", "0"))), deg_to_rad(float(Game.debug.get("pitch", "0"))))

func recapture_mouse() -> void:
	if not get_tree().paused and not hud.notebook_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		if Game.tuning_open():
			return
		hud.toggle_pause()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("notebook"):
		hud.toggle_notebook()
	elif e.is_action_pressed("market"):
		hud.toggle_market()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("interact") and driving:
		exit_car()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("interact") and riding:
		exit_bike()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("reset_car") and riding:
		bike.reset_upright()
	elif e.is_action_pressed("camera_view") and driving and car.has_node("Cockpit"):
		cockpit_view = not cockpit_view
		var ck: CarCockpit = car.get_node("Cockpit")
		ck.activate(cockpit_view)
		if not cockpit_view:
			car.set_driver(true)
		_car_view()
		hud.message("Cockpit view" if cockpit_view else "Chase view")
	elif e.is_action_pressed("reset_car") and driving:
		car.reset_upright()
	elif e is InputEventMouseButton and e.pressed and not get_tree().paused and not Game.tuning_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(_dt: float) -> void:
	if driving and car:
		# Keep the (hidden) player with the car so AI and zones track it.
		player.global_position = car.global_position + Vector3(0, 0.2, 0)
	elif riding and bike:
		player.global_position = bike.global_position + Vector3(0, 0.2, 0)
	elif _thrown:
		_update_thrown(_dt)
	if not _rim_sparks.is_empty():
		_update_rim_sparks()

func _process(_dt: float) -> void:
	if Game.debug.has("drive") and car and Engine.get_process_frames() % 30 == 0:
		print("drive t=%.2f f=%d pos=%s speed=%.2f rpm=%d gear=%d yaw=%.2f" % [Engine.get_physics_frames() / 120.0, Engine.get_process_frames(), str(car.global_position.snapped(Vector3.ONE * 0.1)), car.get_speed(), int(car.get_rpm()), car.get_gear(), car.rotation.y])
	if weather:
		_weather_env()

## Weather nudges fog toward a snowy white-out (from the level's base values).
func _weather_env() -> void:
	var falling := 1.0 if weather.mode == "snow" else 0.0
	env.fog_light_color = base_fog_color.lerp(Color("#93A9B5"), clampf(weather.snow * 0.5 + falling * 0.25, 0.0, 0.7))
	env.fog_density = base_fog_density * (1.0 + falling * 0.9)
