extends Control
## Chanakya's war room: the strategic layer. Order agent operations against
## governors, send the field agent to Saptavarta, end the night.
## Design source: Arthashastra (DESIGN, not Nanda-era fact).

const U = preload("res://scripts/ui_style.gd")

var _state := {}
var _selected_gov := ""
var _hdr: Label
var _govs: VBoxContainer
var _ops: VBoxContainer
var _log: RichTextLabel
var _detail: Label
var _mission_btn: Button
var _end_btn: Button
var _market: MarketPanel
var _overlay: PanelContainer
var _overlay_text: RichTextLabel
var _ended := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_market = MarketPanel.new()
	_market.closed.connect(func(): _market.visible = false)
	add_child.call_deferred(_market)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = U.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := U.label("WAR ROOM // CHANAKYA'S HOUSE", U.AMBER, 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(U.button("Main menu", func(): Game.goto("res://scenes/main_menu.tscn"), 14))
	_hdr = U.label("", U.GREEN, 16)
	v.add_child(_hdr)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	v.add_child(cols)

	var gp := U.panel()
	gp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gp.size_flags_stretch_ratio = 1.4
	cols.add_child(gp)
	var gs := ScrollContainer.new()
	gp.add_child(gs)
	_govs = VBoxContainer.new()
	_govs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gs.add_child(_govs)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	cols.add_child(mid)
	var op := U.panel(U.GREEN)
	op.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(op)
	var ov := VBoxContainer.new()
	op.add_child(ov)
	ov.add_child(U.label("AGENT OPERATIONS", U.AMBER, 16))
	_detail = U.label("", U.GREY, 13)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov.add_child(_detail)
	_ops = VBoxContainer.new()
	_ops.add_theme_constant_override("separation", 6)
	ov.add_child(_ops)
	_mission_btn = U.button("", _go_mission, 18)
	mid.add_child(_mission_btn)
	_end_btn = U.button("End the night", _end_night, 18)
	mid.add_child(_end_btn)
	mid.add_child(U.button("Pataliputra Exchange", func():
		_market.visible = not _market.visible
		_market.refresh(true), 16))

	var lp := U.panel()
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(lp)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.add_theme_font_override("normal_font", Game.mono)
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_color_override("default_color", U.IVORY)
	lp.add_child(_log)

	_overlay = PanelContainer.new()
	_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_overlay.anchor_left = 0.5
	_overlay.anchor_right = 0.5
	_overlay.anchor_top = 0.5
	_overlay.anchor_bottom = 0.5
	_overlay.offset_left = -420
	_overlay.offset_right = 420
	_overlay.offset_top = -240
	_overlay.offset_bottom = 240
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.07, 0.98)
	sb.border_color = U.AMBER
	sb.set_border_width_all(2)
	sb.set_content_margin_all(22)
	_overlay.add_theme_stylebox_override("panel", sb)
	_overlay.visible = false
	add_child(_overlay)
	var ovv := VBoxContainer.new()
	_overlay.add_child(ovv)
	_overlay_text = RichTextLabel.new()
	_overlay_text.bbcode_enabled = true
	_overlay_text.custom_minimum_size = Vector2(790, 380)
	_overlay_text.add_theme_font_override("normal_font", Game.mono)
	_overlay_text.add_theme_font_override("bold_font", Game.mono)
	_overlay_text.add_theme_font_size_override("normal_font_size", 15)
	_overlay_text.add_theme_font_size_override("bold_font_size", 18)
	_overlay_text.add_theme_color_override("default_color", U.IVORY)
	ovv.add_child(_overlay_text)
	ovv.add_child(U.button("Continue", func():
		if _ended:
			Game.goto("res://scenes/main_menu.tscn")
			return
		_overlay.visible = false
		_check_outcome()))
	if Game.debug.has("newcamp") and not Game.sim.has_campaign():
		Game.sim.new_campaign(7)
	refresh()
	_check_outcome()

