import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_coord.dart';

import 'sim/simulated_player.dart' show specFor;

/// The cheapest route through a board, which is the answer a player converges
/// on once the fog has been paid for.
List<HexCoord> _route(GeneratedLevel level) =>
    Pathfinder.cheapestPath(
      level.grid.start,
      level.grid.exit,
      level.grid.isTraversableInPrinciple,
      (c) => level.grid.at(c)!.type.hitsRequired,
    ) ??
    const [];

/// How much of [route] any light touches over a long sweep, and the longest
/// unbroken stretch of it that does.
///
/// The run length is the number that matters. One lit cell is a pause; four in
/// a row is a queue, and a queue is paid for in the one currency waiting also
/// spends — the hunger clock.
({double everLit, int worstRun}) _lightOnRoute(
  GeneratedLevel level,
  List<HexCoord> route,
) {
  if (level.guards.isEmpty || route.isEmpty) {
    return (everLit: 0, worstRun: 0);
  }
  final seen = <HexCoord>{};
  // Long enough for every patrol to walk its route end to end and back several
  // times over, whatever its speed.
  for (var i = 0; i < 1600; i++) {
    for (final guard in level.guards) {
      guard.update(1 / 20);
    }
    final lit = <HexCoord>{for (final guard in level.guards) ...guard.lit};
    for (final c in route) {
      if (lit.contains(c)) seen.add(c);
    }
  }
  var run = 0;
  var worst = 0;
  for (final c in route) {
    if (seen.contains(c)) {
      run++;
      if (run > worst) worst = run;
    } else {
      run = 0;
    }
  }
  return (everLit: seen.length / route.length, worstRun: worst);
}

/// What the second way round costs, with the middle half of [route] shut.
int? _otherWayRound(GeneratedLevel level, List<HexCoord> route) {
  final shut = route
      .sublist(route.length ~/ 4, route.length - route.length ~/ 4)
      .toSet();
  return Pathfinder.cheapestCost(
    level.grid.start,
    level.grid.exit,
    (c) => !shut.contains(c) && level.grid.isTraversableInPrinciple(c),
    (c) => level.grid.at(c)!.type.hitsRequired,
  );
}

void main() {
  group('Level 40 redesign', () {
    test('Pressure Edge keeps its size and its seed', () {
      final rules = Campaign.rulesFor(40);
      expect(rules.seed, 101599, reason: 'the authored board drifted');
      expect(rules.identity.title, 'Pressure Edge');
      expect(rules.pace, LevelPace.challenge);
      expect(
        rules.guards,
        2,
        reason: 'the fix was the board, not the removal of its patrols',
      );
      final level = LevelGenerator.generate(specFor(rules));
      expect(level.par, inInclusiveRange(23, 27));
    });

    test('the patrols do not own the only way through, in either mode', () {
      // The defect this board replaces. On the old seed a quarter of the
      // cheapest route was swept on Normal — four lit cells in a row — and
      // nearly half of it on Hard, where there was also no second way round.
      // She refuses lit ground, so that route was a queue rather than a
      // problem, and it was charged to a twenty-six second clock.
      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(40, difficulty: difficulty);
        final level = LevelGenerator.generate(specFor(rules));
        final route = _route(level);
        expect(route, isNotEmpty, reason: '${difficulty.label} has no route');

        final light = _lightOnRoute(level, route);
        expect(
          light.everLit,
          lessThanOrEqualTo(0.05),
          reason:
              '${difficulty.label}: '
              '${(light.everLit * 100).round()}% of the route is swept',
        );
        expect(
          light.worstRun,
          lessThanOrEqualTo(1),
          reason: '${difficulty.label}: ${light.worstRun} lit cells in a row',
        );
      }
    });

    test('it is a fork rather than a corridor, in both modes', () {
      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(40, difficulty: difficulty);
        final level = LevelGenerator.generate(specFor(rules));
        final route = _route(level);
        final other = _otherWayRound(level, route);
        expect(
          other,
          isNotNull,
          reason:
              '${difficulty.label}: shutting the middle of the route leaves '
              'no way to the bone at all',
        );
        expect(
          other,
          lessThanOrEqualTo(level.par + 6),
          reason:
              '${difficulty.label}: the second way round costs $other '
              'against par ${level.par}, which is not a choice',
        );
      }
    });

    test('the clock has prizes on the way, not off it', () {
      // A patrol charges the hunger clock, so a board that carries patrols has
      // to put the things that pay it back within reach of the route. Five is
      // the count the old board had; nothing here is allowed to be worse.
      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(40, difficulty: difficulty);
        final level = LevelGenerator.generate(specFor(rules));
        final route = _route(level);
        final near = level.pickups
            .where((p) => route.any((c) => c.distanceTo(p.coord) <= 2))
            .length;
        expect(near, greaterThanOrEqualTo(5), reason: difficulty.label);
      }
    });
  });
}
