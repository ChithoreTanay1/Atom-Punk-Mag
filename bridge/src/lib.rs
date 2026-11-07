//! gdext glue. The only crate that touches Godot types.
//!
//! - `world`   process-wide shared state (tuning, AI params, nav, alarm)
//! - `sim`     `GameSim` node: exposes campaign + mission state to GDScript
//! - `player`  `FpsController` on-foot controller
//! - `vehicle` `ArcadeCar` raycast-suspension car + chase camera + engine audio
//! - `npc`     `Npc` guards / governor / civilians
//! - `kit`     `KitBuilder` batches primitive geometry into few draw calls
//! - `sfx`     `SfxBank` procedural sound effects (own work, no samples)

use godot::prelude::*;

mod kit;
mod npc;
mod player;
mod sfx;
mod sim;
mod vehicle;
mod world;

struct MagadhaBridge;

#[gdextension]
unsafe impl ExtensionLibrary for MagadhaBridge {}
