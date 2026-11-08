//! `GameSim`: the single node GDScript talks to for game state. It owns the
//! loaded content, the campaign and the active mission. Everything here is a
//! thin translation between core structs and Godot dictionaries.

use godot::prelude::*;
use std::path::PathBuf;

use magadha_core::campaign::{Campaign, GovStatus};
use magadha_core::content::{Content, GadgetKind, Method};
use magadha_core::market::{eighths, Market, MarketDef};
use magadha_core::mission::{Mission, MissionEvent, TargetStatus};
use magadha_core::surveillance::SurveillanceEvent;
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
    market_def: Option<MarketDef>,
    market: Option<Market>,
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
                    w.wounds = c.wounds.clone();
                }
                self.content = Some(c);
                let md = MarketDef::load(&dir.join("market.ron"));
                self.data_dir = dir;
                match md {
                    Ok(d) => { self.market_def = Some(d); GString::new() }
                    Err(e) => s(&e.0),
                }
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
            "bike" => w.tuning.bike = d.bike,
            "crash" => w.tuning.crash = d.crash,
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
            "has_semi" => w.modes.contains(&magadha_core::content::FireMode::Semi),
            "kind" => match w.kind {
                magadha_core::content::WeaponKind::Gun => "gun",
                magadha_core::content::WeaponKind::Melee => "melee",
                magadha_core::content::WeaponKind::Grapple => "grapple",
            },
            "suppressed" => w.suppressed, "reach" => w.reach, "reserve" => w.reserve as i64,
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
            self.market = self.market_def.as_ref().map(|d| Market::new(d, seed as u64));
        }
    }

    #[func]
    fn has_campaign(&self) -> bool {
        self.campaign.is_some()
    }

    #[func]
    fn save_campaign(&self, path: GString) -> bool {
        let Some(c) = &self.campaign else { return false };
        let mut c = c.clone();
        c.market = self.market.clone();
        c.to_ron().ok().and_then(|t| std::fs::write(path.to_string(), t).ok()).is_some()
    }

    #[func]
    fn load_campaign(&mut self, path: GString) -> bool {
        let Ok(t) = std::fs::read_to_string(path.to_string()) else { return false };
        match Campaign::from_ron(&t) {
            Ok(mut c) => {
                self.market = c.market.take().or_else(|| self.market_def.as_ref().map(|d| Market::new(d, c.seed)));
                // A save from before a listing or a mission existed keeps working.
                if let (Some(m), Some(d)) = (&mut self.market, &self.market_def) { m.refresh_listings(d); }
                if let Some(content) = &self.content { c.refresh_from_content(content); }
                self.campaign = Some(c);
                true
            }
            Err(e) => { godot_warn!("save load failed: {e}"); false }
        }
    }

    #[func]
    fn campaign_state(&self) -> VarDictionary {
        let (Some(c), Some(cs)) = (&self.content, &self.campaign) else { return VarDictionary::new() };
        let mut govs = VarArray::new();
        for g in &cs.governors {
            let rival_name = g.rival.as_ref().and_then(|r| cs.gov(r)).map(|r| r.name.clone()).unwrap_or_default();
            let mission_scene = g.mission.as_ref().and_then(|m| c.mission(m)).map(|m| m.scene.clone()).unwrap_or_default();
            let d = vdict! {
                "mission_scene" => mission_scene.as_str(),
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
        let mut lines: Vec<String> = cs.end_night(c);
        if let (Some(d), Some(m)) = (&self.market_def, &mut self.market) {
            m.open_session();
            for _ in 0..d.night_ticks { m.step(d); }
            for h in m.event(d, "night", 1.0) { lines.push(format!("Exchange: {h}")); }
            // The night's biggest mover, for the war-room report.
            if let Some((i, q)) = m.quotes.iter().enumerate().max_by(|a, b| {
                let ca = ((a.1.price - a.1.open) / a.1.open.max(0.01)).abs();
                let cb = ((b.1.price - b.1.open) / b.1.open.max(0.01)).abs();
                ca.partial_cmp(&cb).unwrap_or(std::cmp::Ordering::Equal)
            }) {
                let ch = (q.price - q.open) / q.open.max(0.01) * 100.0;
                let c = &d.companies[i];
                lines.push(format!("Exchange: {} ({}) closes at {}, {:+.1}% on the session.", c.name, c.ticker, eighths(q.price), ch));
            }
        }
        lines.iter().map(|x| s(x)).collect()
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
        self.begin_mission(&gov_id, paranoia, &mission_id)
    }

    /// Start the mission against one named governor (the war room's choice,
    /// or a free-play menu item).
    #[func]
    fn start_mission_for(&mut self, gov: GString) -> bool {
        let id = gov.to_string();
        let Some(c) = &self.content else { return false };
        let found = self.campaign.as_ref().and_then(|cs| cs.gov(&id).map(|g| (g.paranoia, g.mission.clone())))
            .or_else(|| c.governor(&id).map(|g| (g.paranoia, g.mission.clone())));
        let Some((paranoia, Some(mission_id))) = found else { return false };
        self.begin_mission(&id, paranoia, &mission_id)
    }

    fn begin_mission(&mut self, gov_id: &str, paranoia: f32, mission_id: &str) -> bool {
        let Some(c) = &self.content else { return false };
        self.mission = Mission::new(c, mission_id, paranoia);
        self.mission_gov = Some(gov_id.to_string());
        let festival = self.mission.as_ref().and_then(|m| m.def.festival.clone());
        let mut w = world();
        w.alarm = false;
        w.corpses.clear();
        w.festival = festival;
        self.mission.is_some()
    }

    /// The scene of the active mission.
    #[func]
    fn mission_scene(&self) -> GString {
        match self.mission.as_ref().map(|m| m.def.scene.as_str()) {
            Some(x) if !x.is_empty() => s(x),
            _ => s("res://scenes/province.tscn"),
        }
    }

    /// Dry dispatch line for the debrief ("" if the mission has none).
    #[func]
    fn mission_dispatch(&self, method: GString) -> GString {
        self.mission.as_ref().and_then(|m| m.dispatch_for(method_from(&method.to_string()))).map(s).unwrap_or_default()
    }

    // ---- Surveillance ------------------------------------------------------

    #[func]
    fn sv_add_feed(&mut self, id: GString, zone: GString) {
        if let Some(v) = self.mission.as_mut().and_then(|m| m.surveillance.as_mut()) { v.add_feed(&id.to_string(), &zone.to_string()); }
    }

    #[func]
    fn sv_loop_zone(&mut self, zone: GString) {
        if let Some(v) = self.mission.as_mut().and_then(|m| m.surveillance.as_mut()) { v.loop_zone(&zone.to_string()); }
    }

    /// Breaker panel: returns true if the zone is now dark.
    #[func]
    fn sv_toggle_power(&mut self, zone: GString) -> bool {
        self.mission.as_mut().and_then(|m| m.surveillance.as_mut()).map(|v| v.toggle_power(&zone.to_string())).unwrap_or(false)
    }

    #[func]
    fn sv_restore_zone(&mut self, zone: GString) {
        if let Some(v) = self.mission.as_mut().and_then(|m| m.surveillance.as_mut()) { v.restore_zone(&zone.to_string()); }
    }

    #[func]
    fn sv_pull(&mut self, id: GString) {
        if let Some(v) = self.mission.as_mut().and_then(|m| m.surveillance.as_mut()) { v.pull(&id.to_string()); }
    }

    #[func]
    fn sv_jam(&mut self, id: GString, secs: f32) {
        if let Some(v) = self.mission.as_mut().and_then(|m| m.surveillance.as_mut()) { v.jam(&id.to_string(), secs); }
    }

    #[func]
    fn sv_destroy(&mut self, id: GString) {
        if let Some(v) = self.mission.as_mut().and_then(|m| m.surveillance.as_mut()) { v.destroy(&id.to_string()); }
    }

    /// A crime goes on tape. Returns false if the feed was not recording.
    #[func]
    fn sv_record(&mut self, id: GString, kill: bool) -> bool {
        self.mission.as_mut().map(|m| m.record_crime(&id.to_string(), kill)).unwrap_or(false)
    }

    #[func]
    fn sv_reassign(&mut self, zone: GString) {
        if let Some(v) = self.mission.as_mut().and_then(|m| m.surveillance.as_mut()) { v.reassign(&zone.to_string()); }
    }

    #[func]
    fn sv_set_staffed(&mut self, on: bool) {
        if let Some(v) = self.mission.as_mut().and_then(|m| m.surveillance.as_mut()) { v.set_staffed(on); }
    }

    #[func]
    fn sv_feed_live(&self, id: GString) -> bool {
        self.mission.as_ref().and_then(|m| m.surveillance.as_ref()).map(|v| v.feed_live(&id.to_string())).unwrap_or(false)
    }

    #[func]
    fn sv_zone_dark(&self, zone: GString) -> bool {
        self.mission.as_ref().and_then(|m| m.surveillance.as_ref()).map(|v| v.zone_dark(&zone.to_string())).unwrap_or(false)
    }

    #[func]
    fn sv_zone_reassigned(&self, zone: GString) -> bool {
        self.mission.as_ref().and_then(|m| m.surveillance.as_ref()).map(|v| v.zone_reassigned(&zone.to_string())).unwrap_or(false)
    }

    /// For the HUD: feeds live, feeds total, crimes on tape, and the dark zone
    /// closest to being noticed.
    #[func]
    fn sv_state(&self) -> VarDictionary {
        let Some(v) = self.mission.as_ref().and_then(|m| m.surveillance.as_ref()) else { return VarDictionary::new() };
        let (zone, secs) = v.next_notice().unwrap_or((String::new(), 0.0));
        vdict! {
            "live" => v.live_count() as i64, "total" => v.feeds.len() as i64, "recorded" => v.recorded as i64,
            "next_zone" => zone.as_str(), "next_secs" => secs, "heat" => v.heat, "staffed" => v.staffed,
        }
    }

    // ---- Pursuit -----------------------------------------------------------

    #[func]
    fn pursuit_params(&self) -> VarDictionary {
        let Some(p) = self.mission.as_ref().and_then(|m| m.pursuit.as_ref()).map(|p| &p.params) else { return VarDictionary::new() };
        vdict! {
            "sight_range" => p.sight_range, "bike_speed" => p.bike_speed, "spawn_behind" => p.spawn_behind,
            "shot_range" => p.shot_range, "shot_interval" => p.shot_interval, "shot_damage" => p.shot_damage,
            "shot_hit_chance" => p.shot_hit_chance, "road_first_chunk" => p.road_first_chunk as i64,
            "safehouse_chunk" => p.safehouse_chunk as i64, "lose_seconds" => p.lose_seconds,
        }
    }

    /// Start the chase. Returns { "bikes": n, "drones": n }.
    #[func]
    fn pursuit_start(&mut self) -> VarDictionary {
        let (b, d) = self.mission.as_mut().map(|m| m.start_pursuit()).unwrap_or((0, 0));
        vdict! { "bikes" => b as i64, "drones" => d as i64 }
    }

    #[func]
    fn pursuit_tick(&mut self, dt: f32, seen: bool) {
        if let Some(m) = &mut self.mission { m.pursuit_tick(dt, seen); }
    }

    #[func]
    fn pursuit_active(&self) -> bool {
        self.mission.as_ref().and_then(|m| m.pursuit.as_ref()).is_some_and(|p| p.active())
    }

    #[func]
    fn pursuit_unseen(&self) -> f32 {
        self.mission.as_ref().and_then(|m| m.pursuit.as_ref()).map(|p| p.unseen).unwrap_or(0.0)
    }

    #[func]
    fn reach_safehouse(&mut self) {
        if let Some(m) = &mut self.mission { m.reach_safehouse(); }
    }

    /// Bystanders crushed so far (the level reports the running total).
    #[func]
    fn report_crushed(&mut self, total: i64) {
        if let Some(m) = &mut self.mission { m.crushed = total.max(0) as u32; }
    }

    #[func]
    fn report_bystander(&mut self) {
        if let Some(m) = &mut self.mission { m.bystanders += 1; }
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
            "weapons" => &m.weapons.iter().map(|w| s(w)).collect::<PackedStringArray>(),
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
                MissionEvent::PursuitOver { lost } => vdict! { "type" => "pursuit_over", "lost" => lost },
                MissionEvent::Feed(f) => match f {
                    SurveillanceEvent::FeedChanged { id, live } => vdict! { "type" => "feed_changed", "id" => id.as_str(), "live" => live },
                    SurveillanceEvent::Noticed { zone } => vdict! { "type" => "feed_noticed", "zone" => zone.as_str() },
                    SurveillanceEvent::Destroyed { id, zone } => vdict! { "type" => "feed_destroyed", "id" => id.as_str(), "zone" => zone.as_str() },
                    SurveillanceEvent::Recorded { id, zone, kill } => vdict! { "type" => "recorded", "id" => id.as_str(), "zone" => zone.as_str(), "kill" => kill },
                    SurveillanceEvent::RecordAlarm => vdict! { "type" => "record_alarm" },
                    SurveillanceEvent::Reassigned { zone } => vdict! { "type" => "reassigned", "zone" => zone.as_str() },
                    SurveillanceEvent::ReassignEnded { zone } => vdict! { "type" => "reassign_ended", "zone" => zone.as_str() },
                },
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
        if let Some(g) = self.mission_gov.clone() {
            let key = format!("death:{g}");
            let news = self.market_event_inner(&key, 1.0);
            self.pending_news(news);
        }
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

    /// Draw another carried weapon (ammo is kept per weapon).
    #[func]
    fn switch_weapon(&mut self, id: GString) -> bool {
        self.mission.as_mut().map(|m| m.switch_weapon(&id.to_string())).unwrap_or(false)
    }

    #[func]
    fn add_ammo(&mut self, id: GString, n: i64) {
        if let Some(m) = &mut self.mission { m.add_ammo(&id.to_string(), n.max(0) as u32); }
    }

    #[func]
    fn reload(&mut self) -> bool {
        self.mission.as_mut().map(|m| m.reload()).unwrap_or(false)
    }

    /// Apply the finished mission to the campaign; returns the report text.
    #[func]
    fn apply_mission_result(&mut self, method: GString) -> GString {
        let (Some(c), Some(cs), Some(gov)) = (&self.content, &mut self.campaign, &self.mission_gov) else { return GString::new() };
        let extra = self.mission.as_ref().map(|m| m.extra_heat()).unwrap_or(0.0);
        let text = cs.apply_mission(c, gov, method_from(&method.to_string()), extra);
        let key = format!("removed:{gov}");
        self.mission = None;
        if method.to_string() != "failed" {
            let news = self.market_event_inner(&key, 1.0);
            self.pending_news(news);
        }
        s(&text)
    }

    // ---- Exchange ----------------------------------------------------------

    fn ensure_market(&mut self) {
        if self.market.is_none() {
            if let Some(d) = &self.market_def {
                self.market = Some(Market::new(d, 1980));
            }
        }
    }

    fn market_event_inner(&mut self, key: &str, scale: f32) -> Vec<String> {
        self.ensure_market();
        let mut out = match (&self.market_def, &mut self.market) {
            (Some(d), Some(m)) => m.event(d, key, scale),
            _ => vec![],
        };
        // Show people by name on the wire. Future characters only need an
        // entry here (or in their own content table) to read nicely.
        if let Some(c) = &self.content {
            let mut govs: Vec<_> = c.governors.iter().collect();
            govs.sort_by_key(|g| std::cmp::Reverse(g.id.len()));
            for line in out.iter_mut() {
                for g in &govs {
                    if line.contains(&g.id) {
                        *line = line.replace(&g.id, &format!("{}, {}", g.name, g.title));
                    }
                }
            }
            if let Some(m) = &mut self.market {
                let n = m.news.len();
                for (i, line) in out.iter().enumerate() {
                    if let Some(x) = m.news.get_mut(n.saturating_sub(out.len()) + i) { x.text = line.clone(); }
                }
            }
        }
        out
    }

    fn pending_news(&mut self, news: Vec<String>) {
        if news.is_empty() { return; }
        let arr: PackedStringArray = news.iter().map(|x| s(x)).collect();
        self.base_mut().call_deferred("emit_signal", &["market_news".to_variant(), arr.to_variant()]);
    }

    #[signal]
    fn market_news(headlines: PackedStringArray);

    /// Advance the exchange by real seconds. True if prices changed.
    #[func]
    fn market_tick(&mut self, dt: f32) -> bool {
        self.ensure_market();
        match (&self.market_def, &mut self.market) {
            (Some(d), Some(m)) => m.advance(d, dt),
            _ => false,
        }
    }

    /// Report a game event (see data/market.ron for keys). Returns headlines
    /// and also emits `market_news`.
    #[func]
    fn market_event(&mut self, key: GString, scale: f32) -> PackedStringArray {
        let news = self.market_event_inner(&key.to_string(), scale);
        self.pending_news(news.clone());
        news.iter().map(|x| s(x)).collect()
    }

    /// Buy (qty > 0) or sell (qty < 0). Returns "" or an error.
    #[func]
    fn market_trade(&mut self, id: GString, qty: i64) -> GString {
        self.ensure_market();
        match &mut self.market {
            Some(m) => match m.trade(&id.to_string(), qty) { Ok(()) => GString::new(), Err(e) => s(&e) },
            None => s("The exchange is closed."),
        }
    }

    #[func]
    fn market_state(&mut self) -> VarDictionary {
        self.ensure_market();
        let (Some(d), Some(m)) = (&self.market_def, &self.market) else { return VarDictionary::new() };
        let mut rows = VarArray::new();
        for (i, c) in d.companies.iter().enumerate() {
            let q = &m.quotes[i];
            let held = *m.holdings.get(&c.id).unwrap_or(&0);
            let hist: PackedFloat32Array = q.history.iter().copied().collect();
            let sector = d.sectors.iter().find(|x| x.id == c.sector).map(|x| x.name.clone()).unwrap_or_default();
            let row = vdict! {
                "id" => c.id.as_str(),
                "name" => c.name.as_str(),
                "ticker" => c.ticker.as_str(),
                "sector" => sector.as_str(),
                "description" => c.description.as_str(),
                "price" => q.price,
                "price_text" => eighths(q.price).as_str(),
                "open" => q.open,
                "change" => (q.price - q.open) / q.open.max(0.01),
                "history" => &hist,
                "held" => held,
                "avg_cost" => *m.cost.get(&c.id).unwrap_or(&0.0),
            };
            rows.push(&row.to_variant());
        }
        let mut news = PackedStringArray::new();
        for n in m.news.iter().rev().take(8) { news.push(&s(&n.text)); }
        vdict! {
            "exchange" => d.exchange.as_str(),
            "currency" => d.currency.as_str(),
            "cash" => m.cash,
            "portfolio" => m.portfolio_value(),
            "start_cash" => d.start_cash,
            "companies" => &rows,
            "news" => &news,
            "tick" => m.tick as i64,
        }
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
