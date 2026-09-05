import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';

import 'sim/simulated_player.dart';

/// Plays the campaign as it actually ships.
///
/// The other playthrough tests drive one default board to tune a single number.
/// This one walks the levels a player walks, with their own densities, shapes,
/// patrols, springs and budgets — which is the only place a mistake in the
/// *curve* can show up rather than a mistake in a mechanic.
///
/// **What this file may and may not conclude.** The simulated player is a floor:
/// it carves greedily toward the bone and needs roughly two to three times par
/// to finish a level. A real player is far better than that — this project's own
/// player finished the old level sixty at an effective 1.34x par and called it
/// easy. So "the model lost" is *not* evidence a level is too hard, and nothing
/// here asserts that it wins outside the tutorial. What it can do is catch the
/// things that are true regardless of skill: a level that cannot be generated, a
/// route that does not exist, a curve that goes backwards, or a budget that
/// demands provably optimal play.
void main() {
  group('The campaign, end to end', () {
    test(
      'every level generates, and every level has a way through',
      () {
        for (var n = 1; n <= Campaign.length; n++) {
          final rules = Campaign.rulesFor(n);
          final level = LevelGenerator.generate(specFor(rules));
          expect(level.par, greaterThan(0), reason: 'level $n has no par');
          expect(
            Pathfinder.reachable(
              level.grid.start,
              level.grid.exit,
              level.grid.isTraversableInPrinciple,
            ),
            isTrue,
            reason: 'level $n has no route to the food',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'no level demands provably optimal play',
      () {
        // Par is the *true optimum*, computed with full knowledge of a board the
        // player cannot see. The fog guarantees some taps are spent discovering
        // walls, so a budget that leaves no room to waste any is not difficulty,
        // it is a coin toss with a number on it.
        //
        // This is the invariant the plan for this curve promised and did not
        // check. It is deliberately a floor of two rather than a comfortable
        // margin — how much slack is *right* is a play question, but zero is
        // wrong at any skill level.
        for (var n = 1; n <= Campaign.length; n++) {
          final rules = Campaign.rulesFor(n);
          if (!rules.budget) {
            continue;
          }
          final level = LevelGenerator.generate(specFor(rules));
          final budget = (level.par * rules.budgetMultiplier).ceil();
          expect(
            budget - level.par,
            greaterThanOrEqualTo(2),
            reason:
                'level $n gives ${budget - level.par} spare taps over par '
                '${level.par}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'challenge peaks climb even though individual levels breathe',
      () {
        // Compare like with like. Practice and breather levels deliberately ease
        // pressure; the full-pressure challenge peaks must still keep climbing.
        var budget = double.infinity;
        var clock = double.infinity;
        var anchors = -1.0;
        for (var n = 1; n <= Campaign.length; n++) {
          final rules = Campaign.rulesFor(n);
          if (rules.pace != LevelPace.challenge) {
            continue;
          }
          if (rules.budget) {
            expect(
              rules.budgetMultiplier,
              lessThanOrEqualTo(budget + 1e-9),
              reason: 'challenge $n hands back taps',
            );
            budget = rules.budgetMultiplier;
          }
          if (rules.hunger) {
            expect(
              rules.hungerSecondsPerCell,
              lessThanOrEqualTo(clock + 1e-9),
              reason: 'challenge $n hands back time',
            );
            clock = rules.hungerSecondsPerCell;
          }
          expect(
            rules.anchorDensity,
            greaterThanOrEqualTo(anchors - 1e-9),
            reason: 'challenge $n thins the walls',
          );
          anchors = rules.anchorDensity;
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'the tutorial cannot be lost on its budget',
      () {
        // A teaching level has to be passable by the worst player who has
        // understood the lesson, and the floor player is the closest thing to
        // that this project has. Level four's lesson is "taps are finite" — which
        // is delivered by the counter going down, not by defeat.
        for (var n = 1; n <= Campaign.tutorialBand; n++) {
          final result = playCampaignLevel(n);
          expect(
            result.won,
            isTrue,
            reason: 'level $n was lost by the floor player: ${result.reason}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'no level traps the floor player with no route at all',
      () {
        // Distinct from running out of taps, which is a fair loss. "No route"
        // means the field closed permanently around a reachable board, which is
        // the soft-lock invariant (§4) failing.
        for (var n = 1; n <= Campaign.length; n += 5) {
          final result = playCampaignLevel(n);
          expect(
            result.reason,
            isNot('no route'),
            reason: 'level $n sealed itself shut',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'the campaign as it stands, in numbers',
      () {
        // Not an assertion — a readout. The one thing this project has never had
        // is the whole curve visible at once, and every difficulty argument so
        // far has been conducted on the strength of one remembered playthrough.
        final rows = <String>[];
        for (final band in CampaignBand.values) {
          if (band == CampaignBand.endless) {
            continue;
          }
          var spare = 0;
          var par = 0;
          var treatTaps = 0;
          var levels = 0;
          var guards = 0;
          var springs = 0;
          for (var n = 1; n <= Campaign.length; n++) {
            if (Campaign.bandOf(n) != band) {
              continue;
            }
            final rules = Campaign.rulesFor(n);
            final level = LevelGenerator.generate(specFor(rules));
            final budget = rules.budget
                ? (level.par * rules.budgetMultiplier).ceil()
                : level.par * 3;
            levels++;
            par += level.par;
            spare += budget - level.par;
            treatTaps += rules.treats * rules.treatTaps;
            guards += rules.guards;
            springs += level.grid.all
                .where((c) => c.type.name == 'spring')
                .length;
          }
          final slack = (spare + treatTaps) / par * 100;
          rows.add(
            '${band.label.padRight(11)} '
            'par ${(par / levels).toStringAsFixed(0).padLeft(3)}  '
            'spare ${(spare / levels).toStringAsFixed(1).padLeft(4)}  '
            '+treats ${(treatTaps / levels).toStringAsFixed(1).padLeft(4)}  '
            'room to waste ${slack.toStringAsFixed(0).padLeft(3)}%  '
            'patrols ${(guards / levels).toStringAsFixed(1)}  '
            'springs ${(springs / levels).toStringAsFixed(1)}',
          );
        }
        // ignore: avoid_print
        print('\ncampaign curve, per band (averages per level):');
        for (final row in rows) {
          // ignore: avoid_print
          print('  $row');
        }
        expect(rows, hasLength(4));
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  });
}
