import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';

const _layout = HexLayout(size: 20, origin: Offset(400, 400));

HexGrid _field({
  int radius = 8,
  HexCoord exit = const HexCoord(0, -8),
  Iterable<HexCoord> cleared = const [],
}) {
  final coords = HexCoord.zero.disc(radius);
  final grid = HexGrid(
    cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
    start: HexCoord.zero,
    exit: exit,
    truePath: [HexCoord.zero, exit],
  );
  for (final c in cleared) {
    grid.at(c)!.clear(0);
  }
  return grid;
}

/// Steps the dog forward, asserting the invariant that she is never inside a
/// wall. Returns the cells she visited, in order.
List<HexCoord> _run(
  Dog dog,
  HexGrid grid,
  TuningConfig tuning, {
  required double seconds,
  bool Function()? stopWhen,
}) {
  const dt = 1 / 60;
  final visited = <HexCoord>[dog.cell];
  var elapsed = 0.0;

  while (elapsed < seconds) {
    elapsed += dt;
    dog.update(
      dt: dt,
      grid: grid,
      layout: _layout,
      tuning: tuning,
      fieldVersion: 1,
      regrowthActive: true,
    );
    expect(
      grid.blocks(_layout.toHex(dog.position)),
      isFalse,
      reason: 'dog ended up inside a solid hex at ${dog.position}',
    );
    if (visited.last != dog.cell) {
      visited.add(dog.cell);
    }
    if (stopWhen != null && stopWhen()) {
      break;
    }
  }
  return visited;
}

void main() {
  group('Dog drift', () {
    test('entering the food hex wins even near its edge', () {
      const exit = HexCoord(0, -1);
      final grid = _field(
        radius: 2,
        exit: exit,
        cleared: [HexCoord.zero, exit],
      );
      final centre = _layout.toPixel(exit);
      final towardStart = _layout.toPixel(HexCoord.zero) - centre;
      final position =
          centre +
          towardStart / towardStart.distance * (_layout.inradius * 0.90);
      final dog = Dog(position: position, cell: _layout.toHex(position));

      expect(dog.cell, exit);
      expect(
        (dog.position - centre).distance,
        greaterThan(_layout.inradius * 0.75),
        reason: 'this reproduces the old invisible inner-circle failure',
      );
      expect(dog.hasReachedExit(grid), isTrue);
    });

    test('stays put when there is nowhere to go', () {
      // The opening position: one open cell, walls on all six sides. She
      // should settle, not jitter.
      final grid = _field(cleared: const [HexCoord.zero]);
      final dog = Dog(
        position: _layout.toPixel(HexCoord.zero),
        cell: HexCoord.zero,
      );

      _run(dog, grid, TuningConfig(), seconds: 3);

      expect(dog.cell, HexCoord.zero);
      expect(dog.speed, lessThan(1.0));
      expect(dog.hasBeenFree, isFalse);
      expect(dog.enclosedFor, 0, reason: 'the opening position must not kill');
    });

    test('walks down a cleared corridor to the far end', () {
      final corridor = [for (var r = 0; r >= -7; r--) HexCoord(0, r)];
      final grid = _field(exit: const HexCoord(0, -7), cleared: corridor);
      final dog = Dog(
        position: _layout.toPixel(HexCoord.zero),
        cell: HexCoord.zero,
      );

      final visited = _run(
        dog,
        grid,
        TuningConfig(),
        seconds: 30,
        stopWhen: () => false,
      );

      expect(dog.cell, const HexCoord(0, -7));
      expect(visited, containsAllInOrder(corridor));
      expect(dog.hasBeenFree, isTrue);
    });

    test('follows a corridor that turns', () {
      final corridor = <HexCoord>[
        const HexCoord(0, 0),
        const HexCoord(0, -1),
        const HexCoord(0, -2),
        const HexCoord(1, -3),
        const HexCoord(2, -4),
        const HexCoord(3, -5),
      ];
      final grid = _field(exit: const HexCoord(3, -5), cleared: corridor);
      final dog = Dog(
        position: _layout.toPixel(HexCoord.zero),
        cell: HexCoord.zero,
      );

      _run(dog, grid, TuningConfig(), seconds: 30);

      expect(dog.cell, const HexCoord(3, -5));
    });

    test('openness drives speed: open ground is much faster than a slot', () {
      // §2.2 is the self-regulating difficulty curve — carve wide and go fast,
      // carve narrow and stay safe. If this relationship does not hold, the
      // game has no moment-to-moment tension to tune.
      final tuning = TuningConfig();

      // Peak rather than a fixed sample: in open ground she reaches her
      // target and is already easing off before a fixed instant arrives.
      double peakSpeed(HexGrid grid) {
        final dog = Dog(
          position: _layout.toPixel(HexCoord.zero),
          cell: HexCoord.zero,
        );
        var peak = 0.0;
        const dt = 1 / 60;
        for (var i = 0; i < 60 * 3; i++) {
          dog.update(
            dt: dt,
            grid: grid,
            layout: _layout,
            tuning: tuning,
            fieldVersion: 1,
            regrowthActive: true,
          );
          if (dog.speed > peak) {
            peak = dog.speed;
          }
        }
        return peak;
      }

      final slot = peakSpeed(
        _field(
          exit: const HexCoord(0, -7),
          cleared: [for (var r = 0; r >= -7; r--) HexCoord(0, r)],
        ),
      );
      final openGround = peakSpeed(
        _field(exit: const HexCoord(0, -7), cleared: HexCoord.zero.disc(4)),
      );

      expect(slot, greaterThan(0), reason: 'a corridor should still move her');
      expect(
        openGround,
        greaterThan(slot * 2.5),
        reason: 'open ground must accelerate her hard, not marginally',
      );
    });

    test(
      'a wall that closes beside her pushes her clear instead of trapping',
      () {
        final grid = _field(cleared: HexCoord.zero.disc(1));
        final dog = Dog(
          position: _layout.toPixel(HexCoord.zero),
          cell: HexCoord.zero,
        );
        _run(dog, grid, TuningConfig(), seconds: 0.6);

        // Seal everything except the cell she is standing in.
        for (final c in HexCoord.zero.neighbours) {
          grid.at(c)!.resetToSolid();
        }
        _run(dog, grid, TuningConfig(), seconds: 1.0);

        expect(grid.blocks(dog.cell), isFalse);
        expect(dog.cell, HexCoord.zero);
      },
    );

    test('leaves a trail of pawprints while moving, capped in length', () {
      final grid = _field(
        exit: const HexCoord(0, -7),
        cleared: [for (var r = 0; r >= -7; r--) HexCoord(0, r)],
      );
      final dog = Dog(
        position: _layout.toPixel(HexCoord.zero),
        cell: HexCoord.zero,
      );

      _run(dog, grid, TuningConfig(), seconds: 4);

      expect(dog.pawprints, isNotEmpty);
      expect(dog.pawprints.length, lessThanOrEqualTo(4));
    });
  });
}
