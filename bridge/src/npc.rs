//! `Npc`: guards, the governor, couriers and civilians. Perception geometry
//! (distance, cone, line of sight) is measured here; what the NPC *thinks*
//! comes from `magadha_core::awareness`. Routes come from the core nav graph.
//!
//! Signals are emitted deferred so GDScript handlers can safely call back in.

use godot::classes::{CharacterBody3D, ICharacterBody3D, PhysicsRayQueryParameters3D};
use godot::prelude::*;

use magadha_core::awareness::{AlertState, Awareness, AwarenessEvent, AwarenessParams, Sighting};
use magadha_core::injury::{HitZone, Reaction, Wounds};
use magadha_core::rng::Rng;

use crate::player::{FpsController, LAYER_NPC, LAYER_VEHICLE, LAYER_WORLD};
use crate::world::{arr, v3, world};

const EYE: f32 = 1.62;
const SENSE_INTERVAL: f32 = 0.15;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Brain {
    Routine,
    Investigate,
    Combat,
    Search,
    Flee,
    Dead,
}

#[derive(GodotClass)]
#[class(base = CharacterBody3D)]
pub struct Npc {
    /// "guard", "governor", "courier", "civilian".
    #[var]
    role: GString,
    #[var]
    npc_id: GString,
    #[var]
    health: f32,
    #[var]
    walk_speed: f32,
    #[var]
    run_speed: f32,
    #[var]
    alive: bool,
    #[var]
    shot_damage: f32,
    /// Seconds to wait at each patrol point.
    #[var]
    patrol_wait: f32,
    /// Shown above the head by the level: true while talking.
    #[var]
    speaking: bool,

    patrol: Vec<Vector3>,
    patrol_i: usize,
    wait_timer: f32,
    route: Vec<Vector3>,
    dest: Option<Vector3>,
    goal_face: Option<f32>,
    running: bool,
    arrived_sent: bool,
    brain: Brain,
    awareness: Awareness,
    player: Option<Gd<FpsController>>,
    sense_timer: f32,
    fire_timer: f32,
    radio_timer: f32,
    sees_player: bool,
    suspicious_timer: f32,
    rng: Rng,
    last_hit_from: Vector3,
    last_hit_head: bool,
    last_hit_zone: GString,
    look_timer: f32,
    wounds: Wounds,
    base: Base<CharacterBody3D>,
}

#[godot_api]
impl ICharacterBody3D for Npc {
    fn init(base: Base<CharacterBody3D>) -> Self {
        Self {
            role: GString::from("guard"),
            npc_id: GString::new(),
            health: 100.0,
            walk_speed: 1.45,
            run_speed: 4.3,
            alive: true,
            shot_damage: 11.0,
            patrol_wait: 2.5,
            speaking: false,
            patrol: vec![],
            patrol_i: 0,
            wait_timer: 0.0,
            route: vec![],
            dest: None,
            goal_face: None,
            running: false,
            arrived_sent: true,
            brain: Brain::Routine,
            awareness: Awareness::default(),
            player: None,
            sense_timer: 0.0,
            fire_timer: 1.0,
            radio_timer: -1.0,
            sees_player: false,
            suspicious_timer: 0.0,
            rng: Rng::new(1),
            last_hit_from: Vector3::ZERO,
            last_hit_head: false,
            last_hit_zone: GString::from("chest"),
            look_timer: 0.0,
            wounds: Wounds::default(),
            base,
        }
    }

    fn ready(&mut self) {
        let id = self.base().instance_id().to_i64();
        self.rng = Rng::new(id as u64);
        self.sense_timer = self.rng.range(0.0, SENSE_INTERVAL);
        {
            let mut b = self.base_mut();
            b.set_collision_layer(LAYER_NPC);
            b.set_collision_mask(LAYER_WORLD | LAYER_VEHICLE);
            b.add_to_group("npc");
            b.set_floor_snap_length(0.4);
            b.set_floor_max_angle(50f32.to_radians());
        }
    }

