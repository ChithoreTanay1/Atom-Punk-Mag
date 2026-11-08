# context.md — Project context in one place

A single overview of **Magadha // Simulation 326-B** (working title; the Godot
assembly name is "Magadha 326-B"). It summarises what the project is, how it
is built, what exists today, and, in detail, the atmosphere the game is meant
to have.

Sources of truth, in order: `instructions.md` (rules, overrides everything),
`README.md` (pinned versions, controls, running), `LORE.md` (the only history),
`ASSETS.md` (every asset and its licence), and the images in `/refs` (they
override any text description of the look). This file is a summary; when it
disagrees with those, they win.

---

## 1. What the game is

A first-person **stealth-assassination sandbox** set inside a simulation.

- **Frame story [INVENTED]:** in the far future, an archive model replays
  Alexander's march from Pella to the Indus. At the Hyphasis (Beas), c. 326
  BCE, the army refuses to cross and the model stalls: *"The model cannot
  resolve the east."* Beyond the river is Magadha, capital Pataliputra.
- **The plot:** the Nanda king (Dhana Nanda, "the King") has thrown Chanakya
  out of his court. Chanakya and Chandragupta cannot beat a king that rich and
  that strong head-on, so they **take away his governors**: kill them, poison
  them, or forge evidence so the king kills them himself.
- **The twist in presentation:** the simulation renders ancient India as a
  grey **atompunk** state with **1980s executive interiors** and
  **cassette-futurist** technology. This is deliberate and must not be
  "corrected" to historical architecture. Names, institutions and politics
  stay historical (see `LORE.md`); the look does not.
- **Non-goals:** no army or battle sim, no Alexander gameplay (menu flavour
  only), no multiplayer, no open world or procedural cities in v1, no invented
  "history" outside `LORE.md` (anything invented is tagged `[INVENTED]`).

### Core loop
Scout a governor → learn his routine and relationships → choose a method
(quiet kill, loud kill, poison, frame a rival, turn an ally) → execute with
gadgets → live with the fallout on the other governors and the king's
stability.

The design source for the spy mechanics is Kautilya's *Arthashastra* (agents,
"removal of thorns", sowing discord between officials), used as **design**,
not as Nanda-era fact.

---

## 2. Stack and layout

| Tool | Version |
|---|---|
| Godot | 4.7.2-stable, **Compatibility renderer**, Jolt physics at 120 Hz |
| gdext (`godot` crate) | =0.5.5, feature `api-4-7` |
| Rust | 1.99.1 stable (MSVC) |
| Target hardware | Windows 11, Intel Iris Xe integrated GPU |

```
core/     pure Rust simulation, no Godot types, unit-tested (crate magadha_core)
bridge/   gdext classes, the only crate that touches Godot types (cdylib)
godot/    Godot project: scenes, scripts, shaders, addons, assets
data/     RON content: governors, gadgets, weapons, missions, market, tuning...
refs/     dev-supplied reference images (override text descriptions)
```

**Boundary rule:** Rust owns game state and logic (campaign, mission, AI
decisions, awareness, injuries, market, save/load). Godot owns rendering,
audio, UI and physics nodes. Movement and vehicle controllers are gdext
classes so they run in-process with no latency. Content is data, not code.
The sim is deterministic (seeded SplitMix64) so bugs replay.

### core/src
| Module | Role |
|---|---|
| `campaign.rs` | The war room: governors' loyalty and paranoia, rumours, agent ops, nights, heat, the king's stability, win/lose |
| `mission.rs` | Field mission: sim clock, governor routine, overheard lines and intel, alarm, kill / poison / frame paths, outcome |
| `awareness.rs` | What an NPC *thinks* given the geometry the bridge measures |
| `injury.rs` | Locational damage rules (numbers in `data/wounds.ron`) |
| `market.rs` | The Pataliputra Exchange price model |
| `nav.rs` | Waypoint graph with A* for the hand-laid compound |
| `tuning.rs` | Every movement / vehicle / camera number, from `data/tuning.ron` |
| `content.rs` | Shapes of all RON content |
| `rng.rs` | Deterministic RNG |

