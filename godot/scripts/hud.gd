class_name Hud
extends CanvasLayer
## Cassette-futurist HUD: amber status strip, green readouts, detection
## arcs around the crosshair, subtitles, notebook (Tab), pause (Esc),
## debrief. Physical-looking panels, no holograms.

const AMBER := Color("#D9962B")
const GREEN := Color("#7FCF8A")
const IVORY := Color("#CFC5AE")
const RED := Color("#A5573A")
const PANEL := Color(0.07, 0.08, 0.08, 0.82)

var level: Node
var rig: PlayerRig
var player: FpsController

var _root: Control
var _arcs: Control
var _prompt: Label
var _status: Label
var _clock: Label
var _objectives: Label
var _subtitle: Label
var _feed: VBoxContainer
var _notebook: PanelContainer
var _notebook_text: RichTextLabel
var _pause: PanelContainer
var _debrief: PanelContainer
var _debrief_text: RichTextLabel
var _debrief_buttons: HBoxContainer
var _post: ColorRect
var _drive: Label
var _alarm_lamp: ColorRect
var _sub_t := 0.0
var _damage := 0.0
var _quality_btn: Button
var market: MarketPanel
var _tape: RichTextLabel
var _tape_clip: Control
var _tape_x := 0.0
var _tape_tick := -1
var _tape_flash := 0.0
var _tape_bg: ColorRect

func _ready() -> void:
	layer = 10
	add_to_group("quality_listener")
	add_to_group("market_listener")
	_post = ColorRect.new()
	_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.material = Game.make_post_material()
	add_child(_post)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_arcs = Control.new()
	_arcs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arcs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arcs.draw.connect(_draw_arcs)
	_root.add_child(_arcs)

	_prompt = _label(AMBER, 18)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(-300, 40)
	_prompt.size = Vector2(600, 30)
	_root.add_child(_prompt)

	var strip := _panel()
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_left = 16
	strip.offset_top = -92
	strip.offset_bottom = -16
	strip.offset_right = 520
	_root.add_child(strip)
	var sh := HBoxContainer.new()
	strip.add_child(sh)
	_alarm_lamp = ColorRect.new()
	_alarm_lamp.custom_minimum_size = Vector2(14, 14)
	_alarm_lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(_alarm_lamp)
	_status = _label(GREEN, 15)
	sh.add_child(_status)

	var tr := _panel()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -440
	tr.offset_right = -16
	tr.offset_top = 40
	_root.add_child(tr)
	var tv := VBoxContainer.new()
	tr.add_child(tv)
	_clock = _label(AMBER, 22)
	tv.add_child(_clock)
	_objectives = _label(IVORY, 14)
	_objectives.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objectives.custom_minimum_size = Vector2(400, 0)
	tv.add_child(_objectives)

	_subtitle = _label(IVORY, 19)
	_subtitle.anchor_left = 0.5
	_subtitle.anchor_right = 0.5
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.offset_left = -480
	_subtitle.offset_right = 480
	_subtitle.offset_top = -170
	_subtitle.offset_bottom = -110
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_subtitle)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(16, 120)
	_feed.custom_minimum_size = Vector2(520, 0)
	_root.add_child(_feed)

	_drive = _label(GREEN, 18)
	_drive.anchor_left = 1.0
	_drive.anchor_right = 1.0
	_drive.anchor_top = 1.0
	_drive.anchor_bottom = 1.0
	_drive.offset_left = -360
	_drive.offset_top = -80
	_drive.offset_right = -20
	_drive.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_drive)

	_build_tape()
	market = MarketPanel.new()
	market.closed.connect(toggle_market)
	add_child(market)
	_build_notebook()
	_build_pause()
	_build_debrief()
	on_quality_changed()

func setup(lvl: Node, r: PlayerRig, p: FpsController) -> void:
	level = lvl
	rig = r
	player = p
	rig.message.connect(message)
	rig.hurt.connect(func(_a): _damage = 1.0)

