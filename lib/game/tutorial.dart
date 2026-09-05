import '../entities/dog.dart';
import '../entities/pickup.dart';
import '../gen/pathfinder.dart';
import '../hex/hex_cell.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';

/// What a step points at.
///
/// Named by **rule, not coordinate**, because every board is generated — there
/// is no cell 4,-7 to hardcode. The rule is resolved against the live grid each
/// frame, so a highlight follows the game rather than a script written blind.
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
enum TutorialAdvance {
  /// The player taps the target.
  onTap,

  /// She reaches the target cell.
  onReach,

  /// The player acknowledges the explanation.
  onContinue,
}

class TutorialStep {
  const TutorialStep({
    required this.prompt,
    this.target = TutorialTarget.none,
    this.advance = TutorialAdvance.onContinue,
    this.gate = false,
  });

  final String prompt;
  final TutorialTarget target;
  final TutorialAdvance advance;

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
  HexCoord? _reachTarget;
  bool _done = false;

  int get stepNumber => (_index + 1).clamp(1, steps.length);
  int get stepCount => steps.length;

  void skip() => _done = true;

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
    _reachTarget = null;
    _done = false;
  }

  void _next() {
    _index++;
    _reachTarget = null;
  }

  /// The cell this step points at, resolved against the board as it is now.
  HexCoord? targetCell(HexGrid grid, Dog dog, List<Pickup> pickups) {
    final step = current;
    if (step == null) {
      return null;
    }
    return switch (step.target) {
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
      case TutorialAdvance.onReach:
        final target = targetCell(grid, dog, pickups);
        if (target == null ||
            dog.cell == target ||
            pickups.any((p) => p.coord == target && p.collected)) {
          _next();
        }
      case TutorialAdvance.onTap:
        if (step.target != TutorialTarget.none &&
            targetCell(grid, dog, pickups) == null) {
          _next();
        }
    }
  }

  /// The scripts. Deliberately short: two or three beats, then the level is
  /// theirs.
  static Tutorial? forLevel(int level) => switch (level) {
    1 => Tutorial(const [
      TutorialStep(
        prompt: 'Tap the glowing tile',
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
      TutorialStep(prompt: 'More open space, more speed. Find the bone!'),
    ]),
    // Regrowth and the two special tiles, in one gated run. Four beats rather
    // than the two-and-two they were as separate levels — the ceiling is
    // attention, not level count, and a gated step waits for the player.
    2 => Tutorial(const [
      TutorialStep(prompt: 'Cleared tiles grow back — watch behind her'),
      TutorialStep(prompt: 'Boxed in on every side, and she is finished'),
      TutorialStep(
        prompt: 'Riveted tiles never clear. Go around them',
        target: TutorialTarget.nearestAnchor,
      ),
      TutorialStep(
        prompt: 'Double-ringed tiles take two taps',
        target: TutorialTarget.nearestHeavy,
      ),
    ]),
    // Both resources. Fog is deliberately not here — it moved to level four,
    // where it gets a banner of its own.
    3 => Tutorial(const [
      TutorialStep(prompt: 'Your taps are limited now'),
      TutorialStep(prompt: 'And she tires — the bar is how long she has left'),
      TutorialStep(
        prompt: 'Walk her over this — treats pay back taps and time',
        target: TutorialTarget.nearestPickup,
        advance: TutorialAdvance.onReach,
      ),
      TutorialStep(prompt: 'They sit off your route. Worth the detour?'),
    ]),
    _ => null,
  };
}
