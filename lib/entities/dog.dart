import 'dart:math' as math;
import 'dart:ui';

import '../game/tuning.dart';
import '../gen/pathfinder.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';
import '../hex/hex_layout.dart';

/// One fading footprint left behind the dog (§9.2), so the drift path stays
/// readable after the fact.
class Pawprint {
  Pawprint(this.position, this.angle);

  final Offset position;
  final double angle;
  double age = 0;
}

/// The dog: drifts toward whatever opens up, with momentum, at a speed that
/// scales with how open the surrounding field is (§2.2).
///
/// The player never steers this directly — that is the whole point of the game.
class Dog {
  Dog({required this.position, required this.cell}) {
    _visited.add(cell);
  }

  Offset position;
  Offset velocity = Offset.zero;

  /// The hex currently containing the dog.
  HexCoord cell;

  /// Smoothed heading, in radians. Kept separate from velocity so the dog does
  /// not spin wildly when it is nearly stationary.
  double facing = -math.pi / 2;

  /// Advances with distance travelled, not with time, so the trot cycle
  /// matches the speed instead of running on the spot.
  double gaitPhase = 0;

  /// Signed turn rate, smoothed. Drives the ear flop and the lean into turns.
  double turnRate = 0;

  /// Positive when speeding up, negative when braking. Drives squash/stretch.
  double surge = 0;

  final List<Pawprint> pawprints = [];

  /// How long the dog has been completely walled in. Once this passes the
  /// tuned grace period the field has crushed her (§10).
  double enclosedFor = 0;

  /// Whether she has ever had an open neighbour. Gates the boxed-in timer, so
  /// the opening position never counts as being crushed.
  bool hasBeenFree = false;

  /// Openness of the local field, 0..1. Cached for the renderer and the HUD.
  double openness = 0;

  /// Where the steering flood-fill decided to head. Null when there is nowhere
  /// to go, which is the idle state before the player's first tap.
  HexCoord? steerTarget;

  /// The same local aim used by steering, exposed for the movement cue.
  Offset? get movementAim => isLaunched ? null : _movementAim;
  Offset? _movementAim;

  /// Her committed path, her own cell first, empty when she has nowhere to go.
  ///
  /// Exposed so a hint can name what is *coming* rather than what she is
  /// standing on. Empty while a spring has hold of her: steering is suspended,
  /// so the route describes a walk she is not currently taking.
  List<HexCoord> get route => isLaunched ? const [] : _route;

  /// Distinguishes a patrol stopping her from a corridor that needs opening.
  bool waitingForPatrol = false;

  /// She has a pocket to stand in and no reason to be anywhere else in it:
  /// nothing reachable is closer to the food and every cell of it is ground
  /// she has already walked. Steering is *correct* to hold her here — the way
  /// on has to be opened, not chosen — but it is the one state where a dog
  /// that simply stops looks like a dog that has broken.
  ///
  /// Distinct from [waitingForPatrol], which is a wait with a clock on it, and
  /// from being boxed in, which has nowhere to stand at all and ends the run.
  bool nowhereToGo = false;

  /// How long that wait has actually lasted. She passes through [nowhereToGo]
  /// for a few frames in ordinary play — every time she arrives somewhere
  /// before the next cell opens — so anything that speaks to the player about
  /// it has to wait out the blips or it flickers.
  double nowhereToGoFor = 0;

  /// The wall she is waiting on: the nearest thing to the food that a tap
  /// could still open on the edge of her pocket. This identifies the useful
  /// opening for feedback without changing her stationary presentation.
  /// Null when nothing bordering her can be opened at all, which is not a wait
  /// — the soft-lock check owns that ending.
  HexCoord? gazeTarget;

  /// Every cell she has stood in this run. Used only to stop the "take any
  /// opening" fallback from walking her back and forth over old ground.
  final Set<HexCoord> _visited = {};

  /// The cells she has stood in, in order, deduped at the point of change.
  /// This is what a WHISTLE walks back along: her own trail, never a
  /// direction the player points.
  final List<HexCoord> trail = [];

  /// The cell she stood in [steps] entries back along her trail, or null if
  /// she has not been anywhere yet. Her current cell is the list's tail, and
  /// is never *back* — a whistle to where she stands whistles nothing.
  HexCoord? trailCellBack(int steps) {
    final index = trail.length - 1 - steps;
    return index >= 0 ? trail[index] : null;
  }

  Offset _lastPawprintAt = Offset.zero;
  int _fieldVersionSeen = -1;
  List<HexCoord> _route = const [];

  /// The speed her steering actually asked for this frame.
  ///
  /// Compared against the ground she covered, this is what separates a dog
  /// walking from a dog leaning her whole weight on geometry that will not
  /// move. Nothing else in this file measures intent, and without it a wedge
  /// is indistinguishable from standing still on purpose.
  double _wantedSpeed = 0;

  /// How long she has asked to move and gone nowhere.
  ///
  /// This replaces an older counter that only ticked when her *centre* was
  /// driven into a solid cell. At walking pace her step is about a third of
  /// the standoff the collision solver guarantees, so that could never happen
  /// and the recovery it gated was unreachable. What actually wedges her is
  /// the depenetration pass cancelling every frame of travel, which leaves the
  /// centre test perfectly happy. Measure the outcome, not one cause of it.
  double _wedgedFor = 0;

