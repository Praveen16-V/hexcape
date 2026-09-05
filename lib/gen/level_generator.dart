import 'dart:math' as math;

import '../entities/guard.dart';
import '../entities/pickup.dart';
import '../hex/hex_cell.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';
import '../systems/guard_system.dart';
import '../systems/pickup_system.dart';
import 'pathfinder.dart';
import 'silhouette.dart';

class LevelSpec {
  const LevelSpec({
    required this.seed,
    this.columns = 11,
    this.rows = 23,
    this.anchorDensity = 0.22,
    this.heavyDensity = 0.18,
    this.springDensity = 0,
    this.faultDensity = 0,
    this.guards = 0,
    this.guardSpeed = 0.85,
    this.treats = 3,
    this.powerups = 2,
    this.treatSeconds = 5,
    this.treatTaps = 2,
    this.powerupRotation = 0,
    this.offeredPowerups = PickupKind.values,
    this.shape = FieldShape.ellipse,
  });

  final int seed;

  /// Silhouette size in hexes. Level 1 stays generous per §7 ("large hexes,
  /// sparse obstacles"); later levels shrink the hexes rather than the target.
  ///
  /// The shape runs taller than it is wide because width is what constrains hex
  /// size on a portrait phone — a rounder field would scale to the same hexes
  /// and simply leave the bottom third of the screen empty.
  final int columns;
  final int rows;

  /// Fraction of eligible cells promoted to anchors. Exposed as a slider so
  /// the density lever from §7 can be felt on a real device.
  final double anchorDensity;

  /// Fraction promoted to heavy. These never block, so unlike anchors they need
  /// no solvability check — they only make some routes dearer than others.
  final double heavyDensity;

  /// Fraction promoted to spring. Like heavy hexes these never block, so they
  /// need no solvability check — a spring costs the same single tap a plain hex
  /// does, and only changes what happens after it opens.
  final double springDensity;

  /// Fraction promoted to fault. Like heavy and spring these never block, so
  /// they need no solvability check — a fault costs the same single tap a plain
  /// hex does, and only changes how long what it opens stays open.
  final double faultDensity;

  /// How many patrols sweep the board (§6.1), and how fast they walk.
  final int guards;
  final double guardSpeed;

  /// How many treats and powerups to scatter beside the route (§6.2).
  final int treats;
  final int powerups;

  /// What a treat returns, also used while placing it so the generator never
  /// asks the player to spend more taps or time reaching it than it pays back.
  final double treatSeconds;
  final int treatTaps;

  /// Where in the powerup cycle this level starts, so the campaign does not
  /// open every board with the same one.
  final int powerupRotation;

  /// Which powerups this level is allowed to drop. The campaign widens this as
  /// it climbs, so a player meets one new idea at a time rather than six at
  /// once — the same reason the mechanics themselves are gated per level.
  final List<PickupKind> offeredPowerups;

  /// The outline the board is cut to (§3.3).
  final FieldShape shape;

  LevelSpec copyWith({
    int? seed,
    double? anchorDensity,
    double? heavyDensity,
    double? springDensity,
    double? faultDensity,
    int? guards,
    int? treats,
    int? powerups,
    double? treatSeconds,
    int? treatTaps,
    FieldShape? shape,
  }) => LevelSpec(
    seed: seed ?? this.seed,
    columns: columns,
    rows: rows,
    anchorDensity: anchorDensity ?? this.anchorDensity,
    heavyDensity: heavyDensity ?? this.heavyDensity,
    springDensity: springDensity ?? this.springDensity,
    faultDensity: faultDensity ?? this.faultDensity,
    guards: guards ?? this.guards,
    guardSpeed: guardSpeed,
    treats: treats ?? this.treats,
    powerups: powerups ?? this.powerups,
    treatSeconds: treatSeconds ?? this.treatSeconds,
    treatTaps: treatTaps ?? this.treatTaps,
    powerupRotation: powerupRotation,
    offeredPowerups: offeredPowerups,
    shape: shape ?? this.shape,
  );
}

class GeneratedLevel {
  const GeneratedLevel({
    required this.grid,
    required this.par,
    required this.spec,
    required this.pickups,
    required this.guards,
  });

  final HexGrid grid;

  /// Treats and powerups, sitting off the ideal route (§6.2).
  final List<Pickup> pickups;

  /// Patrol routes (§6.1). Empty on levels that do not use them.
  final List<Guard> guards;

