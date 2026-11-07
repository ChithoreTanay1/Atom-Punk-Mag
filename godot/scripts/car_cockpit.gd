class_name CarCockpit
extends Node3D
## The Kestrel 80's cabin and first-person driving view. Layout follows the
## reference in refs/ (an 80s burgundy interior): wide binnacle with two
## electronic gauges in green rings and a green VFD speed readout between
## them, four-spoke burgundy wheel with a square pad, centre stack with
## vents, an amber VFD climate strip and a cassette deck, T-bar shifter.
## Left-hand drive. One batched mesh for the static cabin; the wheel,
## needles and readouts are the only moving parts.
##
## V toggles between this view and the chase camera.

const P = preload("res://scripts/palette.gd")
const EYE := Vector3(-0.38, 0.72, 0.42)
const VFD_GREEN := Color(0.45, 1.0, 0.68)
const VFD_AMBER := Color(1.0, 0.62, 0.2)

var active := false
var cam: Camera3D
var _car: ArcadeCar
var _wheel: Node3D
var _speedo: Node3D
var _tach: Node3D
var _vfd: Label3D
var _gear: Label3D
var _clock: Label3D
var _climate: Label3D
var _tape: Label3D
var _light: OmniLight3D
var _head_yaw := 0.0
var _head_pitch := -0.1
var _look_timer := 0.0
var _lean := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _tape_scroll := 0.0
var _needle_speed := 0.0
var _needle_rpm := 0.0

func _ready() -> void:
	_car = get_parent() as ArcadeCar
	var mi := MeshInstance3D.new()
	mi.mesh = cabin_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_build_wheel()
	_speedo = _gauge(Vector3(-0.53, 0.5, -0.247), "KM/H", ["0", "40", "80", "120", "160", "200", "240"])
	_tach = _gauge(Vector3(-0.23, 0.5, -0.247), "x1000", ["0", "1", "2", "3", "4", "5", "6", "7", "8"])
	_vfd = _label("0", Vector3(-0.38, 0.525, -0.246), 0.0007, VFD_GREEN, 96)
	_label("KM/H", Vector3(-0.38, 0.48, -0.246), 0.00035, VFD_GREEN.darkened(0.3), 40)
	_gear = _label("P R N [D] 2 1", Vector3(-0.38, 0.46, -0.246), 0.00028, VFD_AMBER, 40)
	_clock = _label("17:50", Vector3(0.0, 0.537, -0.252), 0.00045, VFD_GREEN, 32)
	_climate = _label("AUTO 22C FAN|||", Vector3(0.0, 0.405, -0.254), 0.0004, VFD_AMBER, 30)
	_tape = _label("", Vector3(0.0, 0.322, -0.254), 0.00036, VFD_AMBER, 30)
	_label("PATALIPUTRA FM", Vector3(0.0, 0.3, -0.254), 0.00022, VFD_AMBER.darkened(0.35), 24)
	cam = Camera3D.new()
	cam.name = "CockpitCam"
	cam.position = EYE
	cam.near = 0.03
	cam.fov = 74.0
	add_child(cam)
	_light = OmniLight3D.new()
	_light.position = Vector3(-0.1, 0.6, -0.05)
	_light.omni_range = 1.6
	_light.light_energy = 0.0
	_light.light_color = Color(1.0, 0.75, 0.55)
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	set_process(false)
	# Every street car carries an interior; past 30 m it is not worth a draw.
	_cull_far(self)

# ------------------------------------------------------------------ build

