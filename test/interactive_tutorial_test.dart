import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/ui/hud.dart';

class BoardTap extends TapDownEvent {
  BoardTap(HexcapeGame game, Offset point)
    : _point = Vector2(point.dx, point.dy),
      super(1, game, TapDownDetails(globalPosition: point));
  final Vector2 _point;
  @override
  Vector2 get canvasPosition => _point;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Real board taps advance lessons; reading freezes the run', (
    tester,
  ) async {
    final game = HexcapeGame(tuning: TuningConfig())
      ..onGameResize(Vector2(390, 844))
      ..startLevel(level: 1);
    final script = game.tutorial!;
    for (var i = 0; i < 2; i++) {
      final target = script.targetCell(game.grid, game.dog, game.pickups)!;
      for (var frame = 0; frame < 240 && script.stepNumber == i + 1; frame++) {
        game.onTapDown(BoardTap(game, game.layout.toPixel(target)));
        if (script.stepNumber == i + 1) game.update(1 / 60);
      }
      expect(script.stepNumber, i + 2);
    }
    expect(game.tutorialReading, isTrue);
    final elapsed = game.elapsed;
    final position = game.dog.position;
    final taps = game.taps;
    game.update(2);
    expect(game.elapsed, elapsed);
    expect(game.dog.position, position);
    game.onTapDown(BoardTap(game, game.dog.position));
    expect(game.taps, taps);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(child: Hud(game: game)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(script.stepNumber, 4);
    expect(game.tutorialReading, isFalse);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(script.isDone, isTrue);
    expect(find.text('Skip'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tutorial fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final game = HexcapeGame(tuning: TuningConfig()..reducedMotion = true)
      ..onGameResize(Vector2(320, 640))
      ..startLevel(level: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
            padding: EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: Material(child: Hud(game: game)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Continue'));
    expect(tester.getRect(find.text('Continue')).bottom, lessThan(616));
    expect(game.hudInsets.top + game.hudInsets.bottom, lessThan(640));
    await tester.pumpWidget(const SizedBox());
  });
}