    fn physics_process(&mut self, delta: f64) {
        let dt = delta as f32;
        if !self.alive {
            return;
        }
        self.wounds.tick(dt);
        if self.wounds.downed {
            self.tick_downed(dt);
            return;
        }
        let ai = world().ai.clone();

        // Perception, throttled and staggered.
        self.sense_timer -= dt;
        if self.sense_timer <= 0.0 {
            self.sense_timer += SENSE_INTERVAL;
            self.sense(&ai);
        }

        // Guards radio the alarm a moment after spotting you.
        if self.radio_timer > 0.0 {
            self.radio_timer -= dt;
            if self.radio_timer <= 0.0 && matches!(self.awareness.state, AlertState::Hostile | AlertState::Searching) {
                self.emit("alarm_call", &[]);
            }
        }

        self.think(dt);
        self.locomote(dt);
    }
}

#[godot_api]
impl Npc {
    #[signal]
    fn spotted_player();
    #[signal]
    fn became_suspicious();
    #[signal]
    fn alarm_call();
    #[signal]
    fn body_discovered(at: Vector3);
    #[signal]
    fn shot_at_player(from: Vector3, to: Vector3, hit: bool, damage: f32);
    #[signal]
    fn died(silent: bool);
    #[signal]
    fn reached_goal();
    /// A hit that did not kill: zone ("head", "thigh_l"...), reaction
    /// ("flinch", "head", "arm", "stumble", "down") and where it came from.
    #[signal]
    fn wounded(zone: GString, reaction: GString, from: Vector3);

    fn emit(&mut self, sig: &str, args: &[Variant]) {
        let mut v = vec![sig.to_variant()];
        v.extend_from_slice(args);
        self.base_mut().call_deferred("emit_signal", &v);
    }

    #[func]
    fn set_player(&mut self, p: Gd<FpsController>) {
        self.player = Some(p);
    }

    #[func]
    fn set_patrol(&mut self, points: PackedVector3Array) {
        self.patrol = points.as_slice().to_vec();
        self.patrol_i = 0;
        if let Some(p) = self.patrol.first().copied() {
            self.set_dest(p, false);
        }
    }

    /// Scripted destination (governor routine, courier). `face` is a yaw in
    /// radians to turn to on arrival, or NAN for none.
    #[func]
    fn go_to(&mut self, pos: Vector3, run: bool, face: f32) {
        self.patrol.clear();
        self.goal_face = if face.is_nan() { None } else { Some(face) };
        self.set_dest(pos, run);
        if self.brain != Brain::Dead { self.brain = Brain::Routine; }
    }

    #[func]
    fn at_goal(&self) -> bool {
        self.dest.is_none()
    }

    #[func]
    fn get_alert_level(&self) -> f32 {
        self.awareness.level
    }

    /// 0 calm, 1 suspicious, 2 searching, 3 hostile.
    #[func]
    fn get_alert_state(&self) -> i32 {
        match self.awareness.state {
            AlertState::Calm => 0,
            AlertState::Suspicious => 1,
            AlertState::Searching => 2,
            AlertState::Hostile => 3,
        }
    }

    #[func]
    fn sees_player(&self) -> bool {
        self.sees_player
    }

    #[func]
    fn hear_noise(&mut self, pos: Vector3, radius: f32) {
        if !self.alive { return; }
        let ai = world().ai.clone();
        let d = self.base().get_global_position().distance_to(pos);
        let role = self.role.to_string();
        if role == "civilian" || role == "courier" {
            if radius > 25.0 && d < radius {
                self.flee_from(pos);
            }
            return;
        }
        let was = self.awareness.state;
        if self.awareness.hear(&ai, arr(pos), d, radius) && was == AlertState::Calm {
            self.brain = Brain::Investigate;
            self.suspicious_timer = 1.2;
            self.emit("became_suspicious", &[]);
        }
        if role == "governor" && radius > 25.0 && d < radius {
            self.awareness.force_hostile(&ai, Some(arr(pos)));
        }
    }

