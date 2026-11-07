# INSTRUCTIONS.md — Read this first, every session

Stack: **Rust (gdext / godot-rust) + Godot 4.x**, desktop only.
Pin exact Godot and gdext versions in `README.md`. Only use docs and APIs for those versions. If unsure about an API, say so. Never guess.

---

## 1. Premise

In the far future, someone builds a simulation of Alexander's invasion. It starts in Greece and ends at the Indus border, where it stalls.

In India, a Nanda-like empire has just thrown out Chanakya. He and Chandragupta plan to take it down. The king is too rich and too strong to fight head-on, so we **remove his governors**. We kill them, or kill people to turn them against the throne, using odd future gadgets.

**The simulation renders ancient India through a retro-future lens.** Pataliputra and its provinces look like a grey atompunk state with 1980s executive interiors and cassette-futurist technology. This is deliberate. Do not "correct" it to historical architecture. Names, institutions and politics stay historical (see `LORE.md`).

### Non-goals (do not build)
- No full army or battle simulation.
- No Alexander gameplay. He is backstory and menu flavor only.
- No multiplayer, open-world streaming or procedural cities in v1.
- No hand-written history. Use `LORE.md` only.

---

## 2. Visual direction

Alternate technological future imagined in the 1970s and 80s. **Grey, heavy, institutional, slightly cold.** Not cheerful, not neon, not photoreal, not a low-poly prototype.

### Three styles, three zones
| Zone | Style | Notes |
|---|---|---|
| Exteriors, public infrastructure | **Atompunk, greyed down** | Concrete, steel, monumental entrances, geometric towers, sweeping rooflines, curved elements, repeated structural bays. Overcast sky. Avoid glass skyscrapers. |
| Interiors | **1980s yuppie / executive** | Walnut, leather, marble, smoked glass, brass and chrome, geometric carpet, big plants. Lived-in and expensive, not a museum. |
| Technology, weapons, gadgets | **Cassette futurism** (mandatory) | CRTs, rotary dials, toggle switches, tape drives, chunky keys, beige and grey plastic, visible cables and vents, green mono displays, amber indicators. No holograms or floating UI. |

The contrast is the point: **cold grey outside, warm wood and leather inside.**

### Palette (desaturated, grey-led)
Exterior and neutral base:
- Wet concrete `#8C9091`
- Dark concrete `#5A5F61`
- Overcast sky `#A9B0B2`
- Brushed steel `#9AA3A5`
- Charcoal `#2B2F31`
- Pale concrete `#C4C6C0`

Interior only (use warm colors here and nowhere else in bulk):
- Muted ivory `#CFC5AE`
- Dark walnut `#553B2D`
- Burgundy `#653746`
- Brass `#A98B4E`

Technology:
- Beige plastic `#BDB39B`
- Warm grey `#7B7B76`
- CRT green `#7FCF8A`
- Amber indicator `#D9962B`

Accents (sparse, under 5% of any frame): muted teal `#3E7777`, deep petrol `#24484A`, faded terracotta `#A5573A`.

Night: deep petrol, grey concrete, a few warm amber windows. Light fog. No neon.

### Graphics references (use only these four)
- **Prey (2017):** corporate and executive interiors, retro-futurist spaces.
- **Alien: Isolation:** analogue electronics, CRTs, physical interfaces.
- **Atomic Heart:** monumental atomic-age architecture, scale.
- **Sable:** clean silhouettes, simple geometry, deliberate color blocking.

Do not copy any of them directly. Reference images supplied by the dev in `/refs` override this list.

### Rendering rules
- **Renderer: Compatibility** (the lightest option). Do not use features it lacks (SDFGI, volumetric fog, SSAO, SSR). If lightmaps behave differently on the pinned version, bake what works and flag the rest.
- Stylized **mid-poly** assets. Clean silhouettes first, detail from textures and normal maps, not geometry.
- Prefer baked lighting for static environments. Few real-time lights. Shadows only on the sun and at most a handful of key lights.
- Simple materials: `StandardMaterial3D` or small custom shaders. Minimize transparency.
- Use visibility ranges, LOD and occlusion culling. Use MultiMesh for repeated pieces (tower bays, plants, chairs, props).
- Post-processing restrained: mild grade, mild vignette, light film grain. One optional CRT shader, used **only** on in-world screens.
- Modular, reusable kit pieces. Snap to a grid.

### Asset budget (starting values, adjust with profiling)
- Hero props and weapons: up to 15k tris
- Normal props: 500 to 3k tris
- Modular architecture pieces: 1k to 8k tris
- Vehicles: up to 20k tris
- Textures: 512 to 1024 default, 2048 only for hero items and weapons. Use shared trim sheets and atlases.
- Source assets: kitbash from CC0 and licensed packs (Kenney, Quaternius and similar), then retexture to the palette. Record the license for every asset in `ASSETS.md`.

### Artistic rules
1. No photorealism.
2. No generic cyberpunk, no neon, no holograms.
3. Do not mix unrelated design periods. Everything sits in a 1970s to 80s retro-future.
4. Keep architecture, interiors and tech consistent.
5. Atmosphere, composition, color and readable environmental detail come first.
6. Never add an expensive effect when a cheap one looks the same.

