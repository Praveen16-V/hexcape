import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/components/effects_component.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';

HexcapeGame _game() {
  final game = HexcapeGame(tuning: TuningConfig())
    ..onGameResize(Vector2(390, 844))
    ..startLevel(level: 45);
  game
    ..phase = GamePhase.playing
    ..banner = null
    ..bannerFor = 0
    ..tutorial = null
    ..pickups = const [];
  for (final cell in game.grid.all) {
    cell
      ..type = HexType.plain
      ..revealed = false;
  }
  return game;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('contextual proximity hints', () {
    test('revealed mechanics trigger within two rings and only once', () {
      final game = _game();
      final target = game.dog.cell.neighbours.firstWhere(game.grid.contains);
      game.grid.at(target)!
        ..type = HexType.thorn
        ..revealed = false;

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull, reason: 'fog must not be spoiled');

      game.grid.at(target)!.revealed = true;
      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice?.hex, HexType.thorn);
      expect(game.proximityNoticeFor, HexcapeGame.proximityNoticeSeconds);

      game
        ..proximityNotice = null
        ..proximityNoticeFor = 0;
      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull, reason: 'each type teaches once');
    });

    test('dangerous ground wins over a nearby power-up', () {
      final game = _game();
      final target = game.dog.cell.neighbours.firstWhere(game.grid.contains);
      game.grid.at(target)!
        ..type = HexType.alarm
        ..revealed = true;
      game.pickups = [Pickup(PickupKind.freeze, game.dog.cell)];

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice?.hex, HexType.alarm);
      expect(game.proximityNotice?.pickup, isNull);
    });

    test('a mechanic outside two rings does not trigger', () {
      final game = _game();
      final target = game.grid.all.firstWhere(
        (cell) => cell.coord.distanceTo(game.dog.cell) > 2,
      );
      target
        ..type = HexType.anchor
        ..revealed = true;

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull);
    });

    test('tutorials and important banners suppress proximity hints', () {
      final game = _game();
      final target = game.dog.cell.neighbours.firstWhere(game.grid.contains);
      game.grid.at(target)!
        ..type = HexType.heavy
        ..revealed = true;
      game.banner = 'Important';

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull);
    });
  });

  group('pickup confirmation', () {
    test('every power-up gets a one-second typed confirmation', () {
      for (final kind in PickupKind.values.where((kind) => kind.isPowerup)) {
        final game = _game();
        game.debugTakePickup(Pickup(kind, game.dog.cell));
        expect(game.pickupNotice?.pickup, kind, reason: kind.name);
        expect(game.pickupNoticeFor, HexcapeGame.pickupNoticeSeconds);
      }
    });

    test('food remains a resource receipt instead of a power-up flash', () {
      final game = _game();
      game.debugTakePickup(Pickup(PickupKind.treat, game.dog.cell));
      expect(game.pickupNotice, isNull);
      expect(game.foodReceipt, isNotNull);
    });
  });

  group('victory bones', () {
    test('the full shower is capped and expires', () {
      final effects = EffectsComponent();
      effects.boneShower(Offset.zero, 20, reducedMotion: false);
      effects.boneShower(Offset.zero, 20, reducedMotion: false);
      expect(effects.boneCount, inInclusiveRange(30, 36));
      effects.update(2);
      expect(effects.boneCount, 0);
    });

    test('reduced motion uses a short eight-bone burst', () {
      final effects = EffectsComponent();
      effects.boneShower(Offset.zero, 20, reducedMotion: true);
      expect(effects.boneCount, 8);
      effects.update(0.5);
      expect(effects.boneCount, 0);
    });
  });
}
