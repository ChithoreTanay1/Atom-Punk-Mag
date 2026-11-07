class_name PlayerRig
extends Node
## Weapon, gadgets, interaction and takedowns for the FpsController.
## Rules (damage, ammo, gadget stock) live in Rust; this is presentation
## and physics queries.
##
## Gunfeel stack, per shot: camera punch (spring, recovers), trauma shake,
## FOV kick, permanent aim climb with partial auto-recovery, view-model
## spring kick (position + rotation), star muzzle flash + light + smoke,
## ejected brass with its own bounce sound, a travelling tracer, impact
## sparks/dust/decal or a hit mist, hit marker, layered report with echoes.

const P = preload("res://scripts/palette.gd")
const MASK_SHOT := 1 | 4 | 8 | NpcBody.LAYER
const MASK_INTERACT := 16

signal hurt(amount: float)
signal message(text: String)

var player: FpsController
var cam: Camera3D
var level: Node  # optional hooks: on_npc_killed(npc), on_tape_planted(node)

var weapon := {}
var weapon_id := ""
var drawn := false
var auto_mode := false
var ads := 0.0
var cooldown := 0.0
var reloading := 0.0
var free_ammo := 30  # used outside missions (test track)
var spread_bloom := 0.0
var gadgets: Array = []  # [{id,name,kind,count}]
var gadget_i := 0
var prompt := ""
var focus: Interactable
var takedown_target: Npc
## Hit marker for the HUD: seconds left, and whether it was a kill.
var hit_t := 0.0
var hit_kill := false
var hit_head := false

var _vm: Node3D
var _vm_gun: Node3D
var _mag: Node3D
var _ammo_label: Label3D
var _selector: Node3D
var _flash_light: OmniLight3D
var _flash: MeshInstance3D
var _flash_t := 0.0
var _sway := Vector2.ZERO
var _look_delta := Vector2.ZERO
var _noise_t := 0.0
var _draw_t := 0.0
var _shots_in_burst := 0
# Springs: view-model kick (pos/rot), camera punch (rot).
var _kp := Vector3.ZERO
var _kpv := Vector3.ZERO
var _kr := Vector3.ZERO
var _krv := Vector3.ZERO
var _punch := Vector3.ZERO
var _punch_v := Vector3.ZERO
var _trauma := 0.0
var _fov_kick := 0.0
var _recoil_debt := 0.0
var _since_shot := 9.0
var _wall_pull := 0.0
var _sprint_pose := 0.0
# Pools.
var _tracers: Array = []    # {mi, from, dir, len, s}
var _tracer_i := 0
var _marks: Array[MeshInstance3D] = []
var _mark_i := 0
var _shells: Array = []     # {mi, vel, spin, life, floor, bounces}
var _shell_i := 0
var _fx := {}               # kind -> {list, i}

# Loadout: suppressed AK, silenced pistol, knife (slash + throws), grapple line.
const DEFAULT_LOADOUT := ["wpn_rifle_ashani", "wpn_pistol_mriga", "wpn_knife_nakha", "wpn_grapple_garuda"]
const SHORT := {"wpn_rifle_ashani": "AK-47", "wpn_pistol_mriga": "Pistol", "wpn_knife_nakha": "Knife", "wpn_grapple_garuda": "Line"}
const HOOK_SPEED := 70.0
var loadout: Array = []     # [{id, def}]
var slot := 0
var _models := {}           # id -> {node, mag, selector, label, flash, sight, eye, hip, ads, ...}
var _cfg := {}
var _free := {}             # free-play ammo per weapon (no mission)
var _slash_t := 0.0
var _throw_t := 0.0
var _knives: Array = []     # {node, vel, stuck}
var _hook: Node3D
var _rope: MeshInstance3D
var _hook_t := -1.0         # >= 0 while the hook is in flight
var _hook_dur := 0.1
var _hook_from := Vector3.ZERO
var _hook_to := Vector3.ZERO
var _hook_hit := false
var _hook_body: NpcBody      # the hook is flying at / stuck in this body
var _hook_bone := "UpperChest"
var _latched: NpcBody        # line made fast to a person
var _tether := {}            # {body, at, t}: the person is flying into `at`
var _winch: AudioStreamPlayer

func setup(p: FpsController, lvl: Node) -> void:
	player = p
	level = lvl
	cam = p.get_camera()
	var info: Dictionary = Game.sim.mission_info()
	var ids: Array = []
	for id in info.get("weapons", []):
		ids.append(str(id))
	if ids.is_empty():
		ids = DEFAULT_LOADOUT.duplicate()
	for id in ids:
		var def: Dictionary = Game.sim.weapon_def(id)
		if def.is_empty():
			continue
		def["short"] = SHORT.get(id, def.get("name", id))
		loadout.append({"id": id, "def": def})
		_free[id] = int(def.get("mag_size", 0))
	if loadout.is_empty():
		loadout.append({"id": "wpn_rifle_ashani", "def": {"fire_interval": 0.1, "spread_deg": 2.4, "ads_spread_deg": 0.4, "recoil_pitch_deg": 1.3, "recoil_yaw_deg": 0.5, "range": 120.0, "noise_radius": 11.0, "reload_time": 2.4, "mag_size": 30, "has_auto": true, "suppressed": true, "name": "AK-47", "kind": "gun", "short": "AK-47"}})
		_free["wpn_rifle_ashani"] = 30
	weapon_id = loadout[0].id
	weapon = loadout[0].def
	free_ammo = _free[weapon_id]
	refresh_gadgets()
	_build_viewmodel()
	_build_fx()
	_build_line()
	_equip(0, true)
	if Game.debug.has("weapon"):
		_equip(int(Game.debug.weapon) - 1, true)
	p.footstep.connect(_on_footstep)
	p.landed.connect(_on_landed)

func refresh_gadgets() -> void:
	var st: Dictionary = Game.sim.mission_state()
	gadgets = st.get("gadgets", [])
	gadget_i = clampi(gadget_i, 0, maxi(gadgets.size() - 1, 0))

func mission_on() -> bool:
	return Game.sim.mission_active()

# ------------------------------------------------------------- shared FX resources

static var _radial: GradientTexture2D
static var _hole_tex: GradientTexture2D

static func radial_tex() -> GradientTexture2D:
	if _radial == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_radial = GradientTexture2D.new()
		_radial.gradient = g
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(0.5, 0.0)
		_radial.width = 64
		_radial.height = 64
	return _radial

static func hole_tex() -> GradientTexture2D:
	if _hole_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.02, 0.02, 0.02, 1))
		g.set_color(1, Color(0.3, 0.3, 0.3, 0))
		g.add_point(0.28, Color(0.04, 0.04, 0.04, 1))
		g.add_point(0.45, Color(0.55, 0.55, 0.52, 0.55))
		_hole_tex = GradientTexture2D.new()
		_hole_tex.gradient = g
		_hole_tex.fill = GradientTexture2D.FILL_RADIAL
		_hole_tex.fill_from = Vector2(0.5, 0.5)
		_hole_tex.fill_to = Vector2(0.5, 0.0)
		_hole_tex.width = 32
		_hole_tex.height = 32
	return _hole_tex

static func glow_mat(col: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = radial_tex()
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	return m

# ------------------------------------------------------------- view model

## Reflex sight: an open tube you look *through*. Hollow housing (walls,
## top strap, front and rear hoods), a faintly tinted lens and an amber
## reticle on the lens. SIGHT_CENTER is where the reticle sits in gun
## space; the ADS pose puts it exactly on the camera's forward axis.
const SIGHT_CENTER := Vector3(0, 0.142, -0.05)
const SIGHT_EYE_DIST := 0.27
const SIGHT_HALF := Vector2(0.027, 0.022)

func _build_sight(b: Builder) -> void:
	var c := SIGHT_CENTER
	var hw := SIGHT_HALF.x
	var hh := SIGHT_HALF.y
	var t := 0.0035
	var length := 0.036
	# Mount on the carry rail.
	b.box(P.CHARCOAL, Vector3(0, 0.113, c.z), Vector3(0.036, 0.006, 0.06), false)
	b.box(P.CHARCOAL, Vector3(0, 0.113 + (c.y - SIGHT_HALF.y - 0.0035 - 0.113) * 0.5, c.z), Vector3(0.03, c.y - SIGHT_HALF.y - 0.0035 - 0.113, 0.03), false)
	b.box(P.WARM_GREY, Vector3(0, c.y - hh - t * 0.5, c.z), Vector3(hw * 2 + t * 2, t, length), false)
	# Side walls and top strap: the tube.
	for sx in [-1.0, 1.0]:
		b.box(P.WARM_GREY, Vector3(sx * (hw + t * 0.5), c.y, c.z), Vector3(t, hh * 2 + t * 2, length), false)
	b.box(P.WARM_GREY, Vector3(0, c.y + hh + t * 0.5, c.z), Vector3(hw * 2 + t * 2, t, length), false)
	# Hoods: slightly larger frames at both ends (rear one in dark rubber).
	for e in [[c.z - length * 0.5, P.CHARCOAL, 0.006], [c.z + length * 0.5, P.BLACK, 0.003]]:
		var z: float = e[0]
		var slot: int = e[1]
		var w: float = e[2]
		b.box(slot, Vector3(0, c.y + hh + w * 0.5 + t, z), Vector3(hw * 2 + t * 2 + w * 2, w, 0.012), false)
		b.box(slot, Vector3(0, c.y - hh - w * 0.5 - t, z), Vector3(hw * 2 + t * 2 + w * 2, w, 0.012), false)
		for sx in [-1.0, 1.0]:
			b.box(slot, Vector3(sx * (hw + t + w * 0.5), c.y, z), Vector3(w, hh * 2 + t * 2, 0.012), false)
	# Windage and elevation turrets, battery cap with a ready lamp.
	b.cyl_xf(P.CHARCOAL, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(hw + t + 0.006, c.y, c.z)), 0.008, 0.008, 0.012, 8)
	b.cyl(P.CHARCOAL, Vector3(0, c.y + hh + t + 0.006, c.z), 0.008, 0.008, 0.012, 8)
	b.cyl_xf(P.STEEL, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(-hw - t - 0.005, c.y - 0.006, c.z)), 0.007, 0.007, 0.01, 8)
	b.box(P.AMBER, Vector3(-hw - t - 0.0005, c.y + 0.01, c.z + 0.01), Vector3(0.002, 0.004, 0.004), false)

