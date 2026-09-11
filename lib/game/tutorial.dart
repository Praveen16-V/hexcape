import '../entities/dog.dart';
import '../entities/pickup.dart';
import '../gen/pathfinder.dart';
import '../hex/hex_cell.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';

/// What a step points at.
///
/// Named by **rule, not coordinate**, because every board is generated — there
/// is no cell 4,-7 to hardcode. The rule is resolved against the live grid, so
/// a highlight follows the game rather than a script written blind — but it is
/// resolved *once per lesson* and then held, because a rule re-run every frame
/// answers a question the player is not being asked. Resolution and release are
/// both in [Tutorial.targetCell], and the two together are the whole design.
enum TutorialTarget {
  /// The next cell she needs opened, on the cheapest route to the bone.
  nextOnRoute,

  /// A side tile next to the dog, adding space without extending the corridor.
  widenPath,

  /// The nearest wall, to point at while explaining it.
  nearestAnchor,

  /// The nearest two-tap tile.
  nearestHeavy,

  /// The nearest treat or powerup.
  nearestPickup,

  /// Nothing in particular; the step is just words.
  none,
}

/// What ends a step.
///
/// Only [onContinue] freezes the run, and that is the whole reason the other
/// two watching kinds exist. A step that says *look at this* while the game is
/// stopped is an instruction the player cannot carry out: nothing grows back
/// on a frozen board and no bar drains on a frozen clock, so the two lessons
/// that most needed showing were the two the player could only ever be told.
enum TutorialAdvance {
  /// The player taps the target.
  onTap,

  /// She reaches the target cell.
  onReach,

  /// The player acknowledges the explanation. **Freezes the run.**
  onContinue,

  /// The run keeps going for [TutorialStep.seconds] while the line is up.
  /// For lessons about something that has to be seen happening.
  onWatch,

  /// The run keeps going until the field actually closes a cell.
  ///
  /// Timed to the event rather than to a clock, because the regrow delay is a
  /// tuning value and a fixed wait would show "watch it grow back" either long
  /// before or long after the thing it is pointing at.
  onRegrow,
}

class TutorialStep {
  const TutorialStep({
    required this.prompt,
    this.target = TutorialTarget.none,
    this.advance = TutorialAdvance.onContinue,
    this.gate = false,
    this.seconds = 3.0,
    this.releaseAfter,
  });

  final String prompt;
  final TutorialTarget target;
  final TutorialAdvance advance;

  /// How long a [TutorialAdvance.onWatch] beat holds the line up for. Ignored
  /// by every other kind.
  final double seconds;

  /// Seconds after which an action beat gives up and moves on, or null to wait
  /// forever.
  ///
  /// For lessons whose target the board does not guarantee is *near* her. "Break
  /// a double-ringed tile" is fine when one is beside her and a trap when the
  /// closest is four cells away with the field closing in — the step would sit
  /// there unsatisfiable while the run it was interrupting ran out. A tutorial
  /// is never allowed to be the reason a level is lost.
  final double? releaseAfter;

  /// Whether every tap but the target is refused.
  ///
  /// This is what makes five guided levels teach more than twelve passive ones:
  /// a lesson that will not proceed until the player does the thing cannot be
  /// skimmed past. Used sparingly — gating something a player cannot find is how
  /// a tutorial becomes a trap.
  final bool gate;
}

/// The scripted opening of a level.
///
/// Runs only for its first few beats and then hands the level back. A tutorial
/// that keeps talking after it has made its point is one players learn to stop
/// reading.
class Tutorial {
  Tutorial(this.steps);

  final List<TutorialStep> steps;

  int _index = 0;
  bool _done = false;
  double _watched = 0;
  bool _sawRegrowth = false;

  /// The tile the highlight is standing on, the lesson that put it there, and
  /// how far from her it was when it did.
  ///
  /// A latch, not a cache: the point is that it is *released by events* rather
  /// than re-run per frame. See [targetCell].
  HexCoord? _held;
  int _heldStep = -1;
  int _heldDistance = 0;