func on_quality_changed() -> void:
	_post.visible = Game.post_enabled()
	Game.configure_post(_post.material)

func _label(c: Color, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", Game.mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = AMBER.darkened(0.3)
	sb.border_width_left = 3
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _big_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.07, 0.96)
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	sb.set_content_margin_all(22)
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	return p

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", Game.mono)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	return b

# ------------------------------------------------------------- panels

func _build_notebook() -> void:
	_notebook = _big_panel()
	_notebook.offset_left = -470
	_notebook.offset_right = 470
	_notebook.offset_top = -330
	_notebook.offset_bottom = 330
	add_child(_notebook)
	_notebook_text = RichTextLabel.new()
	_notebook_text.bbcode_enabled = true
	_notebook_text.add_theme_font_override("normal_font", Game.mono)
	_notebook_text.add_theme_font_override("bold_font", Game.mono)
	_notebook_text.add_theme_font_size_override("normal_font_size", 15)
	_notebook_text.add_theme_font_size_override("bold_font_size", 16)
	_notebook_text.add_theme_color_override("default_color", GREEN)
	_notebook.add_child(_notebook_text)

func _build_pause() -> void:
	_pause = _big_panel()
	_pause.offset_left = -220
	_pause.offset_right = 220
	_pause.offset_top = -250
	_pause.offset_bottom = 250
	_pause.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_pause)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_pause.add_child(v)
	var t := _label(AMBER, 22)
	t.text = "SIMULATION PAUSED"
	v.add_child(t)
	v.add_child(_button("Resume", func(): toggle_pause()))
	_quality_btn = _button("", func():
		Game.settings.quality = (int(Game.settings.quality) + 1) % Game.QUALITY.size()
		Game.apply_settings()
		Game.save_settings()
		_quality_btn.text = "Quality: " + Game.q().name)
	_quality_btn.text = "Quality: " + Game.q().name
	v.add_child(_quality_btn)
	v.add_child(_button("Post-processing on/off", func():
		Game.settings.post = not bool(Game.settings.post)
		Game.apply_settings()
		Game.save_settings()))
	var rb: Button
	rb = _button("Retro filter: " + Game.RETRO_NAMES[int(Game.settings.retro)], func():
		rb.text = "Retro filter: " + Game.cycle_retro())
	v.add_child(rb)
	var wb: Button
	wb = _button("Weather: " + str(Game.settings.weather), func():
		wb.text = "Weather: " + Game.cycle_weather())
	v.add_child(wb)
	v.add_child(_button("Mouse sensitivity +", func(): _sens(1.15)))
	v.add_child(_button("Mouse sensitivity -", func(): _sens(1.0 / 1.15)))
	v.add_child(_button("Abandon (counts as failure)", func():
		get_tree().paused = false
		_pause.visible = false
		if level and level.has_method("abandon"):
			level.abandon()))
	v.add_child(_button("Quit to menu", func():
		Game.goto("res://scenes/main_menu.tscn")))

func _sens(f: float) -> void:
	var v: float = Game.sim.get_tuning("camera", "mouse_sensitivity") * f
	Game.sim.set_tuning("camera", "mouse_sensitivity", v)
	message("Mouse sensitivity %.4f (F1 to save)" % v)

func _build_debrief() -> void:
	_debrief = _big_panel()
	_debrief.offset_left = -430
	_debrief.offset_right = 430
	_debrief.offset_top = -260
	_debrief.offset_bottom = 260
	_debrief.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_debrief)
	var v := VBoxContainer.new()
	_debrief.add_child(v)
	_debrief_text = RichTextLabel.new()
	_debrief_text.bbcode_enabled = true
	_debrief_text.fit_content = true
	_debrief_text.custom_minimum_size = Vector2(800, 380)
	_debrief_text.add_theme_font_override("normal_font", Game.mono)
	_debrief_text.add_theme_font_override("bold_font", Game.mono)
	_debrief_text.add_theme_font_size_override("normal_font_size", 16)
	_debrief_text.add_theme_font_size_override("bold_font_size", 18)
	_debrief_text.add_theme_color_override("default_color", IVORY)
	v.add_child(_debrief_text)
	_debrief_buttons = HBoxContainer.new()
	_debrief_buttons.add_theme_constant_override("separation", 12)
	v.add_child(_debrief_buttons)

