import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/ui/level_detail.dart';
import 'package:hexcape/ui/result_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

HexcapeGame gameAt(int level) => HexcapeGame(tuning: TuningConfig())
  ..onGameResize(Vector2(390, 844))
  ..startLevel(level: level);

Widget resultFor(HexcapeGame game, {MediaQueryData? media}) {
  final screen = Scaffold(
    body: ResultOverlay(
      game: game,
      owned: true,
      dailyStreak: 0,
      onMap: () {},
      onHome: () {},
      onUnlock: () {},
    ),
  );
  return MaterialApp(
    home: media == null ? screen : MediaQuery(data: media, child: screen),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Zen completion is practice and cannot advance a locked level', (
    tester,
  ) async {
    final game = gameAt(12);
    game.tuning.zenMode = true;
    game.phase = GamePhase.won;
    await tester.pumpWidget(resultFor(game));
    await tester.pumpAndSettle();

    expect(find.text('Practice complete'), findsOneWidget);
    expect(find.text('ZEN PRACTICE · NOT SAVED'), findsOneWidget);
    expect(find.text('Next level'), findsNothing);
    expect(find.text('Play for stars'), findsOneWidget);

    await tester.tap(find.text('Play for stars'));
    await tester.pump();
    expect(game.tuning.zenMode, isFalse);
    expect(game.levelNumber, 12);
  });

  testWidgets(
    'an endless loss restarts the run instead of retrying its depth',
    (tester) async {
      final game = gameAt(Campaign.length + 5)..phase = GamePhase.starved;
      await tester.pumpWidget(resultFor(game));
      await tester.pumpAndSettle();

      expect(find.text('ENDLESS RUN · NO STARS'), findsOneWidget);
      expect(find.text('Cleared through depth 4.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('New run'), findsOneWidget);

      await tester.tap(find.text('New run'));
      await tester.pump();
      expect(game.depth, 1);
    },
  );

  testWidgets('an endless clear continues deeper without showing stars', (
    tester,
  ) async {
    final game = gameAt(Campaign.length + 3)..phase = GamePhase.won;
    await tester.pumpWidget(resultFor(game));
    await tester.pumpAndSettle();

    expect(find.text('Depth 3 cleared'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('3 stars'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('level briefing states campaign, mastery and endless goals', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'unlocked': Campaign.length + 1,
      'owns_full': true,
    });
    final progress = await Progress.load();

    Future<void> show(int level) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LevelDetail(
              level: level,
              progress: progress,
              inProgress: false,
              onPlay:
                  ({required zen, required difficulty, required restart}) {},
              onUnlock: () {},
            ),
          ),
        ),
      );
    }

    await show(12);
    expect(find.textContaining('CAMPAIGN ·'), findsOneWidget);
    expect(find.textContaining('Stars measure tap efficiency'), findsOneWidget);
    expect(find.text('Zen'), findsOneWidget);

    await show(45);
    expect(find.text('MASTERY · 0/100 THREE-STAR CLEARS'), findsOneWidget);

    await show(Campaign.length + 1);
    expect(find.text('ENDLESS RUN'), findsOneWidget);
    expect(find.textContaining('Every run starts at depth 1'), findsOneWidget);
    expect(find.text('Zen'), findsNothing);
    expect(find.text('START RUN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing mode replaces Resume with the new mode action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'unlocked': 13, 'owns_full': true});
    final progress = await Progress.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LevelDetail(
            level: 12,
            progress: progress,
            inProgress: true,
            initialZen: false,
            onPlay: ({required zen, required difficulty, required restart}) {},
            onUnlock: () {},
          ),
        ),
      ),
    );
    expect(find.text('RESUME'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('RESUME'), findsNothing);
    expect(find.text('PRACTICE'), findsOneWidget);
  });

  testWidgets('mode results fit a narrow screen at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final game = gameAt(45)..phase = GamePhase.won;
    await tester.pumpWidget(
      resultFor(
        game,
        media: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('3 stars at'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
