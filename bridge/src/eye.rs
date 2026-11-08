//! `Eye`: one of Avekṣā's cameras [INVENTED], a gantry camera, a tethered
//! balloon or a saucer drone. Measures geometry only: is a crime in view, with a
//! clear line. What the room does about it is `core::surveillance`.
//!
//! The scene provides a child Node3D named "Head" (looks along its -Z).

use godot::classes::{INode3D, Node3D, PhysicsRayQueryParameters3D};
use magadha_core::crash::Hull;
use godot::prelude::*;

use magadha_core::awareness::{Detector, DetectorParams};
use magadha_core::pursuit::PursuitParams;
use magadha_core::rng::Rng;

use crate::player::{FpsController, LAYER_WORLD};
use crate::world::world;

/// Seconds an eye waits after recording before it can record again.
const RECORD_COOLDOWN: f32 = 8.0;

#[derive(GodotClass)]
#[class(base = Node3D)]
pub struct Eye {
    #[var]
    feed_id: GString,
    /// "gantry", "balloon" or "drone".
    #[var]
    kind: GString,
    #[var]
    live: bool,
    /// Pursuit drone: flies at the player and fires on them.
    #[var]
    chasing: bool,
    player: Option<Gd<FpsController>>,
    head: Option<Gd<Node3D>>,
    params: DetectorParams,
    chase: PursuitParams,
    detector: Detector,
    path: Vec<Vector3>,
    path_i: usize,
    base_yaw: f32,
    sweep_t: f32,
    drift_t: f32,
    home_y: f32,
    cooldown: f32,
    shot_t: f32,
    sees: bool,
    hull: Option<Hull>,
    rng: Rng,
    base: Base<Node3D>,
}

#[godot_api]
impl INode3D for Eye {
    fn init(base: Base<Node3D>) -> Self {
        Self {
            feed_id: GString::new(),
            kind: GString::from("gantry"),
            live: true,
            chasing: false,
            player: None,
            head: None,
            params: DetectorParams::default(),
            chase: PursuitParams::default(),
            detector: Detector::default(),
            path: vec![],
            path_i: 0,
            base_yaw: 0.0,
            sweep_t: 0.0,
            drift_t: 0.0,
            home_y: 0.0,
            cooldown: 0.0,
            shot_t: 0.0,
            sees: false,
            hull: None,
            rng: Rng::new(911),
            base,
        }
    }

    fn ready(&mut self) {
        self.head = self.base().get_node_or_null("Head").and_then(|n| n.try_cast::<Node3D>().ok());
        self.base_yaw = self.head.as_ref().map(|h| h.get_rotation().y).unwrap_or(0.0);
        self.home_y = self.base().get_global_position().y;
        self.sweep_t = self.base().get_global_position().x * 0.37;
        self.drift_t = self.sweep_t;
        self.rng = Rng::new(self.base().instance_id().to_i64() as u64);
        if let Some(f) = &world().festival {
            self.chase = f.pursuit.clone();
            let k = self.kind.to_string();
            self.params = match k.as_str() {
                "balloon" => f.surveillance.balloon.clone(),
                "drone" => f.surveillance.drone.clone(),
                _ => f.surveillance.gantry.clone(),
            };
        }
    }

    fn physics_process(&mut self, delta: f64) {
        let dt = delta as f32;
        self.fly(dt);
        if !self.live {
            self.sees = false;
            self.detector.level = 0.0;
            return;
        }
        self.sweep(dt);
        self.cooldown = (self.cooldown - dt).max(0.0);
        let Some(player) = self.player.clone() else { return };
        let (at, hostile, exposure, enabled) = {
            let p = player.bind();
            (player.get_global_position() + Vector3::new(0.0, 1.3, 0.0), p.is_hostile_to_guards(), p.exposure, p.enabled)
        };
        let dist = self.origin().distance_to(at);
        self.sees = enabled && self.in_cone(at) && self.clear_line(at);
        let crime = if self.sees && hostile && self.cooldown <= 0.0 { Some(dist) } else { None };
        if self.detector.update(&self.params, dt, crime, exposure) {
            self.cooldown = RECORD_COOLDOWN;
            let id = self.feed_id.clone();
            self.base_mut().emit_signal("recorded", &[id.to_variant()]);
        }
    }
}

#[godot_api]
impl Eye {
    /// A crime has been held in frame long enough: it is on tape.
    #[signal]
    fn recorded(feed_id: GString);
    #[signal]
    fn fired(from: Vector3, to: Vector3, hit: bool, damage: f32);

    #[func]
    fn set_player(&mut self, p: Gd<FpsController>) {
        self.player = Some(p);
    }

    /// Patrol route for a drone (the level walks it in a loop).
    #[func]
    fn set_path(&mut self, points: PackedVector3Array) {
        self.path = points.as_slice().to_vec();
        self.path_i = 0;
    }

