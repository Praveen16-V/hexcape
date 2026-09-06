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

    /// All cells touched by the dog's collision body. The centre-point
    /// [dogCell] remains the fallback for callers that do not simulate a
    /// physical position.
    Set<HexCoord> dogOccupiedCells = const {},

    /// Open ground inside the aura of a living overgrowth heart. Regrowth
    /// there runs at double pace while the heart stands — the heart is the
    /// thing closing the pocket, and digging it out is the answer.
    Set<HexCoord> overgrowthAura = const {},

    /// Seconds a crossed thatch braid holds before snapping. Separate from
    /// [TuningConfig.faultDelay] because the two ask different questions: a
    /// fault is a clock on the field, a braid is a clock on her crossing.
    double thatchDelay = 0.5,

    /// Added to every field-closing clock (regrow and fault alike). A braid
    /// waits for its crossing, so its snap stays hers and stands outside
    /// this. Zero by default; a pet's regrowth boon rides here rather than on
    /// [tuning], because tuning is the player's settings and must restart
    /// clean each level.
    double extraDelay = 0,
  }) {
    final events = RegrowthEvents();

    for (final cell in grid.all) {
      switch (cell.state) {
        case CellState.solid:
          break;

        case CellState.open:
          // Staked ground is out of the cycle entirely — that is the whole of
          // what STAKE buys, and it has to outrank the fault exemption below or
          // the one thing that answers cracked ground would not answer it.
          if (cell.pinned) {
            cell.eligibleSince = null;
            continue;
          }
          double delay = tuning.regrowDelay + extraDelay;
          bool eligible;
          if (cell.type == HexType.fault) {
            // A fault is eligible the moment it is cleared, wherever it is.
            // That one exemption is the whole mechanic: it closes in the
            // middle of an open pocket, so the ground *ahead* of her is on a
            // clock too.
            eligible = true;
            delay = tuning.faultDelay + extraDelay;
          } else if (cell.type == HexType.thatch) {
            // A braid waits for its crossing and then closes fast. It never
            // counts down under her feet: the timer is for the tile behind
            // her, which is the one that matters.
            eligible =
                cell.crossed &&
                cell.coord != dogCell &&
                !dogOccupiedCells.contains(cell.coord);
            delay = thatchDelay;
          } else {
            eligible = cell.coord.neighbours.any(grid.blocks);
            if (eligible && overgrowthAura.contains(cell.coord)) {
              // The heart's creepers double the pace of everything closing
              // near it.
              delay *= 0.5;
            }
          }
          if (!eligible) {
            cell.eligibleSince = null;
            continue;
          }
          cell.eligibleSince ??= now;
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
          if ((cell.coord == dogCell ||
                  dogOccupiedCells.contains(cell.coord)) &&
              cell.regrowT > RegrowAnim.dogHold) {
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

  /// A tremor vent's surge: every open cell already counting down sees its
  /// countdown pulled [seconds] closer to the snap. Cells that have not yet
  /// qualified are untouched — the vent accelerates a closing that was coming,
  /// it never invents one, which is what keeps the surge a hurry rather than
  /// an ambush.
  static void surge(HexGrid grid, double seconds) {
    for (final cell in grid.all) {
      if (cell.state != CellState.open || cell.pinned) {
        continue;
      }
      final since = cell.eligibleSince;
      if (since != null) {
        cell.eligibleSince = since - seconds;
      }
    }
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