static func cabin_mesh() -> Mesh:
	return Builder.cached("kestrel_cabin", func():
		var b := Builder.new(0.35)
		# Floor, firewall behind the seats, footwell.
		b.box(P.CARPET, Vector3(0, 0.035, -0.12), Vector3(1.2, 0.03, 1.8), false)
		b.box(P.PLUSH, Vector3(0, 0.5, 0.97), Vector3(1.24, 0.9, 0.04), false)
		b.box(P.DASH_DARK, Vector3(0, 0.3, -0.78), Vector3(1.24, 0.5, 0.04), false)
		# Dash top (long, flat, burgundy) and its face.
		b.box(P.BURGUNDY, Vector3(0, 0.535, -0.52), Vector3(1.24, 0.05, 0.52), false)
		b.box(P.BURGUNDY, Vector3(0, 0.38, -0.29), Vector3(1.24, 0.28, 0.06), false)
		b.box(P.DASH_DARK, Vector3(0, 0.235, -0.31), Vector3(1.2, 0.02, 0.06), false)
		# Driver binnacle: hood, recessed black face, side cheeks.
		b.box(P.BURGUNDY, Vector3(-0.38, 0.6, -0.33), Vector3(0.6, 0.035, 0.2), false)
		b.box(P.DASH_DARK, Vector3(-0.38, 0.49, -0.255), Vector3(0.56, 0.2, 0.012), false)
		for sx in [-0.68, -0.08]:
			b.box(P.BURGUNDY, Vector3(sx, 0.5, -0.29), Vector3(0.03, 0.22, 0.1), false)
		# Little switch pods either side of the binnacle (top reference).
		for sx in [-0.72, -0.04]:
			b.box(P.DASH_DARK, Vector3(sx, 0.43, -0.256), Vector3(0.06, 0.09, 0.01), false)
			for k in 3:
				b.box(P.WARM_GREY, Vector3(sx, 0.405 + k * 0.025, -0.25), Vector3(0.035, 0.012, 0.008), false)
		# Steering column.
		b.cyl_xf(P.DASH_DARK, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(65)), Vector3(-0.38, 0.38, -0.12)), 0.035, 0.035, 0.28, 8)
		# Centre stack: vents, climate strip, cassette deck, lower bin.
		b.box(P.DASH_DARK, Vector3(0, 0.38, -0.268), Vector3(0.36, 0.3, 0.015), false)
		b.box(P.BURGUNDY, Vector3(0, 0.38, -0.27), Vector3(0.4, 0.33, 0.01), false)
		for k in 4:
			b.box(P.CHARCOAL, Vector3(0, 0.455 + k * 0.016, -0.258), Vector3(0.3, 0.006, 0.012), false)
		b.box(P.WARM_GREY, Vector3(0, 0.485, -0.257), Vector3(0.02, 0.06, 0.012), false)
		b.box(P.BLACK, Vector3(0, 0.405, -0.259), Vector3(0.24, 0.04, 0.008), false)
		for k in 6:
			b.box(P.WARM_GREY, Vector3(-0.15 + k * 0.06, 0.375, -0.257), Vector3(0.035, 0.012, 0.01), false)
		b.box(P.BLACK, Vector3(0, 0.315, -0.259), Vector3(0.3, 0.07, 0.008), false)
		b.box(P.CHARCOAL, Vector3(-0.07, 0.305, -0.255), Vector3(0.11, 0.012, 0.01), false)
		for k in 5:
			b.box(P.CHROME, Vector3(0.04 + k * 0.024, 0.296, -0.254), Vector3(0.016, 0.01, 0.01), false)
		b.cyl_xf(P.CHROME, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.125, 0.33, -0.254)), 0.012, 0.012, 0.012, 8)
		b.cyl_xf(P.CHROME, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(-0.125, 0.33, -0.254)), 0.012, 0.012, 0.012, 8)
		# Passenger side: glovebox line and a vent.
		b.box(P.DASH_DARK, Vector3(0.42, 0.4, -0.258), Vector3(0.5, 0.004, 0.01), false)
		b.box(P.CHARCOAL, Vector3(0.6, 0.47, -0.258), Vector3(0.14, 0.05, 0.01), false)
		b.box(P.BRASS, Vector3(0.36, 0.43, -0.256), Vector3(0.06, 0.015, 0.01), false)
		# Console between the seats and the T-bar shifter.
		b.box(P.BURGUNDY, Vector3(0, 0.17, 0.15), Vector3(0.24, 0.3, 0.9), false)
		b.box(P.DASH_DARK, Vector3(0, 0.325, 0.05), Vector3(0.1, 0.01, 0.2), false)
		b.box(P.CHROME, Vector3(0, 0.37, 0.07), Vector3(0.016, 0.1, 0.016), false)
		b.box(P.BURGUNDY, Vector3(0, 0.43, 0.07), Vector3(0.05, 0.04, 0.1), false)
		b.box(P.CHROME, Vector3(0, 0.44, 0.03), Vector3(0.03, 0.012, 0.01), false)
		b.box(P.LEATHER, Vector3(0, 0.33, 0.45), Vector3(0.22, 0.04, 0.3), false)
		# Seats: velour cushions and raked backs.
		for sx in [-0.38, 0.38]:
			b.box(P.PLUSH, Vector3(sx, 0.13, 0.58), Vector3(0.42, 0.12, 0.5), false)
			b.box_xf(P.PLUSH, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(16)), Vector3(sx, 0.48, 0.88)), Vector3(0.42, 0.62, 0.1))
			b.box_xf(P.PLUSH, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(16)), Vector3(sx, 0.83, 0.98)), Vector3(0.26, 0.14, 0.08))
			for k in 4:
				b.box_xf(P.BURGUNDY, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(16)), Vector3(sx, 0.3 + k * 0.12, 0.825 + k * 0.034)), Vector3(0.4, 0.01, 0.012))
		# Door cards with armrests and pulls.
		for sx in [-1.0, 1.0]:
			b.box(P.BURGUNDY, Vector3(sx * 0.612, 0.32, -0.12), Vector3(0.03, 0.56, 1.34), false)
			b.box(P.PLUSH, Vector3(sx * 0.592, 0.4, 0.05), Vector3(0.02, 0.12, 0.8), false)
			b.box(P.LEATHER, Vector3(sx * 0.58, 0.33, 0.25), Vector3(0.04, 0.04, 0.4), false)
			b.box(P.CHROME, Vector3(sx * 0.595, 0.47, -0.3), Vector3(0.012, 0.03, 0.1), false)
		# Door tops trimmed in velour (the pods slope up toward the rear).
		for sx in [-1.0, 1.0]:
			var d0 := Vector3(sx * 0.72, 0.567, -0.8)
			var d1 := Vector3(sx * 0.72, 0.632, 0.55)
			b.box_xf(P.PLUSH, Transform3D(Basis.looking_at(d1 - d0), (d0 + d1) * 0.5), Vector3(0.24, 0.012, d0.distance_to(d1)))
		# Headliner and the rear-view mirror.
		b.box(P.BURGUNDY, Vector3(0, 0.965, 0.3), Vector3(1.16, 0.015, 0.48), false)
		b.box(P.BLACK, Vector3(0, 0.905, -0.0), Vector3(0.17, 0.04, 0.015), false)
		b.box(P.CHROME, Vector3(0, 0.905, 0.009), Vector3(0.155, 0.03, 0.004), false)
		b.box(P.BLACK, Vector3(0, 0.95, -0.0), Vector3(0.015, 0.06, 0.015), false)
		return b.mesh())

