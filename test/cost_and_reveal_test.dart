import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/systems/reveal_system.dart';

const _layout = HexLayout(size: 20, origin: Offset(400, 400));

HexGrid _field({int radius = 6, HexCoord exit = const HexCoord(0, -6)}) {
  final coords = HexCoord.zero.disc(radius);
  return HexGrid(
    cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
    start: HexCoord.zero,
    exit: exit,
    truePath: [HexCoord.zero, exit],
  );
}

void main() {
  group('Pathfinder.cheapestCost', () {
    test('matches the step count when every cell costs the same', () {
      final grid = _field();
      for (var r = -6; r <= 6; r++) {
        final target = HexCoord(0, r);
        final steps = Pathfinder.shortestPath(
          HexCoord.zero,
          target,
          grid.contains,
        );
        final cost = Pathfinder.cheapestCost(
          HexCoord.zero,
          target,
          grid.contains,
          (_) => 1,
        );
        expect(cost, steps!.length - 1, reason: '$target');
      }
    });

    test('takes the longer way round when the short way is expensive', () {
      // The decision heavy hexes exist to create: three cells at two taps each
      // is dearer than a five-cell detour at one.
      final grid = _field();
      for (final cell in grid.all) {
        if (cell.coord.q == 0 && cell.coord.r < 0 && cell.coord.r > -4) {
          cell.type = HexType.heavy;
        }
      }

      final throughTheWall = 3 * 2 + 3; // six taps of heavy, then plain
      final cost = Pathfinder.cheapestCost(
        HexCoord.zero,
        const HexCoord(0, -6),
        grid.isTraversableInPrinciple,
        (c) => grid.cells[c]!.type.hitsRequired,
      );

      expect(cost, isNotNull);
      expect(
        cost,
        lessThan(throughTheWall),
        reason: 'should have routed around the heavy wall, not paid for it',
      );
    });

    test('returns null when anchors seal the food away', () {
      final grid = _field();
      for (final cell in grid.all) {
        if (cell.coord.r == -3) {
          cell.type = HexType.anchor;
        }
      }
      expect(
        Pathfinder.cheapestCost(
          HexCoord.zero,
          const HexCoord(0, -6),
          grid.isTraversableInPrinciple,
          (c) => grid.cells[c]!.type.hitsRequired,
        ),
        isNull,
      );
    });

    test('the cell the dog already stands in is not charged for', () {
      final grid = _field();
      grid.at(HexCoord.zero)!.type = HexType.heavy;
      final cost = Pathfinder.cheapestCost(
        HexCoord.zero,
        const HexCoord(0, -2),
        grid.isTraversableInPrinciple,
        (c) => grid.cells[c]!.type.hitsRequired,
      );
      expect(
        cost,
        2,
        reason: 'two plain cells ahead, and nothing for standing',
      );
    });
  });

  group('RevealSystem', () {
    test('reveals what is close and leaves the rest unknown', () {
      final grid = _field(radius: 8);
      final learned = RevealSystem.reveal(
        grid: grid,
        layout: _layout,
        dogPosition: _layout.toPixel(HexCoord.zero),
        dogCell: HexCoord.zero,
        radius: _layout.width * 2,
      );

      expect(learned, greaterThan(0));
      expect(grid.at(HexCoord.zero)!.revealed, isTrue);
      expect(grid.at(const HexCoord(0, -1))!.revealed, isTrue);
      expect(
        grid.at(const HexCoord(0, -7))!.revealed,
        isFalse,
        reason: 'the far side of the board must stay unknown',
      );
    });

    test('what you have learned stays learned', () {
      final grid = _field(radius: 8);
      RevealSystem.reveal(
        grid: grid,
        layout: _layout,
        dogPosition: _layout.toPixel(HexCoord.zero),
        dogCell: HexCoord.zero,
        radius: _layout.width * 2,
      );

      // Walk away; nothing may un-learn.
      RevealSystem.reveal(
        grid: grid,
        layout: _layout,
        dogPosition: _layout.toPixel(const HexCoord(0, 6)),
        dogCell: const HexCoord(0, 6),
        radius: _layout.width * 2,
      );

      expect(grid.at(HexCoord.zero)!.revealed, isTrue);
      expect(grid.at(const HexCoord(0, -1))!.revealed, isTrue);
    });

    test('a second look over the same ground teaches nothing new', () {
      final grid = _field(radius: 8);
      const args = (radius: 60.0);
      final first = RevealSystem.reveal(
        grid: grid,
        layout: _layout,
        dogPosition: _layout.toPixel(HexCoord.zero),
        dogCell: HexCoord.zero,
        radius: args.radius,
      );
      final second = RevealSystem.reveal(
        grid: grid,
        layout: _layout,
        dogPosition: _layout.toPixel(HexCoord.zero),
        dogCell: HexCoord.zero,
        radius: args.radius,
      );
      expect(first, greaterThan(0));
      expect(second, 0);
    });

    test('sight always outreaches the tap radius', () {
      // Below this the editable highlight would betray anchors by not lighting
      // them, and the fog would leak the very thing it hides.
      expect(RevealSystem.radiusFor(78, 0.5), greaterThan(78));
      expect(RevealSystem.radiusFor(78, 1.0), greaterThan(78));
      expect(RevealSystem.radiusFor(78, 2.2), closeTo(78 * 2.2, 1e-9));
    });
  });
}