    /// Alarm broadcast: become hostile, hunt toward `pos` if given.
    #[func]
    fn alert(&mut self, pos: Vector3, known: bool) {
        if !self.alive { return; }
        let ai = world().ai.clone();
        let role = self.role.to_string();
        if role == "guard" {
            if known {
                self.awareness.force_hostile(&ai, Some(arr(pos)));
            } else if self.awareness.state == AlertState::Calm {
                self.awareness.hear(&ai, arr(pos), 0.0, 1.0);
                self.brain = Brain::Search;
            }
        }
    }

    #[func]
    fn can_takedown(&self, from: Vector3) -> bool {
        if !self.alive { return false; }
        if self.wounds.downed { return true; }
        let pos = self.base().get_global_position();
        let fwd = -self.base().get_global_transform().basis.col_c();
        let to_attacker = Vector3::new(from.x - pos.x, 0.0, from.z - pos.z).normalized_or_zero();
        let behind = fwd.dot(to_attacker) < 0.2;
        behind || self.awareness.state != AlertState::Hostile
    }

    /// Where the killing blow came from (world) and whether it was the head:
    /// the ragdoll uses these for the direction of the knock.
    #[func]
    fn get_last_hit_from(&self) -> Vector3 {
        self.last_hit_from
    }

    #[func]
    fn get_last_hit_head(&self) -> bool {
        self.last_hit_head
    }

    /// Body part the last hit landed on ("head", "chest", "foot_l"...).
    #[func]
    fn get_last_hit_zone(&self) -> GString {
        self.last_hit_zone.clone()
    }

    #[func]
    fn take_down(&mut self) {
        self.last_hit_zone = GString::from("neck");
        self.die(true);
    }

    #[func]
    fn is_downed(&self) -> bool {
        self.wounds.downed
    }

    /// On one knee after a leg hit (seconds left; 0 when standing).
    #[func]
    fn get_stumble(&self) -> f32 {
        self.wounds.stumble_left()
    }

    /// Hits per limb, for the body's limp and dead arm: [leg_l, leg_r, arm_l, arm_r].
    #[func]
    fn get_wounds(&self) -> PackedInt32Array {
        PackedInt32Array::from(&[
            self.wounds.leg_hits[0] as i32,
            self.wounds.leg_hits[1] as i32,
            self.wounds.arm_hits[0] as i32,
            self.wounds.arm_hits[1] as i32,
        ])
    }

    /// Guard has a target: weapon up.
    #[func]
    fn in_combat(&self) -> bool {
        self.brain == Brain::Combat || (self.role.to_string() == "guard" && self.awareness.state == AlertState::Hostile)
    }

    /// Hauled off its feet by the grapple line: down for good, still alive.
    /// `damage` may kill.
    #[func]
    fn knock_down(&mut self, damage: f32, from: Vector3) -> bool {
        if !self.alive { return false; }
        self.last_hit_from = from;
        self.last_hit_head = false;
        self.last_hit_zone = GString::from("chest");
        self.health -= damage;
        if self.health <= 0.0 {
            self.die(false);
            return true;
        }
        if !self.wounds.downed {
            self.wounds.knock_down();
            self.go_down();
        }
        let role = self.role.to_string();
        if role == "guard" || role == "governor" {
            let ai = world().ai.clone();
            self.awareness.force_hostile(&ai, Some(arr(from)));
            if self.radio_timer < 0.0 { self.radio_timer = 1.5; }
        }
        false
    }

    /// Thrown into something at `speed` m/s (the grapple tether): damage
    /// from `crash_damage_per_ms` in wounds.ron. Returns true if it killed.
    #[func]
    fn crash(&mut self, speed: f32, at: Vector3) -> bool {
        let dmg = speed * world().wounds.crash_damage_per_ms;
        self.knock_down(dmg, at)
    }

