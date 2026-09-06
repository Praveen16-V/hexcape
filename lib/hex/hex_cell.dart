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
  spring,

  /// Clears in one tap like a plain hex, then closes again on its own short
  /// clock — whether or not anything is next to it.
  ///
  /// The pressure nothing else in the game applies: **the route closing ahead
  /// of you.** Regrowth only ever eats the corridor behind her, because a cell
  /// has to border something solid before it becomes eligible. The consequence
  /// went unnoticed for a long time: carving far ahead is strictly optimal and
  /// costs nothing, and no obstacle has ever contested it.
  ///
  /// Deliberately **not** permanent, or it is an anchor that took a tap to
  /// make. It re-opens for one tap, every time.
  ///
  /// And deliberately a *fast lane* rather than another subtraction, for the
  /// reason [spring] exists: faults are laid in short lines and cost one tap
  /// each, so the route through a crack is cheaper than the detour around it —
  /// but it has to be run in one continuous push. Cheap-and-timed against
  /// expensive-and-safe is a live choice, which more walls would not be.
  fault,

  /// Clears in one tap, then pushes her one *fixed* direction when she steps
  /// on it — the direction drawn on the tile, not the one she was walking.
  ///
  /// The plannable inverse of [spring], and that contrast is the whole reason
  /// it exists. A spring adds distance to a decision the player already made;
  /// it is a gift precisely because it is uncontrollable, and you set one up
  /// rather than aim it. A slope is aimed *for* you and says so before you
  /// commit, which makes it the first thing in the game you can route
  /// *through* on purpose rather than merely survive.
  ///
  /// It is also the answer to a real gap: nothing in the game ever moved her
  /// somewhere she could see in advance, so HEEL — the one verb that stops her
  /// — had exactly one use, waiting out a patrol. A slope you do not want to
  /// take is the second.
  ///
  /// The direction lives on the cell rather than in the type, because a type
  /// per direction would be six enum entries, six palette colours and six
  /// reference entries for one idea. See [HexCell.slopeDirection].
  slope,

  /// Clears in one tap, but only when something beside it is already open.
  ///
  /// The one pressure the game never applied: **you cannot carve at a
  /// distance.** Every other obstacle costs taps, seconds or a direction; none
  /// of them cost *position*. [fault]'s own note names the consequence that had
  /// gone unopposed — carving far ahead of her is strictly optimal and costs
  /// nothing — and a fault answers it with a clock. This answers it with
  /// geometry: sunken ground has to be reached, one tile at a time, from ground
  /// that is already open.
  ///
  /// Never a soft-lock, and the argument is short: she always stands in an open
  /// cell, so every tile touching her is footed by definition. It bites at
  /// *range*, which is exactly where it is meant to, and it is the first thing
  /// REACH has to think about rather than simply enjoy.
  sunken;

  /// Taps needed to clear one of these from solid.
  int get hitsRequired => this == HexType.heavy ? 2 : 1;

  bool get isClearableType => this != HexType.anchor;

  /// Whether this closes on its own clock rather than by bordering a wall.
  bool get closesOnItsOwn => this == HexType.fault;

  /// Whether a tap needs open ground beside this before it can do anything.
  ///
  /// Asked of the *grid* rather than the cell wherever it matters, because a
  /// cell cannot see its neighbours — see [HexGrid.isClearable].
  bool get needsFooting => this == HexType.sunken;

  /// Whether stepping on this throws her.
  bool get throwsHer => this == HexType.spring || this == HexType.slope;
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

  /// Staked open for the rest of the run — never regrows, never faults.
  ///
  /// Lives on the cell rather than in a set on the game because regrowth reads
  /// it once per cell per frame, and because it belongs to the board: it is
  /// rebuilt with the level, like [type] and unlike an active powerup.
  bool pinned = false;

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

  /// Which way a [HexType.slope] pushes her, as an index into
  /// [HexCoord.directions]. Meaningless on every other type.
  ///
  /// Fixed when the level is generated and drawn on the tile, because a slope
  /// the player cannot read before stepping on it is a spring with worse
  /// manners.
  int slopeDirection = 0;

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
