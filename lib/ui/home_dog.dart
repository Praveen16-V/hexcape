import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/pets.dart';
import '../components/glyphs.dart';
import '../theme/palette.dart';

/// The dog, at rest, on the home screen.
///
/// Deliberately not `DogComponent` (`lib/components/dog_component.dart`):
/// that one is wired to a live `Dog`'s physics, gait and hunger, none of
/// which exists before a level has started. This redraws the same
/// silhouette — body, head, ears, tail — standing still, with a small idle
/// breath and tail wag, so the front door shows whose game this is without
/// borrowing state that only exists mid-run.
class HomeDog extends StatefulWidget {
  const HomeDog({
    required this.pet,
    required this.size,
    this.reducedMotion = false,
    super.key,
  });

  final Pet pet;
  final double size;
  final bool reducedMotion;

  @override
  State<HomeDog> createState() => _HomeDogState();
}

class _HomeDogState extends State<HomeDog> with SingleTickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(HomeDog oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.reducedMotion || MediaQuery.disableAnimationsOf(context)) {
      _idle.stop();
      _idle.value = 0;
    } else if (!_idle.isAnimating) {
      _idle.repeat();
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _idle,
        builder: (context, _) => CustomPaint(
          painter: _HomeDogPainter(pet: widget.pet, phase: _idle.value),
        ),
      ),
    );
  }
}

class _HomeDogPainter extends CustomPainter {
  _HomeDogPainter({required this.pet, required this.phase});

  final Pet pet;

  /// 0 to 1, looping. Drives the breath, the tail wag and a small ear sway —
  /// enough life for a still screen without pretending to be a running game.
  final double phase;

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// The pet's coat, richer than the in-game colour. A dog standing still and
  /// full-size on an otherwise empty screen reads as pale next to the same
  /// hue spent on a few small legs and a muzzle mid-level — so the home
  /// screen asks for more saturation than the shared [Pet] palette carries,
  /// without changing that palette for the game itself.
  Color get _body => _vivid(pet.body);
  Color get _dark => _vivid(pet.dark);

