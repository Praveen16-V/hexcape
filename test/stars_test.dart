import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';

import 'sim/simulated_player.dart';

/// The budget a level actually hands the player, treats included.
///
/// Treats raise the budget mid-run, so the allowance a rating is measured
/// against is not the number the level started with. Every check here uses this
/// rather than the bare multiplier, because it is what the player plays with.
({int par, int budget, int withTreats}) _levelNumbers(int level) {
  final rules = Campaign.rulesFor(level);
  final generated = LevelGenerator.generate(specFor(rules));
  final par = generated.par;
  final budget = rules.budget
      ? (par * rules.budgetMultiplier).ceil()
      : (par * 1.5).ceil();
  return (
    par: par,
    budget: budget,
    withTreats: budget + rules.treats * rules.treatTaps,
  );
}

void main() {
  group('Star ratings', () {
    test('a perfect run is always three stars', () {
      expect(starsFor(taps: 20, par: 20, budget: 30), 3);
      expect(starsFor(taps: 12, par: 20, budget: 30), 3);
      expect(starsFor(taps: 20, par: 20), 3);
    });

    test('all three ratings are reachable on every campaign level', () {
      // The property the old fixed bands violated. Three stars was
      // `taps <= 1.05 x par` while level sixty's budget is `1.06 x par`, so the
      // budget and the cutoff were the same number and every win scored full
      // marks. One star had been unreachable since roughly level thirty-three,
      // because you ran out of taps before you could score that badly.
      for (var level = 1; level <= Campaign.length; level++) {
        final n = _levelNumbers(level);
        final seen = <int>{};
        for (var taps = n.par; taps <= n.withTreats; taps++) {
          seen.add(starsFor(taps: taps, par: n.par, budget: n.budget));
        }
        expect(
          seen,
          {1, 2, 3},
          reason:
              'level $level (par ${n.par}, budget ${n.budget}, '
              'with treats ${n.withTreats}) can only score $seen',
        );
      }
    });

    test('spending a treat can never cost a star', () {
      // A treat raises the budget but never par. Under the old rule the bands
      // were fixed multiples of par, so the extra taps a treat granted pushed
      // the player into a lower band — the reward was wired to punish them.
      for (var level = 1; level <= Campaign.length; level++) {
        final n = _levelNumbers(level);
        for (var taps = n.par; taps <= n.budget; taps++) {
          final without = starsFor(taps: taps, par: n.par, budget: n.budget);
          final with_ = starsFor(taps: taps, par: n.par, budget: n.withTreats);
          expect(
            with_,
            greaterThanOrEqualTo(without),
            reason:
                'level $level: $taps taps scores $without without treats and '
                'only $with_ with them',
          );
        }
      }
    });

    test('the rating falls as taps rise, never the other way', () {
      for (final budget in [24, 32, 48, 90]) {
        var previous = 3;
        for (var taps = 20; taps <= budget + 20; taps++) {
          final stars = starsFor(taps: taps, par: 20, budget: budget);
          expect(
            stars,
            lessThanOrEqualTo(previous),
            reason: 'budget $budget went back up at $taps taps',
          );
          previous = stars;
        }
      }
    });

    test(
      'a level with a tiny allowance still rates rather than dividing by nothing',
      () {
        // Par and budget can land on the same number on a small board once the
        // multiplier is close to one. Without a floor the fraction is a division
        // by zero and every rating becomes NaN-driven nonsense.
        expect(starsFor(taps: 10, par: 10, budget: 10), 3);
        expect(starsFor(taps: 12, par: 10, budget: 10), 1);
        expect(() => starsFor(taps: 11, par: 10, budget: 10), returnsNormally);
      },
    );

    test('an unbudgeted level rates on a nominal allowance', () {
      // The tutorial has no budget. Rating everything three stars there would
      // teach players that the rating means nothing before they meet one that
      // matters.
      expect(starsFor(taps: 20, par: 20), 3);
      expect(starsFor(taps: 30, par: 20), 1);
      expect(
        starsFor(taps: 23, par: 20),
        greaterThan(starsFor(taps: 29, par: 20)),
      );
    });

    test('the bands are ordered and inside the allowance', () {
      expect(threeStarShare, lessThan(twoStarShare));
      expect(twoStarShare, lessThan(1.0));
    });

    test('the displayed mastery targets match the rating function', () {
      for (final numbers in [
        (par: 10, budget: 10),
        (par: 20, budget: 30),
        (par: 27, budget: 32),
        (par: 40, budget: 73),
      ]) {
        final target = starTargetsFor(par: numbers.par, budget: numbers.budget);
        expect(
          starsFor(
            taps: target.three,
            par: numbers.par,
            budget: numbers.budget,
          ),
          3,
        );
        expect(
          starsFor(
            taps: target.three + 1,
            par: numbers.par,
            budget: numbers.budget,
          ),
          lessThan(3),
        );
        expect(
          starsFor(taps: target.two, par: numbers.par, budget: numbers.budget),
          greaterThanOrEqualTo(2),
        );
        expect(
          starsFor(
            taps: target.two + 1,
            par: numbers.par,
            budget: numbers.budget,
          ),
          1,
        );
      }
    });
  });
}