---

## 3. Weapons

- Modeled on **recent real-world weapons** (silhouettes and ergonomics), **reskinned to the cassette-futurist style**: chunky beige, grey or charcoal casings, analog sights, rotary or toggle selectors, amber status lights, visible vents and cables, small CRT or LED readouts.
- Plausible projectile weapons are the default. Gadget and "future trinket" weapons (non-lethal, remote, poison, sabotage, framing) may fire or deploy anything that fits, as long as the **cassette-tech look and rules stay consistent**.
- Weapons are tools for the assassination loop, not a loot treadmill. Few weapons, each with a distinct role.
- Data-driven: every weapon and gadget is a data file (see section 5), not hard-coded.

---

## 4. Game feel: movement and driving (high priority)

Feel beats features. Build and tune these **before** content.

### On foot (CharacterBody3D controller, implemented in Rust via gdext)
- Fixed physics tick (60 Hz minimum, 120 Hz if cheap). Input read per frame, applied per tick.
- Acceleration and friction curves, not instant velocity. Air control with limits.
- Coyote time, jump buffering, step-up on small ledges, slope handling that doesn't snag.
- Crouch and slide. Optional ledge mantle.
- Mouse look is **never smoothed**. No input lag.
- Camera: subtle FOV change with speed, light head-bob and land-impact dip, all adjustable and defaulting low.
- Every movement parameter lives in one tunable resource. No magic numbers.

### Driving
- Arcade-leaning, **fun first, simulation second**. Not `VehicleBody3D` defaults.
- Prefer a custom `RigidBody3D` with raycast suspension, tire grip curves (lateral and longitudinal), anti-roll, and a mild steering-assist and drift-friendly slip model. Enable Jolt physics if available in the pinned version.
- Speed-sensitive steering, strong brakes, weight transfer you can feel, no wallowing or flipping from small bumps.
- Camera: spring-arm chase camera, FOV widens with speed, light shake on rough surface, look-ahead on turns, quick recenter.
- Audio: engine pitch and load tied to RPM, tire squeal on slip, suspension and body thumps, wind at speed.
- On-foot to vehicle transitions must be fast and seamless.
- Provide a **debug tuning panel** (sliders for grip, suspension, steering, camera) from day one.
- Test loop: a flat test track with ramps, curbs, slopes and a tight slalom. If it isn't fun there, don't build cities for it.

---

## 5. Architecture

- **Rust owns game state and logic:** governors, factions, loyalty, rumors, suspicion, contracts, mission state, AI decisions, save/load. Plain Rust structs, no Godot types in the core crate.
- **Godot owns rendering, audio, UI and physics nodes.** Thin gdext glue classes expose Rust state to scenes and forward input back.
- Movement and vehicle controllers are gdext classes extending Godot nodes, so they run in-process with no latency.
- Layout: `core/` (pure Rust sim, unit-tested), `bridge/` (gdext classes), `godot/` (project, scenes, assets), `data/` (RON or JSON content).
- **Data-driven content:** governors, gadgets, weapons, factions, provinces, events. Prefer editing data over editing engine code.
- Deterministic sim where practical (seeded RNG), so bugs can be reproduced.

### Core loop (v1 slice)
Scout a governor → learn routines and relationships → pick a method (direct kill, framing a rival, sabotage, turning an ally) → execute with gadgets → deal with the fallout on the remaining governors and the king's stability.

### First vertical slice
One province, one governor, 3 to 4 gadgets, one weapon, one vehicle, one kill path, one test track. Ship that before anything else.

---

## 6. Lore sources (`LORE.md` must cite these, nothing else)

- Kautilya, *Arthashastra* (Kangle or Olivelle translation): espionage, secret agents, "removal of thorns". Use as design source for mechanics.
- Vishakhadatta, *Mudrarakshasa*: Chanakya vs Rakshasa, political plot.
- Hemachandra, *Parishishtaparvan*: Jain account of Chandragupta.
- Arrian (*Anabasis*), Curtius Rufus, Plutarch, Diodorus Bk. 17: Alexander and the Hyphasis stop. They also mention a Nanda-like ruler as Agrammes/Xandrames.
- Modern: Romila Thapar, Radhakumud Mookerji, A. B. Bosworth.

If something isn't in `LORE.md`, mark it `INVENTED` and keep it clearly fictional.

---

## 7. Working rules for the AI

1. Before coding, restate the task and list the files you'll touch.
2. Work in **small vertical slices**. Compile and run after each. Never leave the build broken.
3. Don't add dependencies, rewrite architecture, rename modules or expand scope without asking.
4. Don't invent history, assets, API calls or crate features. If unsure, say so and ask.
5. Keep the Rust/Godot boundary as defined in section 5.
6. Anything tunable goes in a resource or data file.
7. Profile before optimizing. Report frame time when changing visuals or physics.
8. At the end of each task, give: what changed, how to test it, what's still unverified.
