class_name BodyKit
## Humanoid bodies as separate parts, shared by the living NPC (five animated
## pivots) and the death ragdoll (one part per physical bone).
##
## Every part is authored in its own joint frame: Y up, facing -Z, origin at
## the joint, limbs hanging down along -Y. Rest heights (ground = 0):
##   pelvis 0.95, abdomen 1.07, chest 1.33, head 1.56,
##   arm: shoulder 1.47 (x +-0.30), elbow 1.17; leg: hip 0.92 (x +-0.12), knee 0.49.
##
## Guards follow refs/Gemini_Generated_Image: brushed steel plate (open
## kettle helmet with cheek guards, breastplate, layered pauldrons,
## vambraces, greaves) over a brown tunic with a belted skirt. Variant 1 is
## the elite: black carbon armour, a closed helmet, and an ochre scarf and cape.

const P = preload("res://scripts/palette.gd")

const PELVIS_Y := 0.95
const ABDOMEN_Y := 1.07
const CHEST_Y := 1.33
const HEAD_Y := 1.56
const SHOULDER := Vector3(0.30, 1.47, 0)
const ELBOW_DROP := 0.30
const HIP := Vector3(0.12, 0.92, 0)
const KNEE_DROP := 0.43

static func style(kind: String, tint: int) -> Dictionary:
	var st := {"cloth": P.GUARD, "lower": P.CHARCOAL, "accent": P.BURGUNDY, "boot": P.BLACK, "hand": P.SKIN}
	match kind:
		"guard":
			if tint % 2 == 1:
				st = {"cloth": P.CARBON, "lower": P.CARBON, "accent": P.CAPE, "boot": P.BLACK, "hand": P.BLACK, "elite": true}
			else:
				st = {"cloth": P.TUNIC, "lower": P.CHARCOAL, "accent": P.LEATHER, "boot": P.LEATHER, "hand": P.LEATHER, "plate": true}
		"governor":
			st = {"cloth": P.ROBE, "lower": P.ROBE, "accent": P.BRASS, "boot": P.BLACK, "hand": P.SKIN}
		"courier":
			st = {"cloth": P.TERRACOTTA, "lower": P.WARM_GREY, "accent": P.CHARCOAL, "boot": P.BLACK, "hand": P.SKIN}
		"civilian":
			st = {"cloth": [P.WARM_GREY, P.TEAL, P.IVORY, P.TERRACOTTA, P.PETROL][tint % 5],
				"lower": [P.CHARCOAL, P.WARM_GREY, P.PETROL][tint % 3], "accent": P.BEIGE, "boot": P.BLACK, "hand": P.SKIN}
	return st

static func _bx(b: Builder, xf: Transform3D, slot: int, pos: Vector3, size: Vector3, rot := Basis()) -> void:
	b.box_xf(slot, xf * Transform3D(rot, pos), size)

static func _cy(b: Builder, xf: Transform3D, slot: int, pos: Vector3, r0: float, r1: float, h: float, seg := 10) -> void:
	b.cyl_xf(slot, xf * Transform3D(Basis(), pos), r0, r1, h, seg)

