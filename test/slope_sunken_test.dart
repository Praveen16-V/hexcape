import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/systems/input_system.dart';

HexcapeGame makeGame(int level) => HexcapeGame(tuning: TuningConfig())
  ..onGameResize(Vector2(390, 844))
  ..startLevel(level: level);

Iterable<HexCell> ofType(HexcapeGame game, HexType type) =>
    game.grid.all.where((c) => c.type == type);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Retired slopes', () {
    test('the campaign never generates pushing arrows', () {
      for (var n = 1; n <= Campaign.length + 20; n++) {
        expect(Campaign.rulesFor(n).slopeDensity, 0, reason: 'level $n');
      }
      for (final n in [66, 69, 75, 100]) {
        final game = makeGame(n);
        expect(ofType(game, HexType.slope), isEmpty, reason: 'level $n');
      }
    });
  });
  group('Sunken ground', () {
    test('arrives when the campaign says it does, and not before', () {
      for (var n = 1; n < Campaign.sunkenFrom; n++) {
        expect(Campaign.rulesFor(n).sunkenDensity, 0, reason: 'level $n');
      }
      final game = makeGame(Campaign.sunkenFrom);
      expect(game.rules.introduces, contains('Sunken'));
      expect(
        ofType(game, HexType.sunken).length,
        greaterThanOrEqualTo(4),
        reason: 'one patch is something a player walks around without noticing',
      );
    });

    test('it will not clear with nothing open beside it', () {
      final game = makeGame(95);
      final isolated = ofType(game, HexType.sunken).firstWhere(
        (c) => !game.grid.hasFooting(c.coord),
        orElse: () => throw StateError('no unfooted sunken tile generated'),
      );
      expect(game.grid.isClearable(isolated.coord), isFalse);

      // And the moment something beside it opens, it does.
      final neighbour = game.grid
          .neighboursOf(isolated.coord)
          .firstWhere((c) => game.grid.at(c)!.type.isClearableType);
      game.grid.at(neighbour)!.clear(0);
      expect(game.grid.isClearable(isolated.coord), isTrue);
    });

    test('a tap on it says why it failed instead of hitting a neighbour', () {
      final game = makeGame(95);
      final isolated = ofType(
        game,
        HexType.sunken,
      ).firstWhere((c) => !game.grid.hasFooting(c.coord));
      // Stand her right next to it so range is not what refuses.
      game.dog.position = game.layout.toPixel(isolated.coord);

      final result = InputSystem.resolve(
        point: game.layout.toPixel(isolated.coord),
        grid: game.grid,
        layout: game.layout,
        dogPosition: game.dog.position,
        tapRadius: game.effectiveTapRadius,
      );
      expect(result.outcome, TapOutcome.noFooting);
      expect(
        result.coord,
        isolated.coord,
        reason:
            'a deliberate tap must never be redirected onto a tile the '
            'player was not aiming at',
      );
    });

    test('refusing a tap costs nothing', () {
      final game = makeGame(95);
      final isolated = ofType(
        game,
        HexType.sunken,
      ).firstWhere((c) => !game.grid.hasFooting(c.coord));
      game.dog.position = game.layout.toPixel(isolated.coord);
      final before = game.taps;
      game.handleBoardTapAt(game.layout.toPixel(isolated.coord));
      expect(game.taps, before);
      expect(game.grid.at(isolated.coord)!.isSolid, isTrue);
    });

    test('it is never what boxes her in', () {
      // The safety argument in HexType.sunken, checked rather than asserted:
      // she stands in an open cell, so everything touching her is footed.
      for (final level in [Campaign.sunkenFrom, 90, 100]) {
        final game = makeGame(level);
        for (final n in game.grid.neighboursOf(game.dog.cell)) {
          final cell = game.grid.at(n)!;
          if (!cell.type.isClearableType) continue;
          expect(
            game.grid.isClearable(n),
            isTrue,
            reason: 'level $level: $n beside her refused to open',
          );
        }
      }
    });

    test('it never makes a board unwinnable', () {
      // Sunken ground is clearable, so it prices no route differently — but it
      // is the first type whose clearability depends on the board's state, and
      // that is exactly the kind of thing that quietly breaks solvability.
      for (var n = Campaign.sunkenFrom; n <= Campaign.length; n++) {
        final game = makeGame(n);
        expect(game.par, greaterThan(0), reason: 'level $n has no route');
      }
    });
  });
}
