class_name UiStyle
## Shared look for menus: charcoal panels, amber rules, green readouts,
## monospace type. Flat and physical; no scanline shader outside in-world screens.

const BG := Color("#151819")
const PANEL := Color("#1F2425")
const AMBER := Color("#D9962B")
const GREEN := Color("#7FCF8A")
const IVORY := Color("#CFC5AE")
const GREY := Color("#7B7B76")
const RED := Color("#A5573A")
const TEAL := Color("#3E7777")

static func label(text: String, c := IVORY, size := 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Game.mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l

static func panel(border := AMBER) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = border.darkened(0.25)
	sb.border_width_top = 2
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p

static func button(text: String, cb: Callable, size := 17) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", Game.mono)
	b.add_theme_font_size_override("font_size", size)
	var n := StyleBoxFlat.new()
	n.bg_color = Color("#262B2C")
	n.border_color = Color("#3A4042")
	n.border_width_left = 4
	n.set_content_margin_all(8)
	var h := n.duplicate()
	h.bg_color = Color("#2F3536")
	h.border_color = AMBER
	var pr := n.duplicate()
	pr.bg_color = Color("#3A3024")
	pr.border_color = AMBER
	var d := n.duplicate()
	d.bg_color = Color("#1C1F20")
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_color_override("font_color", IVORY)
	b.add_theme_color_override("font_hover_color", AMBER)
	b.add_theme_color_override("font_disabled_color", Color("#55595A"))
	b.pressed.connect(func():
		Game.play_2d("beep", -10)
		cb.call())
	return b

## Segmented analogue-style bar, e.g. [||||||....]
static func bar(value: float, maxv: float, segs := 20) -> String:
	var n := clampi(int(round(value / maxf(maxv, 0.001) * segs)), 0, segs)
	return "[" + "|".repeat(n) + ".".repeat(segs - n) + "]"
