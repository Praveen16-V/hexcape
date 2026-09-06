import 'dart:math' as math;

import '../entities/guard.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';

/// Lays out lights (§6.1) — every kind from the one call, because separation
/// has to hold *across* the kinds: a sentry laid on top of a patrol would
/// make ground she refuses to enter and cannot clear either, which is a wall
/// the player has no way to read as one.
class GuardSystem {
  GuardSystem._();

  /// Rings of clearance a light keeps from where she starts.
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
  static const minRun = 3;
  static const maxRun = 5;

  /// Keeps two lights from overlapping into one impassable smear.
  static const minSeparation = 4;

  /// Speeds relative to the patrol base, per kind. A runner's dash is meant
  /// to be *fast but telegraphed*; a warden is slow precisely so its wake
  /// matters more than its teeth; a ring must spin fast enough that standing
  /// still means the window passes three cells a second.
  static const spinnerPace = 1.9;
  static const runnerPace = 2.5;
  static const wardenPace = 0.7;

  /// Builds the lights a level asks for. Returns fewer — possibly none — when
  /// the board has no room, which is correct: a small or heavily walled field
  /// should quietly carry fewer lights rather than have them crammed on top
  /// of the route.
  ///
  /// Allocation order respects seniority: patrols first, so a board with room
  /// for only some of what was asked keeps the mechanic the player has known
  /// since level 21 rather than the one they met most recently.
  static List<Guard> place({
    required HexGrid grid,
    required math.Random rng,
    required int count,
    double cellsPerSecond = 0.85,
    int sentries = 0,
    int beacons = 0,
    int spinners = 0,
    int runners = 0,
    int blinkers = 0,
    int wardens = 0,
  }) {
    final wanted = <GuardKind>[
      for (var i = 0; i < count; i++) GuardKind.patrol,
      for (var i = 0; i < sentries; i++) GuardKind.sentry,
      for (var i = 0; i < spinners; i++) GuardKind.spinner,
      for (var i = 0; i < runners; i++) GuardKind.runner,
      for (var i = 0; i < blinkers; i++) GuardKind.blinker,
      for (var i = 0; i < beacons; i++) GuardKind.beacon,
      for (var i = 0; i < wardens; i++) GuardKind.warden,
    ];
    if (wanted.isEmpty) {
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
    final anchorsOf = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(60, wanted.length * 25);

    for (final kind in wanted) {
      var placed = false;
      var localAttempts = 0;
      while (!placed && attempts < maxAttempts && localAttempts < maxAttempts) {
        attempts++;
        localAttempts++;
        final head = candidates[rng.nextInt(candidates.length)];
        if (anchorsOf.any((a) => a.distanceTo(head) < minSeparation)) {
          continue;
        }
        final guard = _build(grid, rng, kind, head, cellsPerSecond);
        if (guard == null) {
          continue;
        }
        anchorsOf.add(head);
        guards.add(guard);
        placed = true;
      }
    }
    return guards;
  }

  /// The route for one light of [kind] headed at [head], or null when the
  /// board gives it no room. Each kind's route *is* the mechanic: a patrol
  /// sweeps, a ring spins, a runner runs straight, a beacon stands.
  static Guard? _build(
    HexGrid grid,
    math.Random rng,
    GuardKind kind,
    HexCoord head,
    double cellsPerSecond,
  ) {
    switch (kind) {
      case GuardKind.beacon:
      case GuardKind.blinker:
        return Guard(patrol: [head], kind: kind);
      case GuardKind.spinner:
        // The ring around the pivot, walked in one direction forever. All six
        // cells must exist as playable ground or the ring has a snag in it.
        final ring = head.neighbours;
        final open = ring.where(grid.isTraversableInPrinciple).toList();
        if (open.length < 6) {
          return null;
        }
        final offset = rng.nextInt(6);
        return Guard(
          patrol: [for (var i = 0; i < 6; i++) ring[(offset + i) % 6]],
          cellsPerSecond: cellsPerSecond * spinnerPace,
          kind: GuardKind.spinner,
        );
      case GuardKind.runner:
        final route = _straight(grid, head, rng);
        if (route.length < minRun) {
          return null;
        }
        return Guard(
          patrol: route,
          cellsPerSecond: cellsPerSecond * runnerPace,
          kind: GuardKind.runner,
        );
      case GuardKind.warden:
        final route = _walk(grid, head, rng);
        if (route.length < minPatrol) {
          return null;
        }
        return Guard(
          patrol: route,
          cellsPerSecond: cellsPerSecond * wardenPace,
          kind: GuardKind.warden,
        );
      case GuardKind.patrol:
      case GuardKind.sentry:
        final route = _walk(grid, head, rng);
        if (route.length < minPatrol) {
          return null;
        }
        return Guard(
          patrol: route,
          cellsPerSecond: cellsPerSecond,
          kind: kind,
        );
    }
  }

  /// A straight dash route: one direction held from [head] until the board
  /// says stop. A runner that turned corners would be a fast patrol; a runner
  /// that never turns is a telegraph you can read two cells early.
  static List<HexCoord> _straight(HexGrid grid, HexCoord head, math.Random rng) {
    final direction = HexCoord.directions[rng.nextInt(6)];
    final route = <HexCoord>[head];
    var cursor = head;
    while (route.length < maxRun) {
      final next = cursor + direction;
      if (!grid.isTraversableInPrinciple(next) ||
          next.distanceTo(grid.start) < clearanceFromStart ||
          next.distanceTo(grid.exit) < clearanceFromExit) {
        break;
      }
      route.add(next);
      cursor = next;
    }
    return route;
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
