class_name BodyKit
## Humanoid bodies as separate parts, one per animated bone of NpcBody (the
## Quaternius skeleton). The same part meshes ride the bones while the body
## is animated and while it is a ragdoll.
##
## Every part is authored in its own joint frame, origin at the joint:
##   torso-style parts (pelvis, abdomen, chest, head, foot): Y up, facing -Z.
##   limbs (uarm, farm, thigh, shin): hanging down along -Y, facing -Z.
## Segment lengths match the skeleton: upper arm 0.275, forearm 0.27,
## thigh 0.40, shin 0.43, ankle 0.10 above the ground.
##
## Shapes are rounded (ellipsoids from stacked rings, tapered cylinders)
## rather than boxes, following refs/Gemini_Generated_Image: guards in
## brushed steel plate (kettle helmet with brim and cheek guards, domed
## pauldrons, breastplate, knee and elbow cops, greaves) over a brown tunic;
## elites (tint 1) in black segmented carbon with a closed visor helmet, an
## ochre scarf and cape and a sword; the governor in a long ochre robe with
## gold trim over carbon collar and pauldrons.

const P = preload("res://scripts/palette.gd")

const UARM := 0.275
const FARM := 0.27
const THIGH := 0.40
const SHIN := 0.43
const ANKLE := 0.10

static func style(kind: String, tint: int) -> Dictionary:
	var st := {"cloth": P.GUARD, "lower": P.CHARCOAL, "accent": P.BURGUNDY, "boot": P.BLACK, "hand": P.SKIN, "hair": P.BLACK}
	match kind:
		"guard":
			if tint == 2:
				# Avekṣā Corp [INVENTED]: petrol fatigues, amber armband, soft
				# leather kit. Security contractors, not soldiers: no plate.
				st = {"cloth": P.PETROL, "lower": P.CHARCOAL, "accent": P.VISOR, "boot": P.BLACK, "hand": P.BLACK, "hair": P.BLACK}
			elif tint % 2 == 1:
				st = {"cloth": P.CARBON, "lower": P.CARBON, "accent": P.CAPE, "boot": P.BLACK, "hand": P.BLACK, "hair": P.BLACK, "elite": true}
			else:
				st = {"cloth": P.TUNIC, "lower": P.CHARCOAL, "accent": P.LEATHER, "boot": P.LEATHER, "hand": P.LEATHER, "hair": P.BLACK, "plate": true}
		"governor":
			st = {"cloth": P.CAPE, "lower": P.CHARCOAL, "accent": P.BRASS, "boot": P.LEATHER, "hand": P.BLACK, "hair": P.WARM_GREY, "robe": true}
		"courier":
			st = {"cloth": P.TERRACOTTA, "lower": P.WARM_GREY, "accent": P.CHARCOAL, "boot": P.BLACK, "hand": P.SKIN, "hair": P.BLACK, "bag": true}
		"civilian" when tint >= 100:
			# A festival pilgrim: the crowd's robes, up close.
			var robe: int = [P.LEATHER, P.IVORY, P.BURGUNDY, P.TERRACOTTA, P.PETROL][(tint - 100) % 5]
			st = {"cloth": robe, "lower": robe, "accent": P.BEIGE, "boot": P.BLACK, "hand": P.SKIN, "hair": P.BLACK, "robe": true}
		"civilian":
			st = {"cloth": [P.WARM_GREY, P.TEAL, P.IVORY, P.TERRACOTTA, P.PETROL][tint % 5],
				"lower": [P.CHARCOAL, P.WARM_GREY, P.PETROL][tint % 3], "accent": P.BEIGE, "boot": P.BLACK, "hand": P.SKIN,
				"hair": [P.BLACK, P.CHARCOAL, P.WARM_GREY][tint % 3], "jacket": tint % 2 == 0}
	return st

# ------------------------------------------------------------- primitives

