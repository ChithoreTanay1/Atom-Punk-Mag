//! Avekṣā Corp's eyes [INVENTED]. Every gantry camera, tethered balloon and
//! saucer drone is a feed patched into one monitoring room. The bridge measures
//! geometry (`crate::awareness::Detector`); this module owns what the room knows:
//! which feeds are live, how long a zone has been dark, what is on tape.
//! Design source: Arthashastra Bk 1 (a state's spy network), used as DESIGN,
//! not as Nanda-era fact.

use serde::{Deserialize, Serialize};

use crate::awareness::DetectorParams;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct SurveillanceParams {
    /// Seconds before the room notices a zone showing a looped tape.
    pub loop_notice_s: f32,
    /// A feed pulled at its junction box (reached with the Garuda Line).
    pub pull_notice_s: f32,
    /// A zone whose power has been cut: noticed faster.
    pub power_notice_s: f32,
    /// A camera jammed by a Static Lure.
    pub jam_notice_s: f32,
    /// An unanswered check-in once the operators are gone.
    pub unstaffed_notice_s: f32,
    /// Heat from each crime on tape.
    pub record_heat: f32,
    /// Heat when a killing is on tape.
    pub kill_record_heat: f32,
    /// Heat when a feed is destroyed (always an immediate alert).
    pub destroyed_heat: f32,
    /// Crimes on tape before the room calls a general alarm.
    pub alarm_after_records: u32,
    /// How long a forged dispatch keeps a sector's patrols away.
    pub reassign_s: f32,
    pub gantry: DetectorParams,
    pub balloon: DetectorParams,
    pub drone: DetectorParams,
}

