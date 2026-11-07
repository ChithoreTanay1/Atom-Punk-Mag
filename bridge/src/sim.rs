//! `GameSim`: the single node GDScript talks to for game state. It owns the
//! loaded content, the campaign and the active mission. Everything here is a
//! thin translation between core structs and Godot dictionaries.

use godot::prelude::*;
use std::path::PathBuf;

use magadha_core::campaign::{Campaign, GovStatus};
use magadha_core::content::{Content, GadgetKind, Method};
use magadha_core::mission::{Mission, MissionEvent, TargetStatus};
use magadha_core::tuning::Tuning;

use crate::world::{v3, world};

#[derive(GodotClass)]
#[class(base = Node, init)]
pub struct GameSim {
    content: Option<Content>,
    data_dir: PathBuf,
    campaign: Option<Campaign>,
    mission: Option<Mission>,
    mission_gov: Option<String>,
    base: Base<Node>,
}

fn method_name(m: Method) -> &'static str {
    match m {
        Method::QuietKill => "quiet_kill",
        Method::LoudKill => "loud_kill",
        Method::Poison => "poison",
        Method::Frame => "frame",
        Method::Failed => "failed",
    }
}

fn method_from(s: &str) -> Method {
    match s {
        "quiet_kill" => Method::QuietKill,
        "loud_kill" => Method::LoudKill,
        "poison" => Method::Poison,
        "frame" => Method::Frame,
        _ => Method::Failed,
    }
}

fn kind_name(k: GadgetKind) -> &'static str {
    match k {
        GadgetKind::TapeBug => "tape_bug",
        GadgetKind::StaticLure => "static_lure",
        GadgetKind::Poison => "poison",
        GadgetKind::Forgery => "forgery",
    }
}

fn status_name(s: GovStatus) -> String {
    match s {
        GovStatus::Serving => "serving".into(),
        GovStatus::Removed(m) => format!("removed:{}", method_name(m)),
        GovStatus::Defected => "defected".into(),
        GovStatus::Executed => "executed".into(),
    }
}

fn s(x: &str) -> GString {
    GString::from(x)
}

#[godot_api]
impl GameSim {
    /// Load all content and tuning from `dir`. Returns "" or an error message.
    #[func]
    fn load_data(&mut self, dir: GString) -> GString {
        let dir = PathBuf::from(dir.to_string());
        match Content::load(&dir) {
            Ok(c) => {
                let tuning: Tuning = magadha_core::read_ron(&dir.join("tuning.ron")).unwrap_or_default();
                {
                    let mut w = world();
                    w.tuning = tuning;
                    w.ai = c.ai.clone();
                }
                self.content = Some(c);
                self.data_dir = dir;
                GString::new()
            }
            Err(e) => s(&e.0),
        }
    }

    // ---- Tuning ------------------------------------------------------------

    #[func]
    fn tuning_sections(&self) -> PackedStringArray {
        Tuning::SECTIONS.iter().map(|x| s(x)).collect()
    }

    #[func]
    fn tuning_fields(&self, section: GString) -> VarArray {
        let sec = section.to_string();
        let w = world();
        let mut out = VarArray::new();
        for f in Tuning::fields(&sec) {
            let d = vdict! {
                "name" => f.name,
                "min" => f.min,
                "max" => f.max,
                "doc" => f.doc,
                "value" => w.tuning.get(&sec, f.name).unwrap_or(0.0),
            };
            out.push(&d.to_variant());
        }
        out
    }

    #[func]
    fn set_tuning(&mut self, section: GString, key: GString, value: f32) -> bool {
        world().tuning.set(&section.to_string(), &key.to_string(), value)
    }

    #[func]
    fn get_tuning(&self, section: GString, key: GString) -> f32 {
        world().tuning.get(&section.to_string(), &key.to_string()).unwrap_or(0.0)
    }

    #[func]
    fn reset_tuning(&mut self, section: GString) {
        let d = Tuning::default();
        let mut w = world();
        match section.to_string().as_str() {
            "movement" => w.tuning.movement = d.movement,
            "camera" => w.tuning.camera = d.camera,
            "vehicle" => w.tuning.vehicle = d.vehicle,
            _ => {}
        }
    }

