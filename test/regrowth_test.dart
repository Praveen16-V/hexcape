import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/systems/regrowth_system.dart';

/// A solid field of the given radius, with [cleared] already open.
HexGrid _field({int radius = 5, Iterable<HexCoord> cleared = const []}) {
  final coords = HexCoord.zero.disc(radius);
  final grid = HexGrid(
    cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
    start: HexCoord.zero,
    exit: coords.last,
    truePath: [HexCoord.zero, coords.last],
  );
  for (final c in cleared) {
    grid.at(c)!.clear(0);
  }
  return grid;
}

/// Runs the system forward and records when each cell turned solid again.
Map<HexCoord, double> _simulate(
  HexGrid grid,
  TuningConfig tuning, {
  required double seconds,
  HexCoord dogCell = const HexCoord(99, 99),
}) {
  final system = RegrowthSystem();
  final solidAt = <HexCoord, double>{};
  const dt = 1 / 60;
  var now = 0.0;

  while (now < seconds) {
    now += dt;
    final events = system.update(
      dt: dt,
      now: now,
      grid: grid,
      tuning: tuning,
      dogCell: dogCell,
    );
    for (final coord in events.snapped) {
      solidAt.putIfAbsent(coord, () => now);
    }
  }
  return solidAt;
}

void main() {
  group('RegrowthSystem', () {
    test('a cell surrounded by open cells never starts regrowing', () {
      // §2.3 is explicit that regrowth works inward from the outside of the
      // cleared area. An interior cell has no exposed edge to grow from.
      final cleared = HexCoord.zero.disc(2);
      final grid = _field(cleared: cleared);
      final tuning = TuningConfig()..regrowDelay = 0.5;

      // Long enough for the exposed outer ring to warn and close
      // (delay + animation), but well short of ring 1 following it in.
      final solidAt = _simulate(grid, tuning, seconds: 2.4);

      expect(solidAt.containsKey(HexCoord.zero), isFalse);
      expect(grid.at(HexCoord.zero)!.eligibleSince, isNull);
      // The exposed outer ring, by contrast, has already closed.
      expect(solidAt.keys.every((c) => c.distanceTo(HexCoord.zero) == 2), true);
      expect(solidAt, isNotEmpty);
    });

    test('a cleared pocket closes strictly from the outside in', () {
      final grid = _field(cleared: HexCoord.zero.disc(2));
      final tuning = TuningConfig()..regrowDelay = 1.0;

      final solidAt = _simulate(grid, tuning, seconds: 12);

      double latestOfRing(int ring) => solidAt.entries
          .where((e) => e.key.distanceTo(HexCoord.zero) == ring)
          .map((e) => e.value)
          .reduce((a, b) => a > b ? a : b);
      double earliestOfRing(int ring) => solidAt.entries
          .where((e) => e.key.distanceTo(HexCoord.zero) == ring)
          .map((e) => e.value)
          .reduce((a, b) => a < b ? a : b);

      expect(solidAt.length, HexCoord.discSize(2));
      expect(latestOfRing(2), lessThan(earliestOfRing(1)));
      expect(latestOfRing(1), lessThan(earliestOfRing(0)));
    });

    test('an interior cell gets a full delay once it becomes exposed', () {
      // The delay is measured from becoming a boundary cell, not from being
      // cleared. Otherwise a long-buried cell would snap shut the instant its
      // neighbour closed, with no warning at all.
      final grid = _field(cleared: HexCoord.zero.disc(2));
      final tuning = TuningConfig()..regrowDelay = 1.0;

      final solidAt = _simulate(grid, tuning, seconds: 12);
      final ringTwo = solidAt.entries
          .where((e) => e.key.distanceTo(HexCoord.zero) == 2)
          .map((e) => e.value)
          .reduce((a, b) => a > b ? a : b);
      final centre = solidAt[HexCoord.zero]!;

      // Ring 1 has to wait a full delay plus its animation after ring 2 seals,
      // and the centre waits again behind ring 1.
      expect(
        centre - ringTwo,
        greaterThan(2 * (1.0 + RegrowAnim.duration) - 0.1),
      );
    });

    test(
      'the cell under the dog holds at the last pulse instead of closing',
      () {
        // Fairness rule from §10: the player is always shown the warning and
        // always has a way out. Being boxed in is a separate, timed failure.
        final grid = _field(cleared: HexCoord.zero.disc(1));
        final tuning = TuningConfig()..regrowDelay = 0.4;

        final solidAt = _simulate(
          grid,
          tuning,
          seconds: 10,
          dogCell: HexCoord.zero,
        );

        expect(solidAt.containsKey(HexCoord.zero), isFalse);
        final centre = grid.at(HexCoord.zero)!;
        expect(centre.state, CellState.regrowing);
        expect(centre.regrowT, closeTo(RegrowAnim.dogHold, 1e-9));
        // Everything around it closed normally.
        expect(solidAt.length, 6);
      },
    );

    test('every cell is warned before it blocks anything', () {
      final grid = _field(cleared: HexCoord.zero.disc(1));
      final tuning = TuningConfig()..regrowDelay = 0.3;
      final system = RegrowthSystem();

      final warned = <HexCoord>{};
      final snapped = <HexCoord>[];
      var now = 0.0;
      const dt = 1 / 60;
      while (now < 6) {
        now += dt;
        final events = system.update(
          dt: dt,
          now: now,
          grid: grid,
          tuning: tuning,
          dogCell: const HexCoord(99, 99),
        );
        warned.addAll(events.warned);
        for (final coord in events.snapped) {
          expect(
            warned.contains(coord),
            isTrue,
            reason: '$coord closed without a warning pulse',
          );
          snapped.add(coord);
        }
      }
      expect(
        snapped.toSet(),
        hasLength(snapped.length),
        reason: 'double-close',
      );
      expect(snapped, isNotEmpty);
    });

    test('zen mode reopens anything mid-regrowth and stops the clock', () {
      final grid = _field(cleared: HexCoord.zero.disc(1));
      final tuning = TuningConfig()..regrowDelay = 0.2;
      final system = RegrowthSystem();

      // Run to a point where the ring is mid-animation: past the delay, but
      // not yet far enough through RegrowAnim.duration to have closed.
      const dt = 1 / 60;
      var now = 0.0;
      while (now < 0.6) {
        now += dt;
        system.update(
          dt: dt,
          now: now,
          grid: grid,
          tuning: tuning,
          dogCell: const HexCoord(99, 99),
        );
      }
      expect(
        grid.all.any((c) => c.state == CellState.regrowing),
        isTrue,
        reason: 'nothing was regrowing, so the test proves nothing',
      );

      system.settleForZen(grid);

      expect(grid.all.any((c) => c.state == CellState.regrowing), isFalse);
      expect(grid.all.every((c) => c.eligibleSince == null), isTrue);
    });
  });
}
