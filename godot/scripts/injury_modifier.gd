class_name InjuryModifier
extends SkeletonModifier3D
## Wounds shown on top of the animation (humanoid bone names):
##   limp — while the wounded leg carries the weight, the hips drop and the
##          trunk lurches over it; that knee stays stiff. The step on it is
##          short and quick, the classic antalgic gait.
##   arm  — a hit arm hangs at the side, elbow loose, whatever the clip does.
## Weights fade in so a fresh wound reads as a change, not a pop.

## Wanted weights 0..1: [left, right].
var limp_want := [0.0, 0.0]
var arm_want := [0.0, 0.0]
## How much the body is walking (0 standing, 1 full stride): the limp only shows in the gait.
var walk_k := 0.0

var _limp := [0.0, 0.0]
var _arm := [0.0, 0.0]
var _idx := {}

const SIDES := ["Left", "Right"]

func _ready() -> void:
	active = true

func _bone(sk: Skeleton3D, n: String) -> int:
	if not _idx.has(n):
		_idx[n] = sk.find_bone(n)
	return _idx[n]

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for s in 2:
		_limp[s] = move_toward(_limp[s], limp_want[s], delta * 2.5)
		_arm[s] = move_toward(_arm[s], arm_want[s], delta * 4.0)
	if _limp[0] + _limp[1] > 0.001 and walk_k > 0.01:
		_apply_limp(sk)
	for s in 2:
		if _arm[s] > 0.001:
			_apply_arm(sk, s, _arm[s])

## Rotate bone `i` by `r` (skeleton space) on top of its current pose.
func _rotate_global(sk: Skeleton3D, i: int, r: Basis) -> void:
	var p := sk.get_bone_parent(i)
	var pg := sk.get_bone_global_pose(p).basis if p >= 0 else Basis()
	var g := sk.get_bone_global_pose(i).basis
	var local := (pg.inverse() * (r * g)).orthonormalized()
	sk.set_bone_pose_rotation(i, local.get_rotation_quaternion())

func _apply_limp(sk: Skeleton3D) -> void:
	var hips := _bone(sk, "Hips")
	var fl := sk.get_bone_global_pose(_bone(sk, "LeftFoot")).origin
	var fr := sk.get_bone_global_pose(_bone(sk, "RightFoot")).origin
	# The planted foot is the lower one.
	var on_l := smoothstep(0.0, 0.05, fr.y - fl.y)
	var on_r := smoothstep(0.0, 0.05, fl.y - fr.y)
	var load_l: float = _limp[0] * on_l * walk_k
	var load_r: float = _limp[1] * on_r * walk_k
	var dip: float = load_l + load_r
	if dip < 0.001:
		return
	# Hips drop: move the hips down in skeleton space.
	var p := sk.get_bone_parent(hips)
	var pg := sk.get_bone_global_pose(p) if p >= 0 else Transform3D()
	var pos := sk.get_bone_pose_position(hips)
	var down_local := pg.basis.inverse() * Vector3(0, -0.075 * dip, 0)
	sk.set_bone_pose_position(hips, pos + down_local)
	# Trunk lurches toward the bad side (skeleton +X is the body's left).
	var lurch := (load_l - load_r) * 0.22
	var fwd := Vector3(0, 0, 1)
	_rotate_global(sk, _bone(sk, "Spine"), Basis(fwd, -lurch))
	_rotate_global(sk, _bone(sk, "Chest"), Basis(Vector3.RIGHT, 0.12 * dip))   # bends over the pain
	_rotate_global(sk, _bone(sk, "Head"), Basis(fwd, lurch * 0.6))
	# Stiff knee on the wounded leg: pull the shin back toward the thigh's line.
	for s in 2:
		if _limp[s] <= 0.0:
			continue
		var knee := _bone(sk, SIDES[s] + "LowerLeg")
		var thigh := _bone(sk, SIDES[s] + "UpperLeg")
		var tb := sk.get_bone_global_pose(thigh).basis
		var kb := sk.get_bone_global_pose(knee).basis
		var straight := Quaternion(kb.y.normalized(), tb.y.normalized())
		var q := Quaternion.IDENTITY.slerp(straight, 0.45 * _limp[s])
		_rotate_global(sk, knee, Basis(q))

func _apply_arm(sk: Skeleton3D, s: int, w: float) -> void:
	var side: String = SIDES[s]
	var ua := _bone(sk, side + "UpperArm")
	var la := _bone(sk, side + "LowerArm")
	if ua < 0 or la < 0:
		return
	# Hang down, a little forward and out from the body.
	var out := 1.0 if s == 0 else -1.0
	var want := Vector3(0.12 * out, -1.0, 0.12).normalized()
	var cur := sk.get_bone_global_pose(ua).basis.y.normalized()
	var q := Quaternion(cur, want)
	_rotate_global(sk, ua, Basis(Quaternion.IDENTITY.slerp(q, w)))
	# Forearm hangs straight on from the upper arm, a slight bend.
	var ub := sk.get_bone_global_pose(ua).basis.y.normalized()
	var lb := sk.get_bone_global_pose(la).basis.y.normalized()
	var want_l := (ub + Vector3(0, 0, 0.2)).normalized()
	_rotate_global(sk, la, Basis(Quaternion.IDENTITY.slerp(Quaternion(lb, want_l), w)))