func _build_wheel() -> void:
	var col := Node3D.new()
	# Column tilted 25 degrees toward the driver.
	col.position = Vector3(-0.38, 0.385, 0.0)
	col.rotation.x = deg_to_rad(-25)
	add_child(col)
	_wheel = Node3D.new()
	col.add_child(_wheel)
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.mesh = Builder.cached("steering_wheel", func():
		var b := Builder.new(0.0)
		var r := 0.17
		var seg := 20
		for i in seg:
			var a := TAU * i / seg
			var t := Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a), sin(a), 0) * r)
			b.box_xf(P.BURGUNDY, t, Vector3(0.03, TAU * r / seg + 0.004, 0.034))
		# Four spokes, X pattern like the reference.
		for deg in [20.0, 160.0, 215.0, 325.0]:
			var a := deg_to_rad(deg)
			var mid := Vector3(cos(a), sin(a), 0) * (r * 0.55)
			b.box_xf(P.BURGUNDY, Transform3D(Basis(Vector3.BACK, a), mid + Vector3(0, 0, 0.01)), Vector3(r * 0.85, 0.034, 0.016))
		# Square pad with a small brass badge.
		b.box(P.BURGUNDY, Vector3(0, -0.005, 0.018), Vector3(0.12, 0.1, 0.035), false)
		b.box(P.PLUSH, Vector3(0, -0.005, 0.037), Vector3(0.1, 0.08, 0.004), false)
		b.box(P.BRASS, Vector3(0, 0.0, 0.04), Vector3(0.02, 0.016, 0.004), false)
		return b.mesh())
	_wheel.add_child(mi)

