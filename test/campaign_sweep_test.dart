import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/gen/silhouette.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';

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
      'a challenge peak is not the one beat with no allowance',
      () {
        // What the cliff at forty actually was. A peak used to be the only
        // pace given no relief at all, so it paid the band's full interpolated
        // rate while carrying every hazard the band had introduced along the
        // way -- level forty pays level twenty's budget with four more hazard
        // families and two patrols on the board. The peak is meant to be the
        // hardest level of its band, not the only one with no room for the
        // taps the fog guarantees are wasted.
        //
        // Three spare rather than the global two: a peak is where the patrols
        // are, and a tap spent finding out where the light sweeps is a tap
        // spent on nothing.
        for (var n = Campaign.foundationEnd; n <= Campaign.length; n++) {
          final rules = Campaign.rulesFor(n);
          if (rules.pace != LevelPace.challenge) {
            continue;
          }
          final level = LevelGenerator.generate(specFor(rules));
          final budget = (level.par * rules.budgetMultiplier).ceil();
          expect(
            budget - level.par,
            greaterThanOrEqualTo(3),
            reason:
                'peak $n gives ${budget - level.par} spare taps over par '
                '${level.par}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'post-20 Normal keeps the promised tap room in every band',
      () {
        const targets = [
          (from: 21, to: 40, minimumSpare: 4, minimumRoom: 0.65),
          (from: 41, to: 60, minimumSpare: 3, minimumRoom: 0.55),
          (from: 61, to: 80, minimumSpare: 2, minimumRoom: 0.45),
          (from: 81, to: 100, minimumSpare: 2, minimumRoom: 0.40),
        ];

        for (final target in targets) {
          var par = 0;
          var room = 0;
          for (var n = target.from; n <= target.to; n++) {
            final rules = Campaign.rulesFor(n);
            final level = LevelGenerator.generate(specFor(rules));
            final budget = (level.par * rules.budgetMultiplier).ceil();
            final spare = budget - level.par;
            expect(
              spare,
              greaterThanOrEqualTo(target.minimumSpare),
              reason: 'Normal stage $n has only $spare discovery taps',
            );
            par += level.par;
            room += spare + rules.treats * rules.treatTaps;
          }
          expect(
            room / par,
            greaterThanOrEqualTo(target.minimumRoom),
            reason: 'Normal stages ${target.from}-${target.to}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'every lock has an other half the player can get to',
      () {
        // A closed gate is priced as a way through — two taps, its own and its
        // switch's — and [HexGrid.isTraversableInPrinciple] agrees, so par is
        // free to route straight across one. All of that rests on the switch
        // being somewhere the dog can reach, and nothing used to check it:
        // rivets and hearts go down before the locks do, and the switch was
        // drawn from the plain-ground pool by distance alone, so one could
        // land in a pocket the rivets had already sealed. Its gate is then
        // shut for the run while par keeps costing a route through it.
        //
        // Stage 80 on Hard shipped that way and could not be finished.
        for (var n = Campaign.gateFrom; n <= Campaign.length; n++) {
          for (final difficulty in Difficulty.values) {
            final rules = Campaign.rulesFor(n, difficulty: difficulty);
            final grid = LevelGenerator.generate(specFor(rules)).grid;
            for (final entry in grid.cells.entries) {
              final cell = entry.value;
              final isHalf =
                  cell.type == HexType.switchTile ||
                  (cell.type == HexType.mirror && cell.partner != null);
              if (!isHalf) continue;
              expect(
                Pathfinder.reachable(
                  grid.start,
                  entry.key,
                  grid.isTraversableInPrinciple,
                ),
                isTrue,
                reason:
                    'stage $n on ${difficulty.name} walls off the '
                    '${cell.type.name} at ${entry.key}',
              );
            }
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'par pays for a plan that actually finishes the level',
      () {
        // Par is what both the budget and the clock are sized from, so it has
        // to be the cost of something a player can really do. Straight
        // Dijkstra is not: it prices a lock at two taps for two tiles and
        // cannot see that the second tile stands four to ten cells off the
        // route, because a detour is not a line of tiles.
        //
        // This costs the two plans that exist — round every lock, or by way of
        // one — and checks the budget covers the cheaper. Hard is allowed to
        // spend par almost exactly on a late challenge peak, so the margin
        // asked for here is zero: what is being caught is a budget that cannot
        // buy *any* finish, which is a different thing from a tight one.
        for (var n = Campaign.gateFrom; n <= Campaign.length; n++) {
          for (final difficulty in Difficulty.values) {
            final rules = Campaign.rulesFor(n, difficulty: difficulty);
            final level = LevelGenerator.generate(specFor(rules));
            final grid = level.grid;
            final budget = (level.par * rules.budgetMultiplier).ceil();

            bool lockless(HexCoord c) {
              final cell = grid.at(c);
              if (cell == null || cell.type.blocksTravelInPrinciple) {
                return false;
              }
              return cell.type != HexType.gate && cell.type != HexType.mirror;
            }

            var cheapest = Pathfinder.cheapestCost(
              grid.start,
              grid.exit,
              lockless,
              grid.remainingCost,
            );
            for (final entry in grid.cells.entries) {
              final cell = entry.value;
              if (cell.type != HexType.switchTile &&
                  !(cell.type == HexType.mirror && cell.partner != null)) {
                continue;
              }
              final out = Pathfinder.cheapestCost(
                grid.start,
                entry.key,
                grid.isTraversableInPrinciple,
                grid.remainingCost,
              );
              final on = Pathfinder.cheapestCost(
                entry.key,
                grid.exit,
                grid.isTraversableInPrinciple,
                grid.remainingCost,
              );
              if (out == null || on == null) continue;
              if (cheapest == null || out + on < cheapest) {
                cheapest = out + on;
              }
            }
            expect(cheapest, isNotNull, reason: 'stage $n has no plan at all');
            expect(
              budget,
              greaterThanOrEqualTo(cheapest!),
              reason:
                  'stage $n on ${difficulty.name} budgets $budget against a '
                  'cheapest real plan of $cheapest (par ${level.par})',
            );
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'a narrow silhouette is not quietly tighter than a wide one',
      () {
        // What made level 49 the tightest non-peak of its band. Almost all of
        // a level's allowance is priced as a ratio of par — the budget is a
        // multiplier, the clock is seconds per cell — so it scales with the
        // route. The treats do not: they are a flat count, worth a flat number
        // of taps however long the way through is.
        //
        // That is invisible while the boards are all about the same size, and
        // the key and the crescent are not. They cut the field to roughly 160
        // cells against the campaign's 230 and snake the route out to par 32
        // and 30 against an average of 27, so the same four treats bought them
        // about five points less room to waste than every other outline. Level
        // 49 drew the key on a beat with no pace relief and came out at 48%,
        // below its own band's challenge peak; its two neighbouring key boards
        // hid the same shortfall behind an introduction's relief.
        //
        // Compared as averages rather than level by level, because the outline
        // is only one of the things setting a level's room and a single board
        // may legitimately sit anywhere.
        var narrowRoom = 0.0;
        var narrow = 0;
        var wideRoom = 0.0;
        var wide = 0;
        for (var n = Campaign.foundationEnd + 1; n <= Campaign.length; n++) {
          final rules = Campaign.rulesFor(n);
          final level = LevelGenerator.generate(specFor(rules));
          final budget = (level.par * rules.budgetMultiplier).ceil();
          final room =
              (budget - level.par + rules.treats * rules.treatTaps) / level.par;
          final isNarrow =
              rules.shape == FieldShape.key ||
              rules.shape == FieldShape.crescent;
          if (isNarrow) {
            narrowRoom += room;
            narrow++;
          } else {
            wideRoom += room;
            wide++;
          }
        }
        expect(narrow, greaterThan(0));
        expect(wide, greaterThan(0));
        expect(
          narrowRoom / narrow,
          greaterThan(wideRoom / wide - 0.02),
          reason:
              'narrow boards average '
              '${(narrowRoom / narrow * 100).toStringAsFixed(1)}% room against '
              '${(wideRoom / wide * 100).toStringAsFixed(1)}% on wide ones',
        );
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
        for (var n = Campaign.foundationEnd + 1; n <= Campaign.length; n++) {
          // Level 52 deliberately starts Normal's late-campaign safety margin.
          // Compare peaks inside that revised curve; requiring 53 to stay below
          // the pre-relief level-40 peak would erase the relaxation entirely.
          if (n == Difficulty.lateCampaignReliefFrom || n == 71) {
            budget = double.infinity;
            clock = double.infinity;
          }
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
          // Walls deliberately are not monotonic challenge to challenge — each
          // band restarts its curve lower, and the flat bands climb on slopes
          // and sunken ground instead. The real invariant, that each band's
          // wall peak beats the last, lives in difficulty_pacing_test.
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
          var faults = 0;
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
            // Collapse's entire difficulty gradient is cracked ground — the
            // other four axes are pinned flat there — so a readout without this
            // column would show that band as a plateau when it is not.
            faults += level.grid.all
                .where((c) => c.type.name == 'fault')
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
            'springs ${(springs / levels).toStringAsFixed(1)}  '
            'cracks ${(faults / levels).toStringAsFixed(1)}',
          );
        }
        // ignore: avoid_print
        print('\ncampaign curve, per band (averages per level):');
        for (final row in rows) {
          // ignore: avoid_print
          print('  $row');
        }
        expect(rows, hasLength(6));
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  });
}
