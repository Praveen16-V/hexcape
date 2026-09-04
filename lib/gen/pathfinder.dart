import 'dart:collection';

import '../hex/hex_coord.dart';

/// Breadth-first search over the hex adjacency graph.
///
/// Shared deliberately: the generator uses it to validate that a level is
/// solvable, and the soft-lock system uses it every time the field changes
/// (§4). One implementation means one place for that logic to be wrong.
class Pathfinder {
  Pathfinder._();

  /// Shortest path from [from] to [to] through cells [passable] accepts,
  /// inclusive of both ends. Null when no route exists.
  static List<HexCoord>? shortestPath(
    HexCoord from,
    HexCoord to,
    bool Function(HexCoord) passable,
  ) {
    if (!passable(from) || !passable(to)) {
      return null;
    }
    if (from == to) {
      return [from];
    }

    final cameFrom = <HexCoord, HexCoord>{};
    final seen = <HexCoord>{from};
    final queue = Queue<HexCoord>()..add(from);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final next in current.neighbours) {
        if (seen.contains(next) || !passable(next)) {
          continue;
        }
        seen.add(next);
        cameFrom[next] = current;
        if (next == to) {
          return _rebuild(cameFrom, from, to);
        }
        queue.add(next);
      }
    }
    return null;
  }

  static bool reachable(
    HexCoord from,
    HexCoord to,
    bool Function(HexCoord) passable,
  ) {
    if (!passable(from) || !passable(to)) {
      return false;
    }
    if (from == to) {
      return true;
    }
    final seen = <HexCoord>{from};
    final queue = Queue<HexCoord>()..add(from);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final next in current.neighbours) {
        if (seen.contains(next) || !passable(next)) {
          continue;
        }
        if (next == to) {
          return true;
        }
        seen.add(next);
        queue.add(next);
      }
    }
    return false;
  }

  /// Cheapest total cost from [from] to [to], where [cost] is what it takes to
  /// open each cell. Returns null when no route exists at any price.
  ///
  /// Heavy hexes cost two taps, so the fewest-cells route and the fewest-taps
  /// route are no longer the same thing — par has to be this, not [shortestPath],
  /// or the tap budget would be quietly wrong.
  ///
  /// Dijkstra over a binary min-heap.
  ///
  /// It is called from the soft-lock check on every field change — every tap and
  /// every hex that closes — not once per level as an earlier version of this
  /// comment claimed. On a 253-cell board that difference is the game running or
  /// stuttering.
  static int? cheapestCost(
    HexCoord from,
    HexCoord to,
    bool Function(HexCoord) passable,
    int Function(HexCoord) cost,
  ) => _dijkstra(from, to, passable, cost)?.cost;

  /// The route behind [cheapestCost], inclusive of both ends. This is the one a
  /// player carving efficiently would actually follow, and the seed of §8's
  /// directional hint.
  static List<HexCoord>? cheapestPath(
    HexCoord from,
    HexCoord to,
    bool Function(HexCoord) passable,
    int Function(HexCoord) cost,
  ) {
    final result = _dijkstra(from, to, passable, cost);
    return result == null ? null : _rebuild(result.cameFrom, from, to);
  }

  static ({int cost, Map<HexCoord, HexCoord> cameFrom})? _dijkstra(
    HexCoord from,
    HexCoord to,
    bool Function(HexCoord) passable,
    int Function(HexCoord) cost,
  ) {
    if (!passable(from) || !passable(to)) {
      return null;
    }

    final best = <HexCoord, int>{from: cost(from)};
    final cameFrom = <HexCoord, HexCoord>{};
    final settled = <HexCoord>{};
    final frontier = _MinHeap()..push(best[from]!, from);

    while (frontier.isNotEmpty) {
      final (currentCost, current) = frontier.pop();
      // Lazily deleted: a cell can be pushed more than once as cheaper routes
      // to it turn up, so stale entries are skipped rather than removed.
      if (settled.contains(current) ||
          currentCost > (best[current] ?? 1 << 30)) {
        continue;
      }
      if (current == to) {
        // The starting cell is where the dog already stands, so opening it is
        // not something the player pays for.
        return (cost: currentCost - cost(from), cameFrom: cameFrom);
      }
      settled.add(current);

      for (final n in current.neighbours) {
        if (settled.contains(n) || !passable(n)) {
          continue;
        }
        final candidate = currentCost + cost(n);
        if (candidate < (best[n] ?? 1 << 30)) {
          best[n] = candidate;
          cameFrom[n] = current;
          frontier.push(candidate, n);
        }
      }
    }
    return null;
  }

  /// Flood fill from [from], returning step counts out to [maxDepth]. This is
  /// what the dog steers on: it finds the shape of the pocket it is standing
  /// in without walking the whole field every frame (§2.2).
  static Map<HexCoord, int> floodDepths(
    HexCoord from,
    bool Function(HexCoord) passable, {
    required int maxDepth,
  }) {
    final depths = <HexCoord, int>{};
    if (!passable(from)) {
      return depths;
    }
    depths[from] = 0;
    final queue = Queue<HexCoord>()..add(from);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final depth = depths[current]!;
      if (depth >= maxDepth) {
        continue;
      }
      for (final next in current.neighbours) {
        if (depths.containsKey(next) || !passable(next)) {
          continue;
        }
        depths[next] = depth + 1;
        queue.add(next);
      }
    }
    return depths;
  }

  static List<HexCoord> _rebuild(
    Map<HexCoord, HexCoord> cameFrom,
    HexCoord from,
    HexCoord to,
  ) {
    final path = <HexCoord>[to];
    var current = to;
    while (current != from) {
      current = cameFrom[current]!;
      path.add(current);
    }
    return path.reversed.toList();
  }
}

/// A plain binary min-heap over (cost, cell).
///
/// This exists because the search above used to find its minimum by scanning
/// the whole frontier every step. That was written when the only caller ran once
/// per level, and its comment said as much — then the budget-aware soft-lock
/// began calling it on every tap and every regrowth snap, and on a 253-cell
/// board the O(n^2) scan turned into tens of thousands of map iterations several
/// times a second. The game visibly stuttered, and the stale comment is why
/// nobody looked here.
///
/// Forty lines and no dependency, so how often the search runs stops being a
/// question anyone has to think about again.
class _MinHeap {
  final List<int> _costs = [];
  final List<HexCoord> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  void push(int cost, HexCoord item) {
    _costs.add(cost);
    _items.add(item);
    var child = _items.length - 1;
    while (child > 0) {
      final parent = (child - 1) >> 1;
      if (_costs[parent] <= _costs[child]) {
        break;
      }
      _swap(parent, child);
      child = parent;
    }
  }

  (int, HexCoord) pop() {
    final topCost = _costs.first;
    final topItem = _items.first;
    final last = _items.length - 1;
    _costs[0] = _costs[last];
    _items[0] = _items[last];
    _costs.removeLast();
    _items.removeLast();

    var parent = 0;
    while (true) {
      final left = parent * 2 + 1;
      final right = left + 1;
      var smallest = parent;
      if (left < _items.length && _costs[left] < _costs[smallest]) {
        smallest = left;
      }
      if (right < _items.length && _costs[right] < _costs[smallest]) {
        smallest = right;
      }
      if (smallest == parent) {
        break;
      }
      _swap(parent, smallest);
      parent = smallest;
    }
    return (topCost, topItem);
  }

  void _swap(int a, int b) {
    final cost = _costs[a];
    _costs[a] = _costs[b];
    _costs[b] = cost;
    final item = _items[a];
    _items[a] = _items[b];
    _items[b] = item;
  }
}
