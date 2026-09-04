import 'dart:math' as math;

import '../entities/pickup.dart';
import '../gen/silhouette.dart';

/// Everything that makes one level what it is.
///
/// Mechanics used to be globals in `TuningConfig`, which is exactly why they all
/// arrived at once and buried a newcomer. Here each level says what is switched
/// on, so the campaign introduces one idea at a time (§7, §12.5).
class LevelRules {
  const LevelRules({
    required this.level,
    required this.seed,
    required this.columns,
    required this.rows,
    this.anchorDensity = 0,
    this.heavyDensity = 0,
    this.springDensity = 0,
    this.guards = 0,
    this.guardSpeed = 0.85,
    this.treats = 0,
    this.powerups = 0,
    this.offeredPowerups = const [PickupKind.freeze, PickupKind.radiusPlus],
    this.powerupRotation = 0,
    this.introduces,
    this.treatSeconds = 5,
    this.treatTaps = 2,
    this.regrowth = false,
    this.regrowDelay = 7,
    this.fog = false,
    this.budget = false,
    this.budgetMultiplier = 1.5,
    this.hunger = false,
    this.hungerSecondsPerCell = 1.3,
    this.teaches,
  });

  final int level;
  final int seed;

  final int columns;
  final int rows;

  final double anchorDensity;
  final double heavyDensity;

  /// Springs (§6.1), from [Campaign.springsFrom] onward.
  final double springDensity;

  /// Patrols (§6.1), from [Campaign.guardsFrom] onward, and how fast they walk.
  final int guards;
  final double guardSpeed;

  final int treats;
  final int powerups;

  /// Which powerups may drop here. Widens as the campaign climbs.
  final List<PickupKind> offeredPowerups;

  /// Where in that list this level starts, so consecutive levels do not all
  /// lead with the same powerup.
  final int powerupRotation;

  /// A one-line banner for the level a mechanic first appears on.
  ///
  /// The tutorial is five levels and gated, and it stays that way — but springs
  /// and patrols arrive long after it has ended, and a mechanic that turns up
  /// at level 21 with no introduction is indistinguishable from a bug. One
  /// sentence at the top of the board is the smallest honest answer.
  final String? introduces;

  /// What one treat pays back.
  ///
  /// These shrink as the campaign climbs, and that is the whole point. A flat
  /// treat value against a tightening budget gets proportionally *stronger*
  /// exactly where the game is meant to bite hardest: at the old level 60, four
  /// treats handed back eight taps and twenty seconds against a thirty-second
  /// clock, which is most of why it could be finished easily.
  final double treatSeconds;
  final int treatTaps;

  final bool regrowth;
  final double regrowDelay;

  final bool fog;

  final bool budget;
  final double budgetMultiplier;

  final bool hunger;
  final double hungerSecondsPerCell;

  /// The single idea this level exists to teach. Null past the tutorial.
  final String? teaches;

  /// The outline this board is cut to. Fixed by seed, so a level's shape is as
  /// much a part of it as its layout.
  FieldShape get shape =>
      shapeFor(level, seed, tutorialBand: Campaign.tutorialBand);

  bool get isEndless => level > Campaign.length;
  bool get isTutorial => level <= Campaign.tutorialBand;
}

/// The four stretches of the campaign, plus what lies past it.
///
/// The bands already existed as numbers the curve interpolated between; naming
/// them is what lets the map show the climb as four stretches with characters
/// rather than sixty numbered tiles in a row.
enum CampaignBand {
  tutorial('Learning'),
  foundation('Foundation'),
  pressure('Pressure'),
  mastery('Mastery'),
  endless('Endless');

  const CampaignBand(this.label);

  final String label;
}

/// The campaign: sixty levels across four bands, then endless.
///
/// Boards are generated, so a level is parameters plus a seed. Authoring sixty
/// by hand would be busywork — designing bands and letting the level number
/// interpolate inside each gives the same result for a fraction of the effort,
/// and extends past the end for free.
class Campaign {
  Campaign._();

  static const length = 60;

