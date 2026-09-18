import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/mechanic_roster.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/ui/reference_sheet.dart';

import 'sim/simulated_player.dart' show specFor;

void main() {
  test('the active roster has ten tiles and ten powers plus treats', () {
    expect(MechanicRoster.tiles.length, 10);
    expect(MechanicRoster.powerups.length, 10);
    expect(MechanicRoster.pickups.length, 11);
    expect(MechanicRoster.tiles, contains(HexType.plain));
    expect(MechanicRoster.pickups, contains(PickupKind.treat));
    expect(MechanicRoster.powerups, isNot(contains(PickupKind.treat)));
    expect(MechanicRoster.tiles, isNot(contains(HexType.slope)));
    expect(Campaign.poolFor(120).toSet(), MechanicRoster.powerups);
  });

  test('the campaign and endless rules offer only active mechanics', () {
    for (var n = 1; n <= Campaign.length + 20; n++) {
      for (final difficulty in Difficulty.values) {
        final rules = Campaign.rulesFor(n, difficulty: difficulty);
        expect(rules.slopeDensity, 0, reason: 'level $n');
        expect(rules.gatePairs, 0, reason: 'level $n');
        expect(rules.mirrorPairs, 0, reason: 'level $n');
        expect(
          rules.offeredPowerups.every(MechanicRoster.pickups.contains),
          isTrue,
          reason: 'level $n',
        );
      }
    }
  });

  test('generated levels and the reference show only active symbols', () {
    for (final n in [
      for (var level = 1; level <= Campaign.length; level++) level,
      120,
    ]) {
      final level = LevelGenerator.generate(specFor(Campaign.rulesFor(n)));
      expect(
        level.grid.all.every(
          (cell) => MechanicRoster.tiles.contains(cell.type),
        ),
        isTrue,
        reason: 'level $n tiles',
      );
      expect(
        level.pickups.every(
          (pickup) => MechanicRoster.pickups.contains(pickup.kind),
        ),
        isTrue,
        reason: 'level $n pickups',
      );
    }
    final entries = referenceFor(Campaign.length);
    expect(entries.where((e) => e.hex != null).length, 10);
    expect(entries.where((e) => e.pickup != null).length, 11);
  });
}
