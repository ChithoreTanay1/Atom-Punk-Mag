# LORE.md

The only source of "history" for this project. If it's not here, it's `INVENTED`, and must be marked so in data and code comments.

Tags: **[HIST]** attested in period or near-period sources. **[TRAD]** from later Indian tradition, with uncertain historicity. **[INVENTED]** ours.

## Honest caveats

- Every Indian account of Chandragupta and Chanakya is **late**: *Mudrarakshasa* (roughly 4th to 8th c. CE), *Parishishtaparvan* (12th c. CE), Buddhist chronicles (Sri Lankan, later). Their stories conflict and are partly legend.
- The *Arthashastra* is traditionally credited to Kautilya/Chanakya, but its date and authorship are debated among scholars. Use it as a **design source**, not as proof of Nanda-era practice.
- The Greek accounts of Alexander are also written generations after the events, and their army figures disagree.
- Almost nothing is reliably known about the Nanda **provincial administration**. Governors, provinces and officials in this game are `INVENTED`.

## Timeline

| When | Event | Tag | Source |
|---|---|---|---|
| 326 BCE | Alexander's army reaches the Hyphasis (Beas) and refuses to go further | [HIST] | Arrian *Anabasis* 5.25–29; Curtius 9.2–3; Diodorus 17.93–95; Plutarch *Alexander* 62 |
| 326 BCE | Greek sources hear of a powerful eastern king (Agrammes/Xandrames) with a huge army, a major reason the troops balk | [HIST] | Diodorus 17.93; Curtius 9.2; Plutarch *Alexander* 62 |
| c. 321 BCE | Nanda dynasty falls; Chandragupta takes Magadha | [HIST], details [TRAD] | Indian tradition; Greek/Latin sources use "Sandrocottus/Androcottus" |
| later | Maurya empire grows under Chandragupta | [HIST] | |

Dates are approximate. Say "c." in-game.

## Setting

- **Magadha**, capital **Pataliputra** (Greek: Palibothra). [HIST]
- The Nandas were proverbially rich, and the Greek texts stress the size of their army. [HIST]
- Reported army size: Greek sources give about 200,000 infantry plus cavalry, chariots and elephants, with the numbers varying by author. Use "huge, roughly 200,000 foot" in-game, not precise counts. [HIST]
- Curtius preserves a hostile story that the ruler was low-born and gained the throne by murder. Treat it as propaganda-flavored rumor, which fits as in-game rumor material. [HIST source, doubtful content]

## Characters

| Name | Role | Tag | Notes |
|---|---|---|---|
| Chanakya (Kautilya, Vishnugupta) | Brahmin strategist | [TRAD] | Jain and Buddhist tradition has him insulted and expelled by the Nanda king; he vows revenge. Authorship of the *Arthashastra* is debated. |
| Chandragupta | Future founder of the Maurya dynasty | [HIST]/[TRAD] | Greek sources know him as Sandrocottus/Androcottus. Plutarch (*Alexander* 62) says he saw Alexander as a youth; Justin (15.4) says he offended Alexander. |
| Dhana Nanda | Last Nanda king | [TRAD] | Name from Indian and Greek-later tradition. In the game, "the King". |
| Rakshasa | Nanda minister | [TRAD] | Central to *Mudrarakshasa*, loyal to the Nandas after their fall. |
| Shakatala | Nanda minister | [TRAD] | Appears in Jain tradition. |
| Alexander | Macedonian king | [HIST] | Backstory and frame only. No gameplay. |
| Governors, spies, rivals, gadget-makers | | [INVENTED] | Make them freely, but tag them. |

## Frame story

[INVENTED] In the far future, someone models Alexander's march from Greece to the Indus. The model reaches the Beas and stalls. The India beyond it is the player's playground: a simulation of Magadha rendered in retro-future style. Keep the frame light: menu text, loading screens, short logs. It is flavor, not a plot.

## Invented content in this build [INVENTED]

All of the following is ours; none of it is history.

