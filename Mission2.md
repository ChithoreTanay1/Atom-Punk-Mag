# Mission2.md — "Nothing Unobserved"

Everything here is **[INVENTED]** unless tagged otherwise. Rules in `instructions.md` and `LORE.md` still apply. Status: design draft. Not built, not tested.

## One-line pitch

Kill the Hiranyavaha Circle's treasury governor in a festival crowd at the Great Temple, past the king's private surveillance firm, then escape on a two-stroke bike.

## Brief (telex from Chanakya)

The king's gold moves through the Hiranyavaha Circle, and its governor counts it. On festival day he walks the processional route to present the king's endowment, in front of thousands of pilgrims.

> HE IS EASY TO FIND. THE DIFFICULTY IS THAT EVERYONE ELSE CAN FIND HIM TOO.

- **Target:** Governor of the Hiranyavaha Circle (name TBD, write in `data/` as an invented official).
- **Province name** is already used in the project. Hiranyavaha is a real old name for the Son River [HIST], used here as a region name only.
- **Time window:** the procession. Start and end times TBD, set in the data file.

## Setting: the Great Temple

- Stepped, grey, concrete temple-mountain in the atompunk style. Terraces, processional ramps, a central sanctum, ring canopies, burgundy banners.
- **Crowd:** pilgrims, vendors, ministers' retinues, guards. It's both your cover and your obstacle.
- Tone: the ritual is the backdrop and is treated respectfully. The state's surveillance is the antagonist, not the faith. No caricature of any religion (rule 3 in `LORE.md`).
- Reference images go in `/refs` (to be added). They override this text.
- Zones: grey atompunk outside, warm 1980s executive interior in the governor's reception room, cassette tech everywhere in Avekṣā's gear.

## Avekṣā Corp

- The king's private surveillance contractor. It sells the state what a spy network once did (*Arthashastra* Book 1 is the design source, [DESIGN] not Nanda-era fact).
- Name: *Avekṣā* (Sanskrit, roughly "watchful regard"). Keep that spelling. Check the diacritics in the final UI font.
- Added as a listing on the Pataliputra Exchange (see Fallout).

### Their equipment (cassette-futurist, no holograms)

| Item | Look | Role |
|---|---|---|
| Gantry cameras | Pan-tilt units on steel gantries, amber tally lamp | Fixed vision cones |
| Balloon cameras | Tethered, drifting above the terraces | Wide, slow coverage |
| Saucer drones | Ducted-fan discs, low hum, amber lamp | Patrol routes, react to alarms |
| Monitoring room | Wall of CRTs, tape recorders, telex | Notices dead feeds; dispatches guards |
| Avekṣā guards | Distinct uniform, **TBD** | Crowd patrols, pursuit |

## Surveillance rules (new systems)

- Each camera and drone is a detector with a cone and range. The bridge measures geometry, `core/awareness.rs` decides what it means.
- Seen = recorded. A recorded crime means a heat spike and a witness report.
- **Dead-feed timer:** if you disable a feed, the monitoring room notices after N minutes (data-tunable). When it notices, it sends guards to that zone. Finish before then, or reset the feed.
- Disabling a feed is quieter than destroying it. A destroyed feed triggers an immediate alert.

## Ways to disable the eyes (existing gadgets, no new ones)

| Method | How |
|---|---|
| Murmur Cassette | Swap a looped tape into a recorder, so the monitors show an empty corridor |
| Static Lure | Jams a camera zone for a short time |
| Forged Dispatch | Gets patrols reassigned away from a sector |
| Breaker panels | Cut power to a zone (noticed faster) |
| Garuda Line | Reach gantries and balloon tethers |

## Ways to kill the governor

| Path | How | Fallout |
|---|---|---|
| Quiet | Takedown inside the crowd press, out of camera view | Low heat, body found later |
| Poison | Datura Ampoule in his ceremonial tea | Delayed, deniable |
| Frame | Forge a dispatch that points at a rival, so the king acts | Lowers stability, raises rival paranoia |
| Loud | Rifle or pistol | Crowd panic and crush risk. Highest heat. The worst option on purpose |

## Crowd rules

- Density flows along the procession route. Crowds part for the governor's retinue.
- Violence in the open starts a panic wave that spreads outward from the event and reroutes pilgrims.
- Crowd members are witnesses with limited sight and memory.
- **Performance:** about 40 full NPCs near the player, cheap instanced impostors beyond that. The count is untested on the Iris Xe target. Profile and adjust at MEDIUM.

## Escape: the bike

- A motorcycle waits outside the complex.
- **Inspiration:** a mid-80s two-stroke sports bike. Use an original, renamed design (working name TBD). Do not use any real manufacturer's name, logo or exact design. Log it in `ASSETS.md`.
- Handling: arcade. A custom `RigidBody3D`, upright stabilizer, visual lean, snappy powerband, light and twitchy. Not a real two-wheel balance model.
- Audio: synthesized two-stroke "ring-ding" through `SfxBank`, plus light blue smoke.
- **Pursuit:** Avekṣā bikes and drones. Route runs onto the A1 Mauryan Way. Pursuit ends when you reach the safehouse yard, or lose them out of sight long enough. All values are data.
- New controller: it's a new class in `bridge/`, not a reskin of `ArcadeCar`.

## Fallout (campaign)

- Uses the existing method-to-stability, heat, loyalty and paranoia rules. Numbers TBD in the data file.
- The governor is replaced by a successor.
- **Pataliputra Exchange:** add *Avekṣā Corp* as a listing. After a failed or loud attempt its price rises, since it wins more contracts. A clean kill barely moves it.
- Sample dispatch lines (dry, official):
  - *"The governor's accounts balanced the night he did not."*
  - *"Avekṣā reports no irregularities. It recorded none."*

## Open items

- [x] Governor's name, appearance, routine and weakness (`data/governors.ron`, `data/missions.ron`)
- [x] Temple name and layout once refs arrive (`godot/scripts/temple.gd`, refs/k*)
- [x] Avekṣā guard uniform (`body_kit.gd`, guard tint 2)
- [x] Bike name, model source and `ASSETS.md` rows (Kestrel Shikra 250, procedural)
- [x] Mission data file (RON) after the shape in `content.rs` is checked
- [ ] Crowd and impostor budget measured on target hardware (dev machine holds 59-60 fps at MEDIUM; target hardware not measured)
- [ ] Dead-feed timer and pursuit values tuned in playtest

## Build order

1. Surveillance detectors and the dead-feed timer on the existing test room.
2. Crowd with the impostor system, then panic.
3. Temple blockout with the procession route.
4. Kill paths (reusing mission 1 systems).
5. Bike controller and tuning, on the test track.
6. Pursuit and the escape route.
7. Dressing, audio and the Exchange listing.
