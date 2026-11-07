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
var driving := false

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
	rain = GPUParticles3D.new()
	rain.amount = 2200
	rain.lifetime = 0.9
	rain.visibility_aabb = AABB(Vector3(-25, -20, -25), Vector3(50, 40, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0.08, -1, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.012, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.82, 0.84, 0.22)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	qm.material = m
	rain.draw_pass_1 = qm
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.local_coords = false
	add_child(rain)
	P.set_wetness(1.0)

func on_quality_changed() -> void:
	var q := Game.q()
	if sun:
		sun.shadow_enabled = q.shadows
		sun.directional_shadow_max_distance = q.shadow_dist
	if rain:
		rain.visible = float(q.props) > 0.6
		rain.amount = int(2200 * float(q.props))
	if player:
		player.get_camera().far = q.far
	if car:
		car.get_node("ChaseCam").far = q.far
	env.fog_density = 0.0075 if float(q.far) > 300 else 0.012
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

func spawn_car(pos: Vector3, yaw: float) -> ArcadeCar:
	var c := Builder.make_car()
	c.position = pos
	c.rotation.y = yaw
	add_child(c)
	Interactable.make(c, Vector3(0, 0.9, 0), Vector3(2.4, 1.6, 4.6),
		func(): return "E  Drive" if not driving else "",
		func(): enter_car(c))
	return c

func enter_car(c: ArcadeCar) -> void:
	if driving:
		return
	car = c
	driving = true
	if rig.drawn:
		rig.set_drawn(false)
	player.set_active(false)
	c.set_driver(true)
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
	car.set_driver(false)
	driving = false
	player.global_position = chosen
	player.velocity = car.linear_velocity * 0.3
	player.set_look(car.rotation.y, 0.0)
	player.set_active(true)
	Game.play_3d("door", car.global_position, -4)

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
	elif e.is_action_pressed("interact") and driving:
		exit_car()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("reset_car") and driving:
		car.reset_upright()
	elif e is InputEventMouseButton and e.pressed and not get_tree().paused and not Game.tuning_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(_dt: float) -> void:
	if driving and car:
		# Keep the (hidden) player with the car so AI and zones track it.
		player.global_position = car.global_position + Vector3(0, 0.2, 0)
	if rain:
		var cam := get_viewport().get_camera_3d()
		if cam:
			rain.global_position = cam.global_position + Vector3(0, 12, 0)