  /// The fewest taps that could finish this level.
  ///
  /// Cost-weighted, not step-counted: a heavy hex costs two taps, so the route
  /// through the fewest *cells* and the route costing the fewest *taps* are
  /// different things. The tap budget is derived from this, so getting it wrong
  /// would hand the player a budget that does not match the board.
  final int par;

  final LevelSpec spec;
}

/// Seeded level generation (§3.2): shape the field, carve a route, fill with
/// decoys, scatter anchors, and verify the result is solvable before handing
/// it over.
class LevelGenerator {
  LevelGenerator._();

  static GeneratedLevel generate(LevelSpec spec) {
    final rng = math.Random(spec.seed);
    final coords = shaped(
      shape: spec.shape,
      columns: spec.columns,
      rows: spec.rows,
    );
    final sorted = sortedCoords(coords);
    final bounds = unitBounds(coords);

    final endpoints = _pickEndpoints(sorted, bounds, rng);
    final start = endpoints.start;
    final exit = endpoints.exit;

    // Carve a maze over the field and keep the start-to-exit route. The player
    // never sees this; it exists for the directional hint (§8) and the debug
    // overlay. Solvability is guaranteed by the anchor validation below, not by
    // keeping this route anchor-free — protecting it would let a player infer
    // the answer from where anchors are absent.
    final truePath = _carve(coords, start, exit, rng);

    // Everything starts as a clearable plain hex, so decoys and route look
    // identical. That is what keeps the route discoverable rather than
    // readable (§3.2).
    final cells = <HexCoord, HexCell>{
      for (final c in sorted) c: HexCell(c, HexType.plain),
    };
    final grid = HexGrid(
      cells: cells,
      start: start,
      exit: exit,
      truePath: truePath,
    );

    _placeAnchors(grid, sorted, spec, rng);
    _placeHeavies(grid, sorted, spec, rng);
    _placeSprings(grid, sorted, spec, rng);
    _placeFaults(grid, sorted, spec, rng);

    final par = Pathfinder.cheapestCost(
      start,
      exit,
      grid.isTraversableInPrinciple,
      (c) => grid.cells[c]?.type.hitsRequired ?? (1 << 20),
    );
    assert(par != null, 'Anchor placement broke solvability (§4 invariant)');

    // Placed last: they are positioned relative to the cheapest route, which
    // only exists once anchors and heavy hexes have settled.
    final pickups = PickupSystem.place(
      grid: grid,
      rng: rng,
      treats: spec.treats,
      powerups: spec.powerups,
      treatSeconds: spec.treatSeconds,
      treatTaps: spec.treatTaps,
      offered: [
        for (final k in spec.offeredPowerups)
          if (k.isPowerup) k,
      ],
      rotation: spec.powerupRotation,
    );

    // Last of all, and told to keep away from both ends of the board.
    final guards = GuardSystem.place(
      grid: grid,
      rng: rng,
      count: spec.guards,
      cellsPerSecond: spec.guardSpeed,
    );

    return GeneratedLevel(
      grid: grid,
      par: par ?? 1,
      spec: spec,
      pickups: pickups,
      guards: guards,
    );
  }

  /// Deterministic ordering. Set iteration order is not guaranteed stable, so
  /// every random choice below draws from a sorted list — otherwise the same
  /// seed could produce different levels and §3.2's reproducible dailies would
  /// quietly not work.
  static List<HexCoord> sortedCoords(Iterable<HexCoord> coords) =>
      coords.toList()
        ..sort((a, b) => a.r != b.r ? a.r.compareTo(b.r) : a.q.compareTo(b.q));

  /// Dog at the bottom, food at the top, with a seeded sideways offset so
  /// regenerating gives a genuinely different journey. A vertical run reads
  /// well on a portrait screen and keeps the goal visible from the start
  /// (§3.1).
  static ({HexCoord start, HexCoord exit}) _pickEndpoints(
    List<HexCoord> cells,
    UnitBounds bounds,
    math.Random rng,
  ) {
    final spanX = bounds.maxX - bounds.minX;
    final spanY = bounds.maxY - bounds.minY;
    final midX = (bounds.minX + bounds.maxX) / 2;

    double jitter() => (rng.nextDouble() - 0.5) * 0.5 * spanX;

    final start = _nearest(cells, midX + jitter(), bounds.maxY - 0.08 * spanY);
    var exit = _nearest(cells, midX + jitter(), bounds.minY + 0.08 * spanY);
    if (exit == start) {
      exit = _nearest(cells, midX, bounds.minY);
    }
    return (start: start, exit: exit);
  }

