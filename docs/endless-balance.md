# Endless balance pass

## What made the opening punitive

Endless had its own rules and did not receive the late-campaign readability
changes. At depth 1 it shortened regrowth delay from 6.3 to about 5 seconds on
Normal, and from 4.7 to 2.4 seconds on Hard. Food fell from 2.5 to 1.3 seconds.
Hard also lost the 1.15 wall-density cap and gained a patrol and a sentry.
Its hunger, tap and regrowth curves were already clamped to their minimums at
depth 1, leaving essentially no resource ramp to ease into.

## New tuning

Only `Campaign._endless` changes. A new run starts below the campaign finale's
pressure, then approaches bounded limits using `1 - 0.98^(depth - 1)`.
About half the numeric ramp is reached at depth 35. Hard keeps denser terrain,
more/faster lights, fewer supplies and tighter resources than Normal.

| Resource | Normal opening → limit | Hard opening → limit |
| --- | --- | --- |
| Tap budget / par | 1.38 → 1.22 | 1.22 → 1.10 |
| Hunger seconds / par | 1.50 → 1.25 | 1.30 → 1.10 |
| Regrowth delay | 7.0 → 5.8 s | 5.6 → 4.4 s |
| Food time | 3.5 → 2.8 s | 3.5 → 2.8 s |
| Food tap refund | 2 | 1 |
| Treats / powerups requested | 5 / 4 | 4 / 3 |

- Lower opening wall/hazard densities grow gradually. Hard retains the late
  campaign's 1.15 cap on wall scaling, rather than jumping back to 1.30.
- Normal opens with two patrols and one sentry; Hard has one extra of each.
  One patrol is added at depth 16 and one sentry at depth 32, separate from the
  existing board-height steps at depths 12 and 24.
- All five specialist light types, fog, regrowth, hunger, tap limits and the
  full active powerup pool remain enabled. This is not an unlimited-resource mode.

## Compatibility and validation

Campaign and daily tuning, seed selection, board-size progression, unlocks,
run restart rules and saved records are unchanged. Endless layouts/pickups can
change because their densities and supply counts changed; a given depth and
mode remain deterministic. Existing best-depth records are retained.

`test/endless_balance_test.dart` adds checks for the campaign-to-Endless
transition, opening breathing room, monotonic bounded curves through depth
1,000,000, staged lights, Normal/Hard ordering, generated-route/resource
sanity, and application/reset of the rules in the live game.

Suggested focused regression run:

```sh
flutter test test/endless_balance_test.dart test/ending_test.dart \
  test/campaign_test.dart test/difficulty_test.dart \
  test/mechanic_roster_test.dart test/mode_clarity_test.dart
```

In the editing environment, the changed Dart files were parsed/formatted with
`dart_style` via its WASM port and the ramp arithmetic was checked separately.
Flutter tests could not execute: the SDK bootstrap failed downloading Dart
from storage.googleapis.com (TLS connection error); the mirror also failed.
The new tests still need to run in a working Flutter environment. No simulated
win-rate result or human/device playtest is claimed by this pass.
