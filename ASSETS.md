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
| proc_humanoid | Guard, governor, courier, civilian bodies | ext / int | n/a (`builder.gd` -> `npc_body.gd`, parts from `body_kit.gd`) | Own work | Own work | see proc_body_kit | none | Yes | Animated by the anim_ual_standard skeleton (the old procedural limb swing is gone) |
| veh_sedan_boxy | Old boxy saloon (`car_prop`), no longer placed; the street now uses drivable Kestrels | vehicle | n/a (`builder.gd`) | Own work | Own work | est. under 2k | none | Yes | Kept for future props |
| wpn_rifle_ashani | Ashani AK-47S view model: AK-47 pattern (stamped receiver, walnut furniture, slanted stock, gas tube, curved 30-round magazine, rear leaf and front post) with a long baffled suppressor, side-rail reflex sight, CRT round counter, amber ready lamp. Replaces the Vajra bullpup carbine | weapon | n/a (`player_rig.gd`) | Own work | Own work | est. under 1.5k | none | Yes | Silhouette from the real AK-47/AKM; INVENTED name. NPC version: `BodyKit.rifle_mesh()` |
| anim_ual_standard | Universal Animation Library [Standard]: skeleton and 46 clips (12 used: idle, talking idle, walk, formal walk, jog, sprint, rifle idle and shot, chest and head hits, kneel) | npc | https://quaternius.com (Universal Animation Library) | Quaternius | CC0 | mannequin mesh not used | none | n/a | `godot/assets/anim/ual_standard.glb`, licence copied alongside. Bones renamed to humanoid names at runtime (`npc_body.gd`) |
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
| addon_active_ragdoll | Active Ragdoll v0.2.0 (`godot/addons/active_ragdoll`): physical bones, muscle-driven fall and limp | npc | https://github.com/DanilKhmyrov/godot-active-ragdoll (asset library 5575), commit c90d8cb6 | Danil Khmyrov | MIT | - | none | n/a | Copied unmodified with its LICENSE. Used for hit flinches, falls, writhing and death ragdolls via `npc_body.gd`. Checked: no file, network or OS calls |
| proc_body_kit | Humanoid part kit per bone (pelvis, abdomen, chest, head, upper arm, forearm with hand, thigh, shin, foot), built from rounded primitives (ellipsoids from stacked rings, tapered cylinders). Faces, hands, boots, belts, pouches. Guard steel plate (kettle helmet with brim and comb, domed pauldrons, breastplate, faulds, elbow and knee cops, vambraces, greaves, tunic skirt and apron), elite carbon (segmented plates, closed visor helmet, ochre scarf and cape, sword), governor robe with gold trim over carbon collar and pauldrons | npc | n/a (`godot/scripts/body_kit.gd`) | Own work | Own work | est. 3k to 4.5k per body (not measured per body; a full Saptavarta frame measured about 130k primitives) | none | Yes | Outfits from the user's Gemini-generated reference image (`refs/Gemini_Generated_Image_wk9unswk9unswk9u.jpg`), not traced |
| wpn_pistol_mriga | Mriga 9 suppressed pistol: slide, ribbed suppressor, notch-and-post iron sights (brass front cap), drop-out magazine | weapon | n/a (`player_rig.gd`) | Own work | Own work | under 400 | none | Yes | ADS lines up the sights on the camera axis |
| wpn_knife_nakha | Nakha knife (walnut grip, blackened blade) plus a sheath of throwing blades; thrown blade mesh | weapon | n/a (`player_rig.gd`) | Own work | Own work | under 200 | none | Yes | |
| wpn_grapple_garuda | Garuda Line launcher (brass spool), three-prong hook, rope (stretched box) | weapon | n/a (`player_rig.gd`) | Own work | Own work | under 400 | none | Yes | Pull physics in `bridge/src/player.rs` |
| sfx_procedural_3 | silenced (suppressed shot), swish, stab, grapple (launch), winch (reel loop) | tech | `bridge/src/sfx.rs` | Own work | Own work | - | - | n/a | Synthesised at startup |
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

No CC-BY assets yet. MIT code:
- "Active Ragdoll" by Danil Khmyrov, https://github.com/DanilKhmyrov/godot-active-ragdoll (MIT, licence file kept in `godot/addons/active_ragdoll/LICENSE`)

CC0 shaders used, credited as a courtesy:
- "PS1/PSX PostProcessing" by Grau, https://godotshaders.com/shader/ps1-psx-postprocessing/ (CC0)
- "Simple rain/snow shader" by mo32167, https://godotshaders.com/shader/simple-rain-snow-shader/ (CC0)