## Add one part's primitives to `b`, placed by `xf` (its joint frame).
## part: pelvis, abdomen, chest, head, uarm, farm, thigh, shin. side: -1 left, 1 right.
static func add_part(b: Builder, part: String, kind: String, tint: int, side: int, xf := Transform3D()) -> void:
	var st := style(kind, tint)
	var plate: bool = st.get("plate", false)
	var elite: bool = st.get("elite", false)
	var cloth: int = st.cloth
	var lower: int = st.lower
	var accent: int = st.accent
	match part:
		"pelvis":
			if kind == "governor":
				_cy(b, xf, cloth, Vector3(0, -0.4, 0), 0.38, 0.29, 0.92, 10)
			_bx(b, xf, lower, Vector3(0, -0.02, 0), Vector3(0.44, 0.2, 0.26))
			_bx(b, xf, accent if not plate else P.LEATHER, Vector3(0, 0.06, 0), Vector3(0.48, 0.07, 0.29))
			if plate:
				_bx(b, xf, P.BRASS, Vector3(0, 0.06, -0.148), Vector3(0.07, 0.05, 0.012))
				# Belted tunic skirt to mid-thigh.
				for z in [-0.125, 0.125]:
					_bx(b, xf, P.TUNIC, Vector3(0, -0.2, z), Vector3(0.42, 0.36, 0.035))
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.TUNIC, Vector3(sx * 0.215, -0.18, 0), Vector3(0.035, 0.32, 0.22))
				_bx(b, xf, P.LEATHER, Vector3(0.16, -0.04, -0.14), Vector3(0.08, 0.1, 0.04))  # pouch
			elif elite:
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.CARBON, Vector3(sx * 0.11, -0.16, -0.13), Vector3(0.18, 0.2, 0.025))  # tassets
				_bx(b, xf, P.AMBER, Vector3(-0.17, 0.06, -0.15), Vector3(0.03, 0.02, 0.01))
		"abdomen":
			_bx(b, xf, cloth, Vector3(0, 0.12, 0), Vector3(0.46, 0.3, 0.26))
			if plate:
				_bx(b, xf, P.ARMOR, Vector3(0, 0.13, -0.135), Vector3(0.4, 0.24, 0.02))
				_bx(b, xf, P.ARMOR, Vector3(0, 0.13, 0.135), Vector3(0.4, 0.24, 0.02))
			elif elite:
				for i in 3:
					_bx(b, xf, P.CARBON, Vector3(0, 0.04 + i * 0.08, -0.138), Vector3(0.3, 0.06, 0.02))
		"chest":
			_bx(b, xf, cloth, Vector3(0, 0.06, 0), Vector3(0.5, 0.26, 0.28))
			if plate:
				_bx(b, xf, P.ARMOR, Vector3(0, 0.06, -0.152), Vector3(0.46, 0.24, 0.035))
				_bx(b, xf, P.ARMOR, Vector3(0, 0.06, -0.174), Vector3(0.035, 0.22, 0.015))  # ridge
				_bx(b, xf, P.ARMOR, Vector3(0, 0.06, 0.15), Vector3(0.46, 0.24, 0.03))
				_cy(b, xf, P.ARMOR, Vector3(0, 0.2, 0), 0.13, 0.11, 0.07, 10)  # gorget
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.ARMOR, Vector3(sx * 0.29, 0.15, 0), Vector3(0.19, 0.07, 0.31))
					_bx(b, xf, P.ARMOR, Vector3(sx * 0.33, 0.09, 0), Vector3(0.15, 0.06, 0.29))
					_bx(b, xf, P.LEATHER, Vector3(sx * 0.12, 0.08, -0.172), Vector3(0.03, 0.2, 0.01))  # straps
			elif elite:
				_bx(b, xf, P.CARBON, Vector3(0, 0.06, -0.152), Vector3(0.44, 0.22, 0.035))
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.CARBON, Vector3(sx * 0.29, 0.14, 0), Vector3(0.2, 0.09, 0.3))
				# Ochre scarf and a cape hanging behind to the calves.
				_cy(b, xf, P.CAPE, Vector3(0, 0.18, 0), 0.22, 0.15, 0.13, 10)
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.CAPE, Vector3(sx * 0.2, 0.12, 0.08), Vector3(0.14, 0.08, 0.2))
				_bx(b, xf, P.CAPE, Vector3(0, -0.5, 0.2), Vector3(0.58, 1.15, 0.03), Basis(Vector3.RIGHT, -0.08))
				_bx(b, xf, P.CAPE, Vector3(-0.22, -0.05, -0.16), Vector3(0.1, 0.3, 0.02), Basis(Vector3.BACK, 0.3))
			elif kind == "governor":
				_bx(b, xf, accent, Vector3(0, 0.05, -0.18), Vector3(0.12, 0.6, 0.04))
		"head":
			_bx(b, xf, P.SKIN, Vector3(0, 0.07, 0), Vector3(0.21, 0.25, 0.23))
			if plate:
				# Open kettle helmet: dome, ridge, brim, cheek guards, neck guard.
				_cy(b, xf, P.ARMOR, Vector3(0, 0.215, 0.005), 0.152, 0.12, 0.1, 12)
				_cy(b, xf, P.ARMOR, Vector3(0, 0.285, 0.005), 0.12, 0.05, 0.05, 12)
				_cy(b, xf, P.ARMOR, Vector3(0, 0.165, 0.005), 0.175, 0.175, 0.02, 12)
				_bx(b, xf, P.ARMOR, Vector3(0, 0.27, 0.005), Vector3(0.02, 0.06, 0.25))
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.ARMOR, Vector3(sx * 0.118, 0.06, -0.01), Vector3(0.022, 0.15, 0.17))
				_bx(b, xf, P.ARMOR, Vector3(0, 0.08, 0.125), Vector3(0.22, 0.13, 0.022))
				_bx(b, xf, P.BLACK, Vector3(0, 0.12, -0.118), Vector3(0.16, 0.025, 0.006))  # brow shadow
			elif elite:
				# Closed black helmet with a dark glass visor band.
				_bx(b, xf, P.CARBON, Vector3(0, 0.09, 0.005), Vector3(0.25, 0.3, 0.27))
				_cy(b, xf, P.CARBON, Vector3(0, 0.25, 0.005), 0.135, 0.09, 0.06, 12)
				_bx(b, xf, P.PETROL, Vector3(0, 0.1, -0.138), Vector3(0.21, 0.065, 0.01))
				_bx(b, xf, P.AMBER, Vector3(0.07, 0.1, -0.144), Vector3(0.02, 0.012, 0.004))
				_bx(b, xf, P.CARBON, Vector3(0, -0.02, -0.13), Vector3(0.14, 0.08, 0.03))
			elif kind == "governor":
				_cy(b, xf, P.IVORY, Vector3(0, 0.23, 0), 0.15, 0.13, 0.12, 10)
				_cy(b, xf, P.BRASS, Vector3(0, 0.18, 0), 0.155, 0.155, 0.03, 10)
			else:
				_bx(b, xf, P.BLACK, Vector3(0, 0.18, 0.02), Vector3(0.23, 0.06, 0.25))
		"uarm":
			_bx(b, xf, cloth, Vector3(0, -0.15, 0), Vector3(0.13, 0.31, 0.14))
			if plate:
				_bx(b, xf, P.ARMOR, Vector3(0, -0.2, 0), Vector3(0.145, 0.14, 0.15))
			elif elite:
				_bx(b, xf, P.CARBON, Vector3(0, -0.12, 0), Vector3(0.145, 0.18, 0.15))
		"farm":
			_bx(b, xf, cloth, Vector3(0, -0.13, 0), Vector3(0.12, 0.26, 0.13))
			_bx(b, xf, st.hand, Vector3(0, -0.31, 0), Vector3(0.1, 0.1, 0.1))
			if plate:
				_bx(b, xf, P.ARMOR, Vector3(0, -0.13, 0), Vector3(0.135, 0.2, 0.145))
			elif elite:
				_bx(b, xf, P.CARBON, Vector3(0, -0.13, 0), Vector3(0.135, 0.22, 0.145))
				_bx(b, xf, P.AMBER, Vector3(side * 0.07, -0.09, -0.03), Vector3(0.006, 0.02, 0.02))
			if kind == "guard" and side > 0:
				# Carbine held at the hip.
				_bx(b, xf, P.CHARCOAL, Vector3(0, -0.32, -0.3), Vector3(0.07, 0.12, 0.7))
				_bx(b, xf, P.BEIGE, Vector3(0, -0.26, -0.15), Vector3(0.08, 0.1, 0.3))
		"thigh":
			_bx(b, xf, lower, Vector3(0, -0.21, 0), Vector3(0.17, 0.43, 0.19))
			if elite:
				_bx(b, xf, P.CARBON, Vector3(0, -0.2, -0.1), Vector3(0.15, 0.3, 0.02))
		"shin":
			_bx(b, xf, lower, Vector3(0, -0.2, 0), Vector3(0.16, 0.4, 0.18))
			_bx(b, xf, st.boot, Vector3(0, -0.44, -0.04), Vector3(0.18, 0.1, 0.28))
			if plate:
				_bx(b, xf, P.ARMOR, Vector3(0, -0.2, -0.02), Vector3(0.175, 0.3, 0.18))
				_bx(b, xf, P.ARMOR, Vector3(0, 0.0, -0.085), Vector3(0.15, 0.1, 0.05))
				_bx(b, xf, st.boot, Vector3(0, -0.36, 0), Vector3(0.185, 0.08, 0.2))
			elif elite:
				_bx(b, xf, P.CARBON, Vector3(0, -0.18, -0.02), Vector3(0.175, 0.32, 0.18))
				_bx(b, xf, P.CARBON, Vector3(0, 0.0, -0.09), Vector3(0.14, 0.1, 0.05))

