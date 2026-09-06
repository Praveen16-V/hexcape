import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';

import 'sim/simulated_player.dart';

/// Every field of [LevelRules], flattened for comparison.
///
/// Listed rather than derived, for the reason [Campaign.rulesFor] refuses a
/// `copyWith`: there is no reflection here, so a field added later will not
/// appear in this list on its own. It is written out in full so that adding one
/// and forgetting it is a visible omission in a file about exactly this.
List<Object?> _fields(LevelRules r) => [
  r.level,
  r.seed,
  r.columns,
  r.rows,
  r.anchorDensity,
  r.heavyDensity,
  r.springDensity,
  r.faultDensity,
  r.guards,
  r.sentries,
  r.guardSpeed,
  r.treats,
  r.powerups,
  r.offeredPowerups,
  r.powerupRotation,
  r.introduces,
  r.treatSeconds,
  r.treatTaps,
  r.regrowth,
  r.regrowDelay,
  r.fog,
  r.budget,
  r.budgetMultiplier,
  r.hunger,
  r.hungerSecondsPerCell,
  r.teaches,
  r.pace,
];

/// The board, without the pressure: everything difficulty promises not to move.
List<Object?> _board(GeneratedLevel level) => [
  level.par,
  level.grid.start,
  level.grid.exit,
  level.grid.truePath,
  [
    for (final entry
        in level.grid.cells.entries.toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString())))
      '${entry.key}:${entry.value.type}',
  ],
  [for (final p in level.pickups) '${p.coord}:${p.kind}'],
];

void main() {
  group('Difficulty', () {
    test('Normal changes nothing at all', () {
      // The guard that protects every existing save file, star record and test
      // in this suite. If this fails, the whole campaign has quietly shifted
      // under players who never asked for a difficulty setting.
      for (var n = 1; n <= Campaign.length + 20; n++) {
        expect(
          _fields(Campaign.rulesFor(n, difficulty: Difficulty.normal)),
          _fields(Campaign.rulesFor(n)),
          reason: 'level $n differs under an explicit Normal',
        );
      }
    });

    test('the three guided levels ignore it', () {
      for (var n = 1; n <= Campaign.tutorialBand; n++) {
        for (final d in Difficulty.values) {
          expect(
            _fields(Campaign.rulesFor(n, difficulty: d)),
            _fields(Campaign.rulesFor(n)),
            reason: 'tutorial level $n moved on ${d.label}',
          );
        }
      }
    });

    test(
      'all three difficulties play the same board',
      () {
        // The invariant the whole design rests on. Anchors, heavies, springs,
        // faults and pickups are placed from one shared RNG stream, so moving
        // any density would shift every draw after it and relocate the treats —
        // which is why difficulty scales none of them. This is the test that
        // catches anyone adding one later.
        for (var n = 1; n <= Campaign.length; n++) {
          final normal = LevelGenerator.generate(specFor(Campaign.rulesFor(n)));
          for (final d in [Difficulty.easy, Difficulty.hard]) {
            final other = LevelGenerator.generate(
              specFor(Campaign.rulesFor(n, difficulty: d)),
            );
            expect(
              _board(other),
              _board(normal),
              reason: 'level $n generates a different board on ${d.label}',
            );
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'no level demands provably optimal play on Hard',
      () {
        // The same fairness gate `campaign_sweep_test` walks for Normal. Hard
        // tightens the budget, so it is the setting that could cross the floor.
        for (var n = 1; n <= Campaign.length; n++) {
          final rules = Campaign.rulesFor(n, difficulty: Difficulty.hard);
          if (!rules.budget) {
            continue;
          }
          final level = LevelGenerator.generate(specFor(rules));
          final budget = (level.par * rules.budgetMultiplier).ceil();
          expect(
            budget - level.par,
            greaterThanOrEqualTo(2),
            reason:
                'level $n on Hard gives ${budget - level.par} spare taps over '
                'par ${level.par}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test('Easy is never harder than Normal, and Hard never easier', () {
      for (var n = Campaign.tutorialBand + 1; n <= Campaign.length + 20; n++) {
        final easy = Campaign.rulesFor(n, difficulty: Difficulty.easy);
        final normal = Campaign.rulesFor(n);
        final hard = Campaign.rulesFor(n, difficulty: Difficulty.hard);

        expect(
          easy.budgetMultiplier,
          greaterThanOrEqualTo(normal.budgetMultiplier),
          reason: 'level $n: Easy has fewer taps',
        );
        expect(
          hard.budgetMultiplier,
          lessThanOrEqualTo(normal.budgetMultiplier),
          reason: 'level $n: Hard has more taps',
        );

        expect(
          easy.hungerSecondsPerCell,
          greaterThanOrEqualTo(normal.hungerSecondsPerCell),
          reason: 'level $n: Easy has less time',
        );
        expect(
          hard.hungerSecondsPerCell,
          lessThanOrEqualTo(normal.hungerSecondsPerCell),
          reason: 'level $n: Hard has more time',
        );

        expect(
          easy.guardSpeed,
          lessThanOrEqualTo(normal.guardSpeed),
          reason: 'level $n: Easy has faster patrols',
        );
        expect(
          hard.guardSpeed,
          greaterThanOrEqualTo(normal.guardSpeed),
          reason: 'level $n: Hard has slower patrols',
        );

        expect(
          easy.guards,
          lessThanOrEqualTo(normal.guards),
          reason: 'level $n: Easy has more patrols',
        );
        expect(
          hard.guards,
          greaterThanOrEqualTo(normal.guards),
          reason: 'level $n: Hard has fewer patrols',
        );

        expect(
          easy.regrowDelay,
          greaterThanOrEqualTo(normal.regrowDelay),
          reason: 'level $n: Easy regrows faster',
        );
        expect(
          hard.regrowDelay,
          lessThanOrEqualTo(normal.regrowDelay),
          reason: 'level $n: Hard regrows slower',
        );
      }
    });

    test('a mechanic the campaign has taught never disappears on Easy', () {
      // Easy quietens patrols; it must not remove them from a level whose whole
      // point is that patrols exist.
      for (var n = Campaign.guardsFrom; n <= Campaign.length; n++) {
        expect(
          Campaign.rulesFor(n, difficulty: Difficulty.easy).guards,
          greaterThanOrEqualTo(1),
          reason: 'level $n has no patrols at all on Easy',
        );
      }
      for (var n = Campaign.sentriesFrom; n <= Campaign.length; n++) {
        expect(
          Campaign.rulesFor(n, difficulty: Difficulty.easy).sentries,
          greaterThanOrEqualTo(1),
          reason: 'level $n has no sentries at all on Easy',
        );
      }
    });
  });
}
