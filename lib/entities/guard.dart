import 'dart:ui';

import '../hex/hex_coord.dart';
import '../hex/hex_layout.dart';

/// A patrolling light that sweeps back and forth over the field (§6.1).
///
/// It does not clear hexes, and hexes do not stop it — it passes over solid
/// ground and open ground alike, because it is a light rather than a body. That
/// is what makes it implementable on a board which is almost entirely solid at
/// the start of a level, and it is also the more interesting obstacle: a guard
/// that could be walled out would simply be another wall, and the game already
/// has walls. This one cannot be tapped away, only waited out.
///
/// The pressure it applies is **timing**, which nothing else in the game did.
/// Every other obstacle is answered by choosing a different route; a patrol is
/// answered by choosing a different *moment*, and the hunger clock is what makes
/// waiting cost something.
class Guard {
  Guard({required this.patrol, this.cellsPerSecond = 0.85})
    : assert(patrol.length >= 2, 'a patrol of one cell never moves');

  /// The route it walks, end to end and back again.
  final List<HexCoord> patrol;

  final double cellsPerSecond;

  int index = 0;
  bool forward = true;

  /// Progress from [cell] toward [nextCell], 0..1.
  double t = 0;

  /// 1 -> 0 after it catches her. Drives the flare.
  double alertFlash = 0;

  HexCoord get cell => patrol[index];

  /// Where it is heading. At either end of the patrol it is already turning,
  /// so the answer is the cell behind it.
  HexCoord get nextCell {
    final step = forward ? 1 : -1;
    final n = index + step;
    if (n < 0 || n >= patrol.length) {
      return patrol[index - step];
    }
    return patrol[n];
  }

  /// The cell the light is actually over, which is what gameplay reads.
  ///
  /// Rounded from the interpolated position rather than held at [cell] for the
  /// whole step: otherwise the drawn light and the forbidden ground disagree by
  /// up to a full hex, and being caught looks like a bug.
  HexCoord get litCentre => t < 0.5 ? cell : nextCell;

  /// The ground she will not walk into.
  Iterable<HexCoord> get lit sync* {
    final centre = litCentre;
    yield centre;
    yield* centre.neighbours;
  }

  Offset positionIn(HexLayout layout) =>
      Offset.lerp(layout.toPixel(cell), layout.toPixel(nextCell), t)!;

  void update(double dt) {
    alertFlash = alertFlash - dt * 2.2;
    if (alertFlash < 0) {
      alertFlash = 0;
    }
    t += dt * cellsPerSecond;
    while (t >= 1) {
      t -= 1;
      _advance();
    }
  }

  void _advance() {
    final step = forward ? 1 : -1;
    final next = index + step;
    if (next < 0 || next >= patrol.length) {
      forward = !forward;
      index += forward ? 1 : -1;
    } else {
      index = next;
    }
  }
}
