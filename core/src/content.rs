//! Data-driven content definitions. Every weapon, gadget, governor, mission,
//! rumor, operation and event is a RON file under `data/`. Nothing here is
//! hard-coded content; these are only the shapes.

use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::{read_ron, LoadError};

/// Lore provenance tag, mirrors LORE.md.
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum Tag {
    Hist,
    Trad,
    #[default]
    Invented,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WeaponDef {
    pub id: String,
    pub name: String,
    pub tag: Tag,
    pub description: String,
    /// Real-world reference the silhouette is drawn from (design note only).
    pub silhouette_ref: String,
    pub damage: f32,
    pub headshot_mult: f32,
    pub range: f32,
    pub falloff_start: f32,
    pub falloff_min: f32,
    pub rpm: f32,
    pub mag_size: u32,
    pub reserve: u32,
    pub reload_time: f32,
    pub spread_deg: f32,
    pub ads_spread_deg: f32,
    pub recoil_pitch_deg: f32,
    pub recoil_yaw_deg: f32,
    pub noise_radius: f32,
    pub modes: Vec<FireMode>,
    /// Gun (hitscan), Melee (knife: slash, and throws from the magazine),
    /// Grapple (rope line that pulls the player to a surface).
    #[serde(default)]
    pub kind: WeaponKind,
    /// Suppressed: quiet report, small flash, no tracer.
    #[serde(default)]
    pub suppressed: bool,
    /// Melee reach (m) for knives; grapple reach is `range`.
    #[serde(default)]
    pub reach: f32,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum WeaponKind {
    #[default]
    Gun,
    Melee,
    Grapple,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum FireMode {
    Semi,
    Auto,
}

impl WeaponDef {
    /// Damage after range falloff. Linear from `falloff_start` to `range`.
    pub fn damage_at(&self, dist: f32, headshot: bool) -> f32 {
        let t = ((dist - self.falloff_start) / (self.range - self.falloff_start).max(0.01)).clamp(0.0, 1.0);
        let base = self.damage * (1.0 - t * (1.0 - self.falloff_min));
        if headshot { base * self.headshot_mult } else { base }
    }

    pub fn fire_interval(&self) -> f32 {
        60.0 / self.rpm.max(1.0)
    }
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum GadgetKind {
    /// Cassette bug: records nearby conversation, yields intel.
    TapeBug,
    /// Thrown noise-maker that pulls guards off their routes.
    StaticLure,
    /// Poison dose applied to a consumable (the governor's tea service).
    Poison,
    /// Forged dispatch planted to make the target look guilty to the king.
    Forgery,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct GadgetDef {
    pub id: String,
    pub name: String,
    pub kind: GadgetKind,
    pub tag: Tag,
    pub description: String,
    pub count: u32,
    /// Placement / interaction range (m).
    pub use_range: f32,
    /// Effect radius (m): recording radius, noise radius...
    pub radius: f32,
    /// Effect duration (s) where relevant.
    pub duration: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct GovernorDef {
    pub id: String,
    pub name: String,
    pub title: String,
    pub province: String,
    pub tag: Tag,
    pub loyalty: f32,
    pub paranoia: f32,
    pub ambition: f32,
    pub troops: f32,
    #[serde(default)]
    pub rival: Option<String>,
    #[serde(default)]
    pub mission: Option<String>,
    #[serde(default)]
    pub successor: Option<String>,
    #[serde(default)]
    pub bio: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ScheduleEntry {
    /// Minutes after midnight, sim clock.
    pub at: f32,
    pub activity: Activity,
    /// Location id; resolved to a position by the level.
    pub location: String,
    /// Dialogue line ids spoken during this activity, in order.
    #[serde(default)]
    pub lines: Vec<String>,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum Activity {
    Work,
    Tea,
    Meeting,
    Inspect,
    Depart,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LineDef {
    pub id: String,
    pub speaker: String,
    pub text: String,
    /// Intel id unlocked when this line is heard (directly or on tape).
    #[serde(default)]
    pub intel: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct IntelDef {
    pub id: String,
    pub title: String,
    pub text: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MissionDef {
    pub id: String,
    pub province: String,
    pub title: String,
    pub briefing: String,
    pub start_minute: f32,
    /// Sim minutes per real second.
    pub time_scale: f32,
    pub schedule: Vec<ScheduleEntry>,
    pub lines: Vec<LineDef>,
    pub intel: Vec<IntelDef>,
    /// Intel required before the forged dispatch carries the right seal.
    pub forgery_requires: String,
    /// Intel id that reveals when he leaves (shown in objectives).
    pub depart_intel: String,
    pub player_health: f32,
    pub governor_health: f32,
    pub guard_health: f32,
    /// Seconds between poisoned tea being drunk and death.
    pub poison_delay: f32,
    /// Extra guards spawned per 25 points of governor paranoia.
    pub guards_per_paranoia: f32,
    pub loadout_weapon: String,
    /// Further weapons carried (sidearm, knives, grapple). Slots follow order.
    #[serde(default)]
    pub loadout_extra: Vec<String>,
    pub loadout_gadgets: Vec<String>,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Method {
    /// Killed by weapon or takedown without a general alarm.
    QuietKill,
    /// Killed during or after a general alarm.
    LoudKill,
    Poison,
    /// Framed; the king's own men remove him.
    Frame,
    /// Mission failed: target survived the night.
    Failed,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Fallout {
    pub method: Method,
    pub stability: f32,
    pub heat: f32,
    pub loyalty_others: f32,
    pub paranoia_others: f32,
    /// Change to the target's own paranoia (used for Failed).
    #[serde(default)]
    pub paranoia_target: f32,
    #[serde(default)]
    pub rumor: Option<String>,
    pub report: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RumorDef {
    pub id: String,
    pub text: String,
    pub tag: Tag,
    /// Loyalty change applied to a governor each night while they believe it.
    pub loyalty_per_night: f32,
    /// Stability change per night while it circulates, scaled by spread.
    pub stability_per_night: f32,
    /// Spread gained per night (0..1).
    pub spread_rate: f32,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum OpKind {
    /// Start a rumor circulating (needs `rumor`).
    SpreadRumor,
    /// Forged letters between a governor and their rival.
    SowDiscord,
    /// Gold and promises to lower a governor's loyalty.
    Bribe,
    /// "Firebrand" agent sent against a governor. Abstract, risky.
    Firebrand,
    /// Pull agents back, cool down.
    LieLow,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OpDef {
    pub id: String,
    pub name: String,
    pub kind: OpKind,
    pub description: String,
    pub needs_target: bool,
    pub cost_gold: i32,
    pub cost_agents: i32,
    pub success: f32,
    pub heat_success: f32,
    pub heat_fail: f32,
    /// Main magnitude (loyalty drop, suspicion, etc).
    pub power: f32,
    #[serde(default)]
    pub rumor: Option<String>,
    #[serde(default)]
    pub agent_lost_on_fail: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum Effect {
    Stability(f32),
    Heat(f32),
    Gold(i32),
    Agents(i32),
    LoyaltyAll(f32),
    ParanoiaAll(f32),
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EventDef {
    pub id: String,
    pub title: String,
    pub text: String,
    pub tag: Tag,
    pub min_night: u32,
    pub chance: f32,
    #[serde(default)]
    pub stability_below: Option<f32>,
    #[serde(default)]
    pub heat_above: Option<f32>,
    #[serde(default)]
    pub once: bool,
    pub effects: Vec<Effect>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CampaignDef {
    pub title: String,
    pub frame_text: Vec<String>,
    pub start_stability: f32,
    pub start_heat: f32,
    pub start_gold: i32,
    pub start_agents: i32,
    pub gold_per_night: i32,
    pub max_nights: u32,
    pub victory_stability: f32,
    pub defeat_heat: f32,
    /// Loyalty under which a governor defects to Chandragupta.
    pub defect_loyalty: f32,
    pub defect_stability_hit: f32,
    pub heat_decay_per_night: f32,
    /// Stability drift per night per point of (average loyalty - 50).
    pub loyalty_drift: f32,
    pub fallout: Vec<Fallout>,
    pub victory_text: String,
    pub defeat_heat_text: String,
    pub defeat_time_text: String,
}

/// All content, loaded once from `data/`.
#[derive(Clone, Debug)]
pub struct Content {
    pub weapons: Vec<WeaponDef>,
    pub gadgets: Vec<GadgetDef>,
    pub governors: Vec<GovernorDef>,
    pub missions: Vec<MissionDef>,
    pub rumors: Vec<RumorDef>,
    pub ops: Vec<OpDef>,
    pub events: Vec<EventDef>,
    pub campaign: CampaignDef,
    pub ai: crate::awareness::AwarenessParams,
}

impl Content {
    pub fn load(dir: &Path) -> Result<Self, LoadError> {
        let c = Self {
            weapons: read_ron(&dir.join("weapons.ron"))?,
            gadgets: read_ron(&dir.join("gadgets.ron"))?,
            governors: read_ron(&dir.join("governors.ron"))?,
            missions: read_ron(&dir.join("missions.ron"))?,
            rumors: read_ron(&dir.join("rumors.ron"))?,
            ops: read_ron(&dir.join("ops.ron"))?,
            events: read_ron(&dir.join("events.ron"))?,
            campaign: read_ron(&dir.join("campaign.ron"))?,
            ai: read_ron(&dir.join("ai.ron"))?,
        };
        c.validate()?;
        Ok(c)
    }

    /// Cross-reference checks so broken data fails loudly at load.
    pub fn validate(&self) -> Result<(), LoadError> {
        let err = |m: String| Err(LoadError(m));
        for g in &self.governors {
            if let Some(r) = &g.rival {
                if self.governor(r).is_none() { return err(format!("governor {} rival {r} missing", g.id)); }
            }
            if let Some(m) = &g.mission {
                if self.mission(m).is_none() { return err(format!("governor {} mission {m} missing", g.id)); }
            }
            if let Some(s) = &g.successor {
                if self.governor(s).is_none() { return err(format!("governor {} successor {s} missing", g.id)); }
            }
        }
        for m in &self.missions {
            if self.weapon(&m.loadout_weapon).is_none() { return err(format!("mission {} weapon missing", m.id)); }
            for w in &m.loadout_extra {
                if self.weapon(w).is_none() { return err(format!("mission {} weapon {} missing", m.id, w)); }
            }
            for g in &m.loadout_gadgets {
                if self.gadget(g).is_none() { return err(format!("mission {} gadget {g} missing", m.id)); }
            }
            for s in &m.schedule {
                for l in &s.lines {
                    if !m.lines.iter().any(|x| &x.id == l) { return err(format!("mission {} line {l} missing", m.id)); }
                }
            }
            for l in &m.lines {
                if let Some(i) = &l.intel {
                    if !m.intel.iter().any(|x| &x.id == i) { return err(format!("mission {} intel {i} missing", m.id)); }
                }
            }
            if !m.schedule.windows(2).all(|w| w[0].at <= w[1].at) {
                return err(format!("mission {} schedule not sorted", m.id));
            }
        }
        for o in &self.ops {
            if let Some(r) = &o.rumor {
                if self.rumor(r).is_none() { return err(format!("op {} rumor {r} missing", o.id)); }
            }
        }
        for f in &self.campaign.fallout {
            if let Some(r) = &f.rumor {
                if self.rumor(r).is_none() { return err(format!("fallout rumor {r} missing")); }
            }
        }
        Ok(())
    }

    pub fn weapon(&self, id: &str) -> Option<&WeaponDef> { self.weapons.iter().find(|w| w.id == id) }
    pub fn gadget(&self, id: &str) -> Option<&GadgetDef> { self.gadgets.iter().find(|w| w.id == id) }
    pub fn governor(&self, id: &str) -> Option<&GovernorDef> { self.governors.iter().find(|w| w.id == id) }
    pub fn mission(&self, id: &str) -> Option<&MissionDef> { self.missions.iter().find(|w| w.id == id) }
    pub fn rumor(&self, id: &str) -> Option<&RumorDef> { self.rumors.iter().find(|w| w.id == id) }
    pub fn op(&self, id: &str) -> Option<&OpDef> { self.ops.iter().find(|w| w.id == id) }
    pub fn fallout(&self, m: Method) -> Option<&Fallout> { self.campaign.fallout.iter().find(|f| f.method == m) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shipped_data_loads_and_validates() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../data");
        let c = Content::load(&dir).unwrap_or_else(|e| panic!("{e}"));
        assert!(!c.weapons.is_empty());
        assert!(c.gadgets.len() >= 3);
        assert!(c.governors.iter().any(|g| g.mission.is_some()));
        for m in [Method::QuietKill, Method::LoudKill, Method::Poison, Method::Frame, Method::Failed] {
            assert!(c.fallout(m).is_some(), "missing fallout for {m:?}");
        }
    }

    #[test]
    fn damage_falloff() {
        let w = WeaponDef {
            id: "t".into(), name: "t".into(), tag: Tag::Invented, description: String::new(),
            silhouette_ref: String::new(), damage: 40.0, headshot_mult: 2.0, range: 100.0,
            falloff_start: 20.0, falloff_min: 0.5, rpm: 600.0, mag_size: 20, reserve: 60,
            reload_time: 2.0, spread_deg: 1.0, ads_spread_deg: 0.2, recoil_pitch_deg: 1.0,
            recoil_yaw_deg: 0.3, noise_radius: 40.0, modes: vec![FireMode::Semi],
            kind: WeaponKind::Gun, suppressed: false, reach: 0.0,
        };
        assert_eq!(w.damage_at(10.0, false), 40.0);
        assert_eq!(w.damage_at(100.0, false), 20.0);
        assert_eq!(w.damage_at(10.0, true), 80.0);
        assert!((w.fire_interval() - 0.1).abs() < 1e-6);
    }
}