    /// A hit on body part `zone` (see `HitZone::parse`). Returns true if it killed.
    #[func]
    fn apply_hit(&mut self, amount: f32, from: Vector3, zone: GString) -> bool {
        let z = HitZone::parse(&zone.to_string()).unwrap_or(HitZone::Chest);
        self.hit_zone(amount, from, z, zone)
    }

    /// Head-or-chest entry point (cars, debug).
    #[func]
    pub(crate) fn apply_damage(&mut self, amount: f32, from: Vector3, headshot: bool) -> bool {
        let (z, name) = if headshot { (HitZone::Head, "head") } else { (HitZone::Chest, "chest") };
        self.hit_zone(amount, from, z, GString::from(name))
    }

    fn hit_zone(&mut self, amount: f32, from: Vector3, zone: HitZone, name: GString) -> bool {
        if !self.alive { return false; }
        self.last_hit_from = from;
        self.last_hit_head = zone == HitZone::Head;
        self.last_hit_zone = name.clone();
        let p = world().wounds.clone();
        let was_down = self.wounds.downed;
        let out = self.wounds.hit(&p, zone, amount);
        self.health -= out.damage;
        if out.lethal || self.health <= 0.0 {
            self.die(false);
            return true;
        }
        if self.wounds.downed && !was_down {
            self.go_down();
        }
        let reaction = match out.reaction {
            Reaction::Down if was_down => "flinch",
            r => r.name(),
        };
        self.emit("wounded", &[name.to_variant(), reaction.to_variant(), from.to_variant()]);
        if self.wounds.downed {
            // Still calls it in from the ground.
            let role = self.role.to_string();
            if (role == "guard" || role == "governor") && self.radio_timer < 0.0 { self.radio_timer = 1.5; }
            return false;
        }
        let ai = world().ai.clone();
        let role = self.role.to_string();
        if role == "guard" || role == "governor" {
            self.awareness.force_hostile(&ai, Some(arr(from)));
            if self.radio_timer < 0.0 { self.radio_timer = 0.8; }
        } else {
            self.flee_from(from);
        }
        false
    }

    // ---- internals ---------------------------------------------------------

    fn set_dest(&mut self, pos: Vector3, run: bool) {
        let here = self.base().get_global_position();
        if let Some(d) = self.dest {
            if d.distance_to(pos) < 1.0 && self.running == run && !self.route.is_empty() { return; }
        }
        let mut r: Vec<Vector3> = world().nav.route(arr(here), arr(pos)).into_iter().map(v3).collect();
        if r.is_empty() { r.push(pos); }
        self.route = r;
        self.dest = Some(pos);
        self.running = run;
        self.arrived_sent = false;
    }

    fn flee_from(&mut self, from: Vector3) {
        let here = self.base().get_global_position();
        let away = Vector3::new(here.x - from.x, 0.0, here.z - from.z).normalized_or_zero();
        let away = if away == Vector3::ZERO { Vector3::BACK } else { away };
        let target = here + away * 25.0;
        self.brain = Brain::Flee;
        self.patrol.clear();
        self.set_dest(target, true);
    }

    /// Legs gone (or hauled off its feet): lies on the ground, bleeding.
    fn go_down(&mut self) {
        self.dest = None;
        self.route.clear();
        self.patrol.clear();
        self.speaking = false;
        self.sees_player = false;
        let mut b = self.base_mut();
        b.set_collision_layer(0);
        b.set_velocity(Vector3::ZERO);
    }

    fn tick_downed(&mut self, dt: f32) {
        let bleed = world().wounds.downed_bleed;
        self.health -= bleed * dt;
        if self.radio_timer > 0.0 {
            self.radio_timer -= dt;
            if self.radio_timer <= 0.0 {
                self.emit("alarm_call", &[]);
            }
        }
        if self.health <= 0.0 {
            self.last_hit_zone = GString::from("chest");
            self.die(true);
        }
    }

