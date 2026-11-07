extends Control
## Expressway minimap: a green-on-charcoal radar plate in the cassette
## style, north-up (-Z, the direction of the spawn, is up). Shows the
## carriageway and lanes, walks, the viaduct with its ramps, the promenade
## and overpasses, building rows, traffic, parked Kestrels and you.
## Reads everything from the level each frame; owns no state.

const UI = preload("res://scripts/ui_style.gd")
const Expressway = preload("res://scripts/expressway.gd")
const SIZE := 240.0
## Pixels per metre.
const S := 1.55

var level: Node3D

const C_BG := Color("#151819")
const C_BLD := Color("#262C2D")
const C_WALK := Color("#30383A")
const C_ROAD := Color("#3B4547")
const C_LINE := Color(0.5, 0.81, 0.54, 0.55)
const C_VIA := Color(0.85, 0.59, 0.17, 0.22)
const C_VIA_EDGE := Color(0.85, 0.59, 0.17, 0.75)
const C_TRAFFIC := Color("#CFC5AE")

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -SIZE - 20.0
	offset_right = -20.0
	offset_top = -SIZE - 92.0
	offset_bottom = -92.0
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	visible = level != null and not get_tree().paused
	queue_redraw()

func _focus() -> Vector3:
	return level._focus()

## World (level-local) x/z to map pixels.
func _m(x: float, z: float, f: Vector3) -> Vector2:
	return Vector2(SIZE * 0.5 + (x - f.x) * S, SIZE * 0.5 + (z - f.z) * S)

func _band(x0: float, x1: float, c: Color, f: Vector3) -> void:
	var a := _m(x0, f.z - 200.0, f)
	var b := _m(x1, f.z + 200.0, f)
	draw_rect(Rect2(a, b - a), c)

func _box(x0: float, x1: float, z0: float, z1: float, c: Color, f: Vector3, filled := true) -> void:
	var a := _m(x0, z0, f)
	var b := _m(x1, z1, f)
	draw_rect(Rect2(a, b - a), c, filled, -1.0 if filled else 1.5)