  static Color _vivid(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * 1.45).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.94).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.26;
    final centre = Offset(size.width / 2, size.height * 0.61);
    final breathe = 1 + 0.035 * math.sin(phase * math.pi * 2);
    final wag = math.sin(phase * math.pi * 2 * 3);
    final sway = math.sin(phase * math.pi * 2) * 0.12;

    // The bone floats above the nose, clear of the dog's silhouette, with a
    // thought-bubble trail leading up from her head — a daydream rather than
    // a prop that happens to share the scene with her.
    final bonePos = Offset(
      size.width * 0.73,
      size.height * 0.18 + math.sin(phase * math.pi * 2) * r * 0.12,
    );
    final headPos = Offset(
      size.width / 2 + r * 0.86,
      size.height * 0.61 - r * 0.92,
    );
    for (final t in const [0.32, 0.6]) {
      final dot = Offset.lerp(headPos, bonePos, t)!;
      _fill.color = Palette.treat.withValues(
        alpha: 0.35 + 0.25 * math.sin(phase * math.pi * 2),
      );
      canvas.drawCircle(dot, r * (0.05 + t * 0.09), _fill);
    }

    canvas.save();
    canvas.translate(bonePos.dx, bonePos.dy);
    canvas.rotate(-0.3 + math.sin(phase * math.pi * 2) * 0.18);
    _fill.color = Palette.treat;
    canvas.drawPath(bonePath(r * 0.75), _fill);
    canvas.restore();

    _renderShadow(canvas, centre, r);
    _renderGlow(canvas, centre, r);

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(1, breathe);

    _renderLegs(canvas, r);
    _renderTail(canvas, r, wag);
    _renderBody(canvas, r);
    _renderHead(canvas, r, sway);

    canvas.restore();
  }

  void _renderShadow(Canvas canvas, Offset centre, double r) {
    _fill
      ..color = const Color(0x33000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.3);
    canvas.drawOval(
      Rect.fromCenter(
        center: centre.translate(0, r * 0.95),
        width: r * 2.1,
        height: r * 0.55,
      ),
      _fill,
    );
    _fill.maskFilter = null;
  }

  void _renderGlow(Canvas canvas, Offset centre, double r) {
    _fill
      ..color = pet.glow.withValues(alpha: pet.glow.a * 0.6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.9);
    canvas.drawCircle(centre, r * 1.15, _fill);
    _fill.maskFilter = null;
  }

  /// [swing] splays the knee and paw sideways from the hip — the same axis
  /// the in-game dog's gait swings a leg along, held at a fixed small value
  /// here instead of animating it. Without it, a far and near leg sharing
  /// (almost) the same hip position draw on top of each other and read as
  /// one thick leg instead of two.
  void _leg(
    Canvas canvas,
    double hipX,
    double hipY,
    double swing,
    double r,
    Color colour,
  ) {
    final knee = Offset(hipX + swing * r * 0.20, hipY + r * 0.32);
    final paw = Offset(hipX + swing * r * 0.42, hipY + r * 0.64);
    _stroke
      ..color = colour
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = r * 0.22;
    canvas.drawPath(
      Path()
        ..moveTo(hipX, hipY)
        ..lineTo(knee.dx, knee.dy)
        ..lineTo(paw.dx, paw.dy),
      _stroke,
    );
    _fill.color = colour;
    canvas.drawOval(
      Rect.fromCenter(center: paw, width: r * 0.30, height: r * 0.17),
      _fill,
    );
  }

  /// Standing square, not mid-stride — the far pair darker and set back, the
  /// same trick the in-game dog uses for depth on a flat drawing. Each pair
  /// shares a hip like the in-game dog's does, splayed apart just enough to
  /// read as two legs rather than one.
  void _renderLegs(Canvas canvas, double r) {
    final far = Color.lerp(_dark, Palette.background, 0.35)!;
    _leg(canvas, -r * 0.46, r * 0.16, -0.5, r, far);
    _leg(canvas, r * 0.50, r * 0.14, 0.5, r, far);
    _leg(canvas, -r * 0.46, r * 0.16, 0.2, r, _dark);
    _leg(canvas, r * 0.50, r * 0.14, -0.2, r, _dark);
  }

  void _renderTail(Canvas canvas, double r, double wag) {
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

  /// Chest, back and haunch as one closed path, same curve the in-game dog
  /// uses — proven to read as an animal rather than a stack of ovals.
  void _renderBody(Canvas canvas, double r) {
    final body = Path()
      ..moveTo(r * 0.70, -r * 0.28)
      ..cubicTo(r * 0.30, -r * 0.70, -r * 0.40, -r * 0.64, -r * 0.84, -r * 0.14)
      ..cubicTo(-r * 1.00, r * 0.16, -r * 0.84, r * 0.46, -r * 0.50, r * 0.46)
      ..cubicTo(-r * 0.10, r * 0.52, r * 0.30, r * 0.50, r * 0.60, r * 0.34)
      ..cubicTo(r * 0.90, r * 0.18, r * 0.92, -r * 0.10, r * 0.70, -r * 0.28)
      ..close();

    _fill.color = _body;
    canvas.drawPath(body, _fill);

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

  void _renderHead(Canvas canvas, double r, double sway) {
    final head = Offset(r * 0.76, -r * 0.50 + sway * r * 0.45);

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

    // Drawn on top of the skull rather than under it — a still pose has no
    // gait to swing an ear clear of the head silhouette the way the in-game
    // dog's does, so on top is what keeps it visible at all. Positioned
    // toward the back of the head, well clear of the nose and eye below.
    _renderEars(canvas, r, head, sway);

    _fill.color = pet.nose;
    canvas.drawOval(
      Rect.fromCenter(
        center: head + Offset(r * 0.82, r * 0.18),
        width: r * 0.22,
        height: r * 0.17,
      ),
      _fill,
    );

    _stroke
      ..color = _dark.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.07;
    canvas.drawLine(
      head + Offset(r * 0.14, -r * 0.26),
      head + Offset(r * 0.40, -r * 0.20),
      _stroke,
    );

    _fill.color = pet.nose;
    canvas.drawOval(
      Rect.fromCenter(
        center: head + Offset(r * 0.32, -r * 0.06),
        width: r * 0.17,
        height: r * 0.21 * (phase > 0.90 && phase < 0.95 ? 0.12 : 1),
      ),
      _fill,
    );
    // A catchlight. One dot, and she stops looking like a cut-out.
    _fill.color = const Color(0xCCFFFFFF);
    if (phase <= 0.90 || phase >= 0.95) {
      canvas.drawCircle(head + Offset(r * 0.35, -r * 0.11), r * 0.045, _fill);
    }
  }

  void _renderEars(Canvas canvas, double r, Offset head, double sway) {
    for (final side in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(
        head.dx - r * 0.08 + r * 0.12 * side,
        head.dy - r * 0.32,
      );
      canvas.rotate(side * 0.35 + sway);

      final ear = Path()
        ..moveTo(-r * 0.16, 0)
        ..quadraticBezierTo(-r * 0.26, r * 0.44, -r * 0.03, r * 0.60)
        ..quadraticBezierTo(r * 0.20, r * 0.40, r * 0.16, 0)
        ..close();
      _fill.color = _body;
      canvas.drawPath(ear, _fill);

      _fill.color = _dark.withValues(alpha: 0.45);
      canvas.drawPath(
        Path.combine(
          PathOperation.intersect,
          ear,
          ear.shift(Offset(r * 0.03, r * 0.12)),
        ),
        _fill,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_HomeDogPainter old) =>
      old.phase != phase || old.pet != pet;
}
