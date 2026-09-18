import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';

import 'sim/simulated_player.dart' show specFor;

List<HexCoord> _route(GeneratedLevel level) => Pathfinder.cheapestPath(
  level.grid.start,
  level.grid.exit,
  level.grid.isTraversableInPrinciple,
  (c) => level.grid.at(c)!.type.hitsRequired,
)!;

void main() {
  const seeds = {
    57: 100010,
    60: 100031,
    64: 105783,
    65: 100001,
    66: 107619,
    69: 102135,
    71: 200299,
    72: 200124,
    74: 200098,
    75: 200066,
    76: 100004,
    79: 200011,
    80: 200303,
    81: 200016,
    82: 200176,
    85: 200074,
    86: 200005,
    87: 200119,
    88: 200102,
    89: 200028,
    90: 200128,
    92: 200060,
    93: 200237,
    95: 200296,
    96: 200020,
    98: 200159,
    99: 200312,
  };

  test('redesigned late boards have a reachable route and nearby supplies', () {
    for (final entry in seeds.entries) {
      final n = entry.key;
      final normal = Campaign.rulesFor(n);
      final hard = Campaign.rulesFor(n, difficulty: Difficulty.hard);
      expect(normal.seed, entry.value, reason: 'level $n seed');
      expect(hard.seed, entry.value, reason: 'level $n Hard seed');
      expect(hard.pace, normal.pace);

      for (final rules in [normal, hard]) {
        final level = LevelGenerator.generate(specFor(rules));
        final route = _route(level);
        final near = level.pickups
            .where((p) => route.any((c) => c.distanceTo(p.coord) <= 2))
            .length;
        final spare = (level.par * rules.budgetMultiplier).ceil() - level.par;

        expect(route.length, greaterThan(1), reason: 'level $n');
        expect(level.par, greaterThan(0), reason: 'level $n');
        expect(near, greaterThanOrEqualTo(3), reason: 'level $n supplies');
        expect(spare, greaterThanOrEqualTo(1), reason: 'level $n taps');
        expect(
          level.grid.all.any((cell) => cell.type == HexType.slope),
          isFalse,
          reason: 'level $n must have no forcing arrows',
        );
      }
    }
  });
}