    fn die(&mut self, silent: bool) {
        if !self.alive { return; }
        self.alive = false;
        self.brain = Brain::Dead;
        self.speaking = false;
        let id = self.base().instance_id().to_i64();
        let pos = self.base().get_global_position();
        world().corpses.push((id, arr(pos)));
        {
            let mut b = self.base_mut();
            b.set_collision_layer(0);
            b.set_velocity(Vector3::ZERO);
        }
        self.emit("died", &[silent.to_variant()]);
    }

    /// Line of sight against static world only (the player may be inside a car).
    fn ray_clear(&self, from: Vector3, to: Vector3) -> bool {
        let Some(mut space) = self.base().get_world_3d().and_then(|w| w.get_direct_space_state()) else { return false };
        let Some(mut q) = PhysicsRayQueryParameters3D::create(from, to) else { return false };
        q.set_collision_mask(LAYER_WORLD);
        space.intersect_ray(&q).is_empty()
    }

    fn sense(&mut self, ai: &AwarenessParams) {
        let Some(player) = self.player.clone() else { return };
        let me = self.base().get_global_position();
        let eye = me + Vector3::new(0.0, EYE, 0.0);
        let fwd = -self.base().get_global_transform().basis.col_c();
        let role = self.role.to_string();
        let alarm = world().alarm;

        // Corpses in view.
        if role == "guard" || role == "governor" {
            let corpses: Vec<(i64, [f32; 3])> = world().corpses.clone();
            let my_id = self.base().instance_id().to_i64();
            for (cid, cp) in corpses {
                if cid == my_id { continue; }
                let c = v3(cp) + Vector3::new(0.0, 0.3, 0.0);
                let d = me.distance_to(c);
                if d > 18.0 { continue; }
                let dir = Vector3::new(c.x - me.x, 0.0, c.z - me.z).normalized_or_zero();
                let ang = fwd.dot(dir).clamp(-1.0, 1.0).acos().to_degrees();
                if !Awareness::in_view(ai, d, ang) { continue; }
                if !self.ray_clear(eye, c) { continue; }
                world().corpses.retain(|(id, _)| *id != cid);
                self.awareness.hear(ai, cp, 0.0, 1.0);
                self.brain = Brain::Search;
                self.emit("body_discovered", &[c.to_variant()]);
                break;
            }
        }

        let (ppos, crouched, speed, hostile_flags, restricted, weapon, exposure, _enabled) = {
            let p = player.bind();
            (
                player.get_global_position(),
                p.is_crouching(),
                p.get_horizontal_speed(),
                p.is_hostile_to_guards(),
                p.restricted,
                p.weapon_raised,
                p.exposure,
                p.enabled,
            )
        };
        let mut sight = None;
        self.sees_player = false;
        {
            let target_h = if crouched { 0.9 } else { 1.45 };
            let pt = ppos + Vector3::new(0.0, target_h, 0.0);
            let d = eye.distance_to(pt);
            if d < ai.view_distance + 2.0 {
                let dir = Vector3::new(pt.x - eye.x, 0.0, pt.z - eye.z).normalized_or_zero();
                let ang = fwd.dot(dir).clamp(-1.0, 1.0).acos().to_degrees();
                if Awareness::in_view(ai, d, ang)
                    && (self.ray_clear(eye, pt) || self.ray_clear(eye, ppos + Vector3::new(0.0, 0.5, 0.0)))
                {
                    self.sees_player = true;
                    let hostile = match role.as_str() {
                        "guard" => hostile_flags,
                        "governor" => restricted > 0 || weapon || alarm,
                        _ => false,
                    };
                    sight = Some(Sighting {
                        distance: d,
                        angle_deg: ang,
                        crouched,
                        moving_fast: speed > 5.0,
                        exposure,
                        hostile,
                        position: arr(ppos),
                    });
                }
            }
        }

        let ev = self.awareness.update(ai, SENSE_INTERVAL, sight, alarm);
        match ev {
            Some(AwarenessEvent::Spotted) => {
                self.emit("spotted_player", &[]);
                if role == "guard" {
                    self.brain = Brain::Combat;
                    self.fire_timer = 0.7;
                    if self.radio_timer < 0.0 { self.radio_timer = 2.2; }
                } else {
                    // Governor shouts for the guards and runs.
                    if self.radio_timer < 0.0 { self.radio_timer = 0.6; }
                    self.brain = Brain::Flee;
                }
            }
            Some(AwarenessEvent::BecameSuspicious) => {
                self.suspicious_timer = 1.5;
                if role == "guard" { self.brain = Brain::Investigate; }
                self.emit("became_suspicious", &[]);
            }
            Some(AwarenessEvent::LostTarget) => {
                if role == "guard" { self.brain = Brain::Search; }
            }
            Some(AwarenessEvent::CalmedDown) => {
                if self.brain != Brain::Flee || role == "guard" {
                    self.brain = Brain::Routine;
                    self.resume_routine();
                }
            }
            None => {}
        }

        // Shooting decisions happen at the sense rate.
        if role == "guard" && self.brain == Brain::Combat && self.sees_player && self.awareness.state == AlertState::Hostile {
            self.fire_timer -= SENSE_INTERVAL;
            if self.fire_timer <= 0.0 && !self.wounds.stumbling() {
                let wp = world().wounds.clone();
                self.fire_timer = self.rng.range(0.45, 0.95) * self.wounds.fire_delay_mult(&wp);
                let d = me.distance_to(ppos);
                let mut p_hit = (0.8 - d / 45.0 - speed * 0.045).clamp(0.08, 0.8);
                if crouched { p_hit *= 0.85; }
                p_hit *= self.wounds.accuracy_mult(&wp);
                let hit = self.rng.chance(p_hit);
                let aim = ppos + Vector3::new(0.0, if crouched { 0.9 } else { 1.3 }, 0.0);
                let miss = if hit {
                    Vector3::ZERO
                } else {
                    Vector3::new(self.rng.range(-1.0, 1.0), self.rng.range(-0.4, 0.8), self.rng.range(-1.0, 1.0)) * (0.6 + d * 0.03)
                };
                let muzzle = eye + fwd * 0.5 - Vector3::new(0.0, 0.25, 0.0);
                let dmg = self.shot_damage * self.rng.range(0.8, 1.2);
                self.emit("shot_at_player", &[muzzle.to_variant(), (aim + miss).to_variant(), hit.to_variant(), dmg.to_variant()]);
            }
        }
    }

