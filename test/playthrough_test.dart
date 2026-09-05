import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/gen/level_generator.dart';

import 'sim/simulated_player.dart';

void main() {
  group('Full playthrough', () {
    test('the loop completes with regrowth off', () {
      // Zen mode (§12.3). No closing field and taps to spare, so a failure here
      // means the carve-and-drift loop itself is broken rather than mistuned.
      // Not every seed: the model is a greedy local carver and can talk itself
      // into a dead end, which is a limit of the model, not of the game.
      var wins = 0;
      for (var seed = 1; seed <= 10; seed++) {
        if (playSeed(seed: seed, regrowth: false, budgetMultiplier: 6).won) {
          wins++;
        }
      }
      expect(wins, greaterThanOrEqualTo(8), reason: 'only $wins/10 reached it');
    });

    test('the hunger clock is beatable, with real margin', () {
      // The number that decides whether the clock is tense or impossible, and
      // the one thing in this file that must not be guessed.
      //
      // Measured with hunger switched off so it reports how long a run *takes*
      // rather than how far it gets before starving, and with a generous tap
      // budget so the two constraints do not mask each other. The model never
      // detours for a treat either, so this is the cost of the plain route.
      final times = <double>[];
      var capacity = 0.0;
      for (var seed = 0; seed < 25; seed++) {
        final result = playSeed(
          seed: seed,
          regrowth: true,
          budgetMultiplier: 6,
          hungerKills: false,
          pickups: false,
        );
        if (result.won) {
          times.add(result.seconds);
          capacity = result.hungerCapacity;
        }
      }
      times.sort();
      final slowest = times.last;
      final median = times[times.length ~/ 2];

      // ignore: avoid_print
      print(
        'clock: bar ${capacity.toStringAsFixed(1)}s vs run '
        'median ${median.toStringAsFixed(1)}s / slowest '
        '${slowest.toStringAsFixed(1)}s '
        '(margin x${(capacity / slowest).toStringAsFixed(2)})',
      );

      expect(
        capacity,
        greaterThan(slowest * 1.15),
        reason: 'the bar must clear even the slowest ordinary run',
      );
    });

    test('a decisive run clears the clock', () {
      // What this can and cannot prove is worth being straight about.
      //
      // The clock exists to punish deliberation, and this model has none: it
      // never hesitates, never re-reads the board, never detours. Sweeping the
      // hunger rate from 0.9 to 1.7 seconds per cell changes its result not at
      // all, because it always finishes in fourteen to seventeen seconds. So
      // the simulation cannot tell anyone whether the clock *bites* — only a
      // person playing can.
      //
      // What it can establish is the floor: how fast a run can possibly go. The
      // bar is set from that, and the assertion here is only that someone
      // playing decisively is never robbed by it.
      var won = 0;
      var starved = 0;
      for (var seed = 0; seed < 25; seed++) {
        final result = playSeed(
          seed: seed,
          regrowth: true,
          budgetMultiplier: 6,
        );
        if (result.won) {
          won++;
        }
        if (result.reason == 'starved') {
          starved++;
        }
      }
      // ignore: avoid_print
      print('hunger at shipped rate: $won/25 won, $starved starved');
      expect(
        won,
        greaterThanOrEqualTo(20),
        reason: 'decisive play must not be starved out',
      );
    });

    test('the level stays winnable with the field closing in', () {
      // This models a *mediocre* player: greedy, local, no planning beyond the
      // next cell, and blind to hex types until they are close enough to see.
      // Its tap count is an upper bound on what a level costs, not a target.
      //
      // The bar is that the mechanics do not deadlock. Whether the budget is
      // *fun* is a question only the phone can answer.
      var generous = 0;
      for (final mult in [1.5, 2.0, 2.5, 3.0, 6.0]) {
        final reasons = <String, int>{};
        var wins = 0;
        final taps = <double>[];
        for (var seed = 0; seed < 25; seed++) {
          final result = playSeed(
            seed: seed,
            regrowth: true,
            budgetMultiplier: mult,
          );
          reasons[result.reason] = (reasons[result.reason] ?? 0) + 1;
          if (result.won) {
            wins++;
            taps.add(result.taps.toDouble());
          }
        }
        if (mult == 6.0) {
          generous = wins;
        }
        // ignore: avoid_print
        print(
          'budget ${mult}x par -> $wins/25 won, '
          'avg taps ${_avg(taps)}, $reasons',
        );
      }

      expect(
        generous,
        greaterThanOrEqualTo(20),
        reason: 'with taps to spare the loop itself must not deadlock',
      );
    });

    test('a blind greedy player stays within a few times par', () {
      // Not a claim that this model plays well — it does not, and its cost sits
      // around twice par. It is a regression guard: if the number of taps it
      // takes to grind out a level suddenly doubles again, something in the
      // generator or the drift has gone wrong and the budget will be a lie.
      for (var seed = 0; seed < 10; seed++) {
        final level = LevelGenerator.generate(LevelSpec(seed: seed));
        final result = playSeed(
          seed: seed,
          regrowth: true,
          budgetMultiplier: 6,
        );
        if (!result.won) {
          continue;
        }
        expect(
          result.taps,
          lessThanOrEqualTo((level.par * 2.6).ceil()),
          reason: 'seed $seed took ${result.taps} against par ${level.par}',
        );
      }
    });
  });
}

String _avg(Iterable<double> values) {
  if (values.isEmpty) {
    return 'n/a';
  }
  final total = values.reduce((a, b) => a + b);
  return (total / values.length).toStringAsFixed(1);
}