static var _reticle_tex: ImageTexture

static func reticle_tex() -> ImageTexture:
	if _reticle_tex:
		return _reticle_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length() / (n * 0.5)
			# Centre dot, a thin broken ring, and soft bloom.
			var dot := clampf(1.0 - d / 0.07, 0.0, 1.0)
			var ring := clampf(1.0 - absf(d - 0.62) / 0.035, 0.0, 1.0)
			var a := atan2(y + 0.5 - c.y, x + 0.5 - c.x)
			if absf(sin(a * 2.0)) < 0.28:
				ring = 0.0  # gaps at 0/90/180/270 degrees
			var glow := clampf(1.0 - d / 0.22, 0.0, 1.0) * 0.25
			var v := clampf(dot + ring * 0.75 + glow, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	_reticle_tex = ImageTexture.create_from_image(img)
	return _reticle_tex

func _build_sight_glass() -> void:
	var c := SIGHT_CENTER
	# Lens: a faint amber-tinted pane with a little sheen.
	var lens := MeshInstance3D.new()
	var lq := QuadMesh.new()
	lq.size = SIGHT_HALF * 2.0
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.albedo_color = Color(0.85, 0.62, 0.3, 0.07)
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lq.material = lm
	lens.mesh = lq
	lens.position = c + Vector3(0, 0, -0.016)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm_gun.add_child(lens)
	# Reticle on the lens, additive so it reads against dark and bright.
	var ret := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(0.02, 0.02)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_texture = reticle_tex()
	rm.albedo_color = Color(1.0, 0.45, 0.12)
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rq.material = rm
	ret.mesh = rq
	ret.position = c + Vector3(0, 0, -0.015)
	ret.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm_gun.add_child(ret)

func _build_viewmodel() -> void:
	_vm = Node3D.new()
	_vm.name = "ViewModel"
	cam.add_child(_vm)
	_vm_gun = Node3D.new()
	_vm.add_child(_vm_gun)
	var b := Builder.new(0.15)
	# AK-47 pattern: charcoal stamped receiver, walnut furniture, slanted
	# stock, gas tube over the barrel, long baffled suppressor, side-rail
	# reflex sight. Cassette touches: amber ready lamp, CRT round counter.
	b.box(P.CHARCOAL, Vector3(0, 0.0, 0.03), Vector3(0.052, 0.07, 0.44), false)      # receiver
	b.cyl_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.035, 0.05)), 0.026, 0.026, 0.38, 10)  # dust cover
	b.box(P.STEEL, Vector3(0.027, 0.012, 0.03), Vector3(0.004, 0.022, 0.09), false)  # ejection port
	b.box(P.WALNUT, Vector3(0, -0.012, -0.29), Vector3(0.058, 0.052, 0.21), false)    # lower handguard
	for i in 3:
		b.box(P.BLACK, Vector3(0, -0.012, -0.22 - i * 0.05), Vector3(0.06, 0.006, 0.012), false)
	b.box(P.WALNUT, Vector3(0, 0.045, -0.28), Vector3(0.042, 0.032, 0.19), false)     # gas tube cover
	b.cyl_xf(P.STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.045, -0.42)), 0.012, 0.012, 0.08, 8)   # gas tube
	b.box(P.STEEL, Vector3(0, 0.02, -0.43), Vector3(0.03, 0.05, 0.03), false)        # gas block
	b.cyl_xf(P.STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.01, -0.47)), 0.011, 0.011, 0.1, 8)     # barrel
	b.box(P.CHARCOAL, Vector3(0, 0.05, -0.47), Vector3(0.01, 0.035, 0.012), false)   # front sight post
	b.cyl_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.01, -0.66)), 0.027, 0.027, 0.3, 12)  # suppressor
	for i in 4:
		b.cyl_xf(P.BLACK, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.01, -0.54 - i * 0.075)), 0.0285, 0.0285, 0.008, 12)
	b.cyl_xf(P.STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.01, -0.812)), 0.024, 0.02, 0.008, 12)
	b.box(P.CHARCOAL, Vector3(0, 0.06, -0.12), Vector3(0.03, 0.012, 0.06), false)    # rear sight leaf
	# Side-rail mount up to the reflex sight.
	b.box(P.CHARCOAL, Vector3(-0.03, 0.03, -0.05), Vector3(0.008, 0.05, 0.1), false)
	b.box(P.CHARCOAL, Vector3(-0.014, 0.09, -0.05), Vector3(0.04, 0.06, 0.03), false)
	_build_sight(b)
	b.box_xf(P.WALNUT, Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(0, -0.085, 0.13)), Vector3(0.034, 0.11, 0.045))  # pistol grip
	b.box(P.CHARCOAL, Vector3(0, -0.045, 0.07), Vector3(0.01, 0.025, 0.08), false)   # trigger guard
	b.box_xf(P.WALNUT, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, -0.02, 0.4)), Vector3(0.045, 0.085, 0.3))  # stock
	b.box_xf(P.STEEL, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, -0.04, 0.55)), Vector3(0.048, 0.11, 0.012)) # butt plate
	b.box(P.CRT, Vector3(-0.027, 0.0, 0.12), Vector3(0.004, 0.035, 0.07), false)     # side CRT
	b.box(P.AMBER, Vector3(0.027, 0.02, 0.17), Vector3(0.005, 0.012, 0.012), false)  # ready lamp
	b.cyl_xf(P.BLACK, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0.04, -0.02, 0.2)), 0.005, 0.005, 0.07, 6) # cable
	var mi := MeshInstance3D.new()
	mi.mesh = b.mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm_gun.add_child(mi)
	_build_sight_glass()
	# Curved thirty-round magazine as its own node so reloads can pull it.
	_mag = Node3D.new()
	_mag.position = Vector3(0, -0.04, -0.06)
	var mb := Builder.new(0.1)
	for i in 5:
		var r := Basis(Vector3.RIGHT, 0.1 + i * 0.1)
		mb.box_xf(P.WARM_GREY, Transform3D(r, Vector3(0, -0.02 - i * 0.034, -0.01 - i * i * 0.006)), Vector3(0.028, 0.04, 0.07))
	mb.box_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(0, -0.185, -0.11)), Vector3(0.032, 0.014, 0.074))
	var mmi := MeshInstance3D.new()
	mmi.mesh = mb.mesh()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mag.add_child(mmi)
	_vm_gun.add_child(_mag)
	_selector = Node3D.new()
	_selector.position = Vector3(0.028, 0.0, 0.06)
	var sb := Builder.new(0.0)
	sb.cyl_xf(P.BRASS, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3.ZERO), 0.014, 0.014, 0.01, 10)
	sb.box(P.CHARCOAL, Vector3(0.007, 0.008, 0), Vector3(0.004, 0.016, 0.004), false)
	var smi := MeshInstance3D.new()
	smi.mesh = sb.mesh()
	_selector.add_child(smi)
	_vm_gun.add_child(_selector)
	_ammo_label = Label3D.new()
	_ammo_label.font = Game.mono
	_ammo_label.font_size = 32
	_ammo_label.pixel_size = 0.0006
	_ammo_label.modulate = Color("#9FE8A8")
	_ammo_label.outline_size = 0
	_ammo_label.position = Vector3(-0.0295, 0.0, 0.12)
	_ammo_label.rotation = Vector3(0, -PI / 2, 0)
	_ammo_label.shaded = false
	_vm_gun.add_child(_ammo_label)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color("#FFC27A")
	_flash_light.omni_range = 11.0
	_flash_light.omni_attenuation = 1.6
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	_flash_light.position = Vector3(0, 0.02, -0.9)
	_vm_gun.add_child(_flash_light)
	# Muzzle flash: a front-facing disc plus two crossed elongated petals.
	var fm := glow_mat(Color(1.0, 0.78, 0.42, 1.0))
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [
		[Vector3(-0.07, -0.07, 0), Vector3(0.07, -0.07, 0), Vector3(0.07, 0.07, 0), Vector3(-0.07, 0.07, 0)],
		[Vector3(-0.05, 0, 0.02), Vector3(0.05, 0, 0.02), Vector3(0.05, 0, -0.26), Vector3(-0.05, 0, -0.26)],
		[Vector3(0, -0.05, 0.02), Vector3(0, 0.05, 0.02), Vector3(0, 0.05, -0.26), Vector3(0, -0.05, -0.26)],
	]
	for qd in quads:
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[k])
			st.add_vertex(qd[k])
	st.commit(am)
	am.surface_set_material(0, fm)
	_flash = MeshInstance3D.new()
	_flash.mesh = am
	_flash.position = Vector3(0, 0.01, -0.82)
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm_gun.add_child(_flash)
	_vm.visible = false
	var rifle := {"node": _vm_gun, "mag": _mag, "selector": _selector, "label": _ammo_label,
		"flash": Vector3(0, 0.01, -0.82), "sight": SIGHT_CENTER, "eye": SIGHT_EYE_DIST,
		"hip": Vector3(0.19, -0.19, -0.4), "ads": true, "flash_scale": 0.35, "mag_rest": Vector3(0, -0.04, -0.06),
		"pitch": 0.72}
	var have_carbine := false
	for e in loadout:
		var kind := str(e.def.get("kind", "gun"))
		if kind == "gun" and e.def.get("has_auto", false) and not have_carbine:
			_models[e.id] = rifle
			have_carbine = true
		elif kind == "gun":
			_models[e.id] = _build_pistol()
		elif kind == "melee":
			_models[e.id] = _build_knife()
		else:
			_models[e.id] = _build_grapple()
	if not have_carbine:
		_vm_gun.visible = false

