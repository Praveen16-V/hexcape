import 'dart:collection';
import 'dart:math' as math;

import '../entities/pickup.dart';
import '../gen/pathfinder.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';

/// Places and collects the things worth detouring for.
class PickupSystem {
  PickupSystem._();

  /// How far off the ideal route a pickup must sit to be worth a decision.
  static const minDetour = 1;
  static const maxDetour = 4;

  /// Keeps pickups from clustering into one lucky corner.
  static const minSpacing = 3;

  /// Drops pickups *beside* the cheapest route rather than on it.
  ///
  /// On the route they would be collected for free on the way past, which is
  /// not a decision — it is just scenery. One to four cells off, the player has
  /// to weigh the detour's taps and seconds against what it pays back. The
  /// actual cheapest route through each candidate is priced below, so a small
  /// treat is kept close while a powerful charge may tempt a longer diversion.
  static List<Pickup> place({
    required HexGrid grid,
    required math.Random rng,
    required int treats,
    required int powerups,
    double treatSeconds = 5,
    int treatTaps = 2,
    List<PickupKind> offered = const [
      PickupKind.freeze,
      PickupKind.radiusPlus,
      PickupKind.sprint,
      PickupKind.scent,
      PickupKind.blast,
      PickupKind.dig,
    ],
    int rotation = 0,

    /// How many of the drops are the taps-only ration — drawn from the same
    /// detour economy as a treat, saving the time it skips paying.
    int rations = 0,
  }) {
    final route = Pathfinder.cheapestPath(
      grid.start,
      grid.exit,
      grid.isTraversableInPrinciple,
      (c) => grid.cells[c]?.type.hitsRequired ?? (1 << 20),
    );
    if (route == null || route.isEmpty) {
      return const [];
    }

    final routeDistance = _distanceFromRoute(grid, route);
    final economics = detourCosts(grid);
    final candidates = [
      for (final entry in routeDistance.entries)
        if (entry.value >= minDetour &&
            entry.value <= maxDetour &&
            entry.key != grid.start &&
            entry.key != grid.exit)
          entry.key,
    ]..sort((a, b) => a.r != b.r ? a.r.compareTo(b.r) : a.q.compareTo(b.q));

    if (candidates.isEmpty) {
      return const [];
    }

    // Powerups cycle so a level never offers three of the same thing. The
    // order is rotated by seed as well, or every board in the campaign would
    // open with a freeze.
    final wanted = <PickupKind>[
      for (var i = 0; i < treats; i++) PickupKind.treat,
      for (var i = 0; i < rations; i++) PickupKind.ration,
      if (offered.isNotEmpty)
        for (var i = 0; i < powerups; i++)
          offered[(rotation + i) % offered.length],
    ];

    final placed = <Pickup>[];
    final taken = <HexCoord>[];
    final maxAttempts = math.max(60, wanted.length * 30);

    for (final kind in wanted) {
      final fair = [
        for (final coord in candidates)
          if (_isWorthDetour(
            kind,
            economics[coord],
            treatSeconds: treatSeconds,
            treatTaps: treatTaps,
          ))
            coord,
      ];
      if (fair.isEmpty) {
        continue;
      }
      var attempts = 0;
      while (attempts < maxAttempts) {
        attempts++;
        final coord = fair[rng.nextInt(fair.length)];
        if (taken.any((t) => t.distanceTo(coord) < minSpacing)) {
          continue;
        }
        // A prize sealed behind anchors is a promise the level cannot keep.
        if (!Pathfinder.reachable(
          grid.start,
          coord,
          grid.isTraversableInPrinciple,
        )) {
          continue;
        }
        taken.add(coord);
        placed.add(Pickup(kind, coord));
        break;
      }
    }
    return placed;
  }

  /// The extra taps and walking steps required by the cheapest route that
  /// visits each cell, compared with going straight to the exit. Zero means an
  /// equally cheap alternate route; candidates still have to sit off the one
  /// route shown by the pathfinder, so even those require a visible choice.
  static Map<HexCoord, ({int taps, int steps})> detourCosts(HexGrid grid) {
    final tapsFromStart = _weightedFrom(grid, grid.start);
    final tapsToExit = _weightedTo(grid, grid.exit);
    final stepsFromStart = _stepsFrom(grid, grid.start);
    final stepsToExit = _stepsFrom(grid, grid.exit);
    final directTaps = tapsFromStart[grid.exit];
    final directSteps = stepsFromStart[grid.exit];
    if (directTaps == null || directSteps == null) {
      return const {};
    }
    return {
      for (final coord in grid.cells.keys)
        if (tapsFromStart[coord] != null &&
            tapsToExit[coord] != null &&
            stepsFromStart[coord] != null &&
            stepsToExit[coord] != null)
          coord: (
            taps: math.max(
              0,
              tapsFromStart[coord]! + tapsToExit[coord]! - directTaps,
            ),
            steps: math.max(
              0,
              stepsFromStart[coord]! + stepsToExit[coord]! - directSteps,
            ),
          ),
    };
  }

