import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/systems/softlock_system.dart';

HexGrid corridor(int length, {Set<int> anchors = const {}}) => HexGrid(
  cells: {
    for (var i = 0; i <= length; i++)
      HexCoord(i, 0): HexCell(
        HexCoord(i, 0),
        anchors.contains(i) ? HexType.anchor : HexType.plain,
      ),
  },
  start: HexCoord.zero,
  exit: HexCoord(length, 0),
  truePath: const [],
);

void main() {
  test('an affordable treat preserves a route beyond the current budget', () {
    final grid = corridor(4);
    final treat = Pickup(PickupKind.treat, const HexCoord(1, 0));
    final system = SoftlockSystem();
    bool locked() => system.check(
      grid: grid,
      dogCell: grid.start,
      fieldVersion: 1,
      tapsLeft: 2,
      pickups: [treat],
      treatTaps: 2,
    );
    expect(locked(), isFalse);
    expect(
      treat.collected,
      isFalse,
      reason: 'the search cannot collect prizes',
    );
    expect(grid.at(treat.coord)!.isSolid, isTrue);
    treat.collected = true;
    expect(locked(), isTrue, reason: 'collection must invalidate the cache');
  });

  test('a second treat can become affordable after the first', () {
    final grid = corridor(5);
    expect(
      SoftlockSystem().check(
        grid: grid,
        dogCell: grid.start,
        fieldVersion: 1,
        tapsLeft: 1,
        treatTaps: 2,
        pickups: [
          Pickup(PickupKind.treat, const HexCoord(3, 0)),
          Pickup(PickupKind.treat, const HexCoord(1, 0)),
        ],
      ),
      isFalse,
    );
  });

  test('one treat cannot be credited repeatedly', () {
    final grid = corridor(6);
    expect(
      SoftlockSystem().check(
        grid: grid,
        dogCell: grid.start,
        fieldVersion: 1,
        tapsLeft: 1,
        treatTaps: 2,
        pickups: [Pickup(PickupKind.treat, const HexCoord(1, 0))],
      ),
      isTrue,
    );
  });

  test('unaffordable or sealed treats cannot rescue the budget', () {
    for (final grid in [
      corridor(5),
      corridor(5, anchors: {1}),
    ]) {
      expect(
        SoftlockSystem().check(
          grid: grid,
          dogCell: grid.start,
          fieldVersion: 1,
          tapsLeft: 1,
          treatTaps: 10,
          pickups: [Pickup(PickupKind.treat, const HexCoord(2, 0))],
        ),
        isTrue,
      );
    }
  });

  test('zero taps can recover through a treat on already open ground', () {
    final grid = corridor(2);
    grid.at(const HexCoord(1, 0))!.clear(0);
    expect(
      SoftlockSystem().check(
        grid: grid,
        dogCell: grid.start,
        fieldVersion: 1,
        tapsLeft: 0,
        treatTaps: 1,
        pickups: [Pickup(PickupKind.treat, const HexCoord(1, 0))],
      ),
      isFalse,
    );
  });

  test('held blast preserves a heavy cluster, but still needs a tap', () {
    final grid = corridor(2);
    grid.at(const HexCoord(1, 0))!.type = HexType.heavy;
    final system = SoftlockSystem();
    for (final taps in [1, 0]) {
      expect(
        system.check(
          grid: grid,
          dogCell: grid.start,
          fieldVersion: 1,
          tapsLeft: taps,
          blastCharges: 1,
        ),
        taps == 0,
      );
    }
  });

  test('blast savings are bounded and cannot remove anchors', () {
    for (final grid in [
      corridor(16),
      corridor(2, anchors: {1}),
    ]) {
      expect(
        SoftlockSystem().check(
          grid: grid,
          dogCell: grid.start,
          fieldVersion: 1,
          tapsLeft: 1,
          blastCharges: 1,
        ),
        isTrue,
      );
    }
  });

  test('dig inventory opens only as many walls as charges held', () {
    final grid = corridor(3, anchors: {1, 2});
    final system = SoftlockSystem();
    for (final digs in [1, 2, 0]) {
      expect(
        system.check(
          grid: grid,
          dogCell: grid.start,
          fieldVersion: 1,
          tapsLeft: 3,
          digCharges: digs,
        ),
        digs < 2,
        reason: 'changing inventory must invalidate the cache',
      );
    }
    expect(grid.isAnchor(const HexCoord(1, 0)), isTrue);
  });

  test('a reachable dig pickup can restore a route through an anchor', () {
    final grid = corridor(3, anchors: {2});
    expect(
      SoftlockSystem().check(
        grid: grid,
        dogCell: grid.start,
        fieldVersion: 1,
        tapsLeft: 3,
        pickups: [Pickup(PickupKind.dig, const HexCoord(1, 0))],
      ),
      isFalse,
    );
  });

  test('a reachable blast pickup can restore an unaffordable route', () {
    final grid = corridor(3);
    expect(
      SoftlockSystem().check(
        grid: grid,
        dogCell: grid.start,
        fieldVersion: 1,
        tapsLeft: 2,
        pickups: [Pickup(PickupKind.blast, const HexCoord(1, 0))],
      ),
      isFalse,
    );
  });

  test('time-only powerups cannot pay for a route', () {
    final grid = corridor(4);
    expect(
      SoftlockSystem().check(
        grid: grid,
        dogCell: grid.start,
        fieldVersion: 1,
        tapsLeft: 1,
        pickups: [
          for (final kind in [
            PickupKind.freeze,
            PickupKind.sprint,
            PickupKind.treat,
          ])
            Pickup(kind, const HexCoord(1, 0)),
        ],
        treatTaps: 0,
      ),
      isTrue,
    );
  });

  test('a new board and changed treat value invalidate cached losses', () {
    final system = SoftlockSystem();
    final grid = corridor(3);
    bool check(HexGrid board, int reward) => system.check(
      grid: board,
      dogCell: board.start,
      fieldVersion: 1,
      tapsLeft: 1,
      pickups: [Pickup(PickupKind.treat, const HexCoord(1, 0))],
      treatTaps: reward,
    );
    expect(check(grid, 1), isTrue);
    expect(check(grid, 2), isFalse);
    expect(check(corridor(8), 2), isTrue);
  });
}
