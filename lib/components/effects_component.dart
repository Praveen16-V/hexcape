import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../hex/hex_layout.dart';
import '../theme/palette.dart';
import 'glyphs.dart';

/// One fragment of a shattered hex. §10 asks for a shard burst rather than a
/// generic particle puff, so the fragments are little hexagons — the shape
/// echoes what just broke.
class _Shard {
  _Shard({
    required this.position,
    required this.velocity,
    required this.size,
    required this.angle,
    required this.spin,
    required this.life,
    required this.colour,
  }) : maxLife = life;

  Offset position;
  Offset velocity;
  double size;
  double angle;
  double spin;
  double life;
  final double maxLife;
  final Color colour;
}

class _Ripple {
  _Ripple(this.centre, this.radius, this.colour);

  final Offset centre;
  final double radius;
  final Color colour;
  double t = 0;
}

class _BoneParticle {
  _BoneParticle({
    required this.position,
    required this.velocity,
    required this.size,
    required this.angle,
    required this.spin,
    required this.life,
    required this.gravity,
  }) : maxLife = life;

  Offset position;
  Offset velocity;
  final double size;
  double angle;
  final double spin;
  double life;
  final double maxLife;
  final double gravity;
}

/// Shards and shockwaves. Kept in one component with a hard particle cap so
/// the effects layer can never be what breaks the 60fps budget (§13.3).
class EffectsComponent extends Component {
  EffectsComponent() : super(priority: 10);

  static const _maxShards = 120;
  static const _maxBones = 36;
  static const _shardLife = 0.55;

  final List<_Shard> _shards = [];
  final List<_Ripple> _ripples = [];
  final List<_BoneParticle> _bones = [];
  final math.Random _rng = math.Random();

  bool get isBusy =>
      _shards.isNotEmpty || _ripples.isNotEmpty || _bones.isNotEmpty;

  int get boneCount => _bones.length;

  void boneShower(
    Offset centre,
    double hexSize, {
    required bool reducedMotion,
  }) {
    final count = reducedMotion ? 8 : 30;
    for (var i = 0; i < count && _bones.length < _maxBones; i++) {
      final radial = reducedMotion;
      final angle = radial
          ? (math.pi * 2 * i / count)
          : _rng.nextDouble() * math.pi * 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      _bones.add(
        _BoneParticle(
          position: radial
              ? centre
              : centre +
                    Offset(
                      (_rng.nextDouble() - 0.5) * hexSize * 7,
                      -hexSize * (3 + _rng.nextDouble() * 3),
                    ),
          velocity: radial
              ? direction * hexSize * 2.8
              : Offset(
                  (_rng.nextDouble() - 0.5) * hexSize * 1.8,
                  hexSize * (2.2 + _rng.nextDouble() * 2.2),
                ),
          size: hexSize * (0.16 + _rng.nextDouble() * 0.12),
          angle: _rng.nextDouble() * math.pi * 2,
          spin: radial ? 0 : (_rng.nextDouble() - 0.5) * 8,
          life: radial ? 0.48 : 1.25 + _rng.nextDouble() * 0.35,
          gravity: radial ? 0 : hexSize * 5.5,
        ),
      );
    }
  }

  /// A hex shattering into 5-6 fragments that scatter outward and fade (§10).
  void shatter(
    Offset centre,
    double hexSize, {
    Color? colour,
    double boost = 1,
  }) {
    if (_shards.length >= _maxShards) {
      return;
    }
    final count = 5 + _rng.nextInt(2);
    final baseAngle = _rng.nextDouble() * math.pi * 2;
    for (var i = 0; i < count; i++) {
      final angle =
          baseAngle + (math.pi * 2 / count) * i + _rng.nextDouble() * 0.4;
      final speed = hexSize * (2.2 + _rng.nextDouble() * 2.6) * boost;
      final direction = Offset(math.cos(angle), math.sin(angle));
      _shards.add(
        _Shard(
          position: centre + direction * hexSize * 0.2,
          velocity: direction * speed,
          size: hexSize * (0.16 + _rng.nextDouble() * 0.16),
          angle: _rng.nextDouble() * math.pi,
          spin: (_rng.nextDouble() - 0.5) * 9,
          life: _shardLife * (0.75 + _rng.nextDouble() * 0.5),
          colour: colour ?? Palette.plainEdge,
        ),
      );
    }
  }

  /// The ripple a hex throws off when it snaps shut again (§10, stage three).
  void ripple(
    Offset centre,
    double radius, {
    Color colour = Palette.shockwave,
  }) {
    _ripples.add(_Ripple(centre, radius, colour));
  }

  void clear() {
    _shards.clear();
    _ripples.clear();
    _bones.clear();
  }

  @override
  void update(double dt) {
    for (final shard in _shards) {
      shard.position += shard.velocity * dt;
      // Drag, so fragments decelerate instead of flying off the field.
      shard.velocity *= math.pow(0.06, dt).toDouble();
      shard.angle += shard.spin * dt;
      shard.life -= dt;
    }
    _shards.removeWhere((s) => s.life <= 0);

    for (final ripple in _ripples) {
      ripple.t += dt / 0.42;
    }
    _ripples.removeWhere((r) => r.t >= 1);

    for (final bone in _bones) {
      bone.velocity += Offset(0, bone.gravity * dt);
      bone.position += bone.velocity * dt;
      bone.angle += bone.spin * dt;
      bone.life -= dt;
    }
    _bones.removeWhere((bone) => bone.life <= 0);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final shard in _shards) {
      final fade = (shard.life / shard.maxLife).clamp(0.0, 1.0);
      paint.color = shard.colour.withValues(alpha: fade);
      canvas.save();
      canvas.translate(shard.position.dx, shard.position.dy);
      canvas.rotate(shard.angle);
      canvas.drawPath(
        HexLayout.pathFromCorners(
          HexLayout.cornersAt(Offset.zero, shard.size * (0.4 + fade * 0.6)),
        ),
        paint,
      );
      canvas.restore();
    }

    final ring = Paint()..style = PaintingStyle.stroke;
    for (final r in _ripples) {
      final eased = 1 - math.pow(1 - r.t, 3).toDouble();
      ring
        ..color = r.colour.withValues(alpha: (1 - r.t) * 0.55)
        ..strokeWidth = 2.4 * (1 - r.t) + 0.4;
      canvas.drawCircle(r.centre, r.radius * (0.55 + eased * 1.1), ring);
    }

    for (final bone in _bones) {
      final fade = (bone.life / bone.maxLife).clamp(0.0, 1.0);
      paint.color = Palette.treat.withValues(alpha: math.min(1, fade * 1.5));
      canvas.save();
      canvas.translate(bone.position.dx, bone.position.dy);
      canvas.rotate(bone.angle);
      canvas.drawPath(bonePath(bone.size), paint);
      canvas.restore();
    }
  }
}
