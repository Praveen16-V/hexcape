import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_coord.dart';

import 'sim/simulated_player.dart' show specFor;

List<HexCoord> _route(GeneratedLevel level) => Pathfinder.cheapestPath(
  level.grid.start,
  level.grid.exit,
  level.grid.isTraversableInPrinciple,
  (c) => level.grid.at(c)!.type.hitsRequired,
)!;

int? _alternateCost(GeneratedLevel level, List<HexCoord> route) {
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

int _litRouteCells(GeneratedLevel level, List<HexCoord> route) {
  final seen = <HexCoord>{};
  for (var i = 0; i < 1600; i++) {
    for (final guard in level.guards) {
      guard.update(1 / 20);
    }
    final lit = <HexCoord>{for (final guard in level.guards) ...guard.lit};
    for (final c in route) {
      if (lit.contains(c)) seen.add(c);
    }
  }
  return seen.length;
}

void main() {
  const seeds = {
    57: 100010,
    60: 100031,
    65: 100001,
    71: 100055,
    76: 100004,
    80: 100033,
    82: 100007,
    88: 100025,
    93: 100011,
    99: 100016,
  };

  test('the redesigned boards have a playable Hard route', () {
    for (final entry in seeds.entries) {
      final n = entry.key;
      final normal = Campaign.rulesFor(n);
      final hard = Campaign.rulesFor(n, difficulty: Difficulty.hard);
      expect(normal.seed, entry.value, reason: 'level $n board changed');
      expect(hard.seed, entry.value, reason: 'level $n Hard board changed');
      expect(hard.pace, normal.pace, reason: 'level $n lost its pacing role');
      expect(hard.identity.signature, normal.identity.signature);

      for (final rules in [normal, hard]) {
        final level = LevelGenerator.generate(specFor(rules));
        final route = _route(level);
        final clock = level.par * rules.hungerSecondsPerCell;
        final clockPerStep = clock / (route.length - 1);
        final near = level.pickups
            .where((p) => route.any((c) => c.distanceTo(p.coord) <= 2))
            .length;
        final lit = _litRouteCells(level, route);

        expect(route.length, greaterThan(1), reason: '$n ${rules.seed}');
        expect(near, greaterThanOrEqualTo(4), reason: 'level $n supplies');
        expect(lit, lessThanOrEqualTo(2), reason: 'level $n patrol route');
        if (rules == hard) {
          expect(
            clockPerStep,
            greaterThanOrEqualTo(0.95),
            reason: 'level $n Hard clock $clock for ${route.length - 1} steps',
          );
          final spare = (level.par * rules.budgetMultiplier).ceil() - level.par;
          expect(spare, greaterThanOrEqualTo(1), reason: 'level $n taps');
        }
      }
    }
  });

  test('57 offers useful rewards and two routes in both modes', () {
    for (final difficulty in Difficulty.values) {
      final level = LevelGenerator.generate(
        specFor(Campaign.rulesFor(57, difficulty: difficulty)),
      );
      final route = _route(level);
      final near = level.pickups
          .where((p) => route.any((c) => c.distanceTo(p.coord) <= 2))
          .length;
      expect(near, greaterThanOrEqualTo(5), reason: difficulty.label);
      expect(_litRouteCells(level, route), 0, reason: difficulty.label);
      expect(_alternateCost(level, route), level.par, reason: difficulty.label);
    }
  });

  test('60 has a reachable second way through in both modes', () {
    for (final difficulty in Difficulty.values) {
      final level = LevelGenerator.generate(
        specFor(Campaign.rulesFor(60, difficulty: difficulty)),
      );
      final route = _route(level);
      final alternate = _alternateCost(level, route);
      expect(alternate, isNotNull, reason: difficulty.label);
      expect(alternate! - level.par, lessThanOrEqualTo(5));
    }
  });
}