    #[func]
    fn save_tuning(&self) -> GString {
        let t = world().tuning.clone();
        match magadha_core::write_ron(&self.data_dir.join("tuning.ron"), &t) {
            Ok(()) => GString::new(),
            Err(e) => s(&e.0),
        }
    }

    // ---- Content lookups ---------------------------------------------------

    #[func]
    fn frame_text(&self) -> PackedStringArray {
        self.content.as_ref().map(|c| c.campaign.frame_text.iter().map(|x| s(x)).collect()).unwrap_or_default()
    }

    #[func]
    fn campaign_title(&self) -> GString {
        self.content.as_ref().map(|c| s(&c.campaign.title)).unwrap_or_default()
    }

    #[func]
    fn weapon_def(&self, id: GString) -> VarDictionary {
        let Some(w) = self.content.as_ref().and_then(|c| c.weapon(&id.to_string())) else { return VarDictionary::new() };
        vdict! {
            "id" => w.id.as_str(), "name" => w.name.as_str(), "description" => w.description.as_str(),
            "damage" => w.damage, "headshot_mult" => w.headshot_mult, "range" => w.range,
            "fire_interval" => w.fire_interval(), "mag_size" => w.mag_size as i64, "reload_time" => w.reload_time,
            "spread_deg" => w.spread_deg, "ads_spread_deg" => w.ads_spread_deg,
            "recoil_pitch_deg" => w.recoil_pitch_deg, "recoil_yaw_deg" => w.recoil_yaw_deg,
            "noise_radius" => w.noise_radius,
            "has_auto" => w.modes.contains(&magadha_core::content::FireMode::Auto),
        }
    }

    #[func]
    fn weapon_damage(&self, id: GString, dist: f32, headshot: bool) -> f32 {
        self.content.as_ref().and_then(|c| c.weapon(&id.to_string())).map(|w| w.damage_at(dist, headshot)).unwrap_or(0.0)
    }

    #[func]
    fn gadget_def(&self, id: GString) -> VarDictionary {
        let Some(g) = self.content.as_ref().and_then(|c| c.gadget(&id.to_string())) else { return VarDictionary::new() };
        vdict! {
            "id" => g.id.as_str(), "name" => g.name.as_str(), "kind" => kind_name(g.kind),
            "description" => g.description.as_str(), "use_range" => g.use_range,
            "radius" => g.radius, "duration" => g.duration,
        }
    }

    // ---- Campaign ----------------------------------------------------------

    #[func]
    fn new_campaign(&mut self, seed: i64) {
        if let Some(c) = &self.content {
            self.campaign = Some(Campaign::new(c, seed as u64));
            self.mission = None;
        }
    }

    #[func]
    fn has_campaign(&self) -> bool {
        self.campaign.is_some()
    }

    #[func]
    fn save_campaign(&self, path: GString) -> bool {
        let Some(c) = &self.campaign else { return false };
        c.to_ron().ok().and_then(|t| std::fs::write(path.to_string(), t).ok()).is_some()
    }

    #[func]
    fn load_campaign(&mut self, path: GString) -> bool {
        let Ok(t) = std::fs::read_to_string(path.to_string()) else { return false };
        match Campaign::from_ron(&t) {
            Ok(c) => { self.campaign = Some(c); true }
            Err(e) => { godot_warn!("save load failed: {e}"); false }
        }
    }

