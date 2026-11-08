//! `BikeController`: the Kestrel Shikra 250 [INVENTED], a mid-80s two-stroke.
//! Its own RigidBody3D, not a car with two wheels:
//!
//! - Two suspension rays; drive at the rear, brakes on both.
//! - The body stays upright through a stabilizer torque. The lean is visual only
//!   (the "Visual" child), so it cannot fall over, and it steers by yaw rate.
//! - A narrow powerband: below `band_start` it bogs, then it comes on the pipe
//!   within `band_snap` of revs. The gearbox shifts itself.
//! - Ridden in first person from the saddle ("RiderCam" under "Visual"): there
//!   is no rider animation to look at. The lean rolls the rider with the bike.
//! - Hard hits throw the rider off and it falls over; hull damage limps the
//!   engine and then kills it (`core::crash`).
//! - One looped ring-ding sample (SfxBank) pitched by RPM; blue smoke on throttle.
//! - The same `ai_*` inputs drive Avekṣā's pursuit bikes.
//!
//! The scene provides Node3Ds "WheelF", "WheelR" (rest positions are the
//! suspension anchors), "Visual", optionally "Smoke", and a CollisionShape3D.

use godot::classes::rigid_body_3d::CenterOfMassMode;
use godot::classes::input::MouseMode;
use godot::classes::{
    AudioStream, AudioStreamPlayer3D, Camera3D, IRigidBody3D, Input, InputEvent, InputEventMouseMotion, Node, Node3D,
    RayCast3D, RigidBody3D,
};
use godot::prelude::*;

use magadha_core::crash::{assess, CrashOutcome, Hull, Tyre, Vehicle as CrashVehicle};
use magadha_core::tuning::{BikeTuning, CameraTuning};

use crate::impact::ImpactSensor;
use crate::npc::Npc;
use crate::player::{LAYER_NPC, LAYER_PLAYER, LAYER_VEHICLE, LAYER_WORLD};
use crate::world::world;

struct Wheel {
    anchor: Vector3,
    ray: Gd<RayCast3D>,
    node: Option<Gd<Node3D>>,
    compression: f32,
    contact: bool,
    spin: f32,
    normal: Vector3,
    tyre: Tyre,
}

#[derive(GodotClass)]
#[class(base = RigidBody3D)]
pub struct BikeController {
    wheels: Vec<Wheel>,
    visual: Option<Gd<Node3D>>,
    smoke: Option<Gd<Node>>,
    camera: Option<Gd<Camera3D>>,
    audio: Option<Gd<AudioStreamPlayer3D>>,
    throttle: f32,
    brake: f32,
    steer: f32,
    rpm: f32,
    gear: i32,
    shift_t: f32,
    on_pipe: f32,
    lean: f32,
    lift: f32,
    idle_t: f32,
    wobble_t: f32,
    cam_yaw: f32,
    cam_pitch: f32,
    cam_look_t: f32,
    sensor: ImpactSensor,
    hull: Hull,
    /// On its side after a crash: no stabilizer, no engine, until remounted.
    fallen: bool,

    /// Weapon up: the view stays where it was put.
    #[var]
    hold_look: bool,

    /// True while the player is riding.
    #[var]
    driver_active: bool,
    /// Pursuit rider: reads `ai_*` instead of the keyboard.
    #[var]
    ai_active: bool,
    #[var]
    ai_throttle: f32,
    #[var]
    ai_steer: f32,
    #[var]
    ai_brake: f32,
    /// Top speed for a pursuit rider (0 = the bike's own).
    #[var]
    ai_max_speed: f32,
    #[var]
    debug_text: GString,

    base: Base<RigidBody3D>,
}