  /// The treat or charge this beat was set on.
  ///
  /// Kept apart from [_held] on purpose. The hold belongs to the *mark* and is
  /// released as soon as the tile stops matching the rule; this is the beat's
  /// own commitment, which [TutorialAdvance.onReach] has to end on — including
  /// when the reason it stopped matching is that she just picked the thing up.
  HexCoord? _reachTarget;

  /// The field just closed a cell. Called by the game so a
  /// [TutorialAdvance.onRegrow] beat ends on the thing it is describing.
  void noteRegrowth() => _sawRegrowth = true;

  int get stepNumber => (_index + 1).clamp(1, steps.length);
  int get stepCount => steps.length;

  /// Gives up on the script. The mark goes with it: a pointer that outlives
  /// the lesson that set it is a hint about nothing.
  void skip() {
    _done = true;
    _clearHold();
  }

  /// Explanations wait for acknowledgement; action steps require real play.
  void continueLesson() {
    if (current?.advance == TutorialAdvance.onContinue) _next();
  }

  bool get isDone => _done || _index >= steps.length;

  TutorialStep? get current => isDone ? null : steps[_index];

  /// The line to show, or null once the script is finished.
  String? get prompt => current?.prompt;

  /// Whether taps other than the target should be refused right now.
  bool get isGating => !isDone && (current?.gate ?? false);

  void reset() {
    _index = 0;
    _clearHold();
    _reachTarget = null;
    _done = false;
    _watched = 0;
    _sawRegrowth = false;
  }

  void _next() {
    _index++;
    _clearHold();
    _reachTarget = null;
    _watched = 0;
    _sawRegrowth = false;
  }

  void _clearHold() {
    _held = null;
    _heldStep = -1;
    _heldDistance = 0;
  }

  /// The cell this step points at, resolved against the board as it is now.
  ///
  /// "As it is now" means *when the lesson was asked*, not *on this frame*.
  /// Every rule above starts from her own cell, so re-running one per frame
  /// re-picks its answer on every step she takes: the cheapest route from here
  /// is not the cheapest route from one cell further on, and while she crosses
  /// an open stretch several tiles ahead qualify in turn. A mark that hops
  /// between candidates is the one thing this must not be — the player spends
  /// the beat watching the tile that lit up last rather than the one to tap,
  /// and a gate that refuses every other tap starts to look arbitrary.
  ///
  /// So one answer is held per lesson, released only by the events that make
  /// it wrong rather than merely nearer:
  ///
  ///  * the step moving on, which [_next] does for every kind of ending;
  ///  * the tile ceasing to be what the rule named — opened by her tap,
  ///    opened by a dig or a launch, grown back over, or picked up;
  ///  * her walking far enough away that the lesson belongs where she is now,
  ///    which is what [_walkedOff] decides.
  ///
  /// The middle one is what stops the hold reading as a freeze: the mark sits
  /// on the tile she is asked to open, stays there the whole way across, and
  /// moves on the moment she has reached it, which is when the next tile
  /// needs it. And since a gate refuses every tap but the one on the held
  /// tile, a hold could in principle outlive its answer and lock the player
  /// out of their own run — which is why both release checks are consulted
  /// before the hold is honoured.
  HexCoord? targetCell(HexGrid grid, Dog dog, List<Pickup> pickups) {
    final step = current;
    if (step == null) {
      _clearHold();
      return null;
    }
    final held = _held;
    if (held != null &&
        _heldStep == _index &&
        _stillAsks(step.target, held, grid, pickups) &&
        !_walkedOff(step, held, dog)) {
      return held;
    }
    final resolved = _resolve(step.target, grid, dog, pickups);
    _held = resolved;
    _heldStep = resolved == null ? -1 : _index;
    _heldDistance = resolved?.distanceTo(dog.cell) ?? 0;
    return resolved;
  }