    #[func]
    fn campaign_state(&self) -> VarDictionary {
        let (Some(c), Some(cs)) = (&self.content, &self.campaign) else { return VarDictionary::new() };
        let mut govs = VarArray::new();
        for g in &cs.governors {
            let rival_name = g.rival.as_ref().and_then(|r| cs.gov(r)).map(|r| r.name.clone()).unwrap_or_default();
            let d = vdict! {
                "id" => g.id.as_str(), "name" => g.name.as_str(), "title" => g.title.as_str(),
                "province" => g.province.as_str(), "loyalty" => g.loyalty, "paranoia" => g.paranoia,
                "ambition" => g.ambition, "troops" => g.troops, "discord" => g.discord,
                "status" => status_name(g.status).as_str(), "rival" => rival_name.as_str(),
                "has_mission" => g.mission.is_some(), "bio" => g.bio.as_str(),
                "believes" => g.believes.len() as i64,
            };
            govs.push(&d.to_variant());
        }
        let mut ops = VarArray::new();
        for o in &c.ops {
            let d = vdict! {
                "id" => o.id.as_str(), "name" => o.name.as_str(), "description" => o.description.as_str(),
                "needs_target" => o.needs_target, "cost_gold" => o.cost_gold as i64,
                "cost_agents" => o.cost_agents as i64, "success" => o.success,
                "used" => cs.ops_tonight.contains(&o.id),
            };
            ops.push(&d.to_variant());
        }
        let mut rumors = VarArray::new();
        for r in &cs.rumors {
            let text = c.rumor(&r.id).map(|x| x.text.clone()).unwrap_or_default();
            rumors.push(&vdict! { "text" => text.as_str(), "spread" => r.spread }.to_variant());
        }
        let log: PackedStringArray = cs.log.iter().rev().take(40).map(|(n, t)| s(&format!("[N{n}] {t}"))).collect();
        let target = cs.mission_target().map(|g| g.id.clone()).unwrap_or_default();
        vdict! {
            "night" => cs.night as i64, "max_nights" => c.campaign.max_nights as i64,
            "stability" => cs.stability, "victory_stability" => c.campaign.victory_stability,
            "heat" => cs.heat, "gold" => cs.gold as i64, "agents" => cs.agents as i64,
            "governors" => &govs, "ops" => &ops, "rumors" => &rumors, "log" => &log,
            "mission_target" => target.as_str(), "mission_done" => cs.mission_done_tonight,
            "outcome" => cs.outcome.map(|o| format!("{o:?}")).unwrap_or_default().as_str(),
            "outcome_text" => cs.outcome_text(c).unwrap_or(""),
        }
    }

    #[func]
    fn run_op(&mut self, op_id: GString, target: GString) -> VarDictionary {
        let (Some(c), Some(cs)) = (&self.content, &mut self.campaign) else { return VarDictionary::new() };
        let t = target.to_string();
        let r = cs.run_op(c, &op_id.to_string(), if t.is_empty() { None } else { Some(&t) });
        match r {
            Ok(text) => vdict! { "ok" => true, "text" => text.as_str() },
            Err(text) => vdict! { "ok" => false, "text" => text.as_str() },
        }
    }

    #[func]
    fn end_night(&mut self) -> PackedStringArray {
        let (Some(c), Some(cs)) = (&self.content, &mut self.campaign) else { return PackedStringArray::new() };
        cs.end_night(c).iter().map(|x| s(x)).collect()
    }

    // ---- Mission -----------------------------------------------------------

    /// Start the playable mission. Uses the campaign's current target if a
    /// campaign is running, else the first playable governor (free play).
    #[func]
    fn start_mission(&mut self) -> bool {
        let Some(c) = &self.content else { return false };
        let (gov_id, paranoia, mission_id) = if let Some(t) = self.campaign.as_ref().and_then(|cs| cs.mission_target()) {
            (t.id.clone(), t.paranoia, t.mission.clone().unwrap_or_default())
        } else if let Some(g) = c.governors.iter().find(|g| g.mission.is_some()) {
            (g.id.clone(), g.paranoia, g.mission.clone().unwrap_or_default())
        } else {
            return false;
        };
        self.mission = Mission::new(c, &mission_id, paranoia);
        self.mission_gov = Some(gov_id);
        let mut w = world();
        w.alarm = false;
        w.corpses.clear();
        self.mission.is_some()
    }

    #[func]
    fn mission_info(&self) -> VarDictionary {
        let (Some(c), Some(m)) = (&self.content, &self.mission) else { return VarDictionary::new() };
        let gov = self.mission_gov.as_ref().and_then(|id| {
            self.campaign.as_ref().and_then(|cs| cs.gov(id).map(|g| (g.name.clone(), g.paranoia, g.bio.clone())))
                .or_else(|| c.governor(id).map(|g| (g.name.clone(), g.paranoia, g.bio.clone())))
        }).unwrap_or_default();
        vdict! {
            "title" => m.def.title.as_str(), "briefing" => m.def.briefing.as_str(),
            "province" => m.def.province.as_str(), "governor" => gov.0.as_str(), "paranoia" => gov.1,
            "bio" => gov.2.as_str(),
            "governor_health" => m.def.governor_health, "guard_health" => m.def.guard_health,
            "extra_guards" => m.extra_guards as i64, "weapon" => m.def.loadout_weapon.as_str(),
            "gadgets" => &m.def.loadout_gadgets.iter().map(|g| s(g)).collect::<PackedStringArray>(),
        }
    }