fn smoothstep(a: f32, b: f32, x: f32) -> f32 {
    let t = ((x - a) / (b - a).max(1e-4)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[godot_api]
impl IRigidBody3D for BikeController {
    fn init(base: Base<RigidBody3D>) -> Self {
        Self {
            wheels: vec![],
            visual: None,
            smoke: None,
            camera: None,
            audio: None,
            throttle: 0.0,
            brake: 0.0,
            steer: 0.0,
            rpm: 1600.0,
            gear: 1,
            shift_t: 0.0,
            on_pipe: 0.0,
            lean: 0.0,
            lift: 0.0,
            idle_t: 0.0,
            wobble_t: 0.0,
            cam_yaw: 0.0,
            cam_pitch: 0.0,
            cam_look_t: 0.0,
            sensor: ImpactSensor::default(),
            hull: Hull::new(70.0),
            fallen: false,
            hold_look: false,
            driver_active: false,
            ai_active: false,
            ai_throttle: 0.0,
            ai_steer: 0.0,
            ai_brake: 0.0,
            ai_max_speed: 0.0,
            debug_text: GString::new(),
            base,
        }
    }

    fn ready(&mut self) {
        let bt = world().tuning.bike.clone();
        self.hull = Hull::new(world().tuning.crash.bike_hull);
        let me = self.to_gd();
        {
            let mut b = self.base_mut();
            b.set_mass(bt.mass);
            b.set_center_of_mass_mode(CenterOfMassMode::CUSTOM);
            b.set_center_of_mass(Vector3::new(0.0, bt.com_height, 0.0));
            b.set_can_sleep(true);
            b.set_angular_damp(1.5);
            b.set_linear_damp(0.02);
            b.set_collision_layer(LAYER_VEHICLE);
            b.set_collision_mask(LAYER_WORLD | LAYER_VEHICLE | LAYER_NPC | LAYER_PLAYER);
            b.set_contact_monitor(true);
            b.set_max_contacts_reported(4);
            b.add_to_group("vehicle");
        }
        for (name, z) in [("WheelF", -0.72f32), ("WheelR", 0.72)] {
            let node = self.base().get_node_or_null(name).and_then(|n| n.try_cast::<Node3D>().ok());
            let anchor = node.as_ref().map(|n| n.get_position()).unwrap_or(Vector3::new(0.0, 0.45, z));
            let mut ray = RayCast3D::new_alloc();
            ray.set_position(anchor);
            ray.set_target_position(Vector3::new(0.0, -(bt.susp_rest + bt.wheel_radius), 0.0));
            ray.set_collision_mask(LAYER_WORLD | LAYER_VEHICLE);
            ray.add_exception(&me);
            ray.set_enabled(true);
            self.base_mut().add_child(&ray);
            self.wheels.push(Wheel { anchor, ray, node, compression: 0.0, contact: false, spin: 0.0, normal: Vector3::UP, tyre: Tyre::default() });
        }
        self.visual = self.base().get_node_or_null("Visual").and_then(|n| n.try_cast::<Node3D>().ok());
        self.smoke = self.base().get_node_or_null("Smoke");

        let mut cam = Camera3D::new_alloc();
        cam.set_name("RiderCam");
        cam.set_near(0.05);
        cam.set_far(900.0);
        if let Some(v) = &mut self.visual { v.add_child(&cam); }
        self.camera = Some(cam);

        let mut player = AudioStreamPlayer3D::new_alloc();
        player.set_unit_size(7.0);
        player.set_max_distance(180.0);
        player.set_volume_db(-5.0);
        self.base_mut().add_child(&player);
        self.audio = Some(player);
    }

    fn input(&mut self, event: Gd<InputEvent>) {
        if !self.driver_active { return; }
        if let Ok(m) = event.try_cast::<InputEventMouseMotion>() {
            if Input::singleton().get_mouse_mode() != MouseMode::CAPTURED { return; }
            let sens = world().tuning.camera.mouse_sensitivity;
            self.cam_yaw = (self.cam_yaw - m.get_relative().x * sens).clamp(-2.4, 2.4);
            self.cam_pitch = (self.cam_pitch - m.get_relative().y * sens).clamp(-1.0, 0.8);
            self.cam_look_t = 1.0;
        }
    }

    fn physics_process(&mut self, delta: f64) {
        let dt = delta as f32;
        let ridden = self.driver_active || self.ai_active;
        if self.fallen && !ridden {
            let xf = self.base().get_global_transform();
            if xf.basis.col_b().y > 0.3 {
                let torque = -xf.basis.col_c() * self.base().get_mass() * 8.0;
                let mut b = self.base_mut();
                b.set_sleeping(false);
                b.apply_torque(torque);
                return;
            }
        }
        if !ridden {
            if self.base().is_sleeping() { return; }
            let at_rest = self.base().get_linear_velocity().length() < 0.08 && self.base().get_angular_velocity().length() < 0.08;
            self.idle_t = if at_rest { self.idle_t + dt } else { 0.0 };
            if self.idle_t > 1.5 {
                self.idle_t = 0.0;
                self.base_mut().set_sleeping(true);
                return;
            }
        }
        if self.fallen { return; }
        let bt = world().tuning.bike.clone();
        self.read_input(dt, &bt);
        self.simulate(dt, &bt);
        self.run_over_check();
        self.check_impact(dt);
    }

    fn process(&mut self, delta: f64) {
        let dt = delta as f32;
        let (bt, ct) = {
            let w = world();
            (w.tuning.bike.clone(), w.tuning.camera.clone())
        };
        self.update_visuals(dt, &bt);
        if self.driver_active {
            self.update_camera(dt, &bt, &ct);
        }
        self.update_audio(&bt);
    }
}

#[godot_api]
impl BikeController {
    #[func]
    fn set_engine_stream(&mut self, stream: Gd<AudioStream>) {
        if let Some(a) = &mut self.audio { a.set_stream(&stream); }
    }

    /// Reports each crash: speed change, injury, whether the rider comes off.
    #[signal]
    fn crashed(delta_v: f32, injury: f32, eject: bool);

    #[func]
    fn shift_origin(&mut self, _delta: Vector3) {}

    /// 0..1: what is left of the structure.
    #[func]
    fn get_hull(&self) -> f32 {
        self.hull.fraction()
    }

    #[func]
    fn tyre_count(&self) -> i64 {
        self.wheels.len() as i64
    }

    #[func]
    fn tyre_pos(&self, i: i64) -> Vector3 {
        let Some(w) = self.wheels.get(i as usize) else { return Vector3::ZERO };
        w.node.as_ref().map(|n| n.get_global_position()).unwrap_or(Vector3::ZERO)
    }

    /// A bullet in tyre `i` (0 front, 1 rear). True if this one punctured it.
    #[func]
    fn shoot_tyre(&mut self, i: i64) -> bool {
        self.base_mut().set_sleeping(false);
        self.idle_t = 0.0;
        self.wheels.get_mut(i as usize).is_some_and(|w| w.tyre.hit())
    }

    #[func]
    fn tyre_pressure(&self, i: i64) -> f32 {
        self.wheels.get(i as usize).map(|w| w.tyre.pressure).unwrap_or(1.0)
    }

    #[func]
    fn flat_tyres(&self) -> i64 {
        self.wheels.iter().filter(|w| w.tyre.punctured).count() as i64
    }

    /// Lost at the impact: where a thrown rider keeps going.
    #[func]
    fn get_impact_velocity(&self) -> Vector3 {
        self.sensor.before
    }

    /// Goes down: the stabilizer lets go and it tumbles to rest.
    #[func]
    fn fall_over(&mut self) {
        self.fallen = true;
        self.throttle = 0.0;
        self.brake = 0.0;
        // The lean was only ever visual: from here the real body tips over.
        self.lean = 0.0;
        self.lift = 0.0;
        if let Some(v) = &mut self.visual { v.set_rotation(Vector3::ZERO); }
        let fwd = self.forward();
        let w = self.base().get_angular_velocity();
        let mut b = self.base_mut();
        b.set_angular_velocity(w + fwd * 3.5 + Vector3::UP * 0.8);
        b.set_angular_damp(1.0);
        // The low centre of mass was there to keep it up.
        b.set_center_of_mass_mode(CenterOfMassMode::AUTO);
        b.set_can_sleep(true);
    }

    #[func]
    fn is_fallen(&self) -> bool {
        self.fallen
    }

    /// Recoil on the rider's head.
    #[func]
    fn view_kick(&mut self, pitch_deg: f32, yaw_deg: f32) {
        self.cam_pitch = (self.cam_pitch + pitch_deg.to_radians()).clamp(-1.0, 0.8);
        self.cam_yaw = (self.cam_yaw + yaw_deg.to_radians()).clamp(-2.4, 2.4);
    }

    #[func]
    fn get_steer_input(&self) -> f32 {
        self.steer
    }

    #[func]
    fn set_driver(&mut self, on: bool) {
        self.driver_active = on;
        self.idle_t = 0.0;
        {
            let mut b = self.base_mut();
            b.set_can_sleep(!on);
            if on { b.set_sleeping(false); }
        }
        if on {
            if self.fallen {
                self.fallen = false;
                self.reset_upright();
            }
            self.cam_yaw = 0.0;
            self.cam_pitch = -0.08;
            if let Some(c) = &mut self.camera { c.make_current(); }
            if let Some(a) = &mut self.audio { if !a.is_playing() { a.play(); } }
        } else {
            self.throttle = 0.0;
            self.brake = 1.0;
            self.steer = 0.0;
            if let Some(a) = &mut self.audio { a.stop(); }
        }
    }

    /// Start or stop the engine for a pursuit rider.
    #[func]
    fn set_ai(&mut self, on: bool) {
        self.ai_active = on;
        {
            let mut b = self.base_mut();
            b.set_can_sleep(!on);
            if on { b.set_sleeping(false); }
        }
        if let Some(a) = &mut self.audio {
            if on && !a.is_playing() { a.play(); }
            if !on { a.stop(); }
        }
    }

    #[func]
    fn get_speed(&self) -> f32 {
        self.base().get_linear_velocity().length()
    }

    #[func]
    fn get_rpm(&self) -> f32 {
        self.rpm
    }

    #[func]
    fn get_gear(&self) -> i32 {
        self.gear
    }

    #[func]
    fn get_throttle(&self) -> f32 {
        self.throttle
    }

    /// 0..1: how far on the pipe.
    #[func]
    fn get_on_pipe(&self) -> f32 {
        self.on_pipe
    }

    #[func]
    fn get_lean(&self) -> f32 {
        self.lean
    }

    #[func]
    fn get_exit_point(&self) -> Vector3 {
        let xf = self.base().get_global_transform();
        xf.origin + xf.basis * Vector3::new(-1.1, 0.3, 0.0)
    }

    #[func]
    fn reset_upright(&mut self) {
        self.sensor.reset(Vector3::ZERO);
        self.fallen = false;
        let p = self.base().get_global_position() + Vector3::new(0.0, 0.8, 0.0);
        let yaw = self.base().get_rotation().y;
        let mut b = self.base_mut();
        b.set_global_transform(Transform3D::new(Basis::from_axis_angle(Vector3::UP, yaw), p));
        b.set_linear_velocity(Vector3::ZERO);
        b.set_angular_velocity(Vector3::ZERO);
    }

    fn forward(&self) -> Vector3 {
        -self.base().get_global_transform().basis.col_c()
    }

    fn read_input(&mut self, dt: f32, bt: &BikeTuning) {
        let (mut thr, mut brk, st) = if self.driver_active {
            let i = Input::singleton();
            (
                i.get_action_strength("move_forward"),
                i.get_action_strength("move_back"),
                i.get_action_strength("move_left") - i.get_action_strength("move_right"),
            )
        } else if self.ai_active {
            (self.ai_throttle.clamp(0.0, 1.0), self.ai_brake.clamp(0.0, 1.0), self.ai_steer.clamp(-1.0, 1.0))
        } else {
            (0.0, 1.0, 0.0)
        };
        let vlong = self.base().get_linear_velocity().dot(self.forward());
        // S brakes while rolling forward, paddles back when nearly stopped.
        if brk > 0.0 && vlong < 0.8 && self.driver_active {
            thr = -brk * (bt.reverse_force / bt.drive_force);
            brk = 0.0;
        }
        self.throttle = thr;
        self.brake = brk;
        self.steer += (st - self.steer) * (1.0 - (-bt.steer_rate * dt).exp());
    }

    fn simulate(&mut self, dt: f32, bt: &BikeTuning) {
        let xf = self.base().get_global_transform();
        let up = xf.basis.col_b();
        let fwd = -xf.basis.col_c();
        let right = xf.basis.col_a();
        let v = self.base().get_linear_velocity();
        let w = self.base().get_angular_velocity();
        let speed = v.length();
        let vlong = v.dot(fwd);
        let ray_len = bt.susp_rest + bt.wheel_radius;
        let top = if self.ai_active && self.ai_max_speed > 0.0 { self.ai_max_speed } else { bt.max_speed };

        // Gearbox: revs within the current gear decide where on the band we are.
        let gears = bt.gears.max(1.0);
        let k = (vlong.abs() / top).clamp(0.0, 1.0);
        let low = (self.gear - 1) as f32 / gears;
        let high = self.gear as f32 / gears;
        let rev = (k / high).clamp(0.0, 1.0);
        self.shift_t = (self.shift_t - dt).max(0.0);
        if rev > 0.97 && self.gear < gears as i32 && self.throttle > 0.0 {
            self.gear += 1;
            self.shift_t = bt.shift_cut;
        } else if self.gear > 1 && k < low * 0.8 {
            self.gear -= 1;
        }
        let pipe = smoothstep(bt.band_start, bt.band_start + bt.band_snap, rev);
        self.on_pipe = pipe;
        let crash = world().tuning.crash.clone();
        let engine = self.hull.engine_factor(&crash);
        for wh in &mut self.wheels { wh.tyre.tick(dt, &crash); }
        let front_tyre = self.wheels.first().map(|w| w.tyre).unwrap_or_default();
        let rear_tyre = self.wheels.get(1).map(|w| w.tyre).unwrap_or_default();
        let band = (bt.below_band + (1.0 - bt.below_band) * pipe) * engine;
        let cut = if self.shift_t > 0.0 { 0.0 } else { 1.0 };
        let limiter = (1.0 - (vlong / top).powi(6)).max(0.0);
        let drive = if self.throttle >= 0.0 {
            self.throttle * bt.drive_force * band * cut * limiter
        } else {
            self.throttle * bt.drive_force
        };

        // Suspension rays.
        let mut contacts = 0;
        let mut ground_up = Vector3::ZERO;
        for i in 0..self.wheels.len() {
            // A flat sits lower: the suspension ray reaches a smaller wheel.
            let ray_len = ray_len - bt.wheel_radius * (1.0 - self.wheels[i].tyre.radius(&crash));
            let point_normal = {
                let wh = &mut self.wheels[i];
                wh.ray.set_target_position(Vector3::new(0.0, -ray_len, 0.0));
                wh.ray.force_raycast_update();
                if wh.ray.is_colliding() { Some((wh.ray.get_collision_point(), wh.ray.get_collision_normal())) } else { None }
            };
            let anchor_g = xf.origin + xf.basis * self.wheels[i].anchor;
            let Some((point, normal)) = point_normal else {
                let wh = &mut self.wheels[i];
                wh.contact = false;
                wh.compression = 0.0;
                continue;
            };
            contacts += 1;
            ground_up += normal;
            let comp = (ray_len - anchor_g.distance_to(point)).clamp(0.0, bt.susp_rest);
            let comp_vel = (comp - self.wheels[i].compression) / dt;
            let f = (comp * bt.susp_spring + comp_vel * bt.susp_damp).max(0.0);
            let is_rear = i == 1;

            // Drive and brakes act through the contact patch, on the slope.
            let along = (fwd - normal * fwd.dot(normal)).normalized_or_zero();
            let mut f_long = if is_rear { drive } else { 0.0 };
            let wheel_mass = bt.mass * 0.5;
            if self.brake > 0.0 {
                let stop = (vlong * wheel_mass / dt).abs();
                f_long -= vlong.signum() * (self.brake * bt.brake_force * 0.5).min(stop);
            } else if self.throttle == 0.0 {
                // Engine braking: a two-stroke has little of it.
                let stop = (vlong * wheel_mass / dt).abs();
                f_long -= vlong.signum() * 60.0f32.min(stop);
            }
            let tyre_grip = self.wheels[i].tyre.grip(&crash);
            let f_long = f_long.clamp(-f * bt.grip * 1.6 * tyre_grip, f * bt.grip * 1.6 * tyre_grip);
            let force = normal * f + along * f_long;
            let r = anchor_g - xf.origin;
            self.base_mut().apply_force_ex(force).position(r).done();

            let wh = &mut self.wheels[i];
            wh.contact = true;
            wh.compression = comp;
            wh.normal = normal;
        }

        // Sideways grip, applied at the centre so it can never roll the bike.
        if contacts > 0 {
            let vlat = v.dot(right);
            let wanted = -vlat * bt.mass * contacts as f32 * 0.5 / dt;
            let load = bt.mass * 21.0 * contacts as f32 * 0.5;
            let mut cap = bt.grip * load * (front_tyre.grip(&crash) + rear_tyre.grip(&crash)) * 0.5;
            if vlat.abs() > bt.slide_at { cap *= 0.8; }
            self.base_mut().apply_central_force(right * wanted.clamp(-cap, cap));
        }

        // Steering: command a yaw rate, fading with speed.
        let inertia = bt.mass * 0.35;
        if contacts > 0 {
            let t = (speed / bt.max_speed).clamp(0.0, 1.0);
            let rate = bt.steer_low + (bt.steer_high - bt.steer_low) * t.sqrt();
            let roll_in = (vlong.abs() / 3.0).clamp(0.0, 1.0) * vlong.signum();
            // A flat front steers badly and shakes the bars at speed.
            self.wobble_t += dt;
            let shake = (1.0 - front_tyre.pressure) * (speed / 30.0).min(1.5) * (self.wobble_t * 11.0).sin() * 0.45;
            let want = self.steer * rate * roll_in * front_tyre.grip(&crash) + shake;
            let yaw_rate = w.dot(up);
            self.base_mut().apply_torque(up * (want - yaw_rate) * bt.yaw_gain * inertia);
        }

        // Upright stabilizer: keep the body square to the ground under it, or to
        // the world in the air.
        let target_up = if contacts > 0 { (ground_up / contacts as f32).normalized_or_zero() } else { Vector3::UP };
        let target_up = if target_up == Vector3::ZERO { Vector3::UP } else { target_up };
        let axis = up.cross(target_up);
        let yaw_part = up * w.dot(up);
        let tilt_rate = w - yaw_part;
        let torque = axis * bt.upright_gain * inertia - tilt_rate * bt.upright_damp * inertia;
        self.base_mut().apply_torque(torque);

        // Drag, and what flat tyres add to it.
        self.base_mut().apply_central_force(-v * speed * bt.drag);
        if contacts > 0 && vlong.abs() > 0.5 {
            let flats = (front_tyre.drag(&crash, vlong) + rear_tyre.drag(&crash, vlong)) * 0.18;
            self.base_mut().apply_central_force(-fwd * vlong.signum() * flats);
        }

        // RPM follows the revs, or free-spins when lifted or stopped.
        let band_rpm = bt.idle_rpm + (bt.max_rpm - bt.idle_rpm) * (0.2 + 0.8 * rev);
        let target = if contacts == 0 || speed < 1.0 {
            bt.idle_rpm + (bt.max_rpm - bt.idle_rpm) * self.throttle.abs() * 0.75
        } else {
            band_rpm
        };
        self.rpm += (target - self.rpm) * (1.0 - (-14.0 * dt).exp());
        let (g, r, p) = (self.gear, self.rpm, self.on_pipe);
        self.debug_text = GString::from(&format!("{:5.1} km/h  gear {}  rpm {:5.0}  pipe {:.2}  contacts {}", speed * 3.6, g, r, p, contacts));
    }

    fn check_impact(&mut self, dt: f32) {
        let v = self.base().get_linear_velocity();
        let touching = self.base().get_contact_count() > 0;
        let Some(dv) = self.sensor.update(v, touching, dt) else { return };
        let t = world().tuning.crash.clone();
        let o = assess(&t, CrashVehicle::Bike, dv);
        if o == CrashOutcome::default() { return; }
        self.hull.damage(o.hull_loss);
        self.base_mut().emit_signal("crashed", &[dv.to_variant(), o.injury.to_variant(), o.eject.to_variant()]);
    }

    fn run_over_check(&mut self) {
        let speed = self.get_speed();
        if speed < 8.0 { return; }
        let pos = self.base().get_global_position();
        for b in self.base().get_colliding_bodies().iter_shared() {
            if let Ok(mut npc) = b.try_cast::<Npc>() {
                npc.bind_mut().apply_damage(speed * 3.5, pos, false);
            }
        }
    }

    fn update_visuals(&mut self, dt: f32, bt: &BikeTuning) {
        let crash = world().tuning.crash.clone();
        let v = self.base().get_linear_velocity();
        let vlong = v.dot(self.forward());
        let t = (vlong.abs() / 12.0).clamp(0.0, 1.0);
        let target = self.steer * bt.lean_max_deg.to_radians() * t;
        self.lean += (target - self.lean) * (1.0 - (-bt.lean_rate * dt).exp());
        let lift_target = if self.throttle > 0.3 && self.gear <= 2 { self.on_pipe * bt.wheelie_deg.to_radians() } else { 0.0 };
        self.lift += (lift_target - self.lift) * (1.0 - (-6.0 * dt).exp());
        let (lean, lift, steer) = (self.lean, self.lift, self.steer);
        if let Some(vis) = &mut self.visual {
            vis.set_rotation(Vector3::new(lift, 0.0, lean));
        }
        for wh in &mut self.wheels {
            let travel = if wh.contact { bt.susp_rest - wh.compression } else { bt.susp_rest };
            wh.spin += vlong / bt.wheel_radius.max(0.05) * dt;
            if let Some(n) = &mut wh.node {
                n.set_position(wh.anchor - Vector3::new(0.0, travel, 0.0));
                let front = wh.anchor.z < 0.0;
                let yaw = if front { steer * 0.3 } else { 0.0 };
                n.set_basis(Basis::from_axis_angle(Vector3::UP, yaw) * Basis::from_axis_angle(Vector3::RIGHT, -wh.spin));
                let k = wh.tyre.radius(&crash);
                n.set_scale(Vector3::new(1.0, k, k));
            }
        }
        let smoking = (self.driver_active || self.ai_active) && self.throttle > 0.1;
        if let Some(s) = &mut self.smoke { s.set("emitting", &smoking.to_variant()); }
    }

    /// First person, from the saddle. The camera hangs off "Visual", so it
    /// already leans with the bike; rolling part of that back keeps the horizon.
    fn update_camera(&mut self, dt: f32, bt: &BikeTuning, ct: &CameraTuning) {
        let speed = self.get_speed();
        self.cam_look_t -= dt;
        if self.cam_look_t <= 0.0 && !self.hold_look {
            let k = (-ct.car_recenter * dt).exp();
            self.cam_yaw *= k;
            self.cam_pitch = -0.08 + (self.cam_pitch + 0.08) * k;
        }
        let fov = bt.fov + bt.fov_gain * (speed / bt.max_speed).clamp(0.0, 1.0);
        let (yaw, pitch) = (self.cam_yaw, self.cam_pitch);
        let lean = self.lean;
        let lift = self.lift;
        if let Some(c) = &mut self.camera {
            c.set_position(Vector3::new(0.0, bt.eye_height, bt.eye_back));
            // Undo the wheelie too: the rider looks where they are going.
            c.set_rotation(Vector3::new(pitch - lift, yaw, -lean * (1.0 - bt.horizon_roll)));
            c.set_fov(fov);
        }
    }

    fn update_audio(&mut self, bt: &BikeTuning) {
        let on = self.driver_active || self.ai_active;
        let rpm_k = ((self.rpm - bt.idle_rpm) / (bt.max_rpm - bt.idle_rpm)).clamp(0.0, 1.0);
        let load = self.throttle.abs();
        let pipe = self.on_pipe;
        if let Some(a) = &mut self.audio {
            if !on { return; }
            // The sample is recorded around 4000 rpm.
            a.set_pitch_scale((self.rpm / 4000.0).clamp(0.3, 3.2));
            a.set_volume_db(-13.0 + 7.0 * load + 4.0 * pipe + 3.0 * rpm_k);
        }
    }
}
