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
3. Main menu: **New campaign** (war room, then the field operation), **Free play: Saptavarta** (the mission alone), **Feel test** (the endless expressway, test room and handling pad, milestone 1).

## The feel test: A1 Mauryan Way

The driving test is an endless expressway built after `refs/expressway.jfif` (`scripts/expressway.gd`, `scripts/traffic.gd`, `scripts/minimap.gd`, level `scripts/test_track.gd`).

- **Streaming:** the road runs along Z in 96 m chunks, 4 kept each side of you. Each chunk is duplicated from prebuilt pieces (road core, a left and a right building row, far skyline, sometimes an overpass), chosen by a hash of the chunk index, so a stretch looks the same when you come back. Past 2 km the whole world is shifted back to 0 (floating origin) and the car's chase camera is told (`ArcadeCar.shift_origin`).
- **Cross-section:** 3 + 3 lanes with a median barrier (a gap every 8th chunk for U-turns), a promenade deck on the left, a viaduct on Y piers on the right, a service road, then building rows (jali halls with banners and saucer roofs, a tower on curved buttresses, a stepped ministry with chhatris, slab offices with fins and floor bands, a stone elephant plaza).
- **Getting on the viaduct:** every 8th chunk has an on-ramp from the service road (chunk -1, just behind the spawn, is one, and a teal Kestrel waits on the service road in front of it); 4 chunks later there is an off-ramp. Climb, then steer left across the open parapet onto the deck.
- **Traffic:** saloons and box vans keep left, follow, change lanes when stuck, and wrap round you. They push your car; they queue behind it.
- **Minimap** (bottom right): lanes, viaduct and ramps (amber), overpasses, traffic, parked Kestrels, you; odometer and the level you are on.
- **Feel-test kit:** in the yard beside the spawn: the on-foot test room (chunk 0) and a handling pad with jumps, slalom, rumble strips and a hill (chunk -1).
- Debug: `--dusk=0..1` (default 0.55, blue hour).

Debug capture: `Godot --path godot res://scenes/province.tscn -- --shot=out.png --frames=150 --pos=x,y,z --yaw=deg --pitch=deg [--dusk=0..1] [--draw=1] [--quality=0..2]` saves a frame and prints FPS, draw calls and primitives. `--weapon=1..4` picks the starting slot. `--ragdoll=1 [--ragdoll_role=guard] [--ragdoll_tint=0|1] [--ragdoll_dist=m] [--ragdoll_wait=s]` stands you in front of an NPC and kills it to show the death ragdoll. Other modes: `--ragdoll=head` (face shot), `leg` (foot shot: kneel, then limp), `arm`, `down` (legs shot out), `takedown`, `yank` (hook and haul them in), `tether` (hook them and tie them to whatever is `--tether_turn=deg` to the side). Add `--exfil=s` to walk out s seconds after the kill and reach the debrief, `--press=1` to then press its first button, and `--campaign=1` to play it as tonight's campaign mission from your save (this overwrites the save).

## Ragdolls, weapons and cars

- **NPC animation** comes from the Quaternius Universal Animation Library (CC0, `godot/assets/anim/ual_standard.glb`). `NpcBody` (`scripts/npc_body.gd`) takes its skeleton, renames the bones to Godot's humanoid names and runs an AnimationTree: idle, walk, jog and sprint with playback scaled to the real ground speed (no foot sliding), talking idle, a rifle carried at low ready or shouldered in combat, a recoil one-shot when a guard fires, and flinch clips. The body parts from `scripts/body_kit.gd` ride the bones.
- **Locational damage**: a shot is traced against the animated bones, so it lands on a real body part (head, neck, chest, abdomen, pelvis, upper arm, forearm, hand, thigh, shin, foot). The rules are in `core/src/injury.rs`, the numbers in `data/wounds.ron`. A face shot kills and drops the body like a sack with the head snapped back. A leg or foot hit drops them onto that knee, then they limp (slower, hips dip and the trunk lurches over the bad leg). A third leg hit, or a hip shot on a bad leg, puts them on the ground, writhing and bleeding out. Shooting the gun arm makes it hang and wrecks their aim. Body hits flinch the upper body physically. Wounds leave marks where the rounds went in. Bodies on the ground can still be shot, knifed or taken down.
- **Ragdolls** use the [Active Ragdoll](https://godotengine.org/asset-library/asset/5575) addon (MIT, `godot/addons/active_ragdoll`) on the NpcBody's own skeleton, built at the first hit. Deaths knock the body along the blow: bullet (by body part), knife, car, or a takedown, where the knees buckle and the body slumps back onto you. Only 10 dead bodies stay physical; older ones freeze in place.
- **Guards** wear the armour from the Gemini reference (`scripts/body_kit.gd`), now rounded rather than boxy. Gate and yard guards wear steel plate: a kettle helmet with a brim, comb and cheek guards, domed pauldrons, breastplate and faulds, elbow and knee cops, vambraces, greaves, a brown tunic skirt with an apron, a belt and pouches. Elites wear black segmented carbon armour with a closed visor helmet, an ochre scarf and cape, and a sword. The governor wears a long ochre robe with gold trim over a carbon collar and pauldrons. Everyone has a face, hands and boots. Guards carry the AK.
- **Weapons** are data in `data/weapons.ron` (`kind: Gun | Melee | Grapple`, `suppressed`, `reach`). Missions list their extras in `loadout_extra`, and the core keeps ammo per weapon (`Mission::switch_weapon`).
- **Cars:** every car in Saptavarta is a drivable Kestrel 80 in its own paint. This includes the governor's black car, which you can steal before it leaves. Driverless cars are put to sleep in the physics engine once at rest, and their interiors are culled beyond 30 m.

## Controls

| Action | Key |
|---|---|
| Move / jump / sprint / crouch (slide while sprinting) | WASD / Space / Shift / Ctrl or C |
| Interact, enter or leave a car | E |
| Fire / aim / reload / holster / fire mode (the AK is full-auto only) | LMB / RMB / R / H / B |
| Weapon slots: suppressed AK-47, silenced pistol, knife, grapple line | 1 / 2 / 3 / 4, or the mouse wheel |
| Knife: slash (kills outright from behind) / throw a blade | LMB / RMB (walk over thrown blades to pick them up) |
| Grapple line: fire at a surface, let go | LMB / LMB again, RMB or Space |
| Grapple line hooked into a person: haul them to you / aim elsewhere and tether them into it / let go | LMB / RMB / R |
| Use gadget / next gadget | G or MMB / Q |
| Takedown (from behind, unseen) | F |
| Notebook (dossier, intel, objectives) | Tab |
| Exchange terminal (buy / sell, telex wire) | X (or M) |
| Driving: cockpit / chase camera | V |
| Reset car upright | T |
| Pause / tuning panel / frame-time overlay / fullscreen | Esc / F1 / F3 / F11 |

## The Pataliputra Exchange (pretend stock market)

A ticker tape runs along the top of the screen while you play, and X (or M) opens the terminal (the war room has an Exchange button too). It holds 15 invented listings across steel, cement, tech, agriculture, power, motors, banking and arms. You start with 5,000 pana and trade in lots of 1, 10 or 100.

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
