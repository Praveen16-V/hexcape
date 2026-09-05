import '../game/tuning.dart';
import '../hex/hex_cell.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';

/// What happened this frame, so the game can fire haptics and bump the field
/// version without the system reaching back into it.
class RegrowthEvents {
  /// Cells that just entered their warning pulses.
  final List<HexCoord> warned = [];

  /// Cells that just closed. These are what change the field graph.
  final List<HexCoord> snapped = [];

  bool get fieldChanged => snapped.isNotEmpty;
}

/// Regrowth (§2.3): the field closes back in, so stalling costs you space and
/// backtracking becomes genuinely impossible. No countdown clock needed.
///
/// Two rules carry the whole feel here:
///
/// * **Outside-in.** A cleared cell only becomes eligible once it borders
///   something solid, and its delay is measured from the moment it became a
///   boundary — not from when it was cleared. An interior cell that is exposed
///   later therefore gets the full warning rather than snapping shut instantly.
/// * **Warned, never sudden.** Every cell runs the three-stage animation
///   before it blocks anything, and the cell under the dog holds short of the
///   snap. Being crushed is always something the player could see coming.
class RegrowthSystem {
  RegrowthEvents update({
    required double dt,
    required double now,
    required HexGrid grid,
    required TuningConfig tuning,
    required HexCoord dogCell,
  }) {
    final events = RegrowthEvents();

    for (final cell in grid.all) {
      switch (cell.state) {
        case CellState.solid:
          break;

        case CellState.open:
          // A fault is eligible the moment it is cleared, wherever it is. That
          // one exemption is the whole mechanic: it closes in the middle of an
          // open pocket, so the ground *ahead* of her is on a clock too.
          final always = cell.type.closesOnItsOwn;
          final onBoundary = always || cell.coord.neighbours.any(grid.blocks);
          if (!onBoundary) {
            cell.eligibleSince = null;
            continue;
          }
          cell.eligibleSince ??= now;
          final delay = always ? tuning.faultDelay : tuning.regrowDelay;
          if (now - cell.eligibleSince! >= delay) {
            cell.state = CellState.regrowing;
            cell.regrowT = 0;
          }

        case CellState.regrowing:
          final before = cell.regrowT;
          cell.regrowT += dt / RegrowAnim.duration;

          // The cell the dog is standing in holds at the last pulse instead of
          // closing on top of it. The player always has a way out; staying put
          // until the grace period runs down is what kills them, not this.
          if (cell.coord == dogCell && cell.regrowT > RegrowAnim.dogHold) {
            cell.regrowT = RegrowAnim.dogHold;
          }

          if (before < RegrowAnim.ghostEnd &&
              cell.regrowT >= RegrowAnim.ghostEnd) {
            events.warned.add(cell.coord);
          }

          if (cell.regrowT >= 1.0) {
            cell.state = CellState.solid;
            cell.regrowT = 0;
            cell.eligibleSince = null;
            cell.snapRipple = 1;
            events.snapped.add(cell.coord);
          }
      }
    }

    return events;
  }

  /// Zen mode still needs cells to finish animations already in flight, but
  /// nothing new may start closing.
  void settleForZen(HexGrid grid) {
    for (final cell in grid.all) {
      if (cell.state == CellState.regrowing) {
        cell.state = CellState.open;
        cell.regrowT = 0;
      }
      cell.eligibleSince = null;
    }
  }
}
