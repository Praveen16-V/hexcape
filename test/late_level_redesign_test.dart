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
    64: 105783,
    65: 100001,
    66: 107619,
    69: 102135,
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

  test('64 stays a challenge without a long lit corridor', () {
    for (final difficulty in Difficulty.values) {
      final rules = Campaign.rulesFor(64, difficulty: difficulty);
      final level = LevelGenerator.generate(specFor(rules));
      final route = _route(level);
      final alternate = _alternateCost(level, route);

      expect(rules.identity.title, 'Standing Stone');
      expect(rules.pace, LevelPace.challenge);
      expect(route.length - 1, inInclusiveRange(24, 25));
      expect(level.par, 31);
      expect(_litRouteCells(level, route), 0, reason: difficulty.label);
      expect(alternate, isNotNull, reason: difficulty.label);
      expect(alternate! - level.par, lessThanOrEqualTo(5));
    }
  });

  test('66 has useful arrows without a mandatory push into a wall', () {
    for (final difficulty in Difficulty.values) {
      final rules = Campaign.rulesFor(66, difficulty: difficulty);
      final level = LevelGenerator.generate(specFor(rules));
      final grid = level.grid;
      final route = _route(level);
      final arrows = grid.all.where((cell) => cell.type == HexType.slope);
      final magnets = grid.all.where((cell) => cell.type == HexType.magnet);

      expect(rules.identity.title, 'Thin Floor');
      expect(rules.pace, LevelPace.introduction);
      expect(arrows.length, greaterThanOrEqualTo(3));
      expect(magnets, isNotEmpty);
      expect(
        magnets.any((m) => route.any((c) => c.distanceTo(m.coord) <= 2)),
        isTrue,
        reason: '${difficulty.label} misses the magnet introduction',
      );
      for (final arrow in arrows) {
        final ahead = arrow.coord + HexCoord.directions[arrow.slopeDirection];
        expect(
          grid.isTraversableInPrinciple(ahead),
          isTrue,
          reason: '${difficulty.label} arrow ${arrow.coord} points into a wall',
        );
      }
      expect(
        route.any((c) => grid.at(c)!.type == HexType.slope),
        isFalse,
        reason: '${difficulty.label} must cross an arrow to finish',
      );
      expect(_litRouteCells(level, route), lessThanOrEqualTo(1));
    }
  });

  test('69 practises arrows without forcing a push away from the exit', () {
    for (final difficulty in Difficulty.values) {
      final rules = Campaign.rulesFor(69, difficulty: difficulty);
      final level = LevelGenerator.generate(specFor(rules));
      final grid = level.grid;
      final route = _route(level);
      final arrows = grid.all.where((cell) => cell.type == HexType.slope);
      final magnets = grid.all.where((cell) => cell.type == HexType.magnet);
      final near = level.pickups
          .where((p) => route.any((c) => c.distanceTo(p.coord) <= 2))
          .length;

      expect(rules.identity.title, 'Undermine');
      expect(rules.pace, LevelPace.practice);
      expect(route.length - 1, 23);
      expect(arrows.length, greaterThanOrEqualTo(4));
      expect(near, greaterThanOrEqualTo(4));
      expect(
        magnets.any((m) => route.any((c) => c.distanceTo(m.coord) <= 2)),
        isTrue,
        reason: '${difficulty.label} misses the magnet practice',
      );
      for (final arrow in arrows) {
        final ahead = arrow.coord + HexCoord.directions[arrow.slopeDirection];
        expect(
          grid.isTraversableInPrinciple(ahead),
          isTrue,
          reason: '${difficulty.label} arrow ${arrow.coord} points into a wall',
        );
      }
      expect(
        route.any((c) => grid.at(c)!.type == HexType.slope),
        isFalse,
        reason: '${difficulty.label} must cross an arrow to finish',
      );
      expect(_litRouteCells(level, route), lessThanOrEqualTo(1));
      final clockPerStep =
          level.par * rules.hungerSecondsPerCell / (route.length - 1);
      expect(
        clockPerStep,
        greaterThanOrEqualTo(difficulty == Difficulty.hard ? 1.15 : 1.3),
      );
    }
  });
}
