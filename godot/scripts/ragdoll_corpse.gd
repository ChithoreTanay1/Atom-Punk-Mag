class_name RagdollCorpse
extends Node3D
## Death ragdoll for the procedural NPCs, driven by the Active Ragdoll addon
## (addons/active_ragdoll, MIT, Danil Khmyrov).
##
## Living NPCs keep their cheap five-pivot animation. When one dies we build
## a humanoid Skeleton3D here, with bones named per SkeletonProfileHumanoid
## (what the addon expects), copy the NPC's current limb swing into it, hang
## the BodyKit parts on the bones with BoneAttachment3D, then let the addon
## take over: collapse (legs give first) plus a knock in the direction of the
## killing blow. Once settled the muscles switch off and Jolt lets the bodies
## sleep; past MAX_ACTIVE the oldest corpse is swapped back to a static pose.

const MAX_ACTIVE := 10
const LAYER := 1 << 9          # own layer: not shot, not walked on by NPCs
const MASK := 1 | 8            # world and cars

static var _active: Array = []

var skeleton: Skeleton3D
var ragdoll: ActiveRagdoll
var npc: Npc
var _settle_t := -1.0

## Bone: [parent, global rest position, part mesh or "", side].
const BONES := {
	"Hips": ["", Vector3(0, 0.95, 0), "pelvis", 0],
	"Spine": ["Hips", Vector3(0, 1.07, 0), "abdomen", 0],
	"Chest": ["Spine", Vector3(0, 1.2, 0), "", 0],
	"UpperChest": ["Chest", Vector3(0, 1.33, 0), "chest", 0],
	"Neck": ["UpperChest", Vector3(0, 1.5, 0), "", 0],
	"Head": ["Neck", Vector3(0, 1.56, 0), "head", 0],
	"LeftShoulder": ["UpperChest", Vector3(-0.12, 1.45, 0), "", -1],
	"LeftUpperArm": ["LeftShoulder", Vector3(-0.3, 1.47, 0), "uarm", -1],
	"LeftLowerArm": ["LeftUpperArm", Vector3(-0.3, 1.17, 0), "farm", -1],
	"LeftHand": ["LeftLowerArm", Vector3(-0.3, 0.87, 0), "", -1],
	"RightShoulder": ["UpperChest", Vector3(0.12, 1.45, 0), "", 1],
	"RightUpperArm": ["RightShoulder", Vector3(0.3, 1.47, 0), "uarm", 1],
	"RightLowerArm": ["RightUpperArm", Vector3(0.3, 1.17, 0), "farm", 1],
	"RightHand": ["RightLowerArm", Vector3(0.3, 0.87, 0), "", 1],
	"LeftUpperLeg": ["Hips", Vector3(-0.12, 0.92, 0), "thigh", -1],
	"LeftLowerLeg": ["LeftUpperLeg", Vector3(-0.12, 0.49, 0), "shin", -1],
	"LeftFoot": ["LeftLowerLeg", Vector3(-0.12, 0.08, 0), "", -1],
	"LeftToes": ["LeftFoot", Vector3(-0.12, 0.02, -0.15), "", -1],
	"RightUpperLeg": ["Hips", Vector3(0.12, 0.92, 0), "thigh", 1],
	"RightLowerLeg": ["RightUpperLeg", Vector3(0.12, 0.49, 0), "shin", 1],
	"RightFoot": ["RightLowerLeg", Vector3(0.12, 0.08, 0), "", 1],
	"RightToes": ["RightFoot", Vector3(0.12, 0.02, -0.15), "", 1],
}
const CHILD := {
	"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftUpperArm", "LeftUpperArm": "LeftLowerArm", "LeftLowerArm": "LeftHand",
	"RightShoulder": "RightUpperArm", "RightUpperArm": "RightLowerArm", "RightLowerArm": "RightHand",
	"LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot", "LeftFoot": "LeftToes",
	"RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot", "RightFoot": "RightToes",
}

