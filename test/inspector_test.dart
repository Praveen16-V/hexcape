import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/ui/level_detail.dart';
import 'package:hexcape/ui/reference_sheet.dart';

const _size = Size(390, 844);

HexcapeGame makeGame({int level = 45}) => HexcapeGame(tuning: TuningConfig())
  ..onGameResize(Vector2(_size.width, _size.height))
  ..startLevel(level: level);

/// Hold a finger on the tile at [coord]. Flame delivers a long tap only to
/// components that already took the tap-down, so this is the real sequence.
void holdOn(HexcapeGame game, HexCoord coord) {
  game.onLongTapDown(
    TapDownEvent(
      0,
      game,
      TapDownDetails(
        globalPosition: game.layout.toPixel(coord),
        localPosition: game.layout.toPixel(coord),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Every mechanic can be looked up', () {
    test('no tile type or pickup is without an explanation', () {
      for (final type in HexType.values) {
        expect(
          referenceForHex(type),
          isNotNull,
          reason: '$type has no reference entry to show',
        );
        expect(referenceForHex(type)!.blurb, isNotEmpty);
      }
      for (final kind in PickupKind.values) {
        expect(
          referenceForPickup(kind),
          isNotNull,
          reason: '$kind has no reference entry to show',
        );
        expect(referenceForPickup(kind)!.blurb, isNotEmpty);
      }
    });

    test('the lookups return the entry the sheet itself would show', () {
      for (final entry in allReferenceEntries) {
        if (entry.hex != null) {
          expect(referenceForHex(entry.hex!), same(entry));
        }
        if (entry.pickup != null) {
          expect(referenceForPickup(entry.pickup!), same(entry));
        }
      }
    });
  });

  group('Holding a tile', () {
    test('names a tile she has already seen', () {
      final game = makeGame();
      final coord = game.dog.cell;
      game.grid.at(coord)!.revealed = true;
      holdOn(game, coord);

      expect(game.inspecting, isNotNull);
      expect(game.inspecting!.hex, game.grid.at(coord)!.type);
      expect(game.inspectFor, greaterThan(0));
    });

    test('refuses to answer through the fog', () {
      final game = makeGame();
      // A cell she has not been near. Its type is exactly what the fog is for.
      final hidden = game.grid.all.firstWhere((c) => !c.revealed);
      holdOn(game, hidden.coord);

      expect(game.inspecting, isNotNull);
      expect(
        game.inspecting!.hex,
        isNull,
        reason: 'the fog hides what a tile is; the inspector must not undo it',
      );
    });

    test('a pickup on the ground answers before the ground does', () {
      final game = makeGame();
      final pickup = game.pickups.firstWhere((p) => !p.collected);
      game.grid.at(pickup.coord)!.revealed = true;
      holdOn(game, pickup.coord);

      expect(game.inspecting!.pickup, pickup.kind);
    });

    test('a hold off the board does nothing at all', () {
      final game = makeGame();
      game.onLongTapDown(
        TapDownEvent(
          0,
          game,
          TapDownDetails(
            globalPosition: Offset(-4000, -4000),
            localPosition: Offset(-4000, -4000),
          ),
        ),
      );
      expect(game.inspecting, isNull);
    });

    test('holding never costs a tap by itself', () {
      final game = makeGame();
      final before = game.taps;
      holdOn(game, game.dog.cell);
      expect(game.taps, before);
    });

    test('it fades on its own rather than waiting to be dismissed', () {
      final game = makeGame();
      game.grid.at(game.dog.cell)!.revealed = true;
      holdOn(game, game.dog.cell);
      expect(game.inspecting, isNotNull);

      for (var i = 0; i < 60 * 4; i++) {
        game.update(1 / 60);
      }
      expect(game.inspecting, isNull);
      expect(game.inspectFor, lessThanOrEqualTo(0));
    });

    test('a player who turned nudges off is not nudged', () {
      final game = makeGame();
      game.tuning.hintsEnabled = false;
      game.grid.at(game.dog.cell)!.revealed = true;
      holdOn(game, game.dog.cell);
      expect(game.inspecting, isNull);
    });
  });

  group('Holding a charge', () {
    test('says what the tool does', () {
      final game = makeGame();
      game.inspectPickup(PickupKind.stake);
      expect(game.inspecting!.pickup, PickupKind.stake);
      expect(referenceForPickup(PickupKind.stake), isNotNull);
    });

    test('respects the nudges setting too', () {
      final game = makeGame();
      game.tuning.hintsEnabled = false;
      game.inspectPickup(PickupKind.stake);
      expect(game.inspecting, isNull);
    });
  });

  group('The level brief names every pressure', () {
    Future<Set<String>> chipsFor(WidgetTester tester, LevelRules rules) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LevelContainsChips(rules: rules)),
        ),
      );
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toSet();
    }

    testWidgets('a Collapse level admits it has cracked ground', (
      tester,
    ) async {
      final rules = Campaign.rulesFor(Campaign.faultsFrom);
      expect(rules.faultDensity, greaterThan(0));
      expect(await chipsFor(tester, rules), contains('Cracked ground'));
    });

    testWidgets('a Vigil level admits it has sentries', (tester) async {
      final rules = Campaign.rulesFor(Campaign.sentriesFrom);
      expect(rules.sentries, greaterThan(0));
      expect(await chipsFor(tester, rules), contains('Warded lights'));
    });

    testWidgets('heavy ground is named wherever it exists', (tester) async {
      final rules = Campaign.rulesFor(30);
      expect(rules.heavyDensity, greaterThan(0));
      expect(await chipsFor(tester, rules), contains('Heavy ground'));
    });

    testWidgets('and a level without them says nothing about them', (
      tester,
    ) async {
      // Level one is the first lesson: bare ground, one idea.
      final rules = Campaign.rulesFor(1);
      final chips = await chipsFor(tester, rules);
      expect(chips, isNot(contains('Cracked ground')));
      expect(chips, isNot(contains('Warded lights')));
      expect(chips, isNot(contains('Patrols')));
    });
  });
}
