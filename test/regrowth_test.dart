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
  _stakeTests();
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

    test('all cells touched by the dog hold while she crosses an edge', () {
      const first = HexCoord.zero;
      const second = HexCoord(1, 0);
      final grid = _field(cleared: [first, second]);
      final tuning = TuningConfig()..regrowDelay = 0.1;
      final system = RegrowthSystem();
      var now = 0.0;

      for (var i = 0; i < 240; i++) {
        now += 1 / 60;
        system.update(
          dt: 1 / 60,
          now: now,
          grid: grid,
          tuning: tuning,
          dogCell: first,
          dogOccupiedCells: {first, second},
        );
      }

      expect(grid.at(first)!.state, CellState.regrowing);
      expect(grid.at(second)!.state, CellState.regrowing);
      expect(grid.at(first)!.regrowT, RegrowAnim.dogHold);
      expect(grid.at(second)!.regrowT, RegrowAnim.dogHold);

      // Once her body has cleared the edge, the old tile is allowed to close.
      for (var i = 0; i < 120; i++) {
        now += 1 / 60;
        system.update(
          dt: 1 / 60,
          now: now,
          grid: grid,
          tuning: tuning,
          dogCell: second,
          dogOccupiedCells: {second},
        );
      }
      expect(grid.at(first)!.isSolid, isTrue);
      expect(grid.at(second)!.isSolid, isFalse);
    });

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

  group('Cracked ground', () {
    /// The same field, with [faults] promoted before anything is cleared.
    HexGrid faultField({
      required Iterable<HexCoord> cleared,
      required Iterable<HexCoord> faults,
    }) {
      final coords = HexCoord.zero.disc(5);
      final grid = HexGrid(
        cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
        start: HexCoord.zero,
        exit: coords.last,
        truePath: [HexCoord.zero, coords.last],
      );
      for (final c in faults) {
        grid.at(c)!.type = HexType.fault;
      }
      for (final c in cleared) {
        grid.at(c)!.clear(0);
      }
      return grid;
    }

    test('an interior fault closes even with nothing solid beside it', () {
      // The whole mechanic, and the exact inverse of the first test in this
      // file: an interior *plain* cell can never close, and that is what makes
      // carving far ahead free. An interior fault closes on its own clock.
      final cleared = HexCoord.zero.disc(2);
      final grid = faultField(cleared: cleared, faults: [HexCoord.zero]);
      final tuning = TuningConfig()
        ..regrowDelay = 30
        ..faultDelay = 0.5;

      final solidAt = _simulate(grid, tuning, seconds: 3);

      expect(
        solidAt.containsKey(HexCoord.zero),
        isTrue,
        reason: 'the fault never closed',
      );
      // And nothing else did: the ordinary cells around it are nowhere near
      // their own delay, so this is the fault's clock and not regrowth's.
      expect(solidAt.keys, [HexCoord.zero]);
    });

    test('it still holds under the dog, so she is never sealed in', () {
      // The fairness rule the rest of regrowth already obeys. A fault that
      // closed on top of her would make the one mechanic that closes ahead of
      // her the one mechanic that can kill without warning.
      final grid = faultField(
        cleared: HexCoord.zero.disc(2),
        faults: [HexCoord.zero],
      );
      final tuning = TuningConfig()
        ..regrowDelay = 30
        ..faultDelay = 0.5;

      final solidAt = _simulate(
        grid,
        tuning,
        seconds: 4,
        dogCell: HexCoord.zero,
      );

      expect(solidAt, isEmpty);
      expect(grid.at(HexCoord.zero)!.state, CellState.regrowing);
      expect(grid.at(HexCoord.zero)!.regrowT, lessThanOrEqualTo(1.0));
    });

    test('it re-opens for one tap rather than becoming a wall', () {
      final grid = faultField(
        cleared: HexCoord.zero.disc(2),
        faults: [HexCoord.zero],
      );
      final tuning = TuningConfig()
        ..regrowDelay = 30
        ..faultDelay = 0.5;
      _simulate(grid, tuning, seconds: 3);

      final cell = grid.at(HexCoord.zero)!;
      expect(cell.isSolid, isTrue);
      expect(cell.type.hitsRequired, 1, reason: 'a fault is not a heavy');
      expect(cell.type.isClearableType, isTrue, reason: 'nor an anchor');
    });

    test('Zen switches it off with everything else', () {
      // `settleForZen` nulls `eligibleSince` on every cell, so faults are
      // covered without knowing they exist. Asserted because that is exactly
      // the kind of thing a later refactor quietly breaks.
      final grid = faultField(
        cleared: HexCoord.zero.disc(2),
        faults: [HexCoord.zero],
      );
      final tuning = TuningConfig()
        ..regrowDelay = 30
        ..faultDelay = 0.5;

      final system = RegrowthSystem();
      const dt = 1 / 60;
      var now = 0.0;
      for (var i = 0; i < 120; i++) {
        now += dt;
        system.update(
          dt: dt,
          now: now,
          grid: grid,
          tuning: tuning,
          dogCell: const HexCoord(99, 99),
        );
        system.settleForZen(grid);
      }

      expect(grid.at(HexCoord.zero)!.isSolid, isFalse);
    });
  });
}

/// STAKE: the tile that never closes again.
///
/// Verified against the regrowth system directly rather than through the game,
/// because the property that matters is not "the tap works" but "the cell is
/// out of the cycle for the rest of the run" — and a run is thousands of frames
/// during which any of three separate code paths could put it back in.
void _stakeTests() {
  group('Staked ground', () {
    HexGrid pinnedField({required HexType type, required bool pinned}) {
      final coords = HexCoord.zero.disc(5);
      final grid = HexGrid(
        cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
        start: HexCoord.zero,
        exit: coords.last,
        truePath: [HexCoord.zero, coords.last],
      );
      grid.at(HexCoord.zero)!.type = type;
      for (final c in HexCoord.zero.disc(2)) {
        grid.at(c)!.clear(0);
      }
      grid.at(HexCoord.zero)!.pinned = pinned;
      return grid;
    }

    test('a staked fault never closes, however long the run goes on', () {
      final grid = pinnedField(type: HexType.fault, pinned: true);
      final tuning = TuningConfig()
        ..regrowDelay = 0.4
        ..faultDelay = 0.3;

      // Sixty seconds is far longer than any real level.
      final solidAt = _simulate(grid, tuning, seconds: 60);

      expect(solidAt.containsKey(HexCoord.zero), isFalse);
      expect(grid.at(HexCoord.zero)!.isSolid, isFalse);
      expect(grid.at(HexCoord.zero)!.eligibleSince, isNull);
    });

    test('the same tile unstaked does close, so the test proves something', () {
      final grid = pinnedField(type: HexType.fault, pinned: false);
      final tuning = TuningConfig()
        ..regrowDelay = 0.4
        ..faultDelay = 0.3;

      final solidAt = _simulate(grid, tuning, seconds: 60);

      expect(solidAt.containsKey(HexCoord.zero), isTrue);
    });

    test('it also holds against ordinary regrowth, not just faults', () {
      // A staked tile on the boundary of the cleared area is the case a player
      // will actually reach for: the corridor behind them closing in.
      final grid = pinnedField(type: HexType.plain, pinned: true);
      // Expose it by walling everything around it back up.
      for (final c in HexCoord.zero.neighbours) {
        grid.at(c)!.resetToSolid();
      }
      final tuning = TuningConfig()..regrowDelay = 0.4;

      final solidAt = _simulate(grid, tuning, seconds: 30);

      expect(solidAt.containsKey(HexCoord.zero), isFalse);
    });
  });
}
