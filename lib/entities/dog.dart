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

  /// Distinguishes a patrol stopping her from a corridor that needs opening.
  bool waitingForPatrol = false;

  /// Every cell she has stood in this run. Used only to stop the "take any
  /// opening" fallback from walking her back and forth over old ground.
  final Set<HexCoord> _visited = {};

  Offset _lastPawprintAt = Offset.zero;
  int _fieldVersionSeen = -1;
  List<HexCoord> _route = const [];

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

  void update({
    required double dt,
    required HexGrid grid,
    required HexLayout layout,
    required TuningConfig tuning,
    required int fieldVersion,
    required bool regrowthActive,
    double speedMultiplier = 1.0,
    Set<HexCoord> blocked = const {},
  }) {
    final previousCell = cell;
    cell = layout.toHex(position);
    _visited.add(cell);
    final evicted = _evictIfWalledIn(grid, layout);

    // A patrol stepping one cell along changes where she may go without
    // changing the field, so it has to be its own trigger — fieldVersion would
    // never notice it.
    final patrolMoved = !_sameCells(blocked, _blockedSeen);
    if (patrolMoved) {
      _blockedSeen = blocked.isEmpty ? const {} : Set.of(blocked);
    }

    if (evicted ||
        patrolMoved ||
        fieldVersion != _fieldVersionSeen ||
        cell != previousCell) {
      _fieldVersionSeen = fieldVersion;
      _recomputeRoute(grid, blocked);
    }

    openness = grid.opennessAround(cell);

    _trackEnclosure(grid, dt, regrowthActive);
    final previousVelocity = velocity;
    if (launchFor > 0) {
      launchFor = math.max(0, launchFor - dt);
    } else {
      _steer(dt, grid, layout, tuning, speedMultiplier);
    }
    _move(dt, grid, layout);
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
    HexCoord? refuge;
    var bestDistance = double.infinity;
    for (final candidate in cell.disc(2)) {
      if (!grid.isPassable(candidate)) {
        continue;
      }
      final d = (layout.toPixel(candidate) - position).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        refuge = candidate;
      }
    }
    if (refuge == null) {
      return false;
    }
    position = layout.toPixel(refuge);
    velocity = Offset.zero;
    cell = refuge;
    return true;
  }

  /// Flood-fill the open pocket the dog is standing in, then pick where to go.
  ///
  /// If the food is inside the pocket, head straight for it — otherwise the
  /// dog could stand next to an open bone and wander off toward a larger
  /// cavern instead. Otherwise head for the deepest reachable cell, biased
  /// toward the exit, which reads as "flows into whatever just opened".
  void _recomputeRoute(HexGrid grid, Set<HexCoord> blocked) {
    waitingForPatrol = false;
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
      target = _bestOf(depths, grid, (_) => true) ?? cell;

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
    }

    steerTarget = target;
    _route = _walkBack(depths, target, grid);
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
      targetSpeed = hexesPerSecond * speedMultiplier * hexWidth;
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

    // Momentum (§2.2): the dog keeps walking after a gap opens, so overshoot
    // is possible and hesitation has a cost.
    final blend = (tuning.momentum * dt).clamp(0.0, 1.0);
    velocity += (desired - velocity) * blend;
  }

  /// The point to walk toward: the furthest cell along the route that the dog
  /// can reach in a straight line. Aiming only at the next hex centre makes
  /// the dog zig-zag down straight corridors.
  Offset? _aimPoint(HexGrid grid, HexLayout layout) {
    if (_route.length < 2) {
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
    return layout.toPixel(_route[chosen]);
  }

  bool _hasClearLine(Offset from, Offset to, HexGrid grid, HexLayout layout) {
    final delta = to - from;
    final distance = delta.distance;
    final steps = math.max(2, (distance / (layout.inradius * 0.5)).ceil());
    for (var i = 1; i <= steps; i++) {
      final p = from + delta * (i / steps);
      if (grid.blocks(layout.toHex(p))) {
        return false;
      }
    }
    return true;
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

  /// Being boxed in only counts once the dog has actually had somewhere to go.
  ///
  /// She starts the level walled in on all six sides, so without this gate a
  /// first tap that lands inside the ring but not next to her starts a death
  /// clock on a player who has not yet done anything wrong. The failure state
  /// is meant to be *the field closing back in* (§10) — not the opening
  /// position.
  void _trackEnclosure(HexGrid grid, double dt, bool regrowthActive) {
    if (!grid.isEnclosed(cell)) {
      hasBeenFree = true;
      enclosedFor = 0;
      return;
    }
    if (regrowthActive && hasBeenFree) {
      enclosedFor += dt;
    } else {
      enclosedFor = 0;
    }
  }

  void _updateAnimationState(
    double dt,
    Offset previousVelocity,
    HexLayout layout,
  ) {
    final currentSpeed = speed;

    if (currentSpeed > layout.width * 0.15) {
      final heading = math.atan2(velocity.dy, velocity.dx);
      var delta = heading - facing;
      while (delta > math.pi) {
        delta -= 2 * math.pi;
      }
      while (delta < -math.pi) {
        delta += 2 * math.pi;
      }
      final turn = delta * (10.0 * dt).clamp(0.0, 1.0);
      facing += turn;
      turnRate += (turn / math.max(dt, 1e-4) - turnRate) * 0.25;
    } else {
      turnRate *= 0.9;
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
