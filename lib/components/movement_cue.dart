import 'dart:math' as math;
import 'dart:ui';

import '../hex/hex_grid.dart';
import '../hex/hex_layout.dart';
import '../theme/palette.dart';

/// A short, static direction mark. It describes current steering, never an
/// undiscovered solution, and needs no animation in Reduced Motion mode.
class MovementCue {
  MovementCue._();

  static Offset? tip({
    required Offset position,
    required Offset? aim,
    required HexGrid grid,
    required HexLayout layout,
  }) {
    if (aim == null) return null;
    final delta = aim - position;
    if (delta.distance < layout.width * 0.65) return null;
    final length = math.min(delta.distance, layout.width * 1.15);
    final direction = delta / delta.distance;
    // Shorten at a wall or unrevealed cell, including after a regrowth update.
    var visible = 0.0;
    for (var d = 0.0; d <= length; d += layout.width * 0.05) {
      final cell = grid.at(layout.toHex(position + direction * d));
      if (cell == null || !cell.isPassable || !cell.revealed) break;
      visible = d;
    }
    return visible < layout.width * 0.65
        ? null
        : position + direction * visible;
  }

  static void draw(
    Canvas canvas, {
    required Offset position,
    required Offset? aim,
    required HexGrid grid,
    required HexLayout layout,
  }) {
    final end = tip(position: position, aim: aim, grid: grid, layout: layout);
    if (end == null) return;
    final direction = (end - position) / (end - position).distance;
    final side = Offset(-direction.dy, direction.dx);
    final wing = layout.width * 0.11;
    final path = Path()
      ..moveTo(
        (end - direction * wing + side * wing).dx,
        (end - direction * wing + side * wing).dy,
      )
      ..lineTo(end.dx, end.dy)
      ..lineTo(
        (end - direction * wing - side * wing).dx,
        (end - direction * wing - side * wing).dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2
        ..color = Palette.goalBone.withValues(alpha: 0.75),
    );
  }
}
