import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/components/field_component.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/systems/input_system.dart';

HexcapeGame makeGame(int level) => HexcapeGame(tuning: TuningConfig())
  ..onGameResize(Vector2(390, 844))
  ..startLevel(level: level);

Iterable<HexCell> ofType(HexcapeGame game, HexType type) =>
    game.grid.all.where((c) => c.type == type);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Slopes', () {
    test('arrive when the campaign says they do, and not before', () {
      for (var n = 1; n < Campaign.slopesFrom; n++) {
        expect(
          Campaign.rulesFor(n).slopeDensity,
          0,
          reason: 'level $n is before the gate',
        );
      }
      var seen = 0;
      for (var n = Campaign.slopesFrom; n <= Campaign.length; n++) {
        if (Campaign.rulesFor(n).slopeDensity > 0) seen++;
      }
      expect(seen, greaterThan(30));
    });

    test('the level that announces them actually generates some', () {
      final game = makeGame(Campaign.slopesFrom);
      expect(game.rules.introduces, contains('push her'));
      // Enough to be *met*, not merely present. `isNotEmpty` passed here while
      // the board generated a single slope tile, which a player can finish the
      // level without ever standing on — a banner promising a mechanic that
      // then does not happen is worse than no banner.
      expect(
        ofType(game, HexType.slope).length,
        greaterThanOrEqualTo(4),
        reason: 'the level that announces slopes has to actually have lanes',
      );
    });

    test('they cost one tap, like plain ground', () {
      final game = makeGame(70);
      for (final cell in ofType(game, HexType.slope)) {
        expect(cell.type.hitsRequired, 1);
        expect(cell.type.isClearableType, isTrue);
      }
    });

    test('a run of them all points the same way', () {
      // The shape is the mechanic: a lane you can choose to enter, not a
      // scatter of individual shoves.
      final game = makeGame(75);
      final slopes = ofType(game, HexType.slope).toList();
      expect(slopes, isNotEmpty);
      var checked = 0;
      for (final cell in slopes) {
        final ahead = cell.coord + HexCoord.directions[cell.slopeDirection];
        final next = game.grid.at(ahead);
        if (next != null && next.type == HexType.slope) {
          checked++;
          expect(
            next.slopeDirection,
            cell.slopeDirection,
            reason: 'a lane that changes direction mid-run cannot be read',
          );
        }
      }
      expect(checked, greaterThan(0), reason: 'no runs generated to check');
    });

    test('she is pushed the way the tile points, not the way she walked', () {
      final game = makeGame(70);
      final slope = ofType(game, HexType.slope).first;
      final coord = slope.coord;
      game.grid.at(coord)!.clear(0);
      game.dog.position = game.layout.toPixel(coord);
      // Walking the *opposite* way to the arrow, so a spring's rule and a
      // slope's rule cannot produce the same answer.
      final push =
          game.layout.toPixel(
            coord + HexCoord.directions[slope.slopeDirection],
          ) -
          game.layout.toPixel(coord);
      game.dog.velocity = -push;

      game.update(1 / 60);

      final after = game.dog.velocity;
      expect(after.distance, greaterThan(0));
      // Same heading as the arrow, within a hair.
      final dot =
          (after.dx * push.dx + after.dy * push.dy) /
          (after.distance * push.distance);
      expect(
        dot,
        greaterThan(0.99),
        reason: 'she was thrown along her own heading, which is a spring',
      );
    });

    test('a board full of them renders without throwing', () {
      final game = makeGame(Campaign.slopesFrom + 8);
      for (final cell in game.grid.all) {
        cell.revealed = true;
      }
      final recorder = PictureRecorder();
      FieldComponent(game).render(Canvas(recorder));
      recorder.endRecording().dispose();
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
      final isolated = ofType(game, HexType.sunken).firstWhere(
        (c) => !game.grid.hasFooting(c.coord),
      );
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
        reason: 'a deliberate tap must never be redirected onto a tile the '
            'player was not aiming at',
      );
    });

    test('refusing a tap costs nothing', () {
      final game = makeGame(95);
      final isolated = ofType(game, HexType.sunken).firstWhere(
        (c) => !game.grid.hasFooting(c.coord),
      );
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