  /// Whether she has put enough ground between herself and the mark that the
  /// lesson it marks is the wrong lesson for where she is now.
  ///
  /// Only the beats a tap settles re-ask, and only once she is a cell further
  /// off than when the mark was set: from there the rule's own reach covers
  /// her, so a fresh answer is nearer *and* costs nothing extra, while a mark
  /// pinned to ground she is walking away from is a gate that will not open.
  /// A beat settled by reaching something keeps its target however far it is —
  /// trading a treat for a nearer one mid-detour is how a lesson turns into a
  /// coin toss, which is why [TutorialTarget.nearestPickup] commits to a cell
  /// in [_resolve].
  bool _walkedOff(TutorialStep step, HexCoord held, Dog dog) {
    // The distance she is allowed to put between herself and the mark before it
    // is re-pointed at where she actually is.
    const slack = 1;
    return step.advance == TutorialAdvance.onTap &&
        held.distanceTo(dog.cell) > _heldDistance + slack;
  }

  /// Whether the tile under the mark is still the tile the rule names — i.e.
  /// whether the lesson it was pinned for is still unanswered.
  static bool _stillAsks(
    TutorialTarget target,
    HexCoord held,
    HexGrid grid,
    List<Pickup> pickups,
  ) {
    final cell = grid.at(held);
    if (cell == null) {
      return false;
    }
    // A tile to open is asked for until it is open. One test covers both ways
    // the lesson ends — her tap, and her walking onto ground something else had
    // opened — so neither needs a rule of its own.
    final open = grid.isClearable(held);
    final waiting = pickups.any((p) => p.coord == held && !p.collected);
    return switch (target) {
      // Never marked, so never held.
      TutorialTarget.none => false,
      TutorialTarget.nextOnRoute || TutorialTarget.widenPath => open,
      TutorialTarget.nearestAnchor => cell.type == HexType.anchor,
      TutorialTarget.nearestHeavy => cell.isSolid && cell.type == HexType.heavy,
      TutorialTarget.nearestPickup => waiting,
    };
  }

  /// The tile the rule names, taken fresh from the board.
  HexCoord? _resolve(
    TutorialTarget target,
    HexGrid grid,
    Dog dog,
    List<Pickup> pickups,
  ) {
    return switch (target) {
      TutorialTarget.none => null,
      TutorialTarget.nextOnRoute => _nextOnRoute(grid, dog),
      TutorialTarget.widenPath => _widenPath(grid, dog),
      TutorialTarget.nearestAnchor => _nearest(
        grid,
        dog,
        (c) => c.type == HexType.anchor,
      ),
      TutorialTarget.nearestHeavy => _nearest(
        grid,
        dog,
        (c) => c.type == HexType.heavy && c.isSolid,
      ),
      // The beat commits once, and [_held] keeps that commit visible for its
      // whole life. Re-picking "the nearest" from wherever she has got to would
      // let a second treat steal the mark mid-detour — and the collect that
      // releases the hold has to be answered against the cell it set out for.
      TutorialTarget.nearestPickup => _reachTarget ??= _nearestPickup(
        dog,
        pickups,
      ),
    };
  }

  static HexCoord? _nextOnRoute(HexGrid grid, Dog dog) {
    final route = Pathfinder.cheapestPath(
      dog.cell,
      grid.exit,
      grid.isTraversableInPrinciple,
      (c) => grid.remainingCost(c).clamp(0, 8),
    );
    if (route == null) {
      return null;
    }
    for (final coord in route.skip(1)) {
      if (grid.isClearable(coord)) {
        return coord;
      }
    }
    return null;
  }

  static HexCoord? _widenPath(HexGrid grid, Dog dog) {
    final forward = _nextOnRoute(grid, dog);
    for (final c in dog.cell.neighbours) {
      if (c != forward && grid.isClearable(c)) return c;
    }
    return null;
  }

  static HexCoord? _nearest(
    HexGrid grid,
    Dog dog,
    bool Function(HexCell) matches,
  ) {
    HexCoord? best;
    var bestDistance = 1 << 30;
    for (final cell in grid.all) {
      if (!matches(cell)) {
        continue;
      }
      final d = cell.coord.distanceTo(dog.cell);
      if (d < bestDistance) {
        bestDistance = d;
        best = cell.coord;
      }
    }
    return best;
  }