static func _bx(b: Builder, xf: Transform3D, slot: int, pos: Vector3, size: Vector3, rot := Basis()) -> void:
	b.box_xf(slot, xf * Transform3D(rot, pos), size)

## Cylinder centred at pos along Y; `sz` squashes it front-to-back (elliptic).
static func _cy(b: Builder, xf: Transform3D, slot: int, pos: Vector3, r0: float, r1: float, h: float, seg := 10, sz := 1.0, rot := Basis(), caps := true) -> void:
	b.cyl_xf(slot, xf * Transform3D(rot * Basis.from_scale(Vector3(1, 1, sz)), pos), r0, r1, h, seg, caps)

## Ellipsoid from stacked rings. `top_only` builds the upper half (domes).
static func _el(b: Builder, xf: Transform3D, slot: int, pos: Vector3, r: Vector3, seg := 10, rings := 4, rot := Basis(), top_only := false) -> void:
	var t0 := 0.0 if top_only else -PI / 2
	for i in rings:
		var a0 := lerpf(t0, PI / 2, float(i) / rings)
		var a1 := lerpf(t0, PI / 2, float(i + 1) / rings)
		var y0 := sin(a0) * r.y
		var y1 := sin(a1) * r.y
		var c0 := cos(a0)
		var c1 := cos(a1)
		var h := y1 - y0
		if h < 1e-4:
			continue
		var cap := i == rings - 1 or (i == 0 and top_only)
		b.cyl_xf(slot, xf * Transform3D(rot * Basis.from_scale(Vector3(r.x, 1, r.z)), pos + rot * Vector3(0, (y0 + y1) * 0.5, 0)), c0, c1, h, seg, cap)

## Limb segment hanging from the joint: tapered, slightly flattened.
static func _limb(b: Builder, xf: Transform3D, slot: int, length: float, r_top: float, r_bot: float, y0 := 0.0, sz := 0.9) -> void:
	_cy(b, xf, slot, Vector3(0, y0 - length * 0.5, 0), r_bot, r_top, length, 10, sz)

# ------------------------------------------------------------- parts

