//! `CrowdField`: draws `core::crowd` as one MultiMesh of cheap pilgrims. The
//! sim decides everything; this node writes the instance buffer and answers the
//! level's questions. The level swaps nearby agents for full NPCs.

use godot::classes::multi_mesh::{TransformFormat};
use godot::classes::geometry_instance_3d::ShadowCastingSetting;
use godot::classes::{INode3D, Mesh, MultiMesh, MultiMeshInstance3D, Node3D, RenderingServer};
use godot::prelude::*;

use magadha_core::crowd::{AgentState, CrowdParams, CrowdSim};

use crate::world::{arr, v3, world};

/// Sim steps per second. The press does not need the physics rate.
const STEP: f32 = 1.0 / 30.0;

/// Robe colours, in the order `Agent.tint` indexes them.
const ROBES: [[f32; 3]; 5] = [
    [0.72, 0.47, 0.13],
    [0.74, 0.70, 0.58],
    [0.40, 0.12, 0.17],
    [0.61, 0.28, 0.12],
    [0.13, 0.33, 0.36],
];

#[derive(GodotClass)]
#[class(base = Node3D)]
pub struct CrowdField {
    sim: Option<CrowdSim>,
    mm: Option<Gd<MultiMesh>>,
    buf: Vec<f32>,
    acc: f32,
    base: Base<Node3D>,
}

#[godot_api]
impl INode3D for CrowdField {
    fn init(base: Base<Node3D>) -> Self {
        Self { sim: None, mm: None, buf: vec![], acc: 0.0, base }
    }

    fn process(&mut self, delta: f64) {
        if self.sim.is_none() || self.base().get_tree().is_paused() { return; }
        self.acc = (self.acc + delta as f32).min(STEP * 4.0);
        let mut stepped = false;
        while self.acc >= STEP {
            self.acc -= STEP;
            if let Some(s) = &mut self.sim { s.tick(STEP); }
            stepped = true;
        }
        if stepped { self.write_buffer(); }
    }
}

#[godot_api]
impl CrowdField {
    /// Must come after the mission started: the numbers are mission data.
    #[func]
    fn setup(&mut self, seed: i64) {
        let params = world().festival.as_ref().map(|f| f.crowd.clone()).unwrap_or_else(CrowdParams::default);
        self.sim = Some(CrowdSim::new(params, seed as u64));
    }

    #[func]
    fn add_lane(&mut self, points: PackedVector3Array, width: f32, closed: bool, weight: f32) {
        let pts = points.as_slice().iter().map(|p| arr(*p)).collect();
        if let Some(s) = &mut self.sim { s.add_lane(pts, width, closed, weight); }
    }

    /// A way off the grounds: panicking people head for it and vanish there.
    #[func]
    fn add_exit(&mut self, at: Vector3, radius: f32) {
        if let Some(s) = &mut self.sim { s.add_exit(arr(at), radius); }
    }

    /// Scatter the agents and create the instances.
    #[func]
    fn populate(&mut self, mesh: Gd<Mesh>, vis_range: f32) {
        let Some(s) = &mut self.sim else { return };
        s.populate();
        let n = s.agents.len() as i32;
        let mut mm = MultiMesh::new_gd();
        mm.set_transform_format(TransformFormat::TRANSFORM_3D);
        mm.set_use_colors(true);
        mm.set_mesh(&mesh);
        mm.set_instance_count(n);
        mm.set_custom_aabb(Aabb::new(Vector3::new(-400.0, -50.0, -400.0), Vector3::new(800.0, 200.0, 800.0)));
        let mut inst = MultiMeshInstance3D::new_alloc();
        inst.set_multimesh(&mm);
        inst.set_cast_shadows_setting(ShadowCastingSetting::OFF);
        if vis_range > 0.0 { inst.set_visibility_range_end(vis_range); }
        self.base_mut().add_child(&inst);
        self.mm = Some(mm);
        self.buf = vec![0.0; n as usize * 16];
        self.write_buffer();
    }

    fn write_buffer(&mut self) {
        let (Some(s), Some(mm)) = (&self.sim, &self.mm) else { return };
        for (i, a) in s.agents.iter().enumerate() {
            let o = &mut self.buf[i * 16..i * 16 + 16];
            let c = ROBES[a.tint as usize % ROBES.len()];
            let hidden = a.promoted || a.state == AgentState::Gone;
            let (hx, hz) = (a.heading[0] * a.dir, a.heading[1] * a.dir);
            // Basis columns: x = right, y = up, z = back (mesh faces -Z).
            let (bx, bz) = ([-hz, 0.0, hx], [-hx, 0.0, -hz]);
            let k = if hidden { 0.0 } else { 1.0 };
            let (m, y) = if a.state == AgentState::Down {
                // On the ground: up becomes the facing direction.
                ([[bx[0], hx, -bz[1]], [bx[1], 0.0, -1.0], [bx[2], hz, 0.0]], a.pos[1] + 0.25)
            } else {
                ([[bx[0], 0.0, bz[0]], [bx[1], 1.0, bz[1]], [bx[2], 0.0, bz[2]]], a.pos[1])
            };
            o[0] = m[0][0] * k; o[1] = m[0][1] * k; o[2] = m[0][2] * k; o[3] = a.pos[0];
            o[4] = m[1][0] * k; o[5] = m[1][1] * k; o[6] = m[1][2] * k; o[7] = y;
            o[8] = m[2][0] * k; o[9] = m[2][1] * k; o[10] = m[2][2] * k; o[11] = a.pos[2];
            o[12] = c[0]; o[13] = c[1]; o[14] = c[2]; o[15] = 1.0;
        }
        let rid = mm.get_rid();
        let packed = PackedFloat32Array::from(self.buf.as_slice());
        RenderingServer::singleton().multimesh_set_buffer(rid, &packed);
    }

