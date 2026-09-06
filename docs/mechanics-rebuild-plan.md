# Mechanics Rebuild Plan — 30 Obstacles + 30 Powerups

Status: **implemented** (all six sections code-complete; `flutter analyze` +
the full test run still owed — the sandbox has no Flutter toolchain).
This document is the full list of what was built, where each piece enters
the campaign, how the pieces combine, and how difficulty scales them.

---

## 0. What exists today (the audit)

**Pickups currently in the game (9):**
`treat` (resource: +time +taps), `freeze`, `radiusPlus` (reach), `sprint`,
`scent`, `blast` (charge), `dig` (charge), `stake` (charge), `heel` (charge).

**Obstacle tile types currently in the game (6):**
`plain` (baseline, not an obstacle), `heavy` (2 taps), `anchor` (riveted wall),
`spring` (throws her along her momentum), `fault` (cracked ground, re-closes on
a short clock), `slope` (pushes her a fixed direction), `sunken` (only clearable
from adjacent open ground).

**Light entities currently in the game (2):**
`patrol` (sweeping light she won't enter; caught = −3 s hunger + shove),
`sentry` (sweeping light that refuses taps inside it).

All of the above are cleared/replaced by the sets below. The rebuild keeps the
game's rules of engagement intact:

- **The player never steers the dog.** Tools carve the field; she walks into
  whatever opens. Anything in the 60 that moves her does so through the board
  (springs, arrows), never through a joystick verb.
- **Every powerup answers a pressure the game actually applies** (taps, time,
  space, information, timing, position). Every obstacle applies one.
- **Charges are one decision each** (armed from the HUD, spent by one tap);
  timed effects are windows; resources are instant.
- **Difficulty now moves the board too.** There are two modes — Normal and
  Hard — and past the tutorial they differ in obstacles *and* supplies
  (densities ×1.3, one fewer treat/powerup, leaner treats) as well as
  budgets, clocks, light counts/speeds and fog. The tutorial trio stays
  identical on both; the floors keep Hard completable.
- **Determinism.** All placement stays seed-derived; new entity layers get
  their own XOR-masked RNG stream exactly like guards do today.

---

## 1. The 30 obstacles

Organised by the pressure they apply. Each entry: behavior → the decision it
creates → placement pattern → how it is drawn.

### Family A — Walls & weight (structure / tap tax)

| # | Name | Behavior & decision | Placement | Look |
|---|------|---------------------|-----------|------|
| 1 | **RIVET** | Never clearable. The wall every route bends around. (Succeeds `anchor`.) | Clumps of 1–3, solvability-checked per clump | Near-black hex with a rivet head at each corner |
| 2 | **BRAMBLE** | Two taps to clear. Route around vs pay through. (Succeeds `heavy`.) | Clumps of 1–3 on plain ground | Denser indigo tile with a doubled inner ring that cracks on the first hit |
| 3 | **HARDPAN** | Three taps. The late-campaign tax that replaces raising bramble density — one decision, three taps. | Singles and pairs, Mastery onward | Slab tile with two hairline seams; each hit sheds a seam |
| 4 | **LOCKBAR GATE + SWITCH** | Gate tile is solid until its *paired switch tile* anywhere on the board is opened; from then on it clears in one tap. Creates an ordered detour: find the switch first. | Gate on likely route, switch 4–8 cells off it; ≤2 pairs per board | Gate: pale hex with a crossbar and keyhole notch. Switch: hex with a single stud that lights when flipped |

### Family B — Closure (the field will not stay open)

| # | Name | Behavior & decision | Placement | Look |
|---|------|---------------------|-----------|------|
| 5 | **CRACKLINE** | Clears in one tap, then re-closes on its own ~2.2 s clock whether or not a wall is near. The route closes *ahead* of you — commit or go around. (Succeeds `fault`.) | Lines of 2–4 | Rust-warm tile with a jagged seam |
| 6 | **THATCH** | Clears in one tap, then snaps shut the instant she steps off it. A one-cross braid: no backtracking through it. | Lines of 2–3 across likely shortcuts | Woven hatch marks; after she crosses, it "knits" shut in one fast pulse |
| 7 | **OVERGROWTH HEART** | A diggable (not tappable) emitter: open ground within 2 rings of it regrows twice as fast while it stands. The space-pressure engine; DIG is its direct answer. | 1–2 per board, off-route | Dark green heart tile with creepers visibly reaching to its neighbours |
| 8 | **TREMOR VENT** | A vent tile that fires on a fixed rhythm: every pending regrowth timer on the board jumps forward 2 s (a closing surge), telegraphed by the vent flashing. Never bursts while any open path cell would seal her in with no warning — it only accelerates what was already closing. | 1 per board, Vigil/endless | Basalt tile with a pulsing ember core |

### Family C — Motion (her body is the playing piece)

| # | Name | Behavior & decision | Placement | Look |
|---|------|---------------------|-----------|------|
| 9 | **SPRING** | Clears in one tap; when she steps on it, throws her ~3 cells the way she was already moving. The one tile that *gives* distance — aimed by setup, not by steering. (Kept.) | Singles, ≥2 apart | Teal tile with a compressed coil glyph |
| 10 | **ARROWHEAD** | Clears in one tap; pushes her one fixed, drawn direction. The plannable spring: a lane you choose to enter. (Succeeds `slope`.) | Runs of 2–3 pointing the same way | Amber tile with a bold chevron in its push direction |
| 11 | **DRIFT ICE** | While she is on it, steering response mutes and momentum carries — she keeps her heading until she leaves. Free speed with no fine control. | Patches of 2–4 | Pale blue tile with a frost-sheen highlight |
| 12 | **MIRE** | She crosses at half speed. A pure time tax you pay per cell — cheap in taps, expensive on the clock. | Patches of 3–5 | Deep umber tile with suction rings |
| 13 | **EDDY** | Open tile that gently pushes her off her line while she crosses — a repulsor dot. Denies a resting place; carve around or push through briskly. | Singles near corridor junctions | Teal-dark tile with an outward ripple glyph |
| 14 | **MAGNET BLOOM** | Open tile that gently pulls her toward its centre while she crosses. The aimable inverse of Eddy: gathering force you can lean on — or get caught by. | Singles | Violet tile with an inward spiral glyph |

### Family D — Information (the fog has texture)

| # | Name | Behavior & decision | Placement | Look |
|---|------|---------------------|-----------|------|
| 15 | **THICKET** | Its neighbours' types stay hidden until the thicket itself is cleared — fog you must carve through. Cheap (1 tap) but blinds the read. | Strings of 2–3 across vision lanes | Dark tile with overlapping leaf strokes |
| 16 | **SLEEPER** | Holds its disguise longer than everything else: type is only revealed when she is *adjacent*, not at reveal radius. "Plain until proven three-tap." | Singles among plain ground | Identical to plain until she is next to it, then shows its true face with a flicker |
| 17 | **FOXFIRE** | A decoy glimmer: through the fog it shines exactly like a pickup, but it is just a tile. Taxes the detour instinct. Placement honours the same 1–4-cells-off-route band as real pickups so the bluff is always plausible. | 1–3 per board | A pickup-sized glow over an ordinary tile; on approach the glow gutters out |

### Family E — Position (where you may carve from)

| # | Name | Behavior & decision | Placement | Look |
|---|------|---------------------|-----------|------|
| 18 | **SUNKEN** | Only clearable while some tile beside it is already open. You must walk up to it — range is no help. (Kept.) | Patches of 2–4 | The dimmest tile on the board |
| 19 | **SCAFFOLD** | The inverse: only clearable from *2+ cells away* — too close and it is unstable. It must be carved early, from range, before she stands beside it. REACH's first real job. | Singles on likely routes | Pale tile on stilts, with a "keep back" ring mark |
| 20 | **MIRROR LOCK PAIR** | Two linked tiles: tapping either *charges* it; both open only once both are charged. Costs the honest 2 taps for 2 cells but enforces split carving across distance. ECHO is its direct answer. | ≤2 pairs, well separated | Twin tiles with a thin silver thread drawn between them when both are revealed |

### Family F — Contact hazards (the ground bites)

| # | Name | Behavior & decision | Placement | Look |
|---|------|---------------------|-----------|------|
| 21 | **THORNPAD** | Stepping on it bites 2 s off the hunger clock. Never blocks; always hurts. Route over it only when the shortcut beats 2 s. | Clusters on shortcut lines | Ash tile with three short spikes |
| 22 | **ALARM BELL** | Stepping on it whips every light on the board to +50% sweep speed for 6 s. A shortcut that angers the lights. | Singles at tempting cut points | Brass tile with a clapper glyph; rings visibly when armed |

### Family G — Lights (the moving layer; extends the Guard engine)

| # | Name | Behavior & decision | Placement | Look |
|---|------|---------------------|-----------|------|
| 23 | **PATROL** | Sweeps a route; she refuses lit ground and is bitten (−3 s) and shoved if caught. Timing pressure. (Kept.) | Walking routes of 3–6 cells | Red warning light pool |
| 24 | **SENTRY** | Sweeps a route; **taps** inside its light are refused. A wall for your hands. (Kept.) | As patrol | Cold white-blue light pool |
| 25 | **BEACON** | A *static* sentry light over a fixed 7-cell patch. The training sentry: timing without motion — wait for the window that never comes, and instead route your carving rhythm through the patch. | One fixed patch off the main route | Steady lighthouse glow, unblinking |
| 26 | **SPINNER** | A light rotating steadily around a pivot cell — an arc sweep. Creates rhythm windows around a point rather than across a corridor. | Pivot off-route, radius 1–2 | Light pool orbiting a hub cell |
| 27 | **RUNNER** | A light dashing a straight line at ~2.5× patrol speed, pausing 1.2 s at each end with a visible wind-up. Fast, fully telegraphed crossing windows. | Straight corridors of 3–5 cells | Thin, bright streak with a fading trail |
| 28 | **BLINKER** | A fixed 7-cell patch that phases fully on/off on a fixed beat (≈1.6 s on / 1.6 s off). Pure timing ground — the rhythm game of taps. | One patch | Light pool breathing on a metronome |
| 29 | **WARDEN** | A slow patrol that also **instantly re-closes** every open tile it passes over. A moving regrowth engine; the corridor it walks is never safe behind you either. | Vigil peak boards | Deep crimson light that leaves closed tiles in its wake |

### Family H — Terrain (whole-board features)

| # | Name | Behavior & decision | Placement | Look |
|---|------|---------------------|-----------|------|
| 30 | **GLOOM BAND** | A horizontal strip (2–3 rows) where reveal radius is halved. Terrain-level fog: you cross it sightless or burn LANTERN. | One band angled across the mid-board | A soft darkness gradient; tiles inside render dimmer even when revealed |

---

## 2. The 30 powerups

Format: type (Resource / Timed / Charge / Passive), effect, the pressure it
answers, and the board it is meant to shine on.

### Family A — Resources (instant)

| # | Name | Effect | Answers |
|---|------|--------|---------|
| 1 | **TREAT** | +seconds and +taps (campaign-scaled, as today). The base currency. | The clock *and* the budget at once |
| 2 | **RATION** | +taps only (no time). The dedicated budget rescue for boards where time is fine and taps are bleeding. | Tap budget, precisely |

### Family B — Timed windows (10)

| # | Name | Effect | Answers |
|---|------|--------|---------|
| 3 | **FREEZE** | Regrowth holds for 5 s. (Kept.) | The field closing |
| 4 | **SPRINT** | Her drift ×1.65 for 6 s. (Kept.) | The clock |
| 5 | **REACH** | Tap radius ×1.6 for 8 s. (Kept.) | Carve position |
| 6 | **SCENT** | Lights the cheapest remaining route through the fog for 5 s. (Kept.) | Being lost |
| 7 | **LANTERN** | Reveal radius ×1.8 for 10 s. | Fog generally (where SCENT answers with one route, this answers with a map) |
| 8 | **CLOAK** | Patrol lights ignore her for 7 s — she may cross lit ground, unbitten and unshoved. | Patrol timing |
| 9 | **SLOWBEAT** | All lights on the board sweep at half speed for 7 s. | Every light at once |
| 10 | **WARDOWN** | Taps work through sentry light for 7 s. | Warded ground |
| 11 | **SUREPAWS** | For 10 s she ignores spring throws, arrow pushes, ice mute and eddy/magnet drift — full control through hazard lanes. | Control taxes |
| 12 | **PAIRWORK** | For 8 s, every tap strikes twice at the tapped tile: brambles fall in one tap, hardpan in one-and-a-half. One tap is still spent. | Multi-tap tiles |

### Family C — Charges (13; arm from the HUD, spent by one tap)

| # | Name | Effect | Answers |
|---|------|--------|---------|
| 13 | **BLAST** | Clear a ring-1 cluster around the tapped tile. (Kept.) | Dense clusters |
| 14 | **DIG** | Break one riveted wall — the only thing that can. Also the only removal for OVERGROWTH HEARTS. (Kept.) | Structure |
| 15 | **STAKE** | Pin one open tile open forever. (Kept.) | One cell that must never close |
| 16 | **HEEL** | The next tap also holds her still for 2.5 s. (Kept.) | A wrong moment |
| 17 | **TROWEL** | Clear a straight run of 3 tiles starting at the tapped tile, along the tapped direction. The line version of BLAST. | Corridors, hardpan seams |
| 18 | **MAUL** | The next tap fully breaks *any* clearable tile in one hit — hardpan included. | Deep tap-tax tiles |
| 19 | **ECHO** | The next tap also strikes the tile mirrored across her position, if it is clearable. | Split carving (MIRROR LOCKS above all) |
| 20 | **REWIND** | Instantly reopens the last 6 tiles that closed this run. | A closing wave at her back, a failed crackline run |
| 21 | **MOLE** | Clear any one *revealed*, non-wall tile anywhere on the board. Reach itself, once. | Position (the one exception to "carve near her") |
| 22 | **HARVEST** | Instantly collects the nearest visible uncollected pickup within 5 rings. | The detour economy (skips FOXFIRE bluffs — it only takes real pickups) |
| 23 | **WHISTLE** | She backtracks 3 cells along her own trail, undoing the last stretch of drift. Not steering — a rewind. | A bad spring / arrow / magnet ride |
| 24 | **SEED** | Tamp one solid plain tile beside open ground into a permanent wall. The inverse of DIG: builds one bumper where you decide. Solvability-checked on spend (refused if it would sever the route, exactly like generator anchors). | Her drifting into things; also blocks unwanted arrow lanes |
| 25 | **BEACON** | Drop a lamp at her cell; it holds a wide reveal bubble there for the rest of the run. | Fog *in a place* — light the crossroads you keep returning to |

### Family D — Passives (5; run-long, rare)

| # | Name | Effect | Answers |
|---|------|--------|---------|
| 26 | **POUCH** | The next Treat collected pays double. One-shot. | Resource luck |
| 27 | **IRONPAW HEART** | For the rest of the run, THORNPADS and ALARM BELLS do not trigger when she crosses. | Contact hazards |
| 28 | **NIGHT EYES** | Reveal radius +25% for the rest of the run. Stacks with LANTERN's window. | Fog, forever |
| 29 | **KEEPSAKE** | The first time this run she would be crushed or starve, consume this instead and continue with +8 s on the clock. | The run itself — a life. Endless-focused, very rare in campaign |
| 30 | **WAYSTONE** | Shows the bearing toward the food (the §8 directional hint) permanently this run, without waiting to get stuck. | Wrong reads before they happen |

---

## 3. Stage-by-stage introduction schedule

Exactly one new idea per level, each followed by a forgiving practice beat,
then worked into combinations — the existing `LevelPace` cadence
(introduction → practice → combination/challenge → breather), extended across
all 30+30. Gates below are the landing levels (they get the banner, the
counter-relief and the "introduced floor density" treatment today's
springFrom/guardsFrom/faultFrom receive).

| Band | Levels | Obstacles enter | Powerups enter |
|------|--------|-----------------|----------------|
| Tutorial | 1–3 | RIVET, BRAMBLE (L2) | TREAT (L3) |
| Foundation | 4–20 | FOG (4, banner), MIRE (5), SPRING (9), THICKET (12), SLEEPER (15), FOXFIRE (18) | SPRINT (6), SCENT (8), RATION (14), LANTERN (17), PAIRWORK (19); FREEZE & REACH already taught in tutorial pool |
| Pressure | 21–40 | PATROL (21), CRACKLINE (29), THATCH (33), DRIFT ICE (36), ALARM BELL (39) | BLAST (22), SLOWBEAT (24), CLOAK (27), STAKE (31), TROWEL (35), HARVEST (37) |
| Mastery | 41–60 | DIG-answer boards start with RIVETS-dense (41), HARDPAN (44), OVERGROWTH HEART (47), SENTRY (51), EDDY (54), SCAFFOLD (58) | DIG (41), MAUL (43), REWIND (46), SUREPAWS (49), WARDOWN (52), HEEL (53), ECHO (56), SEED (59) |
| Collapse | 61–80 | ARROWHEAD (63), MAGNET BLOOM (66), SPINNER (69), BLINKER (72), GATE + SWITCH (75), RUNNER (78) | MOLE (64), WAYSTONE (70), BEACON (76), NIGHT EYES (79) |
| Vigil | 81–100 | SUNKEN (83), MIRROR LOCK (86), THORNPAD (89), WARDEN (92), GLOOM BAND (93), TREMOR VENT (97) | POUCH (87), IRONPAW HEART (90), KEEPSAKE (99) |
| Endless | 101+ | Everything active; densities/timers asymptote to floors as today | Full pool |

Design notes baked into the schedule:

- **Meet it → practise it → then get the answer it two levels later** is kept
  wherever a tool directly answers a hazard (CRACKLINE 29 → STAKE 31,
  SENTRY 51 → WARDOWN 52 → HEEL 53, HARDPAN-adjacent MAUL at 43, GATE 75 →
  MOLE-side relief at 76 via BEACON… exact pairs get tuned with playtests).
- **Never two new ideas on one level.** Introduction levels always run
  eased numbers (`LevelPace.introduction` relief), and the floor-density rule
  (an introduced mechanic must actually *appear* on its banner level) is kept.
- **Challenge peaks are all gauntlets** — full-pressure boards using only
  already-taught mechanics, as today.

---

## 4. Combinations

The signature system (`LevelSignature`) gains a home per new mechanic, and a
small set of **designed pairings** names the combos the campaign deliberately
builds. Rules that hold for all combos:

1. A combination level mixes **at most 3 pressure axes** at once (e.g. taps +
   timing + info); everything else is suppressed so the pair reads.
2. A pairing is only used after **both** mechanics have had their solo
   introduction *and* practice beats.
3. Suppression beats from signatures still apply: a level *about* a pair
   reduces other obstacles rather than stacking everything.

Designed pairings (each becomes a signature with its own level identity):

| Pairing | Why it works |
|---|---|
| SPRING × CRACKLINE | The throw only pays if the landing zone stays open — run the line fast |
| ARROWHEAD × REGROWTH | Fixed lanes under a clock: catch the lane early |
| HEEL × SPINNER/BLINKER | Hold her in the safe pocket, open the corridor during the off-beat |
| CLOAK × twin PATROLS | Walk the overlap once, deliberately |
| ECHO × MIRROR LOCK | The tool was built for this lock |
| SEED × EDDY | Build the bumper that cancels the push |
| LANTERN/BEACON × GLOOM BAND | Light against terrain darkness |
| MAUL × HARDPAN seams | Pay 1 where the board asks 3 |
| SUREPAWS × ARROW lanes | Take the lane's speed, refuse the steering loss |
| REWIND × TREMOR VENT | Answer the surge after the fact |
| HARVEST × FOXFIRE | The magnet only takes real pickups — the bluff is disarmed |
| WARDOWN × crossed SENTRY lanes | Act through the crossfire |
| GATE × SCENT | Find the switch before finding the gate |
| STAKE × THATCH | Pin the one-cross tile to keep the braid open |
| NIGHT EYES × SLEEPER/THICKET boards | Info insurance vs layered fog |
| MIRROR LOCK × MOLE | MOLE clears one half-from anywhere; you still owe the near half — halves the lock, respects the rule |

---

## 5. Difficulty integration

**Two modes.** The tutorial (levels 1–3) is identical on both. From stage 4,
Normal carries a light adventurer's tax and Hard is brutal — and the board
itself now moves with the mode, not just its pressures.

| Knob | Normal | Hard |
|---|---|---|
| Obstacle densities (all families, placed) | ×1.0 (authored curve) | ×1.3 |
| Treats / powerups in the field | as authored | −1 each (floored ≥1) |
| Taps a treat pays | as authored | −1 (floored ≥1) |
| Tap budget relief | −0.04× par | −0.20× par (floor 1.06 / **1.00** par) |
| Hunger clock / cell | −0.04 s | −0.22 s (floor 0.85 / 0.72 s) |
| Light counts (all kinds, guard RNG stream) | — | +2 (floored ≥1 per taught mechanic) |
| Light speed | +0.05 | +0.45 (ceiling widens by the same step) |
| Regrow / crackline / thatch / tremor timers | −0.3 s | −1.4 s (floor 3.2 / 2.4 s) |
| Contact bites (thorn, patrol) | ×1.0 | ×1.6 (−4.8 s patrol sting) |
| Reveal factor / fog | ×0.92 | ×0.60 |
| Directional hint | shown | suppressed |
| Rhythm beats (BLINKER cycle, RUNNER pause) | ×1.0 window | ×0.7 window |

Determinism discipline, kept: the board-changing deltas (density scale, supply
counts) are applied to already-computed campaign values — a value shift, never
a re-seed — so Normal's authored curve and its sweeps still pass untouched,
and the daily (always Normal) stays one board for everyone.

---

## 6. Files this touches (engineering map)

- `lib/hex/hex_cell.dart` — new `HexType` entries, per-cell fields (switch
  links, pair links, timers), interaction verbs.
- `lib/entities/guard.dart` + `lib/systems/guard_system.dart` — extend to a
  general **lights** engine: path-type per light (walk / orbit / dash / blink
  / static / warden), placement with separation rules per kind.
- `lib/entities/pickup.dart` — new `PickupKind` entries, durations, charge
  flags, passive handling.
- `lib/systems/input_system.dart` — new tap outcomes (`locked`, `unstable`,
  `paired`), footing rules, scaffold range rules.
- `lib/systems/pickup_system.dart` — placement weights per kind, FOXFIRE
  decoy placement sharing the same detour band.
- `lib/systems/softlock_system.dart`, `lib/gen/pathfinder.dart` — cost
  accounting for gates, mirror locks, hearts (DIG-removable ⇒ priced like
  anchors on the in-principle route).
- `lib/gen/level_generator.dart` — a placement pass per family with the same
  protected/clump/solvability discipline as today.
- `lib/game/level_rules.dart` — the new gates, per-band curves (densities,
  counts, timers), signatures, pace beats, banners.
- `lib/game/difficulty.dart` — the new deltas in §5.
- `lib/game/hexcape_game.dart` — interaction wiring (contact hazards, cloaks,
  charge spends, passives, wake/surge events).
- `lib/components/glyphs.dart`, `lib/theme/palette.dart`,
  `lib/components/field_component.dart` — every entry gets: its own colour
  tokens **plus** a distinct stroke glyph so nothing is told apart by colour
  alone (existing §9 rule), plus state animation (charge flicker, blink beat,
  gate thread, heart creepers).
- `lib/ui/reference_sheet.dart`, `lib/ui/hud.dart`, inspector — all 60 get
  reference entries and inspector copy; HUD charge row gets overflow handling.
- Tests: extend `obstacle_test`, `generator_test`, `tap_resolution_test`,
  `campaign_sweep_test`, `playthrough_test`, `vigil_test`,
  `difficulty_*_test`, `daily_test` (determinism), plus one focused suite per
  new family; re-run the benchmark methodology from
  `docs/hunger-balance-verification.md` on the rebuilt campaign.

---

## 7. Explicitly out of scope (protecting the concept)

- No steering tools, no teleports for the dog (WHISTLE is a 3-cell rewind of
  her own trail, not a steering verb — flagged, see questions).
- No powerup that grants taps *and* time *and* info at once — every pickup
  answers **one** pressure (TREAT excepted as the base economy piece).
- No obstacle that can cause an unavoidable loss (solvency checks on
  placement; contact bites only ever cost time).
- No difficulty lever that changes board generation streams.

## 8. Delivery plan (after approval)

1. **Foundations pass**: enums, palette tokens, glyphs, reference entries,
   tuning/debug sliders for all 60 (visible in debug, gated off from campaign).
2. **Obstacles**: tiles first (cell-level logic + placement + input), then the
   lights engine generalisation, then terrain features.
3. **Powerups**: resources & timed effects, then charges + HUD, then passives.
4. **Campaign integration**: gates, signatures, banners, pace beats,
   difficulty deltas, endless floors.
5. **Verification**: unit suites per family, campaign sweep & floor-player
   playthrough green, daily determinism unchanged, balance benchmark rerun and
   re-published.