func refresh() -> void:
	_state = Game.sim.campaign_state()
	if _state.is_empty():
		return
	_hdr.text = "NIGHT %d/%d   KING'S STABILITY %s %d (victory at %d)   HEAT %s %d   GOLD %d   AGENTS %d" % [
		int(_state.night), int(_state.max_nights), U.bar(_state.stability, 100.0, 16), int(_state.stability),
		int(_state.victory_stability), U.bar(_state.heat, 100.0, 10), int(_state.heat), int(_state.gold), int(_state.agents)]
	for c in _govs.get_children():
		c.queue_free()
	_govs.add_child(U.label("GOVERNORS OF THE KING", U.AMBER, 16))
	for g in _state.governors:
		_govs.add_child(_gov_card(g))
	for c in _ops.get_children():
		c.queue_free()
	var target_name := ""
	for g in _state.governors:
		if g.id == _selected_gov:
			target_name = g.name
	_detail.text = "Target: %s" % (target_name if target_name != "" else "(select a governor on the left)")
	for o in _state.ops:
		var cost := "%dg %da  %d%%" % [int(o.cost_gold), int(o.cost_agents), int(float(o.success) * 100)]
		var b := U.button("%s   %s" % [o.name, cost], func(): _run_op(o), 14)
		b.tooltip_text = o.description
		b.disabled = o.used or int(o.cost_gold) > int(_state.gold) or int(o.cost_agents) > int(_state.agents) or (o.needs_target and _selected_gov == "") or _state.outcome != ""
		_ops.add_child(b)
	var tgt: String = _state.mission_target
	var tname := ""
	for g in _state.governors:
		if g.id == tgt:
			tname = g.name
	if tgt == "":
		_mission_btn.text = "Field operation: no target in reach"
		_mission_btn.disabled = true
	elif _state.mission_done:
		_mission_btn.text = "Field operation done tonight"
		_mission_btn.disabled = true
	else:
		_mission_btn.text = "> FIELD OPERATION: Saptavarta (%s)" % tname
		_mission_btn.disabled = _state.outcome != ""
	_end_btn.disabled = _state.outcome != ""
	var log := ""
	for l in _state.log:
		log += l + "\n"
	if not _state.rumors.is_empty():
		log = "[color=#D9962B]RUMORS IN THE BAZAARS[/color]\n" + "".join(_state.rumors.map(func(r): return "  %s  \"%s\"\n" % [U.bar(r.spread, 1.0, 8), r.text])) + "\n" + log
	_log.text = log

func _gov_card(g: Dictionary) -> Control:
	var serving: bool = g.status == "serving"
	var sel: bool = g.id == _selected_gov
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", Game.mono)
	b.add_theme_font_size_override("font_size", 13)
	var status: String = g.status.to_upper().replace("_", " ").replace(":", ": ")
	var lines := "%s%s, %s of %s%s\n" % ["> " if sel else "", g.name, g.title, g.province, "  [MISSION]" if g.has_mission and serving else ""]
	if serving:
		lines += "  loyalty %s %d   paranoia %d   discord %d\n  rival: %s" % [U.bar(g.loyalty, 100.0, 12), int(g.loyalty), int(g.paranoia), int(g.discord), g.rival if str(g.rival) != "" else "none"]
	else:
		lines += "  %s" % status
	b.text = lines
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2A2620") if sel else Color("#202425")
	sb.border_color = UiStyle.AMBER if sel else (UiStyle.GREEN.darkened(0.4) if serving else Color("#3A3A3A"))
	sb.border_width_left = 4
	sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", UiStyle.IVORY if serving else UiStyle.GREY)
	b.tooltip_text = g.bio
	b.disabled = not serving
	b.pressed.connect(func():
		_selected_gov = g.id
		Game.play_2d("beep", -12)
		refresh())
	return b

func _run_op(o: Dictionary) -> void:
	var r: Dictionary = Game.sim.run_op(o.id, _selected_gov if o.needs_target else "")
	Game.save_campaign()
	Game.play_2d("telex" if r.get("ok", false) else "beep_low", -8)
	refresh()
	_check_outcome()

func _go_mission() -> void:
	if Game.sim.start_mission():
		Game.mode = "campaign"
		Game.goto("res://scenes/province.tscn")

func _end_night() -> void:
	var lines: PackedStringArray = Game.sim.end_night()
	_market.refresh(true)
	Game.save_campaign()
	refresh()
	var t := "[b][color=#D9962B]DAWN. NIGHT %d BEGINS AT DUSK.[/color][/b]\n\n" % int(_state.night)
	if lines.is_empty():
		t += "A quiet night. Nothing reaches the war room but the rain."
	for l in lines:
		t += "> %s\n\n" % l
	_overlay_text.text = t
	_overlay.visible = true

func _check_outcome() -> void:
	if _state.is_empty() or _state.outcome == "" or _overlay.visible:
		return
	_ended = true
	var win: bool = _state.outcome == "Victory"
	_overlay_text.text = "[b][color=%s]%s[/color][/b]\n\n%s\n\nNights: %d   Stability: %d   Heat: %d" % [
		"#7FCF8A" if win else "#A5573A", "THE EAST RESOLVES" if win else "SIMULATION HALTED",
		_state.outcome_text, int(_state.night), int(_state.stability), int(_state.heat)]
	_overlay.visible = true
