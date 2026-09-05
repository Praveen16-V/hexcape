import 'package:flutter/foundation.dart';

/// The numbers §16 lists as unresolved, exposed as live sliders.
///
/// Speeds are in **hex widths per second** rather than pixels, so the game
/// feels identical on a small phone and a tablet. Reach uses the same board
/// scale; tap snapping remains a separate responsibility of InputSystem.
class TuningConfig extends ChangeNotifier {
  static const tapRadiusRange = (40.0, 160.0);
  static const driftRange = (0.2, 6.0);
  static const momentumRange = (1.5, 14.0);
  static const regrowDelayRange = (1.5, 20.0);
  static const faultDelayRange = (1.0, 6.0);
  static const faultDensityRange = (0.0, 0.25);
  static const suffocateRange = (0.8, 6.0);
  static const anchorDensityRange = (0.0, 0.45);
  static const heavyDensityRange = (0.0, 0.5);
  static const revealFactorRange = (1.2, 4.0);
  static const budgetRange = (1.1, 4.0);
  static const hungerRange = (0.8, 4.0);
  static const treatSecondsRange = (0.0, 12.0);
  static const treatTapsRange = (0.0, 5.0);
  static const pickupCountRange = (0.0, 6.0);
  static const volumeRange = (0.0, 1.0);
  static const shakeRange = (0.0, 2.5);

  /// Reach calibrated at the original simulation's 23.7-pixel hex radius.
  /// Retain the existing tuning range while scaling its physical size with
  /// the board. The default reaches approximately 1.9 hex widths.
  double tapRadius = 78;

  static const referenceHexWidth = 23.7 * 1.7320508075688772;

  double tapRadiusFor(double hexWidth) =>
      tapRadius * hexWidth / referenceHexWidth;

  /// Drift speed in a single-hex channel — the safe, slow end of §2.2.
  double driftMin = 0.75;

  /// Drift speed in wide-open space — the fast, risky end of §2.2.
  double driftMax = 3.4;

  /// Steering responsiveness. Lower means heavier momentum and more overshoot.
  double momentum = 6.0;

  /// Seconds a cleared cell waits, once it is on the edge of the cleared
  /// region, before it begins growing back.
  double regrowDelay = 6.0;

  /// How long the dog survives fully boxed in before the field crushes it.
  double suffocateSeconds = 2.5;

  double anchorDensity = 0.22;

  bool hintsEnabled = true;

  /// Whether the tuning panel is reachable at all. See [Progress.developerTools]
  /// for why this is a setting rather than a compile-time flag.
  bool developerTools = false;

  /// Player setting: no shake, no hit-stop, no fade to grey. Distinct from
  /// [juiceScale], which is a tuning slider — this is the one the player owns,
  /// and it has to switch off the desaturation as well, which juiceScale does
  /// not touch.
  bool reducedMotion = false;

  double springDensity = 0;
  int guardCount = 0;

  /// Warded lights, from [Campaign.sentriesFrom] onward.
  int sentryCount = 0;
  double guardSpeed = 0.85;

  /// Fraction of eligible cells promoted to faults. Zero everywhere until the
  /// campaign introduces them, so the mechanic can ship and be playtested from
  /// the debug panel long before any level references it.
  double faultDensity = 0;

  /// How long a cleared fault stays open.
  ///
  /// Much shorter than [regrowDelay] and independent of it. A fault that
  /// lingered as long as ordinary regrowth would never actually close ahead of
  /// her, which is the only thing it exists to do; one that snapped instantly
  /// would be a wall you paid a tap for. Two seconds is about one confident
  /// push across a short line of them.
  double faultDelay = 2.2;

  double heavyDensity = 0.18;

  /// How far the dog can see hex *types*, as a multiple of the tap radius.
  ///
  /// Must stay above 1: if it ever fell below the tap radius, the editable
  /// highlight would give anchors away by simply not lighting them, and the fog
  /// would leak the very thing it exists to hide.
  double revealFactor = 2.2;

  /// Tap budget as a multiple of par. Par is the cheapest possible route, so
  /// this is how much slack a run gets over perfect play.
  double budgetMultiplier = 1.25;

  /// Seconds of hunger the bar holds per cell of the ideal route, so the clock
  /// scales with the length of the journey rather than being a flat deadline
  /// that quietly punishes bigger levels.
  ///
  /// Cut from 1.2 after watching real runs finish in 13-21 seconds against a
  /// 24-26 second bar: the clock was never the thing that ended a run. At 1.05
  /// a long run comes down to the wire, which is the point of having one.
  ///
  /// Not lower: at 1.0 the bar clears the fastest possible run by only 12%,
  /// and the fairness gate in playthrough_test rejects it. A clock that can rob
  /// someone playing well is not pressure, it is a coin toss.
  double hungerSecondsPerCell = 1.05;

  /// What a treat pays back. The taps matter as much as the seconds: the fog
  /// guarantees some are spent finding walls, so a tight budget needs a way to
  /// earn them back or it is merely arbitrary.
  double treatSeconds = 5;
  double treatTaps = 2;

  double treatCount = 3;
  double powerupCount = 2;

  /// Sound level.
  double volume = 0.85;

  /// Whether the field's own noises — the regrowth warning and a hex closing —
  /// are audible.
  ///
  /// Off by default: they fire in waves exactly while the player is tapping
  /// fastest, and in play they trod all over the tap notes. Their **haptics
  /// still fire** regardless, so the warning is felt without being heard.
  bool regrowthSound = false;

  /// Screen shake and hit-stop strength. Zero removes both entirely — juice
  /// should always be something a player can turn off.
  double juiceScale = 1.0;

  /// Which systems this level runs. Set from [LevelRules] on every level start
  /// so the campaign can introduce them one at a time, and left editable so the
  /// debug panel can still switch any of them mid-level.
  bool regrowthEnabled = true;
  bool fogEnabled = true;
  bool budgetEnabled = true;
  bool hungerEnabled = true;

  /// Whether starting a level reloads its numbers from the campaign.
  ///
  /// On by default, so a level is what the curve says it is. Turn it off to keep
  /// slider values across regenerates — otherwise every tweak marked "next
  /// level" would be overwritten by the definition the moment it took effect.
  bool followCampaign = true;

  /// Zen mode (§12.3): same puzzle, no regrowth pressure.
  bool zenMode = false;

  /// Developer view of the carved route. Never available to players — showing
  /// the answer would remove the discovery loop the game is built on (§8).
  bool showTruePath = false;

  void set(void Function(TuningConfig c) change) {
    change(this);
    notifyListeners();
  }
}