  static bool _isWorthDetour(
    PickupKind kind,
    ({int taps, int steps})? cost, {
    required double treatSeconds,
    required int treatTaps,
  }) {
    if (cost == null) return false;
    // Budget a second per extra walking step, a deliberate tap cadence, and
    // half a second of net benefit. A refund should pay for the diversion.
    //
    // The stronger the thing, the longer the road allowed to fetch it: a
    // keepsake is worth an expedition, a sprint is worth a jog. Every number
    // here is a statement about how far a player should be tempted to walk.
    return switch (kind) {
      PickupKind.treat =>
        cost.taps <= math.max(0, treatTaps) &&
            cost.steps + cost.taps * 0.22 + 0.5 <= treatSeconds,
      PickupKind.ration => cost.taps <= 2 && cost.steps <= 4,
      PickupKind.freeze => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.radiusPlus => cost.taps <= 5 && cost.steps <= 6,
      PickupKind.sprint => cost.taps <= 4 && cost.steps <= 6,
      PickupKind.scent => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.lantern => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.cloak => cost.taps <= 4 && cost.steps <= 6,
      PickupKind.slowbeat => cost.taps <= 4 && cost.steps <= 6,
      PickupKind.wardown => cost.taps <= 4 && cost.steps <= 6,
      PickupKind.surepaws => cost.taps <= 4 && cost.steps <= 6,
      PickupKind.pairwork => cost.taps <= 5 && cost.steps <= 6,
      PickupKind.blast => cost.taps <= 6 && cost.steps <= 6,
      PickupKind.dig => cost.taps <= 4 && cost.steps <= 6,
      PickupKind.stake => cost.taps <= 5 && cost.steps <= 6,
      PickupKind.heel => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.trowel => cost.taps <= 6 && cost.steps <= 6,
      PickupKind.maul => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.echo => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.rewind => cost.taps <= 5 && cost.steps <= 6,
      PickupKind.mole => cost.taps <= 5 && cost.steps <= 7,
      PickupKind.harvest => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.whistle => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.seed => cost.taps <= 5 && cost.steps <= 6,
      PickupKind.beacon => cost.taps <= 4 && cost.steps <= 6,
      PickupKind.pouch => cost.taps <= 3 && cost.steps <= 5,
      PickupKind.ironpaw => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.nightEyes => cost.taps <= 4 && cost.steps <= 5,
      PickupKind.keepsake => cost.taps <= 6 && cost.steps <= 8,
      PickupKind.waystone => cost.taps <= 3 && cost.steps <= 5,
    };
  }

  static Map<HexCoord, int> _stepsFrom(HexGrid grid, HexCoord start) {
    final distance = <HexCoord, int>{start: 0};
    final queue = Queue<HexCoord>()..add(start);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final next = distance[current]! + 1;
      for (final n in current.neighbours) {
        if (distance.containsKey(n) || !grid.isTraversableInPrinciple(n)) {
          continue;
        }
        distance[n] = next;
        queue.add(n);
      }
    }
    return distance;
  }

  static Map<HexCoord, int> _weightedFrom(HexGrid grid, HexCoord start) =>
      _weighted(grid, start, (current, next) => grid.remainingCost(next));

  /// Reverse Dijkstra. Moving from the exit to a predecessor charges the cell
  /// being left, which is the cell that forward travel would enter. This makes
  /// the resulting value the cost from any cell to the exit, excluding that
  /// starting cell and including the exit.
  static Map<HexCoord, int> _weightedTo(HexGrid grid, HexCoord exit) =>
      _weighted(grid, exit, (current, next) => grid.remainingCost(current));

  static Map<HexCoord, int> _weighted(
    HexGrid grid,
    HexCoord start,
    int Function(HexCoord current, HexCoord next) edgeCost,
  ) {
    final best = <HexCoord, int>{start: 0};
    final frontier = SplayTreeMap<int, List<HexCoord>>()
      ..putIfAbsent(0, () => []).add(start);
    while (frontier.isNotEmpty) {
      final key = frontier.firstKey()!;
      final bucket = frontier[key]!;
      final current = bucket.removeLast();
      if (bucket.isEmpty) frontier.remove(key);
      if (key != best[current]) continue;
      for (final next in current.neighbours) {
        if (!grid.isTraversableInPrinciple(next)) continue;
        final candidate = key + edgeCost(current, next);
        if (candidate >= (best[next] ?? 1 << 30)) continue;
        best[next] = candidate;
        frontier.putIfAbsent(candidate, () => []).add(next);
      }
    }
    return best;
  }

  /// Steps from every cell to the nearest cell on [route], routed around
  /// anchors — a detour the player cannot actually walk is not a detour.
  static Map<HexCoord, int> _distanceFromRoute(
    HexGrid grid,
    List<HexCoord> route,
  ) {
    final distance = <HexCoord, int>{};
    final queue = Queue<HexCoord>();
    for (final c in route) {
      distance[c] = 0;
      queue.add(c);
    }
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final next = distance[current]! + 1;
      for (final n in current.neighbours) {
        if (distance.containsKey(n) || !grid.isTraversableInPrinciple(n)) {
          continue;
        }
        distance[n] = next;
        queue.add(n);
      }
    }
    return distance;
  }

  /// The pickup the dog has just walked onto, if any. She has to actually get
  /// there — carving a sight line to it is not enough.
  static Pickup? collect(List<Pickup> pickups, HexCoord dogCell) {
    for (final pickup in pickups) {
      if (!pickup.collected && pickup.coord == dogCell) {
        pickup.collected = true;
        pickup.collectFlash = 1;
        return pickup;
      }
    }
    return null;
  }
}