## Add one part's primitives to `b`, placed by `xf` (its joint frame).
## part: pelvis, abdomen, chest, head, uarm, farm, thigh, shin, foot. side: -1 left, 1 right.
static func add_part(b: Builder, part: String, kind: String, tint: int, side: int, xf := Transform3D()) -> void:
	var st := style(kind, tint)
	var plate: bool = st.get("plate", false)
	var elite: bool = st.get("elite", false)
	var robe: bool = st.get("robe", false)
	var cloth: int = st.cloth
	var lower: int = st.lower
	var accent: int = st.accent
	match part:
		"pelvis":
			_el(b, xf, lower, Vector3(0, 0.0, 0), Vector3(0.165, 0.11, 0.115), 10, 3)
			# Belt with a buckle and kit on it.
			var belt := P.LEATHER if (plate or elite or robe) else P.BLACK
			_cy(b, xf, belt, Vector3(0, 0.075, 0), 0.172, 0.17, 0.055, 12, 0.72)
			_bx(b, xf, P.BRASS, Vector3(0, 0.075, -0.124), Vector3(0.055, 0.04, 0.012))
			if plate:
				# Tunic skirt to mid-thigh, open at the bottom, with a leather apron.
				_cy(b, xf, P.TUNIC, Vector3(0, -0.13, 0), 0.235, 0.18, 0.3, 12, 0.78, Basis(), false)
				_bx(b, xf, P.LEATHER, Vector3(0, -0.13, -0.178), Vector3(0.13, 0.26, 0.012))
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.LEATHER, Vector3(sx * 0.13, 0.03, -0.12), Vector3(0.07, 0.08, 0.04))  # pouches
					_bx(b, xf, P.BRASS, Vector3(sx * 0.13, 0.055, -0.141), Vector3(0.02, 0.012, 0.004))
			elif elite:
				for sx in [-1.0, 1.0]:
					_el(b, xf, P.CARBON, Vector3(sx * 0.11, -0.1, -0.06), Vector3(0.08, 0.11, 0.07), 8, 3)  # tassets
				_bx(b, xf, P.AMBER, Vector3(-0.15, 0.075, -0.1), Vector3(0.025, 0.015, 0.01))
				_bx(b, xf, P.CHARCOAL, Vector3(0.17, 0.0, -0.02), Vector3(0.05, 0.12, 0.09))       # holster box
				_bx(b, xf, P.CRT, Vector3(0.196, 0.02, -0.02), Vector3(0.004, 0.03, 0.04))
				_sword(b, xf, Vector3(-0.19, 0.03, 0.02))
			elif robe:
				# Long robe to the shins with gold hem and a front trim.
				_cy(b, xf, P.CAPE, Vector3(0, -0.42, 0), 0.33, 0.2, 0.92, 14, 0.82, Basis(), false)
				_cy(b, xf, P.BRASS, Vector3(0, -0.87, 0), 0.335, 0.33, 0.04, 14, 0.82, Basis(), false)
				_bx(b, xf, P.BRASS, Vector3(0.05, -0.42, -0.215), Vector3(0.03, 0.9, 0.01), Basis(Vector3.RIGHT, -0.14))
				_bx(b, xf, P.LEATHER, Vector3(0.15, -0.02, -0.12), Vector3(0.07, 0.12, 0.05))       # belt device
				_bx(b, xf, P.AMBER, Vector3(0.15, 0.0, -0.147), Vector3(0.05, 0.04, 0.005))
				_sword(b, xf, Vector3(-0.17, 0.03, -0.02))
			elif st.get("bag", false):
				_bx(b, xf, P.LEATHER, Vector3(0.2, -0.04, 0.04), Vector3(0.07, 0.2, 0.26))         # dispatch bag
				_bx(b, xf, P.BRASS, Vector3(0.237, -0.0, 0.04), Vector3(0.006, 0.03, 0.05))
		"abdomen":
			if robe:
				_cy(b, xf, P.CAPE, Vector3(0, 0.13, 0), 0.19, 0.21, 0.28, 12, 0.72)
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.BRASS, Vector3(sx * 0.06, 0.13, -0.15), Vector3(0.022, 0.28, 0.01), Basis(Vector3.FORWARD, sx * 0.12))
				return
			_cy(b, xf, cloth, Vector3(0, 0.13, 0), 0.155, 0.175, 0.28, 12, 0.7)
			if plate:
				# Faulds: overlapping steel bands.
				for i in 3:
					_cy(b, xf, P.ARMOR, Vector3(0, 0.04 + i * 0.075, -0.005), 0.172 + i * 0.004, 0.178 + i * 0.004, 0.07, 12, 0.74, Basis(), false)
			elif elite:
				for row in 3:
					for sx in [-1.0, 1.0]:
						_el(b, xf, P.CARBON, Vector3(sx * 0.055, 0.04 + row * 0.08, -0.11), Vector3(0.05, 0.035, 0.025), 8, 2)
			elif st.get("jacket", false):
				_bx(b, xf, P.BLACK, Vector3(0, 0.13, -0.124), Vector3(0.012, 0.26, 0.006))        # jacket seam
				for i in 3:
					_bx(b, xf, P.BRASS, Vector3(0.022, 0.06 + i * 0.07, -0.125), Vector3(0.012, 0.012, 0.006))
		"chest":
			if robe:
				_el(b, xf, P.CAPE, Vector3(0, 0.07, 0), Vector3(0.215, 0.17, 0.145), 12, 4)
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.BRASS, Vector3(sx * 0.065, 0.05, -0.148), Vector3(0.024, 0.24, 0.012), Basis(Vector3.FORWARD, sx * 0.25))
				# Carbon armour showing at the collar and shoulders.
				_cy(b, xf, P.CARBON, Vector3(0, 0.205, 0), 0.12, 0.085, 0.13, 12, 0.9)
				_el(b, xf, P.CARBON, Vector3(0, 0.1, -0.06), Vector3(0.11, 0.1, 0.08), 10, 3)
				for sx in [-1.0, 1.0]:
					_el(b, xf, P.CARBON, Vector3(sx * 0.26, 0.13, 0), Vector3(0.11, 0.08, 0.12), 10, 3, Basis(), true)
					_el(b, xf, P.CARBON, Vector3(sx * 0.29, 0.08, 0), Vector3(0.09, 0.06, 0.11), 10, 3, Basis(), true)
				return
			_el(b, xf, cloth, Vector3(0, 0.07, 0), Vector3(0.205, 0.165, 0.135), 12, 4)
			_cy(b, xf, cloth, Vector3(0, 0.2, 0), 0.07, 0.06, 0.08, 8)  # neck base
			if plate:
				# Breastplate with a centre ridge, backplate, gorget and domed pauldrons.
				_el(b, xf, P.ARMOR, Vector3(0, 0.06, -0.01), Vector3(0.212, 0.16, 0.142), 12, 4)
				_bx(b, xf, P.ARMOR, Vector3(0, 0.06, -0.148), Vector3(0.022, 0.24, 0.02))
				_cy(b, xf, P.ARMOR, Vector3(0, 0.205, 0), 0.115, 0.095, 0.07, 12, 0.92)
				for sx in [-1.0, 1.0]:
					_el(b, xf, P.ARMOR, Vector3(sx * 0.25, 0.13, 0), Vector3(0.12, 0.085, 0.13), 10, 3, Basis(Vector3.FORWARD, sx * 0.3), true)
					_el(b, xf, P.ARMOR, Vector3(sx * 0.29, 0.07, 0), Vector3(0.1, 0.06, 0.12), 10, 3, Basis(Vector3.FORWARD, sx * 0.45), true)
					_bx(b, xf, P.LEATHER, Vector3(sx * 0.11, 0.07, -0.148), Vector3(0.025, 0.2, 0.01))
					_bx(b, xf, P.BRASS, Vector3(sx * 0.11, 0.15, -0.155), Vector3(0.018, 0.018, 0.006))
			elif elite:
				# Sculpted carbon: pecs, collar, shoulder domes; ochre scarf and cape.
				for sx in [-1.0, 1.0]:
					_el(b, xf, P.CARBON, Vector3(sx * 0.075, 0.08, -0.095), Vector3(0.09, 0.075, 0.05), 10, 3)
					_el(b, xf, P.CARBON, Vector3(sx * 0.25, 0.13, 0), Vector3(0.12, 0.09, 0.13), 10, 3, Basis(Vector3.FORWARD, sx * 0.3), true)
					_el(b, xf, P.CARBON, Vector3(sx * 0.29, 0.065, 0), Vector3(0.1, 0.06, 0.12), 10, 3, Basis(Vector3.FORWARD, sx * 0.45), true)
				_bx(b, xf, P.AMBER, Vector3(0.12, 0.13, -0.13), Vector3(0.02, 0.01, 0.006))
				_cy(b, xf, P.CAPE, Vector3(0, 0.19, 0.01), 0.21, 0.13, 0.12, 12, 0.85)
				_el(b, xf, P.CAPE, Vector3(-0.1, 0.13, -0.11), Vector3(0.08, 0.06, 0.05), 8, 3)
				_bx(b, xf, P.CAPE, Vector3(-0.17, 0.0, -0.12), Vector3(0.08, 0.22, 0.02), Basis(Vector3.BACK, 0.35))
				# Cape: hangs from the shoulders and flares to the calves, with folds.
				_bx(b, xf, P.CAPE, Vector3(0, -0.12, 0.17), Vector3(0.5, 0.5, 0.025), Basis(Vector3.RIGHT, -0.05))
				_bx(b, xf, P.CAPE, Vector3(0, -0.72, 0.215), Vector3(0.62, 0.75, 0.025), Basis(Vector3.RIGHT, -0.09))
				for i in 4:
					var fx := -0.21 + i * 0.14
					_bx(b, xf, P.CAPE, Vector3(fx, -0.62, 0.235), Vector3(0.04, 0.9, 0.03), Basis(Vector3.RIGHT, -0.09))
			else:
				# Shirt or jacket: collar, placket, shoulder seams.
				_cy(b, xf, st.accent if not st.get("jacket", false) else cloth, Vector3(0, 0.2, 0), 0.085, 0.075, 0.05, 10, 0.95)
				_bx(b, xf, P.BLACK if st.get("jacket", false) else accent, Vector3(0, 0.05, -0.135), Vector3(0.03, 0.22, 0.008))
				for sx in [-1.0, 1.0]:
					_el(b, xf, cloth, Vector3(sx * 0.23, 0.12, 0), Vector3(0.08, 0.06, 0.08), 8, 2, Basis(), true)
				if st.get("jacket", false):
					for sx in [-1.0, 1.0]:
						_bx(b, xf, P.CHARCOAL, Vector3(sx * 0.07, 0.13, -0.132), Vector3(0.06, 0.1, 0.008), Basis(Vector3.FORWARD, sx * 0.5))  # lapels
		"head":
			_cy(b, xf, P.SKIN, Vector3(0, 0.0, 0.0), 0.055, 0.05, 0.1, 8)                    # neck
			_el(b, xf, P.SKIN, Vector3(0, 0.12, 0.0), Vector3(0.092, 0.118, 0.105), 10, 4)    # skull
			_el(b, xf, P.SKIN, Vector3(0, 0.06, -0.035), Vector3(0.07, 0.06, 0.07), 8, 3)    # jaw
			# Face: brow, eyes, nose, mouth, ears.
			_bx(b, xf, P.SKIN, Vector3(0, 0.15, -0.093), Vector3(0.14, 0.022, 0.03))
			for sx in [-1.0, 1.0]:
				_bx(b, xf, P.BLACK, Vector3(sx * 0.036, 0.128, -0.1), Vector3(0.026, 0.011, 0.006))
				_el(b, xf, P.SKIN, Vector3(sx * 0.093, 0.115, 0.005), Vector3(0.014, 0.03, 0.022), 6, 2)
			_bx(b, xf, P.SKIN, Vector3(0, 0.1, -0.108), Vector3(0.026, 0.05, 0.03), Basis(Vector3.RIGHT, 0.25))
			_bx(b, xf, P.LEATHER, Vector3(0, 0.055, -0.1), Vector3(0.04, 0.008, 0.008))
			if plate:
				# Open kettle helmet: dome, comb, wide brim, cheek guards, neck guard.
				_el(b, xf, P.ARMOR, Vector3(0, 0.155, 0.005), Vector3(0.122, 0.12, 0.13), 12, 3, Basis(), true)
				_cy(b, xf, P.ARMOR, Vector3(0, 0.155, 0.005), 0.165, 0.175, 0.016, 14, 1.0)
				_bx(b, xf, P.ARMOR, Vector3(0, 0.235, 0.005), Vector3(0.018, 0.05, 0.22))
				for sx in [-1.0, 1.0]:
					_bx(b, xf, P.ARMOR, Vector3(sx * 0.103, 0.07, -0.025), Vector3(0.016, 0.12, 0.12), Basis(Vector3.FORWARD, sx * 0.1))
					_bx(b, xf, P.BRASS, Vector3(sx * 0.112, 0.11, -0.06), Vector3(0.006, 0.014, 0.014))
				_bx(b, xf, P.ARMOR, Vector3(0, 0.085, 0.11), Vector3(0.2, 0.11, 0.018), Basis(Vector3.RIGHT, 0.2))
				_bx(b, xf, P.LEATHER, Vector3(0, 0.02, -0.04), Vector3(0.19, 0.012, 0.012))      # chin strap
			elif elite:
				# Closed black helmet, dark visor band, chin guard, amber lamp.
				_el(b, xf, P.CARBON, Vector3(0, 0.12, 0.005), Vector3(0.122, 0.148, 0.132), 12, 5)
				_el(b, xf, P.PETROL, Vector3(0, 0.125, -0.02), Vector3(0.112, 0.032, 0.118), 12, 2)
				_el(b, xf, P.CARBON, Vector3(0, 0.035, -0.06), Vector3(0.085, 0.05, 0.07), 10, 3)
				_bx(b, xf, P.CARBON, Vector3(0, 0.2, -0.04), Vector3(0.03, 0.06, 0.18))
				_bx(b, xf, P.AMBER, Vector3(0.09, 0.125, -0.09), Vector3(0.012, 0.01, 0.006))
				_cy(b, xf, P.CARBON, Vector3(0, 0.0, 0.0), 0.075, 0.07, 0.08, 10)
			elif kind == "governor":
				# Grey hair swept back, receding at the temples; lined face.
				_el(b, xf, st.hair, Vector3(0, 0.155, 0.02), Vector3(0.096, 0.09, 0.105), 10, 3, Basis(), true)
				_el(b, xf, st.hair, Vector3(0, 0.12, 0.05), Vector3(0.094, 0.08, 0.07), 10, 3)
				_bx(b, xf, P.LEATHER, Vector3(0, 0.08, -0.096), Vector3(0.09, 0.006, 0.006))
			else:
				_el(b, xf, st.hair, Vector3(0, 0.16, 0.012), Vector3(0.098, 0.085, 0.11), 10, 3, Basis(), true)
				_el(b, xf, st.hair, Vector3(0, 0.12, 0.045), Vector3(0.094, 0.075, 0.07), 10, 2)
				if kind == "courier":
					_cy(b, xf, P.CHARCOAL, Vector3(0, 0.215, 0.0), 0.11, 0.1, 0.05, 12)       # cap
					_bx(b, xf, P.CHARCOAL, Vector3(0, 0.195, -0.12), Vector3(0.15, 0.012, 0.08))
		"uarm":
			_limb(b, xf, cloth, UARM, 0.062, 0.05)
			_el(b, xf, cloth, Vector3(0, -0.01, 0), Vector3(0.065, 0.06, 0.065), 8, 3)
			if plate:
				_limb(b, xf, P.ARMOR, 0.15, 0.064, 0.058, -0.07, 0.95)
				_el(b, xf, P.ARMOR, Vector3(0, -UARM, 0.01), Vector3(0.06, 0.05, 0.065), 8, 3)   # elbow cop
			elif elite:
				_limb(b, xf, P.CARBON, 0.16, 0.066, 0.058, -0.03, 0.95)
				_el(b, xf, P.CARBON, Vector3(0, -UARM, 0.02), Vector3(0.055, 0.055, 0.06), 8, 3)
			elif robe:
				_limb(b, xf, P.CAPE, UARM, 0.075, 0.07, 0.0, 0.95)
		"farm":
			_limb(b, xf, cloth, FARM, 0.05, 0.04)
			# Hand: palm, fingers curled, thumb.
			var hand: int = st.hand
			_el(b, xf, hand, Vector3(0, -FARM - 0.045, 0), Vector3(0.035, 0.055, 0.045), 8, 3)
			_bx(b, xf, hand, Vector3(0, -FARM - 0.09, -0.012), Vector3(0.05, 0.04, 0.05))
			_el(b, xf, hand, Vector3(side * -0.02, -FARM - 0.04, -0.035), Vector3(0.015, 0.03, 0.015), 6, 2)
			if plate:
				_limb(b, xf, P.ARMOR, 0.17, 0.054, 0.046, -0.05, 0.95)   # vambrace
				_cy(b, xf, P.LEATHER, Vector3(0, -FARM + 0.01, 0), 0.046, 0.044, 0.04, 8)
			elif elite:
				_limb(b, xf, P.CARBON, 0.2, 0.056, 0.048, -0.03, 0.95)
				_bx(b, xf, P.AMBER, Vector3(side * 0.05, -0.12, -0.02), Vector3(0.006, 0.018, 0.018))
				_bx(b, xf, P.CRT, Vector3(side * -0.048, -0.15, -0.01), Vector3(0.006, 0.03, 0.03))
			elif robe:
				_cy(b, xf, P.CAPE, Vector3(0, -0.12, 0), 0.08, 0.062, 0.24, 10, 0.95)   # wide sleeve
				_cy(b, xf, P.BRASS, Vector3(0, -0.24, 0), 0.081, 0.081, 0.025, 10, 0.95, Basis(), false)
			else:
				_cy(b, xf, accent if st.get("jacket", false) else cloth, Vector3(0, -FARM + 0.02, 0), 0.045, 0.043, 0.03, 8)
		"thigh":
			_limb(b, xf, lower, THIGH, 0.088, 0.068)
			if elite:
				_limb(b, xf, P.CARBON, 0.26, 0.09, 0.075, -0.06, 0.95)
				_bx(b, xf, P.CHARCOAL, Vector3(side * 0.09, -0.16, 0), Vector3(0.03, 0.1, 0.08))   # leg pouch
		"shin":
			_limb(b, xf, lower, SHIN - 0.12, 0.066, 0.05)
			# Boot shaft up the calf.
			_cy(b, xf, st.boot, Vector3(0, -SHIN + 0.07, 0), 0.056, 0.06, 0.16, 10, 0.95)
			if plate:
				_el(b, xf, P.ARMOR, Vector3(0, -0.01, -0.03), Vector3(0.065, 0.06, 0.05), 8, 3)   # knee cop
				_limb(b, xf, P.ARMOR, 0.26, 0.068, 0.056, -0.06, 0.95)                            # greave
				_bx(b, xf, P.LEATHER, Vector3(0, -0.12, 0.06), Vector3(0.1, 0.018, 0.02))
			elif elite:
				_el(b, xf, P.CARBON, Vector3(0, -0.01, -0.035), Vector3(0.07, 0.075, 0.055), 8, 3)
				_limb(b, xf, P.CARBON, 0.28, 0.07, 0.056, -0.06, 0.95)
		"foot":
			# Ankle at the origin, sole on the ground, toe forward.
			_el(b, xf, st.boot, Vector3(0, -0.035, 0.0), Vector3(0.055, 0.05, 0.06), 8, 3)
			_bx(b, xf, st.boot, Vector3(0, -0.06, -0.04), Vector3(0.095, 0.075, 0.2))
			_el(b, xf, st.boot, Vector3(0, -0.065, -0.14), Vector3(0.048, 0.035, 0.05), 8, 2)
			_bx(b, xf, P.BLACK, Vector3(0, -0.095, -0.04), Vector3(0.1, 0.012, 0.24))   # sole

