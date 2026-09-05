import 'dart:math' as math;

import '../entities/guard.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';

/// Lays out patrol routes (§6.1).
class GuardSystem {
  GuardSystem._();

  /// Rings of clearance a patrol keeps from where she starts.
  ///
  /// A light sitting on the opening would be an obstacle before the player has
  /// taken a single action, which reads as the level being unfair rather than
  /// hard.
  static const clearanceFromStart = 4;

  /// And from the food, so the last step of a run is never a coin toss on
  /// timing the player cannot see coming through the fog.
  static const clearanceFromExit = 3;

  static const minPatrol = 3;
  static const maxPatrol = 6;

  /// Keeps two patrols from overlapping into one impassable smear.
  static const minSeparation = 4;

  /// Builds [count] patrols. Returns fewer — possibly none — when the board has
  /// no room for them, which is correct: a small or heavily walled field should
  /// quietly carry fewer guards rather than have them crammed on top of the
  /// route.
  /// Builds patrols and sentries together.
  ///
  /// One call rather than two, because separation has to hold *across* the two
  /// kinds: a sentry laid on top of a patrol would make ground she refuses to
  /// enter and cannot clear either, which is a wall the player has no way to
  /// read as one.
  static List<Guard> place({
    required HexGrid grid,
    required math.Random rng,
    required int count,
    double cellsPerSecond = 0.85,
    int sentries = 0,
  }) {
    final total = count + sentries;
    if (total <= 0) {
      return const [];
    }
    final candidates = [
      for (final c in grid.cells.keys)
        if (grid.isTraversableInPrinciple(c) &&
            c.distanceTo(grid.start) >= clearanceFromStart &&
            c.distanceTo(grid.exit) >= clearanceFromExit)
          c,
    ]..sort((a, b) => a.r != b.r ? a.r.compareTo(b.r) : a.q.compareTo(b.q));

    if (candidates.isEmpty) {
      return const [];
    }

    final guards = <Guard>[];
    final anchorsOfPatrols = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(40, total * 25);

    while (guards.length < total && attempts < maxAttempts) {
      attempts++;
      final head = candidates[rng.nextInt(candidates.length)];
      if (anchorsOfPatrols.any((a) => a.distanceTo(head) < minSeparation)) {
        continue;
      }
      final patrol = _walk(grid, head, rng);
      if (patrol.length < minPatrol) {
        continue;
      }
      anchorsOfPatrols.add(head);
      guards.add(
        Guard(
          patrol: patrol,
          cellsPerSecond: cellsPerSecond,
          // Patrols first, so a board with room for only some of what was asked
          // for keeps the mechanic the player has known since level 21 rather
          // than the one they met most recently.
          kind: guards.length < count ? GuardKind.patrol : GuardKind.sentry,
        ),
      );
    }
    return guards;
  }

  /// A patrol that prefers to keep going the way it set off.
  ///
  /// An unbiased random walk on a hex grid coils up into a knot a couple of
  /// cells wide, which is a guard standing still with extra steps. Favouring
  /// the previous direction gives a route that actually sweeps across ground,
  /// and so covers and uncovers a corridor rather than smothering one spot.
  static List<HexCoord> _walk(HexGrid grid, HexCoord head, math.Random rng) {
    final route = <HexCoord>[head];
    final seen = <HexCoord>{head};
    final length = minPatrol + rng.nextInt(maxPatrol - minPatrol + 1);
    var direction = rng.nextInt(6);

    while (route.length < length) {
      HexCoord? next;
      // Straight on first, then the two gentle turns, then give up.
      for (final turn in const [0, 1, 5, 2, 4]) {
        final candidate = route.last.neighbour((direction + turn) % 6);
        if (seen.contains(candidate) ||
            !grid.isTraversableInPrinciple(candidate) ||
            candidate.distanceTo(grid.start) < clearanceFromStart ||
            candidate.distanceTo(grid.exit) < clearanceFromExit) {
          continue;
        }
        next = candidate;
        direction = (direction + turn) % 6;
        break;
      }
      if (next == null) {
        break;
      }
      route.add(next);
      seen.add(next);
    }
    return route;
  }
}