### bridge/src
| Module | Role |
|---|---|
| `player.rs` | `FpsController`: Quake-style accel/friction, coyote time, jump buffer, crouch/slide, mantle, grapple pull |
| `vehicle.rs` | `ArcadeCar`: custom RigidBody3D, raycast suspension, slip-angle grip, friction circle, anti-roll, synthesized engine audio |
| `npc.rs` | Guards, governor, couriers, civilians: perception geometry and routes |
| `sim.rs` | `GameSim`, the one node GDScript talks to for game state |
| `kit.rs` | `KitBuilder`: batches procedural geometry into one surface per material |
| `sfx.rs` | `SfxBank`: every sound effect synthesized at startup, no sample files |
| `world.rs` | Shared process-wide state (tuning, AI params, nav, alarm) |

### godot
- **Scenes:** `main_menu.tscn`, `war_room.tscn`, `province.tscn` (Saptavarta), `test_track.tscn` (feel test).
- **Key scripts:** `game.gd` (autoload, settings, quality presets, debug flags), `level_base.gd` (environment, sun, fog, player, car), `province.gd` (the Saptavarta level), `player_rig.gd` (weapons, gadgets, gunfeel, takedowns), `npc_body.gd` + `body_kit.gd` (animated bodies and outfits), `car_cockpit.gd`, `hud.gd`, `market_panel.gd`, `war_room.gd`, `weather.gd`, `palette.gd`, `ui_style.gd`, `builder.gd`, `tuning_panel.gd`.
- **Shaders:** `kit.gdshader` (world material with weather and dusk window glow), `post.gdshader` (grade, vignette, grain, retro filter), `crt.gdshader` (in-world screens only), `precip.gdshader` (screen-space rain/snow).
- **Third-party:** Quaternius Universal Animation Library (CC0), Active Ragdoll addon (MIT), two CC0 shaders. Everything else is procedural own work.

---

## 3. What exists today

- **Milestone 1, feel test:** test track (ramps, curbs, slopes, slalom) and test room; F1 tuning panel edits `data/tuning.ron` live.
- **Milestone 2, vertical slice:** *A Thorn in Saptavarta*. Governor Virabhadra Kaushika works at his desk, meets in the pavilion, takes tea on the terrace, inspects the gate post, returns to work and departs from the motor court between roughly 17:50 and 19:00 sim time. You scout, eavesdrop and pick a path.
- **Campaign (war room):** up to 10 nights, start stability 70, win below 25, lose at heat 100. Fallout per method (quiet kill, loud kill, poison, frame, failed) moves stability, heat, loyalty and paranoia, and seeds rumours. Successor governors take over.
- **Loadout:** Ashani AK-47S (suppressed, full-auto), Mriga 9 silenced pistol, Nakha knife with throwing blades, Garuda Line grapple (haul or tether people). Gadgets: Murmur Cassette tape bug, Static Lure, Datura Ampoule, Forged Dispatch.
- **Bodies:** Quaternius-animated NPCs, locational wounds (limp, dead arm, knocked down, bleeding out), active ragdolls on death, takedowns.
- **Vehicle:** the Kestrel 80 wedge coupe, drivable, with a full 80s cockpit view; every street car is one, including the governor's.
- **The Pataliputra Exchange:** an early-80s pretend stock market with 15 invented listings, ticker tape on the HUD, a terminal (M), prices that react to deaths and methods.
- **Feel test, A1 Mauryan Way:** an endless streamed expressway after `refs/expressway.jfif` (6 lanes, Y-pier viaduct with drivable ramps, promenade, overpasses, atompunk building rows, traffic, airships, minimap), with the test room and handling pad in a yard by the spawn.
- **Mission 2, *Nothing Unobserved*:** a festival crowd at the Great Temple under Avekṣā Corp's surveillance (cameras, aerostat, drones, a reel room), and an escape on the Kestrel Shikra 250 two-stroke, ridden in first person, with pursuit riders behind you. Menu item 04.
- **Vehicle damage:** crashes (injury, hull, thrown riders, bent panels), a two-stage windshield, shootable tyres, guns usable from the seat, riders shot off bikes, and saucer drones you can shoot down or rope into things. See `core/src/crash.rs`.
- **Settings:** weather (rain / snow / clear, with persistent wetness and snow cover), retro filter (off / dither / PSX), LOW / MEDIUM / HIGH presets. Measured: locked 60 fps on Iris Xe at 1600x900, MEDIUM.