    /// A bullet in a drone. True when that was the one that brought it down.
    #[func]
    fn hit(&mut self, damage: f32) -> bool {
        let hull = self.hull.get_or_insert_with(|| Hull::new(world().tuning.crash.drone_hp));
        hull.damage(damage);
        hull.wrecked()
    }

    #[func]
    fn get_hull(&self) -> f32 {
        self.hull.map(|h| h.fraction()).unwrap_or(1.0)
    }

    /// 0..1, how close to recording.
    #[func]
    fn get_level(&self) -> f32 {
        self.detector.level
    }

    /// True while the player is framed, crime or no crime.
    #[func]
    fn sees_player(&self) -> bool {
        self.sees
    }

    /// Geometry only: is this point framed right now?
    #[func]
    fn sees_point(&self, at: Vector3) -> bool {
        self.live && self.in_cone(at) && self.clear_line(at)
    }

    fn origin(&self) -> Vector3 {
        self.head.as_ref().map(|h| h.get_global_position()).unwrap_or_else(|| self.base().get_global_position())
    }

    fn in_cone(&self, at: Vector3) -> bool {
        let Some(h) = &self.head else { return false };
        let o = h.get_global_position();
        let to = at - o;
        let d = to.length();
        if d < 0.01 { return true; }
        let fwd = -h.get_global_transform().basis.col_c();
        let angle = fwd.dot(to / d).clamp(-1.0, 1.0).acos().to_degrees();
        Detector::in_view(&self.params, d, angle)
    }

    fn clear_line(&self, at: Vector3) -> bool {
        let Some(world3d) = self.base().get_world_3d() else { return false };
        let Some(mut space) = world3d.get_direct_space_state() else { return false };
        let Some(mut q) = PhysicsRayQueryParameters3D::create(self.origin(), at) else { return false };
        q.set_collision_mask(LAYER_WORLD);
        space.intersect_ray(&q).is_empty()
    }

    fn sweep(&mut self, dt: f32) {
        if self.chasing { return; }
        self.sweep_t += self.params.sweep_speed.to_radians() * dt;
        let yaw = if self.params.sweep_deg >= 180.0 {
            self.sweep_t
        } else if self.params.sweep_speed <= 0.0 {
            self.base_yaw
        } else {
            let span = self.params.sweep_deg.to_radians();
            self.base_yaw + (self.sweep_t / span.max(0.01)).sin() * span
        };
        if let Some(h) = &mut self.head {
            let mut r = h.get_rotation();
            r.y = yaw;
            h.set_rotation(r);
        }
    }

    fn fly(&mut self, dt: f32) {
        self.drift_t += dt;
        let k = self.kind.to_string();
        if k == "balloon" {
            let mut p = self.base().get_global_position();
            p.y = self.home_y + (self.drift_t * 0.4).sin() * 0.6;
            self.base_mut().set_global_position(p);
            return;
        }
        if k != "drone" { return; }
        if self.chasing {
            self.chase_player(dt);
            return;
        }
        if !self.live {
            // Its fall belongs to the wreck the level drops in its place.
            return;
        }
        if self.path.is_empty() { return; }
        let goal = self.path[self.path_i];
        let p = self.base().get_global_position();
        let to = goal - p;
        if to.length() < 1.0 {
            self.path_i = (self.path_i + 1) % self.path.len();
            return;
        }
        let dir = to.normalized_or_zero();
        let speed = self.params.speed;
        self.base_mut().set_global_position(p + dir * speed * dt);
    }

    fn chase_player(&mut self, dt: f32) {
        if !self.live { self.chasing = false; return; }
        let Some(player) = self.player.clone() else { return };
        let target = player.get_global_position() + Vector3::new(0.0, 7.0, 0.0);
        let p = self.base().get_global_position();
        let to = target - p;
        let speed = self.chase.drone_speed;
        if to.length() > 2.0 {
            self.base_mut().set_global_position(p + to.normalized_or_zero() * (speed * dt).min(to.length()));
        }
        let aim = player.get_global_position() + Vector3::new(0.0, 1.0, 0.0);
        if let Some(h) = &mut self.head {
            if h.get_global_position().distance_to(aim) > 0.5 {
                h.look_at(aim);
            }
        }
        self.shot_t -= dt;
        if self.shot_t > 0.0 { return; }
        let from = self.origin();
        if from.distance_to(aim) > self.chase.shot_range || !self.clear_line(aim) { return; }
        self.shot_t = self.chase.shot_interval * self.rng.range(0.8, 1.4);
        let hit = self.rng.chance(self.chase.shot_hit_chance);
        let dmg = self.chase.shot_damage;
        self.base_mut().emit_signal("fired", &[from.to_variant(), aim.to_variant(), hit.to_variant(), dmg.to_variant()]);
    }
}
