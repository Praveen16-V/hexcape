import 'dart:collection';

import 'hex_cell.dart';
import 'hex_coord.dart';

/// The field of hexes for one level. Pure model — no rendering, no Flutter —
/// so the generator, the regrowth rules and the soft-lock check are all
/// testable without a widget tree.
class HexGrid {
  HexGrid({
    required this.cells,
    required this.start,
    required this.exit,
    required this.truePath,
  });

  final Map<HexCoord, HexCell> cells;

  /// Where the dog begins.
  final HexCoord start;

  /// Where the food sits.
  final HexCoord exit;

  /// The route the generator carved. Never shown to the player — it exists for
  /// the directional hint (§8) and for the debug overlay.
  final List<HexCoord> truePath;

  Iterable<HexCell> get all => cells.values;

  int get length => cells.length;

  bool contains(HexCoord c) => cells.containsKey(c);

  HexCell? at(HexCoord c) => cells[c];

  /// Anything off the silhouette counts as solid, so the field edge behaves
  /// like a wall without needing a border of real cells.
  bool blocks(HexCoord c) {
    final cell = cells[c];
    return cell == null || cell.isSolid;
  }

  bool isPassable(HexCoord c) => cells[c]?.isPassable ?? false;

  bool isClearable(HexCoord c) => cells[c]?.isClearable ?? false;

  bool isAnchor(HexCoord c) => cells[c]?.type == HexType.anchor;

  /// Cells the player could *in principle* travel through, ignoring their
  /// current state — everything except anchors and empty space. This is the
  /// graph the soft-lock check runs on (§4).
  bool isTraversableInPrinciple(HexCoord c) {
    final cell = cells[c];
    return cell != null && cell.type != HexType.anchor;
  }

  Iterable<HexCoord> neighboursOf(HexCoord c) =>
      c.neighbours.where(cells.containsKey);

  /// Taps still needed to open [c]. Zero for anything already passable, and
  /// effectively infinite for anchors and empty space.
  ///
  /// This is the cost function for both par and the budget-aware soft-lock
  /// check, so those two always agree about what a route is worth.
  int remainingCost(HexCoord c) => cells[c]?.remainingHits ?? (1 << 20);

  /// Steps from every cell to the food, routed around anchors.
  ///
  /// Anchors never move once a level is generated, so this is computed once and
  /// reused. Straight hex distance would be cheaper, but it treats a wall as if
  /// it were not there — the dog would press into an anchor face because the
  /// cell beyond it looks closer, instead of following the detour around it.
  ///
  /// Deliberately counted in steps, not in taps: the dog walks through whatever
  /// is already open, and what a cell cost to open is the player's problem, not
  /// hers. Weighting this by tap cost would make her swerve around heavy hexes
  /// that are already holes in the ground.
  /// Cached, not `late final`: [dig] can remove an anchor mid-run, and a field
  /// computed once would then route her around a wall that is no longer there.
  Map<HexCoord, int>? _exitDistance;

  Map<HexCoord, int> get exitDistance => _exitDistance ??= _buildExitDistance();

  /// Call after changing which cells are anchors. Nothing else moves a wall, so
  /// nothing else needs this.
  void invalidateTopology() => _exitDistance = null;

  Map<HexCoord, int> _buildExitDistance() {
    final field = <HexCoord, int>{exit: 0};
    final queue = Queue<HexCoord>()..add(exit);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final next = field[current]! + 1;
      for (final n in current.neighbours) {
        if (field.containsKey(n) || !isTraversableInPrinciple(n)) {
          continue;
        }
        field[n] = next;
        queue.add(n);
      }
    }
    return field;
  }

  /// How far [c] is from the food. Cells walled off by anchors report a large
  /// value rather than being absent, so callers can compare without a null.
  int distanceToExit(HexCoord c) => exitDistance[c] ?? 1 << 20;

  /// True when every direction out of [c] is blocked. Drives the boxed-in
  /// failure state (§10) and the "nowhere to drift" idle.
  bool isEnclosed(HexCoord c) => c.neighbours.every(blocks);

  /// Fraction of the cells within [radius] of [c] that are passable, measured
  /// against how many cells actually exist there. This is the openness that
  /// scales drift speed (§2.2) — the field edge correctly reads as *closed*,
  /// so hugging the boundary slows the dog down rather than speeding it up.
  double opennessAround(HexCoord c, {int radius = 2}) {
    var open = 0;
    final total = HexCoord.discSize(radius);
    for (final coord in c.disc(radius)) {
      if (isPassable(coord)) {
        open++;
      }
    }
    return open / total;
  }

  void resetAll() {
    for (final cell in cells.values) {
      cell.resetToSolid();
    }
  }
}
