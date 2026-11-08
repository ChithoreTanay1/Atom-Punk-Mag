extends Control
## Title: the frame story. A far-future archive model of Alexander's march
## has stalled at the Hyphasis; beyond it, Magadha. [Frame story INVENTED.]
## Behind the menu, a live slice of the simulation: the boulevard monument at
## dusk in the current weather, the camera drifting round it.

const U = preload("res://scripts/ui_style.gd")
const P = preload("res://scripts/palette.gd")

var _lines: PackedStringArray
var _shown := 0
var _char := 0
var _t := 0.0
var _text: Label
var _route: Control
var _blink := 0.0
var _cam: Camera3D
var _orbit := 0.6
var _post: ColorRect
var _weather: Weather
var _env: Environment

func _ready() -> void:
	add_to_group("quality_listener")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_backdrop()
	var ui := CanvasLayer.new()
	ui.layer = 11
	add_child(ui)
	var post_layer := CanvasLayer.new()
	post_layer.layer = 10
	add_child(post_layer)
	_post = ColorRect.new()
	_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.material = Game.make_post_material()
	(_post.material as ShaderMaterial).set_shader_parameter("vignette", 0.6)
	post_layer.add_child(_post)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# Left column: a dark gradient band with the title and the menu.
	var band := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.06, 0.06, 0.94))
	g.set_color(1, Color(0.05, 0.06, 0.06, 0.0))
	g.add_point(0.62, Color(0.05, 0.06, 0.06, 0.82))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	band.texture = gt
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.anchor_bottom = 1.0
	band.offset_right = 760
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)

	var left := VBoxContainer.new()
	left.anchor_bottom = 1.0
	left.offset_left = 72
	left.offset_top = 64
	left.offset_right = 520
	left.offset_bottom = -48
	left.add_theme_constant_override("separation", 0)
	root.add_child(left)
	left.add_child(U.label("ARCHIVE MODEL 326-B  //  EASTERN THEATRE", U.AMBER, 14))
	_gap(left, 14)
	var spaced := FontVariation.new()
	spaced.base_font = Game.mono
	spaced.spacing_glyph = 10
	spaced.variation_embolden = 0.6
	var title := Label.new()
	title.text = "MAGADHA"
	title.add_theme_font_override("font", spaced)
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_color_override("font_color", U.IVORY)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	left.add_child(title)
	var sub := U.label("Chanakya's war against the Nanda throne", Color(U.IVORY, 0.7), 18)
	left.add_child(sub)
	_gap(left, 22)
	var rule := ColorRect.new()
	rule.color = U.AMBER
	rule.custom_minimum_size = Vector2(120, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(rule)
	_gap(left, 30)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 4)
	left.add_child(menu)
	if Game.data_error != "":
		var err := U.label(Game.data_error, U.RED, 14)
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err.custom_minimum_size = Vector2(440, 0)
		menu.add_child(err)
	menu.add_child(_item("01", "New campaign", func(): Game.new_campaign()))
	var cont := _item("02", "Continue campaign", func(): Game.continue_campaign())
	cont.disabled = not Game.has_save()
	menu.add_child(cont)
	menu.add_child(_item("03", "Free play: Saptavarta", func():
		Game.sim.start_mission()
		Game.free_play()))
	menu.add_child(_item("04", "Free play: The Great Temple", func():
		Game.sim.start_mission_for("gov_hiranyavaha")
		Game.free_play()))
	menu.add_child(_item("05", "Feel test: expressway and test room", func():
		Game.mode = "free"
		Game.goto("res://scenes/test_track.tscn")))
	_gap(menu, 18)
	menu.add_child(U.label("SETTINGS", Color(U.IVORY, 0.45), 13))
	_gap(menu, 4)
	var qb: Button
	qb = _item("", "Quality      " + Game.q().name, func():
		Game.settings.quality = (int(Game.settings.quality) + 1) % Game.QUALITY.size()
		Game.apply_settings()
		Game.save_settings()
		qb.text = "     Quality      " + Game.q().name, 16)
	menu.add_child(qb)
	var rb: Button
	rb = _item("", "Retro filter " + Game.RETRO_NAMES[int(Game.settings.retro)], func():
		rb.text = "     Retro filter " + Game.cycle_retro(), 16)
	menu.add_child(rb)
	var wb: Button
	wb = _item("", "Weather      " + str(Game.settings.weather), func():
		wb.text = "     Weather      " + Game.cycle_weather(), 16)
	menu.add_child(wb)
	var fs: Button
	fs = _item("", "Fullscreen   " + ("on" if Game.settings.fullscreen else "off"), func():
		Game.settings.fullscreen = not Game.settings.fullscreen
		Game.apply_settings()
		Game.save_settings()
		fs.text = "     Fullscreen   " + ("on" if Game.settings.fullscreen else "off"), 16)
	menu.add_child(fs)
	_gap(menu, 18)
	menu.add_child(_item("", "Quit", func(): get_tree().quit()))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(U.label("F1 tuning   F3 frame time   F11 fullscreen", Color(U.IVORY, 0.4), 13))

	# Right: the route schematic and the archive log, fixed sizes so text wraps.
	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -660
	right.offset_right = -56
	right.offset_top = 64
	right.offset_bottom = -48
	right.add_theme_constant_override("separation", 16)
	root.add_child(right)
	var mp := _glass_panel(U.GREEN)
	right.add_child(mp)
	var mv := VBoxContainer.new()
	mp.add_child(mv)
	mv.add_child(U.label("MARCH SCHEMATIC", U.GREEN, 13))
	_route = Control.new()
	_route.custom_minimum_size = Vector2(560, 250)
	_route.draw.connect(_draw_route)
	mv.add_child(_route)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	var tp := _glass_panel(U.AMBER)
	right.add_child(tp)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	tp.add_child(tv)
	tv.add_child(U.label("ARCHIVE LOG", U.AMBER, 13))
	_text = U.label("", U.GREEN, 16)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(560, 200)
	_text.add_theme_constant_override("line_spacing", 4)
	tv.add_child(_text)
	_lines = Game.sim.frame_text()
	on_quality_changed()

