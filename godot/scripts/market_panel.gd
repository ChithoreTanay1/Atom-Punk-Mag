class_name MarketPanel
extends PanelContainer
## The exchange terminal: a green-on-charcoal quote board in the style of an
## early-80s trading desk. Prices in eighths, sparkline per listing, trades
## in lots. Reads everything from GameSim.market_state(); owns no state.

const AMBER := Color("#D9962B")
const GREEN := Color("#7FCF8A")
const IVORY := Color("#CFC5AE")
const RED := Color("#C8664A")
const DIM := Color("#6E746F")

signal closed

var _hdr: Label
var _rows: VBoxContainer
var _news: Label
var _detail: Label
var _status: Label
var _lot := 10
var _lot_btn: Button
var _row_nodes := {}  # id -> {ticker, name, price, chg, held, spark}
var _selected := ""
var _state := {}
var _last_tick := -1

func _init() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -640
	offset_right = 640
	offset_top = -360
	offset_bottom = 360
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.055, 0.05, 0.97)
	sb.border_color = GREEN.darkened(0.35)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_hdr = _lab("", AMBER, 18)
	_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_hdr)
	_lot_btn = _btn("LOT 10", func():
		_lot = 100 if _lot == 10 else (1 if _lot == 100 else 10)
		_lot_btn.text = "LOT %d" % _lot)
	top.add_child(_lot_btn)
	top.add_child(_btn("CLOSE  [M]", func(): closed.emit()))
	_status = _lab("", GREEN, 15)
	v.add_child(_status)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 18)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.6
	cols.add_child(left)
	var head := _row_box()
	for h in [["TICKER", 70], ["COMPANY", 290], ["LAST", 96], ["CHG", 76], ["SESSION", 130], ["HELD", 60], ["", 150]]:
		var l := _lab(h[0], DIM, 12)
		l.custom_minimum_size = Vector2(h[1], 0)
		head.add_child(l)
	left.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	right.add_child(_lab("LISTING", AMBER, 13))
	_detail = _lab("Select a listing.", IVORY, 14)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.clip_text = false
	_detail.custom_minimum_size = Vector2(300, 150)
	right.add_child(_detail)
	right.add_child(_lab("TELEX // MARKET WIRE", AMBER, 13))
	_news = _lab("", GREEN, 13)
	_news.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_news.clip_text = false
	_news.custom_minimum_size = Vector2(300, 0)
	right.add_child(_news)
	_build_rows()

func _lab(t: String, c: Color, size: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", Game.mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.clip_text = true
	return l

func _btn(t: String, cb: Callable, size := 13) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_override("font", Game.mono)
	b.add_theme_font_size_override("font_size", size)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.1, 0.13, 0.11)
	n.border_color = GREEN.darkened(0.5)
	n.set_border_width_all(1)
	n.set_content_margin_all(5)
	var h := n.duplicate()
	h.bg_color = Color(0.16, 0.2, 0.15)
	h.border_color = GREEN
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", n)
	b.add_theme_color_override("font_color", GREEN)
	b.add_theme_color_override("font_hover_color", AMBER)
	b.pressed.connect(func():
		Game.play_2d("beep", -14, 1.3)
		cb.call())
	return b

func _row_box() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	return h

func _build_rows() -> void:
	_state = Game.sim.market_state()
	if _state.is_empty():
		_status.text = "EXCHANGE OFFLINE"
		return
	for c in _state.companies:
		var row := _row_box()
		var sel := Button.new()
		sel.flat = true
		sel.text = c.ticker
		sel.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sel.custom_minimum_size = Vector2(70, 0)
		sel.add_theme_font_override("font", Game.mono)
		sel.add_theme_font_size_override("font_size", 15)
		sel.add_theme_color_override("font_color", AMBER)
		sel.add_theme_color_override("font_hover_color", IVORY)
		var id: String = c.id
		sel.pressed.connect(func():
			_selected = id
			refresh(true))
		row.add_child(sel)
		var name := _lab(c.name, IVORY, 14)
		name.custom_minimum_size = Vector2(290, 0)
		row.add_child(name)
		var price := _lab("", IVORY, 15)
		price.custom_minimum_size = Vector2(96, 0)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(price)
		var chg := _lab("", GREEN, 14)
		chg.custom_minimum_size = Vector2(76, 0)
		chg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(chg)
		var spark := Control.new()
		spark.custom_minimum_size = Vector2(130, 24)
		spark.draw.connect(func(): _draw_spark(spark, id))
		row.add_child(spark)
		var held := _lab("", DIM, 14)
		held.custom_minimum_size = Vector2(60, 0)
		held.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(held)
		row.add_child(_btn("BUY", func(): _trade(id, _lot)))
		row.add_child(_btn("SELL", func(): _trade(id, -_lot)))
		_rows.add_child(row)
		_row_nodes[id] = {"price": price, "chg": chg, "held": held, "spark": spark}
	_selected = str(_state.companies[0].id)
	refresh(true)

