import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';

import 'sim/simulated_player.dart' show specFor;

/// The route the player converges on once the fog has been paid for, priced
/// the way par prices it.
List<HexCoord>? _playedRoute(HexGrid grid) => Pathfinder.cheapestPath(
  grid.start,
  grid.exit,
  grid.isTraversableInPrinciple,
  grid.remainingCost,
);

/// The route the light placer protects, priced the way it prices it: raw tap
/// cost, so a gate reads as one tile rather than a tile plus its switch.
List<HexCoord> _guardedRoute(HexGrid grid) =>
    Pathfinder.cheapestPath(
      grid.start,
      grid.exit,
      grid.isTraversableInPrinciple,
      (c) => grid.cells[c]?.type.hitsRequired ?? (1 << 20),
    ) ??
    grid.truePath;

/// Steps from every cell to [route], routed around walls the way she steers.
Map<HexCoord, int> _distanceFromRoute(HexGrid grid, List<HexCoord> route) {
  final dist = <HexCoord, int>{};
  final queue = Queue<HexCoord>();
  for (final c in route) {
    dist[c] = 0;
    queue.add(c);
  }
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    final next = dist[current]! + 1;
    for (final n in current.neighbours) {
      if (dist.containsKey(n) || !grid.isTraversableInPrinciple(n)) {
        continue;
      }
      dist[n] = next;
      queue.add(n);
    }
  }
  return dist;
}

int _longestRunOn(List<HexCoord> route, Set<HexCoord> held) {
  var run = 0;
  var worst = 0;
  for (final cell in route) {
    if (held.contains(cell)) {
      run++;
      if (run > worst) worst = run;
    } else {
      run = 0;
    }
  }
  return worst;
}

