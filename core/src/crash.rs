//! What a crash does: injury, hull damage, thrown riders, broken glass. The
//! bridge measures the impact (change in velocity); everything it means is here.

use crate::tuning::CrashTuning;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Vehicle {
    Car,
    Bike,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct CrashOutcome {
    /// Damage to the person aboard.
    pub injury: f32,
    pub hull_loss: f32,
    /// A motorcycle rider leaves the machine.
    pub eject: bool,
    /// How many hits the windshield takes (0, 1 cracks it, 2 breaks it out).
    pub glass_hits: u32,
}

/// `delta_v` is the speed change of the impact, m/s. Below `min_impact` it is
/// a scrape: nothing happens.
pub fn assess(t: &CrashTuning, v: Vehicle, delta_v: f32) -> CrashOutcome {
    if delta_v < t.min_impact {
        return CrashOutcome::default();
    }
    let mult = if v == Vehicle::Bike { t.bike_injury_mult } else { 1.0 };
    CrashOutcome {
        injury: (delta_v - t.injury_start).max(0.0) * t.injury_per_ms * mult,
        hull_loss: delta_v * t.hull_per_ms,
        eject: v == Vehicle::Bike && delta_v >= t.bike_eject_at,
        glass_hits: if v != Vehicle::Car {
            0
        } else if delta_v >= t.shatter_at {
            2
        } else if delta_v >= t.crack_at {
            1
        } else {
            0
        },
    }
}

/// A vehicle's remaining structure, as a fraction of 1.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Hull {
    pub hp: f32,
    pub max: f32,
}

impl Hull {
    pub fn new(max: f32) -> Self {
        Self { hp: max, max }
    }

    pub fn damage(&mut self, amount: f32) {
        self.hp = (self.hp - amount).max(0.0);
    }

    pub fn fraction(&self) -> f32 {
        if self.max <= 0.0 { 0.0 } else { self.hp / self.max }
    }

    pub fn wrecked(&self) -> bool {
        self.hp <= 0.0
    }

    /// Multiplies engine force: full power, then a limp below `limp_fraction`,
    /// and nothing once wrecked.
    pub fn engine_factor(&self, t: &CrashTuning) -> f32 {
        if self.wrecked() {
            0.0
        } else if self.fraction() < t.limp_fraction {
            t.limp_power
        } else {
            1.0
        }
    }
}

/// A windshield: the first hit crazes the whole pane so you can hardly see
/// through it; the next one takes it out and the view is clear again.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Glass {
    #[default]
    Intact,
    Cracked,
    Gone,
}

impl Glass {
    pub fn hit(&mut self) {
        *self = match self {
            Glass::Intact => Glass::Cracked,
            _ => Glass::Gone,
        };
    }

    pub fn code(&self) -> i32 {
        match self {
            Glass::Intact => 0,
            Glass::Cracked => 1,
            Glass::Gone => 2,
        }
    }
}

/// A tyre. A bullet punctures it and it goes down over a moment; then it runs
/// on the rim: less grip, more drag, lower to the road.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Tyre {
    /// 1 full, 0 flat.
    pub pressure: f32,
    pub punctured: bool,
}

impl Default for Tyre {
    fn default() -> Self {
        Self { pressure: 1.0, punctured: false }
    }
}

impl Tyre {
    /// Returns true if this was the shot that punctured it.
    pub fn hit(&mut self) -> bool {
        let first = !self.punctured;
        self.punctured = true;
        first
    }

    pub fn tick(&mut self, dt: f32, t: &CrashTuning) {
        if self.punctured {
            self.pressure = (self.pressure - dt / t.deflate_seconds.max(0.01)).max(0.0);
        }
    }

    pub fn grip(&self, t: &CrashTuning) -> f32 {
        t.flat_grip + (1.0 - t.flat_grip) * self.pressure
    }

    /// Rolling radius, as a share of a full tyre's.
    pub fn radius(&self, t: &CrashTuning) -> f32 {
        t.flat_radius + (1.0 - t.flat_radius) * self.pressure
    }

    /// Drag force of a flat at `speed` m/s, N. It builds with speed, so a
    /// flat can always limp away but cannot go fast.
    pub fn drag(&self, t: &CrashTuning, speed: f32) -> f32 {
        t.flat_drag * (1.0 - self.pressure) * (speed.abs() / 20.0).min(1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_shot_tyre_goes_down_and_stays_down() {
        let t = CrashTuning::default();
        let mut y = Tyre::default();
        y.tick(10.0, &t);
        assert_eq!(y.pressure, 1.0, "an unshot tyre holds");
        assert_eq!(y.drag(&t, 30.0), 0.0);
        assert!(y.hit());
        assert!(!y.hit(), "only the first shot punctures");
        y.tick(t.deflate_seconds * 0.5, &t);
        assert!(y.pressure > 0.4 && y.pressure < 0.6, "it deflates over time");
        y.tick(t.deflate_seconds, &t);
        assert_eq!(y.pressure, 0.0);
        assert_eq!(y.grip(&t), t.flat_grip);
        assert_eq!(y.radius(&t), t.flat_radius);
        assert_eq!(y.drag(&t, 30.0), t.flat_drag);
        assert!(y.drag(&t, 2.0) < t.flat_drag * 0.2, "a crawl still moves");
    }

    #[test]
    fn a_scrape_does_nothing() {
        let t = CrashTuning::default();
        assert_eq!(assess(&t, Vehicle::Car, t.min_impact - 0.1), CrashOutcome::default());
    }

    #[test]
    fn a_hard_hit_hurts_more_on_a_bike_and_throws_the_rider() {
        let t = CrashTuning::default();
        let car = assess(&t, Vehicle::Car, 20.0);
        let bike = assess(&t, Vehicle::Bike, 20.0);
        assert!(bike.injury > car.injury && car.injury > 0.0);
        assert!(bike.eject && !car.eject);
    }

    #[test]
    fn glass_needs_a_real_impact_and_only_cars_have_it() {
        let t = CrashTuning::default();
        assert_eq!(assess(&t, Vehicle::Car, t.crack_at).glass_hits, 1);
        assert_eq!(assess(&t, Vehicle::Car, t.shatter_at).glass_hits, 2);
        assert_eq!(assess(&t, Vehicle::Bike, 40.0).glass_hits, 0);
    }

    #[test]
    fn two_hits_clear_the_windshield() {
        let mut g = Glass::default();
        g.hit();
        assert_eq!(g, Glass::Cracked);
        g.hit();
        assert_eq!(g, Glass::Gone);
        g.hit();
        assert_eq!(g, Glass::Gone);
    }

    #[test]
    fn engine_limps_then_dies() {
        let t = CrashTuning::default();
        let mut h = Hull::new(100.0);
        assert_eq!(h.engine_factor(&t), 1.0);
        h.damage(100.0 * (1.0 - t.limp_fraction) + 1.0);
        assert_eq!(h.engine_factor(&t), t.limp_power);
        h.damage(1000.0);
        assert!(h.wrecked());
        assert_eq!(h.engine_factor(&t), 0.0);
    }
}
