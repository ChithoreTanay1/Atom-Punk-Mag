//! Measures crashes on a vehicle body. Engine, brakes and suspension change the
//! velocity gently; only a collision changes it by metres per second within a
//! few physics ticks, so that change is the impact.

use godot::classes::{PhysicsServer3D, RigidBody3D};
use godot::prelude::*;

/// Ticks to compare across (Jolt can resolve one hit over a couple of steps).
const WINDOW: usize = 4;
/// One crash, one report.
const COOLDOWN: f32 = 0.4;

#[derive(Default)]
pub struct ImpactSensor {
    hist: [Vector3; WINDOW],
    i: usize,
    cooldown: f32,
    /// Velocity just before the last impact (where a thrown rider is going).
    pub before: Vector3,
    /// Velocity change of the last impact.
    pub delta: Vector3,
}

impl ImpactSensor {
    /// After a teleport: the jump in velocity is not a crash.
    pub fn reset(&mut self, v: Vector3) {
        self.hist = [v; WINDOW];
        self.cooldown = COOLDOWN;
    }

    /// Returns the speed change if this tick completed an impact.
    pub fn update(&mut self, v: Vector3, touching: bool, dt: f32) -> Option<f32> {
        let old = self.hist[self.i];
        self.hist[self.i] = v;
        self.i = (self.i + 1) % WINDOW;
        self.cooldown = (self.cooldown - dt).max(0.0);
        if self.cooldown > 0.0 || !touching {
            return None;
        }
        let dv = (v - old).length();
        if dv < 3.0 {
            return None;
        }
        self.cooldown = COOLDOWN;
        self.before = old;
        self.delta = v - old;
        Some(dv)
    }
}

/// Where on the body the last impact landed, in body space. The hardest contact
/// that is not the ground; failing that, the side the hit must have come from
/// (`half` is the half size of the body's box).
pub fn impact_point(body: &Gd<RigidBody3D>, delta: Vector3, half: Vector3) -> Vector3 {
    let xf = body.get_global_transform();
    let inv = xf.affine_inverse();
    let up = xf.basis.col_b();
    let mut best: Option<(f32, Vector3)> = None;
    if let Some(st) = PhysicsServer3D::singleton().body_get_direct_state(body.get_rid()) {
        for i in 0..st.get_contact_count() {
            if st.get_contact_local_normal(i).dot(up).abs() > 0.8 { continue; }
            let f = st.get_contact_impulse(i).length();
            if best.is_none_or(|(b, _)| f > b) {
                best = Some((f, st.get_contact_local_position(i)));
            }
        }
    }
    if let Some((_, p)) = best {
        return inv * p;
    }
    let d = (inv.basis * -delta).normalized_or_zero();
    let t = [(d.x, half.x), (d.y, half.y), (d.z, half.z)]
        .iter()
        .filter(|(a, _)| a.abs() > 1e-3)
        .map(|(a, h)| h / a.abs())
        .fold(f32::MAX, f32::min);
    if t == f32::MAX { Vector3::ZERO } else { d * t }
}
