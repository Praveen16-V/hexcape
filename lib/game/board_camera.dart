import 'dart:math' as math;
import 'dart:ui';

import '../gen/silhouette.dart';

/// How the board is framed on screen.
///
/// **Zoom is deliberately not a difficulty lever.** Reach is defined in hex
/// units — `TuningConfig.tapRadiusFor` scales the tap radius by the hex width
/// against a fixed `referenceHexWidth` — so magnifying the board changes what
/// the player can *see* and never what they can *reach*. That is what makes
/// this safe to add to a campaign that is already balanced: the editable set at
/// 2.2x is the same set as at fit, cell for cell.
///
/// It exists because the fit is genuinely too small to read. Boards reach 12
/// columns by 29 rows, and fitting all of that on a 320-wide phone leaves a hex
/// about nineteen pixels across. Legibility was defended by tap *forgiveness*
/// — `InputSystem` snaps to the nearest clearable hex within three quarters of
/// a hex width — which keeps the game playable but does not make it readable.
///
/// The camera lives here rather than in Flame's `CameraComponent` because
/// everything that draws (the field, the dog, the effects, the movement cue)
/// and everything that resolves a tap already derives from a single
/// [HexLayout]. Folding zoom and focus into that layout's `size` and `origin`
/// means all of it keeps working untouched, and tap resolution stays correct
/// for free. A real camera component would mean re-parenting every component
/// into `world` and converting every tap, for the same result.
class BoardCamera {
  /// The zoom steps the HUD control cycles through.
  ///
  /// Three, not a continuous slider. A slider is a thing to fiddle with while
  /// the hunger clock runs; a cycle button is one tap to magnify and one tap
  /// back to the whole board, which is the only two states a player actually
  /// wants mid-level.
  static const steps = <double>[1.0, 1.6, 2.2];

  /// Fit-to-screen. At exactly this the framing is identical to the game that
  /// shipped without a camera, and several tests depend on that.
  static const minZoom = 1.0;

  /// How far ahead of the dog the view leads, in hexes.
  ///
  /// Zoomed in, centring on her exactly shows where she has *been*. The whole
  /// reason to carve is to decide where she goes next, so the view biases
  /// toward her heading.
  static const _leadHexes = 1.6;

  /// The share of the viewport she may wander in before the camera reacts.
  ///
  /// She drifts constantly and never stops, so a camera locked to her would
  /// never be still. Forty percent is wide enough that ordinary drift moves
  /// nothing on screen.
  static const _deadZone = 0.40;

  /// How fast the focus closes on its target, per second.
  static const _followRate = 6.0;

  /// Past this many hexes behind, the camera stops easing and jumps.
  ///
  /// A spring throws her at eight and a half hexes a second. Easing at that
  /// speed loses her off the edge of a zoomed viewport, and a dog the player
  /// cannot see is worse than a camera that cut.
  static const _snapDistance = 3.0;

  double _zoom = minZoom;

  /// The point in unit space the viewport centres on.
  Offset focus = Offset.zero;

  double get zoom => _zoom;

  /// Whether the whole board is framed — the state every pre-camera assumption
  /// in the game and its tests was written against.
  bool get isFit => _zoom <= minZoom;

  set zoom(double value) {
    _zoom = math.max(minZoom, value);
  }

  /// The next step up, wrapping back to fit. The HUD control's whole behaviour.
  void cycle() {
    final current = steps.indexWhere((s) => (s - _zoom).abs() < 0.01);
    _zoom = steps[(current + 1) % steps.length];
  }

  void reset() {
    focus = Offset.zero;
  }

  /// Where the viewport should sit to frame [dogUnit], given where she is
  /// heading.
  ///
  /// [heading] is her velocity in unit space per second; zero when she is
  /// still, which simply drops the lead.
  Offset targetFor(Offset dogUnit, Offset heading) {
    if (heading == Offset.zero) {
      return dogUnit;
    }
    final speed = heading.distance;
    if (speed < 1e-6) {
      return dogUnit;
    }
    return dogUnit + (heading / speed) * _leadHexes;
  }

  /// Move [focus] toward [target], but only once the dog has left the dead zone.
  ///
  /// [halfView] is half the viewport in unit space, so the dead zone scales
  /// with how much board is actually on screen.
  void follow(
    Offset target,
    Offset halfView,
    double dt, {
    bool instant = false,
  }) {
    final deadX = halfView.dx * _deadZone;
    final deadY = halfView.dy * _deadZone;
    final dx = target.dx - focus.dx;
    final dy = target.dy - focus.dy;

    var wantX = focus.dx;
    var wantY = focus.dy;
    if (dx.abs() > deadX) {
      wantX = target.dx - deadX * (dx.isNegative ? -1 : 1);
    }
    if (dy.abs() > deadY) {
      wantY = target.dy - deadY * (dy.isNegative ? -1 : 1);
    }

    final want = Offset(wantX, wantY);
    if (instant || (want - focus).distance > _snapDistance) {
      focus = want;
      return;
    }
    // Exponential rather than a fixed step, so the rate is the same whatever
    // the frame time — a stutter must not make the camera lurch.
    final k = 1 - math.exp(-_followRate * dt);
    focus = focus + (want - focus) * k;
  }

  /// Pull [focus] back until the viewport is covered by board on both axes.
  ///
  /// An axis where the board is smaller than the viewport is centred instead,
  /// which is what makes fit-to-screen fall out of this rather than being a
  /// special case bolted beside it.
  Offset clampedFocus({
    required UnitBounds bounds,
    required double hexSize,
    required Size viewport,
  }) {
    // Cell positions are centres, so the board reaches half a hex further out
    // on every side — the same bleed the fit calculation allows for.
    const bleedX = 1.7320508075688772 / 2;
    const bleedY = 1.0;
    final minX = bounds.minX - bleedX;
    final maxX = bounds.maxX + bleedX;
    final minY = bounds.minY - bleedY;
    final maxY = bounds.maxY + bleedY;

    final halfX = viewport.width / (2 * hexSize);
    final halfY = viewport.height / (2 * hexSize);

    double axis(double lo, double hi, double half, double want) {
      final low = lo + half;
      final high = hi - half;
      // Board narrower than the viewport on this axis: centre it, exactly as
      // the game did everywhere before there was a camera.
      if (low >= high) {
        return (lo + hi) / 2;
      }
      return want.clamp(low, high);
    }

    return Offset(
      axis(minX, maxX, halfX, focus.dx),
      axis(minY, maxY, halfY, focus.dy),
    );
  }

  /// The centre of the board in unit space.
  static Offset centreOf(UnitBounds bounds) =>
      Offset((bounds.minX + bounds.maxX) / 2, (bounds.minY + bounds.maxY) / 2);
}