func _model_root() -> Node3D:
	var n := Node3D.new()
	n.visible = false
	_vm.add_child(n)
	return n

func _mesh_into(n: Node3D, b: Builder) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = b.mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)

## Mriga 9: compact pistol with a long ribbed suppressor and iron sights
## (rear notch, brass-capped front post) that line up in ADS.
func _build_pistol() -> Dictionary:
	var n := _model_root()
	var b := Builder.new(0.15)
	b.box(P.CHARCOAL, Vector3(0, 0.032, -0.05), Vector3(0.03, 0.034, 0.19), false)    # slide
	for i in 5:
		b.box(P.BLACK, Vector3(0, 0.035, 0.02 + i * 0.008), Vector3(0.032, 0.026, 0.003), false)  # serrations
	b.box(P.BEIGE, Vector3(0, 0.0, -0.045), Vector3(0.028, 0.03, 0.17), false)        # frame
	b.box_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, 0.22), Vector3(0, -0.065, 0.025)), Vector3(0.03, 0.11, 0.05))  # grip
	b.box(P.CHARCOAL, Vector3(0, -0.028, -0.03), Vector3(0.008, 0.03, 0.05), false)   # trigger guard
	b.cyl_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.027, -0.24)), 0.019, 0.019, 0.17, 10)  # suppressor
	for i in 5:
		b.cyl_xf(P.BLACK, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.027, -0.18 - i * 0.026)), 0.0205, 0.0205, 0.006, 10)
	b.cyl_xf(P.STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.027, -0.327)), 0.017, 0.017, 0.006, 10)
	# Sights: rear notch (two posts) and a front post with a brass cap.
	for sx in [-1.0, 1.0]:
		b.box(P.BLACK, Vector3(sx * 0.0075, 0.054, 0.035), Vector3(0.007, 0.01, 0.008), false)
	b.box(P.BLACK, Vector3(0, 0.054, -0.135), Vector3(0.004, 0.01, 0.006), false)
	b.box(P.BRASS, Vector3(0, 0.0595, -0.135), Vector3(0.004, 0.003, 0.006), false)
	b.box(P.AMBER, Vector3(0.016, 0.03, 0.02), Vector3(0.004, 0.006, 0.006), false)   # chamber lamp
	_mesh_into(n, b)
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.1, 0.03)
	var mb := Builder.new(0.1)
	mb.box(P.WARM_GREY, Vector3.ZERO, Vector3(0.024, 0.06, 0.04), false)
	mb.box(P.CHARCOAL, Vector3(0, -0.032, 0), Vector3(0.028, 0.008, 0.044), false)
	_mesh_into(mag, mb)
	n.add_child(mag)
	return {"node": n, "mag": mag, "flash": Vector3(0, 0.027, -0.335), "sight": Vector3(0, 0.0575, 0.035),
		"eye": 0.3, "hip": Vector3(0.18, -0.17, -0.4), "ads": true, "flash_scale": 0.3, "mag_rest": Vector3(0, -0.1, 0.03)}

## Nakha knife: walnut grip, blackened blade, steel edge; spare throwing
## blades in a sheath on the off hand.
func _build_knife() -> Dictionary:
	var n := _model_root()
	var b := Builder.new(0.1)
	b.box(P.WALNUT, Vector3(0, 0, 0.02), Vector3(0.028, 0.032, 0.11), false)
	for i in 3:
		b.box(P.BLACK, Vector3(0, 0, -0.01 + i * 0.03), Vector3(0.03, 0.034, 0.006), false)
	b.box(P.BRASS, Vector3(0, 0, 0.078), Vector3(0.03, 0.03, 0.01), false)
	b.box(P.BLACK, Vector3(0, 0, -0.04), Vector3(0.07, 0.016, 0.014), false)        # guard
	b.box(P.CHARCOAL, Vector3(0, 0.002, -0.13), Vector3(0.005, 0.034, 0.17), false)  # blade
	b.box(P.CHROME, Vector3(0, -0.016, -0.13), Vector3(0.006, 0.005, 0.17), false)   # edge
	b.box_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.006, -0.222)), Vector3(0.005, 0.025, 0.04))  # tip
	_mesh_into(n, b)
	var sheath := Node3D.new()
	sheath.position = Vector3(-0.42, -0.1, 0.02)
	var sb := Builder.new(0.1)
	sb.box(P.LEATHER, Vector3.ZERO, Vector3(0.09, 0.03, 0.16), false)
	for i in 3:
		sb.box(P.STEEL, Vector3(-0.025 + i * 0.025, 0.02, -0.02), Vector3(0.012, 0.012, 0.12), false)
	_mesh_into(sheath, sb)
	n.add_child(sheath)
	return {"node": n, "flash": Vector3(0, 0, -0.2), "eye": 0.3,
		"hip": Vector3(0.17, -0.17, -0.38), "ads": false, "flash_scale": 0.0, "sheath": sheath}

## Garuda Line: pistol-grip launcher with a brass spool and a three-pronged hook.
func _build_grapple() -> Dictionary:
	var n := _model_root()
	var b := Builder.new(0.15)
	b.box(P.WARM_GREY, Vector3(0, 0.0, -0.05), Vector3(0.06, 0.07, 0.22), false)
	b.box(P.CHARCOAL, Vector3(0, -0.07, 0.02), Vector3(0.035, 0.1, 0.05), false)
	b.cyl_xf(P.BRASS, Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 0.0, 0.02)), 0.045, 0.045, 0.075, 12)  # spool
	b.cyl_xf(P.CHARCOAL, Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 0.0, 0.02)), 0.05, 0.05, 0.02, 12)
	b.cyl_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.01, -0.19)), 0.022, 0.026, 0.08, 10)
	b.box(P.AMBER, Vector3(0.031, 0.02, -0.08), Vector3(0.004, 0.01, 0.02), false)
	b.box(P.CRT, Vector3(-0.031, 0.01, -0.06), Vector3(0.004, 0.03, 0.05), false)
	_mesh_into(n, b)
	var hook := Node3D.new()
	hook.position = Vector3(0, 0.01, -0.25)
	hook.add_child(_hook_mesh_instance())
	n.add_child(hook)
	return {"node": n, "flash": Vector3(0, 0.01, -0.26), "eye": 0.3,
		"hip": Vector3(0.21, -0.2, -0.44), "ads": false, "flash_scale": 0.0, "hook": hook}

func _hook_mesh_instance() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Builder.cached("grapple_hook", func():
		var b := Builder.new(0.0)
		b.cyl_xf(P.STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO), 0.012, 0.012, 0.07, 6)
		for i in 3:
			var a := TAU * i / 3.0
			var d := Vector3(cos(a), sin(a), 0)
			# Prongs swept back from the tip.
			var bas := Basis.looking_at((Vector3(0, 0, 1) + d * 0.9).normalized(), Vector3(0, 0, 1).cross(d))
			b.box_xf(P.STEEL, Transform3D(bas, d * 0.022 + Vector3(0, 0, -0.03)), Vector3(0.008, 0.008, 0.055))
		return b.mesh())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Rope and flying hook live in the world, not in the view model.
func _build_line() -> void:
	var root := get_tree().current_scene
	_rope = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.014, 0.014, 1.0)
	_rope.mesh = bm
	_rope.material_override = P.mats()[P.CHARCOAL]
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.visible = false
	root.add_child.call_deferred(_rope)
	_hook = Node3D.new()
	_hook.add_child(_hook_mesh_instance())
	_hook.visible = false
	root.add_child.call_deferred(_hook)
	_winch = AudioStreamPlayer.new()
	_winch.stream = Game.sfx.get("winch")
	_winch.volume_db = -12.0
	add_child(_winch)

## Draw weapon `i` from the loadout (ammo is kept per weapon).
func _equip(i: int, initial := false) -> void:
	if loadout.is_empty():
		return
	i = posmod(i, loadout.size())
	if i == slot and not initial:
		return
	_free[weapon_id] = free_ammo
	slot = i
	weapon_id = loadout[i].id
	weapon = loadout[i].def
	if mission_on():
		Game.sim.switch_weapon(weapon_id)
	free_ammo = _free.get(weapon_id, 0)
	for id in _models:
		(_models[id].node as Node3D).visible = false
	_cfg = _models[weapon_id]
	_vm_gun = _cfg.node
	_vm_gun.visible = true
	_mag = _cfg.get("mag")
	_selector = _cfg.get("selector")
	_ammo_label = _cfg.get("label")
	_flash.reparent(_vm_gun, false)
	_flash.position = _cfg.flash
	_flash_light.reparent(_vm_gun, false)
	_flash_light.position = _cfg.flash + Vector3(0, 0, -0.08)
	reloading = 0.0
	_slash_t = 0.0
	_throw_t = 0.0
	if not weapon.get("has_auto", false):
		auto_mode = false
	if not initial:
		_release_line()
		_draw_t = 0.32
		if not drawn:
			set_drawn(true)
		else:
			Game.play_2d("dry", -8, 0.9)
			_krv += Vector3(-2.0, 0, 3.0)

func _kind() -> String:
	return str(weapon.get("kind", "gun"))

func _particle_pool(kind: String, n: int, amount: int, life: float, vmin: float, vmax: float, grav: float,
		size: float, spread: float, ramp: Gradient, additive: bool, damping := 0.0, scale_curve := true) -> void:
	var root := get_tree().current_scene
	var list := []
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var m := glow_mat(Color.WHITE, additive)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	qm.material = m
	var curve: Curve = null
	if scale_curve:
		curve = Curve.new()
		curve.add_point(Vector2(0, 0.5))
		curve.add_point(Vector2(1, 1.6))
	for i in n:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = amount
		p.lifetime = life
		p.explosiveness = 1.0
		p.randomness = 0.5
		p.local_coords = false
		p.mesh = qm
		p.direction = Vector3.UP
		p.spread = spread
		p.initial_velocity_min = vmin
		p.initial_velocity_max = vmax
		p.gravity = Vector3(0, -grav, 0)
		p.damping_min = damping
		p.damping_max = damping
		p.color_ramp = ramp
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		if curve:
			p.scale_amount_curve = curve
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child.call_deferred(p)
		list.append(p)
	_fx[kind] = {"list": list, "i": 0}