Next milestones: fallout systems deepening, more provinces and governors as
data (Vatsabhumi March, Ujjayanta Reach, Dakshavana, Hiranyavaha Circle are
already named), then the frame story and menus.

---

## 4. Atmosphere (the asked-for mood, in detail)

This section is the heart of the brief. When a decision about light, colour,
sound, props or text is unclear, come back here.

### 4.1 The one-sentence version

**A cold, grey, monumental state seen under an overcast sky, where power
lives behind heavy concrete in warm, expensive, 1980s rooms, and every
machine clicks, hums and glows amber or green.** It should feel like a
political thriller set inside an old computer's idea of ancient India.

### 4.2 The emotional register

- **Grey, heavy, institutional, slightly cold.** The world is a bureaucracy
  made of concrete. It is orderly, watched and indifferent to you.
- **Quiet tension, not action spectacle.** You are an infiltrator in a
  governor's compound at dusk. The default state is observing: the governor's
  voice through a tape bug, a guard's routine, the clock creeping toward his
  departure.
- **Melancholy grandeur.** Monuments, banners and sweeping rooflines say the
  Nanda state is rich and permanent; the player's job is to prove it isn't.
- **Dry, understated wit.** The governor's lines carry it: *"The only honest
  thing in this province is the tea."* The frame text is clipped, telex-like,
  all caps. Nothing winks at the camera.
- **Not:** cheerful, neon, cyberpunk, glossy sci-fi, photoreal, or a
  low-poly prototype. Not a museum either: spaces are lived-in.

### 4.3 The three zones, and why they contrast

The contrast is the point: **cold grey outside, warm wood and leather inside.**

**Exteriors — greyed-down atompunk.** Concrete and steel; monumental
entrances; geometric towers; sweeping, flying-saucer rooflines and ring
canopies; curved buttresses; repeated structural bays. Indian silhouettes
pushed through the atomic age: domed pavilions and chhatri-like kiosks,
stepped temple-mountain masses (the Gemini reference's citadel), carved
elephant monuments on plinths, arched viaducts. Burgundy banners with a gold
chakra-like wheel hang from facades and lamp poles. Airships drift in the
haze over the skyline. Streets are wide boulevards with market stalls,
awnings, carts, kiosks, phone booths, bollards, wall cameras and antennae.
No glass skyscrapers.

**Interiors — 1980s yuppie / executive.** Walnut panelling and desks,
burgundy leather and velour sofas, marble floors, geometric rugs, smoked
glass, brass and chrome, ring chandeliers, big potted plants, a classical
statue in a niche, floor-to-ceiling windows looking out onto the grey city.
Expensive and used: papers on the desk, a tea trolley, a cassette deck.
This is where the governor is comfortable, and where the warm colours live.

**Technology — cassette futurism (mandatory).** CRT monitors with green
mono screens, rotary dials, toggle switches, reel-to-reel and cassette
drives, chunky keys, beige and grey plastic, visible cables and vents, amber
indicator lamps, VFD readouts. The telex is how power talks to the capital.
No holograms, no floating UI. The CRT shader is used only on in-world
screens.

**Vehicles.** The Kestrel 80 is a low wedge coupe (a nod to the 1968 Bertone
Carabo) with a copper-tinted canopy, louvred engine cover and orange nose and
tail. Inside, the burgundy 80s cabin from the reference photo: a wide
binnacle with two green-ringed electronic gauges, a green VFD speed readout,
a four-spoke burgundy wheel with a square pad, a centre stack of vents,
climate VFD and cassette deck, a T-bar shifter, velour seats.

**Weapons and gadgets.** Recent real-world silhouettes (the AK pattern, a
suppressed pistol) reskinned in cassette style: walnut furniture, chunky
casings, a small CRT round counter, an amber ready lamp, a reflex sight with
an amber dot-and-ring. Gadgets are physical trinkets: a pocket tape recorder
with a magnetic back, a hissing transistor box you throw, a glass ampoule in
a beige spring case, a sealed letter.

### 4.4 People and dress

From the Gemini reference image (outfits are `[INVENTED]`, not a historical
uniform):
- **Line guards:** steel plate over brown tunics. Kettle helmets with brims,
  domed pauldrons, breastplates, greaves, aprons, belts and pouches. They read
  as a medieval levy re-issued by a modern ministry.
- **Elite guards:** black segmented carbon armour, closed visor helmets, an
  ochre scarf and cape, a sword at the hip and a rifle in hand. Faceless,
  sinister, the regime's sharp edge.
- **The governor:** a long ochre robe with gold trim over a carbon collar and
  pauldrons, staff and sword. Old aristocracy wearing new armour.
- **Civilians and couriers** fill the boulevard and market in muted dress.
- The player's side (Chanakya's agents) reads as hooded, caped, crouched in
  shadow at the edge of a lit hall (moodboard bottom-right panel).

