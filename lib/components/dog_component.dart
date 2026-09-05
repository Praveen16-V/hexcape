import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../entities/dog.dart';
import '../game/hexcape_game.dart';
import '../game/pets.dart';
import '../theme/palette.dart';
import 'movement_cue.dart';

/// The dog, her pawprints, and the warnings drawn around her.
///
/// She is always upright and mirrored by travel direction rather than rotated to
/// her heading — a side-view animal rotated to face downward ends up upside
/// down. Direction still reads, because the head, tail and lean all shift with
/// where she is going.
///
/// Redrawn after she was described as looking like a toy, and the difference is
/// almost entirely silhouette: a snout that tapers to a nose, a brow over the
/// eye, legs with a knee in them, a chest and haunch drawn as one line instead
/// of a stack of ovals. Still entirely code — no art assets — but animal-shaped.
class DogComponent extends Component {
  DogComponent(this.game) : super(priority: 20);

  final HexcapeGame game;

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// Held between frames so she does not flicker between facings while
  /// travelling straight up or down.
  double _flip = 1;

  /// Her coat, from whichever pet the player is running (§9.2). Read per
  /// frame rather than cached: the picker changes it while the game is alive
  /// behind the map, and a cached colour would leave her the old one until the
  /// next level.
  Pet get _pet => game.pet;
  Color get _body => _pet.body;
  Color get _dark => _pet.dark;
  Color get _nose => _pet.nose;
  Color get _glow => _pet.glow;

  @override
  void render(Canvas canvas) {
    final dog = game.dog;
    final r = Dog.dogRadius(game.layout);

    _renderPawprints(canvas, dog, r);
    if (!game.isOver && !game.isPausedByPlayer) {
      MovementCue.draw(
        canvas,
        position: dog.position,
        aim: dog.movementAim,
        grid: game.grid,
        layout: game.layout,
      );
    }
    _renderPowerupRing(canvas, dog, r);
    _renderEnclosureWarning(canvas, dog, r);

    final heading = math.cos(dog.facing);
    if (heading.abs() > 0.25) {
      _flip = heading < 0 ? -1 : 1;
    }

    final alert = game.barkFlash;
    final weary = game.tuning.hungerEnabled
        ? (1 - game.hunger.fraction / 0.3).clamp(0.0, 1.0)
        : 0.0;
    final startle = game.startleFlash;

    // Squash and stretch from acceleration (§10), plus a flinch when the field
    // snaps shut beside her.
    final stretch = 1 + dog.surge * 0.14 - startle * 0.12;
    final squash = 1 - dog.surge * 0.14 + startle * 0.18;

    // Trot bob, tied to distance covered rather than to the clock.
    final moving = (dog.velocity.distance / (r * 5)).clamp(0.0, 1.0);
    final motion = game.tuning.reducedMotion ? 0.0 : 1.0;
    final bob =
        -math.sin(dog.gaitPhase * math.pi * 2).abs() *
        r *
        0.12 *
        moving *
        motion;
    final breath = math.sin(game.elapsed * 2.8) * 0.025 * (1 - moving) * motion;
    final lift = alert * r * 0.22 - weary * r * 0.1 - startle * r * 0.06;
    final lean = (-dog.turnRate * 0.02).clamp(-0.35, 0.35) * _flip;

    canvas.save();
    canvas.translate(dog.position.dx, dog.position.dy + bob - lift);

    _renderShadow(canvas, r, -bob + lift);

    canvas.rotate(lean + game.despair * 0.12 + startle * 0.10);
    canvas.scale(_flip * stretch, squash + breath);

    _renderGlow(canvas, r, alert);
    // Far legs first, then body, then near legs — so she has depth rather than
    // four legs all pasted on the same plane.
    _renderLegs(canvas, dog, r, far: true);
    _renderTail(canvas, dog, r, alert);
    _renderBody(canvas, r, weary);
    _renderLegs(canvas, dog, r, far: false);
    _renderHead(canvas, dog, r, alert, weary, startle);

    canvas.restore();
  }

