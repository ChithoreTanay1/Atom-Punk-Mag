//! Locational damage: where a hit lands decides how much it hurts and what
//! it does to the body (limp, a dead arm, knocked down). Pure rules; the
//! bridge measures which zone was hit and the Godot side shows the result.
//! Every number lives in `data/wounds.ron`.

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    Left,
    Right,
}

impl Side {
    fn idx(self) -> usize {
        match self {
            Side::Left => 0,
            Side::Right => 1,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HitZone {
    Head,
    Neck,
    Chest,
    Abdomen,
    Pelvis,
    UpperArm(Side),
    Forearm(Side),
    Hand(Side),
    Thigh(Side),
    Shin(Side),
    Foot(Side),
}

impl HitZone {
    /// Names as the Godot side sends them: "head", "chest", "thigh_l", "foot_r"...
    pub fn parse(s: &str) -> Option<Self> {
        let side = |t: &str| match t {
            "l" => Some(Side::Left),
            "r" => Some(Side::Right),
            _ => None,
        };
        Some(match s {
            "head" => HitZone::Head,
            "neck" => HitZone::Neck,
            "chest" => HitZone::Chest,
            "abdomen" => HitZone::Abdomen,
            "pelvis" => HitZone::Pelvis,
            _ => {
                let (part, sd) = s.rsplit_once('_')?;
                let sd = side(sd)?;
                match part {
                    "upperarm" => HitZone::UpperArm(sd),
                    "forearm" => HitZone::Forearm(sd),
                    "hand" => HitZone::Hand(sd),
                    "thigh" => HitZone::Thigh(sd),
                    "shin" => HitZone::Shin(sd),
                    "foot" => HitZone::Foot(sd),
                    _ => return None,
                }
            }
        })
    }

    pub fn side(self) -> Option<Side> {
        match self {
            HitZone::UpperArm(s) | HitZone::Forearm(s) | HitZone::Hand(s) | HitZone::Thigh(s) | HitZone::Shin(s) | HitZone::Foot(s) => Some(s),
            _ => None,
        }
    }

    pub fn is_leg(self) -> bool {
        matches!(self, HitZone::Thigh(_) | HitZone::Shin(_) | HitZone::Foot(_))
    }

    pub fn is_arm(self) -> bool {
        matches!(self, HitZone::UpperArm(_) | HitZone::Forearm(_) | HitZone::Hand(_))
    }
}

/// Tunables, loaded from `data/wounds.ron`.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WoundParams {
    /// Damage multipliers per zone (the head multiplier comes from the weapon).
    pub neck_mult: f32,
    pub chest_mult: f32,
    pub abdomen_mult: f32,
    pub pelvis_mult: f32,
    pub upper_arm_mult: f32,
    pub forearm_mult: f32,
    pub hand_mult: f32,
    pub thigh_mult: f32,
    pub shin_mult: f32,
    pub foot_mult: f32,
    /// A head hit at least this hard always kills (a bullet in the face).
    pub head_lethal_damage: f32,
    /// Seconds a leg hit puts the body on one knee before it limps on.
    pub stumble_time: f32,
    /// A foot or shin hit stumbles longer than a thigh hit by this factor.
    pub low_leg_stumble_mult: f32,
    /// Leg hits (both legs counted) that put the body on the ground for good.
    pub leg_hits_to_down: u32,
    /// Walking speed per wounded leg, multiplied (one leg 0.55, both lower).
    pub limp_walk_mult: f32,
    /// Running speed per wounded leg, multiplied.
    pub limp_run_mult: f32,
    /// Hit chance multiplier with the gun arm wounded.
    pub gun_arm_accuracy: f32,
    /// Hit chance multiplier with the other arm wounded.
    pub off_arm_accuracy: f32,
    /// Time between shots multiplier with the gun arm wounded.
    pub gun_arm_fire_delay: f32,
    /// Health lost per second while down on the ground.
    pub downed_bleed: f32,
    /// Damage taken by a body hauled in by the grapple line, per m/s of
    /// impact speed when it hits something.
    pub crash_damage_per_ms: f32,
}

impl Default for WoundParams {
    fn default() -> Self {
        Self {
            neck_mult: 1.6,
            chest_mult: 1.1,
            abdomen_mult: 0.95,
            pelvis_mult: 0.85,
            upper_arm_mult: 0.5,
            forearm_mult: 0.4,
            hand_mult: 0.3,
            thigh_mult: 0.6,
            shin_mult: 0.45,
            foot_mult: 0.35,
            head_lethal_damage: 25.0,
            stumble_time: 1.4,
            low_leg_stumble_mult: 1.3,
            leg_hits_to_down: 3,
            limp_walk_mult: 0.55,
            limp_run_mult: 0.4,
            gun_arm_accuracy: 0.35,
            off_arm_accuracy: 0.75,
            gun_arm_fire_delay: 1.8,
            downed_bleed: 1.5,
            crash_damage_per_ms: 4.0,
        }
    }
}

/// What the body should visibly do about a hit.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reaction {
    /// Upper body jerks with the blow, keeps going.
    Flinch,
    /// Head whipped back; with enough damage it is the killing blow.
    HeadSnap,
    /// The arm is hit and hangs from now on.
    ArmLimp(Side),
    /// Drops to one knee on the hit leg, then gets up and limps.
    Stumble(Side),
    /// Legs gone: down on the ground.
    Down,
}

impl Reaction {
    pub fn name(self) -> &'static str {
        match self {
            Reaction::Flinch => "flinch",
            Reaction::HeadSnap => "head",
            Reaction::ArmLimp(_) => "arm",
            Reaction::Stumble(_) => "stumble",
            Reaction::Down => "down",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct HitOutcome {
    pub damage: f32,
    pub reaction: Reaction,
    /// The hit must kill whatever health is left (a face shot).
    pub lethal: bool,
}

/// Wounds one body carries. Guards hold the gun in the right hand.
#[derive(Clone, Debug, Default)]
pub struct Wounds {
    pub leg_hits: [u32; 2],
    pub arm_hits: [u32; 2],
    pub downed: bool,
    stumble: f32,
}

impl Wounds {
    pub fn hit(&mut self, p: &WoundParams, zone: HitZone, damage: f32) -> HitOutcome {
        let mult = match zone {
            HitZone::Head => 1.0,
            HitZone::Neck => p.neck_mult,
            HitZone::Chest => p.chest_mult,
            HitZone::Abdomen => p.abdomen_mult,
            HitZone::Pelvis => p.pelvis_mult,
            HitZone::UpperArm(_) => p.upper_arm_mult,
            HitZone::Forearm(_) => p.forearm_mult,
            HitZone::Hand(_) => p.hand_mult,
            HitZone::Thigh(_) => p.thigh_mult,
            HitZone::Shin(_) => p.shin_mult,
            HitZone::Foot(_) => p.foot_mult,
        };
        let damage = damage * mult;
        let mut lethal = false;
        let reaction = match zone {
            HitZone::Head => {
                lethal = damage >= p.head_lethal_damage;
                Reaction::HeadSnap
            }
            z if z.is_arm() => {
                let s = z.side().unwrap_or(Side::Right);
                self.arm_hits[s.idx()] += 1;
                Reaction::ArmLimp(s)
            }
            z if z.is_leg() => {
                let s = z.side().unwrap_or(Side::Right);
                self.leg_hits[s.idx()] += 1;
                let total = self.leg_hits[0] + self.leg_hits[1];
                if self.downed || total >= p.leg_hits_to_down {
                    self.downed = true;
                    Reaction::Down
                } else {
                    let low = matches!(z, HitZone::Shin(_) | HitZone::Foot(_));
                    self.stumble = p.stumble_time * if low { p.low_leg_stumble_mult } else { 1.0 };
                    Reaction::Stumble(s)
                }
            }
            HitZone::Pelvis if self.leg_hits[0] + self.leg_hits[1] > 0 => {
                // A hip shot on a wounded leg takes the body down too.
                self.downed = true;
                Reaction::Down
            }
            _ => Reaction::Flinch,
        };
        HitOutcome { damage, reaction, lethal }
    }

    pub fn tick(&mut self, dt: f32) {
        self.stumble = (self.stumble - dt).max(0.0);
    }

    /// On one knee after a leg hit: no walking.
    pub fn stumbling(&self) -> bool {
        self.stumble > 0.0
    }

    pub fn stumble_left(&self) -> f32 {
        self.stumble
    }

    pub fn wounded_legs(&self) -> u32 {
        (self.leg_hits[0] > 0) as u32 + (self.leg_hits[1] > 0) as u32
    }

    pub fn speed_mult(&self, p: &WoundParams, running: bool) -> f32 {
        if self.downed || self.stumbling() {
            return 0.0;
        }
        let m = if running { p.limp_run_mult } else { p.limp_walk_mult };
        m.powi(self.wounded_legs() as i32)
    }

    pub fn accuracy_mult(&self, p: &WoundParams) -> f32 {
        let mut a = 1.0;
        if self.arm_hits[Side::Right.idx()] > 0 { a *= p.gun_arm_accuracy; }
        if self.arm_hits[Side::Left.idx()] > 0 { a *= p.off_arm_accuracy; }
        a
    }

    pub fn fire_delay_mult(&self, p: &WoundParams) -> f32 {
        if self.arm_hits[Side::Right.idx()] > 0 { p.gun_arm_fire_delay } else { 1.0 }
    }

    /// Knocked down by something other than a leg wound (hauled in by the line).
    pub fn knock_down(&mut self) {
        self.downed = true;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zones_parse() {
        assert_eq!(HitZone::parse("head"), Some(HitZone::Head));
        assert_eq!(HitZone::parse("foot_l"), Some(HitZone::Foot(Side::Left)));
        assert_eq!(HitZone::parse("upperarm_r"), Some(HitZone::UpperArm(Side::Right)));
        assert_eq!(HitZone::parse("tail_l"), None);
        assert_eq!(HitZone::parse("thigh"), None);
    }

    #[test]
    fn face_shot_is_lethal_limbs_are_not() {
        let p = WoundParams::default();
        let mut w = Wounds::default();
        let h = w.hit(&p, HitZone::Head, 90.0);
        assert!(h.lethal);
        assert_eq!(h.reaction, Reaction::HeadSnap);
        let a = w.hit(&p, HitZone::Hand(Side::Right), 40.0);
        assert!(!a.lethal);
        assert!(a.damage < 40.0);
        assert!(w.accuracy_mult(&p) < 0.5);
    }

    #[test]
    fn leg_hits_stumble_limp_then_drop() {
        let p = WoundParams::default();
        let mut w = Wounds::default();
        let r = w.hit(&p, HitZone::Foot(Side::Left), 30.0);
        assert_eq!(r.reaction, Reaction::Stumble(Side::Left));
        assert!(w.stumbling());
        assert_eq!(w.speed_mult(&p, false), 0.0);
        w.tick(10.0);
        assert!((w.speed_mult(&p, false) - p.limp_walk_mult).abs() < 1e-6);
        w.hit(&p, HitZone::Thigh(Side::Right), 30.0);
        assert!(!w.downed);
        let r = w.hit(&p, HitZone::Shin(Side::Right), 30.0);
        assert_eq!(r.reaction, Reaction::Down);
        assert!(w.downed);
        assert_eq!(w.speed_mult(&p, true), 0.0);
    }

    #[test]
    fn hip_shot_on_a_bad_leg_drops() {
        let p = WoundParams::default();
        let mut w = Wounds::default();
        assert_eq!(w.hit(&p, HitZone::Pelvis, 30.0).reaction, Reaction::Flinch);
        w.hit(&p, HitZone::Thigh(Side::Left), 30.0);
        assert_eq!(w.hit(&p, HitZone::Pelvis, 30.0).reaction, Reaction::Down);
    }
}
