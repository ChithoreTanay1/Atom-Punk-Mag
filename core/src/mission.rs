//! Field mission state: the sim clock, the governor's routine, overheard
//! lines and intel, alarm, kill / poison / frame paths, and the outcome.
//! The level reports facts ("governor reached tea table", "player heard line
//! x") and reads back events and objectives.

use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

use crate::content::{Activity, Content, GadgetKind, Method, MissionDef};

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
pub enum TargetStatus {
    Alive,
    /// Poisoned; seconds left.
    Dying(f32),
    Dead,
    Arrested,
    Escaped,
}

#[derive(Clone, Debug, PartialEq)]
pub enum MissionEvent {
    /// Governor's routine moved on. Level should route him to `location`.
    Activity { activity: Activity, location: String },
    /// A line is being spoken by `speaker` (governor unless stated).
    Line { id: String, speaker: String, text: String },
    IntelGained { id: String, title: String },
    AlarmRaised,
    TargetDown { method: Method },
    TargetDying,
    Message(String),
    /// Mission is over; show debrief.
    Finished { method: Method },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct GadgetStock {
    pub id: String,
    pub kind: GadgetKind,
    pub count: u32,
}

#[derive(Clone, Debug)]
pub struct Mission {
    pub def: MissionDef,
    pub clock: f32,
    pub entry: Option<usize>,
    line_queue: Vec<String>,
    line_timer: f32,
    pub line_interval: f32,
    pub intel: BTreeSet<String>,
    pub alarm: bool,
    pub target: TargetStatus,
    pub removal: Option<Method>,
    pub tea_poisoned: bool,
    pub tea_drunk: bool,
    pub forgery_planted: bool,
    pub telex_sent: bool,
    pub player_health: f32,
    pub player_max_health: f32,
    pub ammo_mag: u32,
    pub ammo_reserve: u32,
    pub mag_size: u32,
    pub gadgets: Vec<GadgetStock>,
    pub kills: u32,
    pub bodies_found: u32,
    pub finished: Option<Method>,
    pub extra_guards: u32,
    events: Vec<MissionEvent>,
}

impl Mission {
    pub fn new(content: &Content, mission_id: &str, target_paranoia: f32) -> Option<Self> {
        let def = content.mission(mission_id)?.clone();
        let weapon = content.weapon(&def.loadout_weapon)?;
        let gadgets = def
            .loadout_gadgets
            .iter()
            .filter_map(|g| content.gadget(g))
            .map(|g| GadgetStock { id: g.id.clone(), kind: g.kind, count: g.count })
            .collect();
        let extra_guards = ((target_paranoia / 25.0).floor() * def.guards_per_paranoia).max(0.0) as u32;
        Some(Self {
            clock: def.start_minute,
            entry: None,
            line_queue: vec![],
            line_timer: 1.5,
            line_interval: 5.5,
            intel: BTreeSet::new(),
            alarm: false,
            target: TargetStatus::Alive,
            removal: None,
            tea_poisoned: false,
            tea_drunk: false,
            forgery_planted: false,
            telex_sent: false,
            player_health: def.player_health,
            player_max_health: def.player_health,
            ammo_mag: weapon.mag_size,
            ammo_reserve: weapon.reserve,
            mag_size: weapon.mag_size,
            gadgets,
            kills: 0,
            bodies_found: 0,
            finished: None,
            extra_guards,
            events: vec![],
            def,
        })
    }

    pub fn drain_events(&mut self) -> Vec<MissionEvent> {
        std::mem::take(&mut self.events)
    }

    pub fn clock_text(&self) -> String {
        let m = self.clock.max(0.0) as u32;
        format!("{:02}:{:02}", (m / 60) % 24, m % 60)
    }

    pub fn current_activity(&self) -> Option<Activity> {
        if self.alarm { return None; }
        self.entry.map(|i| self.def.schedule[i].activity)
    }

    /// Advance by `dt` real seconds.
    pub fn tick(&mut self, dt: f32) {
        if self.finished.is_some() { return; }
        self.clock += dt * self.def.time_scale;

        // Routine progression (suspended under alarm: he hides).
        if !self.alarm && self.target == TargetStatus::Alive {
            let idx = self.def.schedule.iter().rposition(|e| e.at <= self.clock);
            if idx.is_some() && idx != self.entry {
                self.entry = idx;
                let e = &self.def.schedule[idx.unwrap()];
                self.line_queue = e.lines.iter().rev().cloned().collect();
                self.line_timer = 2.0;
                self.events.push(MissionEvent::Activity { activity: e.activity, location: e.location.clone() });
            }
            self.line_timer -= dt;
            if self.line_timer <= 0.0 {
                if let Some(id) = self.line_queue.pop() {
                    if let Some(l) = self.def.lines.iter().find(|l| l.id == id) {
                        self.events.push(MissionEvent::Line { id: l.id.clone(), speaker: l.speaker.clone(), text: l.text.clone() });
                    }
                }
                self.line_timer = self.line_interval;
            }
        }

        if let TargetStatus::Dying(t) = self.target {
            let t = t - dt;
            if t <= 0.0 {
                self.target = TargetStatus::Dead;
                self.set_removed(Method::Poison);
            } else {
                self.target = TargetStatus::Dying(t);
            }
        }
    }

