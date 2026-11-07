//! `ArcadeCar`: custom RigidBody3D car. Fun first, simulation second.
//!
//! - Raycast suspension per wheel (spring + damper), anti-roll bars.
//! - Lateral grip from a slip-angle curve with a peak and falloff, clamped by
//!   a friction circle shared with drive/brake force. Handbrake drops rear grip.
//! - Speed-sensitive steering, automatic counter-steer in slides, yaw damping.
//! - Self-righting torque so small bumps never flip it.
//! - Chase camera (spring arm with collision), FOV with speed, look-ahead,
//!   rough-surface shake, quick recenter after mouse look.
//! - Engine / tyre / wind / thump audio synthesised live (no samples).
//!
//! The scene provides child Node3Ds named WheelFL, WheelFR, WheelRL, WheelRR
//! (their rest positions are the suspension anchors) and a CollisionShape3D.

use godot::classes::rigid_body_3d::CenterOfMassMode;
use godot::classes::{
    AudioStreamGenerator, AudioStreamGeneratorPlayback, AudioStreamPlayer3D, Camera3D, IRigidBody3D,
    Input, InputEvent, InputEventMouseMotion, Node3D, PhysicsRayQueryParameters3D, RayCast3D, RigidBody3D,
};
use godot::classes::input::MouseMode;
use godot::prelude::*;

use magadha_core::rng::Rng;
use magadha_core::tuning::{CameraTuning, VehicleTuning};

use crate::npc::Npc;
use crate::player::{LAYER_NPC, LAYER_PLAYER, LAYER_VEHICLE, LAYER_WORLD};
use crate::world::world;

const WHEELS: [&str; 4] = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"];
const AUDIO_RATE: f32 = 22050.0;

struct Wheel {
    anchor: Vector3,
    front: bool,
    left: bool,
    ray: Gd<RayCast3D>,
    node: Option<Gd<Node3D>>,
    compression: f32,
    contact: bool,
    spin: f32,
    slip: f32,
    load: f32,
}

#[derive(Default)]
struct Synth {
    phase: f32,
    phase2: f32,
    squeal_phase: f32,
    lp_engine: f32,
    lp_wind: f32,
    lp_squeal: f32,
    thump: f32,
    thump_phase: f32,
}

#[derive(GodotClass)]
#[class(base = RigidBody3D)]
pub struct ArcadeCar {
    wheels: Vec<Wheel>,
    steer: f32,
    throttle: f32,
    brake: f32,
    handbrake: bool,
    rpm: f32,
    gear: i32,
    rough: f32,
    upside_timer: f32,
    // Camera
    camera: Option<Gd<Camera3D>>,
    cam_pos: Vector3,
    cam_yaw_offset: f32,
    cam_look_timer: f32,
    cam_lookahead: f32,
    shake_t: f32,
    // Audio
    audio: Option<Gd<AudioStreamPlayer3D>>,
    playback: Option<Gd<AudioStreamGeneratorPlayback>>,
    synth: Synth,
    rng: Rng,
    audio_slip: f32,
    audio_load: f32,
    buf: Vec<Vector2>,

    /// True while the player is driving.
    #[var]
    driver_active: bool,
    /// Seconds a driverless car has been at rest; past a beat it is put to
    /// sleep and skipped entirely, so parked cars cost nothing.
    idle_t: f32,
    /// Raw debug values for the tuning panel overlay.
    #[var]
    debug_text: GString,

    base: Base<RigidBody3D>,
}

#[godot_api]
impl IRigidBody3D for ArcadeCar {
    fn init(base: Base<RigidBody3D>) -> Self {
        Self {
            wheels: vec![],
            steer: 0.0,
            throttle: 0.0,
            brake: 0.0,
            handbrake: false,
            rpm: 900.0,
            gear: 1,
            rough: 0.0,
            upside_timer: 0.0,
            camera: None,
            cam_pos: Vector3::ZERO,
            cam_yaw_offset: 0.0,
            cam_look_timer: 0.0,
            cam_lookahead: 0.0,
            shake_t: 0.0,
            audio: None,
            playback: None,
            synth: Synth::default(),
            rng: Rng::new(77),
            audio_slip: 0.0,
            audio_load: 0.0,
            buf: Vec::with_capacity(4096),
            driver_active: false,
            idle_t: 0.0,
            debug_text: GString::new(),
            base,
        }
    }