func show_debrief(bbcode: String, buttons: Array) -> void:
	_debrief_text.text = bbcode
	for c in _debrief_buttons.get_children():
		c.queue_free()
	for b in buttons:
		_debrief_buttons.add_child(_button(b[0], b[1]))
	_debrief.visible = true
	_notebook.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func toggle_pause() -> void:
	if _debrief.visible:
		return
	var p := not get_tree().paused
	get_tree().paused = p
	_pause.visible = p
	_notebook.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED

func toggle_notebook() -> void:
	if _debrief.visible or get_tree().paused:
		return
	_notebook.visible = not _notebook.visible
	if _notebook.visible:
		_fill_notebook()

func notebook_open() -> bool:
	return _notebook.visible or (market != null and market.visible)

func toggle_market() -> void:
	if _debrief.visible or get_tree().paused:
		return
	market.visible = not market.visible
	if market.visible:
		_notebook.visible = false
		market.refresh(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if player and player.enabled:
			player.set_active(false)
			player.set_meta("market_froze", true)
	else:
		if player and player.has_meta("market_froze"):
			player.remove_meta("market_froze")
			player.set_active(true)
		if level and level.has_method("recapture_mouse"):
			level.recapture_mouse()

# ------------------------------------------------------------- ticker tape

func _build_tape() -> void:
	_tape_bg = ColorRect.new()
	_tape_bg.color = Color(0.03, 0.035, 0.03, 0.88)
	_tape_bg.anchor_right = 1.0
	_tape_bg.offset_bottom = 26
	_tape_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tape_bg)
	var lab := Label.new()
	lab.text = "PTX"
	lab.position = Vector2(10, 3)
	lab.add_theme_font_override("font", Game.mono)
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	var tagbg := ColorRect.new()
	tagbg.color = AMBER
	tagbg.size = Vector2(46, 26)
	_tape_bg.add_child(tagbg)
	_tape_bg.add_child(lab)
	_tape_clip = Control.new()
	_tape_clip.clip_contents = true
	_tape_clip.anchor_right = 1.0
	_tape_clip.offset_left = 54
	_tape_clip.offset_bottom = 26
	_tape_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tape_bg.add_child(_tape_clip)
	_tape = RichTextLabel.new()
	_tape.bbcode_enabled = true
	_tape.fit_content = true
	_tape.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tape.scroll_active = false
	_tape.add_theme_font_override("normal_font", Game.mono)
	_tape.add_theme_font_size_override("normal_font_size", 15)
	_tape.position = Vector2(0, 3)
	_tape.size = Vector2(6000, 22)
	_tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tape_clip.add_child(_tape)

func _update_tape(dt: float) -> void:
	var st: Dictionary = Game.sim.market_state() if Engine.get_process_frames() % 20 == 0 or _tape_tick < 0 else {}
	if not st.is_empty() and int(st.tick) != _tape_tick:
		_tape_tick = int(st.tick)
		var t := ""
		for c in st.companies:
			var ch: float = c.change * 100.0
			var col := "#7FCF8A" if ch >= 0 else "#C8664A"
			t += "[color=#D9962B]%s[/color] [color=#CFC5AE]%s[/color] [color=%s]%s%.2f%%[/color]      " % [c.ticker, c.price_text, col, "+" if ch >= 0 else "", ch]
		for h in st.news.slice(0, 2):
			t += "[color=#E8C070]*** %s ***[/color]      " % str(h).to_upper()
		_tape.text = t + t
	_tape_x -= dt * 70.0
	var w := _tape.get_content_width() * 0.5
	if w > 10.0 and _tape_x < -w:
		_tape_x += w
	_tape.position.x = _tape_x
	_tape_flash = maxf(_tape_flash - dt, 0.0)
	_tape_bg.color = Color(0.03, 0.035, 0.03, 0.88).lerp(Color(0.35, 0.22, 0.05, 0.92), clampf(_tape_flash, 0.0, 1.0) * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)))

