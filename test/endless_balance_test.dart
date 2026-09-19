import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';

import 'sim/simulated_player.dart' show specFor;

LevelRules _depth(int depth, Difficulty difficulty) =>
    Campaign.rulesFor(Campaign.length + depth, difficulty: difficulty);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh run does not drop the late-campaign safety margins', () {
    for (final difficulty in Difficulty.values) {
      final finale = Campaign.rulesFor(Campaign.length, difficulty: difficulty);
      final opening = _depth(1, difficulty);
      final context = difficulty.label;
      expect(
        opening.budgetMultiplier,
        greaterThanOrEqualTo(finale.budgetMultiplier),
        reason: context,
      );
      expect(
        opening.hungerSecondsPerCell,
        greaterThanOrEqualTo(finale.hungerSecondsPerCell),
        reason: context,
      );
      expect(
        opening.regrowDelay,
        greaterThanOrEqualTo(finale.regrowDelay),
        reason: context,
      );
      expect(
        opening.treatSeconds,
        greaterThanOrEqualTo(finale.treatSeconds),
        reason: context,
      );
      expect(
        opening.treatTaps,
        greaterThanOrEqualTo(finale.treatTaps),
        reason: context,
      );
      expect(opening.guards, lessThanOrEqualTo(finale.guards), reason: context);
      expect(
        opening.sentries,
        lessThanOrEqualTo(finale.sentries),
        reason: context,
      );
      expect(
        opening.anchorDensity,
        lessThanOrEqualTo(finale.anchorDensity),
        reason: context,
      );
      expect(
        opening.heavyDensity,
        lessThanOrEqualTo(finale.heavyDensity),
        reason: context,
      );
    }
  });

  test('the first ten depths retain most of their opening breathing room', () {
    for (final difficulty in Difficulty.values) {
      final opening = _depth(1, difficulty);
      final tenth = _depth(10, difficulty);
      final limit = _depth(1000000, difficulty);
      for (final (start, later, floor) in [
        (
          opening.budgetMultiplier,
          tenth.budgetMultiplier,
          limit.budgetMultiplier,
        ),
        (
          opening.hungerSecondsPerCell,
          tenth.hungerSecondsPerCell,
          limit.hungerSecondsPerCell,
        ),
        (opening.regrowDelay, tenth.regrowDelay, limit.regrowDelay),
      ]) {
        expect(start, greaterThan(floor), reason: difficulty.label);
        expect(later, lessThan(start), reason: 'pressure must still build');
        expect(
          (later - floor) / (start - floor),
          greaterThan(0.8),
          reason: 'the opening should not disappear in a few clears',
        );
      }
    }
  });

  test('both curves tighten gradually and keep practical deep-run limits', () {
    for (final difficulty in Difficulty.values) {
      final hard = difficulty == Difficulty.hard;
      var previous = _depth(1, difficulty);
      for (final depth in [for (var n = 1; n <= 200; n++) n, 1000, 1000000]) {
        final rules = _depth(depth, difficulty);
        final context = '${difficulty.label} D$depth';
        expect(rules.pace, LevelPace.endless, reason: context);
        expect(
          rules.regrowth && rules.fog && rules.budget && rules.hunger,
          isTrue,
          reason: context,
        );
        expect(
          rules.budgetMultiplier,
          inInclusiveRange(hard ? 1.10 : 1.22, hard ? 1.22 : 1.38),
          reason: context,
        );
        expect(
          rules.hungerSecondsPerCell,
          inInclusiveRange(hard ? 1.10 : 1.25, hard ? 1.30 : 1.50),
          reason: context,
        );
        expect(
          rules.regrowDelay,
          inInclusiveRange(hard ? 4.4 : 5.8, hard ? 5.6 : 7.0),
          reason: context,
        );
        expect(rules.treatSeconds, inInclusiveRange(2.8, 3.5), reason: context);
        expect(
          rules.anchorDensity,
          lessThanOrEqualTo(0.40 * (hard ? 1.15 : 1)),
          reason: context,
        );
        expect(
          rules.heavyDensity,
          lessThanOrEqualTo(0.30 * (hard ? 1.15 : 1)),
          reason: context,
        );
        expect(rules.rows, inInclusiveRange(27, 29), reason: context);
        expect(
          rules.offeredPowerups,
          Campaign.poolFor(rules.level),
          reason: context,
        );

        for (final (current, before) in [
          (rules.budgetMultiplier, previous.budgetMultiplier),
          (rules.hungerSecondsPerCell, previous.hungerSecondsPerCell),
          (rules.regrowDelay, previous.regrowDelay),
          (rules.treatSeconds, previous.treatSeconds),
        ]) {
          expect(current, lessThanOrEqualTo(before + 1e-9), reason: context);
        }
        for (final (current, before) in [
          (rules.anchorDensity, previous.anchorDensity),
          (rules.heavyDensity, previous.heavyDensity),
          (rules.faultDensity, previous.faultDensity),
          (rules.guardSpeed, previous.guardSpeed),
        ]) {
          expect(current, greaterThanOrEqualTo(before - 1e-9), reason: context);
        }
        previous = rules;
      }
    }
  });

  test(
    'lights arrive one at a time, without reverting to Hard overcrowding',
    () {
      for (final difficulty in Difficulty.values) {
        final extra = difficulty == Difficulty.hard ? 1 : 0;
        for (final depth in [1, 12, 15, 16, 24, 31, 32, 1000]) {
          final rules = _depth(depth, difficulty);
          expect(rules.guards, (depth < 16 ? 2 : 3) + extra);
          expect(rules.sentries, (depth < 32 ? 1 : 2) + extra);
          expect([
            rules.beacons,
            rules.spinners,
            rules.blinkers,
            rules.runners,
            rules.wardens,
          ], everyElement(1));
        }
      }
    },
  );

  test('Hard stays harder without losing its opening ramp', () {
    for (final depth in [1, 10, 16, 32, 100, 1000]) {
      final normal = _depth(depth, Difficulty.normal);
      final hard = _depth(depth, Difficulty.hard);
      expect(hard.seed, normal.seed);
      expect(hard.anchorDensity, greaterThan(normal.anchorDensity));
      expect(hard.heavyDensity, greaterThan(normal.heavyDensity));
      expect(hard.guards, greaterThan(normal.guards));
      expect(hard.sentries, greaterThan(normal.sentries));
      expect(hard.guardSpeed, greaterThan(normal.guardSpeed));
      expect(hard.budgetMultiplier, lessThan(normal.budgetMultiplier));
      expect(hard.hungerSecondsPerCell, lessThan(normal.hungerSecondsPerCell));
      expect(hard.regrowDelay, lessThan(normal.regrowDelay));
      expect(hard.treats, lessThan(normal.treats));
      expect(hard.powerups, lessThan(normal.powerups));
    }
  });

  test(
    'sampled boards retain a route, spare taps and a viable walking clock',
    () {
      for (final difficulty in Difficulty.values) {
        for (final depth in [
          for (var n = 1; n <= 12; n++) n,
          16,
          24,
          32,
          60,
          200,
          2000,
        ]) {
          final rules = _depth(depth, difficulty);
          final generated = LevelGenerator.generate(specFor(rules));
          final grid = generated.grid;
          final route = Pathfinder.cheapestPath(
            grid.start,
            grid.exit,
            grid.isTraversableInPrinciple,
            grid.remainingCost,
          );
          final context = '${difficulty.label} D$depth';
          expect(route, isNotNull, reason: context);
          expect(generated.par, greaterThan(0), reason: context);
          expect(
            (generated.par * rules.budgetMultiplier).ceil() - generated.par,
            greaterThanOrEqualTo(2),
            reason: '$context needs discovery taps',
          );
          // A structural lower bound, not a claim about human completion rates.
          expect(
            generated.par * rules.hungerSecondsPerCell,
            greaterThan((route!.length - 1) / TuningConfig().driftMax),
            reason: '$context must cover the fastest possible walk',
          );
        }
      }
    },
  );

  test('the live game uses the new margins and resets them for a new run', () {
    for (final difficulty in Difficulty.values) {
      final game = HexcapeGame(tuning: TuningConfig()..difficulty = difficulty)
        ..onGameResize(Vector2(390, 844));
      for (final depth in [1, 16, 32, 200, 1]) {
        game.startLevel(level: Campaign.length + depth);
        final rules = _depth(depth, difficulty);
        expect(game.tuning.regrowDelay, rules.regrowDelay);
        expect(game.tuning.treatSeconds, rules.treatSeconds);
        expect(game.tuning.treatTaps, rules.treatTaps.toDouble());
        expect(game.tapBudget, (game.par * rules.budgetMultiplier).ceil());
        expect(
          game.hunger.capacity,
          closeTo(game.par * rules.hungerSecondsPerCell, 1e-9),
        );
        expect(game.hunger.remaining, game.hunger.capacity);
      }
    }
  });
}