func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / (cols.size() - 1), cols[i])
	return g

func _build_fx() -> void:
	var root := get_tree().current_scene
	_particle_pool("sparks", 6, 10, 0.35, 4.0, 9.0, 14.0, 0.035, 55.0,
		_ramp([Color(1, 0.9, 0.6, 1), Color(1, 0.55, 0.15, 0.9), Color(0.6, 0.2, 0.05, 0)]), true, 0.0, false)
	_particle_pool("dust", 6, 6, 0.9, 0.6, 2.2, 1.2, 0.32, 35.0,
		_ramp([Color(0.62, 0.6, 0.56, 0.75), Color(0.5, 0.5, 0.48, 0.35), Color(0.45, 0.45, 0.44, 0)]), false, 2.5)
	_particle_pool("smoke", 4, 3, 0.7, 0.3, 0.9, -0.4, 0.22, 20.0,
		_ramp([Color(0.75, 0.74, 0.72, 0.45), Color(0.6, 0.6, 0.6, 0.18), Color(0.5, 0.5, 0.5, 0)]), false, 1.5)
	_particle_pool("mist", 4, 8, 0.45, 0.8, 2.6, 3.0, 0.2, 40.0,
		_ramp([Color(0.42, 0.06, 0.05, 0.9), Color(0.3, 0.04, 0.04, 0.5), Color(0.25, 0.03, 0.03, 0)]), false, 2.0)
	# Travelling tracers: emissive streaks that glow under the HIGH preset.
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.albedo_color = Color(1.0, 0.72, 0.36)
	var tb := BoxMesh.new()
	tb.size = Vector3(0.022, 0.022, 1.0)
	tb.material = tm
	for i in 12:
		var t := MeshInstance3D.new()
		t.mesh = tb
		t.visible = false
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.top_level = true
		root.add_child.call_deferred(t)
		_tracers.append({"mi": t, "from": Vector3.ZERO, "dir": Vector3.FORWARD, "len": 0.0, "s": 1e9, "speed": 420.0})
	# Bullet holes.
	var mm := StandardMaterial3D.new()
	mm.albedo_texture = hole_tex()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.roughness = 1.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.13, 0.13)
	qm.material = mm
	for i in 40:
		var m := MeshInstance3D.new()
		m.mesh = qm
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.top_level = true
		root.add_child.call_deferred(m)
		_marks.append(m)
	# Brass.
	var sb := Builder.new(0.0)
	sb.cyl_xf(P.BRASS, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO), 0.0055, 0.0055, 0.045, 6)
	var shell_mesh := sb.mesh()
	for i in 14:
		var s := MeshInstance3D.new()
		s.mesh = shell_mesh
		s.visible = false
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.top_level = true
		root.add_child.call_deferred(s)
		_shells.append({"mi": s, "vel": Vector3.ZERO, "spin": Vector3.ZERO, "life": 0.0, "floor": -1e9, "bounces": 0})

func _burst(kind: String, pos: Vector3, normal: Vector3) -> void:
	var pool: Dictionary = _fx[kind]
	var p: CPUParticles3D = pool.list[pool.i]
	pool.i = (pool.i + 1) % pool.list.size()
	if not p.is_inside_tree():
		return
	var y := normal.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	p.global_transform = Transform3D(Basis(x, y, x.cross(y)), pos + y * 0.03)
	p.restart()

func tracer(from: Vector3, to: Vector3, speed := 420.0) -> void:
	var tr: Dictionary = _tracers[_tracer_i]
	_tracer_i = (_tracer_i + 1) % _tracers.size()
	var d := from.distance_to(to)
	if d < 0.5 or not tr.mi.is_inside_tree():
		return
	tr.from = from
	tr.dir = (to - from) / d
	tr.len = d
	tr.s = minf(2.0, d)
	tr.speed = speed

func _update_tracers(dt: float) -> void:
	for tr in _tracers:
		var mi: MeshInstance3D = tr.mi
		if tr.s > tr.len + 4.0:
			mi.visible = false
			continue
		tr.s += tr.speed * dt
		var a := maxf(tr.s - 4.0, 0.0)
		var b := minf(tr.s, tr.len)
		if b - a < 0.05:
			mi.visible = false
			continue
		var p0: Vector3 = tr.from + tr.dir * a
		var p1: Vector3 = tr.from + tr.dir * b
		var up := Vector3.UP if absf(tr.dir.y) < 0.95 else Vector3.RIGHT
		mi.global_transform = Transform3D(Basis.looking_at(tr.dir, up), (p0 + p1) * 0.5)
		mi.scale = Vector3(1, 1, b - a)
		mi.visible = true

func _mark(pos: Vector3, n: Vector3) -> void:
	var m := _marks[_mark_i]
	_mark_i = (_mark_i + 1) % _marks.size()
	if not m.is_inside_tree():
		return
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	m.global_transform = Transform3D(Basis.looking_at(-n, up).rotated(n, randf() * TAU), pos + n * 0.012)
	var s := randf_range(0.7, 1.25)
	m.scale = Vector3(s, s, 1)
	m.visible = true

