import 'dart:ui';

import '../hex/hex_coord.dart';
import '../hex/hex_layout.dart';

/// A light and what it does to you (§6.1), generalised from the one patrolling
/// kind into the whole family.
///
/// None of them clear hexes, and hexes do not stop them — a light passes over
/// solid ground and open ground alike, because it is a light rather than a
/// body. That is what makes them implementable on a board which is almost
/// entirely solid at the start of a level, and it is also the more interesting
/// obstacle: a guard that could be walled out would simply be another wall,
/// and the game already has walls.
///
/// The family splits on two axes. **What it moves over**: a route walked end
/// to end, a ring orbiting a pivot, a straight dash, or one fixed patch of
/// ground. And **what it blocks**: her body ([blocksDog]) or your hands
/// ([wardsTaps]). A patrol is a moving wall for *her*; a sentry is a moving
/// wall for *your taps*. Making one light do both would only be a better
/// guard; keeping the jobs separate is what gives each kind a pressure of its
/// own — and why the warding kinds can never cause an unavoidable loss: the
/// worst they cost is time, which is charged to the hunger clock, which is
/// the right currency for waiting.
enum GuardKind {
  /// Sweeps a route, end to end and back. She refuses the lit ground; being
  /// caught costs three seconds and a shove.
  patrol,

  /// Sweeps a route the same way, but refuses taps rather than her body, and
  /// never bites.
  sentry,

  /// One fixed seven-cell patch, always lit, refusing taps. The training
  /// sentry: timing without motion.
  beacon,

  /// A ring walked continuously in one direction around a pivot. The sweep
  /// never reverses, so the window it opens also never reverses.
  spinner,

  /// A straight line taken at a dash, with a long lit pause at each end to
  /// telegraph the next run. Fast, but honest.
  runner,

  /// One fixed patch that phases fully on and off on a steady beat. Pure
  /// timing ground: taps land when it is dark.
  blinker,

  /// A slow patrol that also re-closes every open tile it passes over. The
  /// corridor it walks is never safe behind her either.
  warden,
}

class Guard {
  Guard({
    required this.patrol,
    this.cellsPerSecond = 0.85,
    this.kind = GuardKind.patrol,
    this.litRadius = 1,
  });

  final GuardKind kind;

  /// The route it walks, end to end and back again. A beacon or blinker is a
  /// route of one cell that never moves; a spinner's route is the ring.
  final List<HexCoord> patrol;

  final double cellsPerSecond;

  /// The lit patch's reach from the lit centre, in rings. One everywhere in
  /// the campaign; parameterised so the debug panel can feel a bigger sweep
  /// without authoring a new kind.
  final int litRadius;

  /// Whether the light does anything at all to the dog's movement.
  bool get blocksDog =>
      kind == GuardKind.patrol ||
      kind == GuardKind.spinner ||
      kind == GuardKind.runner ||
      kind == GuardKind.warden;

  /// Whether taps inside the lit ground are refused while the lamp is on.
  bool get wardsTaps =>
      kind == GuardKind.sentry ||
      kind == GuardKind.beacon ||
      kind == GuardKind.blinker;

  /// Whether the route wraps rather than ping-ponging — the spinner's ring.
  bool get loops => kind == GuardKind.spinner;

  /// Whether the route dashes and then breathes — the runner.
  bool get dashes => kind == GuardKind.runner;

  /// Whether this light is a fixed patch driven by a phase rather than a
  /// walk — the beacon (always on) and the blinker (on a beat).
  bool get isStill => kind == GuardKind.beacon || kind == GuardKind.blinker;

  /// The one the old code asked about: a light for your hands, not her body.
  bool get isSentry => wardsTaps;

  int index = 0;
  bool forward = true;

  /// Progress from [cell] toward [nextCell], 0..1.
  double t = 0;

  /// Seconds left standing at the end of a dash, telegraphing the next one.
  double pauseFor = 0;

