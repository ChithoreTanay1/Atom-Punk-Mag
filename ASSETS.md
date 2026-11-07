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
| veh_sedan_boxy | Governor's car and parked traffic | vehicle | n/a (`builder.gd`) | Own work | Own work | est. under 2k | none | Yes | Wheels are separate nodes |
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
| veh_kestrel80 | Kestrel 80 wedge coupe, the drivable car: lofted wedge body, copper-tint canopy, louvred engine cover, orange nose and tail | vehicle | n/a (`builder.gd` `wedge_body_mesh`, `KitBuilder.add_loft` in `bridge/src/kit.rs`) | Own work | Own work | est. under 1.5k | none | Yes (new slots CAR_PAINT, CAR_ORANGE, CAR_GLASS) | Shape inspired by the 1968 Bertone Alfa Romeo Carabo concept; no badges, name or trade dress copied. Invented make |
| int_kestrel80_cabin | Cockpit: burgundy dash, binnacle with two electronic gauges, VFD speed, four-spoke wheel, centre stack (vents, climate VFD, cassette deck), T-bar shifter, velour seats, door cards | vehicle / int | n/a (`godot/scripts/car_cockpit.gd`) | Own work | Own work | est. under 2k | gauge face 128 px generated at runtime | Yes (new slots PLUSH, DASH_DARK) | Layout from the user's 80s interior reference (`refs/Screenshot 2026-11-07 172247.png`), not traced; one batched mesh plus Label3D readouts |
| wpn_reflex_sight | Open reflex sight on the carbine: hollow housing, tinted lens, amber dot-and-ring reticle; ADS pose puts the reticle on the camera axis | weapon | n/a (`player_rig.gd`) | Own work | Own work | under 200 | reticle 128 px generated at runtime | Yes | Replaces the solid "analog sight box" |
| ui_exchange | Ticker tape (HUD) and the exchange terminal panel (quote board, sparklines, telex wire) | UI | n/a (`hud.gd`, `market_panel.gd`) | Own work | Own work | - | none | Yes (amber / green / ivory) | Drawn with Control nodes; no textures |
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
