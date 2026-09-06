import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/components/dog_component.dart';
import 'package:hexcape/components/field_component.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/systems/input_system.dart';
import 'package:hexcape/systems/reveal_system.dart';
import 'package:hexcape/theme/palette.dart';
import 'package:hexcape/ui/hud.dart';

const sizes = [
  Size(320, 640),
  Size(390, 844),
  Size(768, 1024),
  Size(1280, 800),
];

HexcapeGame makeGame(Size size) => HexcapeGame(tuning: TuningConfig())
  ..onGameResize(Vector2(size.width, size.height))
  ..startLevel(level: 45);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (const bool.fromEnvironment('RENDER_RESPONSIVE')) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    final fontPath = Platform.environment['READABILITY_FONT'];
    if (fontPath != null) {
      await (FontLoader('Roboto')
            ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });

  test(
    'the same board position has identical edit and reveal sets at every size',
    () {
      for (final boosted in [false, true]) {
        Set<HexCoord>? expectedEdits;
        Set<HexCoord>? expectedRevealed;
        for (final size in sizes) {
          final game = makeGame(size);
          if (boosted) game.powerups.grant(PickupKind.radiusPlus);
          final offset = Offset(
            game.layout.width * 0.12,
            game.layout.width * 0.08,
          );
          game.dog.position += offset;
          final edits = InputSystem.editableCells(
            grid: game.grid,
            layout: game.layout,
            dogPosition: game.dog.position,
            tapRadius: game.effectiveTapRadius,
          ).toSet();
          for (final cell in game.grid.all) {
            cell.revealed = false;
          }
          RevealSystem.reveal(
            grid: game.grid,
            layout: game.layout,
            dogPosition: game.dog.position,
            dogCell: game.dog.cell,
            radius: game.revealRadius,
          );
          final revealed = game.grid.all
              .where((c) => c.revealed)
              .map((c) => c.coord)
              .toSet();
          expectedEdits ??= edits;
          expectedRevealed ??= revealed;
          expect(edits, expectedEdits, reason: '$size boosted=$boosted');
          expect(revealed, expectedRevealed, reason: '$size boosted=$boosted');
          expect(edits, isNotEmpty);
          for (final coord in edits) {
            expect(
              InputSystem.resolve(
                point: game.layout.toPixel(coord),
                grid: game.grid,
                layout: game.layout,
                dogPosition: game.dog.position,
                tapRadius: game.effectiveTapRadius,
              ).coord,
              coord,
            );
          }
        }
      }
    },
  );

  test(
    'resizing preserves position, velocity, budget and reach in board units',
    () {
      final game = makeGame(sizes.first);
      final unit = (game.dog.position - game.layout.origin) / game.layout.size;
      game.dog.velocity = Offset(game.layout.width, 0);
      final budget = game.tapBudget;
      final reach = game.effectiveTapRadius / game.layout.width;
      game.onGameResize(Vector2(768, 1024));
      expect(
        ((game.dog.position - game.layout.origin) / game.layout.size - unit)
            .distance,
        lessThan(1e-8),
      );
      expect(game.dog.velocity.dx / game.layout.width, closeTo(1, 1e-8));
      expect(game.effectiveTapRadius / game.layout.width, closeTo(reach, 1e-8));
      expect(game.tapBudget, budget);
      game.tuning.revealFactor = 1.2;
      game.powerups.grant(PickupKind.radiusPlus);
      expect(game.revealRadius, greaterThan(game.effectiveTapRadius));
    },
  );

  testWidgets('a message arriving does not re-frame the board', (tester) async {
    // The HUD reports its message slot to the game as a board inset. When that
    // measured the live message, every hint that arrived, left, or cross-faded
    // resized the slot, moved the inset and re-laid the board out under the
    // player -- which is what the flicker was.
    const size = Size(390, 844);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final game = makeGame(size);
    game
      ..phase = GamePhase.playing
      ..tutorial = null
      ..banner = null
      ..bannerFor = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: Material(color: Palette.background, child: Hud(game: game)),
        ),
      ),
    );

    Future<double> settle() async {
      await tester.pump();
      await tester.pump();
      return game.hudInsets.bottom;
    }

    final quiet = await settle();

    game
      ..pickupNotice = const HudNotice.pickup(PickupKind.freeze)
      ..pickupNoticeFor = HexcapeGame.pickupNoticeSeconds
      ..pickupNoticeReadFor = HexcapeGame.pickupNoticeSeconds;
    expect(await settle(), quiet, reason: 'a pickup card moved the board');

    game
      ..pickupNotice = null
      ..pickupNoticeFor = 0
      ..pickupNoticeReadFor = 0
      ..proximityNotice = const HudNotice.proximity(hex: HexType.thorn)
      ..proximityNoticeFor = HexcapeGame.proximityNoticeSeconds;
    expect(await settle(), quiet, reason: 'a warning moved the board');

    game
      ..proximityNotice = null
      ..proximityNoticeFor = 0;
    expect(await settle(), quiet, reason: 'the slot did not settle back');

    await tester.pumpWidget(const SizedBox());
  });

  for (final size in sizes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('HUD fits $size text=$scale with safe areas and charges', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final game = makeGame(size);
        game.tuning.reducedMotion = scale == 2;
        game.tuning.developerTools = scale == 2;
        game.powerups.grant(PickupKind.blast);
        game.powerups.grant(PickupKind.dig);
        game.announce('Open a tile beside her to widen the path');
        // The inspector card carries the longest copy the HUD ever shows, so
        // it is laid out here at every size and text scale rather than only
        // where it happens to be triggered.
        game.grid.at(game.dog.cell)!.revealed = true;
        game.inspectPickup(PickupKind.stake);
        final capture = GlobalKey();
        Widget screen() => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.fromLTRB(8, 28, 8, 20),
              textScaler: TextScaler.linear(scale),
            ),
            child: RepaintBoundary(
              key: capture,
              child: Material(
                color: Palette.background,
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: _Board(game))),
                    Positioned.fill(child: Hud(game: game)),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(screen());
        await tester.pumpWidget(screen());
        await tester.pump();
        expect(tester.takeException(), isNull);
        final pause = tester.getRect(find.byTooltip('Pause game'));
        expect(pause.width, greaterThanOrEqualTo(48));
        expect(pause.height, greaterThanOrEqualTo(48));
        expect(pause.right, lessThanOrEqualTo(size.width - 8));
        final blast = find.byTooltip('Arm BLAST');
        final dig = find.byTooltip('Arm DIG');
        expect(tester.getRect(blast).size.width, greaterThanOrEqualTo(44));
        expect(tester.getRect(blast).size.height, greaterThanOrEqualTo(44));
        expect(tester.getRect(dig).size.width, greaterThanOrEqualTo(44));
        expect(tester.getRect(dig).size.height, greaterThanOrEqualTo(44));
        game
          ..inspecting = null
          ..inspectFor = 0
          ..banner = null
          ..bannerFor = 0
          ..pickupNotice = const HudNotice.pickup(PickupKind.freeze)
          ..pickupNoticeFor = HexcapeGame.pickupNoticeSeconds;
        await tester.pump();
        expect(find.text('FREEZE'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (size == sizes.first && scale == 1) {
          await tester.tap(blast);
          await tester.pump();
          expect(game.powerups.selectedCharge, PickupKind.blast);
          expect(find.byTooltip('Disarm BLAST'), findsOneWidget);
          await tester.tap(dig);
          await tester.pump();
          expect(game.powerups.selectedCharge, PickupKind.dig);
          expect(find.byTooltip('Arm BLAST'), findsOneWidget);
          expect(find.byTooltip('Disarm DIG'), findsOneWidget);
        }
        for (final cell in game.grid.all) {
          for (final p in game.layout.corners(cell.coord)) {
            expect(p.dy, greaterThanOrEqualTo(game.hudInsets.top - 0.01));
            expect(
              p.dy,
              lessThanOrEqualTo(size.height - game.hudInsets.bottom + 0.01),
            );
          }
        }
        expect(
          game.hudInsets.top + game.hudInsets.bottom,
          // Ahem uses square glyphs, so its wrapping is deliberately unlike
          // the shipped font. Always require a positive board viewport; check
          // usable play area in the real-font rendering run as well.
          lessThan(
            size.height -
                (Platform.environment.containsKey('READABILITY_FONT')
                    ? 160
                    : 32),
          ),
        );
        if (const bool.fromEnvironment('RENDER_RESPONSIVE')) {
          final boundary =
              capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/responsive/${size.width.toInt()}-${scale.toInt()}x.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

class _Board extends CustomPainter {
  _Board(this.game);
  final HexcapeGame game;
  @override
  void paint(Canvas canvas, Size size) {
    FieldComponent(game).render(canvas);
    DogComponent(game).render(canvas);
  }

  @override
  bool shouldRepaint(_Board oldDelegate) => true;
}