static func _sword(b: Builder, xf: Transform3D, at: Vector3) -> void:
	# Hilt up by the hip, scabbard angled back.
	var r := Basis(Vector3.RIGHT, -0.5)
	_cy(b, xf, P.BRASS, at + r * Vector3(0, 0.12, 0), 0.016, 0.016, 0.1, 6, 1.0, r)
	_bx(b, xf, P.BRASS, at + r * Vector3(0, 0.065, 0), Vector3(0.1, 0.018, 0.025), r)
	_cy(b, xf, P.LEATHER, at + r * Vector3(0, -0.3, 0), 0.026, 0.03, 0.66, 6, 0.5, r)
	_cy(b, xf, P.BRASS, at + r * Vector3(0, -0.64, 0), 0.03, 0.02, 0.04, 6, 0.5, r)

static func part_mesh(part: String, kind: String, tint: int, side: int) -> Mesh:
	var key := "bk2_%s_%s_%d_%d" % [part, kind, style_key(kind, tint), side if part in ["farm", "uarm", "thigh"] else 0]
	return Builder.cached(key, func():
		var b := Builder.new(0.2)
		add_part(b, part, kind, tint, side)
		return b.mesh())

## Tints that look the same share meshes.
static func style_key(kind: String, tint: int) -> int:
	match kind:
		"guard":
			return 2 if tint == 2 else tint % 2
		"civilian":
			return tint if tint >= 100 else tint % 30
	return 0