void main() {
  group('Route legibility, stage 52 onward', () {
    test(
      'every lock half stands near the walked route, in both modes',
      () {
        // A gate whose switch is lost in two hundred cells of fog is a wall
        // with homework, not a puzzle — and with no hint on Hard there was
        // nothing pointing at it. Checked one level at a time because each
        // lock board fails in its own place.
        for (var n = Campaign.gateFrom; n <= Campaign.length; n++) {
          for (final difficulty in Difficulty.values) {
            final rules = Campaign.rulesFor(n, difficulty: difficulty);
            final grid = LevelGenerator.generate(specFor(rules)).grid;
            final route = _playedRoute(grid);
            expect(
              route,
              isNotNull,
              reason: 'stage $n on ${difficulty.label} has no route at all',
            );
            final dist = _distanceFromRoute(grid, route!);
            for (final entry in grid.cells.entries) {
              final cell = entry.value;
              final isHalf =
                  cell.type == HexType.switchTile ||
                  (cell.type == HexType.mirror && cell.partner != null);
              if (!isHalf) continue;
              expect(
                dist[entry.key] ?? 1 << 20,
                lessThanOrEqualTo(3),
                reason:
                    'stage $n on ${difficulty.label} strands its '
                    '${cell.type.name} at ${entry.key}',
              );
            }
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'the route is never paved with disguise, in both modes',
      () {
        // Thicket hides what stands behind it, sleepers lie about being
        // plain, scaffolds refuse the taps that walk up to them, and alarms
        // punish following the priced route. One of each along the way is
        // texture; more is a corridor the player cannot read.
        const caps = {
          HexType.thicket: 1,
          HexType.sleeper: 1,
          HexType.scaffold: 2,
          HexType.alarm: 1,
        };
        for (
          var n = Difficulty.lateCampaignReliefFrom;
          n <= Campaign.length;
          n++
        ) {
          for (final difficulty in Difficulty.values) {
            final rules = Campaign.rulesFor(n, difficulty: difficulty);
            final grid = LevelGenerator.generate(specFor(rules)).grid;
            final route = _playedRoute(grid);
            expect(
              route,
              isNotNull,
              reason: 'stage $n on ${difficulty.label} has no route at all',
            );
            final protected = {
              grid.start,
              grid.exit,
              ...grid.start.neighbours,
              ...grid.exit.neighbours,
            };
            for (final entry in caps.entries) {
              final count = route!
                  .where(
                    (c) =>
                        !protected.contains(c) &&
                        grid.cells[c]?.type == entry.key,
                  )
                  .length;
              expect(
                count,
                lessThanOrEqualTo(entry.value),
                reason:
                    'stage $n on ${difficulty.label} paves its route with '
                    '$count ${entry.key.name} tiles',
              );
            }
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'no light holds a stretch of the route, in both modes',
      () {
        // The level-40 rule, extended to every lamp and every late level. A
        // blocking run queues her body; a warding run queues the taps that
        // would open it — and under fog a tap that does nothing reads as no
        // route at all. Read statically off each lamp's whole sweep, which is
        // exactly what placement constrained.
        for (
          var n = Difficulty.lateCampaignReliefFrom;
          n <= Campaign.length;
          n++
        ) {
          for (final difficulty in Difficulty.values) {
            final rules = Campaign.rulesFor(n, difficulty: difficulty);
            final level = LevelGenerator.generate(specFor(rules));
            if (level.guards.isEmpty) continue;
            final route = _guardedRoute(level.grid);
            final held = <HexCoord>{
              for (final guard in level.guards)
                for (final cell in guard.patrol) ...cell.disc(guard.litRadius),
            };
            expect(
              _longestRunOn(route, held),
              lessThanOrEqualTo(2),
              reason:
                  'stage $n on ${difficulty.label} lets its lights hold '
                  '${_longestRunOn(route, held)} route cells in a row',
            );
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test('late Hard keeps its lights authored and its fog readable', () {
      // Hard doubles the working guard — patrols and sentries — and used to
      // double the five younger families too, which put sixteen exotic lamps
      // on the finale. A multiplied lesson is not a harder lesson. And its
      // fog floor lifts from 0.60 to 0.70: still much blinder than Normal's
      // 1.08, but past the point where the route cannot be found at all.
      for (
        var n = Difficulty.lateCampaignReliefFrom;
        n <= Campaign.length;
        n++
      ) {
        final normal = Campaign.rulesFor(n);
        final hard = Campaign.rulesFor(n, difficulty: Difficulty.hard);
        for (final family in [
          ('spinners', normal.spinners, hard.spinners),
          ('blinkers', normal.blinkers, hard.blinkers),
          ('beacons', normal.beacons, hard.beacons),
          ('runners', normal.runners, hard.runners),
          ('wardens', normal.wardens, hard.wardens),
        ]) {
          expect(
            family.$3,
            family.$2,
            reason: 'stage $n multiplies its ${family.$1} on Hard',
          );
        }
        expect(
          hard.guards,
          greaterThanOrEqualTo(normal.guards),
          reason: 'stage $n runs fewer patrols on Hard',
        );
        expect(
          hard.sentries,
          greaterThanOrEqualTo(normal.sentries),
          reason: 'stage $n runs fewer sentries on Hard',
        );
        expect(
          Difficulty.hard.revealMultiplierFor(n),
          greaterThanOrEqualTo(0.70),
          reason: 'stage $n blinds Hard past finding the route',
        );
      }
      expect(Difficulty.hard.revealMultiplierFor(100), closeTo(0.70, 1e-9));
      // The early campaign keeps its shipped tuning: this relief starts where
      // the legibility problem does.
      expect(Difficulty.hard.revealMultiplierFor(20), 0.6);
    });

    test('late walls fund the new families instead of burying them', () {
      // Every rebuilt family draws from the same remaining-plain pool the
      // wall curves were priced against, so the Vigil anchor curve read far
      // denser than its numbers. Both modes hand back a constant slice from
      // stage 52 — constant so the challenge envelope and band ordering the
      // pacing suite pins are untouched — and Hard's wall stacking caps at
      // 1.15 instead of 1.3.
      final normal = Campaign.rulesFor(100);
      expect(normal.anchorDensity, inInclusiveRange(0.35, 0.42));
      expect(normal.heavyDensity, inInclusiveRange(0.25, 0.35));
      final hard = Campaign.rulesFor(100, difficulty: Difficulty.hard);
      expect(hard.anchorDensity, closeTo(normal.anchorDensity * 1.15, 1e-9));
      expect(hard.heavyDensity, closeTo(normal.heavyDensity * 1.15, 1e-9));
      for (
        var n = Difficulty.lateCampaignReliefFrom;
        n <= Campaign.length;
        n++
      ) {
        final nRules = Campaign.rulesFor(n);
        final hRules = Campaign.rulesFor(n, difficulty: Difficulty.hard);
        expect(
          hRules.anchorDensity,
          greaterThanOrEqualTo(nRules.anchorDensity),
          reason: 'stage $n runs fewer walls on Hard',
        );
        expect(
          hRules.heavyDensity,
          greaterThanOrEqualTo(nRules.heavyDensity),
          reason: 'stage $n runs lighter ground on Hard',
        );
      }
      // Before the relief, the curves are exactly what they were.
      expect(Campaign.rulesFor(51).anchorDensity, greaterThan(0.25));
      expect(Campaign.rulesFor(40).anchorDensity, closeTo(0.30, 1e-9));
    });

    test('stage 83 answers the sight tool with a supply run', () {
      // OWL EYES arrives on a board already carrying two lockbar gates, so
      // the level asks the player to *find* things; extra prizes give the
      // new sight a second thing to spend itself on. It also holds the
      // gauntlet count at half the campaign after 77's swap.
      final rules = Campaign.rulesFor(83);
      expect(rules.pace, LevelPace.combination);
      expect(rules.identity.signature, LevelSignature.supplyRun);
      expect(rules.gatePairs, 0);
      // Four base plus the supply run's extra, possibly one more if the
      // drawn silhouette runs narrow.
      expect(rules.treats, greaterThanOrEqualTo(5));
    });

    test('stage 77 no longer introduces the retired gate', () {
      final rules = Campaign.rulesFor(77);
      expect(rules.introduces, isNull);
      expect(rules.gatePairs, 0);
      expect(rules.identity.signature, LevelSignature.gauntlet);
    });
  });
}
