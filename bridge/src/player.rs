//! `FpsController`: first-person on-foot controller.
//!
//! - Physics at the project tick (120 Hz). Jump presses are buffered from
//!   `input()` so no press between ticks is lost.
//! - Quake-style acceleration/friction curves, limited air control.
//! - Coyote time, jump buffer, step-up, slope handling, crouch, slide, mantle.
//! - Mouse look is applied immediately in `input()`. Never smoothed.
//! - Camera FOV/bob/land-dip are cosmetic and only touch the camera node.
//! Every number comes from `data/tuning.ron` via the shared world.

use godot::classes::{
    CapsuleShape3D, CharacterBody3D, CollisionShape3D, ICharacterBody3D, Input, InputEvent,
    InputEventMouseMotion, KinematicCollision3D, Node3D, Camera3D, PhysicsRayQueryParameters3D,
};
use godot::classes::input::MouseMode;
use godot::prelude::*;

use magadha_core::tuning::{CameraTuning, MovementTuning};

use crate::world::world;

pub const LAYER_WORLD: u32 = 1;
pub const LAYER_PLAYER: u32 = 2;
pub const LAYER_NPC: u32 = 4;
pub const LAYER_VEHICLE: u32 = 8;

struct Mantle {
    from: Vector3,
    to: Vector3,
    t: f32,
}

#[derive(GodotClass)]
#[class(base = CharacterBody3D)]
pub struct FpsController {
    head: Option<Gd<Node3D>>,
    camera: Option<Gd<Camera3D>>,
    shape: Option<Gd<CollisionShape3D>>,
    capsule: Option<Gd<CapsuleShape3D>>,

    yaw: f32,
    pitch: f32,
    jump_buffer: f32,
    coyote: f32,
    crouching: bool,
    crouch_was_held: bool,
    height: f32,
    sliding: bool,
    slide_timer: f32,
    slide_cd: f32,
    mantle: Option<Mantle>,
    was_on_floor: bool,
    prev_vel_y: f32,
    // Camera cosmetics
    bob_phase: f32,
    bob_weight: f32,
    dip: f32,
    dip_vel: f32,
    step_offset: f32,
    roll: f32,
    fov: f32,
    step_dist: f32,

    /// Input and physics run only while enabled (off while driving).
    #[var]
    pub(crate) enabled: bool,
    /// Weapon script sets this while aiming down sights.
    #[var]
    aiming: bool,
    /// Weapon drawn in hand: guards treat an armed stranger as hostile.
    #[var]
    pub(crate) weapon_raised: bool,
    /// Number of restricted zones the player is inside.
    #[var]
    pub(crate) restricted: i32,
    /// 0 dark .. 1 lit; set by lighting zones.
    #[var]
    pub(crate) exposure: f32,
    /// Extra FOV multiplier from the weapon (ADS zoom). 1 = none.
    #[var]
    fov_scale: f32,
    /// Current noise radius in metres (for AI hearing).
    #[var]
    noise_radius: f32,
    /// Grapple anchor while the line is winding the player in.
    grapple: Option<Vector3>,
    grapple_t: f32,
    grapple_stuck: f32,

    base: Base<CharacterBody3D>,
}

#[godot_api]
impl ICharacterBody3D for FpsController {
    fn init(base: Base<CharacterBody3D>) -> Self {
        Self {
            head: None,
            camera: None,
            shape: None,
            capsule: None,
            yaw: 0.0,
            pitch: 0.0,
            jump_buffer: 0.0,
            coyote: 0.0,
            crouching: false,
            crouch_was_held: false,
            height: 1.78,
            sliding: false,
            slide_timer: 0.0,
            slide_cd: 0.0,
            mantle: None,
            was_on_floor: true,
            prev_vel_y: 0.0,
            bob_phase: 0.0,
            bob_weight: 0.0,
            dip: 0.0,
            dip_vel: 0.0,
            step_offset: 0.0,
            roll: 0.0,
            fov: 80.0,
            step_dist: 0.0,
            enabled: true,
            aiming: false,
            weapon_raised: false,
            restricted: 0,
            exposure: 1.0,
            fov_scale: 1.0,
            noise_radius: 0.0,
            grapple: None,
            grapple_t: 0.0,
            grapple_stuck: 0.0,
            base,
        }
    }