func _draw() -> void:
	if level == null:
		return
	var f := _focus()
	var road: Expressway = level.road
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), C_BG)
	# Ground bands, left to right.
	_band(-Expressway.PAD, Expressway.BLD_L, C_BLD, f)
	_band(Expressway.BLD_L, -Expressway.ROAD_X, C_WALK, f)
	_band(-Expressway.ROAD_X, Expressway.ROAD_X, C_ROAD, f)
	_band(Expressway.ROAD_X, Expressway.ISLAND, C_WALK, f)
	_band(Expressway.ISLAND, Expressway.SVC_X1, C_ROAD, f)
	_band(Expressway.SVC_X1, Expressway.BLD_R, C_WALK, f)
	_band(Expressway.BLD_R, Expressway.PAD, C_BLD, f)
	# Building plots: a block every few tens of metres, hatched.
	var z := floorf((f.z - 90.0) / 12.0) * 12.0
	while z < f.z + 90.0:
		for x0: float in [-70.0, -50.0, 40.0, 60.0]:
			_box(x0, x0 + 14.0, z + 1.0, z + 10.0, Color("#2E3537"), f)
		z += 12.0
	# Lane lines: solid edges, scrolling dashes.
	for sx: float in [-1.0, 1.0]:
		for x: float in [Expressway.LANE0, Expressway.EDGE]:
			draw_line(_m(sx * x, f.z - 200.0, f), _m(sx * x, f.z + 200.0, f), C_LINE, 1.0)
		for k: float in [1.0, 2.0]:
			var dz := floorf((f.z - 90.0) / 8.0) * 8.0
			while dz < f.z + 90.0:
				var x := sx * (Expressway.LANE0 + Expressway.LANE_W * k)
				draw_line(_m(x, dz, f), _m(x, dz + 3.0, f), Color(C_LINE, 0.35), 1.0)
				dz += 8.0
	draw_line(_m(0, f.z - 200.0, f), _m(0, f.z + 200.0, f), Color("#7FCF8A"), 2.0)
	# Promenade (left, raised) and viaduct (right, raised).
	_box(Expressway.PROM_X0, Expressway.PROM_X1, f.z - 200.0, f.z + 200.0, Color(0.5, 0.81, 0.54, 0.08), f)
	var vx0 := Expressway.VIA_X - Expressway.VIA_W * 0.5
	var vx1 := Expressway.VIA_X + Expressway.VIA_W * 0.5
	_box(vx0, vx1, f.z - 200.0, f.z + 200.0, C_VIA, f)
	draw_line(_m(vx0, f.z - 200.0, f), _m(vx0, f.z + 200.0, f), C_VIA_EDGE, 1.0)
	draw_line(_m(vx1, f.z - 200.0, f), _m(vx1, f.z + 200.0, f), C_VIA_EDGE, 1.0)
	# Per-chunk features: overpasses, median gaps, ramps.
	var L := Expressway.L
	var i0 := int(floor((f.z - 100.0 + road.origin_z) / L))
	var i1 := int(floor((f.z + 100.0 + road.origin_z) / L))
	for i in range(i0, i1 + 1):
		var base := i * L - road.origin_z
		if posmod(i, 4) == 2:
			_box(Expressway.PROM_X1, Expressway.ISLAND, base + Expressway.OZ0, base + Expressway.OZ1, Color(0.5, 0.81, 0.54, 0.45), f)
		elif posmod(i, 8) == 5:
			_box(-1.0, 1.0, base + 44.0, base + 64.0, C_ROAD, f)
		elif posmod(i, 8) == 7 or posmod(i, 8) == 3:
			var up := posmod(i, 8) == 7
			_box(Expressway.RAMP_X0, Expressway.RAMP_X1, base, base + L, Color(0.85, 0.59, 0.17, 0.35), f)
			var fl := Expressway.ramp_span("up" if up else "down")
			_box(vx1, Expressway.RAMP_X1, base + fl.x, base + fl.y, Color(0.85, 0.59, 0.17, 0.6), f)
			var tip := _m((Expressway.RAMP_X0 + Expressway.RAMP_X1) * 0.5, base + (L * 0.35 if up else L * 0.65), f)
			var d := -1.0 if up else 1.0
			draw_colored_polygon(PackedVector2Array([tip + Vector2(0, d * 7), tip + Vector2(-4, -d * 3), tip + Vector2(4, -d * 3)]), UI.AMBER)
	# Traffic.
	if level.traffic:
		for c in level.traffic.cars:
			var body: Node3D = c.body
			if body.is_inside_tree():
				var p := _m(body.position.x, body.position.z, f)
				var half := Vector2(1.0, float(c.len) * 0.5) * S
				draw_rect(Rect2(p - half, half * 2.0), C_TRAFFIC)
	# Kestrels (yours glows amber when you're in it).
	for n in get_tree().get_nodes_in_group("cars"):
		var car := n as Node3D
		if car == null or (level.driving and car == level.car):
			continue
		var p := _m(car.global_position.x, car.global_position.z, f)
		draw_rect(Rect2(p - Vector2(1.6, 3.4), Vector2(3.2, 6.8)), UI.TEAL.lightened(0.3))
	# You.
	var yaw: float = level.car.rotation.y if level.driving else level.player.get_yaw()
	var me := _m(f.x, f.z, f)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var rt := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([me + fwd * 9.0, me - fwd * 5.0 + rt * 5.0, me - fwd * 2.5, me - fwd * 5.0 - rt * 5.0]), UI.AMBER)
	# Frame and readouts.
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(UI.AMBER, 0.7), false, 2.0)
	draw_rect(Rect2(0, 0, SIZE, 22), Color(C_BG, 0.85))
	draw_string(Game.mono, Vector2(8, 16), "A1 MAURYAN WAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.GREEN)
	var km := -(f.z + road.origin_z) / 1000.0
	draw_string(Game.mono, Vector2(8, 16), "KM %+.2f" % km, HORIZONTAL_ALIGNMENT_RIGHT, SIZE - 16.0, 13, UI.AMBER)
	var lvl := "VIADUCT" if f.y > 8.0 else ("PROMENADE" if f.y > 5.0 else "GRADE")
	draw_rect(Rect2(0, SIZE - 20, SIZE, 20), Color(C_BG, 0.85))
	draw_string(Game.mono, Vector2(8, SIZE - 6), lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.IVORY)
	draw_string(Game.mono, Vector2(8, SIZE - 6), "N ^", HORIZONTAL_ALIGNMENT_RIGHT, SIZE - 16.0, 12, UI.GREY)
