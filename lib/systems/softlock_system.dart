import '../gen/pathfinder.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';

/// Soft-lock detection (§4). A correctness requirement, not a convenience:
/// without it a player can end up watching a dead field regrow around them
/// with no recourse, which is worse than any missing hint.
///
/// The test is not "is there a route" but **"is there a route I can still
/// afford"**: the cheapest way from the dog to the food, where cells already
/// open are free and solid ones cost the taps still needed to open them. Locked
/// when that exceeds the taps the player has left.
///
/// Costing it this way is what makes a wasted tap matter immediately. It also
/// means the check finally does real work — with unlimited taps and only static
/// anchors it was effectively an invariant assertion that never fired.
///
/// Deliberately **optimistic**: it ignores regrowth that has not happened yet,
/// so a corridor the player will have to re-open counts as free. Erring this way
/// means the run only ever ends when finishing is genuinely impossible, never
/// when it merely looks unlikely.
class SoftlockSystem {
  HexCoord? _lastCell;
  int _lastFieldVersion = -1;
  int _lastTapsLeft = -1;
  bool _locked = false;

  bool get isLocked => _locked;

  /// Re-runs only when the field or the dog's cell actually changed, so this
  /// costs nothing on a quiet frame.
  bool check({
    required HexGrid grid,
    required HexCoord dogCell,
    required int fieldVersion,
    required int tapsLeft,
  }) {
    if (dogCell == _lastCell &&
        fieldVersion == _lastFieldVersion &&
        tapsLeft == _lastTapsLeft) {
      return _locked;
    }
    _lastCell = dogCell;
    _lastFieldVersion = fieldVersion;
    _lastTapsLeft = tapsLeft;

    final cost = Pathfinder.cheapestCost(
      dogCell,
      grid.exit,
      grid.isTraversableInPrinciple,
      grid.remainingCost,
    );
    _locked = cost == null || cost > tapsLeft;
    return _locked;
  }

  void reset() {
    _lastCell = null;
    _lastFieldVersion = -1;
    _lastTapsLeft = -1;
    _locked = false;
  }
}
