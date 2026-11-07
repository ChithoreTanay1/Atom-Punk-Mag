//! Pure Rust simulation for the Magadha slice. No Godot types live here.
//!
//! Modules:
//! - `rng`       deterministic seeded RNG (reproducible bugs)
//! - `tuning`    every movement / vehicle / camera number, one data file
//! - `content`   data-driven definitions (weapons, gadgets, governors, events)
//! - `awareness` NPC detection model (stealth)
//! - `nav`       waypoint graph + A* for NPC routing
//! - `mission`   field mission state: clock, routine, intel, methods, alarm
//! - `campaign`  strategic layer: governors, loyalty, rumors, king's stability
//! - `market`    the pretend stock exchange; reacts to deaths and events

pub mod awareness;
pub mod campaign;
pub mod content;
pub mod market;
pub mod mission;
pub mod nav;
pub mod rng;
pub mod tuning;

use std::path::Path;

/// Errors surfaced to the bridge as plain strings.
#[derive(Debug)]
pub struct LoadError(pub String);

impl std::fmt::Display for LoadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

pub fn read_ron<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T, LoadError> {
    let text = std::fs::read_to_string(path)
        .map_err(|e| LoadError(format!("{}: {e}", path.display())))?;
    ron::from_str(&text).map_err(|e| LoadError(format!("{}: {e}", path.display())))
}

pub fn write_ron<T: serde::Serialize>(path: &Path, value: &T) -> Result<(), LoadError> {
    let cfg = ron::ser::PrettyConfig::new().depth_limit(4).struct_names(false);
    let text = ron::ser::to_string_pretty(value, cfg).map_err(|e| LoadError(e.to_string()))?;
    std::fs::write(path, text).map_err(|e| LoadError(format!("{}: {e}", path.display())))
}
