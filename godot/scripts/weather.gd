class_name Weather
extends Node3D
## Rain / snow / clear. Owns the world-space particles around the camera, the
## screen-space precipitation layer, the precipitation loop, and the global
## shader values every kit material reads:
##   weather_wet   0..1  darkening + puddle gloss and reflections
##   weather_rain  0..1  animated ripples in puddles while it is raining
##   weather_snow  0..1  snow layer on upward-facing exterior surfaces
## Wetness and snow build up and fade over time, so a shower leaves the
## street glossy for a while and a snowfall lays a growing white layer.

var mode := "rain"
## Set by the level when the camera is under a roof.
var indoor := false
var wet := 0.0
var snow := 0.0
var rain_k := 0.0
var particles: GPUParticles3D
var _rain_draw: QuadMesh
var _snow_draw: QuadMesh
var _rain_pm: ParticleProcessMaterial
var _snow_pm: ParticleProcessMaterial
var _layer: CanvasLayer
var _overlay: ColorRect
var _overlay_mat: ShaderMaterial
var _audio: AudioStreamPlayer
var _quality_fx := 1

func _ready() -> void:
	add_to_group("weather_listener")
	add_to_group("quality_listener")
	particles = GPUParticles3D.new()
	particles.visibility_aabb = AABB(Vector3(-26, -24, -26), Vector3(52, 40, 52))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.local_coords = false
	add_child(particles)
	# Rain: thin fast streaks.
	_rain_pm = ParticleProcessMaterial.new()
	_rain_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_pm.emission_box_extents = Vector3(22, 1, 22)
	_rain_pm.direction = Vector3(0.08, -1, 0.03)
	_rain_pm.spread = 2.0
	_rain_pm.initial_velocity_min = 22.0
	_rain_pm.initial_velocity_max = 26.0
	_rain_pm.gravity = Vector3(0, -9.8, 0)
	_rain_draw = QuadMesh.new()
	_rain_draw.size = Vector2(0.012, 0.6)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.8, 0.84, 0.86, 0.24)
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	rm.billboard_keep_scale = true
	_rain_draw.material = rm
	# Snow: slow, drifting soft flakes.
	_snow_pm = ParticleProcessMaterial.new()
	_snow_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_pm.emission_box_extents = Vector3(24, 1, 24)
	_snow_pm.direction = Vector3(0.25, -1, 0.1)
	_snow_pm.spread = 28.0
	_snow_pm.initial_velocity_min = 0.9
	_snow_pm.initial_velocity_max = 1.8
	_snow_pm.gravity = Vector3(0.15, -0.55, 0.05)
	_snow_pm.angular_velocity_min = -90.0
	_snow_pm.angular_velocity_max = 90.0
	_snow_pm.scale_min = 0.6
	_snow_pm.scale_max = 1.4
	_snow_draw = QuadMesh.new()
	_snow_draw.size = Vector2(0.07, 0.07)
	var sm := PlayerRig.glow_mat(Color(0.95, 0.96, 0.98, 0.9), false)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_snow_draw.material = sm
	# Screen-space layer, drawn beneath the HUD and before the post pass.
	_layer = CanvasLayer.new()
	_layer.layer = 9
	add_child(_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = preload("res://shaders/precip.gdshader")
	_overlay.material = _overlay_mat
	_layer.add_child(_overlay)
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -14.0
	add_child(_audio)
	set_mode(str(Game.settings.weather), true)
	on_quality_changed()

func set_mode(m: String, initial := false) -> void:
	mode = m
	var q: Dictionary = Game.q()
	var props := float(q.props)
	match mode:
		"rain":
			particles.process_material = _rain_pm
			particles.draw_pass_1 = _rain_draw
			particles.amount = maxi(int(2400 * props), 200)
			particles.lifetime = 0.95
			particles.emitting = true
			_overlay_mat.set_shader_parameter("count", 70)
			_overlay_mat.set_shader_parameter("slant", -0.03)
			_overlay_mat.set_shader_parameter("speed", 55.0)
			_overlay_mat.set_shader_parameter("blur", 0.002)
			_overlay_mat.set_shader_parameter("size", Vector2(0.004, 0.22))
			_overlay_mat.set_shader_parameter("colour", Color(0.82, 0.86, 0.9))
			_overlay_mat.set_shader_parameter("alpha", 0.22)
			_overlay_mat.set_shader_parameter("wobble", 0.0)
			_audio.stream = Game.sfx.get("rain")
			_audio.volume_db = -12.0
			if initial:
				wet = 0.85
		"snow":
			particles.process_material = _snow_pm
			particles.draw_pass_1 = _snow_draw
			particles.amount = maxi(int(2600 * props), 300)
			particles.lifetime = 9.0
			particles.preprocess = 9.0
			particles.emitting = true
			_overlay_mat.set_shader_parameter("count", 60)
			_overlay_mat.set_shader_parameter("slant", 0.04)
			_overlay_mat.set_shader_parameter("speed", 2.2)
			_overlay_mat.set_shader_parameter("blur", 0.012)
			_overlay_mat.set_shader_parameter("size", Vector2(0.035, 0.06))
			_overlay_mat.set_shader_parameter("colour", Color(0.97, 0.98, 1.0))
			_overlay_mat.set_shader_parameter("alpha", 0.55)
			_overlay_mat.set_shader_parameter("wobble", 0.02)
			_audio.stream = Game.sfx.get("wind")
			_audio.volume_db = -16.0
			if initial:
				snow = 0.75
				wet = 0.15
		_:
			particles.emitting = false
			_audio.stream = null
			if initial:
				wet = 0.25
	if _audio.stream:
		_audio.play()
	else:
		_audio.stop()
	_apply_globals()

func on_quality_changed() -> void:
	_quality_fx = int(Game.q().get("weather_fx", 1))
	if mode == "rain":
		particles.amount = maxi(int(2400 * float(Game.q().props)), 200)

func _apply_globals() -> void:
	RenderingServer.global_shader_parameter_set("weather_wet", wet)
	RenderingServer.global_shader_parameter_set("weather_snow", snow)
	RenderingServer.global_shader_parameter_set("weather_rain", rain_k)

func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		particles.global_position = cam.global_position + Vector3(0, 12 if mode == "rain" else 10, 0)
	var precip := mode != "clear"
	particles.visible = precip
	# Lens layer: costs a loop per pixel, so LOW skips it and MEDIUM halves it.
	_overlay.visible = precip and not indoor and _quality_fx > 0
	if _overlay.visible:
		var base := 70 if mode == "rain" else 60
		_overlay_mat.set_shader_parameter("count", base if _quality_fx > 1 else base / 2)
	# Build-up and drying.
	match mode:
		"rain":
			wet = move_toward(wet, 1.0, dt / 40.0)
			snow = move_toward(snow, 0.0, dt / 30.0)
			rain_k = move_toward(rain_k, 1.0, dt)
		"snow":
			snow = move_toward(snow, 1.0, dt / 120.0)
			wet = move_toward(wet, 0.15, dt / 90.0)
			rain_k = move_toward(rain_k, 0.0, dt)
		_:
			wet = move_toward(wet, 0.1, dt / 240.0)
			snow = move_toward(snow, 0.0, dt / 400.0)
			rain_k = move_toward(rain_k, 0.0, dt)
	_audio.volume_db = lerpf(_audio.volume_db, (-22.0 if indoor else -12.0) + (-4.0 if mode == "snow" else 0.0), 1.0 - exp(-dt * 4.0))
	_apply_globals()

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("weather_wet", 0.0)
	RenderingServer.global_shader_parameter_set("weather_snow", 0.0)
	RenderingServer.global_shader_parameter_set("weather_rain", 0.0)