- **Provinces:** Saptavarta, Vatsabhumi March, Ujjayanta Reach, Dakshavana, Hiranyavaha Circle.
- **Governors:** Virabhadra Kaushika (Saptavarta, the slice target), his successors Kumaradeva Pingala and Sudarshana Haritaki, Bhuvanesha Andhaka, Dandapani Mauli, Mahasena Tarkshya, Ugrasena Bhauma. Their loyalties, rivalries and biographies in `data/governors.ron` are invented.
- **Gadgets and weapon:** Vajra Mk.VII carbine, Murmur Cassette tape bug, static lure, datura ampoule, forged dispatch (names, stats, behaviour). Datura as a poison has traditional precedent; the gadget is ours.
- **Mriga 9, Nakha knife, Garuda Line:** the suppressed pistol, the knife with throwing blades and the grappling line are all invented, including their names and stats. *Mriga* (deer), *nakha* (claw) and *Garuda* (the eagle mount of Vishnu) are real Sanskrit words, used loosely.
- **Guard dress:** steel plate over brown tunics for the line guards, and black carbon armour with ochre capes for the elite. The atompunk look comes from the user's reference image. It is not a historical Mauryan uniform.
- **Mission:** the Saptavarta compound, the governor's evening routine, every spoken line, the intel items, and the telex-to-the-capital frame path.
- **Rumors, agent operations and night events** in `data/rumors.ron`, `ops.ron` and `events.ron`. Their mechanics take inspiration from the *Arthashastra* (see below), but the texts are ours.
- **Frame story texts:** "archive model 326-B" and its menu lines.
- **The Pataliputra Exchange** (`data/market.ron`): a pretend stock market in the style of an early-1980s trading floor (prices in eighths, ticker tape, telex wire). Currency "pana" (a real ancient coin name, used loosely). All 15 listed companies, their tickers and descriptions are invented: Vajra Steel Works Ltd. (VJRA), Magadha Iron & Alloy Corp. (MIAC), Pataliputra Cement Co. (PCEM), Sone Valley Portland Ltd. (SVPL), Kosala Data Machines Corp. (KDMC), Ratnadeep Electronics Inc. (RTDP), Akashvani Telecom Corp. (AKTC), Ganga Grain Holdings Ltd. (GGRN), Sugandha Tea & Spice Co. (STSC), Krishi Fertiliser Corp. (KFRT), Surya Atomic Power Corp. (SAPC), Kestrel Motor Works Ltd. (KMWL), Garuda Aerodyne Inc. (GRDA), Nanda Royal Treasury Bank (NRTB), Dandapani Arms Corp. (DPAC). Company ties to governors (whose death moves which stock) are ours.
- **A1 Mauryan Way:** the expressway of the feel test, its "A1 Pataliputra" signs, its buildings, the stone elephant and the traffic. The road name comes from the dev's reference image (`refs/expressway.jfif`); "Mauryan" anticipates a dynasty that does not exist yet in the simulation's year, which is part of the archive model's anachronism, not history.
- **Kestrel 80:** the wedge coupe you drive, built by Kestrel Motor Works. Invented make; the shape nods to the 1968 Bertone Carabo concept car.

- **The Great Temple and its festival, *Nothing Unobserved*:** the rock-cut temple, the Hiranyavaha treasury governor, his successor Ratnakara Savarna, the routine, every line and the dispatches. Its carved court is generic and names no deity [INVENTED].
- **Avekṣā Corp:** the private surveillance contractor, its grey uniform, cameras, aerostat and drones, and the reel room [INVENTED].
- **Kestrel Shikra 250:** the two-stroke motorcycle, a second model from the invented Kestrel Motor Works [INVENTED].

## Design source: espionage (the *Arthashastra*)

These inform mechanics. They are **DESIGN**, not Nanda-era fact. Verify book and chapter numbers against your translation.

- Book 1: the king's use of spies and the types of agents, including covert and "firebrand" agents. Source for contracts, informants and the agent roster.
- Book 4, "Removal of Thorns": suppressing internal enemies by covert means. Source for the assassination and framing toolkit.
- Book 5: conduct of courtiers and the management of officials. Source for governor loyalty and suspicion.
- Book 12: covert means against a powerful enemy. Source for sabotage and deception mechanics.
- Use the sowing of discord (sedition between officials) as a core mechanic: **kill a governor, or make a rival look guilty.**

## Rules for adding lore

1. Cite a source from the list below, or tag it `[INVENTED]`.
2. Never present `[TRAD]` as proven.
3. No real-world religious or ethnic caricature. Characters are officials, spies and soldiers in a political thriller.
4. New [HIST] facts need a source line in the table before use.

## Sources

- Kautilya, *Arthashastra*: R. P. Kangle (ed./trans.) or Patrick Olivelle (trans.).
- Vishakhadatta, *Mudrarakshasa*.
- Hemachandra, *Parishishtaparvan*.
- Arrian, *Anabasis of Alexander*; Quintus Curtius Rufus, *History of Alexander*; Diodorus Siculus, Bk. 17; Plutarch, *Life of Alexander*; Justin, *Epitome* 15.4.
- Modern: Romila Thapar; Radhakumud Mookerji; A. B. Bosworth.