  /// Five guided levels, not twelve passive ones. Gating is what makes the
  /// difference: a player cannot skim past a lesson that will not proceed
  /// without them, so each level can carry more and still be understood.
  static const tutorialBand = 5;
  static const foundationEnd = 20;
  static const pressureEnd = 40;

  /// Springs land inside Foundation, once anchors and heavy hexes are familiar
  /// but before the clock gets tight — they are the one obstacle that gives
  /// something back, so meeting them while there is still slack is what lets a
  /// player learn to aim one rather than merely survive it.
  static const springsFrom = 9;

  /// Patrols open the Pressure band. They apply *timing*, which nothing before
  /// them does, so they get a band boundary to themselves rather than being
  /// mixed into a level that is also introducing tighter numbers.
  static const guardsFrom = 21;

  /// Enough springs on a board to be met rather than merely present.
  static const _springIntroDensity = 0.03;

  /// The powerup pool, widening. Early levels offer the two that need no
  /// explanation; each later band adds one that does.
  static const _foundationPowerups = [
    PickupKind.freeze,
    PickupKind.radiusPlus,
    PickupKind.sprint,
  ];
  static const _pressurePowerups = [
    ..._foundationPowerups,
    PickupKind.scent,
    PickupKind.blast,
  ];
  static const _masteryPowerups = [..._pressurePowerups, PickupKind.dig];

  /// The seed for a level, from its number, by an explicit mixer.
  ///
  /// Deliberately **not** `hashCode`, which Dart does not guarantee to be stable
  /// across runs or releases. If this drifted, level 37 would quietly become a
  /// different board in a later build and every saved best score would be a lie
  /// about a level that no longer exists. A fixed mixer is what lets a generated
  /// board be a *place* — the same for everyone, forever.
  ///
  /// The murmur3 finaliser, masked to 32 bits at every step so the arithmetic
  /// cannot differ between platforms.
  static int seedFor(int level) {
    var x = (level * 0x9E3779B1) & 0xFFFFFFFF;
    x ^= x >> 16;
    x = (x * 0x85EBCA6B) & 0xFFFFFFFF;
    x ^= x >> 13;
    x = (x * 0xC2B2AE35) & 0xFFFFFFFF;
    x ^= x >> 16;
    return x & 0x7FFFFFFF;
  }

  static CampaignBand bandOf(int level) {
    if (level <= tutorialBand) {
      return CampaignBand.tutorial;
    }
    if (level <= foundationEnd) {
      return CampaignBand.foundation;
    }
    if (level <= pressureEnd) {
      return CampaignBand.pressure;
    }
    if (level <= length) {
      return CampaignBand.mastery;
    }
    return CampaignBand.endless;
  }

  /// The first level of each band, for the map's section headings.
  static int firstOf(CampaignBand band) => switch (band) {
    CampaignBand.tutorial => 1,
    CampaignBand.foundation => tutorialBand + 1,
    CampaignBand.pressure => foundationEnd + 1,
    CampaignBand.mastery => pressureEnd + 1,
    CampaignBand.endless => length + 1,
  };

  static LevelRules rulesFor(int level) {
    final n = math.max(1, level);
    if (n <= tutorialBand) {
      return _tutorial(n);
    }
    if (n <= foundationEnd) {
      return _band(
        n,
        foundationEnd - tutorialBand,
        n - tutorialBand - 1,
        _foundation,
      );
    }
    if (n <= pressureEnd) {
      return _band(
        n,
        pressureEnd - foundationEnd,
        n - foundationEnd - 1,
        _pressure,
      );
    }
    if (n <= length) {
      return _band(n, length - pressureEnd, n - pressureEnd - 1, _mastery);
    }
    return _endless(n);
  }

  // -------------------------------------------------------------------------
  // Five guided levels. Small boards, so a lesson is over in half a minute.
  // -------------------------------------------------------------------------

