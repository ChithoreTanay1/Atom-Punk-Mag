class_name PlayerRig
extends Node
## Weapon, gadgets, interaction and takedowns for the FpsController.
## Rules (damage, ammo, gadget stock) live in Rust; this is presentation
## and physics queries.

const P = preload("res://scripts/palette.gd")
const MASK_SHOT := 1 | 4 | 8
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
var free_ammo := 24  # used outside missions (test track)
var spread_bloom := 0.0
var gadgets: Array = []  # [{id,name,kind,count}]
var gadget_i := 0
var prompt := ""
var focus: Interactable
var takedown_target: Npc

var _vm: Node3D
var _vm_gun: Node3D
var _ammo_label: Label3D
var _selector: Node3D
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _tracers: Array[MeshInstance3D] = []
var _tracer_i := 0
var _marks: Array[MeshInstance3D] = []
var _mark_i := 0
var _kick := 0.0
var _sway := Vector2.ZERO
var _noise_t := 0.0
var _draw_t := 0.0

func setup(p: FpsController, lvl: Node) -> void:
	player = p
	level = lvl
	cam = p.get_camera()
	var info: Dictionary = Game.sim.mission_info()
	weapon_id = info.get("weapon", "wpn_carbine_vajra")
	weapon = Game.sim.weapon_def(weapon_id)
	if weapon.is_empty():
		weapon = {"fire_interval": 0.1, "spread_deg": 2.0, "ads_spread_deg": 0.3, "recoil_pitch_deg": 1.0, "recoil_yaw_deg": 0.3, "range": 120.0, "noise_radius": 45.0, "reload_time": 2.0, "mag_size": 24, "has_auto": true, "name": "Carbine"}
	free_ammo = int(weapon.get("mag_size", 24))
	refresh_gadgets()
	_build_viewmodel()
	_build_fx()
	p.footstep.connect(_on_footstep)
	p.landed.connect(_on_landed)

func refresh_gadgets() -> void:
	var st: Dictionary = Game.sim.mission_state()
	gadgets = st.get("gadgets", [])
	gadget_i = clampi(gadget_i, 0, maxi(gadgets.size() - 1, 0))

func mission_on() -> bool:
	return Game.sim.mission_active()

# ------------------------------------------------------------- view model

func _build_viewmodel() -> void:
	_vm = Node3D.new()
	_vm.name = "ViewModel"
	cam.add_child(_vm)
	_vm_gun = Node3D.new()
	_vm.add_child(_vm_gun)
	var b := Builder.new(0.15)
	# Bullpup carbine silhouette, cassette-futurist casing.
	b.box(P.BEIGE, Vector3(0, 0, 0.05), Vector3(0.07, 0.11, 0.52), false)          # receiver
	b.box(P.CHARCOAL, Vector3(0, -0.01, -0.33), Vector3(0.06, 0.08, 0.26), false)   # handguard
	b.cyl_xf(P.CHARCOAL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.01, -0.53)), 0.017, 0.017, 0.18, 8)
	b.cyl_xf(P.STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.01, -0.63)), 0.024, 0.024, 0.04, 8)
	b.box(P.CHARCOAL, Vector3(0, 0.085, -0.05), Vector3(0.03, 0.05, 0.36), false)  # carry rail
	b.box(P.WARM_GREY, Vector3(0, 0.125, -0.02), Vector3(0.05, 0.05, 0.13), false) # analog sight box
	b.box(P.BLACK, Vector3(0, 0.125, 0.045), Vector3(0.035, 0.03, 0.005), false)
	b.box(P.CHARCOAL, Vector3(0, -0.1, -0.11), Vector3(0.04, 0.12, 0.05), false)   # grip
	b.box(P.WARM_GREY, Vector3(0, -0.11, 0.12), Vector3(0.045, 0.14, 0.08), false) # magazine (bullpup)
	b.box(P.CHARCOAL, Vector3(0, -0.06, -0.06), Vector3(0.012, 0.05, 0.08), false) # trigger guard
	b.box(P.CHARCOAL, Vector3(0, 0.0, 0.33), Vector3(0.072, 0.12, 0.04), false)    # butt pad
	for i in 5:
		b.box(P.BLACK, Vector3(0.036, 0.02, -0.02 + i * 0.03), Vector3(0.004, 0.05, 0.012), false)  # vents
	b.box(P.CRT, Vector3(-0.037, 0.02, 0.16), Vector3(0.004, 0.045, 0.07), false)  # side CRT
	b.box(P.AMBER, Vector3(0.037, 0.04, 0.2), Vector3(0.006, 0.014, 0.014), false) # ready lamp
	b.cyl_xf(P.BLACK, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0.05, -0.03, 0.22)), 0.006, 0.006, 0.08, 6) # cable
	var mi := MeshInstance3D.new()
	mi.mesh = b.mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm_gun.add_child(mi)
	_selector = Node3D.new()
	_selector.position = Vector3(0.038, -0.02, 0.08)
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
	_ammo_label.position = Vector3(-0.0405, 0.02, 0.16)
	_ammo_label.rotation = Vector3(0, -PI / 2, 0)
	_ammo_label.shaded = false
	_vm_gun.add_child(_ammo_label)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color("#E9B86A")
	_flash_light.omni_range = 7.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	_flash_light.position = Vector3(0, 0.01, -0.7)
	_vm_gun.add_child(_flash_light)
	_flash_mesh = MeshInstance3D.new()
	var qb := Builder.new(0.0)
	qb.box(P.AMBER, Vector3(0, 0, 0), Vector3(0.09, 0.09, 0.12), false)
	_flash_mesh.mesh = qb.mesh()
	_flash_mesh.position = Vector3(0, 0.01, -0.72)
	_flash_mesh.visible = false
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vm_gun.add_child(_flash_mesh)
	_vm.visible = false

