//! Festival crowd [INVENTED]. Hundreds of pilgrims flow along polyline lanes.
//! Cheap by construction: an agent is a distance along a lane and a sideways
//! offset, so the terrain never has to be queried. The bridge draws most of them
//! as instanced impostors and hands the ones nearest the player to full NPCs.
//!
//! Crowd rules from Mission2.md: density flows along the route, crowds part for
//! the governor's retinue, open violence starts a panic wave that spreads
//! outward and reroutes people, and members are witnesses with limited sight
//! and memory.

use serde::{Deserialize, Serialize};

use crate::rng::Rng;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct CrowdParams {
    /// Total agents (impostors plus the ones promoted to full NPCs).
    pub count: u32,
    /// Agents nearer than this may become full NPCs (m).
    pub near_radius: f32,
    /// Full NPC pool. Measured on the target machine; see README.
    pub full_npcs: u32,
    pub walk_speed: f32,
    pub walk_speed_spread: f32,
    /// Chance per second that a walker stops to stand a while.
    pub pause_chance: f32,
    pub pause_seconds: f32,
    /// Retinue push: distance kept and how fast people give way.
    pub part_radius: f32,
    pub part_rate: f32,
    pub panic_speed: f32,
    /// Speed of the wave front (m/s) and how far it travels (m).
    pub wave_speed: f32,
    pub wave_radius: f32,
    /// Seconds a person runs before calming down, where a lane has no exit.
    pub panic_seconds: f32,
    /// People per grid cell on a stair at which a panic turns into a crush.
    pub crush_density: f32,
    /// Chance per second of going down in a crush.
    pub crush_chance: f32,
    /// How far a witness can make out what happened (m).
    pub witness_range: f32,
    /// Density at which the press itself starts to hide things (people per cell).
    pub press_density: f32,
    /// Seconds before a witness forgets.
    pub witness_memory: f32,
    /// A witness tells any guard within this range (m).
    pub report_range: f32,
    /// Heat per person crushed.
    pub crush_heat: f32,
}

impl Default for CrowdParams {
    fn default() -> Self {
        Self {
            count: 420,
            near_radius: 17.0,
            full_npcs: 18,
            walk_speed: 1.15,
            walk_speed_spread: 0.3,
            pause_chance: 0.03,
            pause_seconds: 5.0,
            part_radius: 5.0,
            part_rate: 2.2,
            panic_speed: 4.2,
            wave_speed: 11.0,
            wave_radius: 70.0,
            panic_seconds: 16.0,
            crush_density: 9.0,
            crush_chance: 0.1,
            witness_range: 16.0,
            press_density: 5.0,
            witness_memory: 40.0,
            report_range: 5.0,
            crush_heat: 1.5,
        }
    }
}

const CELL: f32 = 4.0;

#[derive(Clone, Debug)]
pub struct Lane {
    points: Vec<[f32; 3]>,
    /// Cumulative horizontal distance at each point.
    dist: Vec<f32>,
    pub width: f32,
    pub closed: bool,
    pub weight: f32,
    length: f32,
}

fn lerp3(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
}