  static HexCoord? _nearestPickup(Dog dog, List<Pickup> pickups) {
    HexCoord? best;
    var bestDistance = 1 << 30;
    for (final pickup in pickups) {
      if (pickup.collected) {
        continue;
      }
      final d = pickup.coord.distanceTo(dog.cell);
      if (d < bestDistance) {
        bestDistance = d;
        best = pickup.coord;
      }
    }
    return best;
  }

  /// Whether an action beat has waited past its welcome.
  bool _overstayed(double dt, TutorialStep step) {
    final limit = step.releaseAfter;
    if (limit == null) {
      return false;
    }
    _watched += dt;
    return _watched >= limit;
  }

  /// True when [coord] is allowed right now. Always true when not gating.
  bool allowsTap(HexCoord coord, HexGrid grid, Dog dog, List<Pickup> pickups) {
    if (!isGating) {
      return true;
    }
    final target = targetCell(grid, dog, pickups);
    // A gate with no resolvable target would lock the player out of their own
    // game, so an unresolvable target opens the gate rather than closing it.
    return target == null || target == coord;
  }

  /// Call after a tap has actually landed.
  void onTapped(
    HexCoord coord,
    HexGrid grid,
    Dog dog,
    List<Pickup> pickups, {
    HexCoord? targetBeforeTap,
  }) {
    final step = current;
    if (step == null || step.advance != TutorialAdvance.onTap) {
      return;
    }
    // Clearing the highlighted tile changes dynamic target resolution. Match
    // against the target captured before the game applied the tap.
    final target = targetBeforeTap ?? targetCell(grid, dog, pickups);
    // Widening is about the tile *opening*, not about the tap landing, so a
    // tap that merely cracked something has not finished the lesson.
    if (step.target == TutorialTarget.widenPath && !grid.isPassable(coord)) {
      return;
    }
    if (target == null || target == coord) {
      _next();
    }
  }

  /// Action steps wait for play. Missing targets release the step, and the
  /// visible Skip control always gives the player a way out.
  void update(double dt, HexGrid grid, Dog dog, List<Pickup> pickups) {
    final step = current;
    if (step == null) return;
    switch (step.advance) {
      case TutorialAdvance.onContinue:
        break;
      case TutorialAdvance.onWatch:
        _watched += dt;
        if (_watched >= step.seconds) {
          _next();
        }
      case TutorialAdvance.onRegrow:
        // A long stop is still a stop: if the field has not closed anything by
        // then, release the beat rather than leaving the player reading a line
        // about something that is not going to happen on this board.
        _watched += dt;
        if (_sawRegrowth || _watched >= step.seconds) {
          _next();
        }
      case TutorialAdvance.onReach:
        final target = targetCell(grid, dog, pickups);
        if (target == null ||
            dog.cell == target ||
            pickups.any((p) => p.coord == target && p.collected) ||
            _overstayed(dt, step)) {
          _next();
        }
      case TutorialAdvance.onTap:
        // A beat with a release valve owns its own ending. Without this, a
        // reach-limited target would end the step the instant she happened to
        // stand too far from one — which is not the lesson finishing, it is the
        // lesson being missed.
        final missing =
            step.releaseAfter == null &&
            step.target != TutorialTarget.none &&
            targetCell(grid, dog, pickups) == null;
        if (missing || _overstayed(dt, step)) {
          _next();
        }
    }
  }

