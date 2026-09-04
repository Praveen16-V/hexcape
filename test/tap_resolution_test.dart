import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/systems/input_system.dart';

const _layout = HexLayout(size: 24, origin: Offset(500, 500));
const _tapRadius = 78.0;

HexGrid _field() {
  final coords = HexCoord.zero.disc(6);
  return HexGrid(
    cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
    start: HexCoord.zero,
    exit: const HexCoord(0, -6),
    truePath: const [HexCoord.zero, HexCoord(0, -6)],
  );
}

TapResult _tapAt(HexGrid grid, Offset point) => InputSystem.resolve(
  point: point,
  grid: grid,
  layout: _layout,
  dogPosition: _layout.toPixel(HexCoord.zero),
  tapRadius: _tapRadius,
);

void main() {
  group('Tap resolution', () {
    test('an exact tap clears the hex under the finger, not a neighbour', () {
      final grid = _field();
      const target = HexCoord(1, 0);

      final result = _tapAt(grid, _layout.toPixel(target));

      expect(result.outcome, TapOutcome.hit);
      expect(result.coord, target, reason: 'a deliberate tap was reassigned');
    });

    test('tapping the middle of an already-cleared pit does nothing', () {
      // The reported bug. Before this was bounded, the nearest *clearable* hex
      // won regardless of distance, so tapping an open hole shattered some
      // other tile two or three cells away.
      final grid = _field();
      const pit = HexCoord(1, 0);
      grid.at(pit)!.clear(0);

      final result = _tapAt(grid, _layout.toPixel(pit));

      expect(
        result.outcome,
        TapOutcome.nothingToClear,
        reason: 'tapping a hole must not break a different tile',
      );
      expect(result.coord, isNull);
    });

    test('a near miss still falls through to the hex it was reaching for', () {
      // Forgiveness survives: land most of the way toward a solid neighbour and
      // that neighbour is plainly what was meant.
      final grid = _field();
      const pit = HexCoord(1, 0);
      const neighbour = HexCoord(1, -1);
      grid.at(pit)!.clear(0);

      final from = _layout.toPixel(pit);
      final to = _layout.toPixel(neighbour);
      final result = _tapAt(grid, from + (to - from) * 0.65);

      expect(result.outcome, TapOutcome.hit);
      expect(result.coord, neighbour);
    });

    test('a tap never resolves to a hex further than the snap limit', () {
      final grid = _field();
      // Open every cell the dog can reach except one far edge of the ring, so
      // any resolution has to travel to find it.
      for (final c in HexCoord.zero.disc(2)) {
        if (grid.contains(c) && c != const HexCoord(-2, 1)) {
          grid.at(c)!.clear(0);
        }
      }

      for (final probe in HexCoord.zero.disc(2)) {
        final result = _tapAt(grid, _layout.toPixel(probe));
        if (result.outcome != TapOutcome.hit) {
          continue;
        }
        final distance =
            (_layout.toPixel(result.coord!) - _layout.toPixel(probe)).distance;
        expect(
          distance,
          lessThanOrEqualTo(_layout.width * 0.75 + 1e-6),
          reason: 'tap at $probe jumped to ${result.coord}',
        );
      }
    });

    test('the band just outside the ring does not pull taps inward', () {
      // The out-of-range guard is deliberately generous by about a hex, which
      // used to mean every tap in that band snapped back to whatever was
      // nearest inside the ring.
      final grid = _field();
      const outside = HexCoord(2, 0);
      expect(
        (_layout.toPixel(outside) - _layout.toPixel(HexCoord.zero)).distance,
        greaterThan(_tapRadius),
        reason: 'this cell should sit outside the editable ring',
      );

      final result = _tapAt(grid, _layout.toPixel(outside));

      expect(result.outcome, TapOutcome.nothingToClear);
    });

    test('anchors are still reported rather than redirected', () {
      final grid = _field();
      const wall = HexCoord(1, 0);
      grid.at(wall)!.type = HexType.anchor;

      final result = _tapAt(grid, _layout.toPixel(wall));

      expect(result.outcome, TapOutcome.anchor);
      expect(result.coord, wall);
    });

    test('a heavy hex resolves to itself on both taps', () {
      // A heavy hex holding after the first tap can look like a misfire, so it
      // matters that the second tap lands on the same cell rather than
      // wandering off to a neighbour.
      final grid = _field();
      const heavy = HexCoord(0, 1);
      grid.at(heavy)!.type = HexType.heavy;

      final first = _tapAt(grid, _layout.toPixel(heavy));
      expect(first.coord, heavy);
      expect(grid.at(heavy)!.hit(0), isFalse, reason: 'should only crack');

      final second = _tapAt(grid, _layout.toPixel(heavy));
      expect(second.outcome, TapOutcome.hit);
      expect(second.coord, heavy);
      expect(grid.at(heavy)!.hit(0), isTrue);
    });

    test('a wild tap across the screen is still out of range', () {
      final grid = _field();
      final result = _tapAt(grid, const Offset(500, 50));
      expect(result.outcome, TapOutcome.outOfRange);
    });
  });
}
