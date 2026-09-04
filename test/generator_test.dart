import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_cell.dart';

void main() {
  group('LevelGenerator', () {
    test('500 seeds all produce a solvable level', () {
      // §3.2 requires a solvability check before a level is accepted. This is
      // the gate: a generator that can emit an unsolvable field is a generator
      // that will strand players on a seed nobody can reproduce.
      for (var seed = 0; seed < 500; seed++) {
        final level = LevelGenerator.generate(LevelSpec(seed: seed));
        final grid = level.grid;

        final route = Pathfinder.shortestPath(
          grid.start,
          grid.exit,
          grid.isTraversableInPrinciple,
        );
        final cheapest = Pathfinder.cheapestCost(
          grid.start,
          grid.exit,
          grid.isTraversableInPrinciple,
          (c) => grid.cells[c]!.type.hitsRequired,
        );

        expect(route, isNotNull, reason: 'seed $seed has no route to the food');
        expect(grid.start, isNot(grid.exit), reason: 'seed $seed');
        expect(level.par, cheapest, reason: 'seed $seed');
        expect(level.par, greaterThan(0), reason: 'seed $seed');
        // Par counts taps, not cells, and heavy cells cost two — so it can
        // never come in under the cell count of the shortest route.
        expect(
          level.par,
          greaterThanOrEqualTo(route!.length - 1),
          reason: 'seed $seed',
        );
      }
    });

    test('the same seed always produces the same level', () {
      // Set iteration order is not stable across runs, so every random draw in
      // the generator sorts first. Without that, §3.2's reproducible daily
      // challenge would silently differ per device.
      for (final seed in [0, 1, 42, 999, 123456]) {
        final a = LevelGenerator.generate(LevelSpec(seed: seed));
        final b = LevelGenerator.generate(LevelSpec(seed: seed));

        expect(a.grid.start, b.grid.start);
        expect(a.grid.exit, b.grid.exit);
        expect(a.par, b.par);
        expect(a.grid.truePath, b.grid.truePath);

        final anchorsA = _anchors(a);
        final anchorsB = _anchors(b);
        expect(anchorsA, anchorsB, reason: 'anchor placement drifted');
      }
    });

    test('different seeds produce different levels', () {
      final layouts = {
        for (var seed = 0; seed < 30; seed++)
          _anchors(LevelGenerator.generate(LevelSpec(seed: seed))).join('|'),
      };
      expect(layouts.length, greaterThan(25));
    });

    test('heavy hexes raise par and never crowd the dog or the food', () {
      var plainPar = 0;
      var heavyPar = 0;
      for (var seed = 0; seed < 60; seed++) {
        final flat = LevelGenerator.generate(
          LevelSpec(seed: seed, heavyDensity: 0),
        );
        final lumpy = LevelGenerator.generate(
          LevelSpec(seed: seed, heavyDensity: 0.35),
        );
        plainPar += flat.par;
        heavyPar += lumpy.par;

        final grid = lumpy.grid;
        final protectedCells = {
          grid.start,
          grid.exit,
          ...grid.start.neighbours,
          ...grid.exit.neighbours,
        };
        for (final c in protectedCells) {
          final cell = grid.at(c);
          if (cell != null) {
            expect(cell.type, HexType.plain, reason: 'seed $seed at $c');
          }
        }
      }
      // A cost landscape is only a decision if it actually costs something.
      expect(heavyPar, greaterThan(plainPar));
    });

    test('a heavy hex takes two taps, and regrows whole', () {
      final grid = LevelGenerator.generate(
        const LevelSpec(seed: 7, heavyDensity: 0.4),
      ).grid;
      final heavy = grid.all.firstWhere((c) => c.type == HexType.heavy);

      expect(heavy.remainingHits, 2);
      expect(heavy.hit(0), isFalse, reason: 'first tap should only crack it');
      expect(heavy.remainingHits, 1);
      expect(heavy.isSolid, isTrue);
      expect(heavy.hit(0), isTrue, reason: 'second tap should open it');
      expect(heavy.isPassable, isTrue);
      expect(heavy.remainingHits, 0);

      heavy.resetToSolid();
      expect(heavy.remainingHits, 2, reason: 'a regrown heavy must be whole');
    });

    test('anchors never crowd the dog or the food', () {
      for (var seed = 0; seed < 200; seed++) {
        final grid = LevelGenerator.generate(LevelSpec(seed: seed)).grid;
        final protectedCells = {
          grid.start,
          grid.exit,
          ...grid.start.neighbours,
          ...grid.exit.neighbours,
        };
        for (final c in protectedCells) {
          if (grid.contains(c)) {
            expect(grid.isAnchor(c), isFalse, reason: 'seed $seed at $c');
          }
        }
      }
    });

    test('every cell starts solid, so the route is never visible', () {
      final grid = LevelGenerator.generate(const LevelSpec(seed: 3)).grid;
      expect(grid.all.every((c) => c.isSolid), isTrue);
      expect(grid.all.where((c) => c.isClearable).length, greaterThan(0));
    });

    test('the carved path connects the dog to the food step by step', () {
      for (var seed = 0; seed < 100; seed++) {
        final grid = LevelGenerator.generate(LevelSpec(seed: seed)).grid;
        final path = grid.truePath;
        expect(path.first, grid.start, reason: 'seed $seed');
        expect(path.last, grid.exit, reason: 'seed $seed');
        for (var i = 1; i < path.length; i++) {
          expect(path[i - 1].distanceTo(path[i]), 1, reason: 'seed $seed');
          expect(grid.contains(path[i]), isTrue, reason: 'seed $seed');
        }
      }
    });

    test(
      'the exit distance field agrees with par and routes around anchors',
      () {
        // The field is cached on first use. Anchors are placed after the grid is
        // constructed, so anything that touched it too early would bake in a
        // route straight through the walls -- and the dog steers on this.
        for (var seed = 0; seed < 100; seed++) {
          final level = LevelGenerator.generate(
            LevelSpec(seed: seed, anchorDensity: 0.3),
          );
          final grid = level.grid;

          expect(grid.distanceToExit(grid.exit), 0, reason: 'seed $seed');
          // Steps, not taps: this field is what the dog steers on, and she does
          // not care what a cell cost to open. Par counts taps, so with heavy
          // hexes on the board it sits at or above the step count.
          expect(
            level.par,
            greaterThanOrEqualTo(grid.distanceToExit(grid.start)),
            reason: 'seed $seed',
          );
          for (final cell in grid.all) {
            if (cell.type == HexType.anchor) {
              expect(
                grid.exitDistance.containsKey(cell.coord),
                isFalse,
                reason: 'seed $seed routed through an anchor at ${cell.coord}',
              );
            }
          }
        }
      },
    );

    test('raising anchor density places more anchors', () {
      var sparse = 0;
      var dense = 0;
      for (var seed = 0; seed < 40; seed++) {
        sparse += _anchors(
          LevelGenerator.generate(LevelSpec(seed: seed, anchorDensity: 0.05)),
        ).length;
        dense += _anchors(
          LevelGenerator.generate(LevelSpec(seed: seed, anchorDensity: 0.30)),
        ).length;
      }
      expect(dense, greaterThan(sparse * 2));
    });

    test('even a heavily anchored field stays solvable', () {
      // The density slider goes to 0.45; the incremental rollback in
      // _placeAnchors is what keeps that honest.
      for (var seed = 0; seed < 120; seed++) {
        final grid = LevelGenerator.generate(
          LevelSpec(seed: seed, anchorDensity: 0.45),
        ).grid;
        expect(
          Pathfinder.reachable(
            grid.start,
            grid.exit,
            grid.isTraversableInPrinciple,
          ),
          isTrue,
          reason: 'seed $seed became unsolvable at high density',
        );
      }
    });
  });
}

List<String> _anchors(GeneratedLevel level) => [
  for (final cell in level.grid.all)
    if (cell.type == HexType.anchor) '${cell.coord.q},${cell.coord.r}',
]..sort();