func _eject_shell() -> void:
	var sh: Dictionary = _shells[_shell_i]
	_shell_i = (_shell_i + 1) % _shells.size()
	var mi: MeshInstance3D = sh.mi
	if not mi.is_inside_tree():
		return
	var port := _vm_gun.global_transform * Vector3(0.04, 0.03, 0.06)
	var b := cam.global_transform.basis
	mi.global_transform = Transform3D(b, port)
	sh.vel = b * Vector3(randf_range(2.2, 3.2), randf_range(1.6, 2.6), randf_range(0.2, 0.8)) + player.velocity
	sh.spin = Vector3(randf_range(-30, 30), randf_range(-30, 30), randf_range(-30, 30))
	sh.life = 2.5
	sh.bounces = 0
	var q := PhysicsRayQueryParameters3D.create(port, port + Vector3.DOWN * 4.0, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	sh.floor = hit.position.y + 0.006 if not hit.is_empty() else port.y - 1.6
	mi.visible = true

func _update_shells(dt: float) -> void:
	for sh in _shells:
		if sh.life <= 0.0:
			continue
		var mi: MeshInstance3D = sh.mi
		sh.life -= dt
		if sh.life <= 0.0:
			mi.visible = false
			continue
		sh.vel.y -= 9.8 * dt
		var p: Vector3 = mi.global_position + sh.vel * dt
		if p.y < sh.floor:
			p.y = sh.floor
			if sh.bounces < 2 and sh.vel.y < -0.6:
				if sh.bounces == 0:
					Game.play_3d("shell", p, -14, 2.0, randf_range(0.85, 1.2))
				sh.vel = Vector3(sh.vel.x * 0.4, -sh.vel.y * 0.35, sh.vel.z * 0.4)
				sh.spin *= 0.5
				sh.bounces += 1
			else:
				sh.vel = Vector3.ZERO
				sh.spin = Vector3.ZERO
		mi.global_position = p
		mi.rotate_x(sh.spin.x * dt)
		mi.rotate_y(sh.spin.y * dt)

# ------------------------------------------------------------- input

func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_delta += e.relative

func _unhandled_input(e: InputEvent) -> void:
	if player == null or not player.enabled or Game.tuning_open() or get_tree().paused:
		return
	if e.is_action_pressed("holster"):
		set_drawn(not drawn)
	elif e.is_action_pressed("weapon_1"):
		_equip(0)
	elif e.is_action_pressed("weapon_2"):
		_equip(1)
	elif e.is_action_pressed("weapon_3"):
		_equip(2)
	elif e.is_action_pressed("weapon_4"):
		_equip(3)
	elif e.is_action_pressed("weapon_next"):
		_equip(slot + 1)
	elif e.is_action_pressed("weapon_prev"):
		_equip(slot - 1)
	elif e.is_action_pressed("aim") and drawn and _kind() == "melee":
		_throw_knife()
	elif e.is_action_pressed("aim") and _kind() == "grapple":
		if _latched:
			_tether_to_aim()
		else:
			_release_line()
	elif e.is_action_pressed("reload") and _kind() == "grapple":
		_release_line()
	elif e.is_action_pressed("reload"):
		_reload()
	elif e.is_action_pressed("fire_mode") and weapon.get("has_auto", false):
		auto_mode = not auto_mode
		Game.play_2d("beep_low", -8)
		_krv += Vector3(0, 0, 2.0)
	elif e.is_action_pressed("gadget_next") and not gadgets.is_empty():
		gadget_i = (gadget_i + 1) % gadgets.size()
		Game.play_2d("beep", -10)
	elif e.is_action_pressed("gadget_use"):
		_use_gadget()
	elif e.is_action_pressed("interact"):
		if focus:
			# Consume the press: otherwise the level sees the same E while
			# already driving and immediately exits the car again.
			get_viewport().set_input_as_handled()
			focus.use()
			Game.play_2d("beep", -10)
	elif e.is_action_pressed("takedown"):
		_takedown()
	elif e.is_action_pressed("fire") and not drawn:
		set_drawn(true)

func set_drawn(on: bool) -> void:
	if not on:
		_release_line()
	drawn = on
	player.weapon_raised = on
	_vm.visible = on
	_draw_t = 0.32
	Game.play_2d("dry", -6, 0.8 if on else 0.6)
	if on:
		_krv += Vector3(-3.0, 0, 4.0)

func _reload() -> void:
	if not drawn or reloading > 0.0 or _kind() != "gun":
		return
	if mission_on():
		var st: Dictionary = Game.mstate()
		if int(st.ammo) >= int(weapon.mag_size) or int(st.reserve) <= 0:
			return
	elif free_ammo >= int(weapon.mag_size):
		return
	reloading = float(weapon.reload_time)
	Game.play_2d("reload", -4)

## Current cone half-angle in degrees (for the HUD crosshair).
func current_spread() -> float:
	var move := clampf(player.get_horizontal_speed() / 6.0, 0.0, 1.0) * 1.6 * (1.0 - ads)
	var air := 0.0 if player.is_on_floor() else 2.5
	return lerpf(float(weapon.spread_deg), float(weapon.ads_spread_deg), ads) + spread_bloom + move + air

func _physics_process(dt: float) -> void:
	if player == null:
		return
	cooldown -= dt
	_since_shot += dt
	spread_bloom = maxf(spread_bloom - dt * (5.0 if _since_shot > 0.15 else 1.5), 0.0)
	if reloading > 0.0:
		reloading -= dt
		if reloading <= 0.0:
			if mission_on():
				Game.sim.reload()
			else:
				free_ammo = int(weapon.mag_size)
			_krv += Vector3(-4.0, 0, 0)
	# Aim recovery: drift back down toward where the burst started.
	if _recoil_debt > 0.0 and _since_shot > 0.09:
		var r := minf(_recoil_debt, _recoil_debt * dt * 9.0 + dt * 0.5)
		_recoil_debt -= r
		player.apply_recoil(-r, 0.0)
	_update_knives(dt)
	if not player.enabled:
		_release_line()
		return
	var dbg_fire := Game.debug.has("fire")
	var trig := Input.is_action_pressed("fire") or dbg_fire
	var want_fire := drawn and _draw_t <= 0.0 and reloading <= 0.0 and trig and not Game.tuning_open()
	if not trig:
		_shots_in_burst = 0
	if want_fire and cooldown <= 0.0:
		match _kind():
			"gun":
				if auto_mode or dbg_fire or Input.is_action_just_pressed("fire"):
					_fire()
			"melee":
				_slash()
			"grapple":
				if Input.is_action_just_pressed("fire") or (dbg_fire and not has_meta("dbg_grappled")):
					set_meta("dbg_grappled", true)
					print("grapple from ", player.global_position)
					_fire_grapple()
	_update_focus()
	_noise_t -= dt
	if _noise_t <= 0.0:
		_noise_t = 0.33
		if player.noise_radius > 0.0:
			get_tree().call_group("npc", "hear_noise", player.global_position, player.noise_radius)

func _spring3(x: Vector3, v: Vector3, k: float, d: float, dt: float) -> Array:
	# Sub-stepped so stiff springs stay stable at low frame rates.
	var n := maxi(1, int(ceil(dt / 0.008)))
	var h := dt / n
	for i in n:
		v += (-k * x - d * v) * h
		x += v * h
	return [x, v]

func _process(dt: float) -> void:
	if player == null or _vm == null:
		return
	_draw_t -= dt
	hit_t = maxf(hit_t - dt, 0.0)
	_update_tracers(dt)
	_update_shells(dt)
	_update_line(dt)
	_slash_t = maxf(_slash_t - dt, 0.0)
	_throw_t = maxf(_throw_t - dt, 0.0)
	# Muzzle flash lifetime (frame-rate independent).
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash_light.light_energy = 7.0 * clampf(_flash_t / 0.05, 0.0, 1.0)
		if _flash_t <= 0.0:
			_flash.visible = false
			_flash_light.light_energy = 0.0
	var aiming := drawn and bool(_cfg.get("ads", false)) and (Input.is_action_pressed("aim") or Game.debug.has("aim")) and reloading <= 0.0 and player.enabled and not Game.tuning_open()
	player.aiming = aiming
	ads = move_toward(ads, 1.0 if aiming else 0.0, dt * 7.5)
	var ease_ads := ads * ads * (3.0 - 2.0 * ads)
	# Springs.
	var r := _spring3(_kp, _kpv, 260.0, 20.0, dt)
	_kp = r[0]
	_kpv = r[1]
	r = _spring3(_kr, _krv, 220.0, 17.0, dt)
	_kr = r[0]
	_krv = r[1]
	r = _spring3(_punch, _punch_v, 170.0, 15.0, dt)
	_punch = r[0]
	_punch_v = r[1]
	_trauma = maxf(_trauma - dt * 2.2, 0.0)
	_fov_kick = move_toward(_fov_kick, 0.0, dt * 0.5)
	# Camera: punch rotation + trauma shake (offsets only; aim is untouched).
	var t := Time.get_ticks_msec() * 0.001
	var sh := _trauma * _trauma
	cam.rotation = _punch + Vector3(sin(t * 61.0), sin(t * 53.0 + 1.3), sin(t * 47.0 + 2.1) * 1.5) * sh * 0.012
	cam.h_offset = sin(t * 71.0) * sh * 0.012
	cam.v_offset = sin(t * 67.0 + 0.7) * sh * 0.012
	player.fov_scale = 1.0 + _fov_kick
	# Mouse-look sway: the gun lags behind the view.
	var ld := _look_delta
	_look_delta = Vector2.ZERO
	_sway = _sway.lerp(Vector2(clampf(-ld.x * 0.0009, -0.06, 0.06), clampf(ld.y * 0.0009, -0.05, 0.05)) * (1.0 - ease_ads * 0.85), 1.0 - exp(-dt * 10.0))
	# Pose.
	var spd := player.get_horizontal_speed()
	var sprinting := spd > 5.6 and not aiming and _since_shot > 0.35 and reloading <= 0.0
	_sprint_pose = move_toward(_sprint_pose, 1.0 if sprinting else 0.0, dt * 5.0)
	var hip: Vector3 = _cfg.get("hip", Vector3(0.19, -0.19, -0.42))
	# Sight on the camera axis: gun offset = -(sight point) + eye relief.
	var sight_pt: Vector3 = _cfg.get("sight", SIGHT_CENTER)
	var aim := -sight_pt + Vector3(0, 0, -float(_cfg.get("eye", SIGHT_EYE_DIST)))
	var pos := hip.lerp(aim, ease_ads)
	var bob_amt := clampf(spd / 7.0, 0.0, 1.0) * (1.0 - ease_ads * 0.85) * (1.0 if player.is_on_floor() else 0.0)
	var bob := Vector3(sin(t * 7.2) * 0.008, -absf(sin(t * 7.2)) * 0.012, 0) * bob_amt
	var breathe := Vector3(sin(t * 1.3) * 0.0015, sin(t * 1.9) * 0.002, 0) * (1.0 - ease_ads * 0.7)
	var draw_k := clampf(_draw_t / 0.32, 0.0, 1.0)
	var draw_off := Vector3(0.05, -0.3, 0.12) * draw_k * draw_k
	# Wall proximity: pull the gun in so it does not clip into walls.
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + player.get_look_dir() * 0.85, 1)
	var near := not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	_wall_pull = move_toward(_wall_pull, 1.0 if near else 0.0, dt * 6.0)
	# Reload choreography: tilt, drop mag, insert, slap.
	var rel := Vector3.ZERO
	var rel_rot := Vector3.ZERO
	if _mag:
		_mag.position = _cfg.get("mag_rest", Vector3(0, -0.11, 0.12))
		_mag.visible = true
	if _slash_t > 0.0:
		# Knife: a fast diagonal cut from upper right to lower left.
		var ks := 1.0 - _slash_t / 0.32
		var cs := sin(clampf(ks * 1.25, 0.0, 1.0) * PI)
		rel += Vector3(-0.14, 0.03, -0.12) * cs
		rel_rot += Vector3(-0.7, 0.9, 1.4) * cs
	if _throw_t > 0.0:
		var kt := 1.0 - _throw_t / 0.35
		var ct := sin(kt * PI)
		rel += Vector3(-0.05, 0.12, 0.08) * ct
		rel_rot += Vector3(1.2, 0.0, 0.3) * ct
	if reloading > 0.0 and _mag:
		var T := float(weapon.reload_time)
		var k := 1.0 - reloading / T
		var tilt := smoothstep(0.0, 0.18, k) * (1.0 - smoothstep(0.82, 1.0, k))
		rel = Vector3(-0.04, -0.06, 0.05) * tilt
		rel_rot = Vector3(0.35, 0.25, 0.55) * tilt
		if k > 0.2 and k < 0.42:
			_mag.position.y -= smoothstep(0.2, 0.42, k) * 0.35
			_mag.visible = k < 0.4
		elif k >= 0.42 and k < 0.7:
			_mag.position.y -= (1.0 - smoothstep(0.45, 0.7, k)) * 0.3
			_mag.visible = k > 0.45
	var sprint_off := Vector3(-0.06, -0.05, 0.04) * _sprint_pose
	var sprint_rot := Vector3(-0.25, 0.7, 0.25) * _sprint_pose
	var wall_off := Vector3(0, -0.06, 0.16) * _wall_pull
	var wall_rot := Vector3(0.6, 0, 0) * _wall_pull
	var strafe := player.get_global_transform().basis.inverse() * player.velocity
	_vm_gun.position = pos + bob + breathe + draw_off + rel + sprint_off + wall_off + _kp + Vector3(_sway.x, _sway.y, 0) * 0.5
	_vm_gun.rotation = _kr + rel_rot + sprint_rot + wall_rot + Vector3(_sway.y * 2.0, _sway.x * 2.5, clampf(-strafe.x * 0.012, -0.06, 0.06) + _sway.x * 1.5)
	if _selector:
		_selector.rotation.x = -1.2 if auto_mode else 0.0
	var ammo := free_ammo
	if mission_on():
		ammo = int(Game.mstate().get("ammo", 0))
	if _ammo_label:
		_ammo_label.text = "%02d" % ammo
		_ammo_label.modulate = Color("#9FE8A8") if ammo > 6 else Color("#E8A25A")
	if _cfg.has("sheath"):
		(_cfg.sheath as Node3D).visible = ammo > 0
	if _cfg.has("hook"):
		(_cfg.hook as Node3D).visible = _hook_t < 0.0 and not player.is_grappling()

