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
    case PickupKind.ration:
      // A squared biscuit with two score marks: rations, not a meal.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: centre,
            width: size * 1.3,
            height: size * 1.0,
          ),
          Radius.circular(size * 0.22),
        ),
        stroke,
      );
      canvas.drawCircle(centre.translate(-size * 0.25, 0), size * 0.09, fill);
      canvas.drawCircle(centre.translate(size * 0.25, 0), size * 0.09, fill);
    case PickupKind.lantern:
      // A little held lamp: cage, loop and the flame inside.
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy - size * 0.9)
          ..lineTo(centre.dx, centre.dy - size * 0.55),
        stroke,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: centre.translate(0, size * 0.08),
            width: size * 1.0,
            height: size * 1.25,
          ),
          Radius.circular(size * 0.3),
        ),
        stroke,
      );
      canvas.drawCircle(centre.translate(0, size * 0.12), size * 0.22, fill);
    case PickupKind.cloak:
      // A hood and hem: the outline of not being seen.
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.75, centre.dy + size * 0.55)
          ..quadraticBezierTo(
            centre.dx - size * 0.8,
            centre.dy - size * 0.75,
            centre.dx,
            centre.dy - size * 0.8,
          )
          ..quadraticBezierTo(
            centre.dx + size * 0.8,
            centre.dy - size * 0.75,
            centre.dx + size * 0.75,
            centre.dy + size * 0.55,
          )
          ..moveTo(centre.dx - size * 0.45, centre.dy + size * 0.8)
          ..lineTo(centre.dx + size * 0.45, centre.dy + size * 0.8),
        stroke,
      );
      canvas.drawCircle(centre.translate(0, -size * 0.1), size * 0.16, fill);
    case PickupKind.slowbeat:
      // A metronome: triangle body, pendulum caught mid-swing.
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.7, centre.dy + size * 0.75)
          ..lineTo(centre.dx - size * 0.22, centre.dy - size * 0.75)
          ..lineTo(centre.dx + size * 0.22, centre.dy - size * 0.75)
          ..lineTo(centre.dx + size * 0.7, centre.dy + size * 0.75)
          ..close(),
        stroke,
      );
      canvas.drawLine(
        centre.translate(0, size * 0.6),
        centre.translate(-size * 0.3, -size * 0.5),
        stroke,
      );
      canvas.drawCircle(centre.translate(-size * 0.3, -size * 0.5), size * 0.12, fill);
    case PickupKind.wardown:
      // A ward circle with the ward broken out of it.
      canvas.drawCircle(centre, size * 0.7, stroke);
      canvas.drawLine(
        centre.translate(-size * 0.45, -size * 0.45),
        centre.translate(size * 0.45, size * 0.45),
        stroke,
      );
    case PickupKind.surepaws:
      // A paw with grip bars under each toe: planted, unthrowable.
      canvas.drawCircle(centre.translate(0, size * 0.12), size * 0.34, stroke);
      for (var i = -1; i <= 1; i++) {
        canvas.drawCircle(
          centre.translate(size * 0.44 * i, -size * 0.52),
          size * 0.15,
          fill,
        );
      }
      canvas.drawLine(
        centre.translate(-size * 0.55, size * 0.72),
        centre.translate(size * 0.55, size * 0.72),
        stroke,
      );
    case PickupKind.pairwork:
      // Two rings struck as one — the doubled tap.
      canvas.drawCircle(centre.translate(-size * 0.30, 0), size * 0.45, stroke);
      canvas.drawCircle(centre.translate(size * 0.30, 0), size * 0.45, stroke);
      canvas.drawCircle(centre, size * 0.12, fill);
    case PickupKind.trowel:
      // A narrow blade biting a line of ground.
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy - size * 0.85)
          ..lineTo(centre.dx - size * 0.35, centre.dy - size * 0.1)
          ..lineTo(centre.dx, centre.dy + size * 0.35)
          ..lineTo(centre.dx + size * 0.35, centre.dy - size * 0.1)
          ..close(),
        stroke,
      );
      canvas.drawLine(
        centre.translate(0, size * 0.35),
        centre.translate(0, size * 0.85),
        stroke,
      );
    case PickupKind.maul:
      // A hammer: the head heavy, the handle plain.
      canvas.drawRect(
        Rect.fromCenter(
          center: centre.translate(0, -size * 0.45),
          width: size * 1.3,
          height: size * 0.55,
        ),
        stroke,
      );
      canvas.drawLine(
        centre.translate(0, -size * 0.18),
        centre.translate(0, size * 0.85),
        stroke,
      );
    case PickupKind.echo:
      // Two diamonds mirrored across a dashed axis: one tap, two places.
      for (final side in const [-1.0, 1.0]) {
        final c = centre.translate(side * size * 0.5, 0);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - size * 0.4)
            ..lineTo(c.dx + size * 0.32, c.dy)
            ..lineTo(c.dx, c.dy + size * 0.4)
            ..lineTo(c.dx - size * 0.32, c.dy)
            ..close(),
          stroke,
        );
      }
      canvas.drawLine(
        centre.translate(0, -size * 0.55),
        centre.translate(0, size * 0.55),
        stroke,
      );
    case PickupKind.rewind:
      // A circle arrow running anti-clockwise.
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: size * 0.62),
        0.5,
        4.4,
        false,
        stroke,
      );
      final arrowTip = Offset(
        math.cos(0.5) * size * 0.62,
        math.sin(0.5) * size * 0.62,
      );
      canvas.drawPath(
        Path()
          ..moveTo(arrowTip.dx - size * 0.26, arrowTip.dy - size * 0.1)
          ..lineTo(arrowTip.dx + size * 0.06, arrowTip.dy + size * 0.14)
          ..lineTo(arrowTip.dx - size * 0.02, arrowTip.dy - size * 0.26),
        stroke,
      );
      canvas.restore();
    case PickupKind.mole:
      // A drill nose and one curl of spoil.
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.4, centre.dy - size * 0.6)
          ..lineTo(centre.dx + size * 0.4, centre.dy - size * 0.6)
          ..lineTo(centre.dx, centre.dy + size * 0.45)
          ..close(),
        stroke,
      );
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.15, centre.dy - size * 0.35)
          ..lineTo(centre.dx + size * 0.15, centre.dy - size * 0.15)
          ..lineTo(centre.dx - size * 0.1, centre.dy + size * 0.05),
        stroke,
      );
    case PickupKind.harvest:
      // A horseshoe magnet drawing in a star.
      canvas.drawArc(
        Rect.fromCircle(center: centre.translate(0, size * 0.1), radius: size * 0.5),
        0,
        math.pi,
        false,
        stroke,
      );
      canvas.drawCircle(centre.translate(0, -size * 0.55), size * 0.16, fill);
      canvas.drawLine(
        centre.translate(0, -size * 0.3),
        centre.translate(0, -size * 0.05),
        stroke,
      );
    case PickupKind.whistle:
      // A whistle: mouthpiece and bowl with the pea shown.
      canvas.drawCircle(centre.translate(size * 0.15, size * 0.15), size * 0.42, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.85, centre.dy - size * 0.3)
          ..lineTo(centre.dx + size * 0.1, centre.dy - size * 0.05)
          ..lineTo(centre.dx - size * 0.55, centre.dy - size * 0.05)
          ..close(),
        stroke,
      );
      canvas.drawCircle(centre.translate(size * 0.15, size * 0.15), size * 0.12, fill);
    case PickupKind.seed:
      // One seed pressed into a soil line.
      canvas.drawOval(
        Rect.fromCenter(
          center: centre.translate(0, -size * 0.2),
          width: size * 0.5,
          height: size * 0.85,
        ),
        fill,
      );
      canvas.drawLine(
        centre.translate(-size * 0.8, size * 0.45),
        centre.translate(size * 0.8, size * 0.45),
        stroke,
      );
    case PickupKind.beacon:
      // A lamp on a tripod, left standing.
      canvas.drawCircle(centre.translate(0, -size * 0.4), size * 0.28, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy - size * 0.12)
          ..lineTo(centre.dx - size * 0.5, centre.dy + size * 0.75)
          ..moveTo(centre.dx, centre.dy - size * 0.12)
          ..lineTo(centre.dx + size * 0.5, centre.dy + size * 0.75)
          ..moveTo(centre.dx, centre.dy - size * 0.12)
          ..lineTo(centre.dx, centre.dy + size * 0.75),
        stroke,
      );
    case PickupKind.pouch:
      // A tied bag, heavy at the bottom.
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - size * 0.15, centre.dy - size * 0.6)
          ..quadraticBezierTo(
            centre.dx - size * 0.8,
            centre.dy - size * 0.1,
            centre.dx - size * 0.55,
            centre.dy + size * 0.45,
          )
          ..quadraticBezierTo(
            centre.dx,
            centre.dy + size * 0.95,
            centre.dx + size * 0.55,
            centre.dy + size * 0.45,
          )
          ..quadraticBezierTo(
            centre.dx + size * 0.8,
            centre.dy - size * 0.1,
            centre.dx + size * 0.15,
            centre.dy - size * 0.6,
          )
          ..close(),
        stroke,
      );
      canvas.drawLine(
        centre.translate(-size * 0.28, -size * 0.55),
        centre.translate(size * 0.28, -size * 0.55),
        stroke,
      );
    case PickupKind.ironpaw:
      // A shield with a paw pad inside: the thorn answered permanently.
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy - size * 0.75)
          ..lineTo(centre.dx + size * 0.62, centre.dy - size * 0.4)
          ..lineTo(centre.dx + size * 0.62, centre.dy + size * 0.1)
          ..quadraticBezierTo(
            centre.dx + size * 0.62,
            centre.dy + size * 0.6,
            centre.dx,
            centre.dy + size * 0.85,
          )
          ..quadraticBezierTo(
            centre.dx - size * 0.62,
            centre.dy + size * 0.6,
            centre.dx - size * 0.62,
            centre.dy + size * 0.1,
          )
          ..lineTo(centre.dx - size * 0.62, centre.dy - size * 0.4)
          ..close(),
        stroke,
      );
      canvas.drawCircle(centre.translate(0, size * 0.05), size * 0.17, fill);
    case PickupKind.nightEyes:
      // An eye with a crescent beside it: seeing in low light.
      canvas.drawOval(
        Rect.fromCenter(center: centre, width: size * 1.5, height: size * 0.85),
        stroke,
      );
      canvas.drawCircle(centre, size * 0.2, fill);
      canvas.drawPath(
        Path()
          ..addArc(
            Rect.fromCircle(
              center: centre.translate(size * 0.62, -size * 0.55),
              radius: size * 0.3,
            ),
            -1.2,
            3.6,
          ),
        stroke,
      );
    case PickupKind.keepsake:
      // A small heart held in a ring: the one mercy.
      canvas.drawCircle(centre, size * 0.85, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy + size * 0.45)
          ..quadraticBezierTo(
            centre.dx - size * 0.75,
            centre.dy - size * 0.05,
            centre.dx - size * 0.34,
            centre.dy - size * 0.42,
          )
          ..quadraticBezierTo(
            centre.dx,
            centre.dy - size * 0.62,
            centre.dx,
            centre.dy - size * 0.18,
          )
          ..quadraticBezierTo(
            centre.dx,
            centre.dy - size * 0.62,
            centre.dx + size * 0.34,
            centre.dy - size * 0.42,
          )
          ..quadraticBezierTo(
            centre.dx + size * 0.75,
            centre.dy - size * 0.05,
            centre.dx,
            centre.dy + size * 0.45,
          ),
        stroke,
      );
    case PickupKind.waystone:
      // A compass needle: one diamond half filled, pointing somewhere.
      canvas.drawCircle(centre, size * 0.85, stroke);
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy - size * 0.55)
          ..lineTo(centre.dx + size * 0.22, centre.dy)
          ..lineTo(centre.dx, centre.dy + size * 0.55)
          ..lineTo(centre.dx - size * 0.22, centre.dy)
          ..close(),
        stroke,
      );
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy - size * 0.55)
          ..lineTo(centre.dx + size * 0.22, centre.dy)
          ..lineTo(centre.dx - size * 0.22, centre.dy)
          ..close(),
        fill,
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

/// Three bristles rising from the face of a thorn pad, in fill-outline so it
/// batches with the field's spike row and still draws on the reference sheet.
Path thornMarkPath(Offset c, double s) => Path()
  ..moveTo(c.dx - s * 0.40, c.dy + s * 0.34)
  ..lineTo(c.dx - s * 0.22, c.dy - s * 0.26)
  ..lineTo(c.dx - s * 0.05, c.dy + s * 0.34)
  ..close()
  ..moveTo(c.dx - s * 0.03, c.dy + s * 0.34)
  ..lineTo(c.dx, c.dy - s * 0.40)
  ..lineTo(c.dx + s * 0.03, c.dy + s * 0.34)
  ..close()
  ..moveTo(c.dx + s * 0.05, c.dy + s * 0.34)
  ..lineTo(c.dx + s * 0.22, c.dy - s * 0.26)
  ..lineTo(c.dx + s * 0.40, c.dy + s * 0.34)
  ..close();
