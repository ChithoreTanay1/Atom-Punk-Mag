//! NPC detection model. The bridge measures geometry (distance, angle, line
//! of sight); this module decides what the NPC *thinks*.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct AwarenessParams {
    pub view_distance: f32,
    pub view_half_angle_deg: f32,
    /// Inside this range the NPC notices regardless of facing.
    pub sense_radius: f32,
    /// Level gained per second at point-blank, centre of view, fully lit.
    pub base_rate: f32,
    /// Fraction of `base_rate` at the edge of view distance.
    pub far_rate: f32,
    pub crouch_mult: f32,
    pub fast_mult: f32,
    pub peripheral_mult: f32,
    pub decay_rate: f32,
    pub suspicious_at: f32,
    pub search_time: f32,
    pub alarm_rate_mult: f32,
    /// Hearing: loudness radius multiplier for guards.
    pub hearing_mult: f32,
}

impl Default for AwarenessParams {
    fn default() -> Self {
        Self {
            view_distance: 32.0,
            view_half_angle_deg: 55.0,
            sense_radius: 2.2,
            base_rate: 2.6,
            far_rate: 0.12,
            crouch_mult: 0.5,
            fast_mult: 1.5,
            peripheral_mult: 0.45,
            decay_rate: 0.22,
            suspicious_at: 0.3,
            search_time: 14.0,
            alarm_rate_mult: 2.2,
            hearing_mult: 1.0,
        }
    }
}