fn dist_xz(a: [f32; 3], b: [f32; 3]) -> f32 {
    ((a[0] - b[0]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
}

impl Lane {
    pub fn new(points: Vec<[f32; 3]>, width: f32, closed: bool, weight: f32) -> Self {
        let mut pts = points;
        if closed && pts.len() > 1 {
            let first = pts[0];
            pts.push(first);
        }
        let mut dist = Vec::with_capacity(pts.len());
        let mut d = 0.0;
        for i in 0..pts.len() {
            if i > 0 { d += dist_xz(pts[i - 1], pts[i]); }
            dist.push(d);
        }
        Self { length: d, points: pts, dist, width, closed, weight }
    }

    fn segment(&self, s: f32) -> usize {
        let mut i = self.dist.partition_point(|d| *d <= s);
        i = i.clamp(1, self.points.len().max(2) - 1);
        i - 1
    }

    /// World position at distance `s`, and the unit tangent in XZ.
    pub fn sample(&self, s: f32) -> ([f32; 3], [f32; 2]) {
        let i = self.segment(s);
        let (a, b) = (self.points[i], self.points[i + 1]);
        let seg = (self.dist[i + 1] - self.dist[i]).max(1e-4);
        let p = lerp3(a, b, ((s - self.dist[i]) / seg).clamp(0.0, 1.0));
        let (dx, dz) = (b[0] - a[0], b[2] - a[2]);
        let l = (dx * dx + dz * dz).sqrt().max(1e-4);
        (p, [dx / l, dz / l])
    }

    /// Stairs: where a panic turns dangerous.
    fn pinched(&self, s: f32) -> bool {
        let i = self.segment(s);
        let (a, b) = (self.points[i], self.points[i + 1]);
        (b[1] - a[1]).abs() / dist_xz(a, b).max(1e-4) > 0.2
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum AgentState {
    Walk,
    Stand(f32),
    Panic(f32),
    /// Reached an exit in a panic; gone from the festival.
    Gone,
    /// Died in a crush or by violence; lies where it fell.
    Down,
}

#[derive(Clone, Debug)]
pub struct Agent {
    pub lane: usize,
    pub s: f32,
    pub lateral: f32,
    pub lateral_home: f32,
    pub speed: f32,
    pub dir: f32,
    pub state: AgentState,
    pub pos: [f32; 3],
    pub heading: [f32; 2],
    pub tint: u8,
    /// Seconds a witnessed event is remembered, and where it happened.
    pub memory: f32,
    pub saw: [f32; 3],
    /// Handed to a full NPC; the impostor is hidden.
    pub promoted: bool,
}

#[derive(Clone, Copy, Debug)]
struct Wave {
    origin: [f32; 3],
    radius: f32,
}

#[derive(Clone, Debug)]
pub struct CrowdSim {
    pub params: CrowdParams,
    pub lanes: Vec<Lane>,
    pub agents: Vec<Agent>,
    waves: Vec<Wave>,
    /// Ways off the grounds: panicking people head here and vanish.
    exits: Vec<([f32; 3], f32)>,
    retinue: Option<([f32; 3], f32)>,
    grid: std::collections::HashMap<(i32, i32), u16>,
    pub crushed: u32,
    rng: Rng,
}

impl CrowdSim {
    pub fn new(params: CrowdParams, seed: u64) -> Self {
        Self {
            params,
            lanes: vec![],
            agents: vec![],
            waves: vec![],
            exits: vec![],
            retinue: None,
            grid: Default::default(),
            crushed: 0,
            rng: Rng::new(seed),
        }
    }

    pub fn add_lane(&mut self, points: Vec<[f32; 3]>, width: f32, closed: bool, weight: f32) {
        if points.len() >= 2 {
            self.lanes.push(Lane::new(points, width, closed, weight));
        }
    }

    pub fn add_exit(&mut self, at: [f32; 3], radius: f32) {
        self.exits.push((at, radius));
    }

    /// Where this agent will be `metres` further along its lane.
    pub fn ahead_of(&self, a: &Agent, metres: f32) -> [f32; 3] {
        let lane = &self.lanes[a.lane];
        let s = a.s + a.dir * metres;
        let s = if lane.closed { s.rem_euclid(lane.length.max(1.0)) } else { s.clamp(0.0, lane.length) };
        let (p, t) = lane.sample(s);
        [p[0] - t[1] * a.lateral, p[1], p[2] + t[0] * a.lateral]
    }

    /// Scatter `params.count` agents over the lanes, in proportion to length
    /// times weight.
    pub fn populate(&mut self) {
        let total: f32 = self.lanes.iter().map(|l| l.length * l.weight).sum();
        if total <= 0.0 { return; }
        let count = self.params.count as usize;
        self.agents.reserve(count);
        for (li, lane) in self.lanes.iter().enumerate() {
            let n = ((lane.length * lane.weight / total) * count as f32).round() as usize;
            for _ in 0..n {
                let s = self.rng.range(0.0, lane.length);
                let lateral = self.rng.range(-lane.width * 0.5, lane.width * 0.5);
                let speed = self.params.walk_speed + self.rng.range(-1.0, 1.0) * self.params.walk_speed_spread;
                // Closed lanes circulate both ways at the same pace; open lanes
                // run one way and wrap, like a queue that never ends.
                let dir = if lane.closed && self.rng.chance(0.35) { -1.0 } else { 1.0 };
                let tint = (self.rng.next_f32() * 5.0) as u8;
                let (p, h) = lane.sample(s);
                self.agents.push(Agent {
                    lane: li,
                    s,
                    lateral,
                    lateral_home: lateral,
                    speed: speed.max(0.4),
                    dir,
                    state: AgentState::Walk,
                    pos: p,
                    heading: h,
                    tint,
                    memory: 0.0,
                    saw: [0.0; 3],
                    promoted: false,
                });
            }
        }
    }

    pub fn set_retinue(&mut self, r: Option<([f32; 3], f32)>) {
        self.retinue = r;
    }

    /// Open violence at `origin`: a wave spreads out from there.
    pub fn start_panic(&mut self, origin: [f32; 3]) {
        if self.waves.iter().any(|w| dist_xz(w.origin, origin) < 6.0) { return; }
        self.waves.push(Wave { origin, radius: 0.0 });
    }

    pub fn panicking(&self) -> bool {
        !self.waves.is_empty() || self.agents.iter().any(|a| matches!(a.state, AgentState::Panic(_)))
    }

    fn cell(p: [f32; 3]) -> (i32, i32) {
        ((p[0] / CELL).floor() as i32, (p[2] / CELL).floor() as i32)
    }

    /// People per cell around a point (0 in the open).
    pub fn density_at(&self, p: [f32; 3]) -> f32 {
        *self.grid.get(&Self::cell(p)).unwrap_or(&0) as f32
    }

    /// Something violent happened at `at`. Each person near enough may see it;
    /// the denser the press, the fewer can. Returns how many saw.
    pub fn witness(&mut self, at: [f32; 3]) -> u32 {
        let range = self.params.witness_range;
        let press = self.density_at(at);
        // The press hides what happens inside it: at press_density the chance
        // to see halves, and it keeps falling from there.
        let see = 1.0 / (1.0 + press / self.params.press_density.max(0.1)).powi(2);
        let memory = self.params.witness_memory;
        let mut seen = 0;
        for a in &mut self.agents {
            if !matches!(a.state, AgentState::Walk | AgentState::Stand(_)) { continue; }
            let d = dist_xz(a.pos, at);
            if d > range { continue; }
            // Limited sight: mostly what is ahead of them.
            let to = [(at[0] - a.pos[0]) / d.max(0.1), (at[2] - a.pos[2]) / d.max(0.1)];
            let facing = to[0] * a.heading[0] * a.dir + to[1] * a.heading[1] * a.dir;
            let chance = see * if facing > 0.0 { 0.9 } else { 0.25 };
            if self.rng.chance(chance) {
                a.memory = memory;
                a.saw = at;
                seen += 1;
            }
        }
        seen
    }

    /// Witnesses standing near a guard tell him what they saw. Returns where
    /// it happened, once per witness.
    pub fn take_reports(&mut self, guards: &[[f32; 3]]) -> Vec<[f32; 3]> {
        let r = self.params.report_range;
        let mut out = vec![];
        for a in &mut self.agents {
            if a.memory <= 0.0 { continue; }
            if guards.iter().any(|g| dist_xz(*g, a.pos) < r) {
                a.memory = 0.0;
                out.push(a.saw);
            }
        }
        out
    }

    /// Nearest agents a full NPC could stand in for.
    pub fn nearest(&self, at: [f32; 3], radius: f32, k: usize) -> Vec<usize> {
        let mut v: Vec<(f32, usize)> = self
            .agents
            .iter()
            .enumerate()
            .filter(|(_, a)| matches!(a.state, AgentState::Walk | AgentState::Stand(_)))
            .map(|(i, a)| (dist_xz(a.pos, at), i))
            .filter(|(d, _)| *d < radius)
            .collect();
        v.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        v.truncate(k);
        v.into_iter().map(|(_, i)| i).collect()
    }

    pub fn tick(&mut self, dt: f32) {
        let p = self.params.clone();
        for w in &mut self.waves {
            w.radius += p.wave_speed * dt;
        }
        // Density from the last frame is good enough, and is what the press
        // rule reads.
        self.grid.clear();
        for a in &self.agents {
            if matches!(a.state, AgentState::Gone | AgentState::Down) { continue; }
            *self.grid.entry(Self::cell(a.pos)).or_insert(0) += 1;
        }
        let lanes = std::mem::take(&mut self.lanes);
        for i in 0..self.agents.len() {
            let mut a = self.agents[i].clone();
            if matches!(a.state, AgentState::Gone | AgentState::Down) { continue; }
            if a.memory > 0.0 { a.memory -= dt; }
            let lane = &lanes[a.lane];

            // Caught by a wave: run away from it, along the lane.
            if !matches!(a.state, AgentState::Panic(_)) {
                for w in &self.waves {
                    if dist_xz(a.pos, w.origin) < w.radius {
                        let (_, t) = lane.sample(a.s);
                        let along = (a.pos[0] - w.origin[0]) * t[0] + (a.pos[2] - w.origin[2]) * t[1];
                        a.dir = if along >= 0.0 { 1.0 } else { -1.0 };
                        // Reroute: if there is a way out, take the direction
                        // along the lane that gets closer to it.
                        if let Some(best) = nearest_exit(&self.exits, a.pos) {
                            let look = 8.0;
                            let wrap = |s: f32| if lane.closed { s.rem_euclid(lane.length.max(1.0)) } else { s.clamp(0.0, lane.length) };
                            let (ahead, _) = lane.sample(wrap(a.s + look));
                            let (behind, _) = lane.sample(wrap(a.s - look));
                            a.dir = if dist_xz(ahead, best) <= dist_xz(behind, best) { 1.0 } else { -1.0 };
                        }
                        a.state = AgentState::Panic(p.panic_seconds * self.rng.range(0.7, 1.3));
                        break;
                    }
                }
            }

            let mut speed = a.speed;
            let mut lateral_target = a.lateral_home;

            // Part for the retinue: push sideways out of its way and slow down.
            if let Some((rp, rr)) = self.retinue {
                let d = dist_xz(a.pos, rp);
                let reach = rr.max(p.part_radius);
                if d < reach && !matches!(a.state, AgentState::Panic(_)) {
                    let (_, t) = lane.sample(a.s);
                    let side = -(a.pos[0] - rp[0]) * t[1] + (a.pos[2] - rp[2]) * t[0];
                    let sign = if side >= 0.0 { 1.0 } else { -1.0 };
                    lateral_target = sign * (lane.width * 0.5 + reach * 0.6);
                    speed *= 0.25 + 0.75 * (d / reach);
                }
            }

            match a.state {
                AgentState::Walk => {
                    if self.rng.chance(p.pause_chance * dt) {
                        a.state = AgentState::Stand(p.pause_seconds * self.rng.range(0.5, 1.5));
                    }
                }
                AgentState::Stand(t) => {
                    speed = 0.0;
                    a.state = if t - dt <= 0.0 { AgentState::Walk } else { AgentState::Stand(t - dt) };
                }
                AgentState::Panic(t) => {
                    speed = p.panic_speed + a.speed;
                    if self.exits.iter().any(|(e, r)| dist_xz(a.pos, *e) < *r) {
                        a.state = AgentState::Gone;
                        self.agents[i] = a;
                        continue;
                    }
                    let dense = *self.grid.get(&Self::cell(a.pos)).unwrap_or(&0) as f32;
                    if dense >= p.crush_density && lane.pinched(a.s) && self.rng.chance(p.crush_chance * dt) {
                        a.state = AgentState::Down;
                        self.crushed += 1;
                    } else if t - dt <= 0.0 {
                        a.state = AgentState::Walk;
                    } else {
                        a.state = AgentState::Panic(t - dt);
                    }
                }
                _ => {}
            }

            a.s += a.dir * speed * dt;
            if lane.closed {
                a.s = a.s.rem_euclid(lane.length.max(1.0));
            } else if a.s < 0.0 || a.s > lane.length {
                if matches!(a.state, AgentState::Panic(_)) {
                    // Off the end of a lane in a panic: fled the grounds.
                    a.state = AgentState::Gone;
                } else {
                    a.s = a.s.rem_euclid(lane.length.max(1.0));
                }
            }
            a.lateral += (lateral_target - a.lateral) * (1.0 - (-p.part_rate * dt).exp());
            let (pos, t) = lane.sample(a.s.clamp(0.0, lane.length));
            a.heading = t;
            a.pos = [pos[0] - t[1] * a.lateral, pos[1], pos[2] + t[0] * a.lateral];
            self.agents[i] = a;
        }
        self.lanes = lanes;
        let limit = p.wave_radius;
        self.waves.retain(|w| w.radius < limit);
    }

    /// An agent died in front of a full NPC's body (shot, or taken down).
    pub fn kill_agent(&mut self, i: usize) {
        if let Some(a) = self.agents.get_mut(i) {
            a.state = AgentState::Down;
            a.promoted = true;
        }
    }
}

fn nearest_exit(exits: &[([f32; 3], f32)], at: [f32; 3]) -> Option<[f32; 3]> {
    exits
        .iter()
        .map(|(e, _)| *e)
        .min_by(|a, b| dist_xz(*a, at).partial_cmp(&dist_xz(*b, at)).unwrap_or(std::cmp::Ordering::Equal))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn panic_reroutes_a_closed_loop_toward_the_exit() {
        let mut c = CrowdSim::new(CrowdParams { count: 80, panic_seconds: 60.0, ..Default::default() }, 5);
        c.add_lane(vec![[0.0, 0.0, 0.0], [40.0, 0.0, 0.0], [40.0, 0.0, 40.0], [0.0, 0.0, 40.0]], 4.0, true, 1.0);
        c.add_exit([0.0, 0.0, 0.0], 6.0);
        c.populate();
        run(&mut c, 0.1);
        c.start_panic([20.0, 0.0, 20.0]);
        run(&mut c, 30.0);
        let gone = c.agents.iter().filter(|a| a.state == AgentState::Gone).count();
        assert!(gone > 60, "only {gone} of 80 got out");
    }

    #[test]
    fn ahead_of_is_further_along_the_lane() {
        let mut c = sim(5);
        run(&mut c, 0.1);
        let a = c.agents[0].clone();
        let p = c.ahead_of(&a, 3.0);
        assert!((p[2] - a.pos[2]).abs() <= 3.2);
    }

    fn sim(count: u32) -> CrowdSim {
        let mut c = CrowdSim::new(CrowdParams { count, ..Default::default() }, 7);
        c.add_lane(vec![[0.0, 0.0, 0.0], [0.0, 0.0, 100.0]], 6.0, false, 1.0);
        c.populate();
        c
    }

    fn run(c: &mut CrowdSim, secs: f32) {
        let mut t = 0.0;
        while t < secs {
            c.tick(1.0 / 30.0);
            t += 1.0 / 30.0;
        }
    }

    #[test]
    fn people_flow_along_the_lane() {
        let mut c = sim(50);
        assert_eq!(c.agents.len(), 50);
        let before: Vec<f32> = c.agents.iter().map(|a| a.s).collect();
        run(&mut c, 5.0);
        let moved = c.agents.iter().zip(&before).filter(|(a, b)| (a.s - **b).abs() > 1.0).count();
        assert!(moved > 30, "moved {moved}");
        assert!(c.agents.iter().all(|a| a.pos[2] >= -5.0 && a.pos[2] <= 105.0));
    }

    #[test]
    fn crowd_parts_for_the_retinue() {
        let mut c = sim(200);
        run(&mut c, 0.1);
        let centre = [0.0, 0.0, 50.0];
        let near = |c: &CrowdSim| c.agents.iter().filter(|a| dist_xz(a.pos, centre) < 2.0).count();
        let before = near(&c);
        c.set_retinue(Some((centre, 6.0)));
        run(&mut c, 6.0);
        assert!(near(&c) < before.max(2), "still {} of {before} in the way", near(&c));
    }

    #[test]
    fn panic_spreads_outward_from_the_event() {
        let mut c = sim(200);
        run(&mut c, 0.1);
        c.start_panic([0.0, 0.0, 50.0]);
        assert!(c.panicking());
        run(&mut c, 0.5);
        let panicking = |c: &CrowdSim, lo: f32, hi: f32| {
            c.agents.iter().filter(|a| {
                let d = dist_xz(a.pos, [0.0, 0.0, 50.0]);
                d >= lo && d < hi && matches!(a.state, AgentState::Panic(_))
            }).count()
        };
        assert!(panicking(&c, 0.0, 6.0) > 0, "nobody close panics");
        assert_eq!(panicking(&c, 25.0, 200.0), 0, "the wave outran itself");
        run(&mut c, 3.0);
        assert!(panicking(&c, 20.0, 200.0) > 0, "the wave did not spread");
    }

    #[test]
    fn panicking_people_flee_off_the_ends_of_open_lanes() {
        let mut c = sim(100);
        run(&mut c, 0.1);
        c.start_panic([0.0, 0.0, 50.0]);
        run(&mut c, 20.0);
        assert!(c.agents.iter().filter(|a| a.state == AgentState::Gone).count() > 20);
    }

    #[test]
    fn stairs_crush_only_in_a_dense_panic() {
        let stairs = vec![[0.0, 0.0, 0.0], [0.0, 10.0, 30.0]];
        let mut calm = CrowdSim::new(CrowdParams { count: 300, crush_chance: 2.0, ..Default::default() }, 3);
        calm.add_lane(stairs.clone(), 3.0, false, 1.0);
        calm.populate();
        run(&mut calm, 3.0);
        assert_eq!(calm.crushed, 0);
        let mut mob = CrowdSim::new(CrowdParams { count: 300, crush_chance: 2.0, ..Default::default() }, 3);
        mob.add_lane(stairs, 3.0, false, 1.0);
        mob.populate();
        run(&mut mob, 0.1);
        mob.start_panic([0.0, 5.0, 15.0]);
        run(&mut mob, 3.0);
        assert!(mob.crushed > 0);
    }

    #[test]
    fn the_press_hides_things_and_witnesses_forget() {
        // Same spot, thin crowd against a press.
        let seen = |n: u32| {
            let mut c = CrowdSim::new(CrowdParams { count: n, witness_memory: 4.0, ..Default::default() }, 9);
            c.add_lane(vec![[0.0, 0.0, 0.0], [0.0, 0.0, 12.0]], 2.0, false, 1.0);
            c.populate();
            run(&mut c, 0.1);
            c.witness([0.0, 0.0, 6.0]) as f32 / n as f32
        };
        assert!(seen(200) < seen(10), "a dense press should see less per head");

        let mut c = sim(60);
        run(&mut c, 0.1);
        let w = c.witness([0.0, 0.0, 50.0]);
        assert!(w > 0);
        let at = c.agents.iter().find(|a| a.memory > 0.0).unwrap().pos;
        assert!(!c.take_reports(&[at]).is_empty());
        let mut c = sim(60);
        run(&mut c, 0.1);
        c.witness([0.0, 0.0, 50.0]);
        let forget = c.params.witness_memory + 1.0;
        run(&mut c, forget);
        assert!(c.agents.iter().all(|a| a.memory <= 0.0));
    }

    #[test]
    fn nearest_is_sorted_and_limited() {
        let c = {
            let mut c = sim(100);
            run(&mut c, 0.1);
            c
        };
        let near = c.nearest([0.0, 0.0, 50.0], 30.0, 5);
        assert_eq!(near.len(), 5);
        let d: Vec<f32> = near.iter().map(|i| dist_xz(c.agents[*i].pos, [0.0, 0.0, 50.0])).collect();
        assert!(d.windows(2).all(|w| w[0] <= w[1]));
    }
}
