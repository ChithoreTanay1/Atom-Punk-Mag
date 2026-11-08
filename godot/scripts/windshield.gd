class_name Windshield
extends MeshInstance3D
## The Kestrel's windscreen, its own part so it can break. The state lives in
## ArcadeCar (core::crash::Glass): one hit crazes the pane and spoils the view,
## the next takes it out and the view is clear.

const P = preload("res://scripts/palette.gd")
const CRACK = preload("res://shaders/windshield_crack.gdshader")
## Pane corners in car space: the lower edge, then the upper edge.
const LOW_Y := 0.555
const LOW_Z := -0.8
const LOW_W := 0.84
const TOP_Y := 0.97
const TOP_Z := 0.05
const TOP_W := 0.66

var _car: ArcadeCar

func _ready() -> void:
	_car = get_parent() as ArcadeCar
	add_to_group("windshields")
	mesh = pane_mesh()
	material_override = P.mats()[P.CAR_GLASS]
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func pane_mesh() -> Mesh:
	return Builder.cached("kestrel_windshield", func():
		var a := PackedVector3Array([
			Vector3(-LOW_W, LOW_Y, LOW_Z), Vector3(LOW_W, LOW_Y, LOW_Z),
			Vector3(TOP_W, TOP_Y, TOP_Z), Vector3(-TOP_W, TOP_Y, TOP_Z)])
		var n := (a[1] - a[0]).cross(a[3] - a[0]).normalized()
		if n.y < 0.0:
			n = -n
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = a
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([n, n, n, n])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2])
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m)

## Where the line a..b (world space) passes through the pane; NAN x if it does not.
func crossing(a: Vector3, b: Vector3) -> Vector3:
	var inv := global_transform.affine_inverse()
	var la := inv * a
	var lb := inv * b
	var p0 := Vector3(0, LOW_Y, LOW_Z)
	var up := Vector3(0, TOP_Y - LOW_Y, TOP_Z - LOW_Z)
	var nrm := Vector3(1, 0, 0).cross(up).normalized()
	var da := (la - p0).dot(nrm)
	var db := (lb - p0).dot(nrm)
	if da * db > 0.0 or is_equal_approx(da, db):
		return Vector3(NAN, 0, 0)
	var at := la.lerp(lb, da / (da - db))
	var t := (at - p0).dot(up) / up.length_squared()
	if t < 0.0 or t > 1.0 or absf(at.x) > lerpf(LOW_W, TOP_W, t):
		return Vector3(NAN, 0, 0)
	return at

## A bullet (or a crash) strikes the pane at `at`, in car space.
func strike(at: Vector3) -> void:
	if _car == null or not visible:
		return
	var state := _car.windshield_hit()
	if state == 1:
		_crack(at)
	elif state == 2:
		_shatter()

func strike_anywhere() -> void:
	strike(Vector3(randf_range(-0.5, 0.5), lerpf(LOW_Y, TOP_Y, 0.5), 0.0))

func _crack(at: Vector3) -> void:
	var m := ShaderMaterial.new()
	m.shader = CRACK
	m.set_shader_parameter("impact", Vector2(at.x, at.y * 2.0))
	m.set_shader_parameter("seed", randf() * 50.0)
	material_override = m
	Game.play_3d("glass_crack", global_position + global_basis * at, -2)

func _shatter() -> void:
	visible = false
	Game.play_3d("glass_break", global_position, 0)
	var parts := CPUParticles3D.new()
	parts.position = Vector3(0, (LOW_Y + TOP_Y) * 0.5, (LOW_Z + TOP_Z) * 0.5)
	parts.one_shot = true
	parts.explosiveness = 0.95
	parts.amount = 70
	parts.lifetime = 1.3
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	parts.emission_box_extents = Vector3(0.7, 0.2, 0.4)
	parts.direction = Vector3(0, 0.4, 1)
	parts.spread = 70.0
	parts.initial_velocity_min = 0.5
	parts.initial_velocity_max = 3.2
	parts.gravity = Vector3(0, -9.8, 0)
	parts.angular_velocity_min = -400.0
	parts.angular_velocity_max = 400.0
	parts.scale_amount_min = 0.3
	parts.scale_amount_max = 1.0
	var q := BoxMesh.new()
	q.size = Vector3(0.035, 0.005, 0.035)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.8, 0.8)
	mat.roughness = 0.1
	mat.metallic = 0.4
	q.material = mat
	parts.mesh = q
	get_parent().add_child(parts)
	parts.emitting = true
	get_tree().create_timer(2.0).timeout.connect(parts.queue_free)
