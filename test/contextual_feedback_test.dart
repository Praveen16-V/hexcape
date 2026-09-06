import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/components/effects_component.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';

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

/// A game whose dog is actually going somewhere.
///
/// A warning is about ground she has not reached, so none of it exists until
/// there is a route and a speed: an open field, and enough frames for her to
/// commit to a direction.
HexcapeGame _walking({int frames = 30}) {
  final game = _game();
  for (final cell in game.grid.all) {
    cell.clear(0);
  }
  const dt = 1 / 60;
  for (var i = 0; i < frames; i++) {
    game.dog.update(
      dt: dt,
      grid: game.grid,
      layout: game.layout,
      tuning: game.tuning,
      // Bumped every frame so the route is rebuilt rather than cached from a
      // field the test has since changed.
      fieldVersion: i + 1,
      regrowthActive: false,
    );
  }
  return game;
}

/// The first step along her route a warning is allowed to name, or -1.
int _hintableStep(HexcapeGame game, {int from = HexcapeGame.hintLookaheadFrom}) {
  final hexesPerSecond = game.dog.speed / game.layout.width;
  for (
    var step = from;
    step <= HexcapeGame.hintLookaheadTo && step < game.dog.route.length;
    step++
  ) {
    final lead = step / hexesPerSecond;
    if (lead >= HexcapeGame.hintLeadMin && lead <= HexcapeGame.hintLeadMax) {
      return step;
    }
  }
  return -1;
}