func on_market_news(headlines: PackedStringArray) -> void:
	for h in headlines:
		message("EXCHANGE: " + h)
	_tape_tick = -2
	_tape_flash = 2.5
	Game.play_2d("telex", -18, 1.2)

func _fill_notebook() -> void:
	var st: Dictionary = Game.mstate()
	var info: Dictionary = Game.sim.mission_info()
	var t := "[b][color=#D9962B]DOSSIER // %s[/color][/b]\n" % str(info.get("title", "FIELD TEST")).to_upper()
	if not info.is_empty():
		t += "TARGET: %s, governor of %s   PARANOIA %d\n%s\n\n" % [info.governor, info.province, int(info.paranoia), info.bio]
		t += "[color=#D9962B]OBJECTIVES[/color]\n"
		for o in st.get("objectives", []):
			t += "  > %s\n" % o
		t += "\n[color=#D9962B]INTEL %d/%d[/color]  (overhear him, or plant a Murmur Cassette)\n" % [st.intel.size(), int(st.intel_total)]
		for i in st.intel:
			t += "  [color=#CFC5AE]%s[/color]\n    %s\n" % [i.title, i.text]
		t += "\n[color=#D9962B]KIT[/color]\n"
		for g in st.gadgets:
			var d: Dictionary = Game.sim.gadget_def(g.id)
			t += "  %s x%d  %s\n" % [g.name, int(g.count), d.get("description", "")]
	t += "\n[color=#D9962B]CONTROLS[/color]\n"
	t += "  WASD move  SHIFT sprint  CTRL/C crouch (sprint+crouch = slide)  SPACE jump (hold at a ledge to mantle)\n"
	t += "  E use / enter car  F takedown  X draw/holster  LMB fire  RMB aim  R reload  B fire mode\n"
	t += "  Q next gadget  G use gadget  TAB dossier  ESC pause  F1 tuning  F3 frame time  T reset car\n"
	t += "\nAn armed or trespassing stranger is hostile. In the street you are just another clerk."
	_notebook_text.text = t

# ------------------------------------------------------------- feedback

func message(text: String) -> void:
	var l := _label(AMBER, 15)
	l.text = "> " + text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)

func subtitle(speaker: String, text: String, via_tape: bool) -> void:
	var tag := "[TAPE] " if via_tape else ""
	_subtitle.text = "%s%s: %s" % [tag, speaker.to_upper(), text]
	_subtitle.add_theme_color_override("font_color", GREEN if via_tape else IVORY)
	_sub_t = 5.0

