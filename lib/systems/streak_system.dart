import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';

/// What a tap did to the chain, so the game can pick a note, a burst size and a
/// haptic from one decision.
enum StreakOutcome {
  /// Carried the chain forward — a cell genuinely closer to the bone.
  advanced,

  /// Landed, but sideways or backwards. The chain resets.
  broken,

  /// Nothing was carved: an anchor, or a tap that found nothing. Also resets.
  wasted,
}

/// The tap chain.
///
/// Every tap in this game used to be byte-identical — the same haptic, the same
/// five shards, the same silence — twenty times a run. That is what "tap tap
/// tap" describes: the game acknowledging a player's twentieth tap exactly as it
/// acknowledged their first, so nothing ever feels like it is building.
///
/// Consecutive taps that make real progress climb a scale, and the whole
/// presentation climbs with them. Break the chain and it drops to the root.
///
/// It touches **feel only** — never score. Stars stay on taps alone (§12.4), so
/// the chain can never make the game harder, only better to play.
class StreakSystem {
  int _streak = 0;
  int _best = 0;

  int get streak => _streak;

  /// The longest chain this run, for the results panel.
  int get best => _best;

  /// Progress means closer to the bone along a route that exists, measured on
  /// the anchor-aware field the dog steers on. Straight hex distance would
  /// reward carving into a wall just because the bone lies beyond it.
  StreakOutcome register({
    required HexGrid grid,
    required HexCoord tapped,
    required HexCoord dogCell,
    required bool carved,
  }) {
    if (!carved) {
      _streak = 0;
      return StreakOutcome.wasted;
    }
    if (grid.distanceToExit(tapped) < grid.distanceToExit(dogCell)) {
      _streak++;
      if (_streak > _best) {
        _best = _streak;
      }
      return StreakOutcome.advanced;
    }
    _streak = 0;
    return StreakOutcome.broken;
  }

  void reset() {
    _streak = 0;
    _best = 0;
  }

  /// 0..1, how far up the chain is. Drives burst size and haptic weight so they
  /// escalate with the note instead of each being tuned separately.
  double get intensity => (_streak / 8).clamp(0.0, 1.0);
}
