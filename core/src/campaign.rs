//! Strategic layer ("the war room"). Chanakya's network against the king.
//! Governors carry loyalty and paranoia; rumors circulate; every removal has
//! fallout on the remaining governors and on the king's stability.
//! Design source: Arthashastra Bk 1 (agents), Bk 4 (removal of thorns),
//! Bk 5 (officials), Bk 12 (sowing discord). DESIGN, not Nanda-era fact.

use serde::{Deserialize, Serialize};

use crate::content::{Content, Effect, GovernorDef, Method, OpKind};
use crate::rng::Rng;

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
pub enum GovStatus {
    Serving,
    Removed(Method),
    Defected,
    Executed,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct GovState {
    pub id: String,
    pub name: String,
    pub title: String,
    pub province: String,
    pub loyalty: f32,
    pub paranoia: f32,
    pub ambition: f32,
    pub troops: f32,
    pub rival: Option<String>,
    pub mission: Option<String>,
    pub successor: Option<String>,
    pub status: GovStatus,
    /// Suspicion toward their rival, raised by forged letters.
    pub discord: f32,
    pub believes: Vec<String>,
    pub bio: String,
}

impl GovState {
    fn from_def(d: &GovernorDef) -> Self {
        Self {
            id: d.id.clone(),
            name: d.name.clone(),
            title: d.title.clone(),
            province: d.province.clone(),
            loyalty: d.loyalty,
            paranoia: d.paranoia,
            ambition: d.ambition,
            troops: d.troops,
            rival: d.rival.clone(),
            mission: d.mission.clone(),
            successor: d.successor.clone(),
            status: GovStatus::Serving,
            discord: 0.0,
            believes: vec![],
            bio: d.bio.clone(),
        }
    }

