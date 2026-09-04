import 'dart:math' as math;

/// The clock, in the game's own clothes.
///
/// Regrowth was meant to be the pressure (§2.3), but it only ever eats the
/// corridor *behind* her — which a player carving forward one cell at a time
/// never needs again. So a methodical player faced no pressure at all, and
/// thinking was free, against §2.2's promise that "the dog keeps drifting while
/// they decide, so hesitation has a cost".
///
/// A draining hunger bar fixes that, and does something the tap budget cannot:
/// it makes *speed* worth something. Until now, carving wide was strictly worse
/// — more taps, no benefit — so the openness-to-speed trade that §2.2 calls the
/// heart of the game had exactly one correct answer. With a clock running,
/// opening up to go fast becomes a real gamble against losing control.
class HungerSystem {
  double _capacity = 1;
  double _remaining = 1;
  bool _warned = false;

  /// Seconds of walking the bar is worth when full.
  double get capacity => _capacity;

  double get remaining => _remaining;

  /// 1 down to 0, for the bar and for the fading glow.
  double get fraction =>
      _capacity <= 0 ? 0 : (_remaining / _capacity).clamp(0.0, 1.0);

  bool get isStarved => _remaining <= 0;

  /// Below this the bar reddens and a haptic fires once.
  static const warnAt = 0.25;

  /// Sized from par so a long level is not automatically a harder one: the
  /// clock scales with the journey rather than with the calendar.
  void reset({required int par, required double secondsPerCell}) {
    _capacity = math.max(1.0, par * secondsPerCell);
    _remaining = _capacity;
    _warned = false;
  }

  /// Returns true on the frame the bar first crosses into the warning band, so
  /// the game can fire a single haptic rather than one per frame.
  bool drain(double dt) {
    if (_remaining <= 0) {
      return false;
    }
    _remaining = math.max(0, _remaining - dt);
    if (!_warned && fraction <= warnAt) {
      _warned = true;
      return true;
    }
    return false;
  }

  /// A patrol catching her (§6.1). Never drives the bar below empty, so the
  /// starve check downstream sees a clean zero rather than a negative that
  /// would make the drawn bar overshoot.
  void bite(double seconds) {
    _remaining = math.max(0, _remaining - seconds);
  }

  /// A treat. Never overfills — a bar that could exceed its own capacity would
  /// make the readout meaningless.
  void feed(double seconds) {
    _remaining = math.min(_capacity, _remaining + seconds);
    if (fraction > warnAt) {
      _warned = false;
    }
  }
}
