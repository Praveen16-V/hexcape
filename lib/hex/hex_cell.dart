import 'hex_coord.dart';

/// Hex behaviours (§5), rebuilt set: the walls, the weights, the closures, the
/// movers, the disguises, the positional tiles and the ones that bite.
/// Mechanics arrive one at a time per §7 so each can be judged on its own.
enum HexType {
  /// Cleared with one tap. The default.
  plain,

  /// Two taps to clear. This is what stops a straight line at the bone from
  /// always being optimal: pushing through three heavies costs more than a
  /// two-cell detour around them, so a route has to be evaluated rather than
  /// merely aimed.
  heavy,

  /// Three taps. The late-campaign weight: one tile where the campaign asks
  /// for a whole detour's worth of taps in a single choice, so it can tax hard
  /// without raising heavy density into wallpaper.
  hardpan,

  /// Cannot be cleared by a tap at all. Forms the hard walls that must be
  /// routed around, and is the reason "what you leave standing" is a real
  /// choice. DIG is the only way through.
  anchor,

  /// Cannot be tapped, can only be dug. While it stands, open ground within
  /// two rings regrows twice as fast. A rivet with a voice: it is what a
  /// closing pocket *sounds* like before you are inside it.
  overgrowth,

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

  /// Clears in one tap, stays open exactly as long as she has not crossed it,
  /// then snaps shut the moment she steps off. The one-cross braid: no
  /// backtracking through it, so committing is committing both directions at
  /// once.
  ///
  /// Distinct from [fault], which closes on a clock whether she came or not.
  /// A thatch line waits politely until she uses it, and then it is over —
  /// what looks like a shortcut is a decision.
  thatch,

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
  /// The direction lives on the cell rather than in the type, because a type
  /// per direction would be six enum entries, six palette colours and six
  /// reference entries for one idea. See [HexCell.slopeDirection].
  slope,

  /// Clears in one tap, but while she is on it her steering response is muted
  /// and momentum carries: she keeps the heading she arrived with. Free speed
  /// with no fine control — aim the entry, because there is no exit correction.
  ice,

  /// Clears in one tap, but she crosses it at half speed. Cheap in taps,
  /// expensive on the clock — a patch of ground that charges time rather than
  /// taps, which is exactly the split a route has to weigh.
  mire,

  /// Clears in one tap, then gently pushes her off her line for as long as she
  /// stands on it. A repulsor dot: denies the resting place, nudges her into
  /// whatever is beside it. Never blocks; always shoves.
  eddy,

  /// Clears in one tap, then gently pulls her toward its centre while she
  /// crosses. The aimable inverse of [eddy]: a gathering force you can lean on
  /// to hold a line through open ground — or that collects her into a corner
  /// she did not choose.
  magnet,

  /// Clears in one tap, but only when something beside it is already open.
  ///
  /// The one pressure the game never applied: **you cannot carve at a
  /// distance.** Every other obstacle costs taps, seconds or a direction; none
  /// of them cost *position*. [fault]'s own note names the consequence that had
  /// gone unopposed — carving far ahead of her is strictly optimal and costs
  /// nothing — and a fault answers it with a clock. This answers it with
  /// geometry: sunken ground has to be reached, one tile at a time, from ground
  /// that is already open.
  sunken,

  /// The inverse of [sunken]: only clearable while *nothing* beside it is
  /// open — too close and it is unstable. It has to be carved early, from
  /// range, before the corridor reaches it. REACH's first real job, since the
  /// tile is answerable only from the edge of the ring.
  ///
  /// Never a soft-lock for the same reason sunken never is, turned around: a
  /// scaffold that has gone unstable simply waits for its neighbours to close
  /// again, and regrowth guarantees that they do.
  scaffold,

  /// Clears in one tap, but until it is cleared every neighbour of it keeps
  /// its type hidden, regardless of how close she gets. Fog you must carve
  /// through: the tile is a knock on the door of whatever is behind it.
  thicket,

  /// Clears in one tap, and holds its disguise longer than anything else:
  /// its type is only revealed when she is *adjacent*, not at the usual sight
  /// radius. Plain until proven otherwise — the tile the careful player taps
  /// second.
  sleeper,

  /// A decoy: through the fog it glows exactly like a pickup, and it is an
  /// ordinary one-tap tile. It costs nothing to clear and nothing to ignore —
  /// what it taxes is the detour instinct, on boards where the detour band is
  /// where the real treats live.
  foxfire,

  /// One tap, and stepping on it bites two seconds from the hunger clock.
  /// Never blocks, always hurts: route over it only when the short way beats
  /// two seconds.
  thorn,

  /// One tap, and stepping on it whips every light on the board to half again
  /// its speed for a few seconds. A shortcut with an alarm on it: the tile is
  /// cheap, the consequences are for everyone.
  alarm,

  /// A tile with a rhythm: while any vent on the board still stands, it fires
  /// a surge every few seconds that pulls every pending regrowth two seconds
  /// closer. Two taps to silence it, carved early or lived with.
  tremor,

  /// Solid until its paired [switchTile] is opened, then clears in one tap.
  /// The route is ordered before it is priced: find the switch first. The
  /// pair costs the honest two taps wherever both stand, and the gate stays
  /// open once flipped even if the switch regrows.
  gate,

  /// Clear it and its paired [gate] unlocks for good. One tap, no other
  /// behaviour — the whole mechanic is where it is standing.
  switchTile,

  /// One tap *charges* it; it opens only when its paired mirror has also been
  /// charged, and then both open together. Two honest taps for two cells, but
  /// split across the board — the pair enforces working two places at once,
  /// and ECHO is the tool that exists because this lock does.
  mirror;

