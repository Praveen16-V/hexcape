import 'dart:math' as math;
import 'dart:ui';

import '../hex/hex_cell.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';
import '../hex/hex_layout.dart';

enum TapOutcome {
  /// The tap landed on a cell a tap can work on. Whether that opens it or only
  /// cracks it is up to the cell — see [HexCell.hit]. Resolution stays pure;
  /// the game owns the mutation.
  hit,

  /// The tap landed squarely on an anchor. Reported rather than redirected.
  anchor,

  /// Too far from the dog to edit (§2.1).
  outOfRange,

  /// In range, but nothing left to clear there.
  nothingToClear,
}

class TapResult {
  const TapResult(this.outcome, [this.coord]);

  final TapOutcome outcome;
  final HexCoord? coord;
}

/// Tap resolution (§2.1) — the single most important rule in the game.
///
/// The player may only edit near the dog, and they tap *near* a hex rather
/// than precisely on one: the nearest clearable hex to the tap point wins. That
/// forgiveness is what lets difficulty scale through density without punishing
/// finger precision (§7).
///
/// One deliberate exception: a tap that lands squarely on an anchor is
/// reported as an anchor, not quietly redirected to a clearable neighbour.
/// Silently doing something else with a deliberate tap teaches the player the
/// wrong model of the rules.
class InputSystem {
  InputSystem._();

  static TapResult resolve({
    required Offset point,
    required HexGrid grid,
    required HexLayout layout,
    required Offset dogPosition,
    required double tapRadius,
  }) {
    // A wild tap across the screen must not carve next to the dog, but the
    // boundary itself stays forgiving by about one hex.
    if ((point - dogPosition).distance > tapRadius + layout.width) {
      return const TapResult(TapOutcome.outOfRange);
    }

    final direct = layout.toHex(point);
    final directCell = grid.at(direct);
    if (directCell != null && directCell.type == HexType.anchor) {
      return TapResult(TapOutcome.anchor, direct);
    }

    bool inReach(HexCoord c) =>
        (layout.toPixel(c) - dogPosition).distance <= tapRadius;

    // An exact hit wins outright. Resolving the hex actually under the finger
    // first means a deliberate tap is never reinterpreted as something else.
    if (directCell != null && directCell.isClearable && inReach(direct)) {
      return TapResult(TapOutcome.hit, direct);
    }

    // A hex is editable when its centre falls inside the ring drawn around the
    // dog. Keeping that rule crisp is what makes the ring mean something.
    final rings = (tapRadius / layout.width).ceil() + 1;
    final dogCell = layout.toHex(dogPosition);

    HexCoord? best;
    var bestDistance = double.infinity;
    for (final coord in dogCell.disc(rings)) {
      if (!grid.isClearable(coord) || !inReach(coord)) {
        continue;
      }
      final d = (layout.toPixel(coord) - point).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = coord;
      }
    }

    // The snap has to be *bounded*. Without a limit, tapping a hex that cannot
    // be cleared — an open pit, or one whose centre sits just outside the ring —
    // silently shatters whatever clearable tile happened to be nearest, which
    // can be two or three cells from where the finger landed. That is not
    // forgiveness, it is the game overruling a deliberate tap, and it reads as
    // the wrong tile breaking.
    //
    // Adjacent centres are one hex width apart, so this limit lets a tap near a
    // shared edge fall through to the neighbour the player was reaching for,
    // while a tap in the dead centre of a pit correctly does nothing at all.
    if (best == null || bestDistance > _maxSnap(layout) * _maxSnap(layout)) {
      return const TapResult(TapOutcome.nothingToClear);
    }
    return TapResult(TapOutcome.hit, best);
  }

  /// How far a tap may be redirected from where it actually landed.
  static double _maxSnap(HexLayout layout) => layout.width * 0.75;

  /// Every hex the player could clear right now. The renderer uses this to
  /// light the editable area, which is how §2.1 is taught without text (§12.5).
  static List<HexCoord> editableCells({
    required HexGrid grid,
    required HexLayout layout,
    required Offset dogPosition,
    required double tapRadius,
  }) {
    final rings = math.max(1, (tapRadius / layout.width).ceil() + 1);
    final dogCell = layout.toHex(dogPosition);
    return [
      for (final coord in dogCell.disc(rings))
        if (grid.isClearable(coord) &&
            (layout.toPixel(coord) - dogPosition).distance <= tapRadius)
          coord,
    ];
  }
}
