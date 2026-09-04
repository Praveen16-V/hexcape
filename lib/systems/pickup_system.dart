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
  static const minDetour = 2;
  static const maxDetour = 4;

  /// Keeps pickups from clustering into one lucky corner.
  static const minSpacing = 3;

  /// Drops pickups *beside* the cheapest route rather than on it.
  ///
  /// On the route they would be collected for free on the way past, which is
  /// not a decision — it is just scenery. Two to four cells off, the player has
  /// to weigh the detour's taps and seconds against what it pays back, and the
  /// fog means they can see the prize without knowing what stands in the way.
  static List<Pickup> place({
    required HexGrid grid,
    required math.Random rng,
    required int treats,
    required int powerups,
    List<PickupKind> offered = const [
      PickupKind.freeze,
      PickupKind.radiusPlus,
      PickupKind.sprint,
      PickupKind.scent,
      PickupKind.blast,
      PickupKind.dig,
    ],
    int rotation = 0,
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

    final detour = _distanceFromRoute(grid, route);
    final candidates = [
      for (final entry in detour.entries)
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
      if (offered.isNotEmpty)
        for (var i = 0; i < powerups; i++)
          offered[(rotation + i) % offered.length],
    ];

    final placed = <Pickup>[];
    final taken = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(60, wanted.length * 30);

    for (final kind in wanted) {
      while (attempts < maxAttempts) {
        attempts++;
        final coord = candidates[rng.nextInt(candidates.length)];
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
