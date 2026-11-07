class_name NpcBody
extends Node3D
## The visible body of an Npc: a skeleton and clips from the Quaternius
## Universal Animation Library (CC0, assets/anim/ual_standard.glb), with the
## BodyKit parts hung on its bones. The library's mannequin mesh is dropped.
##
## Bones are renamed to SkeletonProfileHumanoid names at load (what the
## Active Ragdoll addon expects); clip tracks are rewritten to match, finger
## and root-motion tracks are stripped. One AnimationLibrary is shared by all.
##
## Layers, bottom to top:
##   gait   idle / walk / jog / sprint / talk, playback scaled to the ground
##          speed so feet do not skate
##   aim    upper body: rifle at low ready (patrol) or shouldered (combat), guards only
##   shoot  upper-body recoil one-shot when the Npc fires
##   hit    upper-body flinch one-shot (chest or head clip)
##   kneel  full-body drop to one knee after a leg hit (stumble)
##   InjuryModifier: limp and dead arms on top
##   ActiveRagdoll (built on the first hit): physical flinches, falls,
##   writhing on the ground, death.
##
## Hit zones: zone_for_ray() finds the body part a shot passes through from
## the animated bones (head, neck, chest, abdomen, pelvis, upper arm, forearm,
## hand, thigh, shin, foot; _l/_r).

signal crashed(impact: float, at: Vector3)