static func part_mesh(part: String, kind: String, tint: int, side: int) -> Mesh:
	var key := "bk_%s_%s_%d_%d" % [part, kind, style_key(kind, tint), side if part in ["farm", "uarm"] else 0]
	return Builder.cached(key, func():
		var b := Builder.new(0.2)
		add_part(b, part, kind, tint, side)
		return b.mesh())

## Tints that look the same share meshes.
static func style_key(kind: String, tint: int) -> int:
	match kind:
		"guard":
			return tint % 2
		"civilian":
			return tint % 15
	return 0

# ------------------------------------------------------------- living body

## The five pivots the Rust Npc animates: Visual, Visual/LegL, LegR, ArmL, ArmR.
static func living(kind: String, tint := 0) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var body := MeshInstance3D.new()
	body.mesh = Builder.cached("bk_body_%s_%d" % [kind, style_key(kind, tint)], func():
		var b := Builder.new(0.25)
		add_part(b, "pelvis", kind, tint, 0, Transform3D(Basis(), Vector3(0, PELVIS_Y, 0)))
		add_part(b, "abdomen", kind, tint, 0, Transform3D(Basis(), Vector3(0, ABDOMEN_Y, 0)))
		add_part(b, "chest", kind, tint, 0, Transform3D(Basis(), Vector3(0, CHEST_Y, 0)))
		add_part(b, "head", kind, tint, 0, Transform3D(Basis(), Vector3(0, HEAD_Y, 0)))
		return b.mesh())
	root.add_child(body)
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.position = Vector3(HIP.x * side, HIP.y, 0)
		var lm := MeshInstance3D.new()
		lm.mesh = Builder.cached("bk_leg_%s_%d" % [kind, style_key(kind, tint)], func():
			var b := Builder.new(0.2)
			add_part(b, "thigh", kind, tint, side)
			add_part(b, "shin", kind, tint, side, Transform3D(Basis(), Vector3(0, -KNEE_DROP, 0)))
			return b.mesh())
		leg.add_child(lm)
		root.add_child(leg)
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0 else "ArmR"
		arm.position = Vector3(SHOULDER.x * side, SHOULDER.y, 0)
		var am := MeshInstance3D.new()
		am.mesh = Builder.cached("bk_arm_%s_%d_%d" % [kind, style_key(kind, tint), side], func():
			var b := Builder.new(0.2)
			add_part(b, "uarm", kind, tint, side)
			add_part(b, "farm", kind, tint, side, Transform3D(Basis(), Vector3(0, -ELBOW_DROP, 0)))
			return b.mesh())
		arm.add_child(am)
		root.add_child(arm)
	for c in root.get_children():
		for m in ([c] + c.get_children()):
			if m is GeometryInstance3D:
				m.visibility_range_end = 95.0
	return root