impl Default for SurveillanceParams {
    fn default() -> Self {
        Self {
            loop_notice_s: 240.0,
            pull_notice_s: 150.0,
            power_notice_s: 75.0,
            jam_notice_s: 45.0,
            unstaffed_notice_s: 120.0,
            record_heat: 3.0,
            kill_record_heat: 10.0,
            destroyed_heat: 4.0,
            alarm_after_records: 3,
            reassign_s: 90.0,
            gantry: DetectorParams::default(),
            balloon: DetectorParams::default(),
            drone: DetectorParams::default(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FeedState {
    Live,
    /// Monitors show a looped tape of an empty corridor.
    Looped,
    /// Static Lure: comes back on its own after the seconds left.
    Jammed(f32),
    /// Breaker pulled for the whole zone.
    Unpowered,
    /// Pulled at the junction box.
    Pulled,
    /// Shot down. An immediate alert, and it stays dead.
    Destroyed,
}

impl FeedState {
    /// Seconds the room takes to notice this kind of dead feed.
    fn notice(self, p: &SurveillanceParams) -> Option<f32> {
        match self {
            FeedState::Live | FeedState::Destroyed => None,
            FeedState::Looped => Some(p.loop_notice_s),
            FeedState::Jammed(_) => Some(p.jam_notice_s),
            FeedState::Unpowered => Some(p.power_notice_s),
            FeedState::Pulled => Some(p.pull_notice_s),
        }
    }
}

#[derive(Clone, Debug)]
pub struct Feed {
    pub id: String,
    pub zone: String,
    pub state: FeedState,
}

#[derive(Clone, Debug, PartialEq)]
pub enum SurveillanceEvent {
    /// A feed went up or down; the level updates the eye.
    FeedChanged { id: String, live: bool },
    /// The room has noticed a dark zone and is sending guards.
    Noticed { zone: String },
    /// A feed was destroyed: immediate alert.
    Destroyed { id: String, zone: String },
    /// A crime is on tape.
    Recorded { id: String, zone: String, kill: bool },
    /// Crimes on tape reached the limit.
    RecordAlarm,
    Reassigned { zone: String },
    ReassignEnded { zone: String },
}

#[derive(Clone, Debug, Default)]
struct ZoneWatch {
    zone: String,
    dark_for: f32,
    noticed: bool,
    reassigned: f32,
}

#[derive(Clone, Debug)]
pub struct Surveillance {
    pub params: SurveillanceParams,
    pub feeds: Vec<Feed>,
    zones: Vec<ZoneWatch>,
    /// Number of crimes on tape.
    pub recorded: u32,
    /// Heat the tapes will cost the network when the mission is over.
    pub heat: f32,
    pub staffed: bool,
    unstaffed_for: f32,
    unstaffed_reported: bool,
    events: Vec<SurveillanceEvent>,
}

impl Surveillance {
    pub fn new(params: SurveillanceParams) -> Self {
        Self {
            params,
            feeds: vec![],
            zones: vec![],
            recorded: 0,
            heat: 0.0,
            staffed: true,
            unstaffed_for: 0.0,
            unstaffed_reported: false,
            events: vec![],
        }
    }

    pub fn add_feed(&mut self, id: &str, zone: &str) {
        self.feeds.push(Feed { id: id.into(), zone: zone.into(), state: FeedState::Live });
        if !self.zones.iter().any(|z| z.zone == zone) {
            self.zones.push(ZoneWatch { zone: zone.into(), ..Default::default() });
        }
    }

    pub fn drain_events(&mut self) -> Vec<SurveillanceEvent> {
        std::mem::take(&mut self.events)
    }

    pub fn feed_live(&self, id: &str) -> bool {
        self.feeds.iter().any(|f| f.id == id && f.state == FeedState::Live)
    }

    pub fn live_count(&self) -> usize {
        self.feeds.iter().filter(|f| f.state == FeedState::Live).count()
    }

    fn set_state(&mut self, f: impl Fn(&Feed) -> bool, state: FeedState) {
        for feed in self.feeds.iter_mut().filter(|x| f(x)) {
            if feed.state == FeedState::Destroyed { continue; }
            let was = feed.state == FeedState::Live;
            let now = state == FeedState::Live;
            feed.state = state;
            if was != now {
                self.events.push(SurveillanceEvent::FeedChanged { id: feed.id.clone(), live: now });
            }
        }
    }

    /// Murmur Cassette in the zone's recorder: every feed shows an empty corridor.
    pub fn loop_zone(&mut self, zone: &str) {
        self.set_state(|f| f.zone == zone, FeedState::Looped);
    }

    /// Breaker panel. Toggles; returns true if the zone is now dark.
    pub fn toggle_power(&mut self, zone: &str) -> bool {
        let dark = self.feeds.iter().any(|f| f.zone == zone && f.state == FeedState::Unpowered);
        if dark {
            self.restore_zone(zone);
            false
        } else {
            self.set_state(|f| f.zone == zone, FeedState::Unpowered);
            true
        }
    }

    /// Put a zone back on the air and clear its dark timer.
    pub fn restore_zone(&mut self, zone: &str) {
        self.set_state(|f| f.zone == zone, FeedState::Live);
        if let Some(z) = self.zones.iter_mut().find(|z| z.zone == zone) {
            z.dark_for = 0.0;
            z.noticed = false;
        }
    }

    /// Pull a single feed at its junction box.
    pub fn pull(&mut self, id: &str) {
        self.set_state(|f| f.id == id, FeedState::Pulled);
    }

    /// Static Lure: only live feeds can be jammed.
    pub fn jam(&mut self, id: &str, secs: f32) {
        if self.feed_live(id) {
            self.set_state(|f| f.id == id, FeedState::Jammed(secs));
        }
    }

    /// Shot down. Louder than any other way of closing an eye.
    pub fn destroy(&mut self, id: &str) {
        let Some(feed) = self.feeds.iter_mut().find(|f| f.id == id) else { return };
        if feed.state == FeedState::Destroyed { return; }
        let zone = feed.zone.clone();
        feed.state = FeedState::Destroyed;
        self.heat += self.params.destroyed_heat;
        self.events.push(SurveillanceEvent::FeedChanged { id: id.into(), live: false });
        self.events.push(SurveillanceEvent::Destroyed { id: id.into(), zone });
    }

    /// A live feed saw a crime. Returns false if nothing is recording.
    pub fn record(&mut self, id: &str, kill: bool) -> bool {
        let Some(feed) = self.feeds.iter().find(|f| f.id == id && f.state == FeedState::Live) else { return false };
        let zone = feed.zone.clone();
        self.recorded += 1;
        self.heat += if kill { self.params.kill_record_heat } else { self.params.record_heat };
        self.events.push(SurveillanceEvent::Recorded { id: id.into(), zone, kill });
        if kill || self.recorded == self.params.alarm_after_records {
            self.events.push(SurveillanceEvent::RecordAlarm);
        }
        true
    }

    /// Forged Dispatch: this sector's patrols are ordered elsewhere for a while.
    pub fn reassign(&mut self, zone: &str) {
        if let Some(z) = self.zones.iter_mut().find(|z| z.zone == zone) {
            z.reassigned = self.params.reassign_s;
            self.events.push(SurveillanceEvent::Reassigned { zone: zone.into() });
        }
    }

    /// The monitoring room's operators are dead or gone.
    pub fn set_staffed(&mut self, staffed: bool) {
        self.staffed = staffed;
    }

    pub fn tick(&mut self, dt: f32) {
        // Jams wear off by themselves.
        let mut back = vec![];
        for f in &mut self.feeds {
            if let FeedState::Jammed(t) = f.state {
                let t = t - dt;
                if t <= 0.0 {
                    f.state = FeedState::Live;
                    back.push(f.id.clone());
                } else {
                    f.state = FeedState::Jammed(t);
                }
            }
        }
        for id in back {
            self.events.push(SurveillanceEvent::FeedChanged { id, live: true });
        }
        if !self.staffed {
            self.unstaffed_for += dt;
            if self.unstaffed_for >= self.params.unstaffed_notice_s && !self.unstaffed_reported {
                self.unstaffed_reported = true;
                self.events.push(SurveillanceEvent::Noticed { zone: "room".into() });
            }
        }
        for i in 0..self.zones.len() {
            let name = self.zones[i].zone.clone();
            let limit = self.dark_limit(&name);
            let z = &mut self.zones[i];
            if z.reassigned > 0.0 {
                z.reassigned -= dt;
                if z.reassigned <= 0.0 {
                    self.events.push(SurveillanceEvent::ReassignEnded { zone: name.clone() });
                }
            }
            let z = &mut self.zones[i];
            match limit {
                // The dark timer only runs while someone is watching the wall.
                Some(l) if self.staffed => {
                    z.dark_for += dt;
                    if z.dark_for >= l && !z.noticed {
                        z.noticed = true;
                        self.events.push(SurveillanceEvent::Noticed { zone: name });
                    }
                }
                Some(_) => {}
                None => {
                    z.dark_for = 0.0;
                    z.noticed = false;
                }
            }
        }
    }

    /// The soonest a zone's dead feeds get noticed, if any feed is dead.
    fn dark_limit(&self, zone: &str) -> Option<f32> {
        self.feeds
            .iter()
            .filter(|f| f.zone == zone)
            .filter_map(|f| f.state.notice(&self.params))
            .fold(None, |m: Option<f32>, n| Some(m.map_or(n, |x| x.min(n))))
    }

    /// (zone, seconds left) of the dark zone closest to being noticed.
    pub fn next_notice(&self) -> Option<(String, f32)> {
        self.zones
            .iter()
            .filter(|z| !z.noticed)
            .filter_map(|z| self.dark_limit(&z.zone).map(|l| (z.zone.clone(), (l - z.dark_for).max(0.0))))
            .min_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
    }

    pub fn zone_reassigned(&self, zone: &str) -> bool {
        self.zones.iter().any(|z| z.zone == zone && z.reassigned > 0.0)
    }

    pub fn zone_dark(&self, zone: &str) -> bool {
        self.feeds.iter().any(|f| f.zone == zone && f.state != FeedState::Live)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn room() -> Surveillance {
        let mut s = Surveillance::new(SurveillanceParams {
            loop_notice_s: 100.0,
            power_notice_s: 20.0,
            pull_notice_s: 60.0,
            jam_notice_s: 30.0,
            unstaffed_notice_s: 50.0,
            alarm_after_records: 2,
            ..Default::default()
        });
        s.add_feed("a", "terrace");
        s.add_feed("b", "terrace");
        s.add_feed("c", "forecourt");
        s
    }

    fn run(s: &mut Surveillance, secs: f32) -> Vec<SurveillanceEvent> {
        let mut out = vec![];
        let mut t = 0.0;
        while t < secs {
            s.tick(0.5);
            out.extend(s.drain_events());
            t += 0.5;
        }
        out
    }

    fn noticed(ev: &[SurveillanceEvent], zone: &str) -> bool {
        ev.iter().any(|e| matches!(e, SurveillanceEvent::Noticed { zone: z } if z == zone))
    }

    #[test]
    fn looped_zone_is_noticed_after_its_timer_and_reset_clears_it() {
        let mut s = room();
        s.loop_zone("terrace");
        assert!(!s.feed_live("a"));
        assert!(s.feed_live("c"));
        assert!(!noticed(&run(&mut s, 90.0), "terrace"));
        let (zone, left) = s.next_notice().unwrap();
        assert_eq!(zone, "terrace");
        assert!(left <= 10.0);
        s.restore_zone("terrace");
        assert!(s.feed_live("a"));
        assert!(s.next_notice().is_none());
        // The clock starts over: a second loop gets the full time again.
        s.loop_zone("terrace");
        assert!(!noticed(&run(&mut s, 90.0), "terrace"));
        assert!(noticed(&run(&mut s, 11.0), "terrace"));
    }

    #[test]
    fn power_cut_is_noticed_faster_than_a_tape() {
        let mut s = room();
        assert!(s.toggle_power("terrace"));
        assert!(noticed(&run(&mut s, 21.0), "terrace"));
        assert!(!s.toggle_power("terrace"));
        assert!(s.feed_live("b"));
    }

    #[test]
    fn destroyed_is_immediate_and_stays_dead() {
        let mut s = room();
        s.destroy("c");
        let ev = s.drain_events();
        assert!(ev.iter().any(|e| matches!(e, SurveillanceEvent::Destroyed { .. })));
        s.restore_zone("forecourt");
        assert!(!s.feed_live("c"));
        assert!(s.heat > 0.0);
    }

    #[test]
    fn jam_wears_off_without_being_noticed() {
        let mut s = room();
        s.jam("a", 9.0);
        assert!(!s.feed_live("a"));
        let ev = run(&mut s, 10.0);
        assert!(s.feed_live("a"));
        assert!(!noticed(&ev, "terrace"));
    }

    #[test]
    fn only_live_feeds_record_and_records_reach_an_alarm() {
        let mut s = room();
        s.loop_zone("forecourt");
        assert!(!s.record("c", false));
        assert_eq!(s.recorded, 0);
        assert!(s.record("a", false));
        assert!(s.drain_events().iter().all(|e| *e != SurveillanceEvent::RecordAlarm));
        assert!(s.record("b", false));
        assert!(s.drain_events().contains(&SurveillanceEvent::RecordAlarm));
        assert!(s.heat > 0.0);
    }

    #[test]
    fn a_recorded_kill_alarms_at_once() {
        let mut s = room();
        assert!(s.record("a", true));
        assert!(s.drain_events().contains(&SurveillanceEvent::RecordAlarm));
    }

    #[test]
    fn empty_room_stops_watching_but_misses_its_check_in() {
        let mut s = room();
        s.loop_zone("terrace");
        s.set_staffed(false);
        let ev = run(&mut s, 45.0);
        assert!(!noticed(&ev, "terrace"));
        assert!(!noticed(&ev, "room"));
        assert!(noticed(&run(&mut s, 6.0), "room"));
    }

    #[test]
    fn forged_dispatch_clears_a_sector_for_a_while() {
        let mut s = room();
        s.reassign("terrace");
        assert!(s.zone_reassigned("terrace"));
        let secs = s.params.reassign_s + 1.0;
        let ev = run(&mut s, secs);
        assert!(!s.zone_reassigned("terrace"));
        assert!(ev.contains(&SurveillanceEvent::ReassignEnded { zone: "terrace".into() }));
    }
}
