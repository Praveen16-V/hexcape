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

  /// A timer runs out.
  onTimer,
}

class TutorialStep {
  const TutorialStep({
    required this.prompt,
    this.target = TutorialTarget.none,
    this.advance = TutorialAdvance.onTimer,
    this.seconds = 3,
    this.gate = false,
  });

  final String prompt;
  final TutorialTarget target;
  final TutorialAdvance advance;
  final double seconds;

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
  double _elapsed = 0;
  bool _done = false;

  bool get isDone => _done || _index >= steps.length;

  TutorialStep? get current => isDone ? null : steps[_index];

  /// The line to show, or null once the script is finished.
  String? get prompt => current?.prompt;

  /// Whether taps other than the target should be refused right now.
  bool get isGating => !isDone && (current?.gate ?? false);

  void reset() {
    _index = 0;
    _elapsed = 0;
    _done = false;
  }

  void _next() {
    _index++;
    _elapsed = 0;
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
      TutorialTarget.nearestPickup => _nearestPickup(dog, pickups),
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

  /// Call every frame while the level is live.
  ///
  /// **Every step has a way out on time**, including the ones waiting for the
  /// player to do something. A step that waits forever for a tap that never
  /// comes, or for her to reach a treat the player has decided to skip, leaves
  /// the game showing a stale instruction — and a gated one leaves the board
  /// refusing every tap. A tutorial that can trap someone is worse than none.
  void update(double dt, HexGrid grid, Dog dog, List<Pickup> pickups) {
    final step = current;
    if (step == null) {
      return;
    }
    _elapsed += dt;
    switch (step.advance) {
      case TutorialAdvance.onTimer:
        if (_elapsed >= step.seconds) {
          _next();
        }
      case TutorialAdvance.onReach:
        final target = targetCell(grid, dog, pickups);
        if (target == null || dog.cell == target || _elapsed >= step.seconds) {
          _next();
        }
      case TutorialAdvance.onTap:
        if (_elapsed >= step.seconds * 6) {
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
        seconds: 4,
      ),
      TutorialStep(
        prompt: 'Open the next tile to make a narrow path',
        target: TutorialTarget.nextOnRoute,
        advance: TutorialAdvance.onTap,
        gate: true,
        seconds: 1.5,
      ),
      TutorialStep(prompt: 'Narrow paths keep her pace gentle', seconds: 1.5),
      TutorialStep(
        prompt: 'Open a tile beside her to widen the path',
        target: TutorialTarget.widenPath,
        advance: TutorialAdvance.onTap,
        seconds: 1.5,
      ),
      TutorialStep(
        prompt: 'Widen it once more for more speed',
        target: TutorialTarget.widenPath,
        advance: TutorialAdvance.onTap,
        seconds: 1.5,
      ),
      TutorialStep(
        prompt: 'More open space, more speed. Find the bone!',
        seconds: 3.5,
      ),
    ]),
    2 => Tutorial(const [
      TutorialStep(
        prompt: 'Cleared tiles grow back — watch behind her',
        seconds: 4.5,
      ),
      TutorialStep(
        prompt: 'Boxed in on every side, and she is finished',
        seconds: 4,
      ),
    ]),
    3 => Tutorial(const [
      TutorialStep(
        prompt: 'Riveted tiles never clear. Go around them',
        target: TutorialTarget.nearestAnchor,
        seconds: 4.5,
      ),
      TutorialStep(
        prompt: 'Double-ringed tiles take two taps',
        target: TutorialTarget.nearestHeavy,
        seconds: 4.5,
      ),
    ]),
    4 => Tutorial(const [
      TutorialStep(prompt: 'Your taps are limited now', seconds: 3.5),
      TutorialStep(
        prompt: 'Walk her over this — treats and powerups pay you back',
        target: TutorialTarget.nearestPickup,
        advance: TutorialAdvance.onReach,
        seconds: 12,
      ),
      TutorialStep(
        prompt: 'They sit off your route. Worth the detour?',
        seconds: 3.5,
      ),
    ]),
    5 => Tutorial(const [
      TutorialStep(prompt: 'You can only see what she is near', seconds: 4),
      TutorialStep(
        prompt: 'And she tires — the bar is how long she has left',
        seconds: 4,
      ),
    ]),
    _ => null,
  };
}
