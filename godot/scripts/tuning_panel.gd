extends Control
## F1 debug tuning panel. Sliders are generated from the Rust tuning tables,
## so every number in data/tuning.ron is editable live. "Save" writes back.

var _tabs: TabContainer
var _status: Label
var _car_info: Label
var _building := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -440
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = -10
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.11, 0.11, 0.93)
	sb.border_color = Color("#D9962B")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var title := Label.new()
	title.text = "TUNING  [F1]   live, saved to data/tuning.ron"
	_style(title, Color("#D9962B"), 14)
	v.add_child(title)
	_car_info = Label.new()
	_style(_car_info, Color("#7FCF8A"), 12)
	v.add_child(_car_info)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	var row := HBoxContainer.new()
	v.add_child(row)
	var save := Button.new()
	save.text = "Save to file"
	save.pressed.connect(_on_save)
	row.add_child(save)
	var reset := Button.new()
	reset.text = "Reset tab"
	reset.pressed.connect(_on_reset)
	row.add_child(reset)
	_status = Label.new()
	_style(_status, Color("#7FCF8A"), 12)
	row.add_child(_status)

func _style(l: Label, c: Color, size: int) -> void:
	l.add_theme_font_override("font", Game.mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)

func refresh() -> void:
	_building = true
	var cur := _tabs.current_tab
	for c in _tabs.get_children():
		c.queue_free()
	for section in Game.sim.tuning_sections():
		var scroll := ScrollContainer.new()
		scroll.name = section.capitalize()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for f in Game.sim.tuning_fields(section):
			list.add_child(_slider(section, f))
		_tabs.add_child(scroll)
	if cur >= 0 and cur < _tabs.get_tab_count():
		_tabs.current_tab = cur
	_building = false

func _slider(section: String, f: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.tooltip_text = f.doc
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_l := Label.new()
	name_l.text = f.name
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style(name_l, Color("#CFC5AE"), 12)
	head.add_child(name_l)
	var val := Label.new()
	_style(val, Color("#D9962B"), 12)
	head.add_child(val)
	var s := HSlider.new()
	s.min_value = f.min
	s.max_value = f.max
	s.step = (float(f.max) - float(f.min)) / 400.0
	s.value = f.value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.text = _fmt(f.value)
	s.value_changed.connect(func(x: float) -> void:
		val.text = _fmt(x)
		if not _building:
			Game.sim.set_tuning(section, f.name, x))
	box.add_child(s)
	return box

func _fmt(x: float) -> String:
	if absf(x) >= 100.0:
		return "%.0f" % x
	if absf(x) >= 1.0:
		return "%.2f" % x
	return "%.4f" % x

func _on_save() -> void:
	var err: String = Game.sim.save_tuning()
	_status.text = "  saved" if err == "" else "  " + err

func _on_reset() -> void:
	var sections: PackedStringArray = Game.sim.tuning_sections()
	Game.sim.reset_tuning(sections[_tabs.current_tab])
	refresh()
	_status.text = "  reset (not saved)"

func _process(_dt: float) -> void:
	if not visible:
		return
	var cars := get_tree().get_nodes_in_group("vehicle")
	_car_info.text = ""
	for c in cars:
		if c.driver_active:
			_car_info.text = c.debug_text