    fn ready(&mut self) {
        let mt = world().tuning.movement.clone();
        self.height = mt.stand_height;

        let mut capsule = CapsuleShape3D::new_gd();
        capsule.set_radius(0.32);
        capsule.set_height(self.height);
        let mut shape = CollisionShape3D::new_alloc();
        shape.set_name("Shape");
        shape.set_shape(&capsule);
        shape.set_position(Vector3::new(0.0, self.height / 2.0, 0.0));

        let mut head = Node3D::new_alloc();
        head.set_name("Head");
        head.set_position(Vector3::new(0.0, self.height - mt.eye_below_top, 0.0));
        let mut cam = Camera3D::new_alloc();
        cam.set_name("Camera");
        cam.set_near(0.05);
        cam.set_far(900.0);
        head.add_child(&cam);

        {
            let mut b = self.base_mut();
            b.add_child(&shape);
            b.add_child(&head);
            b.set_collision_layer(LAYER_PLAYER);
            b.set_collision_mask(LAYER_WORLD | LAYER_NPC | LAYER_VEHICLE);
            b.set_floor_max_angle(mt.max_slope_deg.to_radians());
            b.set_floor_snap_length(0.35);
            b.set_floor_constant_speed_enabled(true);
            b.set_floor_stop_on_slope_enabled(true);
            b.set_safe_margin(0.01);
            b.add_to_group("player");
        }
        self.yaw = self.base().get_rotation().y;
        self.head = Some(head);
        self.camera = Some(cam);
        self.shape = Some(shape);
        self.capsule = Some(capsule);
    }

    fn input(&mut self, event: Gd<InputEvent>) {
        if !self.enabled {
            return;
        }
        if let Ok(m) = event.clone().try_cast::<InputEventMouseMotion>() {
            if Input::singleton().get_mouse_mode() != MouseMode::CAPTURED {
                return;
            }
            let sens = world().tuning.camera.mouse_sensitivity * if self.aiming { 0.6 } else { 1.0 };
            let rel = m.get_relative();
            self.add_look(-rel.x * sens, -rel.y * sens);
        } else if event.is_action_pressed("jump") {
            self.jump_buffer = world().tuning.movement.jump_buffer;
        }
    }

