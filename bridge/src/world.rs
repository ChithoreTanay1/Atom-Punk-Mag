//! Process-wide shared state read by controllers every tick. Godot calls
//! into us on the main thread; the mutex is uncontended and cheap.

use std::sync::{Mutex, MutexGuard, OnceLock};

use magadha_core::awareness::AwarenessParams;
use magadha_core::nav::NavGraph;
use magadha_core::tuning::Tuning;

#[derive(Default)]
pub struct World {
    pub tuning: Tuning,
    pub ai: AwarenessParams,
    pub nav: NavGraph,
    pub alarm: bool,
    /// Dead NPCs not yet discovered: (instance id, position).
    pub corpses: Vec<(i64, [f32; 3])>,
}

static WORLD: OnceLock<Mutex<World>> = OnceLock::new();

pub fn world() -> MutexGuard<'static, World> {
    WORLD
        .get_or_init(|| Mutex::new(World::default()))
        .lock()
        .unwrap_or_else(|e| e.into_inner())
}

pub fn v3(a: [f32; 3]) -> godot::builtin::Vector3 {
    godot::builtin::Vector3::new(a[0], a[1], a[2])
}

pub fn arr(v: godot::builtin::Vector3) -> [f32; 3] {
    [v.x, v.y, v.z]
}
