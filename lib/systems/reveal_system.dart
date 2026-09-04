import 'dart:math' as math;
import 'dart:ui';

import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';
import '../hex/hex_layout.dart';

/// What the player has learned about the board.
///
/// A cell's *state* is never hidden — a hole is obviously a hole — but its
/// *type* is, until the dog has been near enough to see it. Without this the
/// whole obstacle map is readable before the first tap, and §2.1's "cannot plan
/// the full route in advance… carve blind, discovering the path as they go"
/// simply does not happen.
///
/// Reveal is permanent for the run. Re-hiding would make the player feel
/// amnesiac and would punish exploring the very thing they are meant to
/// explore; keeping it means knowledge accumulates, and replaying a seed rewards
/// what was learned last time.
class RevealSystem {
  RevealSystem._();

  /// The reveal radius must always exceed the tap radius. Inside the tap ring
  /// the editable highlight lights up clearable cells and skips anchors, so a
  /// smaller sight radius would give anchors away by omission — the fog would
  /// leak exactly what it exists to hide.
  static double radiusFor(double tapRadius, double factor) =>
      tapRadius * math.max(1.2, factor);

  /// Reveals everything close enough to see. Returns how many cells were newly
  /// learned this call.
  static int reveal({
    required HexGrid grid,
    required HexLayout layout,
    required Offset dogPosition,
    required HexCoord dogCell,
    required double radius,
  }) {
    final rings = math.max(1, (radius / layout.width).ceil() + 1);
    var learned = 0;
    for (final coord in dogCell.disc(rings)) {
      final cell = grid.at(coord);
      if (cell == null || cell.revealed) {
        continue;
      }
      if ((layout.toPixel(coord) - dogPosition).distance <= radius) {
        cell.revealed = true;
        learned++;
      }
    }
    return learned;
  }
}