    fn physics_process(&mut self, delta: f64) {
        if !self.enabled {
            return;
        }
        let dt = delta as f32;
        let (mt, ct) = {
            let w = world();
            (w.tuning.movement.clone(), w.tuning.camera.clone())
        };
        self.base_mut().set_floor_max_angle(mt.max_slope_deg.to_radians());

        if self.mantle.is_some() {
            self.tick_mantle(dt, &mt);
            return;
        }
        if self.grapple.is_some() {
            self.tick_grapple(dt, &mt);
            return;
        }

        let input = Input::singleton();
        let mv = input.get_vector("move_left", "move_right", "move_forward", "move_back");
        let crouch_held = input.is_action_pressed("crouch");
        let crouch_pressed = crouch_held && !self.crouch_was_held;
        self.crouch_was_held = crouch_held;
        let on_floor = self.base().is_on_floor();
        let mut vel = self.base().get_velocity();
        let mut hvel = Vector3::new(vel.x, 0.0, vel.z);
        let hspeed = hvel.length();

        // Timers.
        self.jump_buffer -= dt;
        self.slide_cd -= dt;
        if on_floor { self.coyote = mt.coyote_time; } else { self.coyote -= dt; }

        // Wish direction from yaw only.
        let basis = Basis::from_axis_angle(Vector3::UP, self.yaw);
        let mut wish = basis * Vector3::new(mv.x, 0.0, mv.y);
        if wish.length_squared() > 1.0 { wish = wish.normalized(); }
        let sprint = input.is_action_pressed("sprint") && mv.y < -0.3 && !self.crouching && !self.aiming;

        // Slide start.
        if crouch_pressed && on_floor && !self.sliding && hspeed > mt.slide_min_speed && self.slide_cd <= 0.0 {
            self.sliding = true;
            self.slide_timer = mt.slide_duration;
            if hspeed > 0.01 { hvel += hvel / hspeed * mt.slide_boost; }
        }
        if self.sliding {
            self.slide_timer -= dt;
            if self.slide_timer <= 0.0 || hvel.length() < mt.crouch_speed || !crouch_held {
                self.sliding = false;
                self.slide_cd = mt.slide_cooldown;
            }
        }

        // Crouch state (can't stand under a ceiling).
        let want_crouch = crouch_held || self.sliding;
        if want_crouch {
            self.crouching = true;
        } else if self.crouching && self.can_stand(&mt) {
            self.crouching = false;
        }
        self.update_height(dt, &mt);

        let wish_speed = if self.crouching && !self.sliding {
            mt.crouch_speed
        } else if sprint {
            mt.sprint_speed
        } else {
            mt.walk_speed
        } * wish.length();
        let wish_dir = if wish.length_squared() > 1e-6 { wish.normalized() } else { Vector3::ZERO };

        if on_floor {
            // Friction.
            let fr = if self.sliding { mt.slide_friction } else { mt.ground_friction };
            let sp = hvel.length();
            if sp > 1e-4 {
                let drop = sp.max(mt.stop_speed) * fr * dt;
                hvel *= ((sp - drop).max(0.0)) / sp;
            }
            if !self.sliding {
                hvel = accelerate(hvel, wish_dir, wish_speed, mt.ground_accel, dt);
            }
        } else {
            hvel = accelerate(hvel, wish_dir, wish_speed.min(mt.air_max_speed), mt.air_accel, dt);
        }

        // Gravity.
        if !on_floor {
            let g = mt.gravity * if vel.y < 0.0 { mt.fall_gravity_mult } else { 1.0 };
            vel.y -= g * dt;
        } else if vel.y < 0.0 {
            vel.y = 0.0;
        }

        // Jump (buffered + coyote).
        let mut jumped = false;
        if self.jump_buffer > 0.0 && self.coyote > 0.0 && !(self.crouching && !self.sliding && !self.can_stand(&mt)) {
            vel.y = mt.jump_velocity;
            self.jump_buffer = 0.0;
            self.coyote = 0.0;
            self.sliding = false;
            jumped = true;
        }

        // Mantle: in the air, holding jump, pushing forward into a ledge.
        if !on_floor && !jumped && input.is_action_pressed("jump") && mv.y < -0.2 && vel.y < 3.0 {
            if self.try_mantle(&mt) {
                return;
            }
        }

        vel.x = hvel.x;
        vel.z = hvel.z;

        // Step-up before sliding along the obstacle.
        if on_floor && !jumped && hvel.length_squared() > 0.01 {
            self.try_step(hvel * dt, &mt);
        }

        self.base_mut().set_velocity(vel);
        self.base_mut().move_and_slide();

        let now_floor = self.base().is_on_floor();
        if now_floor && !self.was_on_floor {
            let impact = (-self.prev_vel_y / 12.0).clamp(0.0, 1.5);
            self.dip_vel -= impact * ct.land_dip * 12.0;
            if impact > 0.25 {
                self.emit_deferred("landed", impact);
            }
        }
        self.was_on_floor = now_floor;
        self.prev_vel_y = self.base().get_velocity().y;

        // Noise for AI.
        let sp = Vector3::new(vel.x, 0.0, vel.z).length();
        self.noise_radius = if !now_floor || sp < 0.5 {
            0.0
        } else if self.crouching && !self.sliding {
            1.5
        } else if sprint {
            11.0
        } else {
            5.0
        };

        // Footsteps.
        if now_floor && sp > 0.5 && !self.sliding {
            self.step_dist += sp * dt;
            let stride = if sprint { 2.1 } else if self.crouching { 1.1 } else { 1.6 };
            if self.step_dist > stride {
                self.step_dist = 0.0;
                let loud = if sprint { 1.0 } else if self.crouching { 0.25 } else { 0.55 };
                self.emit_deferred("footstep", loud);
            }
        }
    }