  /// Seconds of gentle recovery still to run. See [_aimPoint].
  double _unwedgeFor = 0;

  /// Time since the route was last rebuilt. A wedged dog changes none of the
  /// things that normally trigger a rebuild, so she needs a clock of her own.
  double _sinceRoute = 0;

  /// Cells she is currently refusing to walk into — a guard's lit ground.
  /// Held so the route can be rebuilt when the patrol moves, which is a change
  /// to where she may go without being a change to the field itself.
  Set<HexCoord> _blockedSeen = const {};

  /// Seconds of steering still suspended after a spring threw her.
  ///
  /// Without this she would decide, on the very next frame, that the direction
  /// she is being flung in is not where she wants to go, and brake — turning a
  /// launch into a shrug. A spring only reads as a spring if she is briefly not
  /// in charge.
  double launchFor = 0;

  /// Seconds left of a HEEL. She stays exactly where she is.
  double holdFor = 0;

  /// True while a spring still has hold of her.
  bool get isLaunched => launchFor > 0;

  /// Throw her. [direction] need not be normalised; a zero vector is ignored,
  /// so a spring entered at a standstill does nothing rather than firing her
  /// somewhere arbitrary.
  void launch(Offset direction, double speed, {double duration = 0.34}) {
    final length = direction.distance;
    if (length < 1e-6) {
      return;
    }
    velocity = (direction / length) * speed;
    _movementAim = null;
    launchFor = duration;
  }

  double get speed => velocity.distance;

  /// How long she has been pressing into something that will not move. Zero on
  /// every frame she is actually travelling. Read by the game so a tile that
  /// pushes her continuously can stand down while she recovers.
  double get wedgedFor => _wedgedFor;

  /// Reaching the food is a cell event, not a hidden centre-radius test.
  /// Steering has no next waypoint once this cell is entered, so requiring a
  /// smaller inner circle can leave her correctly standing on the bone while
  /// the run waits forever for another field edit.
  bool hasReachedExit(HexGrid grid) => cell == grid.exit;

  /// How far the steering flood-fill looks. Six rings is enough to read the
  /// shape of any pocket the player can realistically open in one go, and
  /// keeps the per-frame cost flat regardless of field size.
  static const _lookaheadRings = 6;

  /// Cells of path smoothing. Without this the dog visibly zig-zags from one
  /// hex centre to the next; with too much it stops reacting to space that
  /// just opened beside it.
  static const _maxSmoothing = 3;

  /// How much reachable depth counts next to progress toward the food. Small
  /// on purpose: see [_recomputeRoute].
  static const _depthTieBreak = 0.15;

  /// Shapes how openness maps onto speed. See [_steer].
  static const _opennessCurve = 1.5;

  /// Fraction of the speed she asked for that still counts as travelling.
  ///
  /// A legitimate slide along a wall achieves `wanted * cos(angle)`, so only a
  /// press within about 78 degrees of head-on scores at all — and an ordinary
  /// collision is transient by construction, because the tangential component
  /// carries her off the wall within a few frames.
  static const _wedgeStallRatio = 0.2;

  /// Seconds of going nowhere before the gentle recovery starts. Fifteen
  /// frames: long enough that grazing a corner mid-crossing never reaches it.
  static const _wedgeThreshold = 0.25;

  /// How long the gentle recovery aims her at her own cell centre.
  static const _unwedgeSeconds = 1.0;

  /// Seconds of going nowhere before she is placed on the centre outright.
  /// The walk gets roughly two thirds of a second first, which covers the one
  /// circumradius she can possibly be from it.
  static const _snapAfter = 0.9;

  /// How often a wedged dog asks the routing question again.
  static const _rerouteWhileWedged = 0.4;

  /// Fraction of her collision radius a line of sight must leave clear.
  ///
  /// Under one on purpose: depenetration parks her at *exactly* that radius
  /// from a wall, so demanding the full width would reject the corridor she is
  /// already standing in and collapse all smoothing the moment she touches
  /// anything.
  static const _lineClearance = 0.9;