    pub fn serving(&self) -> bool {
        self.status == GovStatus::Serving
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RumorState {
    pub id: String,
    pub spread: f32,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum Outcome {
    Victory,
    DefeatHeat,
    DefeatTime,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Campaign {
    pub seed: u64,
    pub night: u32,
    pub stability: f32,
    pub heat: f32,
    pub gold: i32,
    pub agents: i32,
    pub governors: Vec<GovState>,
    pub rumors: Vec<RumorState>,
    pub log: Vec<(u32, String)>,
    pub ops_tonight: Vec<String>,
    pub mission_done_tonight: bool,
    pub fired_events: Vec<String>,
    pub outcome: Option<Outcome>,
    rng: Rng,
}

impl Campaign {
    pub fn new(c: &Content, seed: u64) -> Self {
        let mut s = Self {
            seed,
            night: 1,
            stability: c.campaign.start_stability,
            heat: c.campaign.start_heat,
            gold: c.campaign.start_gold,
            agents: c.campaign.start_agents,
            // Successors start off-board; only governors not named as anyone's successor serve.
            governors: c
                .governors
                .iter()
                .filter(|g| !c.governors.iter().any(|o| o.successor.as_deref() == Some(g.id.as_str())))
                .map(GovState::from_def)
                .collect(),
            rumors: vec![],
            log: vec![],
            ops_tonight: vec![],
            mission_done_tonight: false,
            fired_events: vec![],
            outcome: None,
            rng: Rng::new(seed),
        };
        s.log(format!("Night 1. The king's stability stands at {:.0}.", s.stability));
        s
    }

    fn log(&mut self, t: String) {
        self.log.push((self.night, t));
    }

    pub fn gov(&self, id: &str) -> Option<&GovState> {
        self.governors.iter().find(|g| g.id == id)
    }

    fn gov_mut(&mut self, id: &str) -> Option<&mut GovState> {
        self.governors.iter_mut().find(|g| g.id == id)
    }

    /// The serving governor (if any) who has a playable field mission.
    pub fn mission_target(&self) -> Option<&GovState> {
        self.governors.iter().find(|g| g.serving() && g.mission.is_some())
    }

    pub fn add_rumor(&mut self, id: &str, amount: f32) {
        match self.rumors.iter_mut().find(|r| r.id == id) {
            Some(r) => r.spread = (r.spread + amount).min(1.0),
            None => self.rumors.push(RumorState { id: id.into(), spread: amount.min(1.0) }),
        }
    }

    fn clamp(&mut self) {
        self.stability = self.stability.clamp(0.0, 100.0);
        self.heat = self.heat.clamp(0.0, 100.0);
        for g in &mut self.governors {
            g.loyalty = g.loyalty.clamp(0.0, 100.0);
            g.paranoia = g.paranoia.clamp(0.0, 100.0);
            g.discord = g.discord.clamp(0.0, 100.0);
        }
    }

    /// Run an agent operation from the war room.
    pub fn run_op(&mut self, c: &Content, op_id: &str, target: Option<&str>) -> Result<String, String> {
        if self.outcome.is_some() { return Err("The campaign is over.".into()); }
        let op = c.op(op_id).ok_or("Unknown operation")?.clone();
        if self.ops_tonight.iter().any(|o| o == op_id) { return Err("Already ordered tonight.".into()); }
        if self.gold < op.cost_gold { return Err("Not enough gold.".into()); }
        if self.agents < op.cost_agents { return Err("Not enough agents.".into()); }
        let tgt = if op.needs_target {
            let id = target.ok_or("Choose a governor.")?;
            let g = self.gov(id).ok_or("Unknown governor.")?;
            if !g.serving() { return Err("That governor no longer serves.".into()); }
            Some(g.clone())
        } else {
            None
        };
        self.gold -= op.cost_gold;
        self.ops_tonight.push(op_id.into());

        let paranoia = tgt.as_ref().map(|g| g.paranoia).unwrap_or(0.0);
        let p_success = (op.success * (1.0 - paranoia / 220.0)).clamp(0.02, 0.98);
        let ok = self.rng.chance(p_success);
        let report;
        if ok {
            self.heat += op.heat_success;
            report = match op.kind {
                OpKind::SpreadRumor => {
                    let r = op.rumor.clone().unwrap_or_default();
                    self.add_rumor(&r, op.power);
                    let text = c.rumor(&r).map(|x| x.text.clone()).unwrap_or_default();
                    format!("Agents seed the bazaars: \"{text}\"")
                }
                OpKind::SowDiscord => {
                    let g = tgt.unwrap();
                    let rival_id = g.rival.clone();
                    let gm = self.gov_mut(&g.id).unwrap();
                    gm.discord += op.power;
                    let mut msg = format!("Forged letters reach {}. Suspicion of their rival grows ({:.0}).", g.name, gm.discord);
                    if gm.discord >= 100.0 {
                        msg.push(' ');
                        msg.push_str(&self.accusation(&g.id, rival_id.as_deref()));
                    }
                    msg
                }
                OpKind::Bribe => {
                    let g = tgt.unwrap();
                    let gm = self.gov_mut(&g.id).unwrap();
                    let d = op.power * (1.0 - gm.paranoia / 160.0) * (0.6 + gm.ambition / 125.0);
                    gm.loyalty -= d;
                    format!("{} accepts the gold. Loyalty to the throne falls by {:.0}.", g.name, d)
                }
                OpKind::Firebrand => {
                    let g = tgt.unwrap();
                    self.remove_governor(c, &g.id, Method::QuietKill, 0.6)
                }
                OpKind::LieLow => {
                    self.heat -= op.power;
                    self.agents += 1;
                    format!("The network goes quiet. Heat falls by {:.0}.", op.power)
                }
            };
        } else {
            self.heat += op.heat_fail;
            if op.agent_lost_on_fail { self.agents -= op.cost_agents; }
            report = format!("{} failed.{}", op.name, if op.agent_lost_on_fail { " An agent is lost." } else { "" });
        }
        self.clamp();
        self.log(report.clone());
        self.check_end(c);
        Ok(report)
    }

    /// A governor's discord boils over: he accuses his rival before the king.
    fn accusation(&mut self, accuser: &str, rival: Option<&str>) -> String {
        let Some(rival) = rival else { return String::new() };
        let (Some(a), Some(r)) = (self.gov(accuser).cloned(), self.gov(rival).cloned()) else { return String::new() };
        if !r.serving() { return String::new(); }
        // The king believes whoever looks more loyal; the other is executed.
        let victim = if a.loyalty >= r.loyalty { r.clone() } else { a.clone() };
        if let Some(v) = self.gov_mut(&victim.id) { v.status = GovStatus::Executed; }
        if let Some(acc) = self.gov_mut(accuser) { acc.discord = 0.0; }
        self.stability -= 8.0;
        for g in self.governors.iter_mut().filter(|g| g.serving()) {
            g.loyalty -= 6.0;
            g.paranoia += 10.0;
        }
        format!("{} denounces {} before the king. {} is executed; the court trembles.", a.name, r.name, victim.name)
    }

    /// Apply fallout for a removed (or surviving) governor. `scale` lets
    /// abstract ops have weaker effects than a field mission.
    pub fn remove_governor(&mut self, c: &Content, id: &str, m: Method, scale: f32) -> String {
        let Some(f) = c.fallout(m).cloned() else { return String::new() };
        let name = self.gov(id).map(|g| g.name.clone()).unwrap_or_default();
        self.stability += f.stability * scale;
        self.heat += f.heat * scale;
        if let Some(r) = &f.rumor { self.add_rumor(r, 0.35 * scale); }
        if m == Method::Failed {
            if let Some(g) = self.gov_mut(id) { g.paranoia += f.paranoia_target; }
        } else {
            let successor = self.gov(id).and_then(|g| g.successor.clone());
            if let Some(g) = self.gov_mut(id) { g.status = GovStatus::Removed(m); }
            for g in self.governors.iter_mut().filter(|g| g.serving() && g.id != id) {
                g.loyalty += f.loyalty_others * scale;
                g.paranoia += f.paranoia_others * scale;
            }
            if let Some(s) = successor.and_then(|s| c.governor(&s)) {
                let mut ns = GovState::from_def(s);
                ns.paranoia += 10.0;
                self.log(format!("The king appoints {} to {}.", ns.name, ns.province));
                self.governors.push(ns);
            }
        }
        self.clamp();
        let text = f.report.replace("{name}", &name);
        self.log(text.clone());
        self.check_end(c);
        text
    }

    /// Field mission result for tonight.
    pub fn apply_mission(&mut self, c: &Content, gov_id: &str, m: Method) -> String {
        self.mission_done_tonight = true;
        self.remove_governor(c, gov_id, m, 1.0)
    }

    /// Close the night: rumors spread, loyalties drift, events fire.
    pub fn end_night(&mut self, c: &Content) -> Vec<String> {
        let mut out = vec![];
        if self.outcome.is_some() { return out; }
        let cd = &c.campaign;

        // Rumors.
        let rumors = self.rumors.clone();
        for r in &rumors {
            let Some(def) = c.rumor(&r.id) else { continue };
            self.stability += def.stability_per_night * r.spread;
            for i in 0..self.governors.len() {
                if !self.governors[i].serving() { continue; }
                let believes = self.governors[i].believes.contains(&r.id);
                if !believes && self.rng.chance(r.spread * 0.8) {
                    self.governors[i].believes.push(r.id.clone());
                    out.push(format!("{} has heard: \"{}\"", self.governors[i].name, def.text));
                }
                if self.governors[i].believes.contains(&r.id) {
                    self.governors[i].loyalty += def.loyalty_per_night;
                }
            }
        }
        for r in &mut self.rumors {
            let rate = c.rumor(&r.id).map(|d| d.spread_rate).unwrap_or(0.0);
            r.spread = (r.spread + rate).min(1.0);
        }

        // Loyalty drift into the king's stability; defections.
        let serving: Vec<f32> = self.governors.iter().filter(|g| g.serving()).map(|g| g.loyalty).collect();
        if !serving.is_empty() {
            let avg = serving.iter().sum::<f32>() / serving.len() as f32;
            self.stability += (avg - 50.0) * cd.loyalty_drift;
        }
        for i in 0..self.governors.len() {
            let g = &self.governors[i];
            if g.serving() && g.loyalty < cd.defect_loyalty {
                let name = g.name.clone();
                let prov = g.province.clone();
                self.governors[i].status = GovStatus::Defected;
                self.stability -= cd.defect_stability_hit;
                out.push(format!("{name} closes the roads of {prov} and sends word to Chandragupta."));
            }
        }

        // Events.
        for e in &c.events {
            if self.night < e.min_night { continue; }
            if e.once && self.fired_events.contains(&e.id) { continue; }
            if let Some(s) = e.stability_below { if self.stability >= s { continue; } }
            if let Some(h) = e.heat_above { if self.heat <= h { continue; } }
            if !self.rng.chance(e.chance) { continue; }
            self.fired_events.push(e.id.clone());
            for fx in &e.effects {
                match fx {
                    Effect::Stability(v) => self.stability += v,
                    Effect::Heat(v) => self.heat += v,
                    Effect::Gold(v) => self.gold += v,
                    Effect::Agents(v) => self.agents += v,
                    Effect::LoyaltyAll(v) => self.governors.iter_mut().filter(|g| g.serving()).for_each(|g| g.loyalty += v),
                    Effect::ParanoiaAll(v) => self.governors.iter_mut().filter(|g| g.serving()).for_each(|g| g.paranoia += v),
                }
            }
            out.push(format!("{}: {}", e.title, e.text));
        }

        self.heat -= cd.heat_decay_per_night;
        self.gold += cd.gold_per_night;
        self.clamp();
        for line in &out { self.log.push((self.night, line.clone())); }
        self.night += 1;
        self.ops_tonight.clear();
        self.mission_done_tonight = false;
        self.check_end(c);
        if self.outcome.is_none() {
            self.log(format!("Night {}. Stability {:.0}, heat {:.0}.", self.night, self.stability, self.heat));
        }
        out
    }

    fn check_end(&mut self, c: &Content) {
        if self.outcome.is_some() { return; }
        let cd = &c.campaign;
        if self.stability <= cd.victory_stability {
            self.outcome = Some(Outcome::Victory);
        } else if self.heat >= cd.defeat_heat {
            self.outcome = Some(Outcome::DefeatHeat);
        } else if self.night > cd.max_nights {
            self.outcome = Some(Outcome::DefeatTime);
        }
    }

    pub fn outcome_text<'a>(&self, c: &'a Content) -> Option<&'a str> {
        self.outcome.map(|o| match o {
            Outcome::Victory => c.campaign.victory_text.as_str(),
            Outcome::DefeatHeat => c.campaign.defeat_heat_text.as_str(),
            Outcome::DefeatTime => c.campaign.defeat_time_text.as_str(),
        })
    }

    pub fn to_ron(&self) -> Result<String, String> {
        ron::ser::to_string_pretty(self, ron::ser::PrettyConfig::new()).map_err(|e| e.to_string())
    }

    pub fn from_ron(s: &str) -> Result<Self, String> {
        ron::from_str(s).map_err(|e| e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn content() -> Content {
        Content::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../data")).unwrap()
    }

    #[test]
    fn deterministic_with_seed() {
        let c = content();
        let run = |seed| {
            let mut s = Campaign::new(&c, seed);
            for _ in 0..4 {
                let _ = s.run_op(&c, &c.ops[0].id, s.governors.first().map(|g| g.id.clone()).as_deref());
                s.end_night(&c);
            }
            (s.stability, s.heat, s.gold)
        };
        assert_eq!(run(7), run(7));
    }

    #[test]
    fn mission_removal_appoints_successor_and_hits_stability() {
        let c = content();
        let mut s = Campaign::new(&c, 1);
        let target = s.mission_target().unwrap().id.clone();
        let before = s.stability;
        s.apply_mission(&c, &target, Method::Frame);
        assert!(s.stability < before);
        assert!(matches!(s.gov(&target).unwrap().status, GovStatus::Removed(Method::Frame)));
        // Successor now holds the playable province.
        let next = s.mission_target().unwrap();
        assert_ne!(next.id, target);
    }

    #[test]
    fn failed_mission_raises_target_paranoia() {
        let c = content();
        let mut s = Campaign::new(&c, 1);
        let t = s.mission_target().unwrap().clone();
        s.apply_mission(&c, &t.id, Method::Failed);
        assert!(s.gov(&t.id).unwrap().paranoia > t.paranoia);
        assert!(s.gov(&t.id).unwrap().serving());
    }

    #[test]
    fn save_roundtrip() {
        let c = content();
        let mut s = Campaign::new(&c, 3);
        s.end_night(&c);
        let txt = s.to_ron().unwrap();
        let back = Campaign::from_ron(&txt).unwrap();
        assert_eq!(back.night, s.night);
        assert_eq!(back.governors.len(), s.governors.len());
    }

    #[test]
    fn time_runs_out() {
        let c = content();
        let mut s = Campaign::new(&c, 9);
        for _ in 0..(c.campaign.max_nights + 1) { s.end_night(&c); }
        assert!(s.outcome.is_some());
    }
}
