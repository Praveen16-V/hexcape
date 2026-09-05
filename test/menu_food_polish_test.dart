import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/game/level_rules.dart';
import 'sim/simulated_player.dart' show specFor;
import 'package:hexcape/game/daily.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/pets.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/l10n/strings.dart';
import 'package:hexcape/ui/home_screen.dart';
import 'package:hexcape/ui/result_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Food economics cannot reshuffle board geometry or patrols', () {
    for (final n in [21, 40, 61, 81, 100]) {
      final spec = specFor(Campaign.rulesFor(n));
      final a = LevelGenerator.generate(spec);
      final b = LevelGenerator.generate(
        spec.copyWith(treatSeconds: 9, treatTaps: 5),
      );
      expect(b.grid.start, a.grid.start);
      expect(b.grid.exit, a.grid.exit);
      expect(
        b.grid.all.map((c) => (c.coord, c.type)).toList(),
        a.grid.all.map((c) => (c.coord, c.type)).toList(),
      );
      expect(
        b.guards.map((g) => g.patrol).toList(),
        a.guards.map((g) => g.patrol).toList(),
      );
    }
  });
  for (final phase in [
    GamePhase.won,
    GamePhase.crushed,
    GamePhase.starved,
    GamePhase.softLocked,
  ]) {
    testWidgets('Daily ${phase.name} has unique navigation', (tester) async {
      final game = HexcapeGame(tuning: TuningConfig())
        ..onGameResize(Vector2(390, 844))
        ..daily = Daily.forDate(DateTime.utc(2026, 9, 1))
        ..startLevel(level: Daily.forDate(DateTime.utc(2026, 9, 1)).sourceLevel)
        ..phase = phase;
      var maps = 0, homes = 0;
      final date = game.daily!.id;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultOverlay(
              game: game,
              owned: false,
              dailyStreak: 2,
              onMap: () => maps++,
              onHome: () => homes++,
              onUnlock: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(Strings.backToMap), findsOneWidget);
      expect(find.text('Main Menu'), findsOneWidget);
      expect(
        find.text(Strings.retry),
        phase == GamePhase.won ? findsNothing : findsOneWidget,
      );
      expect(
        find.byType(FilledButton),
        findsNWidgets(phase == GamePhase.won ? 1 : 2),
      );
      await tester.tap(find.text(Strings.backToMap));
      await tester.tap(find.text('Main Menu'));
      expect(maps, 1);
      expect(homes, 1);
      expect(game.daily!.id, date);
    });
  }
  for (final owned in [false, true]) {
    testWidgets('Home has one purchase entry when owned=$owned', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'owns_full': owned});
      final progress = await Progress.load();
      var purchases = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            progress: progress,
            pet: Pets.scout,
            onPlay: () {},
            onCampaign: () {},
            onTutorial: () {},
            onDaily: () {},
            onPets: () {},
            onSettings: () {},
            onReference: () {},
            onUnlock: () => purchases++,
          ),
        ),
      );
      expect(
        find.text('Unlock full game'),
        owned ? findsNothing : findsOneWidget,
      );
      expect(find.textContaining('MORE LEVELS'), findsNothing);
      if (!owned) {
        await tester.tap(find.text('Unlock full game'));
        expect(purchases, 1);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  test(
    'Food receipt uses capped time actually restored and resets on retry',
    () {
      final game = HexcapeGame(tuning: TuningConfig())
        ..onGameResize(Vector2(390, 844))
        ..startLevel(level: 3);
      game.tutorial?.skip();
      final food = game.pickups.firstWhere((p) => p.kind == PickupKind.treat);
      game.hunger.drain(0.25);
      game.dog.cell = food.coord;
      game.dog.position = game.layout.toPixel(food.coord);
      game.update(1 / 60);
      expect(food.collected, isTrue);
      expect(game.foodSecondsRefunded, closeTo(0.25, 0.001));
      expect(game.foodTapsRefunded, game.tuning.treatTaps.round());
      expect(game.foodReceipt, contains('+0.3s'));
      game.retry();
      expect(game.foodSecondsRefunded, 0);
      expect(game.foodTapsRefunded, 0);
      expect(game.foodReceipt, isNull);
    },
  );
}