  void update({
    required double dt,
    required HexGrid grid,
    required HexLayout layout,
    required TuningConfig tuning,
    required int fieldVersion,
    required bool regrowthActive,
    double speedMultiplier = 1.0,

    /// How much of her steering gets through. One everywhere except drift
    /// ice, where the mechanic is that it barely gets through at all.
    double controlScale = 1.0,

    /// What the ground under her does to her speed. One everywhere except
    /// mire, where crossing costs pace rather than taps.
    double groundSpeedScale = 1.0,
    Set<HexCoord> blocked = const {},
  }) {
    final previousCell = cell;
    cell = layout.toHex(position);
    _visited.add(cell);
    if (trail.isEmpty || trail.last != cell) {
      trail.add(cell);
      if (trail.length > 24) {
        trail.removeAt(0);
      }
    }
    final evicted = _evictIfWalledIn(grid, layout);

    // A patrol stepping one cell along changes where she may go without
    // changing the field, so it has to be its own trigger — fieldVersion would
    // never notice it.
    final patrolMoved = !_sameCells(blocked, _blockedSeen);
    if (patrolMoved) {
      _blockedSeen = blocked.isEmpty ? const {} : Set.of(blocked);
    }

    // Every trigger but the last is a change to the *world*. Being wedged is
    // the one state where nothing about the world changes and the answer still
    // needs revisiting: rivets never bump [fieldVersion], she has not changed
    // cell, and there is no patrol — so the aim that wedged her would be
    // re-fed sixty times a second forever. Her visited set has grown in the
    // meantime, which is enough for the "take any opening she has not walked"
    // fallback to produce a different answer.
    _sinceRoute += dt;
    if (evicted ||
        patrolMoved ||
        fieldVersion != _fieldVersionSeen ||
        cell != previousCell ||
        (_wedgedFor > 0 && _sinceRoute >= _rerouteWhileWedged)) {
      _fieldVersionSeen = fieldVersion;
      _recomputeRoute(grid, blocked);
    }

    openness = grid.opennessAround(cell);

    _trackEnclosure(grid, layout, dt, regrowthActive);
    final previousVelocity = velocity;
    // Decided before steering, because the recovery works by changing what she
    // aims at and [_aimPoint] runs inside [_steer].
    _advanceRecovery(layout, dt);
    // Outranks a launch: a spring firing her across the board while the player
    // has just paid to hold her still would spend the tool on nothing.
    if (holdFor > 0) {
      holdFor = math.max(0, holdFor - dt);
      launchFor = 0;
      velocity = Offset.zero;
      _wantedSpeed = 0;
    } else if (launchFor > 0) {
      launchFor = math.max(0, launchFor - dt);
      // A throw is intent too: a spring that fires her into a corner has to be
      // covered by the same detector as a walk that presses into one.
      _wantedSpeed = velocity.distance;
    } else {
      _steer(
        dt,
        grid,
        layout,
        tuning,
        speedMultiplier,
        controlScale,
        groundSpeedScale,
      );
    }
    final movedFrom = position;
    _move(dt, grid, layout);
    _trackWedge(dt, layout, movedFrom);
    _settleIfStillWedged(grid, layout, blocked);
    // Only a wait she is actually *serving* counts. She sets the flag the
    // instant she arrives somewhere, a beat before the next cell opens, and
    // coasts to a stop over the frames after — timing it from the flag alone
    // would blink at the player all game.
    if (nowhereToGo && speed <= layout.width * 0.15) {
      nowhereToGoFor += dt;
    } else {
      nowhereToGoFor = 0;
    }
    _updateAnimationState(dt, previousVelocity, layout);
  }