func _trade(id: String, qty: int) -> void:
	var err: String = Game.sim.market_trade(id, qty)
	if err != "":
		_status.text = "REJECTED: " + err
		Game.play_2d("beep_low", -8)
	else:
		Game.play_2d("telex", -16, 1.4)
		_selected = id
	refresh(true)

func refresh(force := false) -> void:
	if not visible and not force:
		return
	_state = Game.sim.market_state()
	if _state.is_empty():
		return
	if not force and int(_state.tick) == _last_tick:
		return
	_last_tick = int(_state.tick)
	var cash: float = _state.cash
	var port: float = _state.portfolio
	var net := cash + port - float(_state.start_cash)
	_hdr.text = "%s   //   TICK %d" % [str(_state.exchange).to_upper(), int(_state.tick)]
	if not _status.text.begins_with("REJECTED") or force:
		_status.text = "CASH %s %s    HOLDINGS %s    NET %s%s" % [
			"%.2f" % cash, _state.currency, "%.2f" % port, "+" if net >= 0 else "", "%.2f" % net]
	for c in _state.companies:
		var n: Dictionary = _row_nodes.get(c.id, {})
		if n.is_empty():
			continue
		var ch: float = c.change * 100.0
		n.price.text = c.price_text
		n.chg.text = "%s%.2f%%" % ["+" if ch >= 0 else "", ch]
		n.chg.add_theme_color_override("font_color", GREEN if ch >= 0 else RED)
		n.held.text = str(int(c.held)) if int(c.held) > 0 else "-"
		n.held.add_theme_color_override("font_color", AMBER if int(c.held) > 0 else DIM)
		n.spark.queue_redraw()
		if c.id == _selected:
			var pl := ""
			if int(c.held) > 0:
				var gain := (float(c.price) - float(c.avg_cost)) * int(c.held)
				pl = "\nPosition: %d @ %.2f   P/L %s%.2f" % [int(c.held), float(c.avg_cost), "+" if gain >= 0 else "", gain]
			_detail.text = "%s (%s)\n%s\n\n%s\nLast %s   Open %.2f%s" % [c.name, c.ticker, c.sector, c.description, c.price_text, float(c.open), pl]
	var lines := []
	for h in _state.news:
		lines.append("> " + h)
	_news.text = "\n".join(lines) if not lines.is_empty() else "> Quiet on the wire."

func _process(_dt: float) -> void:
	if visible:
		refresh()

func _draw_spark(ctl: Control, id: String) -> void:
	var c: Dictionary = {}
	for x in _state.get("companies", []):
		if x.id == id:
			c = x
			break
	if c.is_empty():
		return
	var h: PackedFloat32Array = c.history
	if h.size() < 2:
		return
	var lo := h[0]
	var hi := h[0]
	for p in h:
		lo = minf(lo, p)
		hi = maxf(hi, p)
	var span := maxf(hi - lo, 0.0001)
	var s := ctl.size
	var pts := PackedVector2Array()
	for i in h.size():
		pts.append(Vector2(float(i) / (h.size() - 1) * s.x, s.y - 2.0 - (h[i] - lo) / span * (s.y - 4.0)))
	var up: bool = h[h.size() - 1] >= float(c.open)
	var oy := s.y - 2.0 - (float(c.open) - lo) / span * (s.y - 4.0)
	ctl.draw_line(Vector2(0, oy), Vector2(s.x, oy), Color(DIM, 0.4), 1.0)
	ctl.draw_polyline(pts, GREEN if up else RED, 1.5)