    fn process(&mut self, delta: f64) {
        if !self.enabled {
            return;
        }
        let dt = delta as f32;
        let (mt, ct) = {
            let w = world();
            (w.tuning.movement.clone(), w.tuning.camera.clone())
        };
        self.update_camera(dt, &mt, &ct);
    }
}

fn accelerate(vel: Vector3, dir: Vector3, wish_speed: f32, accel: f32, dt: f32) -> Vector3 {
    if dir == Vector3::ZERO { return vel; }
    let current = vel.dot(dir);
    let add = wish_speed - current;
    if add <= 0.0 { return vel; }
    let a = (accel * wish_speed.max(1.0) * dt).min(add);
    vel + dir * a
}

#[godot_api]
impl FpsController {
    #[signal]
    fn footstep(loudness: f32);
    #[signal]
    fn landed(impact: f32);

    fn emit_deferred(&mut self, sig: &str, v: f32) {
        self.base_mut().call_deferred("emit_signal", &[sig.to_variant(), v.to_variant()]);
    }

    fn add_look(&mut self, dyaw: f32, dpitch: f32) {
        self.yaw += dyaw;
        self.pitch = (self.pitch + dpitch).clamp(-1.53, 1.53);
        let yaw = self.yaw;
        self.base_mut().set_rotation(Vector3::new(0.0, yaw, 0.0));
        let pitch = self.pitch;
        if let Some(h) = &mut self.head {
            let r = h.get_rotation();
            h.set_rotation(Vector3::new(pitch, r.y, r.z));
        }
    }

    /// Weapon recoil: an instant kick, not a smoothing filter.
    #[func]
    fn apply_recoil(&mut self, pitch_deg: f32, yaw_deg: f32) {
        self.add_look(yaw_deg.to_radians(), pitch_deg.to_radians());
    }

    /// Grapple: wind the player toward `anchor` until close, stuck, or jump.
    #[func]
    fn start_grapple(&mut self, anchor: Vector3) {
        self.grapple = Some(anchor);
        self.grapple_t = 0.0;
        self.grapple_stuck = 0.0;
        self.sliding = false;
        self.mantle = None;
    }

    #[func]
    fn stop_grapple(&mut self) {
        self.grapple = None;
    }

    #[func]
    fn is_grappling(&self) -> bool {
        self.grapple.is_some()
    }

    #[func]
    fn get_camera(&self) -> Option<Gd<Camera3D>> {
        self.camera.clone()
    }

    #[func]
    fn get_head(&self) -> Option<Gd<Node3D>> {
        self.head.clone()
    }

    #[func]
    pub(crate) fn is_crouching(&self) -> bool {
        self.crouching
    }

    #[func]
    fn is_sliding(&self) -> bool {
        self.sliding
    }

    #[func]
    fn is_mantling(&self) -> bool {
        self.mantle.is_some()
    }

    #[func]
    pub(crate) fn get_horizontal_speed(&self) -> f32 {
        let v = self.base().get_velocity();
        Vector3::new(v.x, 0.0, v.z).length()
    }

    #[func]
    fn get_eye_position(&self) -> Vector3 {
        self.head.as_ref().map(|h| h.get_global_position()).unwrap_or(self.base().get_global_position())
    }

    #[func]
    fn get_look_dir(&self) -> Vector3 {
        self.camera.as_ref().map(|c| -c.get_global_transform().basis.col_c()).unwrap_or(Vector3::FORWARD)
    }