## Bone basis with +Y pointing at its child (humanoid convention).
static func _bone_basis(name: String) -> Basis:
	if not CHILD.has(name):
		# Leaf bones (head, hands, toes) keep their parent's frame.
		var parent: String = BONES[name][0]
		return _bone_basis(parent) if parent != "" else Basis()
	var d: Vector3 = (BONES[CHILD[name]][1] - BONES[name][1]).normalized()
	if d.dot(Vector3.DOWN) > 0.999:
		return Basis(Vector3.BACK, PI)
	if absf(d.y) > 0.999:
		return Basis()
	if absf(d.x) > 0.9:
		return Basis(Vector3.BACK, -PI / 2 * signf(d.x))
	return Basis(Vector3.RIGHT, atan2(d.z, d.y))

## Build and start a ragdoll from a dead NPC. Hides the NPC's own visual.
static func spawn(n: Npc, impulse: Vector3, bone := "UpperChest", how := "die") -> RagdollCorpse:
	var vis := n.get_node_or_null("Visual") as Node3D
	if vis == null:
		return null
	var c := RagdollCorpse.new()
	c.npc = n
	n.get_parent().add_child(c)
	c.global_transform = n.global_transform
	c._build(str(n.role), int(n.get_meta("tint", 0)), vis)
	vis.visible = false
	c.ragdoll.knock(bone, impulse, how)
	_active.append(c)
	while _active.size() > MAX_ACTIVE:
		var old: RagdollCorpse = _active.pop_front()
		if is_instance_valid(old):
			old.retire()
	return c

func _build(kind: String, tint: int, vis: Node3D) -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	var order := BONES.keys()
	for bn: String in order:
		skeleton.add_bone(bn)
	for bn: String in order:
		var i := skeleton.find_bone(bn)
		var parent: String = BONES[bn][0]
		var g := Transform3D(_bone_basis(bn), BONES[bn][1])
		if parent != "":
			var pi := skeleton.find_bone(parent)
			skeleton.set_bone_parent(i, pi)
			var pg := Transform3D(_bone_basis(parent), BONES[parent][1])
			skeleton.set_bone_rest(i, pg.affine_inverse() * g)
		else:
			skeleton.set_bone_rest(i, g)
		skeleton.reset_bone_pose(i)
	# The pose at the moment of death: limb swing from the living pivots and
	# the visual's own tilt.
	skeleton.transform = vis.transform
	for pair in [["LegL", "LeftUpperLeg"], ["LegR", "RightUpperLeg"], ["ArmL", "LeftUpperArm"], ["ArmR", "RightUpperArm"]]:
		var pivot := vis.get_node_or_null(pair[0]) as Node3D
		if pivot == null:
			continue
		var bn: String = pair[1]
		var i := skeleton.find_bone(bn)
		var parent: String = BONES[bn][0]
		var pg := Transform3D(_bone_basis(parent), BONES[parent][1])
		var g := Transform3D(Basis(Vector3.RIGHT, pivot.rotation.x) * _bone_basis(bn), BONES[bn][1])
		var local := pg.affine_inverse() * g
		skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	# Body parts on the bones. Parts are authored Y-up; undo the bone basis.
	for bn: String in order:
		var part: String = BONES[bn][2]
		if part == "":
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = bn
		skeleton.add_child(att)
		var mi := MeshInstance3D.new()
		mi.mesh = BodyKit.part_mesh(part, kind, tint, int(BONES[bn][3]))
		mi.basis = _bone_basis(bn).inverse()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 95.0
		att.add_child(mi)
	var profile := RagdollProfile.humanoid()
	ragdoll = ActiveRagdoll.create(skeleton, profile)
	ragdoll.collision_layer = LAYER
	ragdoll.collision_mask = MASK
	ragdoll.settled.connect(func(): _settle_t = 1.5)

func _physics_process(dt: float) -> void:
	if _settle_t > 0.0:
		_settle_t -= dt
		if _settle_t <= 0.0 and ragdoll:
			# Limp now: stop the muscle loop, the solver sleeps the bodies.
			ragdoll.set_physics_process(false)

## Too many corpses: drop the physics and show the NPC's own fallen pose.
func retire() -> void:
	if is_instance_valid(npc):
		var vis := npc.get_node_or_null("Visual") as Node3D
		if vis:
			vis.visible = true
			if ragdoll and skeleton.find_bone("Hips") >= 0:
				var hips := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hips"))
				npc.global_position = Vector3(hips.origin.x, npc.global_position.y, hips.origin.z)
	queue_free()

func _exit_tree() -> void:
	_active.erase(self)

## Where the body is now (world), for discovery checks.
func hips_position() -> Vector3:
	if skeleton == null:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