    fn ready(&mut self) {
        let vt = world().tuning.vehicle.clone();
        let self_gd = self.to_gd();
        {
            let mut b = self.base_mut();
            b.set_mass(vt.mass);
            b.set_center_of_mass_mode(CenterOfMassMode::CUSTOM);
            b.set_center_of_mass(Vector3::new(0.0, vt.com_height, 0.0));
            b.set_can_sleep(true);
            b.set_angular_damp(0.6);
            b.set_linear_damp(0.02);
            b.set_collision_layer(LAYER_VEHICLE);
            b.set_collision_mask(LAYER_WORLD | LAYER_VEHICLE | LAYER_NPC | LAYER_PLAYER);
            b.set_contact_monitor(true);
            b.set_max_contacts_reported(4);
            b.add_to_group("vehicle");
        }
        for (i, name) in WHEELS.iter().enumerate() {
            let node = self.base().get_node_or_null(*name).and_then(|n| n.try_cast::<Node3D>().ok());
            let anchor = node.as_ref().map(|n| n.get_position()).unwrap_or(Vector3::new(
                if i % 2 == 0 { -0.8 } else { 0.8 },
                0.0,
                if i < 2 { -1.3 } else { 1.3 },
            ));
            let mut ray = RayCast3D::new_alloc();
            ray.set_position(anchor);
            ray.set_target_position(Vector3::new(0.0, -(vt.susp_rest + vt.wheel_radius), 0.0));
            ray.set_collision_mask(LAYER_WORLD | LAYER_VEHICLE);
            ray.add_exception(&self_gd);
            ray.set_enabled(true);
            self.base_mut().add_child(&ray);
            self.wheels.push(Wheel {
                anchor,
                front: i < 2,
                left: i % 2 == 0,
                ray,
                node,
                compression: 0.0,
                contact: false,
                spin: 0.0,
                slip: 0.0,
                load: 0.0,
            });
        }

        // Chase camera lives outside the body transform.
        let mut cam = Camera3D::new_alloc();
        cam.set_name("ChaseCam");
        cam.set_as_top_level(true);
        cam.set_near(0.08);
        cam.set_far(900.0);
        self.base_mut().add_child(&cam);
        self.cam_pos = self.base().get_global_position() + Vector3::new(0.0, 2.0, 6.0);
        self.camera = Some(cam);

        // Engine audio stream.
        let mut gen = AudioStreamGenerator::new_gd();
        gen.set_mix_rate(AUDIO_RATE);
        gen.set_buffer_length(0.12);
        let mut player = AudioStreamPlayer3D::new_alloc();
        player.set_stream(&gen);
        player.set_unit_size(8.0);
        player.set_max_distance(70.0);
        player.set_volume_db(-4.0);
        self.base_mut().add_child(&player);
        self.audio = Some(player);
    }

    fn input(&mut self, event: Gd<InputEvent>) {
        if !self.driver_active { return; }
        if let Ok(m) = event.try_cast::<InputEventMouseMotion>() {
            if Input::singleton().get_mouse_mode() != MouseMode::CAPTURED { return; }
            let sens = world().tuning.camera.mouse_sensitivity;
            self.cam_yaw_offset = (self.cam_yaw_offset - m.get_relative().x * sens).clamp(-2.6, 2.6);
            self.cam_look_timer = 0.8;
        }
    }

    fn physics_process(&mut self, delta: f64) {
        let dt = delta as f32;
        if !self.driver_active {
            if self.base().is_sleeping() {
                return;
            }
            let at_rest = self.base().get_linear_velocity().length() < 0.08 && self.base().get_angular_velocity().length() < 0.08;
            self.idle_t = if at_rest { self.idle_t + dt } else { 0.0 };
            if self.idle_t > 1.5 {
                self.idle_t = 0.0;
                self.base_mut().set_sleeping(true);
                return;
            }
        }
        let vt = world().tuning.vehicle.clone();
        self.read_input(dt, &vt);
        self.simulate(dt, &vt);
        self.run_over_check();
    }