  static LevelRules _tutorial(int n) {
    final seed = seedFor(n);
    return switch (n) {
      1 => LevelRules(
        level: 1,
        seed: seed,
        columns: 7,
        rows: 11,
        teaches: 'Tap a tile — she walks into whatever opens',
      ),
      2 => LevelRules(
        level: 2,
        seed: seed,
        columns: 8,
        rows: 13,
        regrowth: true,
        regrowDelay: 8.5,
        teaches: 'Tiles grow back. Keep carving',
      ),
      3 => LevelRules(
        level: 3,
        seed: seed,
        columns: 9,
        rows: 15,
        anchorDensity: 0.14,
        heavyDensity: 0.12,
        regrowth: true,
        regrowDelay: 8,
        teaches: 'Riveted tiles never clear. Ringed ones take two taps',
      ),
      4 => LevelRules(
        level: 4,
        seed: seed,
        columns: 10,
        rows: 17,
        anchorDensity: 0.16,
        heavyDensity: 0.12,
        treats: 2,
        powerups: 2,
        regrowth: true,
        regrowDelay: 7.5,
        budget: true,
        // Loose on purpose, and looser than it looks. A tutorial level has to
        // be passable by the *worst* player who has understood the lesson, and
        // level four's lesson is "taps are finite" — which is delivered by the
        // counter going down, not by losing. The simulated floor player failed
        // this level at 26 taps of 27; a first-timer meeting a budget for the
        // first time is not going to do better.
        budgetMultiplier: 2.4,
        // Treats arrive with the budget and not before: they pay back taps, so
        // in a level with neither budget nor clock they do nothing at all, and a
        // pickup that visibly does nothing teaches players to ignore pickups.
        teaches: 'Taps are limited. Treats and powerups sit off your route',
      ),
      _ => LevelRules(
        level: 5,
        seed: seed,
        columns: 10,
        rows: 19,
        anchorDensity: 0.16,
        heavyDensity: 0.14,
        treats: 3,
        powerups: 2,
        regrowth: true,
        regrowDelay: 7,
        fog: true,
        budget: true,
        // Same reasoning, and this one is carrying fog and the clock as well.
        // It previously passed with exactly nothing to spare.
        budgetMultiplier: 2.2,
        hunger: true,
        hungerSecondsPerCell: 1.7,
        teaches: 'You see only what she is near — and she tires',
      ),
    };
  }

  // -------------------------------------------------------------------------
  // The rest, as band endpoints the level number interpolates between.
  // -------------------------------------------------------------------------

  /// Every value moves monotonically toward harder, and each band picks up where
  /// the last left off — a band starting easier than the one before it would
  /// read as the game going backwards.
  ///
  /// Steeper at the top than the first cut of this curve, which could be
  /// finished comfortably at level 60.
  static const _foundation = (
    columns: (10, 11),
    rows: (19, 23),
    anchor: (0.16, 0.24),
    heavy: (0.14, 0.18),
    spring: (0.0, 0.06),
    guards: (0, 0),
    guardSpeed: (0.85, 0.85),
    treats: (3, 3),
    powerups: (2, 2),
    treatSeconds: (5.0, 4.5),
    treatTaps: (2, 2),
    regrow: (7.0, 6.0),
    budget: (1.70, 1.38),
    hunger: (1.60, 1.28),
  );

  static const _pressure = (
    columns: (11, 12),
    rows: (23, 25),
    anchor: (0.24, 0.32),
    heavy: (0.18, 0.24),
    spring: (0.06, 0.08),
    guards: (1, 2),
    guardSpeed: (0.85, 0.95),
    treats: (3, 4),
    powerups: (2, 3),
    treatSeconds: (4.5, 3.0),
    treatTaps: (2, 1),
    regrow: (6.0, 4.8),
    budget: (1.38, 1.18),
    hunger: (1.28, 1.02),
  );

  static const _mastery = (
    columns: (12, 12),
    rows: (25, 27),
    anchor: (0.32, 0.38),
    heavy: (0.24, 0.30),
    spring: (0.08, 0.10),
    guards: (2, 3),
    guardSpeed: (0.95, 1.10),
    treats: (4, 4),
    powerups: (3, 3),
    treatSeconds: (3.0, 2.0),
    treatTaps: (1, 1),
    regrow: (4.8, 3.8),
    budget: (1.18, 1.06),
    hunger: (1.02, 0.85),
  );