    /// Trespassing, armed, or alarm raised: guards treat a sighting as hostile.
    #[func]
    pub(crate) fn is_hostile_to_guards(&self) -> bool {
        self.restricted > 0 || self.weapon_raised || world().alarm
    }

    #[func]
    fn enter_restricted(&mut self) {
        self.restricted += 1;
    }

    #[func]
    fn exit_restricted(&mut self) {
        self.restricted = (self.restricted - 1).max(0);
    }

    #[func]
    fn set_look(&mut self, yaw: f32, pitch: f32) {
        self.yaw = yaw;
        self.pitch = 0.0;
        self.add_look(0.0, pitch);
    }

    #[func]
    fn get_yaw(&self) -> f32 {
        self.yaw
    }

    #[func]
    fn set_active(&mut self, on: bool) {
        self.enabled = on;
        self.base_mut().set_velocity(Vector3::ZERO);
        let mut b = self.base_mut();
        b.set_process(on);
        b.set_visible(on);
        b.set_collision_layer(if on { LAYER_PLAYER } else { 0 });
        b.set_collision_mask(if on { LAYER_WORLD | LAYER_NPC | LAYER_VEHICLE } else { 0 });
        drop(b);
        if on {
            if let Some(c) = &mut self.camera { c.make_current(); }
        }
    }

    // ---- internals --------------------------------------------------------

    fn can_stand(&mut self, mt: &MovementTuning) -> bool {
        let extra = mt.stand_height - self.height;
        if extra <= 0.01 { return true; }
        let xf = self.base().get_global_transform();
        !self.base_mut().test_move(xf, Vector3::new(0.0, extra, 0.0))
    }

    fn update_height(&mut self, dt: f32, mt: &MovementTuning) {
        let target = if self.crouching { mt.crouch_height } else { mt.stand_height };
        if (self.height - target).abs() < 1e-3 { return; }
        let old = self.height;
        self.height += (target - self.height) * (1.0 - (-mt.crouch_rate * dt).exp());
        if (self.height - target).abs() < 0.005 { self.height = target; }
        let h = self.height;
        if let Some(c) = &mut self.capsule { c.set_height(h); }
        if let Some(s) = &mut self.shape { s.set_position(Vector3::new(0.0, h / 2.0, 0.0)); }
        // Crouching mid-air tucks the legs up instead of lowering the head.
        if !self.base().is_on_floor() && h < old {
            let mut p = self.base().get_global_position();
            p.y += old - h;
            self.base_mut().set_global_position(p);
            self.step_offset -= old - h;
        }
    }

    fn try_step(&mut self, motion: Vector3, mt: &MovementTuning) {
        let xf = self.base().get_global_transform();
        if !self.base_mut().test_move(xf, motion) { return; }
        let up = Vector3::new(0.0, mt.step_height, 0.0);
        if self.base_mut().test_move(xf, up) { return; }
        let xf_up = Transform3D::new(xf.basis, xf.origin + up);
        // Look a bit further ahead so thin step lips register.
        let probe = motion.normalized() * motion.length().max(0.08);
        if self.base_mut().test_move(xf_up, probe) { return; }
        let xf_f = Transform3D::new(xf.basis, xf_up.origin + probe);
        let col = KinematicCollision3D::new_gd();
        let hit = self.base_mut().test_move_ex(xf_f, -up).collision(&col).done();
        if !hit { return; }
        if col.get_normal().y < mt.max_slope_deg.to_radians().cos() { return; }
        let travel = col.get_travel();
        let dy = mt.step_height + travel.y;
        if dy <= 0.02 { return; }
        let mut p = self.base().get_global_position();
        p.y += dy + 0.01;
        p += motion;
        self.base_mut().set_global_position(p);
        self.step_offset -= dy;
    }

