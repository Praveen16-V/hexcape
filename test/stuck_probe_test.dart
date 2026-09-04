import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/systems/regrowth_system.dart';

const _layout = HexLayout(size: 22, origin: Offset(400, 400));

/// Carves a zigzag one cell at a time, just ahead of her, with regrowth
/// running — which is what actually happens in play, unlike a pre-cleared
/// corridor.
void main() {
  test('a fresh opening always gets her moving', () {
    // The promise the game rests on: you do not steer her, you create the
    // reason she moves. A tap that opens a cell beside her must produce motion
    // even when that cell is no closer to the bone — carving sideways around a
    // wall the fog is hiding is completely routine.
    final coords = HexCoord.zero.disc(10);
    final grid = HexGrid(
      cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
      start: HexCoord.zero,
      exit: const HexCoord(0, -8),
      truePath: const [HexCoord.zero, HexCoord(0, -8)],
    );
    grid.at(HexCoord.zero)!.clear(0);
    grid.at(const HexCoord(1, 0))!.clear(0);

    final dog = Dog(
      position: _layout.toPixel(HexCoord.zero),
      cell: HexCoord.zero,
    );
    final tuning = TuningConfig();
    final seen = <HexCoord>{};
    for (var i = 0; i < 60 * 6; i++) {
      dog.update(
        dt: 1 / 60,
        grid: grid,
        layout: _layout,
        tuning: tuning,
        fieldVersion: 1,
        regrowthActive: false,
      );
      seen.add(dog.cell);
    }
    expect(
      seen.contains(const HexCoord(1, 0)),
      isTrue,
      reason: 'she never entered the only opening she was given',
    );
  });

  test('progressive zigzag with regrowth', () {
    final exit = const HexCoord(3, -6);
    final route = <HexCoord>[
      const HexCoord(0, 0),
      const HexCoord(1, -1),
      const HexCoord(1, -2),
      const HexCoord(2, -3),
      const HexCoord(2, -4),
      const HexCoord(3, -5),
      exit,
    ];
    final coords = HexCoord.zero.disc(10);
    final grid = HexGrid(
      cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
      start: HexCoord.zero,
      exit: exit,
      truePath: route,
    );
    grid.at(HexCoord.zero)!.clear(0);

    final dog = Dog(
      position: _layout.toPixel(HexCoord.zero),
      cell: HexCoord.zero,
    );
    final tuning = TuningConfig();
    final regrowth = RegrowthSystem();

    const dt = 1 / 60;
    var now = 0.0;
    var fieldVersion = 1;
    var carved = 1;
    var stall = 0;
    var worstStall = 0;
    var worstAt = HexCoord.zero;

    while (now < 45) {
      now += dt;
      // Player carves the next route cell whenever she is within two cells.
      if (carved < route.length &&
          dog.cell.distanceTo(route[carved]) <= 2 &&
          grid.isClearable(route[carved])) {
        grid.at(route[carved])!.clear(now);
        carved++;
        fieldVersion++;
      }

      dog.update(
        dt: dt,
        grid: grid,
        layout: _layout,
        tuning: tuning,
        fieldVersion: fieldVersion,
        regrowthActive: true,
      );
      final events = regrowth.update(
        dt: dt,
        now: now,
        grid: grid,
        tuning: tuning,
        dogCell: dog.cell,
      );
      if (events.fieldChanged) fieldVersion++;

      final open = Pathfinder.floodDepths(
        dog.cell,
        grid.isPassable,
        maxDepth: 2,
      );
      final hasSomewhereToGo = open.length > 1;
      if (dog.speed < 2 && hasSomewhereToGo) {
        stall++;
        if (stall > worstStall) {
          worstStall = stall;
          worstAt = dog.cell;
        }
      } else {
        stall = 0;
      }
      if (dog.cell == exit) break;
    }

    // ignore: avoid_print
    print(
      'progressive: ended ${dog.cell} target $exit carved $carved/${route.length} '
      't=${now.toStringAsFixed(1)}s '
      'worst stall ${(worstStall / 60).toStringAsFixed(2)}s at $worstAt',
    );
    expect(
      worstStall / 60,
      lessThan(1.0),
      reason: 'she stalled with an open cell beside her',
    );
    expect(dog.cell, exit);
  });
}
