import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/components/field_component.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';

/// Cracked ground, drawn.
///
/// The renderer is where a new [HexType] fails quietly rather than loudly: the
/// three colour switches are exhaustive and so the compiler catches those, but
/// the *mark* is drawn from an `if` chain that happily says nothing at all for
/// a type it has never heard of. A fault that renders as a plain tile is a
/// mechanic the player cannot see coming, which is worse than one that crashes.
void main() {
  test('a Collapse level actually generates cracked ground', () {
    final game = HexcapeGame(tuning: TuningConfig())
      ..onGameResize(Vector2(390, 844))
      ..startLevel(level: Campaign.faultsFrom);

    final faults = game.grid.all.where((c) => c.type == HexType.fault);
    expect(faults, isNotEmpty, reason: 'the introduction has no faults');

    // In lines, not confetti. Every fault should touch at least one other.
    final coords = faults.map((c) => c.coord).toSet();
    for (final c in coords) {
      expect(
        c.neighbours.any(coords.contains),
        isTrue,
        reason: 'the fault at $c is a lone cell rather than part of a line',
      );
    }
  });

  test('the field renders a board containing faults without throwing', () {
    final game = HexcapeGame(tuning: TuningConfig())
      ..onGameResize(Vector2(390, 844))
      ..startLevel(level: Campaign.collapseEnd);

    // Revealed, or the renderer draws every unknown cell as plain and the fault
    // branch is never reached — which would make this test pass while proving
    // nothing.
    for (final cell in game.grid.all) {
      cell.revealed = true;
    }
    expect(
      game.grid.all.any((c) => c.type == HexType.fault),
      isTrue,
      reason: 'nothing to draw',
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    FieldComponent(game).render(canvas);
    recorder.endRecording().dispose();
  });
}
