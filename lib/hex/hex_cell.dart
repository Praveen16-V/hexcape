import 'hex_coord.dart';

/// Hex behaviours (§5). Three exist so far — the rest arrive one at a time per
/// §7 so each can be judged on its own.
enum HexType {
  /// Cleared with one tap. The default.
  plain,

  /// Two taps to clear. This is what stops a straight line at the bone from
  /// always being optimal: pushing through three heavies costs more than a
  /// two-cell detour around them, so a route has to be evaluated rather than
  /// merely aimed.
  heavy,

  /// Cannot be cleared at all. Forms the hard walls that must be routed
  /// around, and is the reason "what you leave standing" is a real choice.
  anchor,

  /// Clears in one tap like a plain hex, but throws her when she steps on it.
  ///
  /// Deliberately not a wall. Every other obstacle in the game takes something
  /// away — taps, seconds, a direction — and a board made only of subtractions
  /// gets tighter without getting more interesting. A spring is the one thing
  /// that gives, and it is dangerous for exactly that reason: it gives you
  /// distance in whatever direction she happened to be walking, which is a gift
  /// only if you set it up.
  spring;

  /// Taps needed to clear one of these from solid.
  int get hitsRequired => this == HexType.heavy ? 2 : 1;

  bool get isClearableType => this != HexType.anchor;
}

/// Where a cell is in the clear/regrow cycle.
enum CellState {
  /// Blocks the dog.
  solid,

  /// Cleared and passable.
  open,

  /// Still passable, but animating back toward [solid]. The dog can escape
  /// right up until the snap — that is what makes regrowth fair (§10).
  regrowing,
}

/// Timing for the three-stage regrowth animation (§10). The proportions are
/// fixed; only the *delay* before regrowth begins is player-tunable, because
/// shortening the warning itself would make the mechanic feel like ambush.
class RegrowAnim {
  RegrowAnim._();

  /// Seconds from "starts regrowing" to "solid again".
  static const duration = 1.15;

  /// Stage 1: a faint outline ghost fades in.
  static const ghostEnd = 0.22;

  /// Stage 2: two warning pulses.
  static const pulseEnd = 0.86;
  static const pulseCount = 2;

  /// A cell the dog is standing in holds here instead of snapping shut, so
  /// the player always gets the full warning before being boxed in.
  static const dogHold = 0.84;
}

class HexCell {
  HexCell(this.coord, this.type);

  final HexCoord coord;
  HexType type;

  CellState state = CellState.solid;

  /// Level time at which this cell first qualified for regrowth — i.e. became
  /// open *and* adjacent to something solid. Reset to null whenever it stops
  /// qualifying, so an interior cell that later becomes a boundary cell gets
  /// its full delay rather than snapping shut instantly (§2.3, outside-in).
  double? eligibleSince;

  /// 0..1 progress through [RegrowAnim] while [state] is regrowing.
  double regrowT = 0;

  /// 1 -> 0 decay driving the tap-clear scale-up and shard burst (§10).
  double clearBurst = 0;

  /// 1 -> 0 decay driving the shockwave ripple after a cell snaps shut.
  double snapRipple = 0;

  /// 1 -> 0 decay driving the shake when a tap lands on an anchor.
  double rejectShake = 0;

  /// 1 -> 0 decay driving the chip-off when a heavy hex cracks but holds.
  double crackFlash = 0;

  /// Taps already landed on this cell since it was last solid.
  int hits = 0;

  /// Whether the player has learned what this cell *is*.
  ///
  /// State is never hidden — a hole is obviously a hole — but type is, until
  /// the dog has been near enough to see it. Without this the whole obstacle
  /// map is readable before the first tap, and §2.1's "carve blind, discovering
  /// the path as they go" does not happen at all.
  ///
  /// Once revealed it stays revealed for the run. Re-hiding would make the
  /// player feel amnesiac and would punish exploring the very thing they are
  /// meant to explore.
  bool revealed = false;

  bool get isSolid => state == CellState.solid;

  /// Whether the dog may occupy this cell right now.
  bool get isPassable => state != CellState.solid;

  /// Whether a tap can do anything to this cell. Anchors never can be (§5).
  bool get isClearable => type.isClearableType && state == CellState.solid;

  /// Taps still needed to open this cell. Zero when it is already passable —
  /// this is what the tap budget and the soft-lock check both cost routes with.
  int get remainingHits => isPassable
      ? 0
      : (type.isClearableType ? type.hitsRequired - hits : 1 << 20);

  /// Whether the dog treats this as free space when steering. A regrowing
  /// cell still counts — the dog will happily run through a closing gap.
  bool get isOpenForSteering => state != CellState.solid;

  /// Land one tap. Returns true when the cell actually opened, false when it
  /// only cracked — a heavy hex on its first hit.
  bool hit(double now) {
    hits++;
    if (hits < type.hitsRequired) {
      crackFlash = 1;
      return false;
    }
    clear(now);
    return true;
  }

  void clear(double now) {
    state = CellState.open;
    eligibleSince = null;
    regrowT = 0;
    clearBurst = 1;
    hits = 0;
  }

  void resetToSolid() {
    state = CellState.solid;
    eligibleSince = null;
    regrowT = 0;
    clearBurst = 0;
    snapRipple = 0;
    // A regrown heavy is whole again, so it costs the full two taps.
    hits = 0;
  }
}
