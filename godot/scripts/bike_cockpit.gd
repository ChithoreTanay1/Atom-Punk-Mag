class_name BikeCockpit
extends Node3D
## The Shikra's front end, seen from the saddle: bars and grips that turn with
## the steering, and a pair of real gauges. The needle and the green readout
## both show true road speed. Parked and pursuit bikes never build the gauges.

const P = preload("res://scripts/palette.gd")
const GREEN := Color(0.45, 1.0, 0.68)
const AMBER := Color(1.0, 0.62, 0.2)
const SPEED_MAX := 180.0
const RPM_MAX := 12.0
## Pivot of the steering head, in the bike's Visual space.
const HEAD := Vector3(0, 1.02, -0.6)

var _bike: BikeController
var _dash: Node3D
var _speed_needle: Node3D
var _rpm_needle: Node3D
var _readout: Label3D
var _gear: Label3D
var _damage: Label3D
var _needle_speed := 0.0
var _needle_rpm := 0.0

func _ready() -> void:
	_bike = get_parent().get_parent() as BikeController
	position = HEAD
	var mi := MeshInstance3D.new()
	mi.mesh = bars_mesh()
	add_child(mi)
	set_process(false)

static func bars_mesh() -> Mesh:
	return Builder.cached("shikra_bars", func():
		var b := Builder.new(0.0)
		b.box(P.CHROME, Vector3(0, 0.06, 0.08), Vector3(0.74, 0.024, 0.024), false)
		for s in [-1, 1]:
			b.box(P.BLACK, Vector3(s * 0.33, 0.06, 0.08), Vector3(0.14, 0.036, 0.036), false)
			# Gloves on the grips.
			b.box(P.LEATHER, Vector3(s * 0.33, 0.07, 0.09), Vector3(0.09, 0.05, 0.06), false)
			b.box(P.LEATHER, Vector3(s * 0.33, 0.08, 0.14), Vector3(0.08, 0.04, 0.09), false)
		b.box(P.CHARCOAL, Vector3(0, 0.05, 0.03), Vector3(0.1, 0.05, 0.1), false)
		return b.mesh())

func activate(on: bool) -> void:
	if on and _dash == null:
		_build_gauges()
	if _dash:
		_dash.visible = on
	set_process(on)

func _dial(x: float, marks: Array) -> Node3D:
	var side := Basis(Vector3.RIGHT, PI / 2)
	var R := 0.062
	var b := Builder.new(0.0)
	b.cyl_xf(P.CHROME, Transform3D(side, Vector3(x, 0, -0.012)), R + 0.008, R + 0.008, 0.03, 24)
	b.cyl_xf(P.BLACK, Transform3D(side, Vector3(x, 0, 0.004)), R, R, 0.004, 24)
	var mi := MeshInstance3D.new()
	mi.mesh = b.mesh()
	_dash.add_child(mi)
	for i in marks.size():
		var k := float(i) / (marks.size() - 1)
		var ang := deg_to_rad(225.0 - 270.0 * k)
		_text(str(marks[i]), Vector3(x + cos(ang) * R * 0.74, sin(ang) * R * 0.74, 0.008), 0.0002, Color(0.9, 0.9, 0.85), 40)
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 0, 0.009)
	_dash.add_child(pivot)
	var nb := Builder.new(0.0)
	nb.box(P.TERRACOTTA, Vector3(0, R * 0.38, 0), Vector3(0.0035, R * 0.86, 0.002), false)
	var needle := MeshInstance3D.new()
	needle.mesh = nb.mesh()
	pivot.add_child(needle)
	return pivot

func _text(t: String, pos: Vector3, px: float, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.position = pos
	l.pixel_size = px
	l.modulate = col
	l.font_size = size
	l.outline_size = 0
	l.shaded = false
	l.no_depth_test = false
	_dash.add_child(l)
	return l

func _build_gauges() -> void:
	_dash = Node3D.new()
	_dash.position = Vector3(0, 0.15, 0.03)
	# Face the rider's eye, up over the tank.
	_dash.rotation.x = -0.5
	add_child(_dash)
	_speed_needle = _dial(-0.076, [0, 30, 60, 90, 120, 150, 180])
	_rpm_needle = _dial(0.076, [0, 2, 4, 6, 8, 10, 12])
	_text("KM/H", Vector3(-0.076, -0.03, 0.008), 0.00012, Color(0.7, 0.7, 0.66), 32)
	_text("x1000", Vector3(0.076, -0.03, 0.008), 0.00012, Color(0.7, 0.7, 0.66), 32)
	_readout = _text("0", Vector3(-0.076, -0.016, 0.009), 0.00026, GREEN, 48)
	_gear = _text("1", Vector3(0.076, -0.014, 0.009), 0.00026, AMBER, 48)
	_damage = _text("", Vector3(0, 0.062, 0.009), 0.00018, AMBER, 40)

func _process(dt: float) -> void:
	if _bike == null:
		return
	rotation.y = lerp_angle(rotation.y, _bike.get_steer_input() * 0.3, 1.0 - exp(-dt * 16.0))
	var kmh := _bike.get_speed() * 3.6
	_needle_speed = lerpf(_needle_speed, clampf(kmh / SPEED_MAX, 0.0, 1.0), 1.0 - exp(-dt * 10.0))
	_needle_rpm = lerpf(_needle_rpm, clampf(_bike.get_rpm() / (RPM_MAX * 1000.0), 0.0, 1.0), 1.0 - exp(-dt * 14.0))
	# Zero at lower left, sweeping clockwise; the needle points along +Y at rest.
	_speed_needle.rotation.z = deg_to_rad(135.0 - 270.0 * _needle_speed)
	_rpm_needle.rotation.z = deg_to_rad(135.0 - 270.0 * _needle_rpm)
	_readout.text = "%d" % int(round(kmh))
	_gear.text = str(_bike.get_gear())
	if _bike.get_hull() <= 0.0:
		_damage.text = "ENGINE DEAD"
	elif _bike.get_hull() < 0.35:
		_damage.text = "DAMAGED"
	else:
		_damage.text = ""
