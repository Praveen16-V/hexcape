import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';

const _layout = HexLayout(size: 22, origin: Offset(400, 400));
const _dt = 1 / 60;

/// The reported level-11 failure, reduced to its shape: a three-cell pocket
/// she has walked out to the end of. Nothing reachable is closer to the bone
/// and nothing reachable is new, so steering correctly holds her exactly where
/// she is — and she stops dead, with the hunger bar the only thing still
/// moving on screen. That stop is right; being unable to tell it apart from a
/// hung game is the bug.
({HexGrid grid, Dog dog, TuningConfig tuning}) _deadEnd() {
  final coords = HexCoord.zero.disc(4);
  final grid = HexGrid(
    cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
    start: const HexCoord(0, 2),
    exit: const HexCoord(0, -4),
    truePath: const [HexCoord(0, 2), HexCoord(0, -4)],
  );
  // A pocket running away from the bone, so walking to its best cell means
  // walking every cell of it.
  for (final c in [const HexCoord(0, 2), const HexCoord(0, 1), HexCoord.zero]) {
    grid.at(c)!.clear(0);
  }
  // The wall between her and the bone: heavy, so a tap can answer it, and
  // nearer the food than anything else on the edge of the pocket.
  grid.at(const HexCoord(0, -1))!.type = HexType.heavy;
  return (
    grid: grid,
    dog: Dog(
      position: _layout.toPixel(const HexCoord(0, 2)),
      cell: const HexCoord(0, 2),
    ),
    tuning: TuningConfig(),
  );
}

void _step(HexGrid grid, Dog dog, TuningConfig tuning, int version) {
  dog.update(
    dt: _dt,
    grid: grid,
    layout: _layout,
    tuning: tuning,
    fieldVersion: version,
    regrowthActive: false,
  );
}

void main() {
  test('walking the pocket is never mistaken for having nowhere to go', () {
    final (:grid, :dog, :tuning) = _deadEnd();
    var sawFlag = false;
    for (var i = 0; i < 60 * 3 && dog.cell != HexCoord.zero; i++) {
      // Read before stepping: arriving at the end of the pocket is the moment
      // the flag is *supposed* to go up, and it goes up inside that same
      // frame. What must never happen is her carrying it while still walking.
      if (dog.nowhereToGo) sawFlag = true;
      _step(grid, dog, tuning, 1);
    }
    expect(
      dog.cell,
      HexCoord.zero,
      reason: 'she should walk to the end of the pocket nearest the bone',
    );
    expect(
      sawFlag,
      isFalse,
      reason: 'somewhere to go is somewhere to go, right up to arriving',
    );
    expect(dog.nowhereToGoFor, 0);
  });

  test('the end of the pocket is named rather than silently stood in', () {
    final (:grid, :dog, :tuning) = _deadEnd();
    for (var i = 0; i < 60 * 6; i++) {
      _step(grid, dog, tuning, 1);
    }

    expect(dog.cell, HexCoord.zero);
    expect(dog.speed, lessThan(1), reason: 'she is standing still');
    expect(
      dog.nowhereToGo,
      isTrue,
      reason: 'nothing reachable is closer to the bone and nothing is new',
    );
    expect(
      dog.nowhereToGoFor,
      greaterThan(1.0),
      reason: 'the HUD waits this out before speaking, so it has to accrue',
    );
    expect(
      dog.gazeTarget,
      const HexCoord(0, -1),
      reason: 'the wall a tap could open that stands nearest the bone',
    );

    // And she is looking at it: the sprite flips on the sign of cos(facing),
    // so a heading that points up the board has to actually arrive.
    final toWall = _layout.toPixel(dog.gazeTarget!) - dog.position;
    final wanted = math.atan2(toWall.dy, toWall.dx);
    var delta = dog.facing - wanted;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    expect(
      delta.abs(),
      lessThan(0.35),
      reason: 'she turns to face the wall she is waiting on, not away from it',
    );
  });

  test('a rivet wall is never pointed at as a way through', () {
    final (:grid, :dog, :tuning) = _deadEnd();
    // Nothing on the edge of the pocket a tap can touch. She is still waiting,
    // but there is no wall worth looking at, and promising one would lie.
    for (final c in grid.all) {
      if (!c.isPassable) c.type = HexType.anchor;
    }
    grid.invalidateTopology();
    for (var i = 0; i < 60 * 6; i++) {
      _step(grid, dog, tuning, 1);
    }
    expect(dog.nowhereToGo, isTrue);
    expect(dog.gazeTarget, isNull);
  });

  test('opening the wall she is waiting on puts her back on the move', () {
    final (:grid, :dog, :tuning) = _deadEnd();
    for (var i = 0; i < 60 * 6; i++) {
      _step(grid, dog, tuning, 1);
    }
    expect(dog.nowhereToGo, isTrue);

    // Two taps, because it is heavy — the wall she was looking at.
    final wall = grid.at(dog.gazeTarget!)!;
    wall.hit(0);
    expect(wall.hit(0), isTrue, reason: 'the second tap opens it');

    var walked = false;
    for (var i = 0; i < 60 * 3; i++) {
      _step(grid, dog, tuning, 2);
      if (dog.cell == const HexCoord(0, -1)) break;
      if (dog.speed > 1) walked = true;
      expect(
        dog.nowhereToGo,
        isFalse,
        reason: 'she stayed put with a freshly opened way in front of her',
      );
    }
    expect(
      walked,
      isTrue,
      reason: 'a tap that opens a way is a reason to move again',
    );
    expect(dog.cell, const HexCoord(0, -1));
    // And once she has walked into it, the new end of the pocket is named in
    // its turn rather than being another silent stop.
    for (var i = 0; i < 60 * 2; i++) {
      _step(grid, dog, tuning, 2);
    }
    expect(dog.nowhereToGo, isTrue);
    expect(dog.gazeTarget, const HexCoord(0, -2));
  });
}
