extends Control
## Title: the frame story. A far-future archive model of Alexander's march
## has stalled at the Hyphasis; beyond it, Magadha. [Frame story INVENTED.]

const U = preload("res://scripts/ui_style.gd")

var _lines: PackedStringArray
var _shown := 0
var _char := 0
var _t := 0.0
var _text: Label
var _route: Control
var _blink := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = U.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	margin.add_child(cols)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	var title := U.label(Game.sim.campaign_title() if Game.data_error == "" else "DATA ERROR", U.AMBER, 30)
	left.add_child(title)
	left.add_child(U.label("Chanakya's war against the throne of Magadha", U.GREY, 15))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 28)
	left.add_child(sp)
	if Game.data_error != "":
		var err := U.label(Game.data_error, U.RED, 14)
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(err)
	left.add_child(U.button("New campaign", func(): Game.new_campaign()))
	var cont := U.button("Continue campaign", func(): Game.continue_campaign())
	cont.disabled = not Game.has_save()
	left.add_child(cont)
	left.add_child(U.button("Free play: Saptavarta", func():
		Game.sim.start_mission()
		Game.free_play()))
	left.add_child(U.button("Feel test: track and test room", func():
		Game.mode = "free"
		Game.goto("res://scenes/test_track.tscn")))
	var qb: Button
	qb = U.button("Quality: " + Game.q().name, func():
		Game.settings.quality = (int(Game.settings.quality) + 1) % Game.QUALITY.size()
		Game.apply_settings()
		Game.save_settings()
		qb.text = "Quality: " + Game.q().name)
	left.add_child(qb)
	var fs: Button
	fs = U.button("Fullscreen: " + ("on" if Game.settings.fullscreen else "off"), func():
		Game.settings.fullscreen = not Game.settings.fullscreen
		Game.apply_settings()
		Game.save_settings()
		fs.text = "Fullscreen: " + ("on" if Game.settings.fullscreen else "off"))
	left.add_child(fs)
	left.add_child(U.button("Quit", func(): get_tree().quit()))
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp2)
	left.add_child(U.label("F1 tuning  F3 frame time  F11 fullscreen", U.GREY, 13))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 16)
	cols.add_child(right)
	var mp := U.panel(U.GREEN)
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(mp)
	_route = Control.new()
	_route.custom_minimum_size = Vector2(0, 300)
	_route.draw.connect(_draw_route)
	mp.add_child(_route)
	var tp := U.panel()
	right.add_child(tp)
	_text = U.label("", U.GREEN, 16)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0, 190)
	tp.add_child(_text)
	_lines = Game.sim.frame_text()

func _process(dt: float) -> void:
	_blink += dt
	_route.queue_redraw()
	if _shown >= _lines.size():
		return
	_t += dt
	while _t > 0.018 and _shown < _lines.size():
		_t -= 0.018
		_char += 1
		if _char > _lines[_shown].length():
			_char = 0
			_shown += 1
			_t -= 0.35
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
	var pts := PackedVector2Array()
	var raw := [Vector2(0.05, 0.42), Vector2(0.12, 0.5), Vector2(0.2, 0.62), Vector2(0.3, 0.58), Vector2(0.38, 0.66),
		Vector2(0.47, 0.52), Vector2(0.55, 0.42), Vector2(0.62, 0.36), Vector2(0.68, 0.44), Vector2(0.72, 0.4)]
	for p in raw:
		pts.append(Vector2(p.x * s.x, p.y * s.y))
	var g := Color(U.GREEN, 0.9)
	var grid := Color(U.GREEN, 0.07)
	for i in 21:
		_route.draw_line(Vector2(i * s.x / 20.0, 0), Vector2(i * s.x / 20.0, s.y), grid)
	for i in 11:
		_route.draw_line(Vector2(0, i * s.y / 10.0), Vector2(s.x, i * s.y / 10.0), grid)
	_route.draw_polyline(pts, g, 2.0)
	for p in pts:
		_route.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), g)
	var f := Game.mono
	_route.draw_string(f, pts[0] + Vector2(-10, -14), "PELLA", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, g)
	var end := pts[pts.size() - 1]
	var on := fmod(_blink, 1.0) < 0.6
	_route.draw_circle(end, 7.0 if on else 4.0, Color(U.AMBER, 0.9))
	_route.draw_string(f, end + Vector2(-40, -18), "HYPHASIS  c.326 BCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, U.AMBER)
	_route.draw_string(f, end + Vector2(-40, 30), "MODEL STALLED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, U.AMBER if on else Color(U.AMBER, 0.3))
	var east := Rect2(Vector2(end.x + 30, s.y * 0.15), Vector2(s.x - end.x - 50, s.y * 0.7))
	_route.draw_rect(east, Color(U.AMBER, 0.06))
	_route.draw_rect(east, Color(U.AMBER, 0.4), false, 1.0)
	_route.draw_string(f, east.position + Vector2(10, 22), "MAGADHA", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, U.AMBER)
	_route.draw_string(f, east.position + Vector2(10, 42), "UNRESOLVED", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(U.AMBER, 0.6))
	_route.draw_string(f, Vector2(10, s.y - 10), "SCHEMATIC // ARCHIVE MODEL 326-B", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(U.GREEN, 0.5))
