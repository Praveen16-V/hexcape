import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/components/field_component.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/entities/guard.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/systems/input_system.dart';

final _layout = HexLayout(size: 24, origin: const Offset(400, 400));

HexGrid _openField() {
  final coords = HexCoord.zero.disc(4);
  final grid = HexGrid(
    cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
    start: HexCoord.zero,
    exit: coords.last,
    truePath: const [],
  );
  return grid;
}

void main() {
  group('A warded light', () {
    test('refuses a tap that lands inside it', () {
      final grid = _openField();
      const target = HexCoord(1, 0);

      final open = InputSystem.resolve(
        point: _layout.toPixel(target),
        grid: grid,
        layout: _layout,
        dogPosition: _layout.toPixel(HexCoord.zero),
        tapRadius: 200,
      );
      expect(open.outcome, TapOutcome.hit, reason: 'unwarded, it should carve');

      final warded = InputSystem.resolve(
        point: _layout.toPixel(target),
        grid: grid,
        layout: _layout,
        dogPosition: _layout.toPixel(HexCoord.zero),
        tapRadius: 200,
        warded: {target},
      );
      expect(warded.outcome, TapOutcome.warded);
      expect(warded.coord, target);
    });

    test('is never quietly swapped for a neighbour', () {
      // A tap that missed and got helpfully redirected onto warded ground would
      // spend nothing and look broken; one redirected *off* it would teach the
      // player that the light does not really stop them.
      final grid = _openField();
      const target = HexCoord(1, 0);
      final result = InputSystem.resolve(
        point: _layout.toPixel(target),
        grid: grid,
        layout: _layout,
        dogPosition: _layout.toPixel(HexCoord.zero),
        tapRadius: 200,
        warded: {target},
      );
      expect(result.coord, target, reason: 'the light must own the refusal');
    });

    test('outranks an anchor, so the light is what gets blamed', () {
      final grid = _openField();
      const target = HexCoord(1, 0);
      grid.at(target)!.type = HexType.anchor;

      final result = InputSystem.resolve(
        point: _layout.toPixel(target),
        grid: grid,
        layout: _layout,
        dogPosition: _layout.toPixel(HexCoord.zero),
        tapRadius: 200,
        warded: {target},
      );
      expect(result.outcome, TapOutcome.warded);
    });

    test('does not block her body, unlike a patrol', () {
      // The whole split. A sentry that also walled her out would just be a
      // better guard, and it would need a solvability check it does not have.
      final sentry = Guard(
        patrol: const [HexCoord(0, 0), HexCoord(1, 0)],
        kind: GuardKind.sentry,
      );
      final patrol = Guard(patrol: const [HexCoord(0, 0), HexCoord(1, 0)]);
      expect(sentry.isSentry, isTrue);
      expect(patrol.isSentry, isFalse);
      // Both light the same shape; what differs is which set the game files it
      // under, which is asserted on a real level below.
      expect(sentry.lit.toSet(), patrol.lit.toSet());
    });

    test('a Vigil level files patrols and sentries into separate sets', () {
      final game = HexcapeGame(tuning: TuningConfig())
        ..onGameResize(Vector2(390, 844))
        ..startLevel(level: Campaign.length);

      expect(
        game.guards.any((g) => g.isSentry),
        isTrue,
        reason: 'the last level has no sentry',
      );
      // Run a frame so the lit sets are populated.
      game.update(1 / 60);
      expect(game.wardedCells, isNotEmpty);
      expect(
        game.wardedCells.intersection(game.guardedCells),
        isEmpty,
        reason: 'a cell cannot be both a wall for her and a wall for your taps',
      );
    });

    test('renders without throwing on a board that has one', () {
      final game = HexcapeGame(tuning: TuningConfig())
        ..onGameResize(Vector2(390, 844))
        ..startLevel(level: Campaign.length);
      game.update(1 / 60);
      for (final cell in game.grid.all) {
        cell.revealed = true;
      }
      final recorder = ui.PictureRecorder();
      FieldComponent(game).render(ui.Canvas(recorder));
      recorder.endRecording().dispose();
    });
  });

  group('HEEL', () {
    Dog dogAt(HexCoord cell) =>
        Dog(position: _layout.toPixel(cell), cell: cell);

    test('holds her still, and lets go on its own', () {
      final grid = _openField();
      for (final c in HexCoord.zero.disc(3)) {
        grid.at(c)!.clear(0);
      }
      final dog = dogAt(HexCoord.zero)..holdFor = 2.5;
      final tuning = TuningConfig();

      for (var i = 0; i < 60; i++) {
        dog.update(
          dt: 1 / 60,
          grid: grid,
          layout: _layout,
          tuning: tuning,
          fieldVersion: 1,
          regrowthActive: false,
        );
        expect(dog.velocity, Offset.zero, reason: 'she moved while held');
      }
      expect(dog.holdFor, greaterThan(0));

      for (var i = 0; i < 180; i++) {
        dog.update(
          dt: 1 / 60,
          grid: grid,
          layout: _layout,
          tuning: tuning,
          fieldVersion: 1,
          regrowthActive: false,
        );
      }
      expect(dog.holdFor, 0, reason: 'the hold never ended');
    });

    test('outranks a spring, so the tool is never spent on nothing', () {
      final grid = _openField();
      for (final c in HexCoord.zero.disc(3)) {
        grid.at(c)!.clear(0);
      }
      final dog = dogAt(HexCoord.zero)..holdFor = 2.5;
      dog.launch(const Offset(1, 0), 400);

      dog.update(
        dt: 1 / 60,
        grid: grid,
        layout: _layout,
        tuning: TuningConfig(),
        fieldVersion: 1,
        regrowthActive: false,
      );

      expect(dog.velocity, Offset.zero);
      expect(dog.isLaunched, isFalse);
    });

    test('does not suspend the enclosure timer', () {
      // Being held in a closing pocket still has to kill, or HEEL would be
      // invulnerability rather than a moment bought.
      final coords = HexCoord.zero.disc(4);
      final grid = HexGrid(
        cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
        start: HexCoord.zero,
        exit: coords.last,
        truePath: const [],
      );
      // Free first: the enclosure clock deliberately refuses to run until she
      // has been somewhere open, so a level cannot start by killing her.
      for (final c in HexCoord.zero.disc(2)) {
        grid.at(c)!.clear(0);
      }
      final dog = dogAt(HexCoord.zero);
      final tuning = TuningConfig();
      for (var i = 0; i < 10; i++) {
        dog.update(
          dt: 1 / 60,
          grid: grid,
          layout: _layout,
          tuning: tuning,
          fieldVersion: 1,
          regrowthActive: true,
        );
      }
      expect(dog.hasBeenFree, isTrue);

      // Now seal the pocket around her and hold her in it.
      for (final c in HexCoord.zero.disc(2)) {
        if (c != HexCoord.zero) {
          grid.at(c)!.resetToSolid();
        }
      }
      dog
        ..position = _layout.toPixel(HexCoord.zero)
        ..holdFor = 5;
      for (var i = 0; i < 60; i++) {
        dog.update(
          dt: 1 / 60,
          grid: grid,
          layout: _layout,
          tuning: tuning,
          fieldVersion: 2,
          regrowthActive: true,
        );
      }
      expect(
        dog.enclosedFor,
        greaterThan(0),
        reason: 'the hold froze the enclosure clock',
      );
    });
  });
}
