//! gdext glue. The only crate that touches Godot types.
//!
//! - `world`   process-wide shared state (tuning, AI params, nav, alarm)
//! - `sim`     `GameSim` node: exposes campaign + mission state to GDScript
//! - `player`  `FpsController` on-foot controller
//! - `vehicle` `ArcadeCar` raycast-suspension car + chase camera + engine audio
//! - `npc`     `Npc` guards / governor / civilians
//! - `kit`     `KitBuilder` batches primitive geometry into few draw calls
//! - `sfx`     `SfxBank` procedural sound effects (own work, no samples)
//! - `eye`     `Eye` Avekṣā cameras, balloons and drones
//! - `crowd_field` `CrowdField` festival crowd drawn as one MultiMesh
//! - `bike`    `BikeController` two-stroke motorcycle
//! - `relief`  `ReliefBank` bakes the temple's carved wall at load time

use godot::prelude::*;

mod bike;
mod crowd_field;
mod eye;
mod impact;
mod kit;
mod npc;
mod player;
mod relief;
mod sfx;
mod sim;
mod vehicle;
mod world;

struct MagadhaBridge;

#[gdextension]
unsafe impl ExtensionLibrary for MagadhaBridge {}
