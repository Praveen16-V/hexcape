import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/gen/silhouette.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/systems/regrowth_system.dart';

import 'sim/simulated_player.dart' show specFor, tuningFor;

const _layout = HexLayout(size: 22, origin: Offset(400, 400));

void main() {
  group('Level 11 redesign', () {
    test('Hard Shell is a deliberate, fair board in both modes', () {
      final boards = <Difficulty, GeneratedLevel>{};
      final rulesByDifficulty = <Difficulty, LevelRules>{};

      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(11, difficulty: difficulty);
        final level = LevelGenerator.generate(specFor(rules));
        rulesByDifficulty[difficulty] = rules;
        boards[difficulty] = level;

        expect(rules.seed, 11441, reason: '${difficulty.label} seed drifted');
        expect(rules.identity.title, 'Hard Shell');
        expect(rules.identity.signature, LevelSignature.heavyGround);
        expect(rules.shape, FieldShape.diamond);
        expect(rules.pace, LevelPace.challenge);

        final budget = (level.par * rules.budgetMultiplier).ceil();
        expect(
          budget,
          greaterThanOrEqualTo(level.par),
          reason: '${difficulty.label} cannot afford its cheapest route',
        );

        final route = Pathfinder.cheapestPath(
          level.grid.start,
          level.grid.exit,
          level.grid.isTraversableInPrinciple,
          (coord) => level.grid.at(coord)!.type.hitsRequired,
        );
        expect(route, isNotNull, reason: '${difficulty.label} has no route');
        expect(
          route!.length - 1,
          inInclusiveRange(16, 20),
          reason: '${difficulty.label} lost the compact route',
        );

        final protected = level.grid.truePath;
        for (var i = 1; i < protected.length - 1; i++) {
          final beside = protected[i].neighbours.where(
            (coord) =>
                coord != protected[i - 1] &&
                coord != protected[i + 1] &&
                level.grid.contains(coord) &&
                !level.grid.isAnchor(coord),
          );
          expect(
            beside,
            isNotEmpty,
            reason:
                '${difficulty.label} pinches the protected route at '
                '${protected[i]}',
          );
        }
      }

      final normal = boards[Difficulty.normal]!;
      final hard = boards[Difficulty.hard]!;
      final normalRules = rulesByDifficulty[Difficulty.normal]!;
      final hardRules = rulesByDifficulty[Difficulty.hard]!;
      int count(GeneratedLevel level, HexType type) =>
          level.grid.all.where((cell) => cell.type == type).length;

      expect(count(normal, HexType.heavy), greaterThanOrEqualTo(24));
      expect(
        count(hard, HexType.heavy),
        greaterThan(count(normal, HexType.heavy)),
      );
      expect(
        count(hard, HexType.anchor),
        greaterThan(count(normal, HexType.anchor)),
      );
      expect(hardRules.anchorDensity, greaterThan(normalRules.anchorDensity));
      expect(hardRules.heavyDensity, greaterThan(normalRules.heavyDensity));

      final previousChallenge = Campaign.rulesFor(8);
      expect(
        normalRules.anchorDensity,
        greaterThanOrEqualTo(previousChallenge.anchorDensity),
        reason: 'level 11 is a challenge peak, not an anchor breather',
      );
    });

    test('the dog crosses the protected route on Normal and Hard', () {
      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(11, difficulty: difficulty);
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
        for (var frame = 0; frame < 60 * 60 && dog.cell != grid.exit; frame++) {
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
                '${difficulty.label} stuck at ${dog.position} in ${dog.cell}',
          );
        }

        expect(
          dog.cell,
          grid.exit,
          reason: '${difficulty.label} did not reach the bone',
        );
      }
    });

    test('one-step carving clears Normal and Hard with regrowth live', () {
      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(11, difficulty: difficulty);
        final level = LevelGenerator.generate(specFor(rules));
        final grid = level.grid;
        final path = Pathfinder.cheapestPath(
          grid.start,
          grid.exit,
          grid.isTraversableInPrinciple,
          (coord) => grid.at(coord)!.type.hitsRequired,
        )!;
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

        while (now < 90 && dog.cell != grid.exit) {
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
      }
    });
  });
}