func _gap(parent: Control, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	parent.add_child(c)

func _glass_panel(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.06, 0.82)
	sb.border_color = Color(accent, 0.7)
	sb.border_width_top = 2
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	return p

## Menu entry: transparent until hovered, amber bar and numeral.
func _item(num: String, text: String, cb: Callable, size := 22) -> Button:
	var b := Button.new()
	b.text = ("%s   %s" % [num, text]) if num != "" else "     " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", Game.mono)
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(440, 44 if size > 18 else 34)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0)
	n.border_color = Color(0, 0, 0, 0)
	n.border_width_left = 3
	n.content_margin_left = 14
	var h := n.duplicate()
	h.bg_color = Color(0.85, 0.59, 0.17, 0.14)
	h.border_color = U.AMBER
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_color_override("font_color", U.IVORY)
	b.add_theme_color_override("font_hover_color", U.AMBER)
	b.add_theme_color_override("font_pressed_color", U.AMBER)
	b.add_theme_color_override("font_focus_color", U.AMBER)
	b.add_theme_color_override("font_disabled_color", Color(U.IVORY, 0.25))
	b.mouse_entered.connect(func(): Game.play_2d("beep", -22, 1.6))
	b.pressed.connect(func():
		Game.play_2d("beep", -10)
		cb.call())
	return b

func on_quality_changed() -> void:
	if _post:
		_post.visible = Game.post_enabled()
		Game.configure_post(_post.material)

# ------------------------------------------------------------- backdrop

func _build_backdrop() -> void:
	var world := Node3D.new()
	add_child(world)
	P.mats()
	P.set_dusk(0.75)
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#10222E")
	sky_mat.sky_horizon_color = Color("#3E5662")
	sky_mat.ground_horizon_color = Color("#2C3E48")
	sky_mat.ground_bottom_color = Color("#22272A")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.5
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_light_color = Color("#223844")
	_env.fog_density = 0.016
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = _env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-14, -150, 0)
	sun.light_color = Color("#C9A27A")
	sun.light_energy = 0.25
	world.add_child(sun)
	var b := Builder.new()
	b.box(P.ROAD, Vector3(0, -0.5, 0), Vector3(300, 1, 300), false)
	for s in [-1, 1]:
		b.box(P.CONCRETE, Vector3(13 * s, 0.075, 0), Vector3(6, 0.15, 200), false)
	b.block(P.CONCRETE_PALE, Vector3(0, 0, 0), Vector3(5, 1.2, 5), false)
	b.cyl(P.CONCRETE, Vector3(0, 9.0, 0), 1.6, 0.9, 16, 10)
	b.cyl(P.STEEL, Vector3(0, 13.5, 0), 4.2, 4.2, 0.35, 28)
	b.cyl(P.AMBER, Vector3(0, 13.75, 0), 4.0, 4.0, 0.12, 28, false)
	b.cyl(P.STEEL, Vector3(0, 16.0, 0), 2.8, 2.8, 0.3, 24)
	b.cyl(P.BRASS, Vector3(0, 17.4, 0), 0.6, 0.0, 1.6, 12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for s in [-1, 1]:
		for i in 6:
			var z := -60.0 + i * 26.0
			var h := rng.randf_range(16, 40)
			b.block(P.CONCRETE_DARK, Vector3(28 * s, 0, z), Vector3(22, h, 22), false)
			b.box(P.WINDOWS, Vector3(28 * s - s * 11.06, h * 0.55, z), Vector3(0.1, h * 0.8, 18), false)
	for i in 14:
		var a := i * TAU / 14.0
		var r := rng.randf_range(120, 200)
		var h2 := rng.randf_range(40, 110)
		b.block(P.CONCRETE, Vector3(cos(a) * r, 0, sin(a) * r), Vector3(24, h2, 24), false)
		b.box(P.WINDOWS, Vector3(cos(a) * r, h2 * 0.5, sin(a) * r), Vector3(24.2, h2 * 0.8, 24.2), false)
	b.commit(world, "Backdrop")
	var lamps := []
	for s in [-1, 1]:
		for i in 8:
			lamps.append(Transform3D(Basis(Vector3.UP, 0.0 if s < 0 else PI), Vector3(s * 10.6, 0.15, -60 + i * 16)))
	Builder.scatter(world, Builder.lamp_post(), lamps, 200.0, false)
	var banners := []
	for i in 6:
		banners.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-15.6, 0.15, -52 + i * 20)))
	Builder.scatter(world, Builder.banner_pole(), banners, 200.0, false)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 13, 0)
	glow.omni_range = 18
	glow.light_color = Color("#D9962B")
	glow.light_energy = 1.4
	world.add_child(glow)
	_cam = Camera3D.new()
	_cam.fov = 62
	_cam.far = 400
	world.add_child(_cam)
	_cam.make_current()
	_weather = Weather.new()
	world.add_child(_weather)