    fn resume_routine(&mut self) {
        if let Some(p) = self.patrol.get(self.patrol_i).copied() {
            self.set_dest(p, false);
        }
    }

    fn think(&mut self, dt: f32) {
        let role = self.role.to_string();
        let lk = self.awareness.last_known.map(v3);
        match self.brain {
            Brain::Routine => {
                if self.dest.is_none() && !self.patrol.is_empty() {
                    self.wait_timer -= dt;
                    if self.wait_timer <= 0.0 {
                        self.patrol_i = (self.patrol_i + 1) % self.patrol.len();
                        let p = self.patrol[self.patrol_i];
                        self.set_dest(p, false);
                    }
                }
            }
            Brain::Investigate => {
                // Stop and stare first, then walk over.
                if self.suspicious_timer > 0.0 {
                    self.suspicious_timer -= dt;
                    self.dest = None;
                    self.route.clear();
                    if let Some(p) = lk { self.face_toward(p, dt); }
                } else if let Some(p) = lk {
                    if role == "guard" {
                        self.set_dest(p, false);
                    }
                }
            }
            Brain::Search => {
                if let Some(p) = lk {
                    if self.dest.is_none() {
                        // Arrived: look around, then pick a nearby spot.
                        self.look_timer -= dt;
                        if self.look_timer <= 0.0 {
                            self.look_timer = 2.5;
                            let off = Vector3::new(self.rng.range(-6.0, 6.0), 0.0, self.rng.range(-6.0, 6.0));
                            self.set_dest(p + off, false);
                        }
                    } else if self.dest.map(|d| d.distance_to(p) > 8.0).unwrap_or(true) {
                        self.set_dest(p, true);
                    }
                }
            }
            Brain::Combat => {
                if let Some(p) = lk {
                    let me = self.base().get_global_position();
                    let d = me.distance_to(p);
                    if self.sees_player {
                        // Hold position at range, close in when far.
                        if d > 14.0 { self.set_dest(p, true); } else { self.dest = None; self.route.clear(); }
                        self.face_toward(p, dt);
                    } else {
                        self.set_dest(p, true);
                    }
                }
            }
            Brain::Flee => {}
            Brain::Dead => {}
        }
    }

