extends Node
## Autoload "Game". Owns the Rust GameSim node, input map, settings and
## quality presets, the procedural SFX bank and pooled audio players, scene
## changes, and the always-available overlays (F1 tuning, F3 frame time).

const SAVE_PATH := "user://campaign.ron"
const SETTINGS_PATH := "user://settings.cfg"
const RETRO_NAMES := ["off", "dither", "PSX"]
const WEATHERS := ["rain", "snow", "clear"]

const QUALITY := [
	{"name": "LOW", "scale": 0.7, "shadows": false, "shadow_size": 1024, "shadow_dist": 35.0, "msaa": 0, "post": true, "far": 260.0, "props": 0.55, "weather_fx": 0},
	{"name": "MEDIUM", "scale": 0.85, "shadows": true, "shadow_size": 2048, "shadow_dist": 55.0, "msaa": 0, "post": true, "far": 420.0, "props": 0.8, "weather_fx": 1},
	{"name": "HIGH", "scale": 1.0, "shadows": true, "shadow_size": 4096, "shadow_dist": 80.0, "msaa": 1, "post": true, "far": 700.0, "props": 1.0, "weather_fx": 2},
]

var sim: GameSim
var data_error := ""
var sfx := {}
var settings := {"quality": 1, "mouse_scale": 1.0, "volume": 0.8, "fullscreen": false, "post": true, "retro": 2, "weather": "rain"}
var mode := "campaign"  # "campaign" | "free"
var last_report := ""
var mono: SystemFont

var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _pool2_i := 0
var _overlay: CanvasLayer
var _fps_label: Label
var _tuning_panel: Control
var _fade: ColorRect
## Debug: `-- --shot=out.png --frames=N --pos=x,y,z --yaw=deg --pitch=deg --clock=min`
var debug := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "DejaVu Sans Mono", "monospace"])
	sim = GameSim.new()
	sim.name = "GameSim"
	add_child(sim)
	data_error = sim.load_data(_data_dir())
	if data_error != "":
		push_error("Data load failed: " + data_error)
	sim.market_news.connect(func(h: PackedStringArray): get_tree().call_group("market_listener", "on_market_news", h))
	var bank := SfxBank.new()
	for n in bank.names():
		sfx[n] = bank.make(n)
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 90.0
		p.attenuation_filter_cutoff_hz = 6000.0
		add_child(p)
		_pool3d.append(p)
	for i in 8:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool2d.append(p2)
	_build_overlay()
	_load_settings()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			debug[kv[0]] = kv[1]
	if debug.has("quality"):
		settings.quality = int(debug.quality)
	if debug.has("weather"):
		settings.weather = debug.weather
	if debug.has("retro"):
		settings.retro = int(debug.retro)
	apply_settings()

func _data_dir() -> String:
	var d := ProjectSettings.globalize_path("res://").path_join("../data").simplify_path()
	if DirAccess.dir_exists_absolute(d):
		return d
	return OS.get_executable_path().get_base_dir().path_join("data")

# ---------------------------------------------------------------- input map

func _key(action: String, keys: Array, mouse := -1) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	if mouse >= 0:
		var m := InputEventMouseButton.new()
		m.button_index = mouse
		InputMap.action_add_event(action, m)

func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("sprint", [KEY_SHIFT])
	_key("crouch", [KEY_CTRL, KEY_C])
	_key("interact", [KEY_E])
	_key("fire", [], MOUSE_BUTTON_LEFT)
	_key("aim", [], MOUSE_BUTTON_RIGHT)
	_key("reload", [KEY_R])
	_key("holster", [KEY_X])
	_key("fire_mode", [KEY_B])
	_key("gadget_use", [KEY_G], MOUSE_BUTTON_MIDDLE)
	_key("gadget_next", [KEY_Q])
	_key("takedown", [KEY_F])
	_key("notebook", [KEY_TAB])
	_key("market", [KEY_M])
	_key("camera_view", [KEY_V])
	_key("pause", [KEY_ESCAPE])
	_key("tuning", [KEY_F1])
	_key("frametime", [KEY_F3])
	_key("fullscreen", [KEY_F11])
	_key("reset_car", [KEY_T])

# ---------------------------------------------------------------- settings

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in settings.keys():
			settings[k] = cfg.get_value("settings", k, settings[k])

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)

func q() -> Dictionary:
	return QUALITY[clampi(int(settings.quality), 0, QUALITY.size() - 1)]

func apply_settings() -> void:
	var qq := q()
	var vp := get_viewport()
	vp.scaling_3d_scale = qq.scale
	vp.msaa_3d = Viewport.MSAA_2X if qq.msaa == 1 else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(qq.shadow_size, true)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.volume), 0.001)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	get_tree().call_group("quality_listener", "on_quality_changed")

## Mission state, fetched from Rust at most once per frame.
var _mstate := {}
var _mstate_frame := -1

func mstate() -> Dictionary:
	var f := Engine.get_process_frames()
	if f != _mstate_frame:
		_mstate_frame = f
		_mstate = sim.mission_state()
	return _mstate