    #[func]
    fn start_panic(&mut self, at: Vector3) {
        if let Some(s) = &mut self.sim { s.start_panic(arr(at)); }
    }

    #[func]
    fn panicking(&self) -> bool {
        self.sim.as_ref().is_some_and(|s| s.panicking())
    }

    #[func]
    fn set_retinue(&mut self, at: Vector3, radius: f32) {
        if let Some(s) = &mut self.sim { s.set_retinue(Some((arr(at), radius))); }
    }

    #[func]
    fn clear_retinue(&mut self) {
        if let Some(s) = &mut self.sim { s.set_retinue(None); }
    }

    /// How many people saw something violent at `at`.
    #[func]
    fn witness(&mut self, at: Vector3) -> i64 {
        self.sim.as_mut().map(|s| s.witness(arr(at)) as i64).unwrap_or(0)
    }

    /// Witnesses near a guard tell him. Returns where it happened, per witness.
    #[func]
    fn take_reports(&mut self, guards: PackedVector3Array) -> PackedVector3Array {
        let g: Vec<[f32; 3]> = guards.as_slice().iter().map(|p| arr(*p)).collect();
        self.sim.as_mut().map(|s| s.take_reports(&g)).unwrap_or_default().into_iter().map(v3).collect()
    }

    #[func]
    fn density_at(&self, at: Vector3) -> f32 {
        self.sim.as_ref().map(|s| s.density_at(arr(at))).unwrap_or(0.0)
    }

    #[func]
    fn press_density(&self) -> f32 {
        self.sim.as_ref().map(|s| s.params.press_density).unwrap_or(1.0)
    }

    #[func]
    fn nearest(&self, at: Vector3, radius: f32, k: i64) -> PackedInt32Array {
        self.sim.as_ref().map(|s| s.nearest(arr(at), radius, k.max(0) as usize)).unwrap_or_default().into_iter().map(|i| i as i32).collect()
    }

    #[func]
    fn agent_pos(&self, i: i64) -> Vector3 {
        self.sim.as_ref().and_then(|s| s.agents.get(i as usize)).map(|a| v3(a.pos)).unwrap_or(Vector3::ZERO)
    }

    /// Where the agent will be a few metres on, for a full NPC to walk to.
    #[func]
    fn agent_ahead(&self, i: i64, metres: f32) -> Vector3 {
        let Some(s) = &self.sim else { return Vector3::ZERO };
        let Some(a) = s.agents.get(i as usize) else { return Vector3::ZERO };
        v3(s.ahead_of(a, metres))
    }

    #[func]
    fn set_promoted(&mut self, i: i64, on: bool) {
        if let Some(a) = self.sim.as_mut().and_then(|s| s.agents.get_mut(i as usize)) {
            a.promoted = on;
        }
    }

    #[func]
    fn set_agent_tint(&mut self, i: i64, tint: i64) {
        if let Some(a) = self.sim.as_mut().and_then(|s| s.agents.get_mut(i as usize)) {
            a.tint = tint.rem_euclid(ROBES.len() as i64) as u8;
        }
    }

    #[func]
    fn kill_agent(&mut self, i: i64) {
        if let Some(s) = &mut self.sim { s.kill_agent(i as usize); }
    }

    /// True if the agent is no longer walking about (fled, or down).
    #[func]
    fn agent_gone(&self, i: i64) -> bool {
        self.sim.as_ref().and_then(|s| s.agents.get(i as usize)).is_none_or(|a| matches!(a.state, AgentState::Gone | AgentState::Down))
    }

    #[func]
    fn crushed(&self) -> i64 {
        self.sim.as_ref().map(|s| s.crushed as i64).unwrap_or(0)
    }

    #[func]
    fn full_npc_budget(&self) -> i64 {
        self.sim.as_ref().map(|s| s.params.full_npcs as i64).unwrap_or(0)
    }

    #[func]
    fn near_radius(&self) -> f32 {
        self.sim.as_ref().map(|s| s.params.near_radius).unwrap_or(0.0)
    }

    #[func]
    fn agent_count(&self) -> i64 {
        self.sim.as_ref().map(|s| s.agents.len() as i64).unwrap_or(0)
    }
}