  static LevelRules _band(
    int level,
    int span,
    int index,
    ({
      (int, int) columns,
      (int, int) rows,
      (double, double) anchor,
      (double, double) heavy,
      (double, double) spring,
      (int, int) guards,
      (double, double) guardSpeed,
      (int, int) treats,
      (int, int) powerups,
      (double, double) treatSeconds,
      (int, int) treatTaps,
      (double, double) regrow,
      (double, double) budget,
      (double, double) hunger,
    })
    band,
  ) {
    final t = span <= 1 ? 0.0 : index / (span - 1);
    return LevelRules(
      level: level,
      seed: seedFor(level),
      columns: _lerpInt(band.columns, t),
      rows: _lerpInt(band.rows, t),
      anchorDensity: _lerp(band.anchor, t),
      heavyDensity: _lerp(band.heavy, t),
      // Floored, not merely interpolated. The band's own curve starts at zero,
      // so the level that *announces* springs would generate one on a
      // 143-cell board — a banner promising a mechanic the player then never
      // meets. An introduction has to be dense enough to actually happen.
      springDensity: level >= springsFrom
          ? math.max(_springIntroDensity, _lerp(band.spring, t))
          : 0,
      guards: level >= guardsFrom ? _lerpInt(band.guards, t) : 0,
      guardSpeed: _lerp(band.guardSpeed, t),
      treats: _lerpInt(band.treats, t),
      powerups: _lerpInt(band.powerups, t),
      offeredPowerups: poolFor(level),
      powerupRotation: level,
      introduces: introductionAt(level),
      treatSeconds: _lerp(band.treatSeconds, t),
      treatTaps: _lerpInt(band.treatTaps, t),
      regrowth: true,
      regrowDelay: _lerp(band.regrow, t),
      fog: true,
      budget: true,
      budgetMultiplier: _lerp(band.budget, t),
      hunger: true,
      hungerSecondsPerCell: _lerp(band.hunger, t),
    );
  }

  /// Past sixty, Mastery's slope keeps going — but every value has a floor.
  ///
  /// An unbounded ramp reaches a point no play can survive, and an endless mode
  /// that becomes arithmetically impossible is not difficulty, it is a wall with
  /// a number on it. These floors sit just beyond the hardest campaign level, so
  /// the climb is still felt without becoming a lie.
  static LevelRules _endless(int level) {
    final beyond = level - length;
    final t = 1 - math.pow(0.97, beyond).toDouble();
    return LevelRules(
      level: level,
      seed: seedFor(level),
      columns: 12,
      rows: math.min(29, 27 + (beyond ~/ 12)),
      anchorDensity: 0.38 + 0.03 * t,
      heavyDensity: 0.30 + 0.03 * t,
      springDensity: 0.10,
      guards: 3,
      guardSpeed: math.min(1.25, 1.10 + 0.15 * t),
      treats: 4,
      powerups: 3,
      offeredPowerups: _masteryPowerups,
      powerupRotation: level,
      treatSeconds: 2,
      treatTaps: 1,
      regrowth: true,
      regrowDelay: math.max(3.2, 3.8 - 0.6 * t),
      fog: true,
      budget: true,
      budgetMultiplier: math.max(1.03, 1.06 - 0.03 * t),
      hunger: true,
      hungerSecondsPerCell: math.max(0.78, 0.85 - 0.07 * t),
    );
  }

  /// Which powerups a level may drop.
  static List<PickupKind> poolFor(int level) {
    if (level <= foundationEnd) {
      return _foundationPowerups;
    }
    if (level <= pressureEnd) {
      return _pressurePowerups;
    }
    return _masteryPowerups;
  }

  /// The banner for a level, or null on the great majority that introduce
  /// nothing.
  static String? introductionAt(int level) => switch (level) {
    springsFrom => 'Springs throw her the way she was already walking',
    guardsFrom => 'Patrols sweep the field. She will not walk into the light',
    _ => null,
  };

  static double _lerp((double, double) range, double t) =>
      range.$1 + (range.$2 - range.$1) * t;

  static int _lerpInt((int, int) range, double t) =>
      (range.$1 + (range.$2 - range.$1) * t).round();
}