  void _renderShadow(Canvas canvas, double r, double lift) {
    _fill
      ..color = const Color(0x66000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.28);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, r * 0.98 + lift),
        width: r * 1.85,
        height: r * 0.6,
      ),
      _fill,
    );
    _fill.maskFilter = null;
  }

  void _renderGlow(Canvas canvas, double r, double alert) {
    final fraction = game.tuning.hungerEnabled ? game.hunger.fraction : 1.0;
    var vigour = 0.35 + 0.65 * fraction;
    if (fraction < 0.2) {
      // Guttering reads as a lamp going out, where a number only ticks.
      vigour *= 0.82 + 0.18 * math.sin(game.elapsed * 19);
    }
    vigour += alert * 0.5;
    _fill
      ..color = _glow.withValues(alpha: (_glow.a * vigour).clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.75);
    canvas.drawCircle(Offset.zero, r * (1.05 + alert * 0.3), _fill);
    _fill.maskFilter = null;
  }

  /// A leg with a knee in it.
  ///
  /// Two segments and a paw rather than one straight line — the bend is most of
  /// what separates an animal from a stick figure, and it costs one extra point.
  void _leg(
    Canvas canvas,
    double hipX,
    double hipY,
    double phase,
    double r,
    Color colour,
    double width,
  ) {
    final stride = (game.dog.velocity.distance / (r * 5)).clamp(0.0, 1.0);
    final swing = math.sin(phase) * stride;
    final lift = math.max(0.0, math.cos(phase)) * stride;

    final knee = Offset(
      hipX + swing * r * 0.20,
      hipY + r * 0.34 - lift * r * 0.05,
    );
    final paw = Offset(
      hipX + swing * r * 0.54,
      hipY + r * 0.66 - lift * r * 0.25,
    );

    _stroke
      ..color = colour
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
    canvas.drawPath(
      Path()
        ..moveTo(hipX, hipY)
        ..lineTo(knee.dx, knee.dy)
        ..lineTo(paw.dx, paw.dy),
      _stroke,
    );

    _fill.color = colour;
    canvas.drawOval(
      Rect.fromCenter(
        center: paw + Offset(r * 0.03, r * 0.03),
        width: r * 0.30,
        height: r * 0.17,
      ),
      _fill,
    );
  }

  void _renderLegs(Canvas canvas, Dog dog, double r, {required bool far}) {
    final phase = dog.gaitPhase * math.pi * 2;
    // The far pair is darker and thinner, which is the whole trick for depth on
    // a flat drawing.
    final colour = far ? Color.lerp(_dark, Palette.background, 0.35)! : _dark;
    final width = r * (far ? 0.21 : 0.25);
    final offset = far ? math.pi : 0.0;
    _leg(
      canvas,
      -r * (far ? 0.60 : 0.40),
      r * (far ? 0.10 : 0.16),
      phase + math.pi + offset,
      r,
      colour,
      width,
    );
    _leg(
      canvas,
      r * (far ? 0.38 : 0.58),
      r * 0.14,
      phase + offset,
      r,
      colour,
      width,
    );
  }

  void _renderTail(Canvas canvas, Dog dog, double r, double alert) {
    final excitement = math.max(game.wagBoost, alert);
    final speed = 3.2 + excitement * 9;
    final wag =
        math.sin(
          dog.gaitPhase * math.pi * speed +
              game.elapsed * (3.5 + excitement * 14),
        ) *
        (game.tuning.reducedMotion ? 0.0 : 0.5 + excitement * 0.8);

    // Tapered in two strokes: thick at the root, thin at the tip. A constant
    // width reads as wire.
    _stroke
      ..color = _body
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.24;
    canvas.drawPath(
      Path()
        ..moveTo(-r * 0.86, -r * 0.06)
        ..quadraticBezierTo(
          -r * 1.20,
          -r * (0.24 + wag * 0.22),
          -r * 1.30,
          -r * (0.52 + wag * 0.34),
        ),
      _stroke,
    );
    _stroke.strokeWidth = r * 0.14;
    canvas.drawPath(
      Path()
        ..moveTo(-r * 1.30, -r * (0.52 + wag * 0.34))
        ..quadraticBezierTo(
          -r * 1.38,
          -r * (0.80 + wag * 0.44),
          -r * 1.20,
          -r * (0.96 + wag * 0.50),
        ),
      _stroke,
    );
  }

  /// Chest, back and haunch as a single closed path, so she has a line rather
  /// than an outline made of circles.
  void _renderBody(Canvas canvas, double r, double weary) {
    final sag = weary * r * 0.07;
    final body = Path()
      ..moveTo(r * 0.70, -r * 0.28)
      ..cubicTo(
        r * 0.30,
        -r * 0.70 + sag,
        -r * 0.40,
        -r * 0.64 + sag,
        -r * 0.84,
        -r * 0.14,
      )
      ..cubicTo(-r * 1.00, r * 0.16, -r * 0.84, r * 0.46, -r * 0.50, r * 0.46)
      ..cubicTo(-r * 0.10, r * 0.52, r * 0.30, r * 0.50, r * 0.60, r * 0.34)
      ..cubicTo(r * 0.90, r * 0.18, r * 0.92, -r * 0.10, r * 0.70, -r * 0.28)
      ..close();

    _fill.color = _body;
    canvas.drawPath(body, _fill);

    // Paler underside, intersected with her outline so it reads as markings
    // rather than a shape sitting on top of her.
    //
    // Path.combine rather than canvas.clipPath: a clip forces the renderer to
    // allocate a layer, and stacking those inside an already transformed canvas
    // was painting a black rectangle across the board on device. This resolves
    // the geometry on the CPU instead, which is both correct and cheaper.
    _fill.color = _dark.withValues(alpha: 0.28);
    canvas.drawPath(
      Path.combine(
        PathOperation.intersect,
        body,
        Path()..addOval(
          Rect.fromCenter(
            center: Offset(-r * 0.1, r * 0.54),
            width: r * 1.9,
            height: r * 0.72,
          ),
        ),
      ),
      _fill,
    );
  }

  void _renderHead(
    Canvas canvas,
    Dog dog,
    double r,
    double alert,
    double weary,
    double startle,
  ) {
    // Nudged toward travel, so heading reads even though the body never rotates.
    final lead = Offset(
      math.cos(dog.facing).abs() * r * 0.1,
      math.sin(dog.facing) * r * 0.16,
    );
    final head = Offset(r * 0.76, -r * 0.50 + weary * r * 0.16) + lead;

    // Skull and muzzle as one silhouette, tapering to the nose. The taper is
    // what makes it a snout instead of a second ball.
    final skull = Path()
      ..moveTo(head.dx - r * 0.40, head.dy - r * 0.10)
      ..cubicTo(
        head.dx - r * 0.28,
        head.dy - r * 0.54,
        head.dx + r * 0.32,
        head.dy - r * 0.52,
        head.dx + r * 0.38,
        head.dy - r * 0.12,
      )
      ..cubicTo(
        head.dx + r * 0.60,
        head.dy - r * 0.02,
        head.dx + r * 0.84,
        head.dy + r * 0.06,
        head.dx + r * 0.86,
        head.dy + r * 0.22,
      )
      ..cubicTo(
        head.dx + r * 0.84,
        head.dy + r * 0.38,
        head.dx + r * 0.38,
        head.dy + r * 0.40,
        head.dx + r * 0.14,
        head.dy + r * 0.44,
      )
      ..cubicTo(
        head.dx - r * 0.20,
        head.dy + r * 0.48,
        head.dx - r * 0.44,
        head.dy + r * 0.22,
        head.dx - r * 0.40,
        head.dy - r * 0.10,
      )
      ..close();

    _fill.color = _body;
    canvas.drawPath(skull, _fill);
    // Keep the floppy ears visible against the skull at gameplay scale.
    _renderEars(canvas, dog, r, head, alert, weary);

    _stroke
      ..color = Palette.treat
      ..strokeWidth = r * 0.12
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      head + Offset(-r * 0.22, r * 0.35),
      head + Offset(r * 0.12, r * 0.43),
      _stroke,
    );
    _fill.color = Palette.treat;
    canvas.drawCircle(head + Offset(r * 0.02, r * 0.51), r * 0.10, _fill);
    _stroke
      ..color = _nose
      ..strokeWidth = r * 0.045;
    canvas.drawPath(
      Path()
        ..moveTo(head.dx + r * 0.35, head.dy + r * 0.26)
        ..quadraticBezierTo(
          head.dx + r * 0.53,
          head.dy + r * 0.36,
          head.dx + r * 0.69,
          head.dy + r * 0.25,
        ),
      _stroke,
    );

    _fill.color = _dark.withValues(alpha: 0.20);
    canvas.drawPath(
      Path.combine(
        PathOperation.intersect,
        skull,
        Path()..addOval(
          Rect.fromCenter(
            center: head + Offset(r * 0.62, r * 0.24),
            width: r * 0.72,
            height: r * 0.44,
          ),
        ),
      ),
      _fill,
    );

    _fill.color = _nose;
    canvas.drawOval(
      Rect.fromCenter(
        center: head + Offset(r * 0.82, r * 0.18),
        width: r * 0.22,
        height: r * 0.17,
      ),
      _fill,
    );

    // A brow. Two points of line, and most of what makes a face look like it
    // belongs to something alive rather than to a bead.
    _stroke
      ..color = _dark.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.07;
    final browLift = alert * 0.5 - weary * 0.4 + startle * 0.6;
    canvas.drawLine(
      head + Offset(r * 0.14, -r * (0.26 + browLift * 0.12)),
      head + Offset(r * 0.40, -r * (0.20 + browLift * 0.16)),
      _stroke,
    );

    final blink = !game.tuning.reducedMotion && game.elapsed % 4.7 > 4.54;
    final eyeOpen = blink ? 0.0 : (1 - game.despair) * (1 - weary * 0.35);
    if (eyeOpen > 0.08) {
      _fill.color = _nose;
      canvas.drawOval(
        Rect.fromCenter(
          center: head + Offset(r * 0.32, -r * 0.06),
          width: r * 0.17,
          height: r * 0.21 * eyeOpen * (1 + startle * 0.5),
        ),
        _fill,
      );
      // A catchlight. One dot, and she stops looking like a cut-out.
      _fill.color = const Color(0xCCFFFFFF);
      canvas.drawCircle(head + Offset(r * 0.35, -r * 0.11), r * 0.045, _fill);
    } else {
      _stroke
        ..color = _nose
        ..strokeWidth = r * 0.08;
      canvas.drawLine(
        head + Offset(r * 0.22, -r * 0.06),
        head + Offset(r * 0.42, -r * 0.06),
        _stroke,
      );
    }
  }

  /// Ears prick when she has seen dinner, droop as she tires, and lie flat when
  /// the run is over.
  void _renderEars(
    Canvas canvas,
    Dog dog,
    double r,
    Offset head,
    double alert,
    double weary,
  ) {
    final speed = (dog.velocity.distance / (r * 5)).clamp(0.0, 1.0);
    final motion = game.tuning.reducedMotion ? 0.0 : 1.0;
    final droop = game.despair * 0.22 + weary * 0.12;

    // Two separated ears rise above the crown, then trail toward the tail.
    // Animate the tips rather than rotating the whole ear across the face.
    for (final far in const [true, false]) {
      final flutter =
          math.sin(
            dog.gaitPhase * math.pi * 2 + game.elapsed * 3 + (far ? 1.2 : 0),
          ) *
          (0.04 + speed * 0.14) *
          motion;
      final sweep =
          speed * 0.22 + (dog.turnRate * 0.025).clamp(-0.10, 0.10) * motion;
      canvas.save();
      canvas.translate(head.dx + r * (far ? 0.13 : -0.22), head.dy - r * 0.32);
      final tipX = -r * (0.32 + sweep);
      final tipY = -r * (0.72 + alert * 0.12 - droop + flutter);
      final ear = Path()
        ..moveTo(-r * 0.18, r * 0.07)
        ..cubicTo(
          -r * 0.30,
          -r * 0.20,
          tipX - r * 0.22,
          tipY + r * 0.10,
          tipX,
          tipY,
        )
        ..cubicTo(
          tipX + r * 0.22,
          tipY - r * 0.05,
          r * 0.16,
          -r * 0.25,
          r * 0.14,
          r * 0.05,
        )
        ..close();
      _fill.color = far ? Color.lerp(_body, _dark, 0.30)! : _body;
      canvas.drawPath(ear, _fill);
      _stroke
        ..color = _dark
        ..strokeWidth = r * 0.055
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(ear, _stroke);
      _stroke
        ..color = _dark.withValues(alpha: 0.65)
        ..strokeWidth = r * 0.10
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(-r * 0.04, -r * 0.08)
          ..quadraticBezierTo(
            -r * 0.12,
            -r * 0.30,
            tipX + r * 0.02,
            tipY + r * 0.18,
          ),
        _stroke,
      );
      canvas.restore();
    }
  }

  /// Three fading prints so the drift path stays readable (§9.2).
  void _renderPawprints(Canvas canvas, Dog dog, double r) {
    for (final print in dog.pawprints) {
      final fade = (1 - print.age / 1.6).clamp(0.0, 1.0);
      _fill.color = _body.withValues(alpha: fade * 0.3);
      canvas.save();
      canvas.translate(print.position.dx, print.position.dy);
      canvas.rotate(print.angle + math.pi / 2);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 0.34, height: r * 0.42),
        _fill,
      );
      for (var i = -1; i <= 1; i++) {
        canvas.drawCircle(Offset(i * r * 0.16, -r * 0.3), r * 0.08, _fill);
      }
      canvas.restore();
    }
  }

  /// How long a powerup has left, as a ring closing around her (§6.2). Never a
  /// HUD number — the remaining time belongs where the player is looking.
  void _renderPowerupRing(Canvas canvas, Dog dog, double r) {
    final leading = game.powerups.leading;
    if (leading == null) {
      return;
    }
    final colour = Palette.forPickup(leading.kind);
    _stroke
      ..color = colour.withValues(alpha: 0.75)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: dog.position, radius: r * 2.1),
      -math.pi / 2,
      math.pi * 2 * leading.fraction,
      false,
      _stroke,
    );
  }

  /// When every way out is sealed, a ring closes over the grace period. Being
  /// crushed should never be a surprise (§10).
  void _renderEnclosureWarning(Canvas canvas, Dog dog, double r) {
    if (dog.enclosedFor <= 0) {
      return;
    }
    final t = (dog.enclosedFor / game.tuning.suffocateSeconds).clamp(0.0, 1.0);
    final radius = r * (2.6 - t * 1.4);
    _stroke
      ..color = Palette.danger.withValues(alpha: 0.35 + t * 0.5)
      ..strokeWidth = 1.6 + t * 2.2;
    canvas.drawArc(
      Rect.fromCircle(center: dog.position, radius: radius),
      -math.pi / 2,
      math.pi * 2 * (1 - t),
      false,
      _stroke,
    );
  }
}