    fn try_mantle(&mut self, mt: &MovementTuning) -> bool {
        let Some(mut space) = self.base().get_world_3d().and_then(|w| w.get_direct_space_state()) else { return false };
        let pos = self.base().get_global_position();
        let fwd = Basis::from_axis_angle(Vector3::UP, self.yaw) * Vector3::FORWARD;
        // 1. Wall in front of the chest.
        let from = pos + Vector3::new(0.0, 0.9, 0.0);
        let Some(mut q) = PhysicsRayQueryParameters3D::create(from, from + fwd * mt.mantle_reach) else { return false };
        q.set_collision_mask(LAYER_WORLD | LAYER_VEHICLE);
        let hit = space.intersect_ray(&q);
        if hit.is_empty() { return false; }
        let n: Vector3 = hit.get("normal").map(|v| v.to()).unwrap_or(Vector3::UP);
        if n.y.abs() > 0.3 { return false; }
        let wall: Vector3 = hit.get("position").map(|v| v.to()).unwrap_or(from);
        // 2. Find the top of the ledge.
        let top_from = Vector3::new(wall.x, pos.y + mt.mantle_height + 0.15, wall.z) + fwd * 0.35;
        let top_to = Vector3::new(top_from.x, pos.y + 0.3, top_from.z);
        let Some(mut q2) = PhysicsRayQueryParameters3D::create(top_from, top_to) else { return false };
        q2.set_collision_mask(LAYER_WORLD | LAYER_VEHICLE);
        let top = space.intersect_ray(&q2);
        if top.is_empty() { return false; }
        let tn: Vector3 = top.get("normal").map(|v| v.to()).unwrap_or(Vector3::ZERO);
        if tn.y < 0.7 { return false; }
        let tp: Vector3 = top.get("position").map(|v| v.to()).unwrap_or(top_from);
        let rise = tp.y - pos.y;
        if rise < 0.3 || rise > mt.mantle_height { return false; }
        // 3. Room to stand (at least crouched) on top.
        let target = Vector3::new(tp.x, tp.y + 0.02, tp.z);
        let txf = Transform3D::new(self.base().get_global_transform().basis, target);
        if self.base_mut().test_move(txf, Vector3::new(0.0, 0.05, 0.0)) {
            return false;
        }
        self.mantle = Some(Mantle { from: pos, to: target, t: 0.0 });
        self.base_mut().set_velocity(Vector3::ZERO);
        true
    }

    fn tick_grapple(&mut self, dt: f32, mt: &MovementTuning) {
        let Some(anchor) = self.grapple else { return };
        self.grapple_t += dt;
        let pos = self.base().get_global_position() + Vector3::new(0.0, 1.0, 0.0);
        let to = anchor - pos;
        let dist = to.length();
        let dir = if dist > 1e-3 { to / dist } else { Vector3::ZERO };
        let mut vel = self.base().get_velocity();
        // Reel in: velocity eases toward the line, plus a little lift so the
        // player clears the lip of a roof instead of hanging under it.
        let reel = 24.0;
        let want = dir * reel + Vector3::new(0.0, 1.2, 0.0);
        vel = vel.lerp(want, (1.0 - (-7.0 * dt).exp()).min(1.0));
        let jump = Input::singleton().is_action_just_pressed("jump");
        let release = dist < 1.4 || jump || self.grapple_t > 3.5;
        if release {
            self.grapple = None;
            // Pop over the edge on arrival; keep momentum on a jump release.
            vel = if jump { vel + Vector3::new(0.0, mt.jump_velocity * 0.8, 0.0) } else { dir * 4.0 + Vector3::new(0.0, mt.jump_velocity * 0.9, 0.0) };
        }
        self.base_mut().set_velocity(vel);
        self.base_mut().move_and_slide();
        let moved = self.base().get_real_velocity().length();
        if moved < 1.5 && self.grapple_t > 0.25 {
            self.grapple_stuck += dt;
            if self.grapple_stuck > 0.3 {
                // Snagged on geometry: let go with a hop.
                self.grapple = None;
                let v = Vector3::new(0.0, mt.jump_velocity, 0.0) + dir * 3.0;
                self.base_mut().set_velocity(v);
            }
        } else {
            self.grapple_stuck = 0.0;
        }
        self.was_on_floor = self.base().is_on_floor();
        self.prev_vel_y = self.base().get_velocity().y;
        self.noise_radius = 4.0;
    }

