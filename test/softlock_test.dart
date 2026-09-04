import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/systems/softlock_system.dart';

HexGrid _field({int radius = 4, HexCoord exit = const HexCoord(0, -4)}) {
  final coords = HexCoord.zero.disc(radius);
  return HexGrid(
    cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
    start: HexCoord.zero,
    exit: exit,
    truePath: [HexCoord.zero, exit],
  );
}

void main() {
  group('SoftlockSystem', () {
    test('a field of solid plain hexes is not locked', () {
      // The check runs on what the player could open, not on what is open now.
      // A solid plain hex is one tap away from being a corridor.
      final grid = _field();
      final system = SoftlockSystem();

      expect(
        system.check(
          grid: grid,
          dogCell: HexCoord.zero,
          fieldVersion: 1,
          tapsLeft: 999,
        ),
        isFalse,
      );
    });

    test('a dog ringed by anchors is locked', () {
      final grid = _field();
      for (final c in HexCoord.zero.neighbours) {
        grid.at(c)!.type = HexType.anchor;
      }
      final system = SoftlockSystem();

      expect(
        system.check(
          grid: grid,
          dogCell: HexCoord.zero,
          fieldVersion: 1,
          tapsLeft: 999,
        ),
        isTrue,
      );
    });

    test('a wall of anchors across the field cuts the dog off', () {
      final grid = _field();
      // Seal off every route to the top of the field.
      for (final cell in grid.all) {
        if (cell.coord.r == -1) {
          cell.type = HexType.anchor;
        }
      }
      final system = SoftlockSystem();

      expect(
        system.check(
          grid: grid,
          dogCell: HexCoord.zero,
          fieldVersion: 1,
          tapsLeft: 999,
        ),
        isTrue,
      );
      // Standing on the far side of that wall, the food is reachable again.
      expect(
        system.check(
          grid: grid,
          dogCell: const HexCoord(0, -2),
          fieldVersion: 2,
          tapsLeft: 999,
        ),
        isFalse,
      );
    });

    test('a regrown field is still not locked while plain hexes remain', () {
      // This is why the check ignores cell state: regrowth can seal the dog
      // into a pocket, but every wall of that pocket is still clearable.
      final grid = _field();
      final system = SoftlockSystem();
      for (final cell in grid.all) {
        cell.resetToSolid();
      }

      expect(
        system.check(
          grid: grid,
          dogCell: HexCoord.zero,
          fieldVersion: 9,
          tapsLeft: 999,
        ),
        isFalse,
      );
    });

    test('the result is cached until the field or the dog moves', () {
      final grid = _field();
      final system = SoftlockSystem();
      expect(
        system.check(
          grid: grid,
          dogCell: HexCoord.zero,
          fieldVersion: 1,
          tapsLeft: 999,
        ),
        isFalse,
      );

      // Wall the dog in without telling the system anything changed.
      for (final c in HexCoord.zero.neighbours) {
        grid.at(c)!.type = HexType.anchor;
      }
      expect(
        system.check(
          grid: grid,
          dogCell: HexCoord.zero,
          fieldVersion: 1,
          tapsLeft: 999,
        ),
        isFalse,
        reason: 'should have reused the cached answer',
      );

      expect(
        system.check(
          grid: grid,
          dogCell: HexCoord.zero,
          fieldVersion: 2,
          tapsLeft: 999,
        ),
        isTrue,
        reason: 'a new field version must force a re-check',
      );
    });

    test('reset clears the cached verdict', () {
      final grid = _field();
      for (final c in HexCoord.zero.neighbours) {
        grid.at(c)!.type = HexType.anchor;
      }
      final system = SoftlockSystem();
      expect(
        system.check(
          grid: grid,
          dogCell: HexCoord.zero,
          fieldVersion: 1,
          tapsLeft: 999,
        ),
        isTrue,
      );

      system.reset();
      expect(system.isLocked, isFalse);
    });

    test('a route you cannot afford counts as locked', () {
      // The whole point of the budget: the bone is still reachable, you just
      // cannot pay for it any more.
      final grid = _field();
      final system = SoftlockSystem();
      final cost = grid.start.distanceTo(grid.exit);

      expect(
        system.check(
          grid: grid,
          dogCell: grid.start,
          fieldVersion: 1,
          tapsLeft: cost,
        ),
        isFalse,
        reason: 'exactly enough taps must not be a loss',
      );
      expect(
        system.check(
          grid: grid,
          dogCell: grid.start,
          fieldVersion: 2,
          tapsLeft: cost - 1,
        ),
        isTrue,
        reason: 'one tap short must be',
      );
    });

    test('cells already open are free, so opening a route buys slack', () {
      final grid = _field();
      final system = SoftlockSystem();
      final cost = grid.start.distanceTo(grid.exit);

      // With the first two cells of the route already carved, the same journey
      // costs two taps less.
      var step = grid.start;
      for (var i = 0; i < 2; i++) {
        step = step.neighbours.reduce(
          (a, b) => a.distanceTo(grid.exit) <= b.distanceTo(grid.exit) ? a : b,
        );
        grid.at(step)!.clear(0);
      }

      expect(
        system.check(
          grid: grid,
          dogCell: grid.start,
          fieldVersion: 3,
          tapsLeft: cost - 2,
        ),
        isFalse,
      );
    });

    test('heavy hexes make a route cost more to afford', () {
      final grid = _field();
      final system = SoftlockSystem();
      final cost = grid.start.distanceTo(grid.exit);

      // Wall the direct line with heavy hexes; the cheapest route now either
      // pays double or detours.
      for (final cell in grid.all) {
        if (cell.coord.r == -2) {
          cell.type = HexType.heavy;
        }
      }

      expect(
        system.check(
          grid: grid,
          dogCell: grid.start,
          fieldVersion: 4,
          tapsLeft: cost,
        ),
        isTrue,
        reason: 'a budget that only covered plain cells should no longer do',
      );
    });

    test('generated levels are never locked at their own budget', () {
      // The gate that matters: every level must be winnable at the budget it
      // ships with, before the player has done anything at all.
      final system = SoftlockSystem();
      for (var seed = 0; seed < 200; seed++) {
        final level = LevelGenerator.generate(
          LevelSpec(seed: seed, anchorDensity: 0.45),
        );
        system.reset();
        expect(
          system.check(
            grid: level.grid,
            dogCell: level.grid.start,
            fieldVersion: seed,
            tapsLeft: level.par,
          ),
          isFalse,
          reason: 'seed $seed starts unwinnable at par',
        );
      }
    });
  });
}