## Spend one round of the drawn weapon (mission ammo or free play).
func _take_round() -> bool:
	if mission_on():
		return Game.sim.try_fire()
	if free_ammo > 0:
		free_ammo -= 1
		return true
	return false

func _fire() -> void:
	var ok := _take_round()
	if not ok:
		Game.play_2d("dry", -2)
		cooldown = 0.25
		_krv += Vector3(1.0, 0, 0)
		return
	cooldown = float(weapon.fire_interval)
	_since_shot = 0.0
	_shots_in_burst += 1
	var spread := current_spread()
	spread_bloom = minf(spread_bloom + (0.35 if ads > 0.5 else 0.7), 3.5)
	var dir := player.get_look_dir()
	var rr := deg_to_rad(spread) * sqrt(randf())
	var a := randf() * TAU
	var basis := Basis.looking_at(dir, Vector3.UP)
	dir = (basis * Vector3(cos(a) * tan(rr), sin(a) * tan(rr), -1.0)).normalized()
	var from := cam.global_position
	var to := from + dir * float(weapon.range)
	var hit := _shot_ray(from, to)
	var muzzle := _flash.global_position
	var end := to
	if not hit.is_empty():
		end = hit.position
		var col: Object = hit.collider
		if col is Npc or (col is PhysicalBone3D and col.has_meta("npc_body")):
			var res := _hit_body(hit, dir, from, weapon_id, 18.0 if weapon.get("suppressed", false) else 30.0, "die")
			if res.was_alive:
				hit_t = 0.28 if res.killed else 0.16
				hit_kill = res.killed
				hit_head = res.zone == "head"
				Game.play_2d("hitmark", -6 if not res.killed else -2, 0.8 if res.killed else (1.25 if hit_head else 1.0))
		else:
			var n: Vector3 = hit.normal
			_mark(hit.position, n)
			_burst("dust", hit.position, n)
			_burst("sparks", hit.position, dir.bounce(n) if randf() < 0.5 else n)
			Game.play_3d("impact", hit.position, -4, 4.0, randf_range(0.85, 1.2))
			if randf() < 0.25:
				Game.play_3d("whiz", hit.position, -14, 3.0, randf_range(1.3, 1.7))
		if col is RigidBody3D:
			(col as RigidBody3D).apply_impulse(dir * 6.0, hit.position - (col as RigidBody3D).global_position)
	var sup: bool = weapon.get("suppressed", false)
	if not sup:
		tracer(muzzle, end)
	# Sound: the report, or the suppressor's cough.
	Game.play_2d("silenced" if sup else "shot", -2 if sup else 0, randf_range(0.94, 1.06) * float(_cfg.get("pitch", 1.0)))
	# Flash (a suppressor leaves only a faint spark).
	var fsc := float(_cfg.get("flash_scale", 1.0))
	_flash.visible = fsc > 0.0
	_flash.rotation = Vector3(0, 0, randf() * TAU)
	var fs := randf_range(0.8, 1.3) * fsc
	_flash.scale = Vector3(fs, fs, randf_range(0.8, 1.5) * fsc)
	_flash_t = 0.05
	_flash_light.light_energy = 7.0 * fsc
	if not sup or randf() < 0.4:
		_burst("smoke", muzzle, dir + Vector3.UP * 0.3)
	_eject_shell()
	# Kick: view model, camera punch, shake, FOV, permanent climb.
	var ak := (1.0 - ads * 0.55) * (0.7 if sup else 1.0)
	_kpv += Vector3(randf_range(-0.05, 0.05), 0.12, 1.1) * ak
	_krv += Vector3(3.2, randf_range(-0.8, 0.8), randf_range(-1.6, 1.6)) * ak
	_punch_v += Vector3(0.9 * ak + 0.25, randf_range(-0.25, 0.25), randf_range(-0.5, 0.5) * ak)
	_trauma = minf(_trauma + 0.24 * ak + 0.06, 0.85)
	_fov_kick = 0.03 * ak + 0.01
	var climb := 1.0 + minf(_shots_in_burst, 8) * 0.06
	var rp := float(weapon.recoil_pitch_deg) * (1.0 - ads * 0.4) * climb
	var ry := randf_range(-1.0, 1.0) * float(weapon.recoil_yaw_deg) + 0.12 * float(weapon.recoil_yaw_deg)
	player.apply_recoil(rp, ry)
	_recoil_debt += rp * 0.55
	get_tree().call_group("npc", "hear_noise", player.global_position, float(weapon.noise_radius))

## A shot ray that passes between the limbs of a person goes on through.
func _shot_ray(from: Vector3, to: Vector3) -> Dictionary:
	var ex: Array[RID] = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state
	for i in 3:
		var q := PhysicsRayQueryParameters3D.create(from, to, MASK_SHOT, ex)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not (hit.collider is Npc):
			return hit
		var body := (hit.collider as Npc).get_node_or_null("Visual") as NpcBody
		if body == null:
			return hit
		var z := body.zone_for_ray(from, (to - from).normalized())
		if not z.miss:
			hit["zone"] = z.zone
			hit["bone"] = z.bone
			hit["position"] = z.point
			return hit
		ex.append((hit.collider as Npc).get_rid())
	return {}

## A projectile (bullet or blade) into a person, standing or on the ground:
## damage by body part, wound mark, blood, push on a ragdoll.
func _hit_body(hit: Dictionary, dir: Vector3, from: Vector3, wid: String, knock: float, how: String) -> Dictionary:
	var col: Object = hit.collider
	var npc: Npc
	var body: NpcBody
	var zone := str(hit.get("zone", "chest"))
	var bone := str(hit.get("bone", "UpperChest"))
	if col is PhysicalBone3D:
		body = col.get_meta("npc_body")
		npc = body.npc
		bone = str(col.get("bone_name"))
		zone = str(NpcBody.BONE_ZONE.get(bone, "chest"))
		(col as PhysicalBone3D).apply_impulse(dir * knock * 0.5, hit.position - (col as PhysicalBone3D).global_position)
	else:
		npc = col as Npc
		body = npc.get_node_or_null("Visual") as NpcBody
	var res := {"was_alive": npc != null and npc.alive, "killed": false, "zone": zone}
	_burst("mist", hit.position, -dir + Vector3.UP * 0.2)
	Game.play_3d("flesh", hit.position, 0)
	if body:
		body.mark_wound(hit.position, -dir, bone)
	if npc == null or not npc.alive:
		return res
	npc.set_meta("knock", knock)
	npc.set_meta("knock_how", how)
	var dmg: float = Game.sim.weapon_damage(wid, from.distance_to(hit.position), zone == "head")
	res.killed = npc.apply_hit(dmg, player.global_position, zone)
	if res.killed and level and level.has_method("on_npc_killed"):
		level.on_npc_killed(npc)
	return res

## Where a person is now: standing, or wherever the body lies.
static func _npc_pos(npc: Npc) -> Vector3:
	if npc.is_downed():
		var b := npc.get_node_or_null("Visual") as NpcBody
		if b:
			return b.center()
	return npc.global_position

# ------------------------------------------------------------- interaction

func _update_focus() -> void:
	focus = null
	prompt = ""
	takedown_target = null
	var from := cam.global_position
	var dir := player.get_look_dir()
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.6, MASK_INTERACT | 1)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit.collider is Interactable:
		var it := hit.collider as Interactable
		var p := it.prompt()
		if p != "":
			focus = it
			prompt = p
	# Takedown candidate: close, in front, from behind or unaware.
	var best := 1.8
	for n in get_tree().get_nodes_in_group("npc"):
		var npc := n as Npc
		if npc == null or not npc.alive:
			continue
		var at := _npc_pos(npc)
		var d := at.distance_to(player.global_position)
		if d < best:
			var to := (at - player.global_position)
			to.y = 0
			if to.normalized().dot(Vector3(dir.x, 0, dir.z).normalized()) > 0.6 and npc.can_takedown(player.global_position):
				best = d
				takedown_target = npc
	if takedown_target and prompt == "":
		prompt = "F  Takedown"

func _takedown() -> void:
	if takedown_target == null:
		return
	var npc := takedown_target
	npc.set_meta("knock", 5.0)
	npc.set_meta("knock_how", "limp" if npc.is_downed() else "takedown")
	npc.take_down()
	_krv += Vector3(-4.0, 0, 3.0)
	_kpv += Vector3(0, -0.3, 0.6)
	_trauma = minf(_trauma + 0.2, 0.5)
	Game.play_3d("thud", npc.global_position, -2)
	if level and level.has_method("on_npc_killed"):
		level.on_npc_killed(npc)

# ------------------------------------------------------------- gadgets

func current_gadget() -> Dictionary:
	if gadgets.is_empty():
		return {}
	return gadgets[gadget_i]

func _use_gadget() -> void:
	var g := current_gadget()
	if g.is_empty():
		return
	var kind: String = g.kind
	if Game.sim.gadget_count(g.id) <= 0:
		message.emit("No %s left." % g.name)
		return
	match kind:
		"tape_bug":
			_plant_bug(g)
		"static_lure":
			_throw_lure(g)
		"poison", "forgery":
			if focus and focus.gadget_kind == kind:
				focus.use()
			else:
				message.emit("%s: use it on the right object (look at it and press E)." % g.name)
	refresh_gadgets()