  static HexCoord _nearest(List<HexCoord> cells, double x, double y) {
    var best = cells.first;
    var bestDist = double.infinity;
    for (final c in cells) {
      final p = unitCentre(c);
      final dx = p.x - x;
      final dy = p.y - y;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        best = c;
      }
    }
    return best;
  }

  /// Iterative recursive-backtracker over the hex adjacency graph, producing a
  /// spanning tree. The tree path from start to exit is the carved route.
  static List<HexCoord> _carve(
    Set<HexCoord> field,
    HexCoord start,
    HexCoord exit,
    math.Random rng,
  ) {
    final parent = <HexCoord, HexCoord>{};
    final visited = <HexCoord>{start};
    final stack = <HexCoord>[start];

    while (stack.isNotEmpty) {
      final current = stack.last;
      final options = [
        for (final n in current.neighbours)
          if (field.contains(n) && !visited.contains(n)) n,
      ];
      if (options.isEmpty) {
        stack.removeLast();
        continue;
      }
      final next = options[rng.nextInt(options.length)];
      visited.add(next);
      parent[next] = current;
      stack.add(next);
    }

    final path = <HexCoord>[exit];
    var current = exit;
    while (current != start) {
      final up = parent[current];
      if (up == null) {
        // Only reachable if the silhouette is disconnected; fall back to a
        // straight run so the level stays usable.
        return [start, exit];
      }
      current = up;
      path.add(current);
    }
    return path.reversed.toList();
  }

  /// Anchors go down as small clumps rather than scattered singles, so they
  /// read as walls to route around instead of confetti (§5).
  ///
  /// Each clump is applied, then checked: if it severs the last route to the
  /// food it is rolled back immediately. Validating incrementally means
  /// generation always succeeds instead of rejecting and reseeding whole
  /// levels, and it never has to keep the carved route anchor-free.
  static void _placeAnchors(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    // The dog and the food both need room to manoeuvre on the first move.
    final protected = <HexCoord>{
      grid.start,
      grid.exit,
      ...grid.start.neighbours,
      ...grid.exit.neighbours,
    };

    final candidates = [
      for (final c in sorted)
        if (!protected.contains(c)) c,
    ];
    if (candidates.isEmpty) {
      return;
    }

    final target = (candidates.length * spec.anchorDensity).round();
    var placed = 0;
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);

    while (placed < target && attempts < maxAttempts) {
      attempts++;
      final seed = candidates[rng.nextInt(candidates.length)];
      if (grid.isAnchor(seed)) {
        continue;
      }

      final clump = _growClump(seed, 1 + rng.nextInt(3), grid, protected, rng);
      for (final c in clump) {
        grid.cells[c]!.type = HexType.anchor;
      }

      final stillSolvable = Pathfinder.reachable(
        grid.start,
        grid.exit,
        grid.isTraversableInPrinciple,
      );
      if (stillSolvable) {
        placed += clump.length;
      } else {
        for (final c in clump) {
          grid.cells[c]!.type = HexType.plain;
        }
      }
    }
  }

  /// Heavy hexes go down in clumps too, so they read as expensive walls you can
  /// either push through or route around — scattered singles would just be cost
  /// noise with no decision in it.
  ///
  /// No solvability pass here, unlike anchors: heavy never blocks anything, it
  /// only raises the price.
  /// Springs, scattered as singles.
  ///
  /// Never clumped, unlike anchors and heavy hexes. Two springs side by side
  /// would fling her off the first into the second and out of the player's
  /// hands entirely, and a mechanic whose failure mode is "the dog left" is not
  /// a mechanic worth clumping.
  static void _placeSprings(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    if (spec.springDensity <= 0) {
      return;
    }
    final protected = <HexCoord>{
      grid.start,
      grid.exit,
      ...grid.start.neighbours,
      ...grid.exit.neighbours,
    };
    final candidates = [
      for (final c in sorted)
        if (!protected.contains(c) && grid.cells[c]!.type == HexType.plain) c,
    ];
    if (candidates.isEmpty) {
      return;
    }

    final target = (candidates.length * spec.springDensity).round();
    final placed = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);

    while (placed.length < target && attempts < maxAttempts) {
      attempts++;
      final c = candidates[rng.nextInt(candidates.length)];
      if (grid.cells[c]!.type != HexType.plain) {
        continue;
      }
      if (placed.any((p) => p.distanceTo(c) < 2)) {
        continue;
      }
      grid.cells[c]!.type = HexType.spring;
      placed.add(c);
    }
  }

  /// Faults, in short lines rather than scattered singles.
  ///
  /// The shape is the mechanic. A lone fault is confetti — one tile that
  /// happens to close, indistinguishable from bad luck. A blob of them is an
  /// unreadable timed room. A *line* of two to four reads as a crack you either
  /// commit to and run, or route around, which is the decision the type exists
  /// to create.
  ///
  /// No solvability check, for the same reason springs and heavies need none:
  /// a fault is clearable and costs one tap, so it never blocks a route — it
  /// only prices one. `isTraversableInPrinciple`, `Pathfinder.cheapestCost` and
  /// the softlock check are all already correct without knowing it exists.
  static void _placeFaults(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    if (spec.faultDensity <= 0) {
      return;
    }
    final protected = <HexCoord>{
      grid.start,
      grid.exit,
      ...grid.start.neighbours,
      ...grid.exit.neighbours,
    };
    final candidates = [
      for (final c in sorted)
        if (!protected.contains(c) && grid.cells[c]!.type == HexType.plain) c,
    ];
    if (candidates.isEmpty) {
      return;
    }

    final target = (candidates.length * spec.faultDensity).round();
    final placed = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);

    while (placed.length < target && attempts < maxAttempts) {
      attempts++;
      final start = candidates[rng.nextInt(candidates.length)];
      // Two clear of any existing line, so two cracks never read as one wide
      // smear of timed ground.
      if (placed.any((p) => p.distanceTo(start) < 3)) {
        continue;
      }
      final direction = HexCoord.directions[rng.nextInt(6)];
      final length = 2 + rng.nextInt(3);

      // Walked first and committed second: a line that runs off the board or
      // into a wall halfway through would leave a one-cell stub, which is the
      // confetti case this exists to avoid.
      final line = <HexCoord>[];
      var cursor = start;
      for (var i = 0; i < length; i++) {
        final cell = grid.cells[cursor];
        if (cell == null ||
            cell.type != HexType.plain ||
            protected.contains(cursor)) {
          break;
        }
        line.add(cursor);
        cursor += direction;
      }
      if (line.length < 2) {
        continue;
      }
      for (final c in line) {
        grid.cells[c]!.type = HexType.fault;
        placed.add(c);
      }
    }
  }

  static void _placeHeavies(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    final protected = <HexCoord>{
      grid.start,
      grid.exit,
      ...grid.start.neighbours,
      ...grid.exit.neighbours,
    };

    final candidates = [
      for (final c in sorted)
        if (!protected.contains(c) && !grid.isAnchor(c)) c,
    ];
    if (candidates.isEmpty) {
      return;
    }

    final target = (candidates.length * spec.heavyDensity).round();
    var placed = 0;
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);

    while (placed < target && attempts < maxAttempts) {
      attempts++;
      final seed = candidates[rng.nextInt(candidates.length)];
      if (grid.cells[seed]!.type != HexType.plain) {
        continue;
      }
      final clump = _growClump(
        seed,
        1 + rng.nextInt(3),
        grid,
        protected,
        rng,
        onlyPlain: true,
      );
      for (final c in clump) {
        grid.cells[c]!.type = HexType.heavy;
      }
      placed += clump.length;
    }
  }

  static List<HexCoord> _growClump(
    HexCoord seed,
    int size,
    HexGrid grid,
    Set<HexCoord> protected,
    math.Random rng, {
    bool onlyPlain = false,
  }) {
    final clump = <HexCoord>[seed];
    while (clump.length < size) {
      final options = <HexCoord>{};
      for (final c in clump) {
        for (final n in c.neighbours) {
          final blocked = onlyPlain
              ? grid.cells[n]?.type != HexType.plain
              : grid.isAnchor(n);
          if (grid.contains(n) &&
              !protected.contains(n) &&
              !blocked &&
              !clump.contains(n)) {
            options.add(n);
          }
        }
      }
      if (options.isEmpty) {
        break;
      }
      final ordered = sortedCoords(options);
      clump.add(ordered[rng.nextInt(ordered.length)]);
    }
    return clump;
  }
}
