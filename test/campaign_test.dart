import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';

LevelSpec _specFor(LevelRules r) => LevelSpec(
  seed: r.seed,
  columns: r.columns,
  rows: r.rows,
  anchorDensity: r.anchorDensity,
  heavyDensity: r.heavyDensity,
  springDensity: r.springDensity,
  guards: r.guards,
  guardSpeed: r.guardSpeed,
  treats: r.treats,
  powerups: r.powerups,
  treatSeconds: r.treatSeconds,
  treatTaps: r.treatTaps,
  offeredPowerups: r.offeredPowerups,
  powerupRotation: r.powerupRotation,
  shape: r.shape,
);

void main() {
  group('Campaign seeds', () {
    test('a level always has the same seed', () {
      // If this ever drifts, level 37 quietly becomes a different board in a
      // later build and every saved best score becomes a lie about a level that
      // no longer exists. These are literal expected values on purpose: a test
      // that recomputes the mixer would happily agree with a broken mixer.
      expect(Campaign.seedFor(1), Campaign.seedFor(1));
      expect(Campaign.rulesFor(37).seed, Campaign.seedFor(37));

      final first = [for (var i = 1; i <= 60; i++) Campaign.seedFor(i)];
      final second = [for (var i = 1; i <= 60; i++) Campaign.seedFor(i)];
      expect(first, second);
    });

    test('every level gets its own seed', () {
      final seeds = {for (var i = 1; i <= 200; i++) Campaign.seedFor(i)};
      expect(seeds.length, 200, reason: 'two levels share a board');
    });

    test('seeds are always positive and in range', () {
      for (var i = 1; i <= 200; i++) {
        final seed = Campaign.seedFor(i);
        expect(seed, greaterThanOrEqualTo(0));
        expect(seed, lessThan(1 << 31));
      }
    });
  });

  group('The teaching ladder', () {
    test('level 1 is the game in one sentence and nothing else', () {
      final one = Campaign.rulesFor(1);
      expect(one.regrowth, isFalse);
      expect(one.fog, isFalse);
      expect(one.budget, isFalse);
      expect(one.hunger, isFalse);
      expect(one.anchorDensity, 0);
      expect(one.heavyDensity, 0);
      expect(one.treats, 0);
      expect(one.powerups, 0);
      expect(one.teaches, isNotNull);
    });

    test('each mechanic switches on once and never off again', () {
      // A mechanic that vanished after being taught would read as the game
      // forgetting its own rules.
      var regrowth = false;
      var fog = false;
      var budget = false;
      var hunger = false;
      for (var level = 1; level <= 80; level++) {
        final r = Campaign.rulesFor(level);
        if (regrowth) {
          expect(r.regrowth, isTrue, reason: 'regrowth vanished at $level');
        }
        if (fog) {
          expect(r.fog, isTrue, reason: 'fog vanished at $level');
        }
        if (budget) {
          expect(r.budget, isTrue, reason: 'budget vanished at $level');
        }
        if (hunger) {
          expect(r.hunger, isTrue, reason: 'hunger vanished at $level');
        }
        regrowth |= r.regrowth;
        fog |= r.fog;
        budget |= r.budget;
        hunger |= r.hunger;
      }
      expect(regrowth && fog && budget && hunger, isTrue);
    });

    test('treats never appear before there is a budget to refill', () {
      // A treat pays back taps. On a level with no budget it does nothing at
      // all, and a pickup that visibly does nothing teaches players to ignore
      // pickups for the rest of the game.
      for (var level = 1; level <= 80; level++) {
        final r = Campaign.rulesFor(level);
        if (r.treats > 0) {
          expect(
            r.budget || r.hunger,
            isTrue,
            reason: 'level $level offers treats that can do nothing',
          );
        }
      }
    });

    test('challenge peaks keep climbing while the campaign breathes', () {
      var anchors = -1.0;
      var heavy = -1.0;
      var budget = 99.0;
      var breathers = 0;
      for (
        var level = Campaign.tutorialBand + 1;
        level <= Campaign.length;
        level++
      ) {
        final r = Campaign.rulesFor(level);
        if (r.pace == LevelPace.breather) {
          breathers++;
          final previous = Campaign.rulesFor(level - 1);
          expect(previous.pace, LevelPace.challenge, reason: 'level $level');
          expect(r.budgetMultiplier, greaterThan(previous.budgetMultiplier));
          expect(
            r.hungerSecondsPerCell,
            greaterThan(previous.hungerSecondsPerCell),
          );
          expect(r.regrowDelay, greaterThan(previous.regrowDelay));
        }
        if (r.pace != LevelPace.challenge) {
          continue;
        }
        expect(
          r.anchorDensity,
          greaterThanOrEqualTo(anchors - 1e-9),
          reason: 'challenge $level eased its walls',
        );
        expect(
          r.heavyDensity,
          greaterThanOrEqualTo(heavy - 1e-9),
          reason: 'challenge $level eased its heavy tiles',
        );
        expect(
          r.budgetMultiplier,
          lessThanOrEqualTo(budget + 1e-9),
          reason: 'challenge $level loosened its budget',
        );
        anchors = r.anchorDensity;
        heavy = r.heavyDensity;
        budget = r.budgetMultiplier;
      }
      expect(breathers, greaterThanOrEqualTo(10));
    });

    test('endless keeps climbing but never past its floors', () {
      for (final level in [61, 80, 150, 400, 2000]) {
        final r = Campaign.rulesFor(level);
        expect(r.isEndless, isTrue);
        // Without floors an endless ramp eventually reaches a point no play can
        // survive, which is a wall with a number on it rather than difficulty.
        // These sit lower than the first cut of the curve, which could be
        // finished comfortably — but they are still floors.
        expect(r.budgetMultiplier, greaterThanOrEqualTo(1.03));
        expect(r.hungerSecondsPerCell, greaterThanOrEqualTo(0.78));
        expect(r.anchorDensity, lessThanOrEqualTo(0.42));
        expect(r.heavyDensity, lessThanOrEqualTo(0.34));
      }
    });
  });

  group('Every level is playable', () {
    test('all 60 generate a solvable board', () {
      for (var level = 1; level <= Campaign.length; level++) {
        final rules = Campaign.rulesFor(level);
        final generated = LevelGenerator.generate(_specFor(rules));
        final route = Pathfinder.cheapestCost(
          generated.grid.start,
          generated.grid.exit,
          generated.grid.isTraversableInPrinciple,
          (c) => generated.grid.cells[c]!.type.hitsRequired,
        );
        expect(route, isNotNull, reason: 'level $level has no route');
        expect(generated.par, greaterThan(0), reason: 'level $level');
        expect(
          generated.grid.length,
          greaterThan(30),
          reason: 'level $level is too small to play',
        );
      }
    });

    test('sampled endless levels are solvable too', () {
      for (final level in [61, 75, 120, 300]) {
        final generated = LevelGenerator.generate(
          _specFor(Campaign.rulesFor(level)),
        );
        expect(
          Pathfinder.reachable(
            generated.grid.start,
            generated.grid.exit,
            generated.grid.isTraversableInPrinciple,
          ),
          isTrue,
          reason: 'endless level $level has no route',
        );
      }
    });

    test('boards grow rather than shrink as the campaign goes on', () {
      var cells = 0;
      for (final level in [1, 6, 12, 24, 40, 60]) {
        final generated = LevelGenerator.generate(
          _specFor(Campaign.rulesFor(level)),
        );
        expect(
          generated.grid.length,
          greaterThanOrEqualTo(cells),
          reason: 'level $level is smaller than the one before it',
        );
        cells = generated.grid.length;
      }
    });

    test('the early levels really are short', () {
      // The argument for guided levels rather than more of them is that each is
      // over quickly. If par on level 1 matched par further in, the tutorial
      // would just be full levels with bits switched off.
      final first = LevelGenerator.generate(_specFor(Campaign.rulesFor(1)));
      final last = LevelGenerator.generate(_specFor(Campaign.rulesFor(12)));
      expect(first.par, lessThan(last.par * 0.7));
    });
  });
}