func _build_fx() -> void:
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color("#E9B86A")
	var tb := BoxMesh.new()
	tb.size = Vector3(0.02, 0.02, 1.0)
	tb.material = tm
	var root := get_tree().current_scene
	for i in 10:
		var t := MeshInstance3D.new()
		t.mesh = tb
		t.visible = false
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.top_level = true
		root.add_child.call_deferred(t)
		_tracers.append(t)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.08, 0.08, 0.08)
	mm.roughness = 1.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	qm.material = mm
	for i in 28:
		var m := MeshInstance3D.new()
		m.mesh = qm
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.top_level = true
		root.add_child.call_deferred(m)
		_marks.append(m)

func tracer(from: Vector3, to: Vector3) -> void:
	var t := _tracers[_tracer_i]
	_tracer_i = (_tracer_i + 1) % _tracers.size()
	var d := from.distance_to(to)
	if d < 0.1 or not t.is_inside_tree():
		return
	t.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), (from + to) * 0.5)
	t.scale = Vector3(1, 1, d)
	t.visible = true
	get_tree().create_timer(0.045).timeout.connect(func(): t.visible = false)

func _mark(pos: Vector3, n: Vector3) -> void:
	var m := _marks[_mark_i]
	_mark_i = (_mark_i + 1) % _marks.size()
	if not m.is_inside_tree():
		return
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	m.global_transform = Transform3D(Basis.looking_at(-n, up), pos + n * 0.01)
	m.visible = true

# ------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if player == null or not player.enabled or Game.tuning_open() or get_tree().paused:
		return
	if e.is_action_pressed("holster"):
		set_drawn(not drawn)
	elif e.is_action_pressed("reload"):
		_reload()
	elif e.is_action_pressed("fire_mode") and weapon.get("has_auto", false):
		auto_mode = not auto_mode
		Game.play_2d("beep_low", -8)
	elif e.is_action_pressed("gadget_next") and not gadgets.is_empty():
		gadget_i = (gadget_i + 1) % gadgets.size()
		Game.play_2d("beep", -10)
	elif e.is_action_pressed("gadget_use"):
		_use_gadget()
	elif e.is_action_pressed("interact"):
		if focus:
			focus.use()
			Game.play_2d("beep", -10)
	elif e.is_action_pressed("takedown"):
		_takedown()
	elif e.is_action_pressed("fire") and not drawn:
		set_drawn(true)

func set_drawn(on: bool) -> void:
	drawn = on
	player.weapon_raised = on
	_vm.visible = on
	_draw_t = 0.25
	Game.play_2d("dry", -6, 0.8 if on else 0.6)

func _reload() -> void:
	if not drawn or reloading > 0.0:
		return
	if mission_on():
		var st: Dictionary = Game.mstate()
		if int(st.ammo) >= int(weapon.mag_size) or int(st.reserve) <= 0:
			return
	reloading = float(weapon.reload_time)
	Game.play_2d("reload", -4)

func _physics_process(dt: float) -> void:
	if player == null:
		return
	cooldown -= dt
	spread_bloom = maxf(spread_bloom - dt * 4.0, 0.0)
	if reloading > 0.0:
		reloading -= dt
		if reloading <= 0.0:
			if mission_on():
				Game.sim.reload()
			else:
				free_ammo = int(weapon.mag_size)
	if not player.enabled:
		return
	var want_fire := drawn and _draw_t <= 0.0 and reloading <= 0.0 and Input.is_action_pressed("fire") and not Game.tuning_open()
	if want_fire and cooldown <= 0.0:
		if auto_mode or Input.is_action_just_pressed("fire"):
			_fire()
	# Interaction focus.
	_update_focus()
	# AI hearing from footsteps (cheap, 3x per second).
	_noise_t -= dt
	if _noise_t <= 0.0:
		_noise_t = 0.33
		if player.noise_radius > 0.0:
			get_tree().call_group("npc", "hear_noise", player.global_position, player.noise_radius)

