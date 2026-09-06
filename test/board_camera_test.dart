import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/board_camera.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/systems/input_system.dart';

/// The smallest phone the game supports, where the fit is worst and the camera
/// therefore matters most.
const _small = Size(320, 640);

HexcapeGame makeGame({Size size = _small, int level = 45}) =>
    HexcapeGame(tuning: TuningConfig())
      ..onGameResize(Vector2(size.width, size.height))
      ..startLevel(level: level);

Set<HexCoord> editable(HexcapeGame game) => InputSystem.editableCells(
  grid: game.grid,
  layout: game.layout,
  dogPosition: game.dog.position,
  tapRadius: game.effectiveTapRadius,
).toSet();

/// The dog's position in unit space — the one description of where she is that
/// does not change when the camera does.
Offset unitOf(HexcapeGame game) => Offset(
  (game.dog.position.dx - game.layout.origin.dx) / game.layout.size,
  (game.dog.position.dy - game.layout.origin.dy) / game.layout.size,
);


/// Open the whole board and return the cell furthest from the dog.
///
/// A level starts almost entirely solid, so a test that wants her to *travel*
/// has to carve first, and the longest straight corridor on a generated board
/// is only about six cells — not far enough to outrun a viewport. Clearing
/// everything gives her the full diagonal of the board to cross.
HexCoord openBoardAndFindFarCell(HexcapeGame game) {
  for (final cell in game.grid.all) {
    if (cell.type.isClearableType) cell.clear(0);
  }
  game.fieldVersion++;
  final from = game.dog.position;
  var best = game.dog.cell;
  var bestDistance = 0.0;
  for (final cell in game.grid.all) {
    final d = (game.layout.toPixel(cell.coord) - from).distance;
    if (d > bestDistance) {
      bestDistance = d;
      best = cell.coord;
    }
  }
  return best;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fit is untouched', () {
    test('a fresh level frames the whole board, exactly as it always did', () {
      final game = makeGame();
      expect(game.boardCamera.isFit, isTrue);
      expect(game.boardCamera.zoom, BoardCamera.minZoom);
      expect(game.layout.size, closeTo(game.fitHexSize, 1e-9));

      for (final cell in game.grid.all) {
        for (final p in game.layout.corners(cell.coord)) {
          expect(p.dy, greaterThanOrEqualTo(game.hudInsets.top - 0.01));
          expect(
            p.dy,
            lessThanOrEqualTo(_small.height - game.hudInsets.bottom + 0.01),
          );
          expect(p.dx, greaterThanOrEqualTo(game.hudInsets.left - 0.01));
          expect(
            p.dx,
            lessThanOrEqualTo(_small.width - game.hudInsets.right + 0.01),
          );
        }
      }
    });

    test('cycling all the way round returns to the original framing', () {
      final game = makeGame();
      final origin = game.layout.origin;
      final size = game.layout.size;
      for (var i = 0; i < BoardCamera.steps.length; i++) {
        game.cycleZoom();
      }
      expect(game.boardCamera.isFit, isTrue);
      expect(game.layout.size, closeTo(size, 1e-9));
      expect((game.layout.origin - origin).distance, lessThan(1e-9));
    });
  });

  group('Zoom does not change the rules', () {
    test('the editable set is identical at every zoom step', () {
      final game = makeGame();
      final expected = editable(game);
      expect(expected, isNotEmpty);

      for (var i = 1; i < BoardCamera.steps.length; i++) {
        game.cycleZoom();
        expect(game.boardCamera.zoom, BoardCamera.steps[i]);
        expect(
          editable(game),
          expected,
          reason: 'reach must be measured in hexes, not pixels',
        );
      }
    });

    test('a magnified tap resolves to the same hex as a fitted one', () {
      final game = makeGame();
      // Somewhere off-centre, so a mistake in the origin cannot cancel out.
      final target = editable(game).first;

      TapResult resolveAt(HexCoord c) => InputSystem.resolve(
        point: game.layout.toPixel(c),
        grid: game.grid,
        layout: game.layout,
        dogPosition: game.dog.position,
        tapRadius: game.effectiveTapRadius,
      );

      final atFit = resolveAt(target);
      game.cycleZoom();
      final zoomed = resolveAt(target);

      expect(zoomed.outcome, atFit.outcome);
      expect(zoomed.coord, atFit.coord);
    });

    test('pixel and hex conversions round-trip under zoom and pan', () {
      final game = makeGame()..cycleZoom()..cycleZoom();
      expect(game.boardCamera.isFit, isFalse);
      for (final cell in game.grid.all) {
        expect(game.layout.toHex(game.layout.toPixel(cell.coord)), cell.coord);
      }
    });

    test('the dog keeps her board cell across a zoom change', () {
      final game = makeGame();
      final cell = game.dog.cell;
      final unit = unitOf(game);
      game.cycleZoom();
      expect(game.dog.cell, cell);
      expect((unitOf(game) - unit).distance, lessThan(1e-6));
    });
  });

  group('Framing while magnified', () {
    test('the board always covers the viewport', () {
      final game = makeGame()..cycleZoom()..cycleZoom();
      // Shove the focus far outside the board and let the clamp answer.
      game.boardCamera.focus = const Offset(-500, -500);
      game.onGameResize(Vector2(_small.width, _small.height));

      final view = game.boardViewport;
      final viewLeft = view.left;
      final viewRight = view.right;
      final viewTop = view.top;
      final viewBottom = view.bottom;

      var minX = double.infinity;
      var maxX = double.negativeInfinity;
      var minY = double.infinity;
      var maxY = double.negativeInfinity;
      for (final cell in game.grid.all) {
        for (final p in game.layout.corners(cell.coord)) {
          minX = p.dx < minX ? p.dx : minX;
          maxX = p.dx > maxX ? p.dx : maxX;
          minY = p.dy < minY ? p.dy : minY;
          maxY = p.dy > maxY ? p.dy : maxY;
        }
      }
      // Board taller and wider than the viewport at this zoom, so no edge of
      // the viewport may show anything but board.
      expect(minX, lessThanOrEqualTo(viewLeft + 0.5));
      expect(maxX, greaterThanOrEqualTo(viewRight - 0.5));
      expect(minY, lessThanOrEqualTo(viewTop + 0.5));
      expect(maxY, greaterThanOrEqualTo(viewBottom - 0.5));
    });

    test('the view catches up when a spring throws her across the board', () {
      final game = makeGame()..cycleZoom()..cycleZoom();
      final far = openBoardAndFindFarCell(game);
      final settled = game.boardCamera.focus;

      // A spring covers ground faster than she ever walks, and the far corner
      // of a magnified board is well outside the viewport. Put her there.
      game.dog.position = game.layout.toPixel(far);
      final landed = unitOf(game);
      expect(
        (landed - settled).distance,
        greaterThan(4.0),
        reason: 'she has to land somewhere the camera was not looking',
      );

      final half = Offset(
        game.boardViewport.width / (2 * game.layout.size),
        game.boardViewport.height / (2 * game.layout.size),
      );
      for (var i = 0; i < 120 && !game.isOver; i++) {
        game.update(1 / 60);
      }

      expect(
        (game.boardCamera.focus - settled).distance,
        greaterThan(1.0),
        reason: 'the camera has to have actually followed her',
      );
      final drift = unitOf(game) - game.boardCamera.focus;
      expect(drift.dx.abs(), lessThan(half.dx), reason: 'lost her off the side');
      expect(
        drift.dy.abs(),
        lessThan(half.dy),
        reason: 'lost her off the top or bottom',
      );
    });

    test('she is never lost off an edge while she walks', () {
      final game = makeGame()..cycleZoom()..cycleZoom();
      final far = openBoardAndFindFarCell(game);
      game.dog.launch(
        game.layout.toPixel(far) - game.dog.position,
        game.layout.width * 8.5,
        duration: 10,
      );
      var travelled = 0.0;
      for (var i = 0; i < 600 && !game.isOver; i++) {
        final before = game.dog.position;
        game.update(1 / 60);
        travelled += (game.dog.position - before).distance;
        final half = Offset(
          game.boardViewport.width / (2 * game.layout.size),
          game.boardViewport.height / (2 * game.layout.size),
        );
        final drift = unitOf(game) - game.boardCamera.focus;
        expect(
          drift.dx.abs(),
          lessThan(half.dx),
          reason: 'lost her off the side on frame $i',
        );
        expect(
          drift.dy.abs(),
          lessThan(half.dy),
          reason: 'lost her off the top or bottom on frame $i',
        );
      }
      expect(
        travelled,
        greaterThan(game.layout.width * 3),
        reason: 'she has to actually move for this to prove anything',
      );
    });

    test('the board is kept out from under the HUD', () {
      final game = makeGame();
      // At fit the board already sits inside the insets, so nothing is clipped
      // and nothing is paid for.
      expect(game.boardCamera.isFit, isTrue);
      final view = game.boardViewport;
      expect(view.left, game.hudInsets.left);
      expect(view.top, game.hudInsets.top);
      expect(view.right, _small.width - game.hudInsets.right);
      expect(view.bottom, _small.height - game.hudInsets.bottom);

      // Magnified, the board is taller than that rect — the clamp keeps its
      // edges flush with the frame, so the overflow lands on whichever side the
      // focus is not pinned to. That the board no longer *fits* is the whole
      // reason the render path clips to the frame.
      game.cycleZoom();
      game.cycleZoom();
      var minY = double.infinity;
      var maxY = double.negativeInfinity;
      for (final cell in game.grid.all) {
        for (final p in game.layout.corners(cell.coord)) {
          minY = p.dy < minY ? p.dy : minY;
          maxY = p.dy > maxY ? p.dy : maxY;
        }
      }
      expect(maxY - minY, greaterThan(view.height));
      expect(minY < view.top || maxY > view.bottom, isTrue);
    });

    test('an idle dog does not make the camera drift', () {
      final game = makeGame()..cycleZoom();
      game.dog.velocity = Offset.zero;
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      final settled = game.boardCamera.focus;
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      expect((game.boardCamera.focus - settled).distance, lessThan(0.05));
    });
  });

  group('The magnified board is actually readable', () {
    test('the worst board on the smallest phone gets a usable hex', () {
      // Level 100 is the largest silhouette the campaign generates.
      final game = makeGame(level: 100);
      final fitted = game.layout.width;
      game.cycleZoom();
      game.cycleZoom();
      expect(game.boardCamera.zoom, BoardCamera.steps.last);
      expect(
        game.layout.width,
        greaterThan(fitted * 2),
        reason: 'the point of the feature is a bigger hex',
      );
      expect(
        game.layout.width,
        greaterThan(40),
        reason: 'a hex should reach roughly a touch target across',
      );
    });
  });

  group('The camera itself', () {
    test('it tracks a target crossing the board and keeps it framed', () {
      final camera = BoardCamera()..zoom = 2.2;
      const half = Offset(6, 9);
      camera.focus = Offset.zero;

      var target = Offset.zero;
      // Twenty units of travel at a spring's pace, which is several viewports.
      const step = Offset(0.14, 0.22);
      for (var i = 0; i < 300; i++) {
        target += step;
        camera.follow(camera.targetFor(target, step), half, 1 / 60);
        final drift = target - camera.focus;
        expect(drift.dx.abs(), lessThan(half.dx));
        expect(drift.dy.abs(), lessThan(half.dy));
      }
      expect(
        camera.focus.distance,
        greaterThan(20),
        reason: 'a camera that never moved would keep a target framed only by '
            'accident',
      );
    });

    test('a target inside the dead zone moves nothing', () {
      final camera = BoardCamera()..zoom = 2.0;
      camera.focus = Offset.zero;
      const half = Offset(6, 9);
      for (var i = 0; i < 60; i++) {
        // Well inside 40% of the half-viewport on both axes.
        camera.follow(const Offset(1.0, 1.5), half, 1 / 60);
      }
      expect(camera.focus, Offset.zero);
    });

    test('it cuts rather than glides when reduced motion is asked for', () {
      final camera = BoardCamera()..zoom = 2.0;
      camera.focus = Offset.zero;
      const half = Offset(6, 9);
      camera.follow(const Offset(40, 40), half, 1 / 60, instant: true);
      // Straight to the dead-zone edge, with no easing left to run.
      expect(camera.focus.dx, closeTo(40 - half.dx * 0.40, 1e-9));
      expect(camera.focus.dy, closeTo(40 - half.dy * 0.40, 1e-9));
    });
  });
}
