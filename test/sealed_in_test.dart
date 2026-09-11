import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/systems/regrowth_system.dart';

const _layout = HexLayout(size: 22, origin: Offset(400, 400));

void main() {
  test('a tile closing over her ends the run rather than trapping her', () {
    // The player asked whether this should be game over. It should, and this
    // pins down that it is: her own cell holds short of snapping shut (the
    // fairness rule), but once every way out is sealed the grace period runs
    // and the field crushes her.
    final coords = HexCoord.zero.disc(4);
    final grid = HexGrid(
      cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
      start: HexCoord.zero,
      exit: const HexCoord(0, -4),
      truePath: const [HexCoord.zero, HexCoord(0, -4)],
    );
    for (final c in HexCoord.zero.disc(1)) {
      grid.at(c)!.clear(0);
    }

    final dog = Dog(
      position: _layout.toPixel(HexCoord.zero),
      cell: HexCoord.zero,
    );
    final tuning = TuningConfig()..regrowDelay = 0.3;
    final regrowth = RegrowthSystem();

    const dt = 1 / 60;
    var now = 0.0;
    var crushedAt = -1.0;

    while (now < 20) {
      now += dt;
      dog.update(
        dt: dt,
        grid: grid,
        layout: _layout,
        tuning: tuning,
        fieldVersion: 1,
        regrowthActive: true,
      );
      regrowth.update(
        dt: dt,
        now: now,
        grid: grid,
        tuning: tuning,
        dogCell: dog.cell,
        dogOccupiedCells: dog.occupiedCells(_layout),
      );
      if (dog.enclosedFor >= tuning.suffocateSeconds && crushedAt < 0) {
        crushedAt = now;
        break;
      }
    }

    // ignore: avoid_print
    print(
      'sealed in: crushed at ${crushedAt.toStringAsFixed(1)}s, '
      'her own cell is ${grid.at(dog.cell)!.state.name}',
    );

    expect(crushedAt, greaterThan(0), reason: 'she was never crushed at all');
    expect(
      grid.at(dog.cell)!.isSolid,
      isFalse,
      reason:
          'the cell under her must never finish closing — that is the '
          'fairness rule that guarantees she can always be tapped out',
    );
  });

  test('a hole exactly her own size still ends the run', () {
    // The reported level-11 failure. Regrowth holds every cell she occupies
    // short of the snap so she is never crushed without warning — and while
    // she straddles a shared edge, that is *two* cells. Neither can ever
    // finish closing, so the pocket stays passable forever; the boxed-in test
    // asked only whether her centre cell's six neighbours were solid, said no,
    // and the grace period never started. She stood wedged between two tiles
    // with taps left and no way to spend them, and nothing ended the run but
    // the hunger clock.
    final coords = HexCoord.zero.disc(4);
    final grid = HexGrid(
      // Rivets, so no tap could rescue her even if the player found one: the
      // pocket is the whole board as far as she is concerned.
      cells: {for (final c in coords) c: HexCell(c, HexType.anchor)},
      start: HexCoord.zero,
      exit: const HexCoord(0, -4),
      truePath: const [HexCoord.zero, HexCoord(0, -4)],
    );
    final here = HexCoord.zero;
    final beside = HexCoord.directions[0];
    for (final c in [here, beside]) {
      grid.at(c)!
        ..type = HexType.plain
        ..clear(0);
    }

    // Parked on the shared edge, which is where the collision depenetration
    // leaves her when a cell snaps shut against her.
    final dog = Dog(
      position: (_layout.toPixel(here) + _layout.toPixel(beside)) / 2,
      cell: here,
    )..hasBeenFree = true;
    final tuning = TuningConfig()..regrowDelay = 0.3;
    final regrowth = RegrowthSystem();

    const dt = 1 / 60;
    var now = 0.0;
    while (now < 30 && dog.enclosedFor < tuning.suffocateSeconds) {
      now += dt;
      dog.update(
        dt: dt,
        grid: grid,
        layout: _layout,
        tuning: tuning,
        fieldVersion: 1,
        regrowthActive: true,
      );
      regrowth.update(
        dt: dt,
        now: now,
        grid: grid,
        tuning: tuning,
        dogCell: dog.cell,
        dogOccupiedCells: dog.occupiedCells(_layout),
      );
    }

    expect(
      dog.occupiedCells(_layout),
      hasLength(2),
      reason: 'the test is only meaningful while she is holding both cells',
    );
    expect(
      dog.enclosedFor,
      greaterThanOrEqualTo(tuning.suffocateSeconds),
      reason: 'she had nowhere to step and the run never ended',
    );
    expect(
      grid.at(dog.cell)!.isSolid,
      isFalse,
      reason: 'the fairness rule still holds: the ground under her never snaps',
    );
  });
}