No real-world religious or ethnic caricature. Everyone is an official, a spy
or a soldier in a political thriller.

### 4.5 Colour

Desaturated and grey-led. Warm colours appear in bulk **only indoors**.
Accents stay under 5% of any frame.

| Group | Colours |
|---|---|
| Exterior / neutral | Wet concrete `#8C9091`, dark concrete `#5A5F61`, overcast sky `#A9B0B2`, brushed steel `#9AA3A5`, charcoal `#2B2F31`, pale concrete `#C4C6C0` |
| Interior only | Muted ivory `#CFC5AE`, dark walnut `#553B2D`, burgundy `#653746`, brass `#A98B4E` |
| Technology | Beige plastic `#BDB39B`, warm grey `#7B7B76`, CRT green `#7FCF8A`, amber indicator `#D9962B` |
| Sparse accents | Muted teal `#3E7777`, deep petrol `#24484A`, faded terracotta `#A5573A` |

The moodboard (`refs/Ancient India Retro-Futurist City Moodboard.png`) adds
mustard `#C69B42` and steel `#AEB7B7`, and shows the balance in practice:
burgundy banners and ochre/mustard robes are the only saturated notes in an
otherwise grey frame.

### 4.6 Light, sky and time of day

- **Default sky is overcast.** Flat, cool, diffuse light; soft shadows; a
  pale grey-blue horizon. The procedural sky runs from `#5C6669` at the top
  to `#8E9699` at the horizon.
- **Light fog** (base `#848D90`, density about 0.0075) softens distance and
  makes the skyline read as layered grey silhouettes.
- **Dusk is the mission's hour.** The Saptavarta op starts around 17:50 and
  runs into evening. As dusk rises the sky sinks to deep petrol (`#1C2A2E`),
  fog darkens to `#2E3B3E`, ambient light drops, and **windows and lamps
  glow warm amber**. Interiors visibly become the warm, lit pockets in a cold
  city.
- **Night:** deep petrol, grey concrete, a few warm amber windows, light fog.
  **No neon.**
- Few real-time lights; shadows on the sun and a handful of key lights.
  Baked or cheap tricks (vertex-colour AO) wherever they look the same.

### 4.7 Weather

Weather is a mood control as much as a setting.
- **Rain:** streets build up a wet, darkened gloss with puddle ripples and
  reflections; walls sheet with water; screen-space streaks and a rain loop.
  This is the closest to the moodboard's wet plaza.
- **Snow:** a growing white layer on exposed surfaces, slow flakes, wind.
  Harsh and austere; the grey city gets greyer.
- **Clear:** still overcast-leaning, never sunny-cheerful.
- Wetness and snow persist and fade when the weather changes, so the world
  remembers.

