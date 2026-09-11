import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';

import 'sim/simulated_player.dart' show specFor, tuningFor;

/// Fairness measured without a player model.
///
/// Every number below is a property of the board and the rules, so none of it
/// depends on how well a simulated player happens to play — which is exactly
/// the problem with asking a bot whether a level is fair. Two bounds matter:
///
///  * **Taps.** `budget - par` is the campaign's own stated fairness rule, and
///    par is computed with full knowledge of a board the fog hides.
///  * **Clock.** She drifts between `driftMin` and `driftMax` hex widths per
///    second — slow in a one-hex channel, fast in open ground — so the route
///    length and those two speeds bracket the time any run can take, whatever
///    the player does. `steps / driftMax` is a floor nobody beats.
void main() {
  test(
    'structural fairness, every level, both modes',
    () {
      final rows = <String>[];
      final flags = <String>[];

      for (var n = 1; n <= Campaign.length; n++) {
        for (final d in Difficulty.values) {
          final rules = Campaign.rulesFor(n, difficulty: d);
          final generated = LevelGenerator.generate(specFor(rules));
          final tuning = tuningFor(rules);
          final grid = generated.grid;
          final par = generated.par;

          final route = Pathfinder.cheapestPath(
            grid.start,
            grid.exit,
            grid.isTraversableInPrinciple,
            (coord) => grid.at(coord)!.type.hitsRequired,
          );
          if (route == null) {
            flags.add('BROKEN L$n ${d.label}: no route to the bone');
            continue;
          }
          final steps = route.length - 1;

          final budget = rules.budget
              ? (par * rules.budgetMultiplier).ceil()
              : -1;
          final spare = budget < 0 ? 999 : budget - par;
          final treatTaps = rules.treats * rules.treatTaps;
          final clock = rules.hunger ? par * rules.hungerSecondsPerCell : -1.0;

          // The two drift speeds bracket every possible run.
          final fastest = steps / tuning.driftMax;
          final slowest = steps / tuning.driftMin;
          // How much of a one-hex-channel run the clock pays for. At or above
          // 100% she can crawl the whole way; below it, part of the route has to
          // be carved wide enough for her to pick up speed — which costs taps the
          // budget then has to cover.
          final channel = clock <= 0 ? 99.0 : clock / slowest;

          rows.add(
            '$n\t${d.label}\t$par\t$budget\t$spare\t$treatTaps\t$steps\t'
            '${clock < 0 ? "-" : clock.toStringAsFixed(1)}\t'
            '${fastest.toStringAsFixed(1)}\t${slowest.toStringAsFixed(1)}\t'
            '${(channel * 100).toStringAsFixed(0)}%',
          );

          if (clock > 0 && clock < fastest) {
            flags.add(
              'IMPOSSIBLE L$n ${d.label}: clock ${clock.toStringAsFixed(1)}s is '
              'under the ${fastest.toStringAsFixed(1)}s it takes to walk $steps '
              'cells at full drift speed',
            );
          }
          if (budget > 0 && spare < 2) {
            flags.add(
              'TAPS L$n ${d.label}: $spare spare over par $par '
              '(+$treatTaps from treats, if she detours for them)',
            );
          }
          if (clock > 0 && channel < 0.45) {
            flags.add(
              'CLOCK L$n ${d.label}: the clock pays for only '
              '${(channel * 100).toStringAsFixed(0)}% of a narrow-corridor run '
              '($steps cells in ${clock.toStringAsFixed(1)}s), so she must be '
              'given a wide lane — on $spare spare taps',
            );
          }
        }
      }

      // ignore: avoid_print
      print(
        'lvl\tmode\tpar\tbud\tspare\ttreat\tsteps\tclock\tfast\tslow\tchan%',
      );
      for (final r in rows) {
        // ignore: avoid_print
        print(r);
      }
      // ignore: avoid_print
      print('\n=== ${flags.length} FLAGS ===');
      for (final f in flags) {
        // ignore: avoid_print
        print(f);
      }

      // The flags that are invariants rather than observations. Hard's thin
      // tap margin is deliberate — its budget floor is par itself — so the
      // TAPS flags above are a readout for Hard, not a failure. These are not
      // negotiable: a level with no route, or a clock under the time it
      // physically takes to walk the route, is broken at every skill level.
      expect(
        flags.where((f) => f.startsWith('BROKEN')),
        isEmpty,
        reason: 'a level has no way to the bone',
      );
      expect(
        flags.where((f) => f.startsWith('IMPOSSIBLE')),
        isEmpty,
        reason: 'a level cannot be walked inside its own clock',
      );
      // Normal is the reference curve every record is measured against, and
      // the campaign's stated rule for it is two spare taps at every point.
      expect(
        flags.where((f) => f.startsWith('TAPS') && f.contains('Normal')),
        isEmpty,
        reason: 'Normal fell below two spare taps over par',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
