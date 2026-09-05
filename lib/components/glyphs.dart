import 'dart:math' as math;
import 'dart:ui';

import '../entities/pickup.dart';
import '../hex/hex_layout.dart';

/// The glyph for a pickup, drawn once and used everywhere.
///
/// This lived inline in the field renderer, which was fine while the field was
/// the only thing that drew it. The reference sheet draws the same shapes, and
/// two copies of a drawing diverge the first time one of them is adjusted —
/// leaving the legend quietly describing a game that no longer looks like that.
///
/// Draws the glyph only. The glow, the pulse and the collect animation belong
/// to the field, because they are about a pickup sitting on a board.
void drawPickupGlyph(
  Canvas canvas,
  PickupKind kind, {
  required Offset centre,
  required double size,
  required Paint fill,
  required Paint stroke,
}) {
  switch (kind) {
    case PickupKind.treat:
      // A small bone, so it reads as the same currency as the goal.
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(-0.38);
      canvas.drawPath(bonePath(size * 1.7), fill);
      canvas.restore();
    case PickupKind.freeze:
      // Six spokes: a snowflake that is also a hexagon's own symmetry.
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3;
        canvas.drawLine(
          centre,
          centre + Offset(math.cos(a), math.sin(a)) * size,
          stroke,
        );
      }
    case PickupKind.radiusPlus:
      // Concentric rings — reach, spreading outward.
      for (final r in const [0.45, 0.8, 1.15]) {
        canvas.drawCircle(centre, size * r, stroke);
      }
    case PickupKind.sprint:
      // Stacked chevrons, pointing the way she runs.
      for (var i = -1; i <= 1; i++) {
        final y = centre.dy + i * size * 0.45;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - size * 0.45, y - size * 0.32)
            ..lineTo(centre.dx + size * 0.5, y)
            ..lineTo(centre.dx - size * 0.45, y + size * 0.32),
          stroke,
        );
      }
    case PickupKind.scent:
      // A trail rising and thinning, the way a smell is drawn.
      final trail = Path()
        ..moveTo(centre.dx - size * 0.7, centre.dy + size * 0.6);
      for (var i = 1; i <= 3; i++) {
        final t = i / 3;
        trail.quadraticBezierTo(
          centre.dx - size * 0.7 + size * 1.4 * (t - 0.17),
          centre.dy +
              size * (0.6 - 1.2 * t) +
              (i.isEven ? size * 0.4 : -size * 0.4),
          centre.dx - size * 0.7 + size * 1.4 * t,
          centre.dy + size * (0.6 - 1.2 * t),
        );
      }
      canvas.drawPath(trail, stroke);
    case PickupKind.blast:
      // Rays off a hollow centre: something going off, not something solid.
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3 + math.pi / 6;
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          centre + dir * size * 0.42,
          centre + dir * size * 1.1,
          stroke,
        );
      }
      canvas.drawCircle(centre, size * 0.26, fill);
    case PickupKind.dig:
      // A hexagon with a crack straight through it — the one thing that
      // opens an anchor, drawn as the anchor giving way.
      canvas.drawPath(
        HexLayout.pathFromCorners(HexLayout.cornersAt(centre, size * 0.95)),
        stroke,
      );
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.5, centre.dy - size * 0.7)
          ..lineTo(centre.dx + size * 0.12, centre.dy - size * 0.1)
          ..lineTo(centre.dx - size * 0.16, centre.dy + size * 0.2)
          ..lineTo(centre.dx + size * 0.44, centre.dy + size * 0.78),
        stroke,
      );
    case PickupKind.heel:
      // A paw over a bar: stay. Reads as an instruction to the dog rather than
      // a change to the board, which is exactly what it is.
      canvas.drawCircle(centre.translate(0, -size * 0.14), size * 0.30, stroke);
      for (var i = -1; i <= 1; i++) {
        canvas.drawCircle(
          centre.translate(size * 0.42 * i, -size * 0.62),
          size * 0.15,
          stroke,
        );
      }
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.85, centre.dy + size * 0.62)
          ..lineTo(centre.dx + size * 0.85, centre.dy + size * 0.62),
        stroke,
      );
    case PickupKind.stake:
      // A peg driven into a baseline. The inverse of DIG's cracked hexagon,
      // and readable as "this ground is fixed" rather than "this ground
      // opens".
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy - size * 0.85)
          ..lineTo(centre.dx, centre.dy + size * 0.45),
        stroke,
      );
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.34, centre.dy + size * 0.12)
          ..lineTo(centre.dx, centre.dy + size * 0.45)
          ..lineTo(centre.dx + size * 0.34, centre.dy + size * 0.12),
        stroke,
      );
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.85, centre.dy + size * 0.78)
          ..lineTo(centre.dx + size * 0.85, centre.dy + size * 0.78),
        stroke,
      );
  }
}

/// The bone, used for the food and for a treat.
///
/// Moved here rather than reimplemented: writing a second bone by eye is how
/// the legend ends up showing a shape the game does not draw.
Path bonePath(double size) {
  final knob = size * 0.19;
  final reach = size * 0.36;
  final path = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-reach, -knob * 0.52, reach, knob * 0.52),
        Radius.circular(knob * 0.5),
      ),
    );
  for (final side in const [-1.0, 1.0]) {
    path
      ..addOval(
        Rect.fromCircle(
          center: Offset(reach * side, -knob * 0.62),
          radius: knob * 0.72,
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(reach * side, knob * 0.62),
          radius: knob * 0.72,
        ),
      );
  }
  return path;
}
