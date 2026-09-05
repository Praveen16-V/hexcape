import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/components/dog_component.dart';
import 'package:hexcape/components/field_component.dart';
import 'package:hexcape/components/movement_cue.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/tutorial.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/theme/palette.dart';
import 'package:hexcape/ui/hud.dart';

const origin = HexCoord.zero;
const next = HexCoord(0, -1);
const layout = HexLayout(size: 22, origin: Offset(180, 240));

HexGrid field() {
  final grid = HexGrid(
    cells: {
      for (final c in origin.disc(4))
        c: HexCell(c, HexType.plain)..revealed = true,
    },
    start: origin,
    exit: const HexCoord(0, -4),
    truePath: const [],
  );
  for (final c in [origin, next, const HexCoord(0, -2)]) {
    grid.at(c)!.clear(0);
  }
  return grid;
}

Dog dogFor(HexLayout l) => Dog(position: l.toPixel(origin), cell: origin);

void step(
  Dog dog,
  HexGrid grid, {
  Set<HexCoord> blocked = const {},
  int version = 1,
}) {
  dog.update(
    dt: 1 / 60,
    grid: grid,
    layout: layout,
    tuning: TuningConfig(),
    fieldVersion: version,
    regrowthActive: false,
    blocked: blocked,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Optional real font for human inspection; normal tests remain portable.
    final path = Platform.environment['READABILITY_FONT'];
    if (path != null) {
      final font = FontLoader('Roboto')
        ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
      await font.load();
    }
  });
  test(
    'cue follows steering, disappears at a wall and during spring flight',
    () {
      final grid = field();
      final dog = dogFor(layout);
      step(dog, grid);
      expect(dog.movementAim, isNotNull);
      final tip = MovementCue.tip(
        position: dog.position,
        aim: dog.movementAim,
        grid: grid,
        layout: layout,
      );
      expect(tip, isNotNull);
      expect(grid.isPassable(layout.toHex(tip!)), isTrue);
      expect(
        (tip - dog.position).distance,
        lessThanOrEqualTo(layout.width * 1.15),
      );
      grid.at(next)!.resetToSolid();
      step(dog, grid, version: 2);
      expect(dog.movementAim, isNull);
      grid.at(next)!.clear(0);
      step(dog, grid, version: 3);
      dog.launch(const Offset(0, -1), 100);
      expect(dog.movementAim, isNull);
    },
  );

  test('cue does not cross hidden terrain even with an old aim', () {
    final grid = field();
    final dog = dogFor(layout);
    step(dog, grid);
    grid.at(next)!.revealed = false;
    expect(
      MovementCue.tip(
        position: dog.position,
        aim: dog.movementAim,
        grid: grid,
        layout: layout,
      ),
      isNull,
    );
  });

  test(
    'patrol waiting differs from solid walls and clears when light moves',
    () {
      final grid = field();
      final dog = dogFor(layout);
      step(dog, grid, blocked: {next});
      expect(dog.waitingForPatrol, isTrue);
      expect(dog.movementAim, isNull);
      step(dog, grid);
      expect(dog.waitingForPatrol, isFalse);
      expect(dog.movementAim, isNotNull);
      grid.at(next)!.resetToSolid();
      step(dog, grid, version: 2, blocked: {next});
      expect(dog.waitingForPatrol, isFalse);
    },
  );

  test(
    'widening lesson advances on a cleared side tile and increases speed',
    () {
      final grid = field();
      final dog = dogFor(layout);
      final lesson = Tutorial([
        ...Tutorial.forLevel(
          1,
        )!.steps.where((s) => s.target == TutorialTarget.widenPath),
      ]);
      final narrow = grid.opennessAround(dog.cell);
      final narrowDog = dogFor(layout);
      step(narrowDog, grid);
      final narrowSpeed = narrowDog.speed;
      for (var i = 0; i < 2; i++) {
        final target = lesson.targetCell(grid, dog, const [])!;
        expect(target.distanceTo(dog.cell), 1);
        lesson.onTapped(target, grid, dog, const [], targetBeforeTap: target);
        expect(
          lesson.isDone,
          isFalse,
          reason: 'a tap without opening is not widening',
        );
        grid.at(target)!.clear(0);
        lesson.onTapped(target, grid, dog, const [], targetBeforeTap: target);
      }
      expect(lesson.isDone, isTrue);
      expect(grid.opennessAround(dog.cell), greaterThan(narrow));
      step(dog, grid);
      expect(dog.speed, greaterThan(narrowSpeed));
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1280, 800),
  ]) {
    for (final reduced in [false, true]) {
      testWidgets('movement and wrapped lesson $size reduced=$reduced', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final game = HexcapeGame(
          tuning: TuningConfig()
            ..hungerEnabled = false
            ..fogEnabled = false
            ..reducedMotion = reduced,
        );
        game.onGameResize(Vector2(size.width, size.height));
        game.grid = field();
        game.layout = HexLayout(
          size: math.min(32, (size.width - 28) / (9 * math.sqrt(3))),
          origin: Offset(size.width / 2, size.height / 2),
        );
        game.dog = dogFor(game.layout);
        game.dog.update(
          dt: 1 / 60,
          grid: game.grid,
          layout: game.layout,
          tuning: game.tuning,
          fieldVersion: 1,
          regrowthActive: false,
        );
        game.tutorialTarget = const HexCoord(1, 0);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: Material(
                color: Palette.background,
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: _Board(game))),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: GameHint(
                        text: 'Open a tile beside her to widen the path',
                        reducedMotion: reduced,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final text = tester.getRect(
          find.text('Open a tile beside her to widen the path'),
        );
        expect(text.left, greaterThanOrEqualTo(20));
        expect(text.right, lessThanOrEqualTo(size.width - 20));
        expect(text.bottom, lessThanOrEqualTo(size.height - 20));
        if (const bool.fromEnvironment('RENDER_READABILITY')) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/readability/${size.width.toInt()}-${reduced ? "reduced" : "normal"}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
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