func _process(dt: float) -> void:
	if player == null or _vm == null:
		return
	_draw_t -= dt
	var aiming := drawn and Input.is_action_pressed("aim") and reloading <= 0.0 and player.enabled and not Game.tuning_open()
	player.aiming = aiming
	ads = move_toward(ads, 1.0 if aiming else 0.0, dt * 7.0)
	_kick = move_toward(_kick, 0.0, dt * 0.6)
	var hip := Vector3(0.19, -0.19, -0.42)
	var aim := Vector3(0.0, -0.137, -0.3)
	var pos := hip.lerp(aim, ads)
	var spd := player.get_horizontal_speed()
	var t := Time.get_ticks_msec() * 0.001
	var bob := Vector3(sin(t * 7.0) * 0.006, absf(sin(t * 7.0)) * 0.008, 0) * clampf(spd / 7.0, 0.0, 1.0) * (1.0 - ads * 0.8)
	var draw_off := Vector3(0, -0.25, 0.1) * clampf(_draw_t / 0.25, 0.0, 1.0)
	var reload_off := Vector3(0, -0.12, 0.05) * clampf(sin(clampf(reloading / float(weapon.reload_time), 0, 1) * PI), 0.0, 1.0)
	_vm_gun.position = pos + bob + draw_off + reload_off + Vector3(0, 0, _kick)
	_vm_gun.rotation = Vector3(_kick * 1.5 + reload_off.y * 2.0, 0, 0)
	_selector.rotation.x = -1.2 if auto_mode else 0.0
	var ammo := free_ammo
	if mission_on():
		ammo = int(Game.mstate().get("ammo", 0))
	_ammo_label.text = "%02d" % ammo

func _fire() -> void:
	var ok := false
	if mission_on():
		ok = Game.sim.try_fire()
	else:
		ok = free_ammo > 0
		if ok:
			free_ammo -= 1
	if not ok:
		Game.play_2d("dry", -2)
		cooldown = 0.25
		return
	cooldown = float(weapon.fire_interval)
	var spread: float = lerpf(float(weapon.spread_deg), float(weapon.ads_spread_deg), ads) + spread_bloom
	spread_bloom = minf(spread_bloom + 0.6, 3.0)
	var dir := player.get_look_dir()
	var r := deg_to_rad(spread) * sqrt(randf())
	var a := randf() * TAU
	var basis := Basis.looking_at(dir, Vector3.UP)
	dir = (basis * Vector3(cos(a) * tan(r), sin(a) * tan(r), -1.0)).normalized()
	var from := cam.global_position
	var to := from + dir * float(weapon.range)
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK_SHOT, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var muzzle := _flash_mesh.global_position
	var end := to
	if not hit.is_empty():
		end = hit.position
		var col: Object = hit.collider
		if col is Npc:
			var npc := col as Npc
			var head: bool = hit.position.y > npc.global_position.y + 1.48
			var dmg: float = Game.sim.weapon_damage(weapon_id, from.distance_to(hit.position), head)
			var killed := npc.apply_damage(dmg, player.global_position, head)
			Game.play_3d("flesh", hit.position, -2)
			if killed and level and level.has_method("on_npc_killed"):
				level.on_npc_killed(npc)
		else:
			_mark(hit.position, hit.normal)
			Game.play_3d("hit", hit.position, -8, 4.0, randf_range(0.85, 1.2))
	tracer(muzzle, end)
	Game.play_2d("shot", -3, randf_range(0.95, 1.05))
	_flash_light.light_energy = 3.0
	_flash_mesh.visible = true
	_flash_mesh.rotation.z = randf() * TAU
	get_tree().create_timer(0.04).timeout.connect(func():
		_flash_light.light_energy = 0.0
		_flash_mesh.visible = false)
	_kick = 0.04
	var rp := float(weapon.recoil_pitch_deg) * (1.0 - ads * 0.45)
	player.apply_recoil(rp, randf_range(-1.0, 1.0) * float(weapon.recoil_yaw_deg))
	get_tree().call_group("npc", "hear_noise", player.global_position, float(weapon.noise_radius))

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
		var d := npc.global_position.distance_to(player.global_position)
		if d < best:
			var to := (npc.global_position - player.global_position)
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
	npc.take_down()
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

## Called by the level when a guard fires at the player.
func incoming_shot(from: Vector3, to: Vector3, hit: bool, dmg: float) -> void:
	tracer(from, to)
	Game.play_3d("shot_far", from, -4, 10.0, randf_range(0.9, 1.1))
	if hit:
		hurt.emit(dmg)
	else:
		Game.play_3d("hit", to, -10, 3.0, randf_range(1.1, 1.5))
