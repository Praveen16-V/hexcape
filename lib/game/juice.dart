import 'dart:math' as math;
import 'dart:ui';

/// Screen shake and hit-stop.
///
/// Both are the cheapest weight a game can buy. Shake says *that landed*;
/// hit-stop — a few frames where the simulation simply stops — says *that
/// mattered*. At 40 to 80 milliseconds nobody reads it as a pause; they read it
/// as impact.
class Juice {
  Juice({this.scale = 1.0});

  /// Global multiplier. Zero turns all of it off without removing the calls.
  double scale;

  double _shake = 0;
  double _hitStop = 0;
  double _time = 0;

  final math.Random _rng = math.Random();
  Offset _offset = Offset.zero;

  /// Time constant of the decay. A hit should be over in a few hundred
  /// milliseconds — anything slower stops reading as impact and starts reading
  /// as a camera on a boat.
  static const _decayTau = 0.1;

  /// Below this the shake is sub-pixel, so it is cut rather than left to crawl
  /// toward zero for another half-second.
  static const _cutoff = 0.15;

  /// Where the whole field should be drawn this frame.
  ///
  /// Applied once when rendering the component tree — deliberately **not** by
  /// shifting `HexLayout.origin`, which is what tap resolution hit-tests
  /// against. Shaking that would make the board physically dodge the player's
  /// finger, which is a worse version of the mis-tap bug this game already had.
  Offset get offset => _offset;

  bool get isFrozen => _hitStop > 0;

  double get shakeAmount => _shake;

  /// [amount] is in logical pixels of initial displacement.
  void shake(double amount) {
    _shake = math.max(_shake, amount * scale);
  }

  /// Freezes the simulation for [seconds]. Visuals keep decaying.
  void freeze(double seconds) {
    _hitStop = math.max(_hitStop, seconds * (scale > 0 ? 1 : 0));
  }

  /// Returns the time step the simulation should actually advance by, and
  /// updates the shake. During hit-stop this is zero, so callers can pass the
  /// result straight through without branching everywhere.
  double consume(double dt) {
    _time += dt;

    // Decay first so a shake started this frame is still visible on it.
    if (_shake > _cutoff) {
      // Random direction each frame rather than a smooth wobble: a rattle reads
      // as an impact, a sine reads as a camera on a boat.
      _offset = Offset(
        (_rng.nextDouble() * 2 - 1) * _shake,
        (_rng.nextDouble() * 2 - 1) * _shake,
      );
      _shake *= math.exp(-dt / _decayTau);
    } else {
      _shake = 0;
      _offset = Offset.zero;
    }

    if (_hitStop > 0) {
      _hitStop = math.max(0, _hitStop - dt);
      return 0;
    }
    return dt;
  }

  void reset() {
    _shake = 0;
    _hitStop = 0;
    _offset = Offset.zero;
  }

  /// Free-running clock, for anything that should keep animating through a
  /// freeze.
  double get time => _time;
}