### 4.8 Sound

Everything is synthesized, which suits the analogue-machine feel.
- **Ambience:** low city hum, wind, rain loops. Mostly quiet.
- **Machines:** telex chatter, tape whirr, static, beeps (high and low),
  alarms. These are the world's voice.
- **Violence is short and heavy:** a suppressed rifle cough, a layered
  gunshot with echoes off concrete, brass, impacts, flesh hits, knife swish
  and stab, the grapple's launch and winch.
- **The car:** engine pitch tied to RPM, tyre squeal on slip, wind at speed.

### 4.9 Interface and text

- The HUD is cassette-futurist: an **amber status strip**, **green
  readouts**, detection arcs around the crosshair, physical-looking panels,
  monospace type, segmented analogue bars like `[||||||....]`.
- Menus use charcoal panels, amber rules and green readouts. No scanlines
  outside in-world screens.
- The Exchange looks like an early-80s trading desk: green-on-charcoal quote
  board, prices in eighths, sparklines, a ticker tape and a telex wire.
- The main menu sits on a live slice of the simulation: the boulevard
  monument at dusk in the current weather, with the camera slowly drifting
  around it, and the frame text in clipped capitals.
- Writing style: terse, dry, official. Reports read like dispatches:
  *"{name} falls ill over his evening tea and does not rise. In the bazaar
  they say the king sent the tea."*

### 4.10 Post-processing

Restrained: a mild grade, mild vignette and light film grain, plus a damage
tint. The optional **retro filter** (dither, or PSX colour reduction with
ordered dither and 450-line pixelation) leans into the "old simulation"
frame; the HUD stays sharp over it.

### 4.11 Reference touchstones

Only these four, never copied directly; the `/refs` images override them:
- **Prey (2017):** corporate and executive retro-futurist interiors.
- **Alien: Isolation:** analogue electronics, CRTs, physical interfaces.
- **Atomic Heart:** monumental atomic-age architecture and scale.
- **Sable:** clean silhouettes, simple geometry, deliberate colour blocking.

Reference images in `/refs`:
- `Ancient India Retro-Futurist City Moodboard.png`: the master mood. The
  palace with saucer-ring roofs and burgundy banners, the elephant statue,
  airships, the walnut-and-burgundy office over a grey skyline, the green-CRT
  terminal, the wet bazaar boulevard, the cloaked figure on a balcony, the
  hooded agent watching guards in a bannered hall.
- `Gemini_Generated_Image_wk9unswk9unswk9u.jpg`: guard, elite and governor
  dress; brutalist concrete compound with curved canopies and a stepped
  citadel; army tents in a dirt yard.
- `Screenshot 2026-11-07 172247.png`: the 80s burgundy car interiors behind
  the Kestrel cockpit.

### 4.12 Atmosphere checklist (for any new asset, scene or text)

- [ ] Does it belong to exactly one zone: grey atompunk outside, 80s
      executive inside, cassette tech everywhere?
- [ ] Are warm colours confined to interiors (or tiny accents)?
- [ ] No neon, holograms, glossy panels, glass skyscrapers or photorealism?
- [ ] Does it sit in the 1970s–80s imagined future, with no mixed periods?
- [ ] Does it read clearly in silhouette at gameplay distance, in fog?
- [ ] Does it still work at dusk, in rain and in snow?
- [ ] Is the text dry, terse and in-world?
- [ ] Is it the cheapest way to get this look?

---

## 5. Working rules (short form)

From `instructions.md` section 7: restate the task and list files first; work
in small vertical slices and never leave the build broken; don't add
dependencies, rename modules or expand scope without asking; don't invent
history, assets or APIs; keep the Rust/Godot boundary; put every tunable in
data; profile before optimising and report frame time on visual or physics
changes; end every task with what changed, how to test it, and what's
unverified. Every asset gets a row in `ASSETS.md` before it enters `/godot`.

Build and run: `cargo build -p bridge`, then Godot 4.7.2 with `--path godot`.
Debug captures and flags are listed in `README.md`.
