class_name DroneWreck
extends RigidBody3D
## A saucer drone coming down. Shot down, it falls where it was and trails smoke.
## Roped, it is dragged hard at `target` and slams into it. Either way, the level
## hears about the impact once.

const SLAM_SPEED := 30.0

var target := Vector3.INF
var on_landed: Callable
var _landed := false
var _age := 0.0

func launch(mesh: Mesh, xf: Transform3D, vel: Vector3, at: Vector3, landed: Callable) -> void:
	global_transform = xf
	linear_velocity = vel
	angular_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(-5.0, 5.0), randf_range(-2.5, 2.5))
	target = at
	on_landed = landed
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 8
	mass = 140.0
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	if target != Vector3.INF:
		gravity_scale = 0.3
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.15
	physics_material_override = phys
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.2
	shape.height = 0.5
	cs.shape = shape
	add_child(cs)
	var smoke := Builder.damage_smoke(Vector3.ZERO)
	smoke.amount = 34
	add_child(smoke)
	smoke.emitting = true
	body_entered.connect(func(_b): _land())

func is_landed() -> bool:
	return _landed

func _physics_process(dt: float) -> void:
	_age += dt
	if _landed:
		return
	if target != Vector3.INF:
		var to := target - global_position
		if to.length() < 1.5:
			_land()
			return
		linear_velocity = linear_velocity.lerp(to.normalized() * SLAM_SPEED, 1.0 - exp(-dt * 7.0))
	if _age > 12.0:
		_land()

func _land() -> void:
	if _landed:
		return
	_landed = true
	gravity_scale = 1.0
	target = Vector3.INF
	if on_landed.is_valid():
		on_landed.call(global_position, linear_velocity.length())
