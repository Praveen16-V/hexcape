import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../entities/pickup.dart';
import '../gen/pathfinder.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';

/// Soft-lock detection (§4). A correctness requirement, not a convenience:
/// without it a player can end up watching a dead field regrow around them
/// with no recourse, which is worse than any missing hint.
///
/// The test is not "is there a route" but **"is there a route I can still
/// afford"**: the cheapest way from the dog to the food, where cells already
/// open are free and solid ones cost the taps still needed to open them. When
/// that exceeds the remaining taps, check pickups and charges before ending
/// the run.
///
/// Costing it this way is what makes a wasted tap matter immediately. It also
/// means the check finally does real work — with unlimited taps and only static
/// anchors it was effectively an invariant assertion that never fired.
///
/// Deliberately **optimistic**: it ignores regrowth that has not happened yet,
/// so a corridor the player will have to re-open counts as free. Erring this way
/// means the run only ever ends when finishing is genuinely impossible, never
/// when it merely looks unlikely.
class SoftlockSystem {
  HexGrid? _lastGrid;
  HexCoord? _lastCell;
  int _lastFieldVersion = -1;
  int _lastTapsLeft = -1;
  int _lastTreatTaps = -1;
  int _lastBlasts = -1;
  int _lastDigs = -1;
  List<(PickupKind, HexCoord)> _lastPickups = const [];
  bool _locked = false;

  bool get isLocked => _locked;

  /// Reuses the verdict until the board, dog, budget, or recovery resources
  /// change. Pickup collection can change affordability without a field edit.
  bool check({
    required HexGrid grid,
    required HexCoord dogCell,
    required int fieldVersion,
    required int tapsLeft,
    Iterable<Pickup> pickups = const [],
    int treatTaps = 0,
    int blastCharges = 0,
    int digCharges = 0,
  }) {
    // Only what can actually pay for a route out. Written as an explicit list
    // rather than `kind.isCharge`, because a charge is not automatically a
    // recovery: STAKE holds ground open but opens none, so counting it here
    // would let the check believe in a rescue that cannot happen and leave a
    // player stuck in a level it had decided was still winnable.
    const recoveries = {PickupKind.blast, PickupKind.dig};
    final remaining = [
      for (final pickup in pickups)
        if (!pickup.collected &&
            (recoveries.contains(pickup.kind) ||
                (pickup.kind.refundsTaps && treatTaps > 0)))
          (pickup.kind, pickup.coord),
    ];
    if (identical(grid, _lastGrid) &&
        dogCell == _lastCell &&
        fieldVersion == _lastFieldVersion &&
        tapsLeft == _lastTapsLeft &&
        treatTaps == _lastTreatTaps &&
        blastCharges == _lastBlasts &&
        digCharges == _lastDigs &&
        listEquals(remaining, _lastPickups)) {
      return _locked;
    }
    _lastGrid = grid;
    _lastCell = dogCell;
    _lastFieldVersion = fieldVersion;
    _lastTapsLeft = tapsLeft;
    _lastTreatTaps = treatTaps;
    _lastBlasts = blastCharges;
    _lastDigs = digCharges;
    _lastPickups = remaining;

    final cost = Pathfinder.cheapestCost(
      dogCell,
      grid.exit,
      grid.isTraversableInPrinciple,
      grid.remainingCost,
    );
    _locked =
        (cost == null || cost > tapsLeft) &&
        !_recoveryPossible(
          grid: grid,
          dogCell: dogCell,
          tapsLeft: tapsLeft,
          pickups: remaining,
          treatTaps: treatTaps,
          blasts: blastCharges,
          digs: digCharges,
        );
    return _locked;
  }

  /// A lower bound on recovery cost, not a solver promising a winning route.
  /// Credit each affordable pickup once, then search again for newly affordable
  /// pickups. Detour costs and future regrowth are deliberately not deducted:
  /// overestimating the player's options delays a loss instead of causing one.
  /// Blast gets its maximum possible saving (seven heavy cells for one tap),
  /// while dig searches track the actual number of anchors it can remove.
  static bool _recoveryPossible({
    required HexGrid grid,
    required HexCoord dogCell,
    required int tapsLeft,
    required List<(PickupKind, HexCoord)> pickups,
    required int treatTaps,
    required int blasts,
    required int digs,
  }) {
    if (pickups.isEmpty && blasts <= 0 && digs <= 0) {
      return false;
    }
    var allowance = math.max(0, tapsLeft);
    final pending = pickups.toList();
    final blastSaving = HexCoord.discSize(ActiveEffects.blastRadius) * 2 - 1;
    while (true) {
      // A charge still costs a tap. At zero, only a pickup on open ground can
      // restore spending power; merely holding a charge cannot do that.
      final budget =
          allowance + math.min(math.max(0, blasts), allowance) * blastSaving;
      final reachable = _affordableCells(
        grid,
        dogCell,
        budget,
        math.min(math.max(0, digs), allowance),
      );
      if (reachable.contains(grid.exit)) {
        return true;
      }
      var gained = false;
      for (final pickup in pending.toList()) {
        if (!reachable.contains(pickup.$2)) {
          continue;
        }
        pending.remove(pickup);
        gained = true;
        switch (pickup.$1) {
          case PickupKind.treat:
            allowance += math.max(0, treatTaps);
          case PickupKind.ration:
            allowance += ActiveEffects.rationTaps;
          case PickupKind.blast:
            blasts++;
          case PickupKind.dig:
            digs++;
          default:
            break;
        }
      }
      if (!gained) {
        return false;
      }
    }
  }

  /// Dijkstra with a separate state for each number of digs spent. Keeping
  /// these states distinct preserves a more expensive route that saves a dig
  /// for a later wall. No board or pickup is mutated by the recovery search.
  static Set<HexCoord> _affordableCells(
    HexGrid grid,
    HexCoord start,
    int budget,
    int digs,
  ) {
    final origin = (start, 0);
    final best = <(HexCoord, int), int>{origin: 0};
    final frontier = SplayTreeMap<int, List<(HexCoord, int)>>()..[0] = [origin];
    final reachable = <HexCoord>{};
    while (frontier.isNotEmpty) {
      final cost = frontier.firstKey()!;
      final bucket = frontier[cost]!;
      final state = bucket.removeLast();
      if (bucket.isEmpty) {
        frontier.remove(cost);
      }
      if (best[state] != cost) {
        continue;
      }
      reachable.add(state.$1);
      for (final next in grid.neighboursOf(state.$1)) {
        final anchor = grid.isDiggable(next);
        final spent = state.$2 + (anchor ? 1 : 0);
        if (spent > digs) {
          continue;
        }
        final nextCost = cost + (anchor ? 1 : grid.remainingCost(next));
        final nextState = (next, spent);
        if (nextCost > budget || nextCost >= (best[nextState] ?? 1 << 30)) {
          continue;
        }
        best[nextState] = nextCost;
        (frontier[nextCost] ??= []).add(nextState);
      }
    }
    return reachable;
  }

  void reset() {
    _lastGrid = null;
    _lastCell = null;
    _lastFieldVersion = -1;
    _lastTapsLeft = -1;
    _lastTreatTaps = -1;
    _lastBlasts = -1;
    _lastDigs = -1;
    _lastPickups = const [];
    _locked = false;
  }
}
