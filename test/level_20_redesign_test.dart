import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/entitlements.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/gen/silhouette.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/systems/regrowth_system.dart';

import 'sim/simulated_player.dart' show specFor, tuningFor;

const _layout = HexLayout(size: 22, origin: Offset(400, 400));

/// The cheapest route through a board, which is the answer a player converges
/// on once the fog has been paid for.
List<HexCoord> _route(GeneratedLevel level) => Pathfinder.cheapestPath(
  level.grid.start,
  level.grid.exit,
  level.grid.isTraversableInPrinciple,
  (coord) => level.grid.at(coord)!.type.hitsRequired,
)!;

/// What the second way round costs, with the middle half of [route] shut.
///
/// Shutting the *middle* rather than single cells is what makes this a test for
/// another way round rather than for a detour: a route that merely steps off
/// the first one for a cell and rejoins it cannot survive losing its whole
/// midsection.
int? _otherWayRound(GeneratedLevel level, List<HexCoord> route) {
  final shut = route
      .sublist(route.length ~/ 4, route.length - route.length ~/ 4)
      .toSet();
  return Pathfinder.cheapestCost(
    level.grid.start,
    level.grid.exit,
    (coord) =>
        !shut.contains(coord) && level.grid.isTraversableInPrinciple(coord),
    (coord) => level.grid.at(coord)!.type.hitsRequired,
  );
}

