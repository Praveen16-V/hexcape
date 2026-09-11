import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/game/tutorial.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/ui/hud.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('the mark holds its tile while she crosses to it', (
    tester,
  ) async {
    // The complaint this beat exists to keep fixed: the tile the lesson points
    // at is the first one on the route *from where she is standing*, so a mark
    // recomputed per frame re-picks itself on every step she takes and hops
    // between candidates ahead of her. It holds one tile until the tile is
    // opened; only then does it move on.
    final game = HexcapeGame(tuning: TuningConfig())
      ..onGameResize(Vector2(390, 844))
      ..startLevel(level: 1);
    final script = game.tutorial!;
    final marked = script.targetCell(game.grid, game.dog, game.pickups)!;
    for (var frame = 0; frame < 240 && script.stepNumber == 1; frame++) {
      game.onTapDown(BoardTap(game, game.layout.toPixel(marked)));
      game.update(1 / 60);
    }
    expect(script.stepNumber, 2, reason: 'the tap answers the first beat');

    // A tapped tile buys a frame of hit-stop, so give the beat that follows a
    // few frames to put its own mark up before anything is read off it.
    for (var frame = 0; frame < 6; frame++) {
      game.update(1 / 60);
      if (game.tutorialTarget != marked) break;
    }
    final held = game.tutorialTarget!;
    expect(held, isNot(marked), reason: 'the next beat marks the next tile');
    final seen = <HexCoord>{held};
    final wasAt = game.dog.position;
    for (var frame = 0; frame < 180; frame++) {
      game.update(1 / 60);
      seen.add(game.tutorialTarget!);
    }
    expect(seen, {held}, reason: 'the mark moved under her feet: $seen');
    expect(
      game.dog.position,
      isNot(wasAt),
      reason: 'she was walking the whole time, which is the point',
    );
  });

  testWidgets('Tutorial fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Level three, because it is the one whose lesson still opens on a card
    // with a Continue button. Level two now opens by asking the player to
    // carve, so there is nothing to press on its first beat.
    final game = HexcapeGame(tuning: TuningConfig()..reducedMotion = true)
      ..onGameResize(Vector2(320, 640))
      ..startLevel(level: 3);
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

  testWidgets('a lesson about motion lets the board move', (tester) async {
    // Level two's regrowth beat. The run has to be *live* while the line is up
    // — the whole sentence is "watch the ground behind her", and a frozen
    // board has nothing to show.
    final game = HexcapeGame(tuning: TuningConfig())
      ..onGameResize(Vector2(390, 844))
      ..startLevel(level: 2);
    final script = game.tutorial!;

    final target = script.targetCell(game.grid, game.dog, game.pickups)!;
    for (var f = 0; f < 240 && script.stepNumber == 1; f++) {
      game.onTapDown(BoardTap(game, game.layout.toPixel(target)));
      game.update(1 / 60);
    }
    expect(script.stepNumber, 2, reason: 'the carve opens the lesson');
    expect(script.current!.advance, TutorialAdvance.onRegrow);
    expect(
      game.tutorialReading,
      isFalse,
      reason: 'a watching beat must not stop the run',
    );

    final wasAt = game.dog.position;
    for (var f = 0; f < 60; f++) {
      game.update(1 / 60);
    }
    expect(
      game.dog.position,
      isNot(wasAt),
      reason: 'she keeps walking while the line is up',
    );

    // And it ends on the event it is describing, not on a guess at the clock.
    expect(script.stepNumber, 2);
    script.noteRegrowth();
    game.update(1 / 60);
    expect(script.stepNumber, 3);
  });

  testWidgets('a lesson already learned does not play again', (tester) async {
    // It used to rebuild on every entry, so a loss and a retry put the player
    // back through the whole script before they could try the level again.
    SharedPreferences.setMockInitialValues({'unlocked': 3});
    final progress = await Progress.load();
    final game = HexcapeGame(tuning: TuningConfig())
      ..onGameResize(Vector2(390, 844))
      ..progress = progress;

    game.startLevel(level: 1);
    expect(game.tutorial, isNotNull, reason: 'never taught, so teach it');
    game.tutorial!.skip();
    game.update(1 / 60);
    expect(progress.lessonsSeen, 1);

    game.startLevel(level: 1);
    expect(game.tutorial, isNull, reason: 'a retry is not another lesson');

    // Unless the player asks for it by name.
    game.replayLesson = true;
    game.startLevel(level: 1);
    expect(game.tutorial, isNotNull);
    expect(game.replayLesson, isFalse, reason: 'a one-shot, not a mode');

    // And a later lesson is untouched by an earlier one being replayed.
    game.startLevel(level: 2);
    expect(game.tutorial, isNotNull);
  });
}