    fn set_removed(&mut self, m: Method) {
        if self.removal.is_none() {
            self.removal = Some(m);
            self.events.push(MissionEvent::TargetDown { method: m });
            self.events.push(MissionEvent::Message("Target removed. Exfiltrate: leave the compound.".into()));
        }
    }

    /// The level heard a line: player in earshot, or a tape bug in range.
    pub fn hear_line(&mut self, line_id: &str) {
        let Some(l) = self.def.lines.iter().find(|l| l.id == line_id) else { return };
        if let Some(intel) = &l.intel {
            if self.intel.insert(intel.clone()) {
                let title = self.def.intel.iter().find(|i| &i.id == intel).map(|i| i.title.clone()).unwrap_or_default();
                self.events.push(MissionEvent::IntelGained { id: intel.clone(), title });
            }
        }
    }

    pub fn gadget_count(&self, id: &str) -> u32 {
        self.gadgets.iter().find(|g| g.id == id).map(|g| g.count).unwrap_or(0)
    }

    pub fn consume_gadget(&mut self, id: &str) -> bool {
        match self.gadgets.iter_mut().find(|g| g.id == id) {
            Some(g) if g.count > 0 => { g.count -= 1; true }
            _ => false,
        }
    }

    pub fn raise_alarm(&mut self) {
        if !self.alarm {
            self.alarm = true;
            self.line_queue.clear();
            self.events.push(MissionEvent::AlarmRaised);
            self.events.push(MissionEvent::Message("GENERAL ALARM. The governor is moving to his shelter.".into()));
        }
    }

    // ---- Poison path -------------------------------------------------------

    pub fn poison_tea(&mut self, gadget_id: &str) -> Result<(), &'static str> {
        if self.tea_drunk { return Err("The tea has already been served."); }
        if self.tea_poisoned { return Err("The tea is already dosed."); }
        if !self.consume_gadget(gadget_id) { return Err("No ampoules left."); }
        self.tea_poisoned = true;
        self.events.push(MissionEvent::Message("Tea service dosed. Wait for the governor's tea.".into()));
        Ok(())
    }

    /// Level reports the governor has sat down to tea.
    pub fn governor_drinks_tea(&mut self) {
        if self.tea_drunk || self.target != TargetStatus::Alive { return; }
        self.tea_drunk = true;
        if self.tea_poisoned {
            self.target = TargetStatus::Dying(self.def.poison_delay);
            self.events.push(MissionEvent::TargetDying);
        }
    }

    // ---- Frame path --------------------------------------------------------

    pub fn forgery_ready(&self) -> bool {
        self.intel.contains(&self.def.forgery_requires)
    }