    fn process(&mut self, delta: f64) {
        let dt = delta as f32;
        let (vt, ct) = {
            let w = world();
            (w.tuning.vehicle.clone(), w.tuning.camera.clone())
        };
        self.update_wheel_visuals(dt, &vt);
        if self.driver_active {
            self.update_camera(dt, &vt, &ct);
        }
        self.update_audio(&vt);
    }
}

#[godot_api]
impl ArcadeCar {
    /// Floating origin: the level moved the whole world by `delta`. The
    /// chase camera smooths in world space, so carry its state along.
    #[func]
    fn shift_origin(&mut self, delta: Vector3) {
        self.cam_pos += delta;
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
            let fwd = self.forward();
            self.cam_pos = self.base().get_global_position() - fwd * 5.0 + Vector3::new(0.0, 2.0, 0.0);
            self.cam_yaw_offset = 0.0;
            if let Some(c) = &mut self.camera { c.make_current(); }
            if let Some(a) = &mut self.audio { if !a.is_playing() { a.play(); } }
            self.playback = self.audio.as_ref()
                .and_then(|a| a.get_stream_playback())
                .and_then(|p| p.try_cast::<AudioStreamGeneratorPlayback>().ok());
        } else {
            self.throttle = 0.0;
            self.brake = 0.0;
            self.steer = 0.0;
            self.handbrake = true;
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

    /// Exit point beside the driver door, in world space.
    /// Current front-wheel steer angle (radians, + = left).
    #[func]
    fn get_steer(&self) -> f32 {
        self.steer
    }

    #[func]
    fn get_throttle(&self) -> f32 {
        self.throttle
    }

    #[func]
    fn get_brake(&self) -> f32 {
        self.brake
    }

    #[func]
    fn get_exit_point(&self) -> Vector3 {
        let xf = self.base().get_global_transform();
        xf.origin + xf.basis * Vector3::new(-1.6, 0.4, -0.2)
    }

    /// Put the car back on its wheels (debug / stuck).
    #[func]
    fn reset_upright(&mut self) {
        let p = self.base().get_global_position() + Vector3::new(0.0, 1.0, 0.0);
        let yaw = self.base().get_rotation().y;
        let mut b = self.base_mut();
        b.set_global_transform(Transform3D::new(Basis::from_axis_angle(Vector3::UP, yaw), p));
        b.set_linear_velocity(Vector3::ZERO);
        b.set_angular_velocity(Vector3::ZERO);
    }

    fn forward(&self) -> Vector3 {
        -self.base().get_global_transform().basis.col_c()
    }

    fn read_input(&mut self, dt: f32, vt: &VehicleTuning) {
        let input = Input::singleton();
        let (mut thr, mut brk, mut st, hb) = (0.0, 0.0, 0.0, !self.driver_active);
        if self.driver_active {
            thr = input.get_action_strength("move_forward");
            brk = input.get_action_strength("move_back");
            st = input.get_action_strength("move_left") - input.get_action_strength("move_right");
        }
        let hb = hb || (self.driver_active && input.is_action_pressed("jump"));
        let v = self.base().get_linear_velocity();
        let fwd = self.forward();
        let vlong = v.dot(fwd);
        let speed = v.length();
        // S brakes while rolling forward, reverses when nearly stopped.
        if brk > 0.0 && vlong < 1.0 {
            thr = -brk * (vt.reverse_force / vt.engine_force);
            brk = 0.0;
        }
        self.throttle = thr;
        self.brake = brk;
        self.handbrake = hb;

        let k = (speed / vt.max_speed).clamp(0.0, 1.0);
        let steer_scale = 1.0 + (vt.steer_high_speed - 1.0) * k;
        let mut target = st * vt.steer_max_deg.to_radians() * steer_scale;

        // Counter-steer assist: steer toward the velocity direction in slides.
        if speed > 3.0 && vlong > 0.0 {
            let right = self.base().get_global_transform().basis.col_a();
            let slip = (v.dot(right)).atan2(vlong.abs());
            target += -slip * vt.steer_assist;
        }
        let max = vt.steer_max_deg.to_radians();
        target = target.clamp(-max, max);
        self.steer += (target - self.steer) * (1.0 - (-vt.steer_rate * dt).exp());
    }

    fn simulate(&mut self, dt: f32, vt: &VehicleTuning) {
        let xf = self.base().get_global_transform();
        let up = xf.basis.col_b();
        let v = self.base().get_linear_velocity();
        let w = self.base().get_angular_velocity();
        let com = xf.origin + xf.basis * Vector3::new(0.0, vt.com_height, 0.0);
        let mass = vt.mass;
        let speed = v.length();
        let fwd_body = -xf.basis.col_c();
        let vlong_body = v.dot(fwd_body);

        let ray_len = vt.susp_rest + vt.wheel_radius;
        let mut contacts = 0;
        let mut rough = 0.0;
        let mut slip_total = 0.0;
        let mut load_total = 0.0;
        let mut comps = [0.0f32; 4];

        let drive_total = self.throttle * vt.engine_force * (1.0 - (vlong_body / vt.max_speed).powi(2)).max(0.0);

        for i in 0..self.wheels.len() {
            let (front, left) = (self.wheels[i].front, self.wheels[i].left);
            {
                let wh = &mut self.wheels[i];
                wh.ray.set_target_position(Vector3::new(0.0, -ray_len, 0.0));
                wh.ray.force_raycast_update();
            }
            let anchor_g = xf.origin + xf.basis * self.wheels[i].anchor;
            if !self.wheels[i].ray.is_colliding() {
                let wh = &mut self.wheels[i];
                wh.contact = false;
                wh.compression = 0.0;
                wh.load = 0.0;
                continue;
            }
            contacts += 1;
            let point = self.wheels[i].ray.get_collision_point();
            let normal = self.wheels[i].ray.get_collision_normal();
            let dist = anchor_g.distance_to(point);
            let comp = (ray_len - dist).clamp(0.0, vt.susp_rest);
            let prev = self.wheels[i].compression;
            let comp_vel = (comp - prev) / dt;
            rough += comp_vel.abs();
            comps[i] = comp;

            let f_susp = (comp * vt.susp_spring + comp_vel * vt.susp_damp).max(0.0);
            let load = f_susp;

            // Wheel frame.
            let steer = if front { self.steer } else { 0.0 };
            let wfwd = (Basis::from_axis_angle(up, steer) * fwd_body).normalized();
            let wfwd = (wfwd - normal * wfwd.dot(normal)).normalized();
            let wright = wfwd.cross(normal).normalized();
            let r = point - com;
            let pv = v + w.cross(r);
            let vlong = pv.dot(wfwd);
            let vlat = pv.dot(wright);

            // Grip curve.
            let mut mu = if front { vt.grip_front } else { vt.grip_rear };
            if !front && self.handbrake { mu *= vt.handbrake_grip; }
            let slip_angle = vlat.abs().atan2(vlong.abs() + 0.5);
            let peak = vt.slip_peak_deg.to_radians();
            let curve = if slip_angle < peak {
                slip_angle / peak
            } else {
                let t = ((slip_angle - peak) / (peak * 3.0)).min(1.0);
                1.0 + (vt.grip_falloff - 1.0) * t
            };
            let max_f = mu * load;
            // Cancel lateral velocity, limited by the grip curve.
            let wheel_mass = mass / 4.0;
            let f_lat_wanted = -vlat * wheel_mass / dt;
            let lat_cap = max_f * curve.max(0.25);
            let mut f_lat = f_lat_wanted.clamp(-lat_cap, lat_cap);

            // Longitudinal: drive split, brakes, handbrake lock.
            let bias = if front { 1.0 - vt.rear_drive_bias } else { vt.rear_drive_bias };
            let mut f_long = drive_total * bias / 2.0;
            let mut brake = self.brake * vt.brake_force / 4.0;
            if self.handbrake && !front { brake += vt.brake_force * 0.6 / 2.0; }
            if brake > 0.0 {
                let stop = (vlong * wheel_mass / dt).abs();
                f_long -= vlong.signum() * brake.min(stop);
            }
            if self.throttle == 0.0 && brake == 0.0 {
                // Rolling resistance / engine braking.
                let stop = (vlong * wheel_mass / dt).abs();
                f_long -= vlong.signum() * (vt.rolling_resistance + 120.0).min(stop);
            }

            // Friction circle. Longitudinal force (drive or brake) is served
            // first; lateral grip gets what is left. Scaling both together let
            // tiny lateral jitter (huge f_lat_wanted at 120 Hz) eat the whole
            // budget and the car barely accelerated.
            f_long = f_long.clamp(-max_f, max_f);
            let lat_budget = (max_f * max_f - (f_long * 0.75) * (f_long * 0.75)).max(0.0).sqrt();
            f_lat = f_lat.clamp(-lat_budget, lat_budget);
            let lat_slip = ((f_lat_wanted.abs() - lat_cap).max(0.0) / (wheel_mass * 10.0)).min(1.0);
            slip_total += lat_slip + if self.handbrake && !front && speed > 3.0 { 0.4 } else { 0.0 };
            load_total += load;

            let force = normal * f_susp + wright * f_lat + wfwd * f_long;
            self.base_mut().apply_force_ex(force).position(point - xf.origin).done();

            let wh = &mut self.wheels[i];
            wh.contact = true;
            wh.compression = comp;
            wh.slip = lat_slip;
            wh.load = load;
            let _ = left;
        }

        // Anti-roll bars.
        for (l, r) in [(0usize, 1usize), (2, 3)] {
            if l >= self.wheels.len() || r >= self.wheels.len() { continue; }
            let diff = comps[l] - comps[r];
            let f = diff * vt.anti_roll;
            if self.wheels[l].contact {
                let p = xf.basis * self.wheels[l].anchor;
                self.base_mut().apply_force_ex(-up * f).position(p).done();
            }
            if self.wheels[r].contact {
                let p = xf.basis * self.wheels[r].anchor;
                self.base_mut().apply_force_ex(up * f).position(p).done();
            }
        }

        // Aero.
        let drag = -v * speed * vt.drag;
        let mut b = self.base_mut();
        b.apply_central_force(drag);
        if contacts > 0 {
            b.apply_central_force(-up * vt.downforce * speed * speed);
        }

        // Yaw damping when not steering hard (keeps it planted, still drifts).
        let yaw_rate = w.dot(up);
        b.apply_torque(-up * yaw_rate * vt.yaw_damping * mass);

        // Self-righting: in the air, or tilted beyond 35 degrees.
        let tilt = up.dot(Vector3::UP);
        if contacts < 2 || tilt < 0.82 {
            let axis = up.cross(Vector3::UP);
            b.apply_torque(axis * vt.air_righting * mass);
            // Damp roll/pitch spin in the air.
            let spin = w - up * yaw_rate;
            b.apply_torque(-spin * mass * 0.3);
        }
        drop(b);

        // Upside down and stuck for 2 s: reset.
        if tilt < 0.2 && speed < 2.0 {
            self.upside_timer += dt;
            if self.upside_timer > 2.0 {
                self.upside_timer = 0.0;
                self.reset_upright();
            }
        } else {
            self.upside_timer = 0.0;
        }

        self.rough += (rough * 0.02 - self.rough) * (1.0 - (-6.0 * dt).exp());
        self.audio_slip += ((slip_total * 0.5).min(1.0) - self.audio_slip) * (1.0 - (-12.0 * dt).exp());
        self.audio_load = self.throttle.abs();
        if rough > 6.0 { self.synth.thump = (rough * 0.03).min(1.0); }
        let _ = load_total;

        // Fake gearbox for RPM and audio.
        let gears = vt.gears.max(1.0);
        let k = (vlong_body.abs() / vt.max_speed).clamp(0.0, 1.0);
        let g = ((k * gears).floor() as i32 + 1).min(gears as i32);
        let in_gear = (k * gears - (g - 1) as f32).clamp(0.0, 1.0);
        let target_rpm = vt.idle_rpm + (vt.max_rpm - vt.idle_rpm) * (0.25 + 0.75 * in_gear).min(1.0)
            * if contacts == 0 { 1.0 } else { 0.6 + 0.4 * self.throttle.abs().max(k) };
        let target_rpm = if speed < 0.5 && self.throttle == 0.0 { vt.idle_rpm } else { target_rpm };
        self.gear = if vlong_body < -0.5 { -1 } else { g };
        self.rpm += (target_rpm - self.rpm) * (1.0 - (-8.0 * dt).exp());

        let gs = self.gear;
        self.debug_text = GString::from(&format!(
            "{:5.1} km/h  gear {}  rpm {:4.0}  slip {:.2}  contacts {}",
            speed * 3.6, gs, self.rpm, self.audio_slip, contacts
        ));
    }

    fn run_over_check(&mut self) {
        let speed = self.get_speed();
        if speed < 7.0 { return; }
        let bodies = self.base().get_colliding_bodies();
        for b in bodies.iter_shared() {
            if let Ok(mut npc) = b.try_cast::<Npc>() {
                let pos = self.base().get_global_position();
                npc.bind_mut().apply_damage(speed * 9.0, pos, false);
            }
        }
    }

    fn update_wheel_visuals(&mut self, dt: f32, vt: &VehicleTuning) {
        let fwd = self.forward();
        let v = self.base().get_linear_velocity();
        let vlong = v.dot(fwd);
        let steer = self.steer;
        for wh in &mut self.wheels {
            let travel = if wh.contact { vt.susp_rest - wh.compression } else { vt.susp_rest };
            wh.spin += vlong / vt.wheel_radius.max(0.05) * dt;
            if let Some(n) = &mut wh.node {
                n.set_position(wh.anchor - Vector3::new(0.0, travel, 0.0));
                let yaw = if wh.front { steer } else { 0.0 };
                n.set_basis(Basis::from_axis_angle(Vector3::UP, yaw) * Basis::from_axis_angle(Vector3::RIGHT, -wh.spin));
            }
        }
    }

    fn update_camera(&mut self, dt: f32, vt: &VehicleTuning, ct: &CameraTuning) {
        let xf = self.base().get_global_transform();
        let v = self.base().get_linear_velocity();
        let speed = v.length();
        let fwd = self.forward();
        let flat_fwd = Vector3::new(fwd.x, 0.0, fwd.z).normalized_or_zero();
        let flat_fwd = if flat_fwd == Vector3::ZERO { Vector3::FORWARD } else { flat_fwd };

        // Recenter mouse-look after a pause.
        self.cam_look_timer -= dt;
        if self.cam_look_timer <= 0.0 {
            self.cam_yaw_offset *= (-ct.car_recenter * dt).exp();
        }
        // Look-ahead into turns.
        let yaw_rate = self.base().get_angular_velocity().y;
        let la_target = (yaw_rate * ct.car_lookahead).clamp(-0.6, 0.6);
        self.cam_lookahead += (la_target - self.cam_lookahead) * (1.0 - (-3.0 * dt).exp());

        let yaw = self.cam_yaw_offset + self.cam_lookahead;
        let dir = Basis::from_axis_angle(Vector3::UP, yaw) * flat_fwd;
        let pivot = xf.origin + Vector3::new(0.0, 1.1, 0.0);
        let mut desired = pivot - dir * ct.car_distance + Vector3::new(0.0, ct.car_height - 1.1, 0.0);

        // Spring-arm collision.
        if let Some(mut space) = self.base().get_world_3d().and_then(|w| w.get_direct_space_state()) {
            if let Some(mut q) = PhysicsRayQueryParameters3D::create(pivot, desired) {
                q.set_collision_mask(LAYER_WORLD);
                let hit = space.intersect_ray(&q);
                if let Some(p) = hit.get("position") {
                    let p: Vector3 = p.to();
                    desired = p + (pivot - p).normalized_or_zero() * 0.3;
                }
            }
        }

        let k = 1.0 - (-ct.car_stiffness * dt).exp();
        self.cam_pos += (desired - self.cam_pos) * k;
        // Never lag too far behind at speed.
        let max_d = ct.car_distance * 1.6;
        if self.cam_pos.distance_to(pivot) > max_d {
            self.cam_pos = pivot + (self.cam_pos - pivot).normalized_or_zero() * max_d;
        }

        // Shake on rough ground and at speed.
        self.shake_t += dt * 31.0;
        let sh = ct.car_shake * (self.rough.min(1.0) + (speed / vt.max_speed).powi(2) * 0.3);
        let shake = Vector3::new((self.shake_t * 1.3).sin(), (self.shake_t * 1.7).cos(), 0.0) * sh;

        let look_at = pivot + flat_fwd * 2.5 + Vector3::new(0.0, 0.2, 0.0);
        let fov = ct.car_fov_base + ct.car_fov_gain * (speed / vt.max_speed).clamp(0.0, 1.0);
        let cam_pos = self.cam_pos + shake;
        if let Some(c) = &mut self.camera {
            c.set_global_position(cam_pos);
            if cam_pos.distance_to(look_at) > 0.1 {
                c.look_at(look_at);
            }
            c.set_fov(fov);
        }
    }

    fn update_audio(&mut self, vt: &VehicleTuning) {
        let speed = self.base().get_linear_velocity().length();
        let Some(pb) = &mut self.playback else { return };
        let frames = pb.get_frames_available().max(0) as usize;
        if frames == 0 { return; }
        let rpm_norm = ((self.rpm - vt.idle_rpm) / (vt.max_rpm - vt.idle_rpm)).clamp(0.0, 1.0);
        let f0 = self.rpm / 60.0 * 2.0; // 4-cylinder: two firings per revolution
        let load = self.audio_load;
        let slip = self.audio_slip;
        let wind = (speed / vt.max_speed).powi(2);
        let s = &mut self.synth;
        let r = &mut self.rng;
        self.buf.clear();
        let tau = std::f32::consts::TAU;
        for _ in 0..frames {
            s.phase = (s.phase + f0 / AUDIO_RATE).fract();
            s.phase2 = (s.phase2 + f0 * 0.5 / AUDIO_RATE).fract();
            let saw = s.phase * 2.0 - 1.0;
            let sub = (s.phase2 * tau).sin();
            let n = r.next_f32() * 2.0 - 1.0;
            let raw = saw * (0.35 + 0.35 * load) + sub * 0.5 + n * 0.15 * load;
            let cutoff = 0.08 + 0.25 * rpm_norm + 0.15 * load;
            s.lp_engine += (raw - s.lp_engine) * cutoff;
            let engine = s.lp_engine * (0.45 + 0.25 * load);

            s.squeal_phase = (s.squeal_phase + (1050.0 + 90.0 * (s.phase2 * tau).sin()) / AUDIO_RATE).fract();
            s.lp_squeal += (n - s.lp_squeal) * 0.4;
            let squeal = ((s.squeal_phase * tau).sin() * 0.6 + s.lp_squeal * 0.4) * slip * 0.28;

            s.lp_wind += (n - s.lp_wind) * 0.03;
            let wnd = s.lp_wind * wind * 1.4;

            s.thump_phase = (s.thump_phase + 55.0 / AUDIO_RATE).fract();
            let th = (s.thump_phase * tau).sin() * s.thump;
            s.thump *= 0.9993;

            let x = (engine + squeal + wnd + th * 0.6).clamp(-1.0, 1.0);
            self.buf.push(Vector2::new(x, x));
        }
        let packed = PackedVector2Array::from(self.buf.as_slice());
        pb.push_buffer(&packed);
    }
}