  /// A blinker's accumulated phase, and whether the lamp is lit *now*.
  /// Everything else keeps its lamp on permanently.
  double phase = 0;
  bool lampOn = true;

  /// 1 -> 0 as a runner telegraphs its next dash.
  double get windUp => dashes && pauseFor > 0
      ? (1 - pauseFor / endPause).clamp(0.0, 1.0)
      : 0;

  /// Seconds a runner stands at each end. Long enough to see, short enough
  /// that a lane reopens often.
  static const endPause = 1.2;

  /// The blinker's beat, in seconds: this much dark, this much light.
  static const blinkDark = 1.6;
  static const blinkLit = 1.6;

  /// 1 -> 0 after it catches her. Drives the flare.
  double alertFlash = 0;

  HexCoord get cell => patrol[index];

  /// Where it is heading. A walking light turns at the ends of its route; a
  /// ring light never turns; a still light is always here.
  HexCoord get nextCell {
    if (loops) {
      return patrol[(index + 1) % patrol.length];
    }
    final step = forward ? 1 : -1;
    final n = index + step;
    if (n < 0 || n >= patrol.length) {
      return patrol.isEmpty ? cell : patrol[(index - step).clamp(0, patrol.length - 1)];
    }
    return patrol[n];
  }

  /// The cell the light is actually over, which is what gameplay reads.
  ///
  /// Rounded from the interpolated position rather than held at [cell] for the
  /// whole step: otherwise the drawn light and the forbidden ground disagree by
  /// up to a full hex, and being caught looks like a bug.
  HexCoord get litCentre => t < 0.5 ? cell : nextCell;

  /// The ground the lamp currently rules. Empty while a blinker is dark —
  /// which is the entire point of a blinker — and while nothing is lit a
  /// light blocks nothing and wards nothing.
  Iterable<HexCoord> get lit =>
      lampOn ? litCentre.disc(litRadius) : const <HexCoord>[];

  Offset positionIn(HexLayout layout) =>
      Offset.lerp(layout.toPixel(cell), layout.toPixel(nextCell), t)!;

  /// Instantaneous motion in pixels per second — the runner's trail reads it.
  Offset velocityIn(HexLayout layout) =>
      (layout.toPixel(nextCell) - layout.toPixel(cell)) * cellsPerSecond;

  /// The spinner's sweep angle, for its blades: progress around the ring it
  /// walks, so the vane it carries turns with the window it opens.
  double get leadAngle =>
      patrol.length < 2 ? 0.0 : (index + t) / patrol.length * 2 * 3.141592653589793;

  void update(double dt) {
    alertFlash = alertFlash - dt * 2.2;
    if (alertFlash < 0) {
      alertFlash = 0;
    }

    if (kind == GuardKind.blinker) {
      phase += dt;
      final cycle = blinkDark + blinkLit;
      final within = phase % cycle;
      lampOn = within >= blinkDark;
      return;
    }
    if (isStill) {
      lampOn = true;
      return;
    }
    lampOn = true;

    if (dashes && pauseFor > 0) {
      pauseFor -= dt;
      if (pauseFor > 0) {
        return;
      }
      pauseFor = 0;
    }

    t += dt * cellsPerSecond;
    while (t >= 1) {
      t -= 1;
      _advance();
      if (dashes && _atEnd) {
        pauseFor = endPause;
        t = 0;
        break;
      }
    }
  }

  bool get _atEnd {
    if (loops) {
      return false;
    }
    return forward ? index == patrol.length - 1 : index == 0;
  }

  void _advance() {
    if (loops) {
      index = (index + 1) % patrol.length;
      return;
    }
    final step = forward ? 1 : -1;
    final next = index + step;
    if (next < 0 || next >= patrol.length) {
      forward = !forward;
      index += forward ? 1 : -1;
      index = index.clamp(0, patrol.length - 1);
    } else {
      index = next;
    }
  }
}