/// What the NPC can currently see of the player. `None` = not visible.
#[derive(Clone, Copy, Debug)]
pub struct Sighting {
    pub distance: f32,
    /// Angle from the NPC's forward, in degrees.
    pub angle_deg: f32,
    pub crouched: bool,
    pub moving_fast: bool,
    /// 0 = deep shadow, 1 = fully lit.
    pub exposure: f32,
    /// Player is somewhere they shouldn't be, armed, or already known hostile.
    pub hostile: bool,
    pub position: [f32; 3],
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum AlertState {
    Calm,
    Suspicious,
    Searching,
    Hostile,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum AwarenessEvent {
    BecameSuspicious,
    Spotted,
    LostTarget,
    CalmedDown,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Awareness {
    pub level: f32,
    pub state: AlertState,
    pub search_timer: f32,
    pub last_known: Option<[f32; 3]>,
}

impl Default for Awareness {
    fn default() -> Self {
        Self { level: 0.0, state: AlertState::Calm, search_timer: 0.0, last_known: None }
    }
}

impl Awareness {
    /// Can this NPC see a point at `distance` / `angle_deg` at all?
    pub fn in_view(p: &AwarenessParams, distance: f32, angle_deg: f32) -> bool {
        distance < p.sense_radius || (distance < p.view_distance && angle_deg < p.view_half_angle_deg)
    }

    pub fn gain_rate(p: &AwarenessParams, s: &Sighting, alarm: bool) -> f32 {
        if !s.hostile {
            return 0.0;
        }
        if s.distance < p.sense_radius * 0.6 {
            return 50.0; // effectively instant at arm's length
        }
        let t = (s.distance / p.view_distance).clamp(0.0, 1.0);
        let dist_f = 1.0 + (p.far_rate - 1.0) * t.sqrt();
        let ang_f = if s.angle_deg > p.view_half_angle_deg * 0.5 { p.peripheral_mult } else { 1.0 };
        let mut r = p.base_rate * dist_f * ang_f * (0.25 + 0.75 * s.exposure.clamp(0.0, 1.0));
        if s.crouched { r *= p.crouch_mult; }
        if s.moving_fast { r *= p.fast_mult; }
        if alarm { r *= p.alarm_rate_mult; }
        r
    }

    pub fn update(&mut self, p: &AwarenessParams, dt: f32, sight: Option<Sighting>, alarm: bool) -> Option<AwarenessEvent> {
        let before = self.state;
        match sight {
            Some(s) if s.hostile => {
                self.level = (self.level + Self::gain_rate(p, &s, alarm) * dt).min(1.0);
                self.last_known = Some(s.position);
                if self.state == AlertState::Hostile {
                    self.search_timer = p.search_time;
                } else if self.level >= 1.0 {
                    self.state = AlertState::Hostile;
                    self.search_timer = p.search_time;
                } else if self.level >= p.suspicious_at && self.state == AlertState::Calm {
                    self.state = AlertState::Suspicious;
                    self.search_timer = p.search_time * 0.5;
                }
            }
            _ => {
                match self.state {
                    AlertState::Hostile => {
                        // Keep hunting the last known position for a while.
                        self.search_timer -= dt;
                        if self.search_timer < p.search_time * 0.6 {
                            self.state = AlertState::Searching;
                        }
                    }
                    AlertState::Searching | AlertState::Suspicious => {
                        self.search_timer -= dt;
                        self.level = (self.level - p.decay_rate * dt).max(0.0);
                        if self.search_timer <= 0.0 {
                            self.state = AlertState::Calm;
                            self.level = self.level.min(p.suspicious_at * 0.5);
                            self.last_known = None;
                        }
                    }
                    AlertState::Calm => {
                        self.level = (self.level - p.decay_rate * dt).max(0.0);
                    }
                }
            }
        }
        match (before, self.state) {
            (a, b) if a == b => None,
            (_, AlertState::Hostile) => Some(AwarenessEvent::Spotted),
            (AlertState::Calm, AlertState::Suspicious) => Some(AwarenessEvent::BecameSuspicious),
            (AlertState::Hostile, AlertState::Searching) => Some(AwarenessEvent::LostTarget),
            (_, AlertState::Calm) => Some(AwarenessEvent::CalmedDown),
            _ => None,
        }
    }

    /// A noise at `pos` heard from `distance` with source radius `radius`.
    pub fn hear(&mut self, p: &AwarenessParams, pos: [f32; 3], distance: f32, radius: f32) -> bool {
        if distance > radius * p.hearing_mult {
            return false;
        }
        self.last_known = Some(pos);
        match self.state {
            AlertState::Hostile => {}
            _ => {
                self.state = AlertState::Suspicious;
                self.level = self.level.max(p.suspicious_at);
                self.search_timer = p.search_time;
            }
        }
        true
    }

    /// Jump straight to hostile (body found, alarm call, shot at).
    pub fn force_hostile(&mut self, p: &AwarenessParams, pos: Option<[f32; 3]>) {
        self.level = 1.0;
        self.state = AlertState::Hostile;
        self.search_timer = p.search_time;
        if pos.is_some() {
            self.last_known = pos;
        }
    }
}

/// A camera or drone [INVENTED]. It has no suspicion, only a slow fill while a
/// crime stays in frame: seen long enough is recorded. Numbers are data.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct DetectorParams {
    pub view_distance: f32,
    pub view_half_angle_deg: f32,
    /// Fill per second at point-blank; falls to `far_rate` of that at range.
    pub rate: f32,
    pub far_rate: f32,
    pub decay: f32,
    /// Pan: how far either side (deg) and how fast (deg/s).
    pub sweep_deg: f32,
    pub sweep_speed: f32,
    /// Patrol or drift speed for things that fly (m/s).
    pub speed: f32,
}

impl Default for DetectorParams {
    fn default() -> Self {
        Self {
            view_distance: 42.0,
            view_half_angle_deg: 28.0,
            rate: 1.4,
            far_rate: 0.35,
            decay: 0.4,
            sweep_deg: 35.0,
            sweep_speed: 14.0,
            speed: 3.0,
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct Detector {
    pub level: f32,
}

impl Detector {
    pub fn in_view(p: &DetectorParams, distance: f32, angle_deg: f32) -> bool {
        distance < p.view_distance && angle_deg < p.view_half_angle_deg
    }

    /// `crime`: there is a crime in view at this distance. `exposure` 0..1 is
    /// how visible the player is (the press of the crowd lowers it). Returns
    /// true on the moment the crime goes on tape.
    pub fn update(&mut self, p: &DetectorParams, dt: f32, crime: Option<f32>, exposure: f32) -> bool {
        match crime {
            Some(d) => {
                let t = (d / p.view_distance.max(1.0)).clamp(0.0, 1.0);
                let rate = p.rate * (1.0 + (p.far_rate - 1.0) * t) * exposure.clamp(0.1, 1.0);
                self.level += rate * dt;
                if self.level >= 1.0 {
                    self.level = 0.0;
                    return true;
                }
            }
            None => self.level = (self.level - p.decay * dt).max(0.0),
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detector_records_a_crime_it_keeps_seeing_and_forgets_otherwise() {
        let p = DetectorParams { rate: 1.0, far_rate: 0.5, decay: 1.0, ..Default::default() };
        let mut d = Detector::default();
        let mut on_tape = false;
        for _ in 0..30 { on_tape |= d.update(&p, 0.1, Some(1.0), 1.0); }
        assert!(on_tape);
        d.level = 0.5;
        for _ in 0..10 { assert!(!d.update(&p, 0.1, None, 1.0)); }
        assert_eq!(d.level, 0.0);
    }

    #[test]
    fn the_crowd_and_range_slow_a_detector_down() {
        let p = DetectorParams::default();
        let time = |dist: f32, exposure: f32| {
            let mut d = Detector::default();
            let mut t = 0.0;
            while !d.update(&p, 0.01, Some(dist), exposure) && t < 60.0 { t += 0.01; }
            t
        };
        assert!(time(5.0, 1.0) < time(40.0, 1.0));
        assert!(time(5.0, 1.0) < time(5.0, 0.3));
    }

    fn sight(distance: f32, hostile: bool, crouched: bool) -> Sighting {
        Sighting { distance, angle_deg: 5.0, crouched, moving_fast: false, exposure: 1.0, hostile, position: [0.0; 3] }
    }

    #[test]
    fn public_player_never_spotted() {
        let p = AwarenessParams::default();
        let mut a = Awareness::default();
        for _ in 0..600 {
            assert_eq!(a.update(&p, 1.0 / 60.0, Some(sight(5.0, false, false)), false), None);
        }
        assert_eq!(a.state, AlertState::Calm);
    }

    #[test]
    fn trespasser_spotted_faster_close_than_far_and_crouch_helps() {
        let p = AwarenessParams::default();
        let time_to_spot = |d: f32, c: bool| {
            let mut a = Awareness::default();
            let mut t = 0.0;
            while a.state != AlertState::Hostile && t < 60.0 {
                a.update(&p, 0.01, Some(sight(d, true, c)), false);
                t += 0.01;
            }
            t
        };
        assert!(time_to_spot(6.0, false) < time_to_spot(25.0, false));
        assert!(time_to_spot(10.0, false) < time_to_spot(10.0, true));
        assert!(time_to_spot(1.0, false) < 0.05);
    }

    #[test]
    fn hostile_decays_to_search_then_calm() {
        let p = AwarenessParams::default();
        let mut a = Awareness::default();
        a.force_hostile(&p, Some([1.0, 0.0, 1.0]));
        let mut events = vec![];
        for _ in 0..(60 * 40) {
            if let Some(e) = a.update(&p, 1.0 / 60.0, None, false) { events.push(e); }
        }
        assert_eq!(events, vec![AwarenessEvent::LostTarget, AwarenessEvent::CalmedDown]);
        assert_eq!(a.state, AlertState::Calm);
    }

    #[test]
    fn noise_makes_suspicious() {
        let p = AwarenessParams::default();
        let mut a = Awareness::default();
        assert!(!a.hear(&p, [0.0; 3], 30.0, 10.0));
        assert!(a.hear(&p, [3.0, 0.0, 0.0], 5.0, 10.0));
        assert_eq!(a.state, AlertState::Suspicious);
        assert_eq!(a.last_known, Some([3.0, 0.0, 0.0]));
    }
}
