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
  r.hardpanDensity,
  r.thatchDensity,
  r.overgrowthDensity,
  r.tremorDensity,
  r.iceDensity,
  r.mireDensity,
  r.eddyDensity,
  r.magnetDensity,
  r.thicketDensity,
  r.sleeperDensity,
  r.foxfireDensity,
  r.scaffoldDensity,
  r.thornDensity,
  r.alarmDensity,
  r.gatePairs,
  r.mirrorPairs,
  r.gloom,
  r.guards,
  r.sentries,
  r.beacons,
  r.spinners,
  r.runners,
  r.blinkers,
  r.wardens,
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
  group('The two modes', () {
    test('there are exactly two of them', () {
      // The design decision, pinned: one adventure and one gauntlet.
      expect(Difficulty.values, [Difficulty.normal, Difficulty.hard]);
    });

    test('a saved "easy" key reads as Normal', () {
      // Old builds could persist the retired mode; it must not crash, and the
      // run it describes is closest to the adventure.
      expect(Difficulty.fromKey('easy'), Difficulty.normal);
      expect(Difficulty.fromKey('hard'), Difficulty.hard);
      expect(Difficulty.fromKey(null), Difficulty.normal);
    });

    test('Normal is its own curve; asking for it explicitly changes nothing', () {
      // The guard that protects every existing save file, star record and test
      // in this suite: the *default* campaign and the explicitly-normal one
      // must stay the same rules.
      for (var n = 1; n <= Campaign.length + 20; n++) {
        expect(
          _fields(Campaign.rulesFor(n, difficulty: Difficulty.normal)),
          _fields(Campaign.rulesFor(n)),
          reason: 'level $n differs under an explicit Normal',
        );
      }
    });

    test('the tutorial ignores both modes', () {
      // Three scripted levels are a lesson, not a contest. Both modes leave
      // them alone — rules and boards alike — and Difficulty.tutorialLevels
      // must stay the campaign's tutorial count, because the constant lives in
      // this file: level_rules imports difficulty and the arrow runs one way.
      expect(Difficulty.tutorialLevels, Campaign.tutorialBand);
      for (var n = 1; n <= Campaign.tutorialBand; n++) {
        final ours = LevelGenerator.generate(specFor(Campaign.rulesFor(n)));
        for (final d in Difficulty.values) {
          expect(
            _fields(Campaign.rulesFor(n, difficulty: d)),
            _fields(Campaign.rulesFor(n)),
            reason: 'tutorial level $n moved on ${d.label}',
          );
          expect(
            _board(LevelGenerator.generate(
              specFor(Campaign.rulesFor(n, difficulty: d)),
            )),
            _board(ours),
            reason: 'tutorial level $n generates a different board on ${d.label}',
          );
        }
      }
    });

    test('Normal tightens from stage 4 — a little, and on schedule', () {
      // The adventure shift: modest, and exactly where the user asked for it
      // (after the tutorial trio). The unnamed default curve is Normal's, so
      // these assertions compare numbers against themselves through the mode.
      for (var n = Campaign.tutorialBand + 1; n <= Campaign.length; n++) {
        final d = Difficulty.normal;
        expect(d.budgetRelief(n), -0.04, reason: 'budget shift at $n');
        expect(d.hungerRelief(n), -0.04, reason: 'clock shift at $n');
        expect(d.regrowRelief(n), -0.3, reason: 'regrowth shift at $n');
        expect(d.guardSpeedDelta(n), 0.05, reason: 'pace shift at $n');
        expect(d.guardDelta(n), 0, reason: 'Normal never adds lights');
        expect(d.revealMultiplierFor(n), 0.92, reason: 'fog shift at $n');
      }
      for (var n = 1; n <= Campaign.tutorialBand; n++) {
        final d = Difficulty.normal;
        expect(d.budgetRelief(n), 0);
        expect(d.hungerRelief(n), 0);
        expect(d.regrowRelief(n), 0);
        expect(d.guardSpeedDelta(n), 0);
        expect(d.guardDelta(n), 0);
        expect(d.revealMultiplierFor(n), 1.0);
      }
    });

    test(
      'past the tutorial, Hard plays a heavier board — rules, not luck',
      () {
        // The two-mode promise now reaches the ground itself. Asserted on the
        // rules rather than the RNG output: a density claim belongs to the
        // campaign, and a seed-by-seed comparison would pin fates we want the
        // seeds free to have.
        for (var n = Campaign.tutorialBand + 1; n <= Campaign.length; n++) {
          final normal = Campaign.rulesFor(n);
          final hard = Campaign.rulesFor(n, difficulty: Difficulty.hard);

          for (final family in [
            ('anchors', normal.anchorDensity, hard.anchorDensity),
            ('brambles', normal.heavyDensity, hard.heavyDensity),
            ('springs', normal.springDensity, hard.springDensity),
            ('cracklines', normal.faultDensity, hard.faultDensity),
            ('mire', normal.mireDensity, hard.mireDensity),
            ('thicket', normal.thicketDensity, hard.thicketDensity),
            ('hardpan', normal.hardpanDensity, hard.hardpanDensity),
            ('thorns', normal.thornDensity, hard.thornDensity),
          ]) {
            expect(
              family.$3,
              greaterThanOrEqualTo(family.$2),
              reason: 'level $n has fewer ${family.$1} on Hard',
            );
          }

          expect(
            hard.treats,
            lessThanOrEqualTo(normal.treats),
            reason: 'level $n hands out more treats on Hard',
          );
          expect(
            hard.powerups,
            lessThanOrEqualTo(normal.powerups),
            reason: 'level $n hands out more powerups on Hard',
          );
          expect(
            hard.treatTaps,
            lessThanOrEqualTo(normal.treatTaps),
            reason: 'level $n pays more taps per treat on Hard',
          );
          // …but never empty-handed: the floors exist, on both modes.
          expect(hard.treats, greaterThanOrEqualTo(1));
          expect(hard.powerups, greaterThanOrEqualTo(1));
          expect(hard.treatTaps, greaterThanOrEqualTo(1));
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'no level is arithmetically impossible, even on Hard',
      () {
        // Hard's floor is par itself: the level demands essentially perfect
        // play and nothing else. That is the boundary of "brutal but fair" —
        // one tap less and the run cannot be completed at all.
        for (var n = 1; n <= Campaign.length; n++) {
          final rules = Campaign.rulesFor(n, difficulty: Difficulty.hard);
          if (!rules.budget) {
            continue;
          }
          final level = LevelGenerator.generate(specFor(rules));
          final budget = (level.par * rules.budgetMultiplier).ceil();
          expect(
            budget,
            greaterThanOrEqualTo(level.par),
            reason:
                'level $n on Hard budget $budget below par ${level.par}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test('Hard is never easier than Normal, on any axis', () {
      for (var n = Campaign.tutorialBand + 1; n <= Campaign.length + 20; n++) {
        final normal = Campaign.rulesFor(n);
        final hard = Campaign.rulesFor(n, difficulty: Difficulty.hard);

        expect(
          hard.budgetMultiplier,
          lessThanOrEqualTo(normal.budgetMultiplier),
          reason: 'level $n: Hard has more taps',
        );
        expect(
          hard.hungerSecondsPerCell,
          lessThanOrEqualTo(normal.hungerSecondsPerCell),
          reason: 'level $n: Hard has more time',
        );
        expect(
          hard.guardSpeed,
          greaterThanOrEqualTo(normal.guardSpeed),
          reason: 'level $n: Hard has slower patrols',
        );
        expect(
          hard.guards,
          greaterThanOrEqualTo(normal.guards),
          reason: 'level $n: Hard has fewer patrols',
        );
        expect(
          hard.regrowDelay,
          lessThanOrEqualTo(normal.regrowDelay),
          reason: 'level $n: Hard regrows slower',
        );
      }
    });

    test('a taught mechanic survives even Hard', () {
      // +2 lights per mechanic, floored at one wherever the mechanic exists —
      // never zero, because a pressure with its answer withheld is not
      // difficulty.
      for (var n = Campaign.guardsFrom; n <= Campaign.length; n++) {
        expect(
          Campaign.rulesFor(n, difficulty: Difficulty.hard).guards,
          greaterThanOrEqualTo(1),
          reason: 'level $n has no patrols at all, even on Hard',
        );
      }
      for (var n = Campaign.sentriesFrom; n <= Campaign.length; n++) {
        expect(
          Campaign.rulesFor(n, difficulty: Difficulty.hard).sentries,
          greaterThanOrEqualTo(1),
          reason: 'level $n has no sentries at all, even on Hard',
        );
      }
      for (var n = Campaign.blinkerFrom; n <= Campaign.length; n++) {
        expect(
          Campaign.rulesFor(n, difficulty: Difficulty.hard).blinkers,
          greaterThanOrEqualTo(1),
          reason: 'level $n has no blinkers at all, even on Hard',
        );
      }
    });
  });
}