static var _gauge_tex: ImageTexture

static func gauge_texture() -> ImageTexture:
	if _gauge_tex:
		return _gauge_tex
	if true:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var c := Vector2(n, n) * 0.5
		var green := Color(0.4, 1.0, 0.6)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5, y + 0.5) - c
				var r := d.length() / (n * 0.5)
				if r > 1.0:
					continue
				var ang := atan2(d.x, -d.y)  # 0 at top, + clockwise
				var col := Color(0.03, 0.05, 0.04, 1.0)
				# Outer ring.
				if r > 0.93:
					col = Color(0.14, 0.2, 0.16, 1.0)
				# Sweep: -135..135 degrees.
				var deg := rad_to_deg(ang)
				if absf(deg) <= 136.0:
					var step := fmod(deg + 135.0 + 360.0, 13.5)
					var major := fmod(deg + 135.0 + 360.0, 33.75)
					if r > 0.78 and r < 0.9 and (step < 1.6 or step > 11.9):
						col = green
					if r > 0.7 and r < 0.9 and (major < 2.4 or major > 31.35):
						col = green
					# A thin bright arc at the inner edge.
					if r > 0.69 and r < 0.715:
						col = green.darkened(0.35)
				# Crosshair lines, as in the reference's vector gauges.
				if r < 0.6 and (absf(d.x) < 0.6 or absf(d.y) < 0.6):
					col = Color(0.2, 0.45, 0.3, 1.0)
				img.set_pixel(x, y, col)
		_gauge_tex = ImageTexture.create_from_image(img)
	return _gauge_tex

func _gauge(pos: Vector3, unit: String, nums: Array) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.15, 0.15)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = gauge_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	q.material = m
	face.mesh = q
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(face)
	for i in nums.size():
		var a := deg_to_rad(-135.0 + 270.0 * i / (nums.size() - 1))
		var l := _label(nums[i], Vector3(sin(a), cos(a), 0) * 0.048 + Vector3(0, 0, 0.001), 0.00022, VFD_GREEN, 24, root)
		l.modulate.a = 0.9
	_label(unit, Vector3(0, -0.04, 0.001), 0.0002, VFD_GREEN.darkened(0.3), 22, root)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0, 0.004)
	root.add_child(pivot)
	var needle := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.0035, 0.062, 0.002)
	var nm := StandardMaterial3D.new()
	nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nm.albedo_color = Color(1.0, 0.45, 0.2)
	bm.material = nm
	needle.mesh = bm
	needle.position = Vector3(0, 0.026, 0)
	pivot.add_child(needle)
	return pivot

func _label(t: String, pos: Vector3, px: float, col: Color, size: int, parent: Node3D = self) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.position = pos
	l.pixel_size = px
	l.font = Game.mono
	l.font_size = size
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.fixed_size = false
	l.no_depth_test = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	parent.add_child(l)
	return l