    fn tick_mantle(&mut self, dt: f32, mt: &MovementTuning) {
        let Some(m) = &mut self.mantle else { return };
        m.t += dt / mt.mantle_time.max(0.01);
        let t = m.t.min(1.0);
        // Up first, then over.
        let ty = (t / 0.65).min(1.0);
        let ty = 1.0 - (1.0 - ty) * (1.0 - ty);
        let txz = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
        let p = Vector3::new(
            m.from.x + (m.to.x - m.from.x) * txz,
            m.from.y + (m.to.y - m.from.y) * ty,
            m.from.z + (m.to.z - m.from.z) * txz,
        );
        let done = m.t >= 1.0;
        self.base_mut().set_global_position(p);
        if done {
            self.mantle = None;
            let fwd = Basis::from_axis_angle(Vector3::UP, self.yaw) * Vector3::FORWARD;
            self.base_mut().set_velocity(fwd * 2.0);
            self.dip_vel -= 0.4;
        }
    }

    fn update_camera(&mut self, dt: f32, mt: &MovementTuning, ct: &CameraTuning) {
        let speed = self.get_horizontal_speed();
        let on_floor = self.base().is_on_floor();

        // FOV with speed (subtle), times ADS scale.
        let k = ((speed - mt.walk_speed) / (mt.sprint_speed - mt.walk_speed).max(0.1)).clamp(0.0, 1.0);
        let target_fov = if self.aiming { ct.ads_fov } else { ct.fov_base + ct.fov_speed_gain * k };
        self.fov += (target_fov - self.fov) * (1.0 - (-ct.fov_rate * dt).exp());

        // Head-bob by distance travelled, faded in/out.
        let bobbing = on_floor && speed > 0.5 && !self.sliding;
        let w_target = if bobbing { (speed / mt.sprint_speed).min(1.0) } else { 0.0 };
        self.bob_weight += (w_target - self.bob_weight) * (1.0 - (-8.0 * dt).exp());
        self.bob_phase += speed * dt * ct.bob_frequency * std::f32::consts::TAU;
        let bob_amt = ct.bob_amount * if self.aiming { 0.25 } else { 1.0 };
        let bob_y = self.bob_phase.sin().abs() * bob_amt * self.bob_weight;
        let bob_x = (self.bob_phase * 0.5).sin() * bob_amt * 0.6 * self.bob_weight;

        // Land dip: damped spring back to 0.
        let k_spring = ct.land_recover * ct.land_recover;
        let c_damp = 2.0 * ct.land_recover;
        self.dip_vel += (-k_spring * self.dip - c_damp * self.dip_vel) * dt;
        self.dip += self.dip_vel * dt;
        self.dip = self.dip.clamp(-0.4, 0.2);

        // Step smoothing.
        self.step_offset *= (-ct.step_smooth * dt).exp();
        if self.step_offset.abs() < 1e-3 { self.step_offset = 0.0; }

        // Slide roll.
        let roll_target = if self.sliding { -ct.slide_roll_deg.to_radians() } else { 0.0 };
        self.roll += (roll_target - self.roll) * (1.0 - (-10.0 * dt).exp());

        let eye = self.height - mt.eye_below_top;
        let pitch = self.pitch;
        let roll = self.roll;
        let y = eye + bob_y + self.dip + self.step_offset;
        if let Some(h) = &mut self.head {
            h.set_position(Vector3::new(bob_x, y, 0.0));
            h.set_rotation(Vector3::new(pitch, 0.0, roll));
        }
        let fov = self.fov * self.fov_scale;
        if let Some(c) = &mut self.camera { c.set_fov(fov); }
    }
}