  /// Safety net: if the dog somehow ends up inside a solid cell, shove her
  /// into the nearest open one.
  ///
  /// Ordering the update loop correctly should stop this happening at all —
  /// but a dog sealed inside a wall has no open pocket to flood-fill, so she
  /// would freeze in place for the rest of the run with no way for the player
  /// to recover. That failure is bad enough to be worth catching twice.
  static bool _sameCells(Set<HexCoord> a, Set<HexCoord> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final c in a) {
      if (!b.contains(c)) {
        return false;
      }
    }
    return true;
  }

  bool _evictIfWalledIn(HexGrid grid, HexLayout layout) {
    if (!grid.blocks(cell)) {
      return false;
    }
    // Ranked, not simply nearest.
    //
    // Taking the closest open cell in two rings looks equivalent and is not:
    // from inside a wall the nearest hole can be on the far side of it, in a
    // pocket the player never opened. A safety net that can drop her in a
    // different pocket is a worse bug than the one it catches -- it either
    // hands her progress nobody paid for, or strands her somewhere no tap can
    // reach. So prefer ground her body is already touching, then ground
    // beside her, and nothing further out at all.
    final refuge =
        _nearestPassable(occupiedCells(layout), grid, layout) ??
        _nearestPassable(cell.neighbours, grid, layout);
    if (refuge == null) {
      // Nothing she touches and nothing beside her is open. The old search
      // widened to two rings here, which is how she could end up on the far
      // side of a rivet; there is no honest move left, so leave her and let
      // [_trackEnclosure] put a clock on it.
      return false;
    }
    position = layout.toPixel(refuge);
    velocity = Offset.zero;
    cell = refuge;
    return true;
  }

  HexCoord? _nearestPassable(
    Iterable<HexCoord> candidates,
    HexGrid grid,
    HexLayout layout,
  ) {
    HexCoord? best;
    var bestDistance = double.infinity;
    for (final candidate in candidates) {
      if (!grid.isPassable(candidate)) {
        continue;
      }
      final d = (layout.toPixel(candidate) - position).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = candidate;
      }
    }
    return best;
  }

  /// Flood-fill the open pocket the dog is standing in, then pick where to go.
  ///
  /// If the food is inside the pocket, head straight for it — otherwise the
  /// dog could stand next to an open bone and wander off toward a larger
  /// cavern instead. Otherwise head for the deepest reachable cell, biased
  /// toward the exit, which reads as "flows into whatever just opened".
  void _recomputeRoute(HexGrid grid, Set<HexCoord> blocked) {
    waitingForPatrol = false;
    nowhereToGo = false;
    gazeTarget = null;
    // Her own cell is never excluded. Standing in the light is a thing that
    // happens to her; treating it as impassable would leave the flood with no
    // source at all and freeze her exactly when she most needs to move.
    final depths = Pathfinder.floodDepths(
      cell,
      (c) => grid.isPassable(c) && (c == cell || !blocked.contains(c)),
      maxDepth: _lookaheadRings,
    );
    if (depths.length <= 1) {
      waitingForPatrol = cell.neighbours.any(
        (c) => grid.isPassable(c) && blocked.contains(c),
      );
      steerTarget = null;
      _route = const [];
      return;
    }

    HexCoord target;
    if (depths.containsKey(grid.exit)) {
      target = grid.exit;
    } else {
      // Progress toward the food dominates; depth only breaks ties, nudging
      // her to commit to a direction across a wide pocket.
      //
      // Weighting these the other way round -- deepest cell wins, distance as a
      // nudge -- looks reasonable and is quietly broken: the deepest open cell
      // is usually the corridor she has *already walked*, so she turns round
      // and heads home. Regrowth hides it by sealing that corridor behind her,
      // which is exactly why it has to be right here rather than left to a
      // system that happens to clean up after it.
      // Only a cell that is *strictly* closer to the food counts as progress.
      //
      // Without that word the depth tie-break decides equidistant cells, and
      // depth is measured from wherever she is standing rather than being a
      // property of the cell — so a neighbour the same distance from the bone
      // always outscores standing still, from both ends. Two open tiles side
      // by side then each name the other, twenty-five times a second, and she
      // vibrates in the throat between them instead of moving. Requiring the
      // gap to actually close makes the primary choice monotone, which is what
      // rules the cycle out rather than damping it.
      //
      // It costs nothing that was working: depth can shift the score by at
      // most `_depthTieBreak * _lookaheadRings`, which is under one, so a
      // strictly closer cell already beat every equidistant one. Sideways
      // moves were never the goal-seeker's job — they belong to the fallback
      // below, which has the guard against walking the same ground twice.
      final here = grid.distanceToExit(cell);
      target =
          _bestOf(depths, grid, (c) => grid.distanceToExit(c) < here) ?? cell;

      // If nothing on offer beats standing still, take the best opening she has
      // not already walked.
      //
      // Pure goal-seeking refuses any move that does not close the gap to the
      // bone, so a player carving sideways — around a wall the fog is hiding,
      // which is routine — opens a cell right beside her and watches her ignore
      // it. That breaks the promise the whole game rests on: you do not move
      // her, you create the reason she moves. Every tap must produce motion.
      //
      // Excluding ground already covered is what keeps this from becoming a
      // pendulum. She will investigate the new cell and, finding nothing beyond
      // it, settle back — one round trip, not an endless one.
      if (target == cell) {
        final fresh = _bestOf(
          depths,
          grid,
          (c) => c != cell && !_visited.contains(c),
        );
        if (fresh != null) {
          target = fresh;
        }
      }

      // Still herself: she is standing on the best ground her pocket has, and
      // every other cell of it is ground she has already covered. Holding her
      // here is the right answer — the way on has to be *opened* — but it is
      // also the moment she stops moving entirely, with the hunger bar as the
      // only thing on screen still doing anything. Say so, and give her
      // something to look at, or a correct decision reads as a hung game.
      if (target == cell) {
        nowhereToGo = true;
        gazeTarget = _wallWorthOpening(depths, grid);
      }
    }

    steerTarget = target;
    _route = _walkBack(depths, target, grid);
  }

  /// The wall she is waiting on: of everything solid that a tap could open
  /// along the edge of her pocket, the one standing closest to the food.
  ///
  /// Measured on the anchor-aware field, so a tile with rivets behind it is
  /// correctly worth less than one with road behind it, and rivets themselves
  /// — which no tap can touch — are never named. Null when the pocket is
  /// ringed entirely by ground a tap cannot answer: that is not a wait, and
  /// pointing her at a rivet would promise a way through that is not there.
  HexCoord? _wallWorthOpening(Map<HexCoord, int> depths, HexGrid grid) {
    HexCoord? best;
    var bestDistance = 1 << 30;
    for (final c in depths.keys) {
      for (final n in c.neighbours) {
        if (depths.containsKey(n) || !grid.isClearable(n)) {
          continue;
        }
        final d = grid.distanceToExit(n);
        if (d < bestDistance) {
          bestDistance = d;
          best = n;
        }
      }
    }
    return best;
  }

  /// Highest scoring cell in the flood that [accept] allows, or her own cell
  /// when nothing qualifies. Progress toward the food dominates; reachable
  /// depth only breaks ties.
  HexCoord? _bestOf(
    Map<HexCoord, int> depths,
    HexGrid grid,
    bool Function(HexCoord) accept,
  ) {
    HexCoord? best;
    var bestScore = double.negativeInfinity;
    for (final entry in depths.entries) {
      if (!accept(entry.key)) {
        continue;
      }
      final score =
          -grid.distanceToExit(entry.key).toDouble() +
          _depthTieBreak * entry.value;
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
      }
    }
    return best;
  }

  /// Rebuild the route by stepping down the depth field from [target] back to
  /// the dog. Ties break toward the exit so the dog hugs the useful side of a
  /// wide corridor.
  List<HexCoord> _walkBack(
    Map<HexCoord, int> depths,
    HexCoord target,
    HexGrid grid,
  ) {
    final reversed = <HexCoord>[target];
    var current = target;
    var depth = depths[target] ?? 0;

    while (depth > 0) {
      HexCoord? best;
      var bestDistance = 1 << 30;
      for (final n in current.neighbours) {
        if (depths[n] != depth - 1) {
          continue;
        }
        final d = grid.distanceToExit(n);
        if (best == null || d < bestDistance) {
          best = n;
          bestDistance = d;
        }
      }
      if (best == null) {
        break;
      }
      current = best;
      depth--;
      reversed.add(current);
    }
    return reversed.reversed.toList();
  }

  void _steer(
    double dt,
    HexGrid grid,
    HexLayout layout,
    TuningConfig tuning,
    double speedMultiplier,
    double controlScale,
    double groundSpeedScale,
  ) {
    final aim = _aimPoint(grid, layout);
    _movementAim = aim;
    final hexWidth = layout.width;

    double targetSpeed;
    if (aim == null) {
      // Nowhere to drift: settle on the spot rather than jittering.
      targetSpeed = 0;
    } else {
      // §2.2: a wide cleared pocket accelerates the dog hard, a tight channel
      // slows her to a crawl.
      //
      // The exponent has to be above 1. Openness never reaches zero in a
      // playable corridor -- the cleared cells behind her still count, so a
      // single-hex slot already measures around 0.25 -- and a linear or
      // square-root response turns that into more than half speed. The spread
      // between "safe and slow" and "fast and risky" then collapses to under
      // 2x, and the self-regulating tension curve stops being felt at all.
      // Squaring it out gives roughly 1.1 / 1.6 / 3.0 hex per second across a
      // slot, a two-wide channel and open ground.
      final t = math.pow(openness.clamp(0.0, 1.0), _opennessCurve).toDouble();
      var hexesPerSecond =
          tuning.driftMin + (tuning.driftMax - tuning.driftMin) * t;
      // Sprint (§6.2) scales the whole curve rather than raising the floor, so
      // a tight channel is still slower than open ground while it runs — the
      // openness tension survives the powerup instead of being flattened by it.
      targetSpeed =
          hexesPerSecond * speedMultiplier * hexWidth * groundSpeedScale;
    }

    var desired = Offset.zero;
    if (aim != null) {
      final delta = aim - position;
      final distance = delta.distance;
      if (distance > 1e-3) {
        desired = (delta / distance) * targetSpeed;
        // Ease into the final approach so the dog does not jitter around the
        // centre of the cell it has already arrived at.
        final arrival = (distance / (layout.inradius * 0.9)).clamp(0.0, 1.0);
        desired *= arrival;
      }
    }

    // What she asked for, before momentum gets a say. Recorded here rather
    // than derived from [velocity] afterwards because the whole point is to
    // compare intent against the ground she actually covered.
    _wantedSpeed = desired.distance;

    // Momentum (§2.2): the dog keeps walking after a gap opens, so overshoot
    // is possible and hesitation has a cost.
    //
    // Drift ice scales the blend, not the target: she still *wants* the same
    // thing, she just cannot get there from here — which is exactly what
    // sliding means.
    final blend = (tuning.momentum * controlScale * dt).clamp(0.0, 1.0);
    velocity += (desired - velocity) * blend;
  }

  /// The point to walk toward: the furthest cell along the route that the dog
  /// can reach in a straight line. Aiming only at the next hex centre makes
  /// the dog zig-zag down straight corridors.
  Offset? _aimPoint(HexGrid grid, HexLayout layout) {
    if (_unwedgeFor > 0 && grid.isPassable(cell)) {
      // Recovery: walk to the middle of the tile she is already standing on.
      //
      // This always works, from any position inside an open cell and against
      // any arrangement of walls. The centre is the deepest point of a convex
      // hexagon, one inradius from every face against a body of roughly a
      // third that; her distance to a solid neighbour is at least her distance
      // to the line their shared edge sits on, and that distance varies
      // linearly along the walk, ending at the inradius. So her clearance
      // never decreases on the way there, and no alternation between two walls
      // can cancel the move -- the direction home lies inside the feasible
      // cone of every wall currently pressing on her.
      //
      // It is legitimate for the same reason the two cases below are: the aim
      // stays inside a passable cell she already occupies, so it creates no
      // route progress and opens no wall. It is a walk, not a snap.
      return layout.toPixel(cell);
    }
    if (_route.length < 2) {
      // Crossing a shared edge changes [cell] before her body has finished
      // entering the new hex. Route selection can quite correctly decide that
      // this is the end of the useful pocket, but braking at that instant
      // leaves her visibly wedged between two open tiles. Finish the crossing
      // before settling so an open tile never looks as though she refused to
      // enter it. This cannot create route progress or bypass a wall: the aim
      // stays inside the passable logical cell she already occupies.
      final centre = layout.toPixel(cell);
      if (grid.isPassable(cell) &&
          (centre - position).distance > layout.size * 0.05) {
        return centre;
      }
      return null;
    }
    final limit = math.min(_route.length - 1, _maxSmoothing);
    var chosen = 1;
    for (var i = limit; i >= 1; i--) {
      if (_hasClearLine(position, layout.toPixel(_route[i]), grid, layout)) {
        chosen = i;
        break;
      }
    }
    if (chosen == 1) {
      final throat = _throatAim(_route[1], grid, layout);
      if (throat != null) {
        return throat;
      }
    }
    return layout.toPixel(_route[chosen]);
  }

  /// The middle of the shared edge into [next], while that edge is the
  /// tightest kind of passage in the game.
  ///
  /// A hexagon's edge equals its circumradius, so a throat with a wall at both
  /// corners is exactly one `size` wide against a body of `0.68 * size` -- a
  /// sixth of a hex of room per side, and none at all if she arrives off the
  /// axis. Aiming at the midpoint makes the approach perpendicular, which is
  /// the only line that uses the whole margin.
  ///
  /// Deliberately not applied to every step. Funnelling through edge midpoints
  /// is smoother in general, but it would change the feel of every corridor in
  /// the game and undercut the smoothing [_maxSmoothing] exists to provide. It
  /// earns its place only where the margin is what is actually failing, which
  /// is why both corner hexes have to be solid and why smoothing must already
  /// have given up.
  Offset? _throatAim(HexCoord next, HexGrid grid, HexLayout layout) {
    final index = HexCoord.directions.indexOf(next - cell);
    if (index < 0) {
      return null;
    }
    if (!grid.blocks(cell + HexCoord.directions[(index + 1) % 6]) ||
        !grid.blocks(cell + HexCoord.directions[(index + 5) % 6])) {
      return null;
    }
    final centre = layout.toPixel(cell);
    final beyond = layout.toPixel(next);
    final axis = beyond - centre;
    // Once her centre is through, the midpoint is behind her and aiming at it
    // would pull her back onto the seam she has just crossed.
    final along =
        (position.dx - centre.dx) * axis.dx +
        (position.dy - centre.dy) * axis.dy;
    if (along >= axis.distanceSquared * 0.5) {
      return null;
    }
    // Pointed *at* the throat, held *beyond* it.
    //
    // The midpoint of two adjacent centres lands exactly on their shared edge,
    // and steering straight at it is what pulls an off-axis approach back onto
    // the axis before the gap narrows. But it cannot be the aim itself:
    // [_steer]'s arrival damping does not know a waypoint from a destination,
    // so she would decelerate to nothing on the seam and cross every throat in
    // the game at a crawl. Aiming a whole hex further along that same bearing
    // keeps the correction and drops the braking.
    //
    // Aiming at the next centre instead would do neither: from off the axis
    // that line only halves her offset by the time she reaches the gap, which
    // is the half that does not fit.
    final toThroat = (centre + beyond) / 2 - position;
    if (toThroat.distance < 1e-6) {
      return null;
    }
    return position + (toThroat / toThroat.distance) * layout.width;
  }

  /// Whether her *body* can travel this line, not just her centre.
  ///
  /// The distinction is not academic. Take three cells around a sixty degree
  /// bend: the straight line between the first and last centres does not
  /// merely pass near the shared edge of the two cells between them, it
  /// contains it -- same bearing, collinear endpoints. Every sample along that
  /// span sits exactly on the boundary, hex rounding picks a side by floating
  /// point luck, and a line with a rivet on one side gets approved. She is
  /// then aimed down a path her body overlaps by its whole radius, and spends
  /// every frame being pushed back out of a wall she is steering into.
  ///
  /// Rejecting too much is cheap: [_aimPoint] falls back to the next cell of
  /// the route, so the worst case is less smoothing, never less movement.
  bool _hasClearLine(Offset from, Offset to, HexGrid grid, HexLayout layout) {
    final delta = to - from;
    final distance = delta.distance;
    final steps = math.max(2, (distance / (layout.inradius * 0.5)).ceil());
    final room = collisionRadius(layout) * _lineClearance;
    for (var i = 1; i <= steps; i++) {
      final p = from + delta * (i / steps);
      if (grid.blocks(layout.toHex(p)) || clearanceAt(p, grid, layout) < room) {
        return false;
      }
    }
    return true;
  }

  /// How much room her body has at [p]: the distance to the nearest solid hex
  /// face, or infinity when nothing solid is near.
  ///
  /// Shares [_closestPointOnPolygon] with the collision solver on purpose, so
  /// the test that decides where to aim and the test that decides where she
  /// may stand can never disagree about the same piece of geometry.
  ///
  /// Searching the containing cell's neighbours is complete, not a heuristic:
  /// the nearest cell two steps away comes no closer than a full `size` to any
  /// point inside the middle one, and her body is barely a third of that.
  static double clearanceAt(Offset p, HexGrid grid, HexLayout layout) {
    var room = double.infinity;
    for (final n in layout.toHex(p).neighbours) {
      if (!grid.blocks(n)) {
        continue;
      }
      final d = (_closestPointOnPolygon(p, layout.corners(n)) - p).distance;
      if (d < room) {
        room = d;
      }
    }
    return room;
  }

  void _move(double dt, HexGrid grid, HexLayout layout) {
    if (velocity == Offset.zero) {
      return;
    }
    // Collision tests the cell she is moving *into*, which is only sound while
    // one frame's travel is shorter than a hex. At walking speed it always is;
    // a spring throws her several times faster and she would step clean over a
    // wall. Splitting the frame keeps every test local, and costs nothing at
    // normal speeds because the loop then runs exactly once.
    final travel = velocity.distance * dt;
    final limit = layout.inradius * 0.5;
    final steps = travel <= limit ? 1 : math.min(8, (travel / limit).ceil());
    final slice = dt / steps;
    for (var i = 0; i < steps && velocity != Offset.zero; i++) {
      _moveOnce(slice, grid, layout);
    }
  }

  void _moveOnce(double dt, HexGrid grid, HexLayout layout) {
    final radius = collisionRadius(layout);
    final step = velocity * dt;

    // Axis-separated resolution: sliding along a wall beats stopping dead at it.
    var next = position + step;
    if (grid.blocks(layout.toHex(next))) {
      final slideX = Offset(position.dx + step.dx, position.dy);
      final slideY = Offset(position.dx, position.dy + step.dy);
      if (!grid.blocks(layout.toHex(slideX))) {
        next = slideX;
        velocity = Offset(velocity.dx, 0);
      } else if (!grid.blocks(layout.toHex(slideY))) {
        next = slideY;
        velocity = Offset(0, velocity.dy);
      } else {
        // Both axes refused. Stop, and leave the recovery to [_trackWedge] --
        // there is exactly one stall measure in this file and it is the one
        // that watches whether she actually travelled.
        velocity = Offset.zero;
        return;
      }
    }
    position = next;

    // The dog is a disc, not a point, so push it clear of any solid hex it
    // overlaps. Two passes settles the corner case of touching two walls at
    // once. This also cleanly evicts the dog when a neighbouring cell snaps
    // shut against it.
    for (var pass = 0; pass < 2; pass++) {
      var adjusted = false;
      final here = layout.toHex(position);
      for (final n in here.neighbours) {
        if (!grid.blocks(n)) {
          continue;
        }
        final corners = layout.corners(n);
        final closest = _closestPointOnPolygon(position, corners);
        final away = position - closest;
        final distance = away.distance;
        if (distance >= radius || distance < 1e-6) {
          continue;
        }
        final normal = away / distance;
        position = closest + normal * radius;
        // Kill only the component driving into the wall, so the dog keeps
        // sliding along it instead of sticking.
        final into = velocity.dx * normal.dx + velocity.dy * normal.dy;
        if (into < 0) {
          velocity -= normal * into;
        }
        adjusted = true;
      }
      if (!adjusted) {
        break;
      }
    }
  }

  /// Book-keeping for the gentle recovery, run before steering each frame.
  ///
  /// Starting it clears her velocity once. The wedge is a standing press into
  /// a wall, and carrying that momentum into the recovery would just aim the
  /// same force at the same corner for another few frames.
  void _advanceRecovery(HexLayout layout, double dt) {
    if (_unwedgeFor > 0) {
      _unwedgeFor = math.max(0, _unwedgeFor - dt);
      // Arrived. Nothing is gained by holding the aim once she is on the spot,
      // and releasing early hands her straight back to ordinary steering.
      if ((layout.toPixel(cell) - position).distance <= layout.size * 0.05) {
        _unwedgeFor = 0;
      }
      return;
    }
    if (_wedgedFor >= _wedgeThreshold) {
      _unwedgeFor = _unwedgeSeconds;
      velocity = Offset.zero;
    }
  }

  /// Did she get where she asked to go?
  ///
  /// The floor is the same "actually moving" threshold used for the waiting
  /// clock and the gait, and it is what keeps a dog correctly easing onto a
  /// cell centre from reading as wedged: [_steer]'s arrival damping drives the
  /// speed she asks for toward zero as she arrives.
  void _trackWedge(double dt, HexLayout layout, Offset from) {
    final achieved = (position - from).distance / math.max(dt, 1e-4);
    if (_wantedSpeed > layout.width * 0.15 &&
        achieved < _wantedSpeed * _wedgeStallRatio) {
      _wedgedFor += dt;
    } else {
      _wedgedFor = 0;
    }
  }

  /// Last resort: put her on the centre of a cell her body already occupies.
  ///
  /// Bounded by the circumradius, because she is by definition inside that
  /// cell — this moves her less than one hex and cannot carry her past a wall.
  /// It is deliberately second: it reads as a snap rather than a walk, and the
  /// aim in [_aimPoint] is provably sufficient whenever her own cell is open,
  /// so reaching this means that premise was already broken — a launch
  /// overshoot, or ground that closed under her.
  void _settleIfStillWedged(
    HexGrid grid,
    HexLayout layout,
    Set<HexCoord> blocked,
  ) {
    if (_wedgedFor < _snapAfter) {
      return;
    }
    final refuge = _settleCell(grid, layout);
    if (refuge == null) {
      return;
    }
    position = layout.toPixel(refuge);
    velocity = Offset.zero;
    cell = refuge;
    _wedgedFor = 0;
    _unwedgeFor = 0;
    _recomputeRoute(grid, blocked);
  }

  /// Open ground she is already standing on, nearest first. Never anywhere
  /// else: putting her in a cell she does not already touch would be opening a
  /// wall for her, which is the one thing no recovery may do.
  HexCoord? _settleCell(HexGrid grid, HexLayout layout) {
    if (grid.isPassable(cell)) {
      return cell;
    }
    HexCoord? best;
    var bestDistance = double.infinity;
    for (final candidate in occupiedCells(layout)) {
      if (!grid.isPassable(candidate)) {
        continue;
      }
      final d = (layout.toPixel(candidate) - position).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = candidate;
      }
    }
    return best;
  }

  /// Being boxed in only counts once the dog has actually had somewhere to go.
  ///
  /// She starts the level walled in on all six sides, so without this gate a
  /// first tap that lands inside the ring but not next to her starts a death
  /// clock on a player who has not yet done anything wrong. The failure state
  /// is meant to be *the field closing back in* (§10) — not the opening
  /// position.
  ///
  /// Measured against her whole collision footprint rather than the cell under
  /// her centre, because regrowth holds every cell she occupies short of the
  /// snap. While she straddles a shared edge that mercy holds two cells open
  /// at once and neither can ever close, so a two-cell hole exactly her own
  /// size reads as an open pocket forever: she has nowhere to walk, the ground
  /// cannot finish closing on her, and the run never ends. See
  /// [HexGrid.isBoxedIn].
  void _trackEnclosure(
    HexGrid grid,
    HexLayout layout,
    double dt,
    bool regrowthActive,
  ) {
    if (!grid.isBoxedIn(occupiedCells(layout))) {
      hasBeenFree = true;
      enclosedFor = 0;
      return;
    }
    if (regrowthActive && hasBeenFree) {
      enclosedFor += dt;
    } else if (!grid.isPassable(cell) && _settleCell(grid, layout) == null) {
      // Sealed in stone: her centre is inside a wall, nothing her body touches
      // is open, and the eviction net found nowhere to put her. Steering has
      // no aim, the solver has no constraint left to relieve, and no tap can
      // change any of it. Every other enclosure is regrowth closing on her and
      // is gated on regrowth running; this one is not, because regrowth is not
      // what put her there.
      enclosedFor += dt;
    } else {
      enclosedFor = 0;
    }
  }

  /// Ease [facing] toward [heading] at [rate], taking the short way round.
  /// Returns the turn applied, which is what drives the lean and the ear flop.
  double _turnToward(double heading, double rate, double dt) {
    var delta = heading - facing;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    final turn = delta * (rate * dt).clamp(0.0, 1.0);
    facing += turn;
    return turn;
  }

  void _updateAnimationState(
    double dt,
    Offset previousVelocity,
    HexLayout layout,
  ) {
    final currentSpeed = speed;

    if (currentSpeed > layout.width * 0.15) {
      final turn = _turnToward(math.atan2(velocity.dy, velocity.dx), 10.0, dt);
      turnRate += (turn / math.max(dt, 1e-4) - turnRate) * 0.25;
    } else {
      turnRate *= 0.9;
      // Hold the last travelled heading while stationary. Turning toward an
      // editable wall without moving made the sprite look like it was being
      // rotated by the board rather than choosing a direction of travel.
    }

    // Tie the gait to distance covered so the trot never runs on the spot.
    gaitPhase += (currentSpeed * dt) / (layout.width * 0.42);

    final accel =
        (currentSpeed - previousVelocity.distance) / math.max(dt, 1e-4);
    surge += (accel / (layout.width * 4) - surge) * 0.2;
    surge = surge.clamp(-1.0, 1.0);

    for (final print in pawprints) {
      print.age += dt;
    }
    pawprints.removeWhere((p) => p.age > 1.6);

    if (currentSpeed > 1 &&
        (position - _lastPawprintAt).distance > layout.width * 0.55) {
      _lastPawprintAt = position;
      pawprints.add(Pawprint(position, facing));
      if (pawprints.length > 4) {
        pawprints.removeAt(0);
      }
    }
  }

  /// Radius used for drawing.
  static double dogRadius(HexLayout layout) => layout.size * 0.46;

  /// Radius used for collision, deliberately tighter than the drawn one.
  ///
  /// The gap between two adjacent hexes is their shared edge, and a regular
  /// hexagon's edge length equals its circumradius — so the tightest legal
  /// passage in the whole field is exactly `size` wide, regardless of how wide
  /// the hexes look. Anything at or above `size / 2` wedges against the two
  /// corners of that throat and stops dead in a one-hex corridor, which is the
  /// most common shape in the game. Staying well under it leaves clearance for
  /// the momentum to carry her through a turn.
  static double collisionRadius(HexLayout layout) => layout.size * 0.34;

  /// Every hex touched by the dog's collision body.
  ///
  /// [cell] is selected from the centre point, but while crossing a shared
  /// edge the dog physically occupies both cells. Regrowth must hold both or
  /// one side can close into her and pinch her between two walls.
  Set<HexCoord> occupiedCells(HexLayout layout) {
    final radius = collisionRadius(layout);
    final here = layout.toHex(position);
    final occupied = <HexCoord>{here};
    for (final candidate in here.neighbours) {
      final closest = _closestPointOnPolygon(
        position,
        layout.corners(candidate),
      );
      if ((closest - position).distance < radius) {
        occupied.add(candidate);
      }
    }
    return occupied;
  }

  static Offset _closestPointOnPolygon(Offset p, List<Offset> polygon) {
    var best = polygon.first;
    var bestDistance = double.infinity;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final candidate = _closestPointOnSegment(p, a, b);
      final d = (candidate - p).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = candidate;
      }
    }
    return best;
  }

  static Offset _closestPointOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.distanceSquared;
    if (lengthSquared < 1e-9) {
      return a;
    }
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    return a + ab * t;
  }
}