func _plant_bug(g: Dictionary) -> void:
	var def: Dictionary = Game.sim.gadget_def(g.id)
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + player.get_look_dir() * float(def.get("use_range", 3.0)), 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		message.emit("Murmur Cassette: aim at a nearby surface.")
		return
	if not Game.sim.consume_gadget(g.id):
		return
	var bug := Node3D.new()
	bug.add_to_group("tape_bug")
	bug.set_meta("radius", float(def.get("radius", 11.0)))
	var b := Builder.new(0.0)
	b.box(P.BEIGE, Vector3.ZERO, Vector3(0.12, 0.08, 0.03), false)
	b.box(P.BLACK, Vector3(0, 0, 0.016), Vector3(0.08, 0.035, 0.005), false)
	b.box(P.CRT, Vector3(0.045, 0.028, 0.016), Vector3(0.01, 0.01, 0.006), false)
	var mi := MeshInstance3D.new()
	mi.mesh = b.mesh()
	bug.add_child(mi)
	get_tree().current_scene.add_child(bug)
	var n: Vector3 = hit.normal
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	bug.global_transform = Transform3D(Basis.looking_at(-n, up), hit.position + n * 0.016)
	Game.play_3d("tape", bug.global_position, -6)
	message.emit("Murmur Cassette planted. It records speech within %d m." % int(def.get("radius", 11.0)))

func _throw_lure(g: Dictionary) -> void:
	if not Game.sim.consume_gadget(g.id):
		return
	var def: Dictionary = Game.sim.gadget_def(g.id)
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.6
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.22, 0.14, 0.1)
	cs.shape = bs
	body.add_child(cs)
	var b := Builder.new(0.0)
	b.box(P.WARM_GREY, Vector3.ZERO, Vector3(0.22, 0.14, 0.1), false)
	b.box(P.CHARCOAL, Vector3(0, 0, 0.052), Vector3(0.14, 0.09, 0.005), false)
	b.box(P.AMBER, Vector3(0.08, 0.05, 0.052), Vector3(0.015, 0.015, 0.006), false)
	b.cyl(P.STEEL, Vector3(-0.08, 0.17, 0), 0.006, 0.004, 0.22, 4)
	var mi := MeshInstance3D.new()
	mi.mesh = b.mesh()
	body.add_child(mi)
	var audio := AudioStreamPlayer3D.new()
	audio.stream = Game.sfx["static"]
	audio.unit_size = 5.0
	audio.max_distance = 40.0
	body.add_child(audio)
	get_tree().current_scene.add_child(body)
	var dir := player.get_look_dir()
	body.global_position = cam.global_position + dir * 0.5
	body.linear_velocity = dir * 13.0 + Vector3.UP * 2.5 + player.velocity * 0.5
	body.angular_velocity = Vector3(randf(), randf(), randf()) * 6.0
	Game.play_2d("throw", -6)
	var radius := float(def.get("radius", 18.0))
	var duration := float(def.get("duration", 9.0))
	await get_tree().create_timer(1.1).timeout
	if not is_instance_valid(body):
		return
	audio.play()
	var t := 0.0
	while t < duration and is_instance_valid(body):
		get_tree().call_group("npc", "hear_noise", body.global_position, radius)
		await get_tree().create_timer(1.5).timeout
		t += 1.5
	if is_instance_valid(body):
		audio.stop()
	message.emit("Static Lure exhausted.")

# ------------------------------------------------------------- feedback

func _on_footstep(loudness: float) -> void:
	Game.play_3d("step", player.global_position, linear_to_db(0.25 + loudness * 0.5), 3.0, randf_range(0.85, 1.15))

func _on_landed(impact: float) -> void:
	Game.play_3d("land", player.global_position, linear_to_db(clampf(impact, 0.2, 1.0)), 3.0)
	_kpv += Vector3(0, -0.6 * clampf(impact, 0.2, 1.0), 0)
	_krv += Vector3(-2.0 * clampf(impact, 0.2, 1.0), 0, 0)

## Called by the level when a guard fires at the player.
func incoming_shot(from: Vector3, to: Vector3, hit: bool, dmg: float) -> void:
	tracer(from, to, 260.0)
	Game.play_3d("shot_far", from, -2, 10.0, randf_range(0.9, 1.1))
	var eye := player.get_eye_position()
	if hit:
		hurt.emit(dmg)
		_punch_v += Vector3(randf_range(-1.5, 1.5), randf_range(-2.0, 2.0), randf_range(-2.5, 2.5))
		_trauma = minf(_trauma + 0.45, 1.0)
		Game.play_2d("flesh", -4, 0.8)
	else:
		# Near miss: crack past the head if the line passes close.
		var seg := to - from
		var t := clampf((eye - from).dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
		var closest := from + seg * t
		if closest.distance_to(eye) < 3.0:
			Game.play_3d("whiz", closest, -2, 4.0, randf_range(0.9, 1.2))
			_trauma = minf(_trauma + 0.15, 1.0)
		Game.play_3d("impact", to, -8, 3.0, randf_range(1.0, 1.3))
		_burst("dust", to, (from - to).normalized())

# ------------------------------------------------------------- knife

## Slash: one cut in front. Unaware targets (from behind) die outright.
func _slash() -> void:
	cooldown = float(weapon.get("fire_interval", 0.5))
	_slash_t = 0.32
	_krv += Vector3(-1.5, 2.0, 3.0)
	Game.play_2d("swish", -4, randf_range(0.9, 1.15))
	var reach := float(weapon.get("reach", 2.3))
	var dir := player.get_look_dir()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var best: Npc = null
	var best_d := reach
	for n in get_tree().get_nodes_in_group("npc"):
		var npc := n as Npc
		if npc == null or not npc.alive:
			continue
		var to := _npc_pos(npc) - player.global_position
		var d := Vector2(to.x, to.z).length()
		if d < best_d and absf(to.y) < 1.5 and Vector3(to.x, 0, to.z).normalized().dot(flat) > 0.55:
			best = npc
			best_d = d
	if best == null:
		get_tree().call_group("npc", "hear_noise", player.global_position, float(weapon.get("noise_radius", 2.0)))
		return
	var silent_kill := best.can_takedown(player.global_position)
	var dmg: float = 9999.0 if silent_kill else float(weapon.get("damage", 70.0))
	best.set_meta("knock", 12.0)
	best.set_meta("knock_how", "die")
	var killed := best.apply_damage(dmg, player.global_position, false)
	var at := best.global_position + Vector3(0, 1.2, 0)
	_burst("mist", at, -flat + Vector3.UP * 0.3)
	Game.play_3d("stab", at, 0)
	hit_t = 0.28 if killed else 0.16
	hit_kill = killed
	hit_head = false
	Game.play_2d("hitmark", -2 if killed else -6, 0.8 if killed else 1.0)
	_trauma = minf(_trauma + 0.15, 0.6)
	if killed and level and level.has_method("on_npc_killed"):
		level.on_npc_killed(best)
	get_tree().call_group("npc", "hear_noise", player.global_position, float(weapon.get("noise_radius", 2.0)))

static func _knife_mesh() -> Mesh:
	return Builder.cached("throw_knife", func():
		var b := Builder.new(0.0)
		b.box(P.CHARCOAL, Vector3(0, 0, -0.08), Vector3(0.006, 0.03, 0.16), false)
		b.box(P.CHROME, Vector3(0, -0.014, -0.08), Vector3(0.007, 0.005, 0.16), false)
		b.box(P.LEATHER, Vector3(0, 0, 0.05), Vector3(0.012, 0.024, 0.1), false)
		return b.mesh())

## Throw one of the spare blades. It flies with gravity, sticks where it
## lands and can be picked back up by walking over it.
func _throw_knife() -> void:
	if _throw_t > 0.0 or _slash_t > 0.0:
		return
	if not _take_round():
		Game.play_2d("dry", -6)
		return
	_throw_t = 0.35
	Game.play_2d("swish", -2, 1.3)
	var mi := MeshInstance3D.new()
	mi.mesh = _knife_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	var dir := player.get_look_dir()
	mi.global_position = cam.global_position + dir * 0.4 + cam.global_basis.x * 0.12
	mi.global_basis = Basis.looking_at(dir, Vector3.UP)
	_knives.append({"node": mi, "vel": dir * 30.0 + Vector3.UP * 1.2, "stuck": false, "id": weapon_id, "age": 0.0})
	while _knives.size() > 12:
		var old: Dictionary = _knives.pop_front()
		if is_instance_valid(old.node):
			old.node.queue_free()

func _update_knives(dt: float) -> void:
	var space := player.get_world_3d().direct_space_state
	for k in _knives.duplicate():
		var node: Node3D = k.node
		if not is_instance_valid(node):
			_knives.erase(k)
			continue
		k.age += dt
		if k.stuck:
			# Pick-up: walk over it.
			if k.age > 0.5 and node.global_position.distance_to(player.global_position + Vector3(0, 0.6, 0)) < 1.6:
				if mission_on():
					Game.sim.add_ammo(k.id, 1)
				elif k.id == weapon_id:
					free_ammo += 1
				else:
					_free[k.id] = int(_free.get(k.id, 0)) + 1
				Game.play_2d("beep", -10, 1.4)
				node.queue_free()
				_knives.erase(k)
			continue
		var v: Vector3 = k.vel
		v.y -= 9.8 * dt
		k.vel = v
		var from := node.global_position
		var to := from + v * dt
		var hit := _shot_ray(from, to)
		if hit.is_empty():
			node.global_position = to
			node.rotate_object_local(Vector3.RIGHT, -dt * 22.0)
			if k.age > 4.0:
				node.queue_free()
				_knives.erase(k)
			continue
		k.stuck = true
		k.age = 0.0
		var col: Object = hit.collider
		if col is Npc or (col is PhysicalBone3D and col.has_meta("npc_body")):
			var res := _hit_body(hit, v.normalized(), from, k.id, 14.0, "die")
			Game.play_3d("stab", hit.position, 0)
			if res.was_alive:
				hit_t = 0.28 if res.killed else 0.16
				hit_kill = res.killed
				hit_head = res.zone == "head"
				Game.play_2d("hitmark", -2 if res.killed else -6)
			# Drop at their feet to be recovered.
			node.global_position = Vector3(hit.position.x, player.global_position.y + 0.05, hit.position.z)
			node.global_basis = Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, -PI / 2)
		else:
			node.global_position = hit.position - v.normalized() * 0.06
			node.global_basis = Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.95 else Vector3.RIGHT)
			Game.play_3d("impact", hit.position, -8, 3.0, 1.6)
			_burst("sparks", hit.position, hit.normal)
		get_tree().call_group("npc", "hear_noise", node.global_position, 4.0)