func _process(dt: float) -> void:
	_blink += dt
	_orbit += dt * 0.035
	var r := 24.0
	_cam.position = Vector3(cos(_orbit) * r, 3.2 + sin(_orbit * 0.7) * 0.6, sin(_orbit) * r)
	_cam.look_at(Vector3(0, 10.0, 0))
	if _weather:
		_env.fog_light_color = Color("#223844").lerp(Color("#9AA3A6"), _weather.snow * 0.7 if _weather.mode == "snow" else 0.0)
	_route.queue_redraw()
	if _shown >= _lines.size():
		return
	_t += dt
	while _t > 0.02 and _shown < _lines.size():
		_t -= 0.02
		_char += 1
		if _char > _lines[_shown].length():
			_char = 0
			_shown += 1
			_t -= 0.45
	var out := ""
	for i in _shown:
		out += _lines[i] + "\n"
	if _shown < _lines.size():
		out += _lines[_shown].substr(0, _char) + ("_" if fmod(_blink, 0.6) < 0.3 else "")
	_text.text = out

## Schematic of the modelled march (not a map): west to east, ending at the
## Hyphasis, beyond which the model has nothing.
func _draw_route() -> void:
	var s := _route.size
	var f: Font = Game.mono
	var g := Color(U.GREEN, 0.9)
	var grid := Color(U.GREEN, 0.08)
	for i in 13:
		_route.draw_line(Vector2(i * s.x / 12.0, 0), Vector2(i * s.x / 12.0, s.y), grid)
	for i in 7:
		_route.draw_line(Vector2(0, i * s.y / 6.0), Vector2(s.x, i * s.y / 6.0), grid)
	var raw := [Vector2(0.04, 0.38), Vector2(0.11, 0.46), Vector2(0.19, 0.6), Vector2(0.28, 0.55), Vector2(0.36, 0.64),
		Vector2(0.44, 0.5), Vector2(0.51, 0.4), Vector2(0.57, 0.34), Vector2(0.61, 0.42)]
	var pts := PackedVector2Array()
	for p in raw:
		pts.append(Vector2(p.x * s.x, p.y * s.y))
	# Draw the march progressively, so it reads as a model replaying.
	var k := clampf(_blink / 4.0, 0.0, 1.0) * (pts.size() - 1)
	for i in pts.size() - 1:
		if float(i) >= k:
			break
		var e := pts[i].lerp(pts[i + 1], clampf(k - i, 0.0, 1.0))
		_route.draw_line(pts[i], e, g, 2.0)
	for i in pts.size():
		if float(i) <= k:
			_route.draw_rect(Rect2(pts[i] - Vector2(3, 3), Vector2(6, 6)), g)
	_route.draw_string(f, pts[0] + Vector2(-4, -12), "PELLA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, g)
	_route.draw_string(f, pts[4] + Vector2(-20, 22), "PERSIS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(g, 0.6))
	var end := pts[pts.size() - 1]
	var on := fmod(_blink, 1.0) < 0.6
	if k >= pts.size() - 1.01:
		_route.draw_circle(end, 7.0 if on else 4.0, Color(U.AMBER, 0.9))
		_route.draw_string(f, end + Vector2(-60, -16), "HYPHASIS  c.326 BCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, U.AMBER)
		_route.draw_string(f, end + Vector2(-60, 26), "MODEL STALLED", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, U.AMBER if on else Color(U.AMBER, 0.3))
	var east := Rect2(Vector2(s.x * 0.7, s.y * 0.12), Vector2(s.x * 0.28, s.y * 0.72))
	_route.draw_rect(east, Color(U.AMBER, 0.07))
	_route.draw_rect(east, Color(U.AMBER, 0.5), false, 1.0)
	_route.draw_string(f, east.position + Vector2(12, 24), "MAGADHA", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.AMBER)
	_route.draw_string(f, east.position + Vector2(12, 44), "UNRESOLVED", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(U.AMBER, 0.6))