/// Puts [type] on her route [step] cells ahead and returns where it went.
HexCoord _placeAhead(HexcapeGame game, int step, HexType type) {
  final coord = game.dog.route[step];
  game.grid.at(coord)!
    ..type = type
    ..revealed = true;
  return coord;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('contextual proximity hints', () {
    test('a mechanic ahead on her route is named before she reaches it', () {
      final game = _walking();
      final step = _hintableStep(game);
      expect(step, greaterThanOrEqualTo(0), reason: 'she is going nowhere');
      final coord = _placeAhead(game, step, HexType.thorn);

      game.grid.at(coord)!.revealed = false;
      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull, reason: 'fog must not be spoiled');

      game.grid.at(coord)!.revealed = true;
      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice?.hex, HexType.thorn);
      expect(game.proximityNoticeFor, HexcapeGame.proximityNoticeSeconds);
      expect(
        game.dog.cell,
        isNot(coord),
        reason: 'a warning she has already walked into is a caption',
      );

      game
        ..proximityNotice = null
        ..proximityNoticeFor = 0;
      game.debugElapseHintGap();
      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull, reason: 'each type teaches once');
    });

    test('the ground she is standing on is never named', () {
      final game = _walking();
      game.grid.at(game.dog.cell)!
        ..type = HexType.thorn
        ..revealed = true;

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull);
    });

    test('a mechanic beside her but off her route is never named', () {
      // The old scan swept a disc, so anything within two rings triggered --
      // including ground she was walking away from, and ground she had just
      // left. Only the path ahead counts.
      final game = _walking();
      final ahead = game.dog.route.toSet();
      final aside = game.dog.cell
          .disc(2)
          .where((c) => !ahead.contains(c) && game.grid.contains(c))
          .first;
      game.grid.at(aside)!
        ..type = HexType.alarm
        ..revealed = true;

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull);
    });

    test('a mechanic further off than the lookahead does not trigger', () {
      final game = _walking();
      final step = game.dog.route.length - 1;
      expect(
        step,
        greaterThan(HexcapeGame.hintLookaheadTo),
        reason: 'route too short to have anything past the lookahead',
      );
      _placeAhead(game, step, HexType.anchor);

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull);
    });

    test('a dog standing still is warned about nothing', () {
      // She is approaching nothing, so there is nothing to react to -- and the
      // lead time this is all measured in does not exist at zero speed.
      final game = _walking();
      final step = _hintableStep(game);
      expect(step, greaterThanOrEqualTo(0));
      _placeAhead(game, step, HexType.spring);
      game.dog.velocity = Offset.zero;

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull);
    });

    test('the second warning waits for the gap', () {
      final game = _walking();
      final first = _hintableStep(game);
      expect(first, greaterThanOrEqualTo(0));
      final second = _hintableStep(game, from: first + 1);
      expect(second, greaterThan(first), reason: 'need two steps in window');
      _placeAhead(game, first, HexType.thorn);
      _placeAhead(game, second, HexType.alarm);

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice?.hex, HexType.thorn, reason: 'soonest first');

      game
        ..proximityNotice = null
        ..proximityNoticeFor = 0;
      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull, reason: 'two in a row is chatter');

      game.debugElapseHintGap();
      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice?.hex, HexType.alarm);
    });

    test('a power-up ahead is not announced before it is collected', () {
      // Nothing to react to in walking into something good, and the card on
      // collecting it already says what it does.
      final game = _walking();
      final step = _hintableStep(game);
      expect(step, greaterThanOrEqualTo(0));
      game.pickups = [Pickup(PickupKind.freeze, game.dog.route[step])];

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull);
    });

    test('tutorials and important banners suppress proximity hints', () {
      final game = _walking();
      final step = _hintableStep(game);
      expect(step, greaterThanOrEqualTo(0));
      _placeAhead(game, step, HexType.heavy);
      game.banner = 'Important';

      game.debugRefreshNearbyNotice();
      expect(game.proximityNotice, isNull);
    });
  });

  group('pickup confirmation', () {
    test('every power-up gets a typed confirmation', () {
      for (final kind in PickupKind.values.where((kind) => kind.isPowerup)) {
        final game = _game();
        game.debugTakePickup(Pickup(kind, game.dog.cell));
        expect(game.pickupNotice?.pickup, kind, reason: kind.name);
        expect(
          game.pickupNoticeFor,
          kind.isCharge
              ? HexcapeGame.chargeNoticeSeconds
              : HexcapeGame.pickupNoticeSeconds,
          reason: kind.name,
        );
      }
    });

    test('a charge instructs through the card, not through a banner', () {
      // The card already renders `readyHint` for charges. A banner repeating it
      // was the same sentence twice, and it silenced contextual hints for its
      // whole life.
      for (final kind in PickupKind.values.where((kind) => kind.isCharge)) {
        final game = _game();
        game.debugTakePickup(Pickup(kind, game.dog.cell));
        expect(game.banner, isNull, reason: kind.name);
        expect(game.pickupNotice?.pickup, kind, reason: kind.name);
      }
    });

    test('a timed effect keeps its card until the effect runs out', () {
      // One second was not long enough to find the card, let alone read it.
      // It now lasts as long as the thing it describes.
      final game = _game();
      game.debugTakePickup(Pickup(PickupKind.freeze, game.dog.cell));

      game.debugElapseNotices(PickupKind.freeze.duration - 1);
      expect(
        game.pickupNotice?.pickup,
        PickupKind.freeze,
        reason: 'the card went before the freeze did',
      );
      expect(game.pickupNoticeReadFor, 0, reason: 'read window is not the life');

      game.debugElapseNotices(1 + HexcapeGame.pickupNoticeFadeSeconds + 0.5);
      expect(game.pickupNotice, isNull);
    });

    test('a charge keeps its card until it is spent', () {
      // The card names the tap the player still owes, so it stays until they
      // make it.
      final game = _game();
      game.debugTakePickup(Pickup(PickupKind.blast, game.dog.cell));

      game.debugElapseNotices(30);
      expect(game.pickupNotice?.pickup, PickupKind.blast);

      game.powerups.spend(PickupKind.blast);
      game.debugElapseNotices(HexcapeGame.pickupNoticeFadeSeconds + 0.5);
      expect(game.pickupNotice, isNull);
    });

    test('a passive gets the read window and no more', () {
      // It is held for the rest of the run; a card that never left would own
      // the slot for the whole level.
      final game = _game();
      game.debugTakePickup(Pickup(PickupKind.ironpaw, game.dog.cell));

      game.debugElapseNotices(HexcapeGame.pickupNoticeSeconds + 0.1);
      expect(game.pickupNotice, isNull);
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