    fn face_toward(&mut self, p: Vector3, dt: f32) {
        let me = self.base().get_global_position();
        let d = Vector3::new(p.x - me.x, 0.0, p.z - me.z);
        if d.length_squared() < 0.01 { return; }
        let target = (-d.x).atan2(-d.z);
        self.turn_to(target, dt, 9.0);
    }

    fn turn_to(&mut self, target_yaw: f32, dt: f32, rate: f32) {
        let mut r = self.base().get_rotation();
        let mut diff = target_yaw - r.y;
        while diff > std::f32::consts::PI { diff -= std::f32::consts::TAU; }
        while diff < -std::f32::consts::PI { diff += std::f32::consts::TAU; }
        r.y += diff * (1.0 - (-rate * dt).exp());
        self.base_mut().set_rotation(r);
    }

    fn locomote(&mut self, dt: f32) {
        let me = self.base().get_global_position();
        let mut vel = self.base().get_velocity();
        let mut want = Vector3::ZERO;
        while let Some(next) = self.route.first().copied() {
            let flat = Vector3::new(next.x - me.x, 0.0, next.z - me.z);
            let last = self.route.len() == 1;
            let radius = if last { 0.35 } else { 0.8 };
            if flat.length() < radius {
                self.route.remove(0);
                continue;
            }
            let limp = self.wounds.speed_mult(&world().wounds, self.running);
            let speed = if self.running { self.run_speed } else { self.walk_speed } * limp;
            want = flat.normalized() * speed;
            if last && flat.length() < 1.2 { want *= flat.length() / 1.2 + 0.2; }
            break;
        }
        if self.route.is_empty() && self.dest.is_some() {
            self.dest = None;
            self.wait_timer = self.patrol_wait;
            if !self.arrived_sent {
                self.arrived_sent = true;
                if self.brain == Brain::Flee && self.role.to_string() != "governor" {
                    // Civilians cower where they ended up.
                } else {
                    self.emit("reached_goal", &[]);
                }
            }
        }
        let accel = 10.0;
        vel.x += (want.x - vel.x) * (1.0 - (-accel * dt).exp());
        vel.z += (want.z - vel.z) * (1.0 - (-accel * dt).exp());
        if self.base().is_on_floor() { vel.y = -0.5; } else { vel.y -= 20.0 * dt; }
        self.base_mut().set_velocity(vel);
        self.base_mut().move_and_slide();

        let hs = Vector3::new(vel.x, 0.0, vel.z);
        if self.wounds.stumbling() {
            // On one knee: no turning either.
        } else if hs.length() > 0.3 && self.brain != Brain::Combat {
            let yaw = (-hs.x).atan2(-hs.z);
            self.turn_to(yaw, dt, 8.0);
        } else if self.dest.is_none() {
            if let Some(f) = self.goal_face {
                if self.brain == Brain::Routine { self.turn_to(f, dt, 5.0); }
            }
        }
    }
}
