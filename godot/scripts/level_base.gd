class_name LevelBase
extends Node3D
## Shared level plumbing: environment and sun, rain, player + rig + HUD,
## the player's car with fast enter/exit, pause / notebook input.

const P = preload("res://scripts/palette.gd")

var player: FpsController
var rig: PlayerRig
var hud: Hud
var car: ArcadeCar
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var rain: GPUParticles3D
var weather: Weather
var base_fog_color := Color("#848D90")
var base_fog_density := 0.0075
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
	sky_mat.sky_top_color = Color("#5C6669")
	sky_mat.sky_horizon_color = Color("#8E9699")
	sky_mat.ground_horizon_color = Color("#8C9091")
	sky_mat.ground_bottom_color = Color("#4A4F51")
	sky_mat.sky_curve = 0.12
	sky_mat.sun_angle_max = 40.0
	sky_mat.sun_curve = 0.25
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.fog_enabled = true
	env.fog_light_color = Color("#848D90")
	env.fog_density = 0.0075
	env.fog_sky_affect = 0.55
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.06
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -145, 0)
	sun.light_color = Color("#E3DACB")
	sun.light_energy = 0.62
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
	base_fog_density = 0.0075 if float(q.far) > 300 else 0.012
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
	Interactable.make(c, Vector3(0, 0.9, 0), Vector3(2.4, 1.6, 4.6),
		func(): return "E  Drive" if not driving else "",
		func(): enter_car(c))
	return c

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
		print("ragdoll test: ", best.role, " at ", best.global_position)
		best.apply_damage(9999.0, player.global_position, Game.debug.get("ragdoll") == "head")

## Physical death: hand the body to the Active Ragdoll addon, knocked along
## the killing blow (bullet, knife, takedown or a car).
func spawn_ragdoll(n: Npc) -> void:
	for c in get_tree().get_nodes_in_group("cars"):
		var ac := c as ArcadeCar
		if ac and ac.global_position.distance_to(n.global_position) < 5.0 and ac.linear_velocity.length() > 3.0:
			var v := ac.linear_velocity
			RagdollCorpse.spawn(n, v * 9.0 + Vector3.UP * v.length() * 3.0, "Hips", "limp")
			return
	var from: Vector3 = n.get_last_hit_from()
	if from == Vector3.ZERO:
		from = player.global_position
	var dir := n.global_position - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else -n.global_basis.z
	var knock := float(n.get_meta("knock", 26.0))
	var how := str(n.get_meta("knock_how", "die"))
	RagdollCorpse.spawn(n, (dir + Vector3.UP * 0.15) * knock, "Head" if n.get_last_hit_head() else "UpperChest", how)

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
	Game.play_3d("door", c.global_position, -4)

func exit_car() -> void:
	if not driving:
		return
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
	elif e.is_action_pressed("camera_view") and driving and car.has_node("Cockpit"):
		cockpit_view = not cockpit_view
		var ck: CarCockpit = car.get_node("Cockpit")
		ck.activate(cockpit_view)
		if not cockpit_view:
			car.set_driver(true)
		hud.message("Cockpit view" if cockpit_view else "Chase view")
	elif e.is_action_pressed("reset_car") and driving:
		car.reset_upright()
	elif e is InputEventMouseButton and e.pressed and not get_tree().paused and not Game.tuning_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(_dt: float) -> void:
	if driving and car:
		# Keep the (hidden) player with the car so AI and zones track it.
		player.global_position = car.global_position + Vector3(0, 0.2, 0)

func _process(_dt: float) -> void:
	if Game.debug.has("drive") and car and Engine.get_process_frames() % 30 == 0:
		print("drive t=%.2f f=%d pos=%s speed=%.2f rpm=%d gear=%d yaw=%.2f" % [Engine.get_physics_frames() / 120.0, Engine.get_process_frames(), str(car.global_position.snapped(Vector3.ONE * 0.1)), car.get_speed(), int(car.get_rpm()), car.get_gear(), car.rotation.y])
	if weather:
		_weather_env()

## Weather nudges fog toward a snowy white-out (from the level's base values).
func _weather_env() -> void:
	var falling := 1.0 if weather.mode == "snow" else 0.0
	env.fog_light_color = base_fog_color.lerp(Color("#B4BCC0"), clampf(weather.snow * 0.5 + falling * 0.25, 0.0, 0.7))
	env.fog_density = base_fog_density * (1.0 + falling * 0.9)
