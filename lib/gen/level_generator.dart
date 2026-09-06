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
    this.slopeDensity = 0,
    this.sunkenDensity = 0,
    this.hardpanDensity = 0,
    this.thatchDensity = 0,
    this.overgrowthDensity = 0,
    this.tremorDensity = 0,
    this.iceDensity = 0,
    this.mireDensity = 0,
    this.eddyDensity = 0,
    this.magnetDensity = 0,
    this.thicketDensity = 0,
    this.sleeperDensity = 0,
    this.foxfireDensity = 0,
    this.scaffoldDensity = 0,
    this.thornDensity = 0,
    this.alarmDensity = 0,
    this.gatePairs = 0,
    this.mirrorPairs = 0,
    this.gloom = false,
    this.guards = 0,
    this.sentries = 0,
    this.beacons = 0,
    this.spinners = 0,
    this.runners = 0,
    this.blinkers = 0,
    this.wardens = 0,
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

  /// Fraction promoted to slope. Never blocks — a slope costs the same single
  /// tap a plain hex does and only changes what happens after she steps on it.
  final double slopeDensity;

  /// Fraction promoted to sunken.
  ///
  /// Needs no solvability check either, and the argument is worth writing down
  /// because it is not the same one the others make. Sunken ground *is*
  /// clearable; what it refuses is being cleared from a distance. Any route the
  /// pathfinder finds is walked one cell at a time, so by the time she is beside
  /// a sunken tile the cell she is standing in is open and the tile is footed.
  /// A route through sunken ground therefore always costs exactly what
  /// [Pathfinder] already thinks it costs.
  final double sunkenDensity;

  /// Fraction promoted to fault. Like heavy and spring these never block, so
  /// they need no solvability check — a fault costs the same single tap a plain
  /// hex does, and only changes how long what it opens stays open.
  final double faultDensity;

  // ---------------------------------------------------------------------
  // The rebuilt families (§mechanics-rebuild). Every one defaults to zero,
  // so a spec that names none of them generates the same field shape of
  // decision the game always had: walls, weights, and a clock.
  // ---------------------------------------------------------------------

  /// Three-tap slabs. The late-campaign tap tax.
  final double hardpanDensity;

  /// One-cross braids: reclose the moment she steps off.
  final double thatchDensity;

  /// Diggable emitters doubling nearby regrowth while they stand.
  final double overgrowthDensity;

  /// Rhythm vents firing closing surges while any of them stands.
  final double tremorDensity;

  /// Steering-mute tiles. Free speed, no fine control.
  final double iceDensity;

  /// Half-speed ground. Time tax.
  final double mireDensity;

  /// Repulsor dots pushing her off her line.
  final double eddyDensity;

  /// Attractor dots pulling her toward their centre.
  final double magnetDensity;

  /// Tiles concealing their neighbours until cleared.
  final double thicketDensity;

  /// Tiles revealed only when she stands adjacent.
  final double sleeperDensity;

  /// Decoy glimmers posed in the pickup band.
  final double foxfireDensity;

  /// Tiles refusing taps that come from too close.
  final double scaffoldDensity;

  /// Stepping stones with teeth: two seconds off the clock.
  final double thornDensity;

  /// Tripwires that hurry every light on the board.
  final double alarmDensity;

  /// Lockbar pairs: a gate tile and its switch tile, wired.
  final int gatePairs;

  /// Mirror pairs: linked tiles that only open together.
  final int mirrorPairs;

  /// Whether the silhouette carries a central band of doubled fog.
  final bool gloom;

  /// How many patrols sweep the board (§6.1), and how fast they walk.
  final int guards;
  final double guardSpeed;

  /// How many of the sweeping lights refuse taps rather than block her.
  final int sentries;

  /// Fixed no-tap patches; orbiting ring lights; dashing straight lights;
  /// phasing patches; slow patrols that re-close what they pass.
  final int beacons;
  final int spinners;
  final int runners;
  final int blinkers;
  final int wardens;

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
    int? sentries,
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
    slopeDensity: slopeDensity,
    sunkenDensity: sunkenDensity,
    hardpanDensity: hardpanDensity,
    thatchDensity: thatchDensity,
    overgrowthDensity: overgrowthDensity,
    tremorDensity: tremorDensity,
    iceDensity: iceDensity,
    mireDensity: mireDensity,
    eddyDensity: eddyDensity,
    magnetDensity: magnetDensity,
    thicketDensity: thicketDensity,
    sleeperDensity: sleeperDensity,
    foxfireDensity: foxfireDensity,
    scaffoldDensity: scaffoldDensity,
    thornDensity: thornDensity,
    alarmDensity: alarmDensity,
    gatePairs: gatePairs,
    mirrorPairs: mirrorPairs,
    gloom: gloom,
    guards: guards ?? this.guards,
    sentries: sentries ?? this.sentries,
    beacons: beacons,
    spinners: spinners,
    runners: runners,
    blinkers: blinkers,
    wardens: wardens,
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

  /// Lights and their routes (§6.1). Empty on levels that do not use them.
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
    _placeOvergrowth(grid, sorted, spec, rng);
    _placeHeavies(grid, sorted, spec, rng);
    _placeHardpans(grid, sorted, spec, rng);
    _placeGates(grid, sorted, spec, rng);
    _placeMirrors(grid, sorted, spec, rng);
    _placeSprings(grid, sorted, spec, rng);
    _placeFaults(grid, sorted, spec, rng);
    _placeThatch(grid, sorted, spec, rng);
    _placeTremor(grid, sorted, spec, rng);
    _placeSlopes(grid, sorted, spec, rng);
    _placeIce(grid, sorted, spec, rng);
    _placeMire(grid, sorted, spec, rng);
    _placeEddy(grid, sorted, spec, rng);
    _placeMagnet(grid, sorted, spec, rng);
    _placeThicket(grid, sorted, spec, rng);
    _placeSleeper(grid, sorted, spec, rng);
    _placeFoxfire(grid, sorted, spec, rng);
    _placeScaffold(grid, sorted, spec, rng);
    _placeSunken(grid, sorted, spec, rng);
    _placeThorns(grid, sorted, spec, rng);
    _placeAlarms(grid, sorted, spec, rng);
    _markGloom(grid, spec, rng);

    final par = Pathfinder.cheapestCost(
      start,
      exit,
      grid.isTraversableInPrinciple,
      grid.remainingCost,
    );
    assert(par != null, 'Anchor placement broke solvability (§4 invariant)');

    // Placed last: they are positioned relative to the cheapest route, which
    // only exists once anchors and heavy hexes have settled.
    //
    // Rations once the campaign has heard of them: around a third of the
    // treat economy converts to the taps-only sibling, split *here* rather
    // than in campaign rules so the daily's one-board-for-everyone promise
    // keeps meaning the layout too.
    final rations = spec.offeredPowerups.contains(PickupKind.ration)
        ? (spec.treats / 3).round()
        : 0;
    final pickups = PickupSystem.place(
      grid: grid,
      rng: rng,
      treats: spec.treats - rations,
      powerups: spec.powerups,
      treatSeconds: spec.treatSeconds,
      treatTaps: spec.treatTaps,
      offered: [
        for (final k in spec.offeredPowerups)
          if (k.isPowerup) k,
      ],
      rations: rations,
      rotation: spec.powerupRotation,
    );

    // Last of all, and told to keep away from both ends of the board.
    final guards = GuardSystem.place(
      grid: grid,
      // Food tuning must not reshuffle patrols on the same board.
      rng: math.Random(spec.seed ^ 0x47554152),
      count: spec.guards,
      cellsPerSecond: spec.guardSpeed,
      sentries: spec.sentries,
      beacons: spec.beacons,
      spinners: spec.spinners,
      runners: spec.runners,
      blinkers: spec.blinkers,
      wardens: spec.wardens,
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

  /// The cells nothing may ever take: the two ends and their doorsteps, so
  /// the dog and the food both have room to manoeuvre on the first move.
  static Set<HexCoord> _protected(HexGrid grid) => {
    grid.start,
    grid.exit,
    ...grid.start.neighbours,
    ...grid.exit.neighbours,
  };

  /// The plain, unprotected cells a family may take, in draw order.
  static List<HexCoord> _pool(HexGrid grid, List<HexCoord> sorted) {
    final protected = _protected(grid);
    return [
      for (final c in sorted)
        if (!protected.contains(c) && grid.cells[c]!.type == HexType.plain) c,
    ];
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
    final protected = _protected(grid);
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

  /// Overgrowth hearts, one at a time, checked like anchors.
  ///
  /// A heart *is* a wall until dug — same in-principle removal from the route
  /// graph — so placing one gets the anchor treatment: apply, check the run
  /// still answers, roll back if it severs. Aura pressure is a bonus on top,
  /// never the licence for an impossible board.
  static void _placeOvergrowth(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    if (spec.overgrowthDensity <= 0) {
      return;
    }
    final candidates = _pool(grid, sorted);
    if (candidates.isEmpty) {
      return;
    }
    final target = (candidates.length * spec.overgrowthDensity).round();
    final placed = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);
    while (placed.length < target && attempts < maxAttempts) {
      attempts++;
      final c = candidates[rng.nextInt(candidates.length)];
      if (grid.cells[c]!.type != HexType.plain) {
        continue;
      }
      // Hearts keep apart: two overlapping auras is one aura.
      if (placed.any((p) => p.distanceTo(c) < 5)) {
        continue;
      }
      grid.cells[c]!.type = HexType.overgrowth;
      final stillSolvable = Pathfinder.reachable(
        grid.start,
        grid.exit,
        grid.isTraversableInPrinciple,
      );
      if (stillSolvable) {
        placed.add(c);
      } else {
        grid.cells[c]!.type = HexType.plain;
      }
    }
  }

  /// Heavy hexes go down in clumps too, so they read as expensive walls you can
  /// either push through or route around — scattered singles would just be cost
  /// noise with no decision in it.
  ///
  /// No solvability pass here, unlike anchors: heavy never blocks anything, it
  /// only raises the price.
  static void _placeHeavies(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    final protected = _protected(grid);
    final candidates = [
      for (final c in sorted)
        if (!protected.contains(c) &&
            grid.cells[c]!.type != HexType.anchor &&
            grid.cells[c]!.type != HexType.overgrowth)
          c,
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

  /// Hardpan goes down as singles and pairs: one three-tap slab is a
  /// decision; a field of them is attrition. The clump grew the decision out
  /// of the mechanic, so hardpan stays rare and reads as *the expensive tile*
  /// rather than as more heavy ground.
  static void _placeHardpans(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _scatterSingles(
      grid,
      sorted,
      spec.hardpanDensity,
      rng,
      HexType.hardpan,
      spacing: 2,
    );
  }

  /// Lockbar pairs: a gate on likely ground, its switch a walk away.
  ///
  /// No solvability pass is needed and the reason is worth writing down: a
  /// closed gate blocks the route *physically* but never *in principle* — the
  /// pathfinder prices it at two taps because the switch is an ordinary tile
  /// that always exists and always opens it. The pair can be placed anywhere
  /// plain ground stands and the level stays answerable.
  static void _placeGates(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    if (spec.gatePairs <= 0) {
      return;
    }
    final taken = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = spec.gatePairs * 40;
    var link = 0;

    while (link < spec.gatePairs && attempts < maxAttempts) {
      attempts++;
      final candidates = _pool(grid, sorted);
      if (candidates.isEmpty) {
        return;
      }
      final gate = candidates[rng.nextInt(candidates.length)];
      if (taken.any((t) => t.distanceTo(gate) < 3)) {
        continue;
      }
      final switchPool = [
        for (final c in candidates)
          if (c != gate &&
              grid.cells[c]!.type == HexType.plain &&
              !taken.contains(c))
            c,
      ];
      // The switch stands 4–8 cells off its gate: far enough that holding it
      // in mind is the puzzle, near enough that the detour is one detour.
      final distant = [
        for (final c in switchPool)
          if (c.distanceTo(gate) >= 4 && c.distanceTo(gate) <= 8) c,
      ];
      if (distant.isEmpty) {
        continue;
      }
      final switchCell = distant[rng.nextInt(distant.length)];
      grid.cells[gate]!
        ..type = HexType.gate
        ..link = link;
      grid.cells[switchCell]!
        ..type = HexType.switchTile
        ..link = link;
      taken.addAll([gate, switchCell]);
      link++;
    }
  }

  /// Mirror pairs: two far-apart cells wired to open together.
  ///
  /// Far enough apart that charging both is two decisions in two places —
  /// the whole shape of the lock — and each placed on plain ground so the
  /// pair never hides inside another mechanic's tile.
  static void _placeMirrors(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    if (spec.mirrorPairs <= 0) {
      return;
    }
    final taken = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = spec.mirrorPairs * 40;
    var placed = 0;

    while (placed < spec.mirrorPairs && attempts < maxAttempts) {
      attempts++;
      final candidates = _pool(grid, sorted);
      if (candidates.isEmpty) {
        return;
      }
      final a = candidates[rng.nextInt(candidates.length)];
      if (taken.any((t) => t.distanceTo(a) < 3)) {
        continue;
      }
      final distant = [
        for (final c in candidates)
          if (c != a &&
              grid.cells[c]!.type == HexType.plain &&
              !taken.contains(c) &&
              c.distanceTo(a) >= 5 &&
              c.distanceTo(a) <= 10)
            c,
      ];
      if (distant.isEmpty) {
        continue;
      }
      final b = distant[rng.nextInt(distant.length)];
      grid.cells[a]!
        ..type = HexType.mirror
        ..partner = b;
      grid.cells[b]!
        ..type = HexType.mirror
        ..partner = a;
      taken.addAll([a, b]);
      placed++;
    }
  }

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
    _scatterSingles(
      grid,
      sorted,
      spec.springDensity,
      rng,
      HexType.spring,
      spacing: 2,
    );
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
    _placeLines(
      grid,
      sorted,
      spec.faultDensity,
      rng,
      HexType.fault,
      minRun: 2,
      maxRun: 4,
      spacing: 3,
    );
  }

  /// Thatch braids: short lines like faults, laid the same way for the same
  /// reason — one braid is noise, a line of three is a one-way street you
  /// choose to enter.
  static void _placeThatch(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _placeLines(
      grid,
      sorted,
      spec.thatchDensity,
      rng,
      HexType.thatch,
      minRun: 2,
      maxRun: 3,
      spacing: 3,
    );
  }

  /// Tremor vents, as singles well apart: one clock on the closing field.
  static void _placeTremor(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _scatterSingles(
      grid,
      sorted,
      spec.tremorDensity,
      rng,
      HexType.tremor,
      spacing: 6,
    );
  }

  /// Slopes, in short runs pointing the same way.
  ///
  /// The shape is the mechanic, exactly as it is for faults. A lone slope is a
  /// one-cell shove — noise. Two or three in a row pointing the same way is a
  /// *lane*, which is a thing a player can decide to enter or avoid, and
  /// deciding is the whole point of making the direction visible.
  static void _placeSlopes(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    if (spec.slopeDensity <= 0) {
      return;
    }
    final candidates = _pool(grid, sorted);
    if (candidates.isEmpty) {
      return;
    }

    final target = (candidates.length * spec.slopeDensity).round();
    final placed = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);

    while (placed.length < target && attempts < maxAttempts) {
      attempts++;
      final head = candidates[rng.nextInt(candidates.length)];
      if (grid.cells[head]!.type != HexType.plain) {
        continue;
      }
      if (placed.any((p) => p.distanceTo(head) < 3)) {
        continue;
      }
      final direction = rng.nextInt(HexCoord.directions.length);
      final step = HexCoord.directions[direction];
      final run = 2 + rng.nextInt(2);
      var c = head;
      for (var i = 0; i < run; i++) {
        final cell = grid.cells[c];
        if (cell == null || cell.type != HexType.plain) {
          break;
        }
        // A run never takes a protected cell: an arrow lane across the start
        // pocket would shove her before the first decision was hers.
        if (_protected(grid).contains(c)) {
          break;
        }
        cell.type = HexType.slope;
        // Every tile in a run points the same way, which is what makes it a
        // lane rather than a scatter of shoves.
        cell.slopeDirection = direction;
        placed.add(c);
        c = c + step;
      }
    }
  }

  /// Drift ice, in patches: one cell of no-steering is a curiosity, three is
  /// a surface you commit to.
  static void _placeIce(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _placePatches(
      grid,
      sorted,
      spec.iceDensity,
      rng,
      HexType.ice,
      minSize: 2,
      maxSize: 4,
      spacing: 3,
    );
  }

  /// Mire, in patches, for the same reason: a tax you only pay once is not a
  /// tax you ever notice.
  static void _placeMire(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _placePatches(
      grid,
      sorted,
      spec.mireDensity,
      rng,
      HexType.mire,
      minSize: 3,
      maxSize: 5,
      spacing: 3,
    );
  }

  /// Eddies and magnets, as singles. A force dot needs space around it to be
  /// read against, and two of them overlapping is a whirlpool nobody authored.
  static void _placeEddy(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _scatterSingles(
      grid,
      sorted,
      spec.eddyDensity,
      rng,
      HexType.eddy,
      spacing: 3,
    );
  }

  static void _placeMagnet(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _scatterSingles(
      grid,
      sorted,
      spec.magnetDensity,
      rng,
      HexType.magnet,
      spacing: 3,
    );
  }

  /// Thicket: short strings across sightlines. The concealment is the
  /// mechanic; a single tile conceals one neighbour, a line conceals a wall's
  /// worth.
  static void _placeThicket(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _placeLines(
      grid,
      sorted,
      spec.thicketDensity,
      rng,
      HexType.thicket,
      minRun: 2,
      maxRun: 3,
      spacing: 4,
    );
  }

  /// Sleepers as scattered singles: plain until proven otherwise, most honest
  /// where they are rare enough that a second tap on "plain" is a lesson
  /// rather than the rule.
  static void _placeSleeper(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _scatterSingles(
      grid,
      sorted,
      spec.sleeperDensity,
      rng,
      HexType.sleeper,
      spacing: 2,
    );
  }

  /// Foxfire decoys, posed where a real prize might sit: off the shoulders of
  /// the route, not buried in the corners — a telltale nobody believes is not
  /// a trap worth checking.
  static void _placeFoxfire(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    if (spec.foxfireDensity <= 0) {
      return;
    }
    final candidates = [
      for (final c in _pool(grid, sorted))
        if (c.distanceTo(grid.start) >= 3 && c.distanceTo(grid.exit) >= 3) c,
    ];
    if (candidates.isEmpty) {
      return;
    }
    final target = (candidates.length * spec.foxfireDensity).round();
    final placed = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);
    while (placed.length < target && attempts < maxAttempts) {
      attempts++;
      final c = candidates[rng.nextInt(candidates.length)];
      if (grid.cells[c]!.type != HexType.plain) {
        continue;
      }
      if (placed.any((p) => p.distanceTo(c) < 3)) {
        continue;
      }
      grid.cells[c]!.type = HexType.foxfire;
      placed.add(c);
    }
  }

  /// Scaffolds, singles: carve-from-range tiles. Never beside the ends, or
  /// the first tap of the level would already stand too close.
  static void _placeScaffold(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _scatterSingles(
      grid,
      sorted,
      spec.scaffoldDensity,
      rng,
      HexType.scaffold,
      spacing: 3,
    );
  }

  /// Sunken ground, in small patches.
  ///
  /// Patches rather than lines or singles: the pressure is "you cannot reach
  /// across this", and one tile is a pebble you step over without noticing.
  /// Three or four together is a piece of ground you have to walk *into*.
  static void _placeSunken(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _placePatches(
      grid,
      sorted,
      spec.sunkenDensity,
      rng,
      HexType.sunken,
      minSize: 2,
      maxSize: 4,
      spacing: 3,
    );
  }

  /// Thorn pads, in small clusters on plain ground: the shortcut you can see
  /// the spikes on.
  static void _placeThorns(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _placePatches(
      grid,
      sorted,
      spec.thornDensity,
      rng,
      HexType.thorn,
      minSize: 2,
      maxSize: 3,
      spacing: 4,
    );
  }

  /// Alarm bells, scattered: one per tempting cut-point at most.
  static void _placeAlarms(
    HexGrid grid,
    List<HexCoord> sorted,
    LevelSpec spec,
    math.Random rng,
  ) {
    _scatterSingles(
      grid,
      sorted,
      spec.alarmDensity,
      rng,
      HexType.alarm,
      spacing: 5,
    );
  }

  /// The gloom band: one strip across the middle of the silhouette where the
  /// fog is twice as thick. It is terrain, not tiles — the cells stay
  /// whatever they are; the band only dims what she can see of them.
  static void _markGloom(HexGrid grid, LevelSpec spec, math.Random rng) {
    if (!spec.gloom) {
      return;
    }
    final rows = [
      for (final c in grid.cells.keys) c,
    ]..sort((a, b) => a.r != b.r ? a.r.compareTo(b.r) : a.q.compareTo(b.q));
    if (rows.isEmpty) {
      return;
    }
    final lo = rows.first.r;
    final hi = rows.last.r;
    final span = hi - lo;
    if (span < 8) {
      return;
    }
    // Somewhere in the middle half — multiplied r keeps the two axial bands
    // of the same row together regardless of column skew.
    final bandLo = lo + (span * (0.3 + rng.nextDouble() * 0.4)).floor();
    for (final cell in grid.all) {
      final r = cell.coord.r;
      if (r >= bandLo && r <= bandLo + 1) {
        cell.gloomed = true;
      }
    }
  }

  /// Single scattered tiles of one type with breathing room between them —
  /// the shared shape for every family whose mechanic dies in a clump.
  static void _scatterSingles(
    HexGrid grid,
    List<HexCoord> sorted,
    double density,
    math.Random rng,
    HexType type, {
    required int spacing,
  }) {
    if (density <= 0) {
      return;
    }
    final candidates = _pool(grid, sorted);
    if (candidates.isEmpty) {
      return;
    }
    final target = (candidates.length * density).round();
    final placed = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);
    while (placed.length < target && attempts < maxAttempts) {
      attempts++;
      final c = candidates[rng.nextInt(candidates.length)];
      if (grid.cells[c]!.type != HexType.plain) {
        continue;
      }
      if (placed.any((p) => p.distanceTo(c) < spacing)) {
        continue;
      }
      grid.cells[c]!.type = type;
      placed.add(c);
    }
  }

  /// Short straight runs of one type — faults, braids, thickets: the families
  /// whose mechanic only reads when at least two of them line up.
  static void _placeLines(
    HexGrid grid,
    List<HexCoord> sorted,
    double density,
    math.Random rng,
    HexType type, {
    required int minRun,
    required int maxRun,
    required int spacing,
  }) {
    if (density <= 0) {
      return;
    }
    final candidates = _pool(grid, sorted);
    if (candidates.isEmpty) {
      return;
    }
    final target = (candidates.length * density).round();
    final placed = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);

    while (placed.length < target && attempts < maxAttempts) {
      attempts++;
      final start = candidates[rng.nextInt(candidates.length)];
      if (placed.any((p) => p.distanceTo(start) < spacing)) {
        continue;
      }
      final direction = HexCoord.directions[rng.nextInt(6)];
      final length = minRun + rng.nextInt(maxRun - minRun + 1);

      // Walked first and committed second: a line that runs off the board or
      // into a wall halfway through would leave a one-cell stub, which is the
      // confetti case this exists to avoid.
      final line = <HexCoord>[];
      var cursor = start;
      for (var i = 0; i < length; i++) {
        final cell = grid.cells[cursor];
        if (cell == null ||
            cell.type != HexType.plain ||
            _protected(grid).contains(cursor)) {
          break;
        }
        line.add(cursor);
        cursor += direction;
      }
      if (line.length < minRun) {
        continue;
      }
      for (final c in line) {
        grid.cells[c]!.type = type;
        placed.add(c);
      }
    }
  }

  /// Small blobs of one type: patches big enough that stepping around them is
  /// a choice, small enough that the board is not made of them.
  static void _placePatches(
    HexGrid grid,
    List<HexCoord> sorted,
    double density,
    math.Random rng,
    HexType type, {
    required int minSize,
    required int maxSize,
    required int spacing,
  }) {
    if (density <= 0) {
      return;
    }
    final candidates = _pool(grid, sorted);
    if (candidates.isEmpty) {
      return;
    }
    final target = (candidates.length * density).round();
    final placed = <HexCoord>[];
    var attempts = 0;
    final maxAttempts = math.max(40, target * 12);

    while (placed.length < target && attempts < maxAttempts) {
      attempts++;
      final seed = candidates[rng.nextInt(candidates.length)];
      if (grid.cells[seed]!.type != HexType.plain) {
        continue;
      }
      if (placed.any((p) => p.distanceTo(seed) < spacing)) {
        continue;
      }
      final patch = [seed, ...seed.neighbours]..shuffle(rng);
      final size = minSize + rng.nextInt(maxSize - minSize + 1);
      var takenInPatch = 0;
      for (final c in patch) {
        if (takenInPatch >= size) {
          break;
        }
        final cell = grid.cells[c];
        if (cell == null ||
            cell.type != HexType.plain ||
            _protected(grid).contains(c)) {
          continue;
        }
        cell.type = type;
        placed.add(c);
        takenInPatch++;
      }
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
              : grid.cells[n]?.type.blocksTravelInPrinciple == true;
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