const GLB := "res://assets/anim/ual_standard.glb"
const BONE_MAP := {
	"DEF-hips": "Hips", "DEF-spine.001": "Spine", "DEF-spine.002": "Chest", "DEF-spine.003": "UpperChest",
	"DEF-neck": "Neck", "DEF-head": "Head",
	"DEF-shoulder.L": "LeftShoulder", "DEF-upper_arm.L": "LeftUpperArm", "DEF-forearm.L": "LeftLowerArm", "DEF-hand.L": "LeftHand",
	"DEF-shoulder.R": "RightShoulder", "DEF-upper_arm.R": "RightUpperArm", "DEF-forearm.R": "RightLowerArm", "DEF-hand.R": "RightHand",
	"DEF-thigh.L": "LeftUpperLeg", "DEF-shin.L": "LeftLowerLeg", "DEF-foot.L": "LeftFoot", "DEF-toe.L": "LeftToes",
	"DEF-thigh.R": "RightUpperLeg", "DEF-shin.R": "RightLowerLeg", "DEF-foot.R": "RightFoot", "DEF-toe.R": "RightToes",
}
## Clips used, and whether they loop.
const CLIPS := {
	"Idle": true, "Idle_Talking": true, "Walk": true, "Walk_Formal": true, "Jog_Fwd": true, "Sprint": true,
	"Pistol_Idle": true, "Pistol_Shoot": false, "Hit_Chest": false, "Hit_Head": false,
	"Fixing_Kneeling": false,
}
## Ground speed of each gait clip at 1x (measured from the foot travel), m/s.
const NATURAL := {"walk": 0.9, "jog": 2.5, "sprint": 3.4}
const UPPER := ["Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
## Part meshes per bone: [bone, part, side, frame] (frame: torso-style or limb).
const PARTS := [
	["Hips", "pelvis", 0, "t"], ["Spine", "abdomen", 0, "t"], ["UpperChest", "chest", 0, "t"], ["Head", "head", 0, "t"],
	["LeftUpperArm", "uarm", -1, "l"], ["LeftLowerArm", "farm", -1, "l"], ["RightUpperArm", "uarm", 1, "l"], ["RightLowerArm", "farm", 1, "l"],
	["LeftUpperLeg", "thigh", -1, "l"], ["LeftLowerLeg", "shin", -1, "l"], ["RightUpperLeg", "thigh", 1, "l"], ["RightLowerLeg", "shin", 1, "l"],
	["LeftFoot", "foot", -1, "t"], ["RightFoot", "foot", 1, "t"],
]
## Hit segments: [zone, bone, to bone or length along the bone, radius].
const SEGMENTS := [
	["head", "Head", 0.24, 0.12], ["neck", "Neck", "Head", 0.07],
	["chest", "UpperChest", "Neck", 0.19], ["abdomen", "Spine", "UpperChest", 0.17], ["pelvis", "Hips", "Spine", 0.17],
	["upperarm_l", "LeftUpperArm", "LeftLowerArm", 0.075], ["forearm_l", "LeftLowerArm", "LeftHand", 0.06], ["hand_l", "LeftHand", 0.12, 0.06],
	["upperarm_r", "RightUpperArm", "RightLowerArm", 0.075], ["forearm_r", "RightLowerArm", "RightHand", 0.06], ["hand_r", "RightHand", 0.12, 0.06],
	["thigh_l", "LeftUpperLeg", "LeftLowerLeg", 0.095], ["shin_l", "LeftLowerLeg", "LeftFoot", 0.07], ["foot_l", "LeftFoot", "LeftToes", 0.07],
	["thigh_r", "RightUpperLeg", "RightLowerLeg", 0.095], ["shin_r", "RightLowerLeg", "RightFoot", 0.07], ["foot_r", "RightFoot", "RightToes", 0.07],
]
## Zone -> the physical bone a blow goes into.
const ZONE_BONE := {
	"head": "Head", "neck": "Head", "chest": "UpperChest", "abdomen": "Spine", "pelvis": "Hips",
	"upperarm_l": "LeftUpperArm", "forearm_l": "LeftLowerArm", "hand_l": "LeftLowerArm",
	"upperarm_r": "RightUpperArm", "forearm_r": "RightLowerArm", "hand_r": "RightLowerArm",
	"thigh_l": "LeftUpperLeg", "shin_l": "LeftLowerLeg", "foot_l": "LeftFoot",
	"thigh_r": "RightUpperLeg", "shin_r": "RightLowerLeg", "foot_r": "RightFoot",
}
## Physical bone -> zone (shots into a body on the ground).
const BONE_ZONE := {
	"Hips": "pelvis", "Spine": "abdomen", "Chest": "abdomen", "UpperChest": "chest", "Head": "head",
	"LeftUpperArm": "upperarm_l", "LeftLowerArm": "forearm_l", "RightUpperArm": "upperarm_r", "RightLowerArm": "forearm_r",
	"LeftUpperLeg": "thigh_l", "LeftLowerLeg": "shin_l", "LeftFoot": "foot_l",
	"RightUpperLeg": "thigh_r", "RightLowerLeg": "shin_r", "RightFoot": "foot_r",
}

const MAX_ACTIVE := 10       # dead bodies kept physical; older ones freeze
const LAYER := 1 << 9        # ragdoll bodies: shot and hooked, not walked on
const MASK := 1 | 8          # world and cars

static var _scene: PackedScene
static var _lib: AnimationLibrary
static var _active: Array = []

var kind := "civilian"
var tint := 0
var npc: Npc
var model: Node3D
var skeleton: Skeleton3D
var tree: AnimationTree
var injury: InjuryModifier
var ragdoll: ActiveRagdoll
var dead := false
var downed := false
var _walk_clip := "Walk"
var _aim := 0.45
var _gait := ""
var _att := {}               # bone -> BoneAttachment3D
var _marks: Array = []
var _acc := 0.0
var _frame := 0
var _seq := false            # a scripted sequence keeps the animation running
var _flying := false
var _fly_t := 0.0
var _fly_prev := 0.0
var _land_t := 0.0
var _wound_t := 0.0
var _retired := false
var _wound_bone := "UpperChest"

static func create(k: String, t := 0) -> NpcBody:
	var b := NpcBody.new()
	b.name = "Visual"
	b.kind = k
	b.tint = t
	b._build()
	return b

static func _glb() -> PackedScene:
	if _scene == null:
		_scene = load(GLB)
	return _scene

## The shared clip library, retargeted to humanoid bone names.
static func library() -> AnimationLibrary:
	if _lib:
		return _lib
	_lib = AnimationLibrary.new()
	var src := _glb().instantiate()
	var ap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for nm: String in CLIPS:
		if not ap.has_animation(nm):
			push_warning("NpcBody: clip %s missing" % nm)
			continue
		var a := ap.get_animation(nm).duplicate(true) as Animation
		for t in range(a.get_track_count() - 1, -1, -1):
			var path := str(a.track_get_path(t))
			var bone := path.get_slice(":", 1)
			var keep: bool = BONE_MAP.has(bone)
			if keep and a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				keep = BONE_MAP[bone] == "Hips" and a.track_get_type(t) == Animation.TYPE_POSITION_3D
			if not keep:
				a.remove_track(t)
				continue
			a.track_set_path(t, NodePath("Skeleton3D:" + BONE_MAP[bone]))
		a.loop_mode = Animation.LOOP_LINEAR if CLIPS[nm] else Animation.LOOP_NONE
		_lib.add_animation(nm, a)
	src.free()
	return _lib

func _build() -> void:
	model = Node3D.new()
	model.name = "Model"
	model.rotation.y = PI      # the library faces +Z; Godot bodies face -Z
	add_child(model)
	var src := _glb().instantiate()
	var sk := src.find_child("Skeleton3D", true, false) as Skeleton3D
	sk.get_parent().remove_child(sk)
	sk.owner = null
	src.free()
	for c in sk.get_children():
		sk.remove_child(c)
		c.free()
	sk.name = "Skeleton3D"
	model.add_child(sk)
	skeleton = sk
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		if BONE_MAP.has(bn):
			sk.set_bone_name(i, BONE_MAP[bn])
	# The armour is broader than the mannequin: shoulders and hips out a bit.
	for s in [1.0, -1.0]:
		var side := "Left" if s > 0 else "Right"
		_move_rest(side + "UpperArm", Vector3(0.245 * s, 0, 0), true)
		_move_rest(side + "UpperLeg", Vector3(0.105 * s, 0, 0), true)
	injury = InjuryModifier.new()
	injury.name = "Injury"
	sk.add_child(injury)
	_walk_clip = "Walk_Formal" if kind == "governor" else "Walk"
	_build_tree()
	_attach_parts()

## Put a bone's rest (and pose) origin at the given skeleton-space x, keeping y/z.
func _move_rest(bn: String, at: Vector3, only_x: bool) -> void:
	var i := skeleton.find_bone(bn)
	var p := skeleton.get_bone_parent(i)
	if i < 0 or p < 0:
		return
	var g := skeleton.get_bone_global_rest(i).origin
	var want := Vector3(at.x, g.y, g.z) if only_x else at
	var rest := skeleton.get_bone_rest(i)
	rest.origin = skeleton.get_bone_global_rest(p).affine_inverse() * want
	skeleton.set_bone_rest(i, rest)
	skeleton.set_bone_pose_position(i, rest.origin)

func _anim(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a

func _filter_upper(n: AnimationNode) -> void:
	n.filter_enabled = true
	for b in UPPER:
		n.set_filter_path(NodePath("Skeleton3D:" + b), true)

func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "Tree"
	model.add_child(tree)
	tree.root_node = NodePath("..")
	tree.add_animation_library("", library())
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var bt := AnimationNodeBlendTree.new()
	var gait := AnimationNodeTransition.new()
	gait.xfade_time = 0.25
	var states := {"idle": "Idle", "walk": _walk_clip, "jog": "Jog_Fwd", "sprint": "Sprint", "talk": "Idle_Talking"}
	gait.input_count = states.size()
	var i := 0
	for st: String in states:
		gait.set_input_name(i, st)
		bt.add_node("a_" + st, _anim(states[st]))
		bt.add_node("ts_" + st, AnimationNodeTimeScale.new())
		bt.connect_node("ts_" + st, 0, "a_" + st)
		i += 1
	bt.add_node("gait", gait)
	i = 0
	for st: String in states:
		bt.connect_node("gait", i, "ts_" + st)
		i += 1
	# Upper body: the rifle shouldered; half blended it is carried at low ready.
	bt.add_node("a_up", _anim("Pistol_Idle"))
	var aim := AnimationNodeBlend2.new()
	_filter_upper(aim)
	bt.add_node("aim", aim)
	bt.connect_node("aim", 0, "gait")
	bt.connect_node("aim", 1, "a_up")
	var shoot := AnimationNodeOneShot.new()
	shoot.fadein_time = 0.04
	shoot.fadeout_time = 0.15
	_filter_upper(shoot)
	bt.add_node("shoot", shoot)
	bt.add_node("a_shoot", _anim("Pistol_Shoot"))
	bt.connect_node("shoot", 0, "aim")
	bt.connect_node("shoot", 1, "a_shoot")
	var hitpose := AnimationNodeTransition.new()
	hitpose.input_count = 2
	hitpose.set_input_name(0, "chest")
	hitpose.set_input_name(1, "head")
	bt.add_node("hitpose", hitpose)
	bt.add_node("a_hitc", _anim("Hit_Chest"))
	bt.add_node("a_hith", _anim("Hit_Head"))
	bt.connect_node("hitpose", 0, "a_hitc")
	bt.connect_node("hitpose", 1, "a_hith")
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.03
	hit.fadeout_time = 0.2
	_filter_upper(hit)
	bt.add_node("hit", hit)
	bt.connect_node("hit", 0, "shoot")
	bt.connect_node("hit", 1, "hitpose")
	var kneel := AnimationNodeOneShot.new()
	kneel.fadein_time = 0.06
	kneel.fadeout_time = 0.3
	bt.add_node("kneel", kneel)
	bt.add_node("a_kneel", _anim("Fixing_Kneeling"))
	bt.add_node("ts_kneel", AnimationNodeTimeScale.new())
	bt.connect_node("ts_kneel", 0, "a_kneel")
	bt.connect_node("kneel", 0, "hit")
	bt.connect_node("kneel", 1, "ts_kneel")
	bt.connect_node("output", 0, "kneel")
	tree.tree_root = bt
	tree.active = true
	_set_gait("idle", 1.0)
	tree.set("parameters/aim/blend_amount", 0.45 if kind == "guard" else 0.0)
	tree.advance(randf() * 2.0)

func _attachment(bone: String) -> BoneAttachment3D:
	if _att.has(bone):
		return _att[bone]
	var a := BoneAttachment3D.new()
	a.name = "At_" + bone
	a.bone_name = bone
	skeleton.add_child(a)
	_att[bone] = a
	return a

## Part frame at rest, skeleton space (the body faces +Z there).
func _part_basis(bone: String, frame: String) -> Basis:
	if frame == "t":
		return Basis(Vector3.UP, PI)
	var i := skeleton.find_bone(bone)
	var child := ""
	for c in skeleton.get_bone_children(i):
		var cn := skeleton.get_bone_name(c)
		if not cn.begins_with("DEF-"):
			child = cn
			break
	var dir := skeleton.get_bone_global_rest(i).basis.y.normalized()
	if child != "":
		dir = (skeleton.get_bone_global_rest(skeleton.find_bone(child)).origin - skeleton.get_bone_global_rest(i).origin).normalized()
	var y := -dir
	var z := Vector3(0, 0, -1)
	z = (z - y * y.dot(z)).normalized()
	return Basis(y.cross(z), y, z)

func _attach_parts() -> void:
	for p in PARTS:
		var bone: String = p[0]
		var i := skeleton.find_bone(bone)
		if i < 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = BodyKit.part_mesh(p[1], kind, tint, p[2])
		mi.basis = skeleton.get_bone_global_rest(i).basis.orthonormalized().inverse() * _part_basis(bone, p[3])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 95.0
		_attachment(bone).add_child(mi)
	if kind == "guard":
		var hand := skeleton.find_bone("RightHand")
		var a: Animation = library().get_animation("Pistol_Idle")
		var h := _anim_global(a, hand, 0.0)
		var grip := h * Vector3(0, 0.07, 0)
		var gun := MeshInstance3D.new()
		gun.name = "Rifle"
		gun.mesh = BodyKit.rifle_mesh()
		gun.transform = h.affine_inverse() * Transform3D(Basis(Vector3.UP, PI), grip)
		gun.visibility_range_end = 80.0
		_attachment("RightHand").add_child(gun)

## Global (skeleton space) transform of bone i in clip `a` at time t.
func _anim_global(a: Animation, i: int, t: float) -> Transform3D:
	var chain: Array[int] = []
	while i >= 0:
		chain.push_front(i)
		i = skeleton.get_bone_parent(i)
	var g := Transform3D()
	for b in chain:
		var rest := skeleton.get_bone_rest(b)
		var rot := rest.basis.get_rotation_quaternion()
		var pos := rest.origin
		var path := NodePath("Skeleton3D:" + skeleton.get_bone_name(b))
		var tr := a.find_track(path, Animation.TYPE_ROTATION_3D)
		if tr >= 0:
			rot = a.rotation_track_interpolate(tr, t)
		var tp := a.find_track(path, Animation.TYPE_POSITION_3D)
		if tp >= 0:
			pos = a.position_track_interpolate(tp, t)
		g = g * Transform3D(Basis(rot), pos)
	return g

func _ready() -> void:
	npc = get_parent() as Npc
	if npc == null:
		return
	npc.wounded.connect(_on_wounded)
	npc.shot_at_player.connect(func(_a, _b, _c, _d): _fire_shot())

# ------------------------------------------------------------- living

func _set_gait(st: String, scale: float) -> void:
	if st != _gait:
		_gait = st
		tree.set("parameters/gait/transition_request", st)
	tree.set("parameters/ts_" + st + "/scale", scale)

func _process(dt: float) -> void:
	if npc == null or tree == null:
		return
	if (dead or downed) and not _seq:
		return
	# Far bodies animate at a lower rate.
	_acc += dt
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_squared_to(global_position) > 45.0 * 45.0
	if far and _frame % 3 != 0:
		return
	if not _seq:
		_drive()
	tree.advance(_acc)
	_acc = 0.0

func _drive() -> void:
	var v := npc.velocity
	var s := Vector2(v.x, v.z).length()
	var st := "idle"
	if s > 0.25:
		st = "walk"
	if s > 1.9:
		st = "jog"
	if s > 3.7:
		st = "sprint"
	if st == "idle" and npc.speaking:
		st = "talk"
	var scale := 1.0
	if NATURAL.has(st):
		scale = clampf(s / float(NATURAL[st]), 0.55, 2.2)
	_set_gait(st, scale)
	if kind == "guard":
		var want := 1.0 if npc.in_combat() else 0.45
		_aim = move_toward(_aim, want, get_process_delta_time() * 3.0)
		tree.set("parameters/aim/blend_amount", _aim)
	injury.walk_k = clampf(s / 0.7, 0.0, 1.0)
	_wound_t -= get_process_delta_time()
	if _wound_t <= 0.0:
		_wound_t = 0.25
		var w := npc.get_wounds()
		injury.limp_want = [minf(w[0], 2) * 0.6, minf(w[1], 2) * 0.6]
		injury.arm_want = [1.0 if w[2] > 0 else 0.0, 1.0 if w[3] > 0 else 0.0]

func _fire_shot() -> void:
	if dead or downed:
		return
	tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

# ------------------------------------------------------------- hits

## Which body part a shot along `dir` from `from` goes through, from the
## animated bones. Returns {zone, point, bone, miss} — miss when the ray only
## clipped the collision capsule and passed between the limbs.
func zone_for_ray(from: Vector3, dir: Vector3) -> Dictionary:
	var g := skeleton.global_transform
	var best := {"zone": "chest", "point": from, "bone": "UpperChest", "miss": true}
	var best_d := INF
	for s in SEGMENTS:
		var i := skeleton.find_bone(s[1])
		if i < 0:
			continue
		var a := g * skeleton.get_bone_global_pose(i).origin
		var b: Vector3
		if s[2] is String:
			b = g * skeleton.get_bone_global_pose(skeleton.find_bone(s[2])).origin
		else:
			b = a + (g.basis * skeleton.get_bone_global_pose(i).basis.y).normalized() * float(s[2])
		var r := _ray_segment(from, dir, a, b)
		var d: float = r[0] - float(s[3])
		if d < best_d:
			best_d = d
			best = {"zone": s[0], "point": r[1], "bone": ZONE_BONE[s[0]], "miss": d > 0.1}
	return best

## [distance, closest point on the segment] between a ray and segment ab.
static func _ray_segment(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Array:
	var u := d.normalized()
	var v := b - a
	var w := o - a
	var aa := 1.0
	var bb := u.dot(v)
	var cc := v.dot(v)
	var dd := u.dot(w)
	var ee := v.dot(w)
	var den := aa * cc - bb * bb
	var sc := 0.0
	var tc := 0.0
	if den < 1e-6:
		tc = clampf(ee / maxf(cc, 1e-6), 0.0, 1.0)
		sc = maxf(0.0, -dd + bb * tc)
	else:
		sc = maxf(0.0, (bb * ee - cc * dd) / den)
		tc = clampf((aa * ee - bb * dd) / den, 0.0, 1.0)
		sc = maxf(0.0, u.dot(a + v * tc - o))
	var p := o + u * sc
	var q := a + v * tc
	return [p.distance_to(q), q]

## A dark wound where the shot went in, riding that bone.
func mark_wound(point: Vector3, normal: Vector3, bone: String) -> void:
	var at := _attachment(bone)
	if not at.is_inside_tree():
		return
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07) * randf_range(0.8, 1.3)
	q.material = _wound_mat()
	m.mesh = q
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	at.add_child(m)
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	m.global_transform = Transform3D(Basis.looking_at(-n, up).rotated(n, randf() * TAU), point + n * 0.012)
	_marks.append(m)
	while _marks.size() > 8:
		var old: Node = _marks.pop_front()
		if is_instance_valid(old):
			old.queue_free()

static var _wmat: StandardMaterial3D
static func _wound_mat() -> StandardMaterial3D:
	if _wmat == null:
		_wmat = StandardMaterial3D.new()
		_wmat.albedo_texture = PlayerRig.hole_tex()
		_wmat.albedo_color = Color(0.42, 0.05, 0.04)
		_wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wmat.roughness = 0.35
	return _wmat

func _ensure_ragdoll() -> void:
	if ragdoll:
		return
	ragdoll = ActiveRagdoll.create(skeleton, RagdollProfile.humanoid())
	ragdoll.collision_layer = LAYER
	ragdoll.collision_mask = MASK
	for pb: PhysicalBone3D in ragdoll.bones.values():
		pb.set_meta("npc_body", self)
	ragdoll.settled.connect(_on_settled)

func _blow_dir(from: Vector3) -> Vector3:
	var d := global_position - from
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else global_basis.z

func _on_wounded(zone: String, reaction: String, from: Vector3) -> void:
	if dead:
		return
	_ensure_ragdoll()
	var dir := _blow_dir(from)
	var bone: String = ZONE_BONE.get(zone, "UpperChest")
	_wound_bone = bone
	match reaction:
		"down":
			go_down(dir * 30.0 + Vector3.UP * 4.0, bone)
		"stumble":
			# Drops onto the wounded knee: the kneel clip, sped up to the stumble.
			var t := maxf(npc.get_stumble(), 0.6)
			tree.set("parameters/ts_kneel/scale", 5.2 / (t + 0.4))
			tree.set("parameters/kneel/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			ragdoll.hit("UpperChest", dir * 18.0)
		"arm":
			ragdoll.hit(bone, dir * 22.0, 0.6)
		"head":
			tree.set("parameters/hitpose/transition_request", "head")
			tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			ragdoll.hit("Head", dir * 14.0)
		_:
			tree.set("parameters/hitpose/transition_request", "chest")
			tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			if downed:
				ragdoll._blow(bone if ragdoll.bones.has(bone) else "Hips", dir * 25.0)
			else:
				ragdoll.hit(bone if ragdoll.bones.has(bone) else "UpperChest", dir * 28.0)

## Off its feet for good (legs shot out, or hauled by the line): falls with
## the blow, then lies writhing, holding the wound.
func go_down(impulse: Vector3, bone := "Hips") -> void:
	if downed or dead:
		return
	downed = true
	_ensure_ragdoll()
	ragdoll.knock(bone if ragdoll.bones.has(bone) else "Hips", impulse, "fall", npc.velocity)
	_land_t = 0.0
	get_tree().create_timer(1.4).timeout.connect(_start_writhe)

func _start_writhe() -> void:
	if dead or not is_instance_valid(ragdoll) or not ragdoll.is_running() or _flying:
		return
	ragdoll.writhe(StringName(_wound_bone))

## Death. how: "die" (collapse), "head" (drops like a sack, head whipped
## back), "limp" (cars), "takedown" (knees go, slumps back onto the attacker).
func die(impulse: Vector3, bone: String, how: String) -> void:
	if dead:
		return
	dead = true
	_ensure_ragdoll()
	if how == "takedown" and not ragdoll.is_running():
		_seq = true
		tree.set("parameters/hitpose/transition_request", "head")
		tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		tree.set("parameters/ts_kneel/scale", 4.0)
		tree.set("parameters/kneel/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		await get_tree().create_timer(0.38).timeout
		_seq = false
		if not is_instance_valid(ragdoll):
			return
		ragdoll.knock("UpperChest", impulse, "limp")
	else:
		_drop(impulse, bone, how)
	_active.append(self)
	while _active.size() > MAX_ACTIVE:
		var old: NpcBody = _active.pop_front()
		if is_instance_valid(old):
			old.retire()

func _drop(impulse: Vector3, bone: String, how: String) -> void:
	if not ragdoll.bones.has(bone):
		bone = "UpperChest"
	if ragdoll.is_running():
		# Already on the ground (or flying): the muscles give out.
		ragdoll._end_writhe()
		ragdoll.collapse({"legs": 0.05, "spine": 0.3, "head": 0.3, "arms": 0.5}, 0.5)
		ragdoll._blow(bone, impulse)
		return
	match how:
		"head":
			# Lights out: no tone anywhere, the head snaps back along the shot.
			ragdoll.knock("Head", impulse * 0.6, "limp", npc.velocity)
			var hb := ragdoll.bones.get("Head") as PhysicalBone3D
			if hb:
				var d := impulse.normalized()
				hb.angular_velocity += Vector3.UP.cross(d).normalized() * 16.0
				hb.linear_velocity += d * 3.5 + Vector3.UP * 0.6
			var ub := ragdoll.bones.get("UpperChest") as PhysicalBone3D
			if ub:
				ub.linear_velocity += impulse.normalized() * 0.8
		"limp":
			ragdoll.knock(bone, impulse, "limp", npc.velocity)
		_:
			ragdoll.knock(bone, impulse, "die", npc.velocity)

func _on_settled() -> void:
	if dead and not _flying:
		get_tree().create_timer(1.5).timeout.connect(func():
			if is_instance_valid(ragdoll) and dead and not _flying:
				ragdoll.set_physics_process(false))

## Too many bodies lying about: keep this one's pose, drop its physics.
func retire() -> void:
	if ragdoll == null or _retired or not dead:
		return
	_retired = true
	skeleton.skeleton_updated.connect(_freeze, CONNECT_ONE_SHOT)

func _freeze() -> void:
	var poses: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_global_pose(i))
	_apply_freeze.call_deferred(poses)

func _apply_freeze(poses: Array[Transform3D]) -> void:
	if not is_instance_valid(ragdoll):
		return
	ragdoll.stop()
	tree.active = false
	for i in skeleton.get_bone_count():
		var p := skeleton.get_bone_parent(i)
		var local: Transform3D = poses[i] if p < 0 else poses[p].affine_inverse() * poses[i]
		skeleton.set_bone_pose_position(i, local.origin)
		skeleton.set_bone_pose_rotation(i, local.basis.orthonormalized().get_rotation_quaternion())

func is_physical() -> bool:
	return ragdoll != null and ragdoll.is_running() and not _retired

## Where the body is now (hips), world.
func center() -> Vector3:
	if is_physical() and ragdoll.bones.has("Hips"):
		return (ragdoll.bones["Hips"] as PhysicalBone3D).global_position
	var i := skeleton.find_bone("Hips")
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin

## World position of a bone (for the rope).
func bone_position(bone: String) -> Vector3:
	if is_physical() and ragdoll.bones.has(bone):
		return (ragdoll.bones[bone] as PhysicalBone3D).global_position
	var i := skeleton.find_bone(bone)
	if i < 0:
		return center()
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin

# ------------------------------------------------------------- the line

## Thrown along `v` (m/s, world): the body leaves its feet and flies, arms
## flailing; when it hits something hard, `crashed` fires with the speed.
func fling(v: Vector3) -> void:
	if _retired:
		return
	_ensure_ragdoll()
	if not ragdoll.is_running():
		ragdoll.start(v)
		ragdoll.fall(0.45, 2.2, true)
	else:
		ragdoll._end_writhe()
		if not dead:
			ragdoll.fall(0.45, 2.2, true)
		ragdoll.set_physics_process(true)
		for pb: PhysicalBone3D in ragdoll.bones.values():
			PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
			pb.linear_velocity = v * randf_range(0.95, 1.05)
	if not dead:
		downed = true
	_flying = true
	_fly_t = 0.0
	_fly_prev = v.length()

## Keep pulling while the line is taut (the tether): steer toward `at`.
func pull_toward(at: Vector3, speed: float, dt: float) -> void:
	if not is_physical():
		return
	for pb: PhysicalBone3D in ragdoll.bones.values():
		var to := at - pb.global_position
		var want := to.normalized() * speed
		pb.linear_velocity = pb.linear_velocity.lerp(want, clampf(dt * 6.0, 0.0, 1.0))

func flying() -> bool:
	return _flying

func _physics_process(dt: float) -> void:
	if not _flying or not is_physical():
		return
	_fly_t += dt
	var hips := ragdoll.bones.get("Hips") as PhysicalBone3D
	if hips == null:
		_flying = false
		return
	var s := hips.linear_velocity.length()
	if _fly_t > 0.08 and _fly_prev > 5.0 and s < _fly_prev * 0.45:
		_flying = false
		crashed.emit(_fly_prev, hips.global_position)
		if not dead:
			get_tree().create_timer(1.2).timeout.connect(_start_writhe)
		return
	if _fly_t > 3.0 or (_fly_t > 0.5 and s < 1.0):
		_flying = false
		if not dead:
			_start_writhe()
		return
	_fly_prev = maxf(s, _fly_prev * 0.92) if _fly_t < 0.15 else s
