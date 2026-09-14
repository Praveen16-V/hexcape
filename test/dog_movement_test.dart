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
    test('collision footprint includes both cells at a shared edge', () {
      const first = HexCoord.zero;
      const second = HexCoord(1, 0);
      final position = (_layout.toPixel(first) + _layout.toPixel(second)) / 2;
      final dog = Dog(position: position, cell: _layout.toHex(position));

      expect(
        dog.occupiedCells(_layout),
        containsAll(<HexCoord>[first, second]),
      );
    });

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

    test('a pocket whose best cell is a dead end does not make her shiver', () {
      // The stutter, in its smallest form. The food is north; a one-cell stub
      // runs north and stops, and there is fresh ground south of her.
      //
      // Standing in the stub, nothing is closer to the food, so she turns to
      // investigate the fresh ground. One step south, the stub is the closest
      // thing again, so goal-seeking turns her back north. Arriving, nothing
      // is closer. Each cell argues the opposite of its neighbour, and she
      // buzzes on the boundary between them — on screen, a dog who cannot make
      // up her mind, with the direction arrow strobing between two tiles.
      final grid = _field(
        cleared: const [
          HexCoord.zero,
          HexCoord(0, -1),
          HexCoord(0, 1),
          HexCoord(0, 2),
        ],
      );
      final dog = Dog(
        position: _layout.toPixel(HexCoord.zero),
        cell: HexCoord.zero,
      );

      const dt = 1 / 60;
      final changedAt = <double>[];
      final chosen = <HexCoord?>[];
      var fastestReversal = double.infinity;
      var elapsed = 0.0;
      while (elapsed < 8) {
        elapsed += dt;
        dog.update(
          dt: dt,
          grid: grid,
          layout: _layout,
          tuning: TuningConfig(),
          fieldVersion: 1,
          regrowthActive: false,
        );
        final target = dog.steerTarget;
        if (chosen.isEmpty || chosen.last != target) {
          // A reversal is her going back to the choice before last: the shape
          // of a loop rather than of a journey.
          if (chosen.length >= 2 && chosen[chosen.length - 2] == target) {
            final gap = elapsed - changedAt.last;
            if (gap < fastestReversal) {
              fastestReversal = gap;
            }
          }
          chosen.add(target);
          changedAt.add(elapsed);
        }
      }

      expect(
        fastestReversal,
        greaterThan(0.5),
        reason: 'she reversed her mind mid-stride, which reads as a stutter',
      );
      // Two pieces of fresh ground, so at most a couple of round trips before
      // there is nothing left to look at.
      expect(
        chosen.length,
        lessThan(12),
        reason: 'she changed her mind ${chosen.length} times in eight seconds',
      );
      expect(
        dog.nowhereToGo,
        isTrue,
        reason: 'having looked everywhere, she should be waiting, not pacing',
      );
    });

    test('a side branch she declined does not fetch her back, cell by cell', () {
      // The bug this guards: she walks a corridor north to its head, finds
      // nothing closer to the food, and sets off to investigate a branch she
      // walked straight past three cells ago. Arriving one cell into it, the
      // corridor head is closer to the food again, so she turns round and
      // walks all the way back — and there she finds the *second* cell of the
      // branch just as unvisited as the first was, and sets off again.
      //
      // One round trip of the whole board per cell of side branch, forever,
      // with nothing the player did to cause any of it. With the field closing
      // in behind her, one of those crossings is where she gets sealed in.
      final grid = _field(
        cleared: const [
          HexCoord(0, 0),
          HexCoord(0, -1),
          HexCoord(0, -2),
          HexCoord(0, -3),
          HexCoord(1, -1),
          HexCoord(2, -1),
          HexCoord(3, -1),
        ],
      );
      final dog = Dog(
        position: _layout.toPixel(HexCoord.zero),
        cell: HexCoord.zero,
      );

      const dt = 1 / 60;
      var crossings = 0;
      var wasAtHead = false;
      for (var i = 0; i < 60 * 20; i++) {
        dog.update(
          dt: dt,
          grid: grid,
          layout: _layout,
          tuning: TuningConfig(),
          fieldVersion: 1,
          regrowthActive: false,
        );
        final atHead = dog.cell == const HexCoord(0, -3);
        if (atHead && !wasAtHead) {
          crossings++;
        }
        wasAtHead = atHead;
      }

      expect(
        crossings,
        1,
        reason: 'she walked the corridor $crossings times over unchanged ground',
      );
      expect(
        dog.cell,
        const HexCoord(0, -3),
        reason: 'she should be waiting on the best ground her pocket has',
      );
      expect(
        dog.nowhereToGo,
        isTrue,
        reason: 'the branch is ground she already declined, not a reason to move',
      );
    });

    test('an investigation yields to ground that actually beats it', () {
      // The commitment must not become stubbornness: the moment the player
      // opens something closer to the food than the best the pocket held, she
      // turns on the spot.
      final grid = _field(cleared: const [HexCoord.zero, HexCoord(0, -1)]);
      final dog = Dog(
        position: _layout.toPixel(HexCoord.zero),
        cell: HexCoord.zero,
      );

      const dt = 1 / 60;
      var version = 1;
      void run(double seconds, {bool Function()? until}) {
        for (var i = 0; i < 60 * seconds; i++) {
          dog.update(
            dt: dt,
            grid: grid,
            layout: _layout,
            tuning: TuningConfig(),
            fieldVersion: version,
            regrowthActive: false,
          );
          if (until != null && until()) {
            return;
          }
        }
      }

      // Let her walk to the head of the corridor and run out of road.
      run(4);

      // The player carves south, away from the food. Ground that has just
      // appeared is the only thing that starts an investigation, so the tap
      // has to come after she has settled — see [Dog]'s offered set.
      grid.at(const HexCoord(0, 1))!.clear(0);
      grid.at(const HexCoord(0, 2))!.clear(0);
      version++;

      var committed = false;
      run(
        4,
        until: () {
          final target = dog.steerTarget;
          committed =
              target != null &&
              grid.distanceToExit(target) > grid.distanceToExit(dog.cell);
          return committed;
        },
      );
      expect(
        committed,
        isTrue,
        reason: 'this test needs her walking away from the food to mean it',
      );

      // The player carves north, past the dead end.
      grid.at(const HexCoord(0, -2))!.clear(0);
      version++;
      for (var i = 0; i < 60; i++) {
        dog.update(
          dt: dt,
          grid: grid,
          layout: _layout,
          tuning: TuningConfig(),
          fieldVersion: version,
          regrowthActive: false,
        );
      }
      expect(
        grid.distanceToExit(dog.steerTarget!),
        lessThan(grid.distanceToExit(HexCoord.zero)),
        reason: 'a tap that makes progress must turn her round at once',
      );
    });

    test('holds its last facing while stationary', () {
      final grid = _field(cleared: const [HexCoord.zero]);
      final dog = Dog(
        position: _layout.toPixel(HexCoord.zero),
        cell: HexCoord.zero,
      )..facing = 0.63;

      _run(dog, grid, TuningConfig(), seconds: 3);

      expect(dog.speed, lessThan(1.0));
      expect(
        dog.facing,
        closeTo(0.63, 1e-9),
        reason: 'an idle sprite must not swivel toward a nearby wall',
      );
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