func post_enabled() -> bool:
	return bool(settings.post) and bool(q().post)

## Full-screen post material (grade + PSX), configured from settings.
func make_post_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/post.gdshader")
	configure_post(m)
	return m

func configure_post(m: ShaderMaterial) -> void:
	var r := int(settings.retro)
	m.set_shader_parameter("psx_enabled", r > 0)
	m.set_shader_parameter("colors", 24 if r == 1 else 16)
	m.set_shader_parameter("dither_size", 1 if r == 1 else 2)
	m.set_shader_parameter("pixel_lines", 450.0 if r == 2 else 0.0)

func cycle_retro() -> String:
	settings.retro = (int(settings.retro) + 1) % RETRO_NAMES.size()
	save_settings()
	get_tree().call_group("quality_listener", "on_quality_changed")
	return RETRO_NAMES[int(settings.retro)]

func cycle_weather() -> String:
	var i := WEATHERS.find(str(settings.weather))
	settings.weather = WEATHERS[(i + 1) % WEATHERS.size()]
	save_settings()
	get_tree().call_group("weather_listener", "set_mode", settings.weather)
	return settings.weather

# ---------------------------------------------------------------- audio

func play_3d(name: String, pos: Vector3, db := 0.0, unit := 6.0, pitch := 1.0) -> AudioStreamPlayer3D:
	if not sfx.has(name):
		return null
	var p := _pool3d[_pool_i]
	_pool_i = (_pool_i + 1) % _pool3d.size()
	p.stop()
	p.stream = sfx[name]
	p.global_position = pos
	p.volume_db = db
	p.unit_size = unit
	p.pitch_scale = pitch
	p.play()
	return p

func play_2d(name: String, db := 0.0, pitch := 1.0) -> void:
	if not sfx.has(name):
		return
	var p := _pool2d[_pool2_i]
	_pool2_i = (_pool2_i + 1) % _pool2d.size()
	p.stream = sfx[name]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()

# ---------------------------------------------------------------- scenes

func goto(path: String) -> void:
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	await tw.finished
	get_tree().paused = false
	for p in _pool3d:
		p.stop()
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.4)
	await tw2.finished
	_fade.visible = false

func new_campaign() -> void:
	mode = "campaign"
	sim.new_campaign(int(Time.get_unix_time_from_system()) & 0x7fffffff)
	save_campaign()
	goto("res://scenes/war_room.tscn")

func continue_campaign() -> bool:
	mode = "campaign"
	if sim.load_campaign(ProjectSettings.globalize_path(SAVE_PATH)):
		goto("res://scenes/war_room.tscn")
		return true
	return false

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_campaign() -> void:
	if sim.has_campaign():
		sim.save_campaign(ProjectSettings.globalize_path(SAVE_PATH))

func free_play() -> void:
	mode = "free"
	goto("res://scenes/province.tscn")

# ---------------------------------------------------------------- overlays

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 50
	add_child(_overlay)
	_fps_label = Label.new()
	_fps_label.position = Vector2(8, 8)
	_fps_label.add_theme_font_override("font", mono)
	_fps_label.add_theme_font_size_override("font_size", 13)
	_fps_label.add_theme_color_override("font_color", Color("#7FCF8A"))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.visible = false
	_overlay.add_child(_fps_label)
	_tuning_panel = preload("res://scripts/tuning_panel.gd").new()
	_tuning_panel.visible = false
	_overlay.add_child(_tuning_panel)
	_fade = ColorRect.new()
	_fade.color = Color(0.04, 0.05, 0.05, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	var fl := CanvasLayer.new()
	fl.layer = 100
	add_child(fl)
	fl.add_child(_fade)

func tuning_open() -> bool:
	return _tuning_panel.visible

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("tuning"):
		_tuning_panel.visible = not _tuning_panel.visible
		if _tuning_panel.visible:
			_tuning_panel.call("refresh")
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			get_tree().call_group("mouse_owner", "recapture_mouse")
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("frametime"):
		_fps_label.visible = not _fps_label.visible
	elif e.is_action_pressed("fullscreen"):
		settings.fullscreen = not settings.fullscreen
		apply_settings()
		save_settings()

func _process(_dt: float) -> void:
	# The exchange trades while you play (levels and the war room).
	var cs := get_tree().current_scene
	if cs and not get_tree().paused and (cs is LevelBase or cs.name == "WarRoom"):
		sim.market_tick(_dt)
	if debug.has("shot") and Engine.get_process_frames() == int(debug.get("frames", "120")) - 3:
		get_tree().call_group("mouse_owner", "debug_relook")
	if debug.has("shot") and Engine.get_process_frames() == int(debug.get("frames", "120")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(debug.shot)
		print("saved ", debug.shot, " fps ", Engine.get_frames_per_second(), " draws ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " prims ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		get_tree().quit()
	if _fps_label.visible:
		var ms := 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_fps_label.text = "%d FPS  %.2f ms  draws %d  tris %dk  phys %.2f ms  [%s]" % [
			Engine.get_frames_per_second(), ms, draws, int(prims / 1000.0),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, q().name]
