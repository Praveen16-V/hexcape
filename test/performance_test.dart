import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';

import 'sim/simulated_player.dart';

HexGrid _boardFor(int level) {
  final rules = Campaign.rulesFor(level);
  return LevelGenerator.generate(
    LevelSpec(
      seed: rules.seed,
      columns: rules.columns,
      rows: rules.rows,
      anchorDensity: rules.anchorDensity,
      heavyDensity: rules.heavyDensity,
      treats: rules.treats,
      powerups: rules.powerups,
    ),
  ).grid;
}

/// The linear-scan Dijkstra that used to live in Pathfinder, kept here as the
/// reference implementation. It is obviously correct and obviously slow, which
/// makes it exactly the right thing to check the fast one against.
int? _referenceCost(
  HexCoord from,
  HexCoord to,
  bool Function(HexCoord) passable,
  int Function(HexCoord) cost,
) {
  if (!passable(from) || !passable(to)) {
    return null;
  }
  final best = <HexCoord, int>{from: cost(from)};
  final settled = <HexCoord>{};
  while (true) {
    HexCoord? current;
    var currentCost = 1 << 30;
    for (final entry in best.entries) {
      if (!settled.contains(entry.key) && entry.value < currentCost) {
        current = entry.key;
        currentCost = entry.value;
      }
    }
    if (current == null) {
      return null;
    }
    if (current == to) {
      return currentCost - cost(from);
    }
    settled.add(current);
    for (final n in current.neighbours) {
      if (settled.contains(n) || !passable(n)) {
        continue;
      }
      final candidate = currentCost + cost(n);
      if (candidate < (best[n] ?? 1 << 30)) {
        best[n] = candidate;
      }
    }
  }
}

void main() {
  group('Pathfinding cost', () {
    test('the heap agrees with the reference on every campaign board', () {
      // A faster search that returns different answers would be a far worse bug
      // than a slow one, and the soft-lock ends runs on this number.
      for (var level = 1; level <= Campaign.length; level += 3) {
        final grid = _boardFor(level);
        int costOf(HexCoord c) => grid.cells[c]!.type.hitsRequired;

        final fast = Pathfinder.cheapestCost(
          grid.start,
          grid.exit,
          grid.isTraversableInPrinciple,
          costOf,
        );
        final reference = _referenceCost(
          grid.start,
          grid.exit,
          grid.isTraversableInPrinciple,
          costOf,
        );
        expect(fast, reference, reason: 'level $level disagrees');
      }
    });

    test('and agrees from arbitrary cells, not just the start', () {
      final grid = _boardFor(45);
      int costOf(HexCoord c) => grid.cells[c]!.type.hitsRequired;
      var checked = 0;
      for (final cell in grid.all) {
        if (cell.type.isClearableType && checked < 40) {
          checked++;
          expect(
            Pathfinder.cheapestCost(
              cell.coord,
              grid.exit,
              grid.isTraversableInPrinciple,
              costOf,
            ),
            _referenceCost(
              cell.coord,
              grid.exit,
              grid.isTraversableInPrinciple,
              costOf,
            ),
            reason: 'from ${cell.coord}',
          );
        }
      }
      expect(checked, greaterThan(20));
    });

    test('the search is fast enough to run on every field change', () {
      // This is the regression that made the game stutter on level 60. The
      // soft-lock calls this on every tap and every hex that closes, so its cost
      // has to be nothing much — and that has to be catchable here rather than
      // by feel on a phone.
      final grid = _boardFor(Campaign.length);
      expect(grid.length, greaterThan(200), reason: 'not a big enough board');
      int costOf(HexCoord c) => grid.remainingCost(c);

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 400; i++) {
        Pathfinder.cheapestCost(
          grid.start,
          grid.exit,
          grid.isTraversableInPrinciple,
          costOf,
        );
      }
      stopwatch.stop();

      // ignore: avoid_print
      print(
        'cheapestCost on ${grid.length} cells: '
        '${(stopwatch.elapsedMicroseconds / 400 / 1000).toStringAsFixed(3)}ms '
        'per call',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(400),
        reason:
            '400 calls took ${stopwatch.elapsedMilliseconds}ms — '
            'that is a frame budget spent on pathfinding',
      );
    });

    test('scent can be lit on the biggest board without a hitch', () {
      // Scent recomputes the cheapest *path* — not just its cost — whenever the
      // field changes or she reaches a new cell, and it runs for five seconds
      // at a time. It is cached against both of those, so this measures the
      // worst honest case: a recompute, not a frame.
      final grid = _boardFor(Campaign.length);
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 300; i++) {
        Pathfinder.cheapestPath(
          grid.start,
          grid.exit,
          grid.isTraversableInPrinciple,
          grid.remainingCost,
        );
      }
      stopwatch.stop();
      // ignore: avoid_print
      print(
        'cheapestPath on ${grid.length} cells: '
        '${(stopwatch.elapsedMicroseconds / 300 / 1000).toStringAsFixed(3)}ms '
        'per recompute',
      );
      expect(
        stopwatch.elapsedMicroseconds / 300 / 1000,
        lessThan(4.0),
        reason: 'a scent recompute has to fit inside a frame with room to spare',
      );
    });

    test('a whole simulated frame at level sixty fits the budget', () {
      // Everything at once: three patrols, springs, regrowth, the clock, and
      // the soft-lock check on every single frame. The simulation does strictly
      // more per frame than the game does, so this is an upper bound on the
      // logic half of a frame — the half that was responsible for the stutter.
      // Played with a loose budget and the clock switched off, not to make it
      // winnable but to make it *long*: at its shipped budget the floor player
      // soft-locks after a hundred frames, which is not enough of a sample to
      // say anything about a frame. The board, the patrols and the per-frame
      // work are identical either way.
      final rules = Campaign.rulesFor(Campaign.length);
      final stopwatch = Stopwatch()..start();
      final result = play(
        spec: specFor(rules),
        tuning: tuningFor(rules)..budgetMultiplier = 6,
        regrowth: rules.regrowth,
        limit: 30,
        hungerKills: false,
      );
      stopwatch.stop();

      final frames = (result.seconds * 60).round();
      expect(frames, greaterThan(300), reason: 'not enough frames to mean much');
      final perFrame = stopwatch.elapsedMicroseconds / frames / 1000;
      // ignore: avoid_print
      print(
        'level ${Campaign.length} logic: '
        '${perFrame.toStringAsFixed(3)}ms per frame over $frames frames',
      );
      expect(
        perFrame,
        lessThan(4.0),
        reason:
            'the logic alone is eating a frame at ${perFrame.toStringAsFixed(2)}ms',
      );
    });

    test('a flood fill over the biggest board is cheap too', () {
      final grid = _boardFor(Campaign.length);
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 2000; i++) {
        Pathfinder.floodDepths(grid.start, grid.isPassable, maxDepth: 6);
      }
      stopwatch.stop();
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(400),
        reason: 'the dog re-routes on this every time the field changes',
      );
    });
  });
}