# ------------------------------------------------------------------ runtime

func _cull_far(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_end = 30.0
		_cull_far(c)

func activate(on: bool) -> void:
	active = on
	set_process(on)
	_light.visible = on
	_light.light_energy = 0.35 if on else 0.0
	if on:
		_head_yaw = 0.0
		_head_pitch = -0.1
		_prev_vel = _car.linear_velocity if _car else Vector3.ZERO
		cam.make_current()

func _unhandled_input(e: InputEvent) -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if e is InputEventMouseMotion:
		var sens: float = 0.0022
		_head_yaw = clampf(_head_yaw - e.relative.x * sens, -1.9, 1.9)
		_head_pitch = clampf(_head_pitch - e.relative.y * sens, -0.75, 0.55)
		_look_timer = 1.2

func _process(dt: float) -> void:
	if _car == null:
		return
	var speed := _car.get_speed()
	var kmh := speed * 3.6
	# Wheel: about 7x the road-wheel angle, like a real steering ratio.
	_wheel.rotation.z = lerp_angle(_wheel.rotation.z, _car.get_steer() * 7.0, 1.0 - exp(-dt * 20.0))
	_needle_speed = lerpf(_needle_speed, clampf(kmh / 240.0, 0.0, 1.0), 1.0 - exp(-dt * 8.0))
	_needle_rpm = lerpf(_needle_rpm, clampf(_car.get_rpm() / 8000.0, 0.0, 1.0), 1.0 - exp(-dt * 12.0))
	_speedo.rotation.z = deg_to_rad(135.0 - 270.0 * _needle_speed)
	_tach.rotation.z = deg_to_rad(135.0 - 270.0 * _needle_rpm)
	_vfd.text = "%d" % int(round(kmh))
	var g: int = _car.get_gear()
	_gear.text = "P [R] N D 2 1" if g < 0 else ("P R N [D] 2 1" if speed > 0.5 or _car.get_throttle() > 0.0 else "P R [N] D 2 1")
	var st: Dictionary = Game.mstate() if Engine.get_process_frames() % 30 == 0 else {}
	if st.has("clock"):
		_clock.text = str(st.clock)
	elif _clock.text == "":
		_clock.text = "--:--"
	_tape_scroll += dt * 6.0
	var song := "  SIDE A  >  RAAG MALKAUNS (TAPE)  >  DOLBY B  "
	var i0 := int(_tape_scroll) % song.length()
	_tape.text = (song + song).substr(i0, 22)
	# Head: recentres after a pause, glances into turns, leans with g-forces.
	_look_timer -= dt
	var yaw_rate := _car.angular_velocity.y
	if _look_timer <= 0.0:
		_head_yaw = lerpf(_head_yaw, clampf(yaw_rate * 0.12, -0.25, 0.25), 1.0 - exp(-dt * 3.0))
		_head_pitch = lerpf(_head_pitch, -0.1, 1.0 - exp(-dt * 2.0))
	var basis_inv := _car.global_transform.basis.inverse()
	var acc := basis_inv * ((_car.linear_velocity - _prev_vel) / maxf(dt, 0.001))
	_prev_vel = _car.linear_velocity
	var lean_target := Vector3(clampf(-acc.x * 0.004, -0.05, 0.05), clampf(-acc.y * 0.002, -0.03, 0.03), clampf(-acc.z * 0.004, -0.05, 0.05))
	_lean = _lean.lerp(lean_target, 1.0 - exp(-dt * 6.0))
	var shake := 0.0
	if speed > 2.0:
		shake = 0.0012 * clampf(speed / 30.0, 0.0, 1.5)
	cam.position = EYE + _lean + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake
	cam.rotation = Vector3(_head_pitch, _head_yaw, -_lean.x * 0.8)
	cam.fov = 72.0 + 8.0 * clampf(speed / 50.0, 0.0, 1.0)