## The guards' rifle: AK-pattern, walnut and charcoal, long suppressor, a
## cassette-tech reflex box on the side rail. Origin at the pistol grip,
## barrel along -Z.
static func rifle_mesh() -> Mesh:
	return Builder.cached("npc_rifle_ak", func():
		var b := Builder.new(0.15)
		var t := Transform3D()
		_bx(b, t, P.CHARCOAL, Vector3(0, 0.06, -0.08), Vector3(0.05, 0.07, 0.4))                    # receiver
		_cy(b, t, P.CHARCOAL, Vector3(0, 0.1, -0.1), 0.024, 0.024, 0.34, 8, 1.0, Basis(Vector3.RIGHT, PI / 2))  # dust cover
		_bx(b, t, P.WALNUT, Vector3(0, 0.045, -0.38), Vector3(0.056, 0.05, 0.2))                    # lower handguard
		_bx(b, t, P.WALNUT, Vector3(0, 0.1, -0.37), Vector3(0.04, 0.032, 0.18))                     # gas tube cover
		_cy(b, t, P.STEEL, Vector3(0, 0.07, -0.52), 0.012, 0.012, 0.12, 6, 1.0, Basis(Vector3.RIGHT, PI / 2))
		_cy(b, t, P.CHARCOAL, Vector3(0, 0.07, -0.72), 0.028, 0.028, 0.3, 10, 1.0, Basis(Vector3.RIGHT, PI / 2))  # suppressor
		for i in 3:
			_cy(b, t, P.BLACK, Vector3(0, 0.07, -0.63 - i * 0.09), 0.03, 0.03, 0.01, 10, 1.0, Basis(Vector3.RIGHT, PI / 2))
		_bx(b, t, P.CHARCOAL, Vector3(0, 0.12, -0.47), Vector3(0.012, 0.04, 0.012))               # front sight
		# Curved magazine.
		for i in 4:
			var r := Basis(Vector3.RIGHT, 0.12 + i * 0.12)
			_bx(b, t, P.LEATHER, Vector3(0, -0.02 - i * 0.05, -0.12 - i * 0.022), Vector3(0.03, 0.06, 0.07), r)
		_bx(b, t, P.WALNUT, Vector3(0, -0.04, 0.02), Vector3(0.035, 0.1, 0.045), Basis(Vector3.RIGHT, 0.35))  # grip
		_bx(b, t, P.WALNUT, Vector3(0, 0.03, 0.27), Vector3(0.042, 0.08, 0.3), Basis(Vector3.RIGHT, 0.12))   # stock
		_bx(b, t, P.STEEL, Vector3(0, 0.015, 0.42), Vector3(0.045, 0.1, 0.012), Basis(Vector3.RIGHT, 0.12))
		_bx(b, t, P.BEIGE, Vector3(0, 0.15, -0.12), Vector3(0.04, 0.04, 0.07))                     # reflex box
		_bx(b, t, P.AMBER, Vector3(0.022, 0.15, -0.1), Vector3(0.004, 0.01, 0.01))
		return b.mesh())