    #[func]
    fn mission_tick(&mut self, dt: f32) {
        if let Some(m) = &mut self.mission {
            m.tick(dt);
            world().alarm = m.alarm;
        }
    }

    #[func]
    fn mission_events(&mut self) -> VarArray {
        let mut out = VarArray::new();
        let Some(m) = &mut self.mission else { return out };
        for e in m.drain_events() {
            let d = match e {
                MissionEvent::Activity { activity, location } => vdict! {
                    "type" => "activity", "activity" => format!("{activity:?}").to_lowercase().as_str(), "location" => location.as_str(),
                },
                MissionEvent::Line { id, speaker, text } => vdict! {
                    "type" => "line", "id" => id.as_str(), "speaker" => speaker.as_str(), "text" => text.as_str(),
                },
                MissionEvent::IntelGained { id, title } => vdict! { "type" => "intel", "id" => id.as_str(), "title" => title.as_str() },
                MissionEvent::AlarmRaised => vdict! { "type" => "alarm" },
                MissionEvent::TargetDown { method } => vdict! { "type" => "target_down", "method" => method_name(method) },
                MissionEvent::TargetDying => vdict! { "type" => "target_dying" },
                MissionEvent::Message(t) => vdict! { "type" => "message", "text" => t.as_str() },
                MissionEvent::Finished { method } => vdict! { "type" => "finished", "method" => method_name(method) },
            };
            out.push(&d.to_variant());
        }
        out
    }

    #[func]
    fn mission_state(&self) -> VarDictionary {
        let (Some(c), Some(m)) = (&self.content, &self.mission) else { return VarDictionary::new() };
        let mut gadgets = VarArray::new();
        for g in &m.gadgets {
            let name = c.gadget(&g.id).map(|x| x.name.clone()).unwrap_or_default();
            gadgets.push(&vdict! { "id" => g.id.as_str(), "name" => name.as_str(), "kind" => kind_name(g.kind), "count" => g.count as i64 }.to_variant());
        }
        let mut intel = VarArray::new();
        for i in &m.def.intel {
            if m.intel.contains(&i.id) {
                intel.push(&vdict! { "id" => i.id.as_str(), "title" => i.title.as_str(), "text" => i.text.as_str() }.to_variant());
            }
        }
        let target = match m.target {
            TargetStatus::Alive => "alive",
            TargetStatus::Dying(_) => "dying",
            TargetStatus::Dead => "dead",
            TargetStatus::Arrested => "arrested",
            TargetStatus::Escaped => "escaped",
        };
        vdict! {
            "clock" => m.clock_text().as_str(), "minute" => m.clock,
            "health" => m.player_health, "max_health" => m.player_max_health,
            "ammo" => m.ammo_mag as i64, "reserve" => m.ammo_reserve as i64,
            "alarm" => m.alarm, "objectives" => &m.objectives().iter().map(|x| s(x)).collect::<PackedStringArray>(),
            "gadgets" => &gadgets, "intel" => &intel, "intel_total" => m.def.intel.len() as i64,
            "target" => target, "removed" => m.removal.map(method_name).unwrap_or(""),
            "finished" => m.finished.map(method_name).unwrap_or(""),
            "tea_poisoned" => m.tea_poisoned, "forgery_planted" => m.forgery_planted,
            "kills" => m.kills as i64,
        }
    }

    #[func]
    fn mission_active(&self) -> bool {
        self.mission.as_ref().map(|m| m.finished.is_none()).unwrap_or(false)
    }

    #[func]
    fn hear_line(&mut self, id: GString) {
        if let Some(m) = &mut self.mission { m.hear_line(&id.to_string()); }
    }

