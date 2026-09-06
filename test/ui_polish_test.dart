import 'dart:io';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/game/daily.dart';
import 'package:hexcape/game/pets.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/ui/home_screen.dart';
import 'package:hexcape/ui/level_map.dart';
import 'package:hexcape/ui/pause_overlay.dart';
import 'package:hexcape/ui/result_overlay.dart';
import 'package:hexcape/ui/hud.dart';
import 'package:hexcape/components/field_component.dart';
import 'package:hexcape/components/dog_component.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontPath = Platform.environment['READABILITY_FONT'];
    if (fontPath != null) {
      for (final family in ['Roboto', 'Arial', 'Ahem']) {
        await (FontLoader(
              family,
            )..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView)))
            .load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final size in [
    const Size(320, 640),
    const Size(768, 1024),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Home, campaign and pause fit $size scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'opt_reduced_motion': scale == 2,
        });
        final progress = await Progress.load();
        final game = HexcapeGame(tuning: TuningConfig())
          ..onGameResize(Vector2(size.width, size.height))
          ..startLevel(level: 1);
        var homePressed = false;
        int? campaignSelected;
        final screens = <String, Widget>{
          'home': HomeScreen(
            progress: progress,
            pet: Pets.scout,
            onPlay: () {},
            onCampaign: () {},
            onTutorial: () {},
            onDaily: () {},
            onPets: () {},
            onSettings: () {},
            onReference: () {},
            onUnlock: () {},
          ),
          'tutorial': Material(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _TutorialBoard(game)),
                ),
                Positioned.fill(child: Hud(game: game)),
              ],
            ),
          ),
          for (final phase in [GamePhase.won, GamePhase.crushed])
            phase.name: Material(
              child: ResultOverlay(
                game: HexcapeGame(tuning: TuningConfig())
                  ..onGameResize(Vector2(size.width, size.height))
                  ..startLevel(level: 1)
                  ..phase = phase,
                owned: true,
                dailyStreak: 0,
                onMap: () {},
                onUnlock: () {},
                onHome: () => homePressed = true,
              ),
            ),
          for (final phase in [GamePhase.won, GamePhase.starved])
            'daily-${phase.name}': Material(
              child: ResultOverlay(
                game: HexcapeGame(tuning: TuningConfig())
                  ..onGameResize(Vector2(size.width, size.height))
                  ..daily = Daily.forDate(DateTime.utc(2026, 9, 1))
                  ..startLevel(
                    level: Daily.forDate(DateTime.utc(2026, 9, 1)).sourceLevel,
                  )
                  ..phase = phase,
                owned: false,
                dailyStreak: 2,
                onMap: () {},
                onUnlock: () {},
                onHome: () => homePressed = true,
              ),
            ),
          'campaign': LevelMap(
            progress: progress,
            onSelect: (level) => campaignSelected = level,
            onBack: () {},
            showToken: 1,
          ),
          'pause': Material(
            child: PauseOverlay(
              game: game,
              onMap: () {},
              onHome: () => homePressed = true,
              onReference: () {},
            ),
          ),
        };
        for (final entry in screens.entries) {
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: scale == 2,
                ),
                child: RepaintBoundary(key: key, child: entry.value),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 450));
          expect(tester.takeException(), isNull, reason: entry.key);
          if (entry.key == 'campaign') {
            expect(find.text('THE LONG TRAIL'), findsOneWidget);
            expect(find.text('CONTINUE · LEVEL 1'), findsOneWidget);
            await tester.tap(find.text('CONTINUE · LEVEL 1'));
            expect(campaignSelected, 1);
          }
          if (entry.key == 'won' || entry.key == 'crushed') {
            homePressed = false;
            await tester.ensureVisible(find.text('Main Menu'));
            await tester.tap(find.text('Main Menu'));
            expect(homePressed, isTrue);
          }
          if (entry.key == 'pause') {
            await tester.tap(find.text('MAIN MENU'));
            expect(homePressed, isTrue);
          }
          if (const bool.fromEnvironment('RENDER_UI')) {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/ui-review/${entry.key}-${size.width.toInt()}-${scale.toInt()}x.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (entry.key == 'tutorial') {
            await tester.tap(find.text('Skip'));
            await tester.pump();
            expect(game.tutorial!.isDone, isTrue);
            expect(game.tutorialTarget, isNull);
          }
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}

class _TutorialBoard extends CustomPainter {
  _TutorialBoard(this.game);
  final HexcapeGame game;
  @override
  void paint(Canvas canvas, Size size) {
    game.tutorialTarget = game.tutorial?.targetCell(
      game.grid,
      game.dog,
      game.pickups,
    );
    FieldComponent(game).render(canvas);
    DogComponent(game).render(canvas);
  }

  @override
  bool shouldRepaint(_TutorialBoard oldDelegate) => true;
}