  /// Taps needed to clear one of these from solid.
  int get hitsRequired => switch (this) {
    HexType.heavy => 2,
    HexType.hardpan => 3,
    HexType.tremor => 2,
    _ => 1,
  };

  /// Whether a tap could ever clear this, ignoring state and position.
  /// [overgrowth] joins [anchor] out: both yield only to DIG. A closed [gate]
  /// stays in — it is clearable *in principle*, its switch is somewhere.
  bool get isClearableType => this != HexType.anchor && this != HexType.overgrowth;

  /// Whether a tap on this tile is refused outright, and the refusal is worth
  /// reporting to the player (protocolled as the old anchor thunk).
  bool get blocksTaps => this == HexType.anchor || this == HexType.overgrowth;

  /// Whether DIG can remove it. Rivets and hearts alike.
  bool get isDiggable => this == HexType.anchor || this == HexType.overgrowth;

  /// Whether a solid tile of this type impassably walls the board. Gates are
  /// traversable in *principle* — the pathfinder prices their switch — where
  /// rivets and hearts are priced by dig charges instead.
  bool get blocksTravelInPrinciple =>
      this == HexType.anchor || this == HexType.overgrowth;

  /// Whether this closes on its own clock rather than by bordering a wall.
  /// [thatch] qualifies too, but only after the crossing — see
  /// [HexCell.crossed] and the regrowth system.
  bool get closesOnItsOwn => this == HexType.fault || this == HexType.thatch;

  /// Whether a tap needs open ground beside this before it can do anything.
  ///
  /// Asked of the *grid* rather than the cell wherever it matters, because a
  /// cell cannot see its neighbours — see [HexGrid.isClearable].
  bool get needsFooting => this == HexType.sunken;

  /// Whether a tap needs *no* open ground beside this before it can do
  /// anything — the scaffolds' inverse footing.
  bool get needsDistance => this == HexType.scaffold;

  /// Whether this tile's type is only revealed when she is adjacent.
  bool get revealsLate => this == HexType.sleeper;

  /// Whether stepping on this throws her.
  bool get throwsHer => this == HexType.spring || this == HexType.slope;

  /// Whether this tile applies a continuous force while she stands on it.
  bool get pushesContinuously =>
      this == HexType.eddy || this == HexType.magnet;
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

  /// Thatch memory: she has stood on this tile since it was last cleared.
  /// The braid only closes once it has been used, which is the whole
  /// difference between it and a fault.
  bool crossed = false;

  /// Gate pairs (§Lockbar): [link] matches a gate cell to its switch cell,
  /// [gateOpen] lives on the gate, and [switchTripped] on the switch. All
  /// three persist through regrowth — once flipped, a lockbar stays flipped.
  int link = -1;
  bool gateOpen = false;
  bool switchTripped = false;

  /// Mirror pairs: the other half. Charging either one charges it; both open
  /// when both are charged. The link is a coordinate rather than an id because
  /// the game resolves pairs cell-to-cell and never enumerates them.
  HexCoord? partner;
  bool charged = false;

  /// Inside the gloom band (terrain-level fog): reveal reaches only half as
  /// far onto this cell, whatever her radius is.
  bool gloomed = false;

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

  /// Whether a tap can do anything to this cell, ignoring position rules.
  /// Walls and hearts never can be (§5); a closed gate waits for its switch.
  bool get isClearable =>
      type.isClearableType && state == CellState.solid && !isLockedGate;

  /// Whether this gate is still waiting for its switch.
  bool get isLockedGate => type == HexType.gate && !gateOpen;

  /// Whether tap resolution should report this as a refused deliberate tap,
  /// the anchor protocol: walls, hearts, and locked gates.
  bool get reportsRefusal => type.blocksTaps || isLockedGate;

  /// Taps still needed to open this cell. Zero when it is already passable —
  /// this is what the tap budget and the soft-lock check both cost routes with.
  ///
  /// Mirror pairs and locked gates lie deliberately low here (one tap for the
  /// cell itself); the *pair* cost lives in [HexGrid.remainingCost], which can
  /// see the partner, so par and the budget stay honest about the second tap.
  int get remainingHits => isPassable
      ? 0
      : (type.isClearableType ? type.hitsRequired - hits : 1 << 20);

  /// Whether the dog treats this as free space when steering. A regrowing
  /// cell still counts — the dog will happily run through a closing gap.
  bool get isOpenForSteering => state != CellState.solid;

  /// Whether the wolf-at-the-door shows while solid: the one tile that never
  /// looks like its own kind until she is beside it.
  bool get disguised => type.revealsLate && !revealed;

  /// The type as the player currently knows it. Sleeper ground reads as plain
  /// until she is adjacent — the disguise is the mechanic.
  HexType get apparentType => disguised ? HexType.plain : type;

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
    // A fresh thatch has not been crossed yet; it closes only after use.
    crossed = false;
  }

  /// The mirror half of a tap: armed. Not an opening. The pair opens when
  /// both halves are armed — see the game's tap handler, which owns that rule
  /// because it can see the partner.
  void charge() {
    charged = true;
    hits = type.hitsRequired;
    crackFlash = 1;
  }

  void resetToSolid() {
    state = CellState.solid;
    eligibleSince = null;
    regrowT = 0;
    clearBurst = 0;
    snapRipple = 0;
    // A regrown heavy is whole again, so it costs the full two taps.
    hits = 0;
    // Arming does not survive closure: a mirror that closed on its own starts
    // the pair over. Gate and switch state deliberately persist — flipped is
    // flipped, which is the whole promise of a lockbar.
    charged = false;
  }
}