# ------------------------------------------------------------- grapple line

## Fire the hook at whatever is under the crosshair. A wall or a roof: it
## winds you in (jump, LMB or RMB lets go). A person: the hook sticks in
## them. Then LMB hauls them flying back to you, or aim at something else
## and RMB makes the line fast there: they fly into it and crash. R drops it.
const LINE_MASK := 1 | 4 | 8 | NpcBody.LAYER

func _fire_grapple() -> void:
	cooldown = 0.35
	if _latched:
		_yank()
		return
	if player.is_grappling() or _hook_t >= 0.0 or not _tether.is_empty():
		_release_line()
		return
	var dir := player.get_look_dir()
	var from := cam.global_position
	var rng := float(weapon.get("range", 38.0))
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * rng, LINE_MASK, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	_hook_body = null
	if not hit.is_empty():
		_hook_body = _body_of(hit.collider)
		if _hook_body:
			var z := _hook_body.zone_for_ray(from, dir)
			_hook_bone = str(hit.collider.get("bone_name")) if hit.collider is PhysicalBone3D else str(z.bone)
	_hook_from = _flash.global_position
	_hook_hit = not hit.is_empty() and (_hook_body != null or (int(hit.collider.get("collision_layer")) & 1) != 0)
	_hook_to = hit.position if not hit.is_empty() else from + dir * rng
	_hook_dur = maxf(_hook_from.distance_to(_hook_to) / HOOK_SPEED, 0.05)
	_hook_t = 0.0
	_hook.visible = true
	_rope.visible = true
	Game.play_2d("grapple", -3)
	_krv += Vector3(2.5, 0, 0)
	_trauma = minf(_trauma + 0.1, 0.4)

## The person a collider belongs to (standing capsule or a ragdoll bone).
func _body_of(col: Object) -> NpcBody:
	if col is Npc:
		return (col as Npc).get_node_or_null("Visual") as NpcBody
	if col is PhysicalBone3D and col.has_meta("npc_body"):
		var b: NpcBody = col.get_meta("npc_body")
		return b if is_instance_valid(b) and b.is_physical() else null
	return null

## Ballistic launch velocity from `a` to land at `b` after `t` seconds.
static func _launch(a: Vector3, b: Vector3, t: float) -> Vector3:
	return (b - a) / t + Vector3.UP * 0.5 * 9.8 * t

## Haul the hooked person in: off their feet, flying back to land at yours.
func _yank() -> void:
	var body := _latched
	_latched = null
	if not is_instance_valid(body):
		_release_line()
		return
	var npc := body.npc
	var flat := player.get_look_dir()
	flat.y = 0.0
	flat = flat.normalized()
	var land := player.global_position + flat * 2.4 + Vector3.UP * 0.15
	var start := body.center()
	var t := clampf(start.distance_to(land) / 15.0, 0.35, 1.0)
	if npc and npc.alive and not npc.is_downed():
		npc.set_meta("knock", 10.0)
		npc.set_meta("knock_how", "die")
		npc.knock_down(8.0, player.global_position)
	body.fling(_launch(start, land, t))
	Game.play_2d("winch", -2, 1.4)
	Game.play_3d("swish", start, 0, 4.0, 0.7)
	_krv += Vector3(-6.0, 0, 0)
	_kpv += Vector3(0, 0, 1.4)
	_trauma = minf(_trauma + 0.3, 0.7)
	_tether = {"body": body, "at": Vector3.INF, "t": 0.0, "hand": true}
	if not body.crashed.is_connected(_on_crash):
		body.crashed.connect(_on_crash.bind(body))

## Make the line fast to whatever is under the crosshair: the hooked person
## flies into it.
func _tether_to_aim() -> void:
	var body := _latched
	if not is_instance_valid(body):
		_release_line()
		return
	var dir := player.get_look_dir()
	var from := cam.global_position
	var rng := float(weapon.get("range", 38.0)) * 1.5
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * rng, LINE_MASK, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		Game.play_2d("dry", -6)
		return
	var other := _body_of(hit.collider)
	if other == body:
		return
	_latched = null
	var at: Vector3 = hit.position
	var npc := body.npc
	if npc and npc.alive and not npc.is_downed():
		npc.set_meta("knock", 10.0)
		npc.set_meta("knock_how", "die")
		npc.knock_down(8.0, player.global_position)
	var start := body.center()
	var speed := 24.0
	var dist := start.distance_to(at)
	# Fast and flat: barely any arc, straight into it.
	var v := (at - start) / maxf(dist / speed, 0.08) + Vector3.UP * minf(dist * 0.15, 3.0)
	body.fling(v)
	if other:
		# Two people: they meet in the middle.
		var on := other.npc
		if on and on.alive and not on.is_downed():
			on.knock_down(8.0, player.global_position)
		other.fling((start - other.center()).normalized() * 9.0 + Vector3.UP * 2.0)
		if not other.crashed.is_connected(_on_crash):
			other.crashed.connect(_on_crash.bind(other))
	_tether = {"body": body, "at": at, "t": 0.0, "hand": false, "anchor": hit.collider}
	_hook.global_position = at
	_hook.visible = true
	Game.play_2d("grapple", -2, 0.85)
	Game.play_3d("impact", at, -4, 4.0, 1.3)
	Game.play_2d("winch", -2, 1.6)
	_krv += Vector3(3.0, 0, 0)
	if not body.crashed.is_connected(_on_crash):
		body.crashed.connect(_on_crash.bind(body))

func _on_crash(impact: float, at: Vector3, body: NpcBody) -> void:
	Game.play_3d("thud", at, 2, 6.0, randf_range(0.8, 1.0))
	Game.play_3d("impact", at, 0, 6.0, 0.7)
	_burst("dust", at, Vector3.UP)
	if player.global_position.distance_to(at) < 8.0:
		_trauma = minf(_trauma + 0.25, 0.8)
	var npc := body.npc if is_instance_valid(body) else null
	if npc and npc.alive:
		npc.set_meta("knock", 4.0)
		npc.set_meta("knock_how", "limp")
		var killed := npc.crash(impact, at)
		if killed:
			hit_t = 0.28
			hit_kill = true
			hit_head = false
			Game.play_2d("hitmark", -2, 0.8)
			if level and level.has_method("on_npc_killed"):
				level.on_npc_killed(npc)
	if not _tether.is_empty() and _tether.body == body:
		_release_line()

func _release_line() -> void:
	if player and player.is_grappling():
		player.stop_grapple()
	_hook_t = -1.0
	_hook_body = null
	_latched = null
	_tether = {}
	if _hook:
		_hook.visible = false
	if _rope:
		_rope.visible = false
	if _winch and _winch.playing:
		_winch.stop()

func _update_line(dt: float) -> void:
	if _rope == null or not _rope.is_inside_tree():
		return
	var hand := _flash.global_position if _kind() == "grapple" else player.global_position + Vector3(0, 1.2, 0)
	if _hook_t >= 0.0:
		_hook_t += dt
		var k := clampf(_hook_t / _hook_dur, 0.0, 1.0)
		var to := _hook_to
		if is_instance_valid(_hook_body):
			to = _hook_body.bone_position(_hook_bone)   # the target may move
		var at := _hook_from.lerp(to, k)
		_hook.global_position = at
		var d := (to - _hook_from).normalized()
		if d.length() > 0.1:
			_hook.global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
		_draw_rope(hand, at)
		if k >= 1.0:
			_hook_t = -1.0
			if is_instance_valid(_hook_body):
				_latched = _hook_body
				_hook_body = null
				Game.play_3d("stab", to, -2, 4.0, 1.2)
				_burst("mist", to, (hand - to).normalized())
				var n := _latched.npc
				if n and n.alive:
					n.hear_noise(player.global_position, 30.0)
				message.emit("Line fast.  LMB: haul in   RMB at a target: tether   R: let go")
			elif _hook_hit:
				if Game.debug.has("fire"):
					print("grapple anchor ", _hook_to)
				player.start_grapple(_hook_to)
				Game.play_3d("impact", _hook_to, -4, 4.0, 1.4)
				_winch.play()
			else:
				_release_line()
		return
	if _latched:
		if not is_instance_valid(_latched) or _latched.global_position.distance_to(player.global_position) > float(weapon.get("range", 38.0)) * 1.6:
			_release_line()
			return
		var at := _latched.bone_position(_hook_bone)
		_hook.global_position = at
		_draw_rope(hand, at)
		return
	if not _tether.is_empty():
		var body: NpcBody = _tether.body
		_tether.t += dt
		if not is_instance_valid(body) or _tether.t > 3.0:
			_release_line()
			return
		var at := body.bone_position(_hook_bone)
		if _tether.hand:
			_hook.global_position = at
			_draw_rope(hand, at)
			if not body.flying() and _tether.t > 0.3:
				_release_line()
		else:
			# The line runs from the person to the anchor; keep it taut.
			var anchor: Vector3 = _tether.at
			_hook.global_position = anchor
			_draw_rope(at, anchor)
			if body.flying():
				body.pull_toward(anchor, 22.0, dt)
			elif _tether.t > 0.3:
				_release_line()
		return
	if player.is_grappling():
		_draw_rope(hand, _hook.global_position)
	elif _rope.visible:
		if Game.debug.has("fire"):
			print("grapple released at ", player.global_position)
		_release_line()

func _draw_rope(a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	if len < 0.05:
		_rope.visible = false
		return
	_rope.visible = true
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT
	var bas := Basis.looking_at(b - a, up)
	bas.z *= len
	_rope.global_transform = Transform3D(bas, (a + b) * 0.5)