  /// The scripts. Deliberately short: two or three beats, then the level is
  /// theirs.
  static Tutorial? forLevel(int level) => switch (level) {
    1 => Tutorial(const [
      TutorialStep(
        // The goal in the first words she reads, because the first lesson is a
        // tap on a tile and a tap on a tile looks like the whole game. The bone
        // is on the board already, glowing, so the line points at something she
        // can see rather than at a noun she has to imagine.
        prompt: 'Open a way to the bone: tap the glowing tile',
        target: TutorialTarget.nextOnRoute,
        advance: TutorialAdvance.onTap,
        gate: true,
      ),
      TutorialStep(
        prompt: 'Open the next tile to make a narrow path',
        target: TutorialTarget.nextOnRoute,
        advance: TutorialAdvance.onTap,
        gate: true,
      ),
      TutorialStep(prompt: 'Narrow paths keep her pace gentle'),
      TutorialStep(
        prompt: 'Open a tile beside her to widen the path',
        target: TutorialTarget.widenPath,
        advance: TutorialAdvance.onTap,
      ),
      TutorialStep(
        prompt: 'Widen it once more for more speed',
        target: TutorialTarget.widenPath,
        advance: TutorialAdvance.onTap,
      ),
      TutorialStep(prompt: 'More open space, more speed'),
      // The line the whole level exists for, and the one no amount of tapping
      // can imply. Four beats of "open this tile" teach that the board is the
      // game; then the board is open, the card is gone, and nothing has said
      // that clearing ground is only how she gets somewhere. **She has to
      // arrive at the bone**, and every lesson above is a means to that.
      //
      // Named on the first card so she knows what she is aiming at, and again
      // here because a goal read before the very first tap is a slogan while
      // one read after four taps that moved her is an instruction. Being the
      // final beat also puts it on the card whose button reads "Let's play", so
      // the last words before the run is hers are the thing she has to do.
      TutorialStep(
        prompt: 'She has to reach the bone herself — keep opening a way to it',
      ),
    ]),
    // Regrowth and the two special tiles.
    //
    // This was four cards in a row, every one of them frozen, and the player
    // reached the end of it having tapped nothing at all. Worse, its opening
    // line was "watch behind her" on a stopped board with nothing yet cleared
    // — the one thing it asked for was the one thing it made impossible. Now
    // the ground is opened by the player, the regrowth beat runs live until
    // the field actually closes something, and the heavy tile is learned by
    // spending two taps on it rather than by being told it costs two.
    2 => Tutorial(const [
      TutorialStep(
        prompt: 'Open her a way through',
        target: TutorialTarget.nextOnRoute,
        advance: TutorialAdvance.onTap,
        gate: true,
      ),
      TutorialStep(
        prompt: 'Now watch the ground behind her — cleared tiles grow back',
        advance: TutorialAdvance.onRegrow,
        seconds: 14,
      ),
      TutorialStep(prompt: 'Let it close on every side and she is finished'),
      TutorialStep(
        prompt: 'Riveted tiles never clear. Go around them',
        target: TutorialTarget.nearestAnchor,
      ),
      // Deliberately a card that points rather than a tap to perform. The tap
      // ring reaches about one cell, and nothing makes a generated board put a
      // double-ringed tile beside her — so "break one" is a lesson the board
      // can refuse to make possible, which is the one thing a tutorial step
      // must never be.
      TutorialStep(
        prompt: 'Double-ringed tiles take two taps',
        target: TutorialTarget.nearestHeavy,
      ),
    ]),
    // Both resources. Fog is deliberately not here — it moved to level four,
    // where it gets a banner of its own.
    //
    // The clock beat runs live for the same reason level two's does: "the bar
    // is how long she has left" said over a frozen bar is a caption on a still
    // photograph.
    3 => Tutorial(const [
      TutorialStep(prompt: 'Your taps are limited now — the count is up top'),
      // This carve is not decoration. A watching beat can only run once the
      // run has actually started: before the player's first tap the level sits
      // in its idle phase, where the clock does not tick and the script does
      // not advance — so a clock lesson placed ahead of it would hang on a bar
      // that was never going to move.
      TutorialStep(
        prompt: 'Spend one. Open her a way through',
        target: TutorialTarget.nextOnRoute,
        advance: TutorialAdvance.onTap,
        gate: true,
      ),
      TutorialStep(
        prompt: 'And she tires. Watch the bar — that is how long she has',
        advance: TutorialAdvance.onWatch,
        seconds: 4,
      ),
      TutorialStep(
        prompt: 'Walk her over this — treats pay back taps and time',
        target: TutorialTarget.nearestPickup,
        advance: TutorialAdvance.onReach,
        releaseAfter: 30,
      ),
      TutorialStep(prompt: 'They sit off your route. Worth the detour?'),
    ]),
    _ => null,
  };
}
