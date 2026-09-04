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
}