func _process(dt: float) -> void:
	_update_tape(dt)
	_sub_t -= dt
	if _sub_t <= 0.0:
		_subtitle.text = ""
	_damage = maxf(_damage - dt * 1.5, 0.0)
	if _post.visible:
		(_post.material as ShaderMaterial).set_shader_parameter("damage", _damage)
	if rig == null or player == null:
		return
	var st: Dictionary = Game.mstate()
	var on_foot := player.enabled
	_prompt.text = rig.prompt if on_foot else ""
	var lines := []
	if not st.is_empty():
		var hp := int(round(float(st.health) / float(st.max_health) * 10.0))
		lines.append("HEALTH [%s%s]" % ["|".repeat(hp), ".".repeat(10 - hp)])
	var g := rig.current_gadget()
	var ammo_txt := ""
	if not st.is_empty():
		ammo_txt = "%02d/%02d" % [int(st.ammo), int(st.reserve)]
	else:
		ammo_txt = "%02d/--" % rig.free_ammo
	var wname: String = rig.weapon.get("name", "")
	lines.append("%s %s %s  %s" % [wname, "AUTO" if rig.auto_mode else "SEMI", ammo_txt, "DRAWN" if rig.drawn else "holstered (X)"])
	if not g.is_empty():
		lines.append("GADGET [Q] %s x%d  (G)" % [g.name, int(g.count)])
	_status.text = "\n".join(lines)
	var alarm: bool = st.get("alarm", false)
	_alarm_lamp.color = (RED if fmod(Time.get_ticks_msec() * 0.004, 2.0) < 1.0 else Color(0.2, 0.08, 0.06)) if alarm else Color(0.15, 0.25, 0.16)
	if not st.is_empty():
		_clock.text = "%s   %s" % [st.clock, "ALARM" if alarm else ""]
		var obj: PackedStringArray = st.objectives
		_objectives.text = "\n".join(Array(obj).map(func(o): return "> " + o))
	else:
		_clock.text = "FEEL TEST"
		_objectives.text = "> Movement and driving tuning track\n> F1 tuning panel, E to enter the car"
	_drive.text = ""
	if level and "car" in level and level.car and level.car.driver_active:
		var c: ArcadeCar = level.car
		var g2 := c.get_gear()
		_drive.text = "%3d KM/H  %s  %4d RPM" % [int(c.get_speed() * 3.6), "R" if g2 < 0 else str(g2), int(c.get_rpm())]
	_arcs.queue_redraw()

func _draw_arcs() -> void:
	if player == null or not player.enabled:
		return
	var cam := player.get_camera()
	var centre := _arcs.size * 0.5
	# Crosshair: four ticks placed at the true spread cone, a dot, hit marker.
	var half_fov := deg_to_rad(cam.fov * 0.5)
	var px := tan(deg_to_rad(rig.current_spread())) / tan(half_fov) * _arcs.size.y * 0.5
	var gap := 4.0 + px
	var a := clampf(1.0 - rig.ads * 1.6, 0.0, 1.0)
	if rig.drawn and a > 0.01:
		var c := Color(IVORY, 0.9 * a)
		var sh := Color(0, 0, 0, 0.45 * a)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_arcs.draw_line(centre + d * gap + Vector2(1, 1), centre + d * (gap + 9.0) + Vector2(1, 1), sh, 2.0)
			_arcs.draw_line(centre + d * gap, centre + d * (gap + 9.0), c, 2.0)
	_arcs.draw_circle(centre, 1.6, Color(IVORY, 0.9))
	if rig.hit_t > 0.0:
		var hc := RED.lightened(0.15) if rig.hit_kill else (AMBER if rig.hit_head else IVORY)
		var k := clampf(rig.hit_t / 0.16, 0.0, 1.0)
		var r0 := 7.0 + (1.0 - k) * 4.0 + (3.0 if rig.hit_kill else 0.0)
		var ln := 7.0 + (4.0 if rig.hit_kill else 0.0)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn: Vector2 = d.normalized()
			_arcs.draw_line(centre + dn * r0, centre + dn * (r0 + ln), Color(hc, minf(k * 1.5, 1.0)), 2.5 if rig.hit_kill else 2.0)
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	for n in get_tree().get_nodes_in_group("npc"):
		var npc := n as Npc
		if npc == null or not npc.alive:
			continue
		var lvl := npc.get_alert_level()
		var state := npc.get_alert_state()
		if lvl < 0.04 and state == 0:
			continue
		var to := npc.global_position - player.global_position
		if to.length() > 60.0:
			continue
		var ang := atan2(to.normalized().dot(right), to.normalized().dot(fwd))
		var col := AMBER if state < 3 else RED
		var r := 64.0
		var w := 0.32
		var fill := clampf(lvl, 0.1, 1.0)
		_arcs.draw_arc(centre, r, ang - PI / 2 - w * 0.5, ang - PI / 2 + w * 0.5, 10, Color(col, 0.25), 4.0)
		_arcs.draw_arc(centre, r, ang - PI / 2 - w * 0.5 * fill, ang - PI / 2 + w * 0.5 * fill, 10, Color(col, 0.95), 4.0)
