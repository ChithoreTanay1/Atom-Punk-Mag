# ASSETS.md

Every asset in the project gets a row here before it enters `/godot`. No row, no asset.

## Allowed sources and licenses

- **Own work:** fine.
- **CC0 / public domain:** fine (Kenney, Quaternius and similar).
- **CC-BY:** allowed, needs attribution in the credits. Record the author and URL.
- **Not allowed:** CC-NC or CC-ND, unlicensed or "free for personal use" assets, anything ripped from a game, and anything copied from reference games.
- **AI-generated assets:** allowed only if the tool's terms allow commercial use. Mark them and note the tool.
- When a license is unclear, don't use the asset.

## Log

| ID | Asset | Zone (ext / int / tech / weapon / vehicle) | Source URL | Author | License | Tris | Tex size | Retextured to palette? | Notes |
|---|---|---|---|---|---|---|---|---|---|
| proc_kit_architecture | Walls, slabs, stairs, columns, towers, saucer rings (Builder/KitBuilder, batched one surface per material) | ext / int | n/a (generated in `godot/scripts/builder.gd`, `bridge/src/kit.rs`) | Own work | Own work | per level: 19k-45k on screen | none (procedural shader) | Yes, palette in `palette.gd` | Vertex-colour AO; box occluders on large blocks |
| proc_props | Lamp post, banner pole, tree, planter, facade fin, stall, crate, cone, chair, chandelier, tea trolley | ext / int | n/a (`builder.gd`) | Own work | Own work | est. under 500 each (not measured per asset) | none | Yes | MultiMesh with visibility ranges |
| proc_humanoid | Guard, governor, courier, civilian bodies with limb nodes | ext / int | n/a (`builder.gd`) | Own work | Own work | est. under 500 | none | Yes | Procedural limb animation in `npc.rs` |
| veh_sedan_boxy | Player car and governor's car | vehicle | n/a (`builder.gd`) | Own work | Own work | est. under 2k | none | Yes | Wheels are separate nodes |
| wpn_carbine_vajra | Bullpup carbine view model with Label3D ammo counter | weapon | n/a (`player_rig.gd`) | Own work | Own work | est. under 1k | none | Yes | |
| shd_kit | World material: concrete, walnut, marble, carpet, steel, foliage, road, fabric, facade windows | all | `godot/shaders/kit.gdshader` | Own work | Own work | - | none | n/a | Wetness and dusk window glow driven at runtime |
| shd_post / shd_crt | Grade, vignette, grain, damage tint; CRT screens (in-world only) | tech | `godot/shaders/` | Own work | Own work | - | none | n/a | |
| sfx_procedural | shot, shot_far, dry, reload, step, land, hit, flesh, thud, static, tape, telex, alarm, beep, beep_low, pour, throw, door, ambience; car engine/squeal/wind synth | tech | `bridge/src/sfx.rs`, `bridge/src/vehicle.rs` | Own work | Own work | - | - | n/a | Synthesised at startup; no sample files |
| shd_psx_post | PS1/PSX colour reduction + ordered dither, merged into `post.gdshader` (screen texture, optional pixelation added) | tech | https://godotshaders.com/shader/ps1-psx-postprocessing/ | Grau | CC0 | - | none | n/a | Adapted; credit kept in the shader header |
| shd_precip | Screen-space rain/snow streak layer (`precip.gdshader`) | ext | https://godotshaders.com/shader/simple-rain-snow-shader/ | mo32167 | CC0 | - | none | n/a | Adapted (slow snow, alpha, wobble); credit in header |
| shd_kit_weather | Kit shader additions: global weather (wet gloss, puddle ripples, wall sheeting, snow layer, glints), grime | all | `godot/shaders/kit.gdshader` | Own work | Own work | - | none | n/a | Driven by `scripts/weather.gd` via shader globals |
| proc_street_props | Bench, bin, phone booth, bollard, kiosk, AC unit, water tank, antenna, hedge, wall camera, wire coil, parked cars, road paint | ext | n/a (`builder.gd`, `province.gd`) | Own work | Own work | est. under 600 each | none | Yes | MultiMesh with visibility ranges |
| proc_gun_fx | Muzzle flash, tracers, smoke/dust/sparks/mist particles, bullet-hole decal, brass; radial gradient textures generated at runtime | weapon | n/a (`player_rig.gd`) | Own work | Own work | tiny | 64 px generated | n/a | Pooled, no allocations per shot |
| sfx_procedural_2 | Layered gunshot with echoes, shell, hitmark, whiz, impact, rain loop, wind loop | tech | `bridge/src/sfx.rs` | Own work | Own work | - | - | n/a | Synthesised at startup |
| font_mono | System monospace font (SystemFont lookup) | UI | OS-provided | OS vendor | Not shipped | - | - | n/a | Nothing bundled; falls back to Godot default |

## Budgets (starting values, from `instructions.md`)

| Type | Tris | Textures |
|---|---|---|
| Hero props, weapons | up to 15k | 2048 allowed |
| Normal props | 500–3k | 512–1024 |
| Architecture modules | 1k–8k | trim sheet / atlas |
| Vehicles | up to 20k | 1024–2048 |

Assets over budget need a note here and a reason.

## Style checklist (every asset)

- [ ] Fits one zone: grey atompunk exterior, yuppie interior, or cassette tech.
- [ ] Colors pulled to the palette in `instructions.md`. Warm colors on interiors only.
- [ ] No neon, holograms or glossy futuristic panels.
- [ ] Clean silhouette at gameplay distance.
- [ ] Modular: snaps to the grid, reusable.
- [ ] Shares atlas or trim sheet where possible.
- [ ] LOD or visibility range set, if large or repeated.
- [ ] Repeated items use MultiMesh.

## Naming

`zone_type_name_variant`, snake_case. Examples: `ext_wall_bay_a`, `int_sofa_leather_01`, `tech_crt_monitor_small`, `wpn_rifle_alpha`, `veh_sedan_boxy`.

## Credits (generated from the log)

List every CC-BY asset here with author, title and URL.

No CC-BY assets yet. CC0 shaders used, credited as a courtesy:
- "PS1/PSX PostProcessing" by Grau, https://godotshaders.com/shader/ps1-psx-postprocessing/ (CC0)
- "Simple rain/snow shader" by mo32167, https://godotshaders.com/shader/simple-rain-snow-shader/ (CC0)
