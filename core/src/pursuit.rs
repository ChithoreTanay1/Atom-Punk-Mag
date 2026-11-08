//! The chase after the kill [INVENTED]. How hard Avekṣā comes after you depends
//! on how the killing went; it ends at the safehouse yard, or once you have been
//! out of everyone's sight for long enough.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct PursuitParams {
    /// Unseen for this long and they give up (s).
    pub lose_seconds: f32,
    /// Pursuers while nothing has been recorded: none, the kill stays clean.
    pub bikes_clean: u32,
    pub drones_clean: u32,
    /// Pursuers once a crime is on tape.
    pub bikes_recorded: u32,
    pub drones_recorded: u32,
    /// Pursuers after a general alarm.
    pub bikes_alarm: u32,
    pub drones_alarm: u32,
    /// A pursuer sees you within this range with a clear line (m).
    pub sight_range: f32,
    pub bike_speed: f32,
    pub drone_speed: f32,
    /// Pursuers spawn this far behind you (m).
    pub spawn_behind: f32,
    pub shot_range: f32,
    pub shot_interval: f32,
    pub shot_damage: f32,
    pub shot_hit_chance: f32,
    /// First chunk of the A1 past the temple gate, and the safehouse yard's.
    pub road_first_chunk: i32,
    pub safehouse_chunk: i32,
}

impl Default for PursuitParams {
    fn default() -> Self {
        Self {
            lose_seconds: 14.0,
            bikes_clean: 0,
            drones_clean: 0,
            bikes_recorded: 1,
            drones_recorded: 1,
            bikes_alarm: 3,
            drones_alarm: 2,
            sight_range: 90.0,
            bike_speed: 44.0,
            drone_speed: 34.0,
            spawn_behind: 70.0,
            shot_range: 45.0,
            shot_interval: 1.3,
            shot_damage: 7.0,
            shot_hit_chance: 0.28,
            road_first_chunk: 2,
            safehouse_chunk: 14,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum PursuitState {
    Idle,
    Active,
    /// They gave up.
    Lost,
    /// Reached the safehouse yard.
    Reached,
}

#[derive(Clone, Debug)]
pub struct Pursuit {
    pub params: PursuitParams,
    pub state: PursuitState,
    /// Seconds since anyone last saw you.
    pub unseen: f32,
    pub bikes: u32,
    pub drones: u32,
}

impl Pursuit {
    pub fn new(params: PursuitParams) -> Self {
        Self { params, state: PursuitState::Idle, unseen: 0.0, bikes: 0, drones: 0 }
    }

    /// Start the chase. Returns (bikes, drones); (0, 0) means no one is coming.
    pub fn start(&mut self, recorded: bool, alarm: bool) -> (u32, u32) {
        if self.state != PursuitState::Idle {
            return (self.bikes, self.drones);
        }
        let p = &self.params;
        let (b, d) = if alarm {
            (p.bikes_alarm, p.drones_alarm)
        } else if recorded {
            (p.bikes_recorded, p.drones_recorded)
        } else {
            (p.bikes_clean, p.drones_clean)
        };
        self.bikes = b;
        self.drones = d;
        if b + d > 0 {
            self.state = PursuitState::Active;
        }
        (b, d)
    }

    /// `seen`: did any pursuer have you this frame? Returns the new state.
    pub fn tick(&mut self, dt: f32, seen: bool) -> PursuitState {
        if self.state == PursuitState::Active {
            self.unseen = if seen { 0.0 } else { self.unseen + dt };
            if self.unseen >= self.params.lose_seconds {
                self.state = PursuitState::Lost;
            }
        }
        self.state
    }

    /// Reached the yard: the end of it, whatever was behind you.
    pub fn reach_safehouse(&mut self) {
        self.state = PursuitState::Reached;
    }

    pub fn active(&self) -> bool {
        self.state == PursuitState::Active
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_clean_kill_brings_no_one() {
        let mut p = Pursuit::new(PursuitParams::default());
        assert_eq!(p.start(false, false), (0, 0));
        assert_eq!(p.state, PursuitState::Idle);
    }

    #[test]
    fn the_worse_it_went_the_more_come() {
        let d = PursuitParams::default();
        let mut p = Pursuit::new(d.clone());
        assert_eq!(p.start(true, false), (d.bikes_recorded, d.drones_recorded));
        let mut p = Pursuit::new(d.clone());
        assert_eq!(p.start(true, true), (d.bikes_alarm, d.drones_alarm));
        assert!(d.bikes_alarm > d.bikes_recorded);
    }

    #[test]
    fn staying_out_of_sight_loses_them_and_being_seen_resets_it() {
        let mut p = Pursuit::new(PursuitParams { lose_seconds: 10.0, ..Default::default() });
        p.start(true, true);
        for _ in 0..9 { assert_eq!(p.tick(1.0, false), PursuitState::Active); }
        assert_eq!(p.tick(1.0, true), PursuitState::Active);
        assert_eq!(p.unseen, 0.0);
        for _ in 0..9 { p.tick(1.0, false); }
        assert_eq!(p.tick(1.0, false), PursuitState::Lost);
    }

    #[test]
    fn the_safehouse_ends_it() {
        let mut p = Pursuit::new(PursuitParams::default());
        p.start(true, true);
        p.reach_safehouse();
        assert_eq!(p.tick(1.0, true), PursuitState::Reached);
        assert!(!p.active());
    }
}