    #[func]
    fn consume_gadget(&mut self, id: GString) -> bool {
        self.mission.as_mut().map(|m| m.consume_gadget(&id.to_string())).unwrap_or(false)
    }

    #[func]
    fn gadget_count(&self, id: GString) -> i64 {
        self.mission.as_ref().map(|m| m.gadget_count(&id.to_string()) as i64).unwrap_or(0)
    }

    /// Returns "" on success or the reason it failed.
    #[func]
    fn poison_tea(&mut self, gadget_id: GString) -> GString {
        let Some(m) = &mut self.mission else { return s("no mission") };
        m.poison_tea(&gadget_id.to_string()).err().map(s).unwrap_or_default()
    }

    #[func]
    fn plant_forgery(&mut self, gadget_id: GString) -> GString {
        let Some(m) = &mut self.mission else { return s("no mission") };
        m.plant_forgery(&gadget_id.to_string()).err().map(s).unwrap_or_default()
    }

    #[func]
    fn send_telex(&mut self) -> GString {
        let Some(m) = &mut self.mission else { return s("no mission") };
        m.send_telex().err().map(s).unwrap_or_default()
    }

    #[func]
    fn governor_drinks_tea(&mut self) {
        if let Some(m) = &mut self.mission { m.governor_drinks_tea(); }
    }

    #[func]
    fn governor_killed(&mut self) {
        if let Some(m) = &mut self.mission { m.governor_killed(); }
    }

    #[func]
    fn governor_escaped(&mut self) {
        if let Some(m) = &mut self.mission { m.governor_escaped(); }
    }

    #[func]
    fn npc_killed(&mut self) {
        if let Some(m) = &mut self.mission { m.kills += 1; }
    }

    #[func]
    fn body_found(&mut self) {
        if let Some(m) = &mut self.mission { m.body_found(); world().alarm = true; }
    }

    #[func]
    fn raise_alarm(&mut self) {
        if let Some(m) = &mut self.mission { m.raise_alarm(); }
        world().alarm = true;
    }

    #[func]
    fn is_alarm(&self) -> bool {
        world().alarm
    }

    /// Returns true if the player died.
    #[func]
    fn damage_player(&mut self, amount: f32) -> bool {
        self.mission.as_mut().map(|m| m.damage_player(amount)).unwrap_or(false)
    }

    #[func]
    fn heal_player(&mut self, amount: f32) {
        if let Some(m) = &mut self.mission { m.heal_player(amount); }
    }

    #[func]
    fn player_exfiltrated(&mut self) {
        if let Some(m) = &mut self.mission { m.player_exfiltrated(); }
    }

    #[func]
    fn abort_mission(&mut self) {
        if let Some(m) = &mut self.mission { m.abort(); }
    }

    #[func]
    fn try_fire(&mut self) -> bool {
        self.mission.as_mut().map(|m| m.try_fire()).unwrap_or(false)
    }

    #[func]
    fn reload(&mut self) -> bool {
        self.mission.as_mut().map(|m| m.reload()).unwrap_or(false)
    }

    /// Apply the finished mission to the campaign; returns the report text.
    #[func]
    fn apply_mission_result(&mut self, method: GString) -> GString {
        let (Some(c), Some(cs), Some(gov)) = (&self.content, &mut self.campaign, &self.mission_gov) else { return GString::new() };
        let text = cs.apply_mission(c, gov, method_from(&method.to_string()));
        self.mission = None;
        s(&text)
    }

    // ---- Navigation --------------------------------------------------------

    #[func]
    fn nav_clear(&mut self) {
        world().nav = Default::default();
    }

    #[func]
    fn nav_add(&mut self, p: Vector3) -> i64 {
        world().nav.add_node([p.x, p.y, p.z]) as i64
    }

    #[func]
    fn nav_link(&mut self, a: i64, b: i64) {
        world().nav.link(a as usize, b as usize);
    }

    #[func]
    fn nav_route(&self, from: Vector3, to: Vector3) -> PackedVector3Array {
        world().nav.route([from.x, from.y, from.z], [to.x, to.y, to.z]).into_iter().map(v3).collect()
    }
}