    pub fn plant_forgery(&mut self, gadget_id: &str) -> Result<(), &'static str> {
        if self.forgery_planted { return Err("The dispatch is already in his tray."); }
        if !self.forgery_ready() {
            return Err("You don't know whose seal to forge. Overhear the governor first.");
        }
        if !self.consume_gadget(gadget_id) { return Err("No forged dispatch left."); }
        self.forgery_planted = true;
        self.events.push(MissionEvent::Message("Forged dispatch planted. Tip off the capital from his telex.".into()));
        Ok(())
    }

    pub fn send_telex(&mut self) -> Result<(), &'static str> {
        if self.telex_sent { return Err("The capital has already been informed."); }
        if !self.forgery_planted { return Err("Nothing incriminating to report yet. Plant the dispatch."); }
        if self.target != TargetStatus::Alive { return Err("The governor is no longer a concern."); }
        self.telex_sent = true;
        self.target = TargetStatus::Arrested;
        self.events.push(MissionEvent::Message("TELEX SENT TO PATALIPUTRA. The king's inspectors are on their way.".into()));
        self.set_removed(Method::Frame);
        Ok(())
    }

    // ---- Direct path -------------------------------------------------------

    pub fn governor_killed(&mut self) {
        if matches!(self.target, TargetStatus::Alive | TargetStatus::Dying(_)) {
            self.target = TargetStatus::Dead;
            self.kills += 1;
            self.set_removed(if self.alarm { Method::LoudKill } else { Method::QuietKill });
        }
    }

    pub fn governor_escaped(&mut self) {
        if self.target == TargetStatus::Alive {
            self.target = TargetStatus::Escaped;
            self.events.push(MissionEvent::Message("The governor's car has left the compound.".into()));
            self.finish(Method::Failed);
        }
    }

    pub fn body_found(&mut self) {
        self.bodies_found += 1;
        self.raise_alarm();
    }

    pub fn damage_player(&mut self, amount: f32) -> bool {
        if self.finished.is_some() { return false; }
        self.player_health = (self.player_health - amount).max(0.0);
        if self.player_health <= 0.0 {
            self.events.push(MissionEvent::Message("Agent down. The network loses a hand.".into()));
            self.finish(Method::Failed);
            return true;
        }
        false
    }

    pub fn heal_player(&mut self, amount: f32) {
        self.player_health = (self.player_health + amount).min(self.player_max_health);
    }

    pub fn player_exfiltrated(&mut self) {
        if let Some(m) = self.removal {
            self.finish(m);
        }
    }

    pub fn abort(&mut self) {
        self.finish(Method::Failed);
    }

    fn finish(&mut self, m: Method) {
        if self.finished.is_none() {
            self.finished = Some(m);
            self.events.push(MissionEvent::Finished { method: m });
        }
    }

    // ---- Weapon ammo -------------------------------------------------------

    pub fn try_fire(&mut self) -> bool {
        if self.ammo_mag > 0 { self.ammo_mag -= 1; true } else { false }
    }

    pub fn reload(&mut self) -> bool {
        let need = self.mag_size - self.ammo_mag;
        if need == 0 || self.ammo_reserve == 0 { return false; }
        let take = need.min(self.ammo_reserve);
        self.ammo_reserve -= take;
        self.ammo_mag += take;
        true
    }

    // ---- HUD ---------------------------------------------------------------

    pub fn objectives(&self) -> Vec<String> {
        let mut out = vec![];
        if self.removal.is_some() {
            out.push("Exfiltrate: leave through the south boulevard or drive away".into());
            return out;
        }
        out.push("Remove the governor before he departs".into());
        if let Some(depart) = self.def.schedule.iter().find(|e| e.activity == Activity::Depart) {
            if self.intel.contains(&self.def.depart_intel) {
                out.push(format!("He leaves at {:02}:{:02}", depart.at as u32 / 60, depart.at as u32 % 60));
            }
        }
        if self.tea_poisoned && !self.tea_drunk { out.push("Tea is dosed. Let him drink.".into()); }
        if self.forgery_planted && !self.telex_sent { out.push("Send the tip-off from the office telex".into()); }
        if !self.forgery_planted && self.forgery_ready() { out.push("Optional: plant the forged dispatch in his office".into()); }
        if self.alarm { out.push("ALARM: he is sheltering in the strongroom".into()); }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn content() -> Content {
        Content::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../data")).unwrap()
    }

    fn first_mission(c: &Content) -> Mission {
        Mission::new(c, &c.missions[0].id, 0.0).unwrap()
    }

    #[test]
    fn routine_advances_and_speaks() {
        let c = content();
        let mut m = first_mission(&c);
        let mut acts = 0;
        let mut lines = 0;
        for _ in 0..(60 * 300) {
            m.tick(1.0 / 60.0);
            for e in m.drain_events() {
                match e {
                    MissionEvent::Activity { .. } => acts += 1,
                    MissionEvent::Line { .. } => lines += 1,
                    _ => {}
                }
            }
        }
        assert!(acts >= 2, "activities {acts}");
        assert!(lines >= 2, "lines {lines}");
    }

    #[test]
    fn poison_path() {
        let c = content();
        let mut m = first_mission(&c);
        let poison = m.gadgets.iter().find(|g| g.kind == GadgetKind::Poison).unwrap().id.clone();
        m.poison_tea(&poison).unwrap();
        assert!(m.poison_tea(&poison).is_err());
        m.governor_drinks_tea();
        assert!(matches!(m.target, TargetStatus::Dying(_)));
        for _ in 0..(60 * 120) { m.tick(1.0 / 60.0); }
        assert_eq!(m.target, TargetStatus::Dead);
        assert_eq!(m.removal, Some(Method::Poison));
        m.player_exfiltrated();
        assert_eq!(m.finished, Some(Method::Poison));
    }

    #[test]
    fn frame_needs_intel() {
        let c = content();
        let mut m = first_mission(&c);
        let forg = m.gadgets.iter().find(|g| g.kind == GadgetKind::Forgery).unwrap().id.clone();
        assert!(m.plant_forgery(&forg).is_err());
        assert!(m.send_telex().is_err());
        let line = m.def.lines.iter().find(|l| l.intel.as_deref() == Some(m.def.forgery_requires.as_str())).unwrap().id.clone();
        m.hear_line(&line);
        m.plant_forgery(&forg).unwrap();
        m.send_telex().unwrap();
        assert_eq!(m.removal, Some(Method::Frame));
    }

    #[test]
    fn alarm_makes_kills_loud_and_death_fails() {
        let c = content();
        let mut m = first_mission(&c);
        m.raise_alarm();
        m.governor_killed();
        assert_eq!(m.removal, Some(Method::LoudKill));
        let mut m2 = first_mission(&c);
        assert!(m2.damage_player(1000.0));
        assert_eq!(m2.finished, Some(Method::Failed));
    }

    #[test]
    fn ammo() {
        let c = content();
        let mut m = first_mission(&c);
        let mag = m.ammo_mag;
        for _ in 0..mag { assert!(m.try_fire()); }
        assert!(!m.try_fire());
        assert!(m.reload());
        assert_eq!(m.ammo_mag, mag);
    }
}