void main() {
  group('Level 20 redesign', () {
    test('Foundation Edge is a fork, not a corridor, in both modes', () {
      final routes = <Difficulty, List<HexCoord>>{};
      final walls = <Difficulty, int>{};

      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(20, difficulty: difficulty);
        final level = LevelGenerator.generate(specFor(rules));

        expect(rules.seed, 26895, reason: '${difficulty.label} seed drifted');
        expect(rules.identity.title, 'Foundation Edge');
        expect(rules.shape, FieldShape.diamond);
        expect(rules.pace, LevelPace.challenge);
        expect(
          rules.level,
          Entitlements.freeThrough,
          reason: 'this test is about the last free level',
        );

        final route = _route(level);
        routes[difficulty] = route;
        walls[difficulty] = level.grid.all
            .where((cell) => cell.type == HexType.anchor)
            .length;

        // Long enough to be a finale. The board this replaced answered to
        // nineteen steps straight up its own centre column.
        expect(
          route.length - 1,
          inInclusiveRange(22, 30),
          reason: '${difficulty.label} route is ${route.length - 1} steps',
        );

        // And it wanders. A straight line changes direction nowhere, so this is
        // the cheapest way to say "not the centre column" without the test
        // needing to know where the centre column is.
        var turns = 0;
        for (var i = 2; i < route.length; i++) {
          if (route[i - 1] - route[i - 2] != route[i] - route[i - 1]) turns++;
        }
        expect(
          turns,
          greaterThanOrEqualTo(10),
          reason: '${difficulty.label} route turns only $turns times',
        );

        // It spends the width of the board rather than one column of it.
        final spread = unitBounds(route);
        final board = unitBounds(level.grid.all.map((cell) => cell.coord));
        expect(
          (spread.maxX - spread.minX) / (board.maxX - board.minX),
          greaterThan(0.45),
          reason: '${difficulty.label} route hugs one column',
        );

        // The fork itself: shut the whole middle of the route and there is
        // still a way round, within two taps of the first. That margin is the
        // difference between a choice and a cheap answer beside a mistake.
        final other = _otherWayRound(level, route);
        expect(other, isNotNull, reason: '${difficulty.label} is one corridor');
        expect(
          other! - level.par,
          lessThanOrEqualTo(2),
          reason:
              '${difficulty.label} second way round costs ${other - level.par} '
              'taps more than par ${level.par}',
        );

        // Foundation's whole vocabulary is on the board, because this is the
        // level that closes the band that taught it.
        int count(HexType type) =>
            level.grid.all.where((cell) => cell.type == type).length;
        for (final type in [
          HexType.anchor,
          HexType.heavy,
          HexType.spring,
          HexType.mire,
          HexType.thicket,
          HexType.sleeper,
          HexType.foxfire,
        ]) {
          expect(
            count(type),
            greaterThan(0),
            reason: '${difficulty.label} has no ${type.name}',
          );
        }
      }

      // Hard is a different board, not the same board behind more scenery. Its
      // heavier ground flips which flank is cheaper, so the two modes' answers
      // barely overlap.
      final shared = routes[Difficulty.hard]!
          .toSet()
          .intersection(routes[Difficulty.normal]!.toSet())
          .length;
      expect(
        shared / routes[Difficulty.normal]!.length,
        lessThan(0.5),
        reason: 'Hard walks Normal\'s route with more walls beside it',
      );
      expect(walls[Difficulty.hard]!, greaterThan(walls[Difficulty.normal]!));
    });

    test('neither mode is a coin toss on the last free level', () {
      // Hard runs at nought or one spare tap across most of the campaign on
      // purpose — its budget floor is par itself. This is the level worth
      // excepting: it is the board the purchase decision gets made on, and a
      // finish that turns on a single discovery tap under fog is not a finale.
      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(20, difficulty: difficulty);
        final level = LevelGenerator.generate(specFor(rules));
        final budget = (level.par * rules.budgetMultiplier).ceil();
        expect(
          budget - level.par,
          greaterThanOrEqualTo(2),
          reason:
              '${difficulty.label} gives ${budget - level.par} spare taps over '
              'par ${level.par}',
        );
      }
    });

    test('she crosses the protected route in both modes', () {
      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(20, difficulty: difficulty);
        final level = LevelGenerator.generate(specFor(rules));
        final grid = level.grid;

        for (final cell in grid.all) {
          cell.resetToSolid();
        }
        for (final coord in grid.truePath) {
          grid.at(coord)!.clear(0);
        }

        final dog = Dog(
          position: _layout.toPixel(grid.start),
          cell: grid.start,
        );
        final tuning = tuningFor(rules);
        var stalledFrames = 0;
        for (var frame = 0; frame < 60 * 90 && dog.cell != grid.exit; frame++) {
          dog.update(
            dt: 1 / 60,
            grid: grid,
            layout: _layout,
            tuning: tuning,
            fieldVersion: 1,
            regrowthActive: false,
          );
          if (dog.route.length > 1 && dog.speed < 2) {
            stalledFrames++;
          } else {
            stalledFrames = 0;
          }
          expect(
            stalledFrames,
            lessThan(120),
            reason:
                '${difficulty.label} wedged at ${dog.position} in ${dog.cell}',
          );
        }

        expect(
          dog.cell,
          grid.exit,
          reason: '${difficulty.label} did not reach the bone',
        );
      }
    });

    test('one-step carving clears both modes with regrowth live', () {
      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(20, difficulty: difficulty);
        final level = LevelGenerator.generate(specFor(rules));
        final grid = level.grid;
        final path = _route(level);
        grid.at(grid.start)!.clear(0);

        final dog = Dog(
          position: _layout.toPixel(grid.start),
          cell: grid.start,
        );
        final tuning = tuningFor(rules);
        final regrowth = RegrowthSystem();
        final budget = (level.par * rules.budgetMultiplier).ceil();
        var taps = 0;
        var next = 1;
        var now = 0.0;
        var nextTapAt = 0.0;
        var fieldVersion = 1;

        while (now < 120 && dog.cell != grid.exit) {
          now += 1 / 60;
          while (next < path.length && path[next] == dog.cell) {
            next++;
          }
          if (next < path.length &&
              now >= nextTapAt &&
              dog.cell.distanceTo(path[next]) <= 1 &&
              grid.isClearable(path[next])) {
            final opened = grid.at(path[next])!.hit(now);
            taps++;
            nextTapAt = now + 0.22;
            if (opened) fieldVersion++;
          }

          dog.update(
            dt: 1 / 60,
            grid: grid,
            layout: _layout,
            tuning: tuning,
            fieldVersion: fieldVersion,
            regrowthActive: true,
          );
          final events = regrowth.update(
            dt: 1 / 60,
            now: now,
            grid: grid,
            tuning: tuning,
            dogCell: dog.cell,
            dogOccupiedCells: dog.occupiedCells(_layout),
          );
          if (events.fieldChanged) fieldVersion++;
        }

        expect(
          dog.cell,
          grid.exit,
          reason: '${difficulty.label} stalled at ${dog.cell} after $taps taps',
        );
        expect(
          taps,
          lessThanOrEqualTo(budget),
          reason: '${difficulty.label} costs $taps taps but budgets $budget',
        );
        // The clock is derived from par, so a longer route buys proportionally
        // more of it. This checks the two have not drifted apart.
        expect(
          now,
          lessThan(level.par * rules.hungerSecondsPerCell),
          reason:
              '${difficulty.label} takes ${now.toStringAsFixed(1)}s against a '
              '${(level.par * rules.hungerSecondsPerCell).toStringAsFixed(1)}s '
              'clock',
        );
      }
    });
  });
}
