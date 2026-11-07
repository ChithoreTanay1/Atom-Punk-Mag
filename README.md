# Project README

Working title: **TBD**
Genre: stealth-assassination sandbox. Setting: simulated ancient India (Chandragupta and Chanakya vs the Nanda empire), rendered as grey atompunk with cassette-futurist tech.

Start with `instructions.md`. It overrides anything else.

## Pinned versions (fill in on install, then never change without a note here)

| Tool | Version | Notes |
|---|---|---|
| Godot | 4.7.2-stable (win64) | Compatibility renderer (gl_compatibility), Jolt physics at 120 Hz |
| gdext (`godot` crate) | =0.5.5, feature `api-4-7` | Must match the Godot version above |
| Rust (stable) | rustc 1.99.1 (MSVC toolchain) | gdext 0.5.5 needs rustc >= 1.94 |
| OS / GPU tested | Windows 11 Home, Intel Iris Xe (integrated) | Lowest-spec machine counts as the target |

Rule: every doc, example and API call must match these versions. If an API isn't in these versions' docs, don't use it.

## Layout

```
/core        pure Rust simulation (no Godot types), unit-tested
/bridge      gdext classes (the only crate that touches Godot types)
/godot       Godot project: scenes, materials, shaders, assets
/data        RON/JSON content: governors, gadgets, weapons, factions, events
/refs        dev-supplied reference images (override text descriptions)
instructions.md   rules for the AI
LORE.md           cited history; nothing outside it counts as history
ASSETS.md         license and budget log for every asset
```

## Setup

1. Install Rust (stable) and Godot (pinned version above).
2. Follow the official godot-rust book for the `.gdextension` file and crate settings (`bridge` builds as a `cdylib`). Do not guess the file format.
3. Build and test:
   - `cargo test -p core`
   - `cargo build -p bridge`
4. Open `/godot` in the editor. Set the renderer to **Compatibility**.

## Milestones

1. **Feel test:** flat test track plus a test room. Movement and driving fun with the tuning panel. Nothing else until this passes.
2. **Vertical slice:** one province, one governor, 3 to 4 gadgets, one weapon, one vehicle, one kill path.
3. **Fallout systems:** loyalty, suspicion, rumor spread, king's stability.
4. **More provinces and governors** (data only, if the architecture holds).
5. **Frame story and menus** (the Alexander simulation flavor).

## Known gaps

- Performance budgets in `instructions.md` are untested starting values.
- Lightmap support under Compatibility depends on the pinned Godot version. Check before baking.
- gdext targets desktop only. Web export is not planned.

## Dependencies added

- `core`: `serde` (derive) and `ron` 0.8, for loading the RON content in `/data`. (No new dependencies for the exchange, car or sight.) Nothing else outside `godot` in `bridge`.

## Running

1. `cargo build -p bridge` (the `.gdextension` points at `target/debug/bridge.dll`; build `--release` for the release entry).
2. Run Godot 4.7.2 with `--path godot`, or open `/godot` in the editor and press Play.
3. Main menu: **New campaign** (war room, then the field operation), **Free play: Saptavarta** (the mission alone), **Feel test** (track and test room, milestone 1).

Debug capture: `Godot --path godot res://scenes/province.tscn -- --shot=out.png --frames=150 --pos=x,y,z --yaw=deg --pitch=deg [--dusk=0..1] [--draw=1] [--quality=0..2]` saves a frame and prints FPS, draw calls and primitives.

## Controls

| Action | Key |
|---|---|
| Move / jump / sprint / crouch (slide while sprinting) | WASD / Space / Shift / Ctrl or C |
| Interact, enter or leave a car | E |
| Fire / aim / reload / holster / fire mode | LMB / RMB / R / X / B |
| Use gadget / next gadget | G or MMB / Q |
| Takedown (from behind, unseen) | F |
| Notebook (dossier, intel, objectives) | Tab |
| Exchange terminal (buy / sell, telex wire) | M |
| Driving: cockpit / chase camera | V |
| Reset car upright | T |
| Pause / tuning panel / frame-time overlay / fullscreen | Esc / F1 / F3 / F11 |

## The Pataliputra Exchange (pretend stock market)

A ticker tape runs along the top of the screen while you play, and M opens the terminal (the war room has an Exchange button too). It holds 15 invented listings across steel, cement, tech, agriculture, power, motors, banking and arms. You start with 5,000 pana and trade in lots of 1, 10 or 100.

- **State and logic** live in `core/src/market.rs` and travel with the campaign save. **Content** lives in `data/market.ron`. The bridge exposes `market_tick`, `market_event`, `market_trade` and `market_state` on GameSim, plus the `market_news` signal.
- **Price model:** each company has a fundamental value. News moves the value at once, and part of the move gaps the price immediately. The price then chases the value with momentum and noise, and sectors move together.
- **Events** are plain string keys: `death:<id>`, `removed:<id>`, `method:<kill method>`, `alarm`, `night`. Reactions in data match a key exactly, or by prefix with a trailing `*`.
- **Characters later:** give a character an id and add `ties: [(entity: "char_<id>", on_death: -0.15)]` to any company. Then report `Game.sim.market_event("death:char_<id>", 1.0)` when they die. No code change is needed. Names are resolved for the wire in `GameSim::market_event_inner` (only governors today).
- Debug: `--market=1` buys 40 PCEM, reports the Saptavarta governor's death and opens the terminal.

## Settings (main menu and pause menu)

- **Retro filter:** off / dither / PSX (colour reduction, ordered dither and 450-line pixelation). The HUD stays sharp.
- **Weather:** rain / snow / clear. Rain builds up wet, glossy streets with puddle ripples and reflections. Snow lays a growing white layer on exposed surfaces. Wetness and snow persist and fade when the weather changes.
- Debug flags for captures: `--weather=rain|snow|clear`, `--retro=0..2`, `--fire=1` (hold the trigger), `--newcamp=1` (war room without a save), `--aim=1` (hold ADS), `--drive=move_forward+move_left` (enter the car and hold those actions, printing speed, gear and yaw).

## Performance (measured)

Integrated Intel Iris Xe, 1600x900, MEDIUM preset, PSX filter and weather on: locked at the 60 fps vsync cap everywhere sampled. After the detail pass the Saptavarta level draws 420–650 calls and 40k–88k primitives per frame; the test track about 120 calls and 16k primitives. LOW skips the screen-space precipitation layer. Quality presets (LOW/MEDIUM/HIGH) change shadows, view distance, render scale, MSAA and the post pass.
