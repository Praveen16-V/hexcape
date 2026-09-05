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
    this.faultDensity = 0,
    this.guards = 0,
    this.sentries = 0,
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
    this.pace = LevelPace.learning,
  });

  final int level;
  final int seed;

  final int columns;
  final int rows;

  final double anchorDensity;
  final double heavyDensity;

  /// Springs (§6.1), from [Campaign.springsFrom] onward.
  final double springDensity;

  /// Cracked ground, from [Campaign.faultsFrom] onward. Zero until then, so
  /// every level that shipped before faults existed is untouched.
  final double faultDensity;

  /// Patrols (§6.1), from [Campaign.guardsFrom] onward, and how fast they walk.
  final int guards;
  final double guardSpeed;

  /// Warded lights, from [Campaign.sentriesFrom] onward.
  final int sentries;

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

  /// The role this level plays in the campaign's difficulty rhythm.
  final LevelPace pace;

  /// Its authored name and dominant gameplay idea. Generation still supplies
  /// the exact board, but this is what makes the level recognizable before and
  /// after the seed has done its work.
  LevelIdentity get identity => Campaign.identityFor(level);

  /// The outline this board is cut to. Fixed by seed, so a level's shape is as
  /// much a part of it as its layout.
  FieldShape get shape =>
      shapeFor(level, seed, tutorialBand: Campaign.tutorialBand);

  bool get isEndless => level > Campaign.length;
  bool get isTutorial => level <= Campaign.tutorialBand;
}

/// A level's job in the difficulty curve. The campaign climbs through harder
/// bands, but within each band these beats create room to learn and recover.
enum LevelPace {
  learning('Learning', 'A guided lesson with room to experiment.'),
  introduction('New idea', 'Meet one new hazard with extra time and taps.'),
  practice('Practice', 'Use the latest ideas with forgiving pressure.'),
  combination('Mixed', 'Several familiar pressures work together.'),
  challenge('Challenge', 'The band\'s full pressure, with little wasted room.'),
  breather('Breather', 'A lighter run before the climb resumes.'),
  endless('Endless', 'Pressure rises gradually with no final level.');

  const LevelPace(this.label, this.description);

  final String label;
  final String description;
}

/// A recurring gameplay shape with a clear promise to the player.
enum LevelSignature {
  lesson('Guided lesson', 'One rule is introduced with room to learn it.'),
  openTrail('Open trail', 'Sparse walls reward decisive, wide carving.'),
  closingTrail(
    'Closing trail',
    'Regrowth is the main pressure; Freeze buys breathing room.',
  ),
  heavyGround(
    'Heavy ground',
    'More two-hit tiles make every choice of route matter.',
  ),
  springLine(
    'Spring line',
    'Springs dominate the route; carve where their momentum will land.',
  ),
  nightWatch(
    'Night watch',
    'Patrol lanes make timing and Scent more valuable.',
  ),
  supplyRun('Supply run', 'Extra rewards invite a profitable side route.'),
  breach('Breach', 'Riveted walls dominate; a Dig can rewrite the route.'),
  faultLine(
    'Fault line',
    'Cracked ground dominates; carve late and keep moving.',
  ),
  warded('Warded', 'Sentry light refuses your taps; time the window.'),
  gauntlet('Gauntlet', 'Every unlocked pressure is active at full strength.');

  const LevelSignature(this.label, this.description);

  final String label;
  final String description;
}

class LevelIdentity {
  const LevelIdentity({required this.title, required this.signature});

  final String title;
  final LevelSignature signature;
}

/// The stretches of the campaign, plus what lies past it.
///
/// The bands already existed as numbers the curve interpolated between; naming
/// them is what lets the map show the climb as four stretches with characters
/// rather than a long column of numbered tiles.
enum CampaignBand {
  tutorial('Learning'),
  foundation('Foundation'),
  pressure('Pressure'),
  mastery('Mastery'),
  collapse('Collapse'),
  vigil('Vigil'),
  endless('Endless');

  const CampaignBand(this.label);

  final String label;
}

/// The campaign: a hundred levels across six bands, then endless.
///
/// Boards are generated, so a level is parameters plus a seed. Authoring a
/// hundred by hand would be busywork — designing bands and letting the level number
/// interpolate inside each gives the same result for a fraction of the effort,
/// and extends past the end for free.
class Campaign {
  Campaign._();

  static const length = 100;

  /// Five guided levels, not twelve passive ones. Gating is what makes the
  /// difference: a player cannot skim past a lesson that will not proceed
  /// without them, so each level can carry more and still be understood.
  static const tutorialBand = 5;
  static const foundationEnd = 20;
  static const pressureEnd = 40;

  /// The last level of the Mastery band.
  ///
  /// Distinct from [length], and that distinction is the whole point. These
  /// were the same number while Mastery was the final band, so `rulesFor`
  /// interpolated it as `length - pressureEnd` — which silently turns Mastery
  /// into a band of every remaining level the moment the campaign grows past
  /// it. A band has to know where it ends independently of where the campaign
  /// does.
  static const masteryEnd = 60;

  /// The last level of the Collapse band.
  static const collapseEnd = 80;

  /// Warded lights open the Vigil band. They apply pressure to the *tap* rather
  /// than to the route or the clock, which nothing before them does, so like
  /// patrols they get a band boundary to themselves.
  static const sentriesFrom = 81;

  /// HEEL, two levels later — the same meet-it-then-answer-it beat that STAKE
  /// follows cracked ground with.
  static const heelFrom = 83;

  /// Springs land inside Foundation, once anchors and heavy hexes are familiar
  /// but before the clock gets tight — they are the one obstacle that gives
  /// something back, so meeting them while there is still slack is what lets a
  /// player learn to aim one rather than merely survive it.
  static const springsFrom = 9;

  /// Cracked ground opens the Collapse band.
  ///
  /// Set before the band exists, and deliberately: the mechanic ships first,
  /// behind a density of zero, so it can be built and played from the debug
  /// panel without any level referencing it. Until the campaign reaches here
  /// this reads as "never", which is exactly right.
  static const faultsFrom = 61;

  /// STAKE, two levels after the pressure it answers.
  ///
  /// Meet the crack, practise it, *then* be handed the tool that pins ground
  /// open. Arriving with the mechanic would let a player neutralise it before
  /// they had understood what it does to them.
  static const stakeFrom = 63;

  /// Patrols open the Pressure band. They apply *timing*, which nothing before
  /// them does, so they get a band boundary to themselves rather than being
  /// mixed into a level that is also introducing tighter numbers.
  static const guardsFrom = 21;

  /// Enough springs on a board to be met rather than merely present.
  static const _springIntroDensity = 0.03;

  /// Enough cracked ground on a board to be met rather than merely present.
  ///
  /// Higher than [_springIntroDensity] because faults are placed in *lines* of
  /// two to four rather than as single cells: at the spring's floor the
  /// introduction generated one crack of three on a 140-cell board, which a
  /// player can walk an entire level without touching. This is about two or
  /// three separate lines, so the banner describes something they will meet.
  static const _faultIntroDensity = 0.08;

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
  static const _collapsePowerups = [..._masteryPowerups, PickupKind.stake];
  static const _vigilPowerups = [..._collapsePowerups, PickupKind.heel];

  /// Authored names turn stable generated boards into places a player can
  /// remember and discuss. Their mechanics still come from the signatures
  /// below, so the name is backed by a different play pattern rather than
  /// being decorative copy.
  static const _titles = [
    'First Footsteps',
    'Closing Ground',
    'Rivets and Rings',
    'The Long Way',
    'Into the Fog',
    'Open Trail',
    'Narrow Promise',
    'Stone Teeth',
    'First Spring',
    'Follow Through',
    'Hard Shell',
    'The Pinch',
    'Breathing Room',
    'Spring Arc',
    'Tipping Point',
    'Supply Pocket',
    'Backfill',
    'Fault Line',
    'Loose Earth',
    'Foundation Edge',
    'First Patrol',
    'Shadow Step',
    'Closing Lane',
    'Searchlights',
    'Safe Pocket',
    'Double Weight',
    'Noon Watch',
    'Supply Gap',
    'Long Throw',
    'Crossing Lines',
    'Open Window',
    'Night Route',
    'Crossfire',
    'Hidden Cache',
    'Backtrack',
    'No Safe Line',
    'Second Wind',
    'Iron Floor',
    'Last Light',
    'Pressure Edge',
    'The First Breach',
    'Broken Wall',
    'Iron Garden',
    'Deep Cache',
    'Collapse',
    'Hot Trail',
    'Clear Ground',
    'Spring Trap',
    'Rivet Clock',
    'Found Time',
    'Dark Crossing',
    'Triple Watch',
    'Spare Breath',
    'Second Breach',
    'Black Ice',
    'Last Cache',
    'Heavy Silence',
    'Closing Net',
    'Calm Before',
    'Final Hex',
    // Collapse (61-80). Named for ground that does not stay where you put it.
    'First Crack',
    'Give Way',
    'Held Ground',
    'Standing Stone',
    'Cracked Run',
    'Thin Floor',
    'The Drop',
    'Quick Ground',
    'Undermine',
    'Rift',
    'Set in Stone',
    'Sinking Trail',
    'Long Fall',
    'Fixed Point',
    'Shatterline',
    'Slow Collapse',
    'Deep Crack',
    'Last Footing',
    'Bedrock',
    'Everything Gives',
    // Vigil (81-100). Named for waiting, watching, and the space between
    // sweeps.
    'First Sentry',
    'Warded Light',
    'Blind Spot',
    'Hold Still',
    'Sweep',
    'Cold Eye',
    'The Wait',
    'Between Passes',
    'Night Shift',
    'Lamp Line',
    'Counted Steps',
    'Still Water',
    'Watchtower',
    'Shuttered',
    'Two Lights',
    'Dead Air',
    'Last Sweep',
    'Long Watch',
    'Quiet Hour',
    'Final Vigil',
  ];

  static const _openTrailLevels = {6, 13, 19, 25, 31, 37, 47, 53, 59};
  static const _closingTrailLevels = {7, 17, 23, 35, 45};
  static const _heavyGroundLevels = {11, 26, 38, 57};
  static const _springLineLevels = {9, 10, 14, 29, 48};
  static const _nightWatchLevels = {21, 22, 32, 51};
  static const _supplyRunLevels = {16, 28, 34, 44, 50, 56};
  static const _breachLevels = {41, 42, 54};

  /// Collapse's own signature. Every entry is deliberately a non-challenge
  /// level: [LevelSignature.faultLine] carries no anchor or heavy delta, but
  /// keeping the rule visible here is what stops the next one from breaking it.
  static const _faultLineLevels = {61, 62, 65, 68, 71, 74, 77};

  /// Vigil's own, and every entry is a non-challenge level for the same reason
  /// the others are: a signature that adds walls must never land on a challenge
  /// peak, or the next peak drops below it and monotonicity fails.
  static const _wardedLevels = {81, 82, 85, 88, 91, 94, 97};

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
    if (level <= masteryEnd) {
      return CampaignBand.mastery;
    }
    if (level <= collapseEnd) {
      return CampaignBand.collapse;
    }
    if (level <= length) {
      return CampaignBand.vigil;
    }
    return CampaignBand.endless;
  }

  static LevelIdentity identityFor(int level) {
    final n = math.max(1, level);
    if (n > length) {
      return LevelIdentity(
        title: 'Depth ${n - length}',
        signature: LevelSignature.gauntlet,
      );
    }
    return LevelIdentity(title: _titles[n - 1], signature: signatureFor(n));
  }

  static LevelSignature signatureFor(int level) {
    if (level <= tutorialBand) return LevelSignature.lesson;
    if (_openTrailLevels.contains(level)) return LevelSignature.openTrail;
    if (_closingTrailLevels.contains(level)) {
      return LevelSignature.closingTrail;
    }
    if (_heavyGroundLevels.contains(level)) return LevelSignature.heavyGround;
    if (_springLineLevels.contains(level)) return LevelSignature.springLine;
    if (_nightWatchLevels.contains(level)) return LevelSignature.nightWatch;
    if (_supplyRunLevels.contains(level)) return LevelSignature.supplyRun;
    if (_breachLevels.contains(level)) return LevelSignature.breach;
    if (_faultLineLevels.contains(level)) return LevelSignature.faultLine;
    if (_wardedLevels.contains(level)) return LevelSignature.warded;
    return LevelSignature.gauntlet;
  }

  /// The first level of each band, for the map's section headings.
  static int firstOf(CampaignBand band) => switch (band) {
    CampaignBand.tutorial => 1,
    CampaignBand.foundation => tutorialBand + 1,
    CampaignBand.pressure => foundationEnd + 1,
    CampaignBand.mastery => pressureEnd + 1,
    CampaignBand.collapse => masteryEnd + 1,
    CampaignBand.vigil => collapseEnd + 1,
    CampaignBand.endless => length + 1,
  };

  /// The rules for a level, optionally on a different board.
  ///
  /// [seed] overrides the one this level would normally derive, and is how the
  /// daily challenge borrows a level's *shape of difficulty* without borrowing
  /// its board. Deliberately an override on this function rather than a
  /// `copyWith` on [LevelRules]: a copy of twenty-five fields silently drops
  /// whichever one is added next, and the failure would be a daily board that
  /// quietly stopped matching the level it claims to be built from.
  static LevelRules rulesFor(int level, {int? seed}) {
    final n = math.max(1, level);
    if (n <= tutorialBand) {
      return _tutorial(n, seed: seed);
    }
    if (n <= foundationEnd) {
      return _band(
        n,
        foundationEnd - tutorialBand,
        n - tutorialBand - 1,
        _foundation,
        seed: seed,
      );
    }
    if (n <= pressureEnd) {
      return _band(
        n,
        pressureEnd - foundationEnd,
        n - foundationEnd - 1,
        _pressure,
        seed: seed,
      );
    }
    if (n <= masteryEnd) {
      return _band(
        n,
        masteryEnd - pressureEnd,
        n - pressureEnd - 1,
        _mastery,
        seed: seed,
      );
    }
    if (n <= collapseEnd) {
      return _band(
        n,
        collapseEnd - masteryEnd,
        n - masteryEnd - 1,
        _collapse,
        seed: seed,
      );
    }
    if (n <= length) {
      return _band(
        n,
        length - collapseEnd,
        n - collapseEnd - 1,
        _vigil,
        seed: seed,
      );
    }
    return _endless(n, seed: seed);
  }

  // -------------------------------------------------------------------------
  // Five guided levels. Small boards, so a lesson is over in half a minute.
  // -------------------------------------------------------------------------

  static LevelRules _tutorial(int n, {int? seed}) {
    seed ??= seedFor(n);
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

  /// These are the challenge ceilings. Each band picks up where the last one
  /// ended, while [LevelPace] selectively relieves pressure between peaks.
  /// The result still climbs toward the harder endpoint without asking every
  /// consecutive level to be harsher than the last.
  static const _foundation = (
    columns: (10, 11),
    rows: (19, 23),
    anchor: (0.16, 0.24),
    heavy: (0.14, 0.18),
    spring: (0.0, 0.06),
    fault: (0.0, 0.0),
    guards: (0, 0),
    guardSpeed: (0.85, 0.85),
    sentries: (0, 0),
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
    fault: (0.0, 0.0),
    guards: (1, 2),
    guardSpeed: (0.85, 0.95),
    sentries: (0, 0),
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
    fault: (0.0, 0.0),
    guards: (2, 3),
    guardSpeed: (0.95, 1.10),
    sentries: (0, 0),
    treats: (4, 4),
    powerups: (3, 3),
    treatSeconds: (3.0, 2.0),
    treatTaps: (1, 1),
    regrow: (4.8, 3.8),
    budget: (1.18, 1.06),
    hunger: (1.02, 0.85),
  );

  /// Collapse (61-80). Cracked ground.
  ///
  /// **Budget, hunger and regrowth are pinned flat at Mastery's floor**, and
  /// that is the design rather than an oversight. Those three axes were within
  /// a hair of their limits by level 60 — the budget cannot fall below about
  /// 1.06 without demanding provably optimal play, which `campaign_sweep_test`
  /// rightly forbids. Squeezing another twenty levels out of them would produce
  /// a gradient nobody can feel and a fairness gate nobody can pass.
  ///
  /// So the whole felt climb of this band rides on [LevelRules.faultDensity],
  /// which starts at zero and has exactly as much room as springs and patrols
  /// had. Anchors and heavies creep by 0.02 across the band purely to satisfy
  /// the non-decreasing wall assertions; that much is deliberately imperceptible.
  static const _collapse = (
    columns: (12, 12),
    rows: (27, 27),
    anchor: (0.38, 0.40),
    heavy: (0.30, 0.31),
    spring: (0.10, 0.10),
    // Read against the *remaining plain* cells, not the whole board — anchors,
    // heavies and springs have already taken theirs by the time faults are
    // placed, so these numbers buy roughly half what their face value suggests.
    // At (0.03, 0.09) the band averaged two cracks a board, which is not a
    // gradient, and this band has no other one.
    fault: (0.06, 0.18),
    guards: (3, 3),
    guardSpeed: (1.10, 1.10),
    sentries: (0, 0),
    treats: (4, 4),
    powerups: (3, 3),
    // Still shrinking, and it has to. The clock is flat across this band, so a
    // flat treat value would make treats proportionally *stronger* exactly
    // where the game is meant to bite hardest — the mistake `tutorial_test`
    // was written to catch, and which it caught here.
    treatSeconds: (2.0, 1.6),
    treatTaps: (1, 1),
    regrow: (3.8, 3.8),
    budget: (1.06, 1.06),
    hunger: (0.85, 0.85),
  );

  /// Vigil (81-100). Warded lights.
  ///
  /// Same shape as Collapse and for the same reason: the four numeric axes stay
  /// pinned at their floors, faults keep climbing, and the band's own new
  /// pressure — sentries — starts at zero with room to grow. Difficulty here is
  /// a question of *when* you may act rather than how much you may spend.
  static const _vigil = (
    columns: (12, 12),
    rows: (27, 29),
    anchor: (0.40, 0.42),
    heavy: (0.31, 0.32),
    spring: (0.10, 0.10),
    fault: (0.18, 0.22),
    guards: (3, 3),
    guardSpeed: (1.10, 1.15),
    sentries: (1, 2),
    treats: (4, 4),
    powerups: (3, 3),
    treatSeconds: (1.6, 1.3),
    treatTaps: (1, 1),
    regrow: (3.8, 3.8),
    budget: (1.06, 1.06),
    hunger: (0.85, 0.85),
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
      (double, double) fault,
      (int, int) guards,
      (int, int) sentries,
      (double, double) guardSpeed,
      (int, int) treats,
      (int, int) powerups,
      (double, double) treatSeconds,
      (int, int) treatTaps,
      (double, double) regrow,
      (double, double) budget,
      (double, double) hunger,
    })
    band, {
    int? seed,
  }) {
    final t = span <= 1 ? 0.0 : index / (span - 1);
    final pace = paceFor(level);
    final signature = signatureFor(level);
    final baseAnchor = _lerp(band.anchor, t);
    final baseHeavy = _lerp(band.heavy, t);
    final baseSpring = _lerp(band.spring, t);
    final baseFault = _lerp(band.fault, t);
    final baseGuards = _lerpInt(band.guards, t);
    final baseGuardSpeed = _lerp(band.guardSpeed, t);
    final baseRegrow = _lerp(band.regrow, t);
    final baseBudget = _lerp(band.budget, t);
    final baseHunger = _lerp(band.hunger, t);
    return LevelRules(
      level: level,
      seed: seed ?? seedFor(level),
      columns: _lerpInt(band.columns, t),
      rows: _lerpInt(band.rows, t),
      anchorDensity: math.max(
        0,
        baseAnchor - pace.anchorRelief + signature.anchorDelta,
      ),
      heavyDensity: math.max(
        0,
        baseHeavy - pace.heavyRelief + signature.heavyDelta,
      ),
      // Floored, not merely interpolated. The band's own curve starts at zero,
      // so the level that *announces* springs would generate one on a
      // 143-cell board — a banner promising a mechanic the player then never
      // meets. An introduction has to be dense enough to actually happen.
      springDensity: level >= springsFrom
          ? math.max(
              _springIntroDensity,
              baseSpring * pace.obstacleMultiplier * signature.springMultiplier,
            )
          : 0,
      // Floored on the introduction level for the same reason springs are: a
      // banner promising cracked ground on a board that generates none is a
      // promise the level does not keep.
      faultDensity: level >= faultsFrom
          ? math.max(
              _faultIntroDensity,
              baseFault * pace.obstacleMultiplier * signature.faultMultiplier,
            )
          : 0,
      guards: level >= guardsFrom
          ? math.max(
              1,
              baseGuards -
                  pace.guardRelief +
                  (pace == LevelPace.combination ? signature.guardBonus : 0),
            )
          : 0,
      guardSpeed: math.max(0.75, baseGuardSpeed - pace.guardSpeedRelief),
      sentries: level >= sentriesFrom
          ? math.max(
              1,
              _lerpInt(band.sentries, t) +
                  (pace == LevelPace.combination ? signature.sentryBonus : 0) -
                  pace.guardRelief,
            )
          : 0,
      treats: _lerpInt(band.treats, t) + signature.extraTreats,
      powerups: _lerpInt(band.powerups, t) + signature.extraPowerups,
      offeredPowerups: _powerupsFor(signature, level),
      powerupRotation: level,
      introduces: introductionAt(level),
      treatSeconds: _lerp(band.treatSeconds, t),
      treatTaps: _lerpInt(band.treatTaps, t),
      regrowth: true,
      regrowDelay: math.max(
        3.2,
        baseRegrow + pace.regrowRelief + signature.regrowDelta,
      ),
      fog: true,
      budget: true,
      budgetMultiplier: baseBudget + pace.budgetRelief,
      hunger: true,
      hungerSecondsPerCell: baseHunger + pace.hungerRelief,
      pace: pace,
    );
  }

  /// Authored beats around the three mechanic introductions and the three band
  /// finales. The repeated mixed/challenge/breather cadence keeps later levels
  /// readable without turning the campaign into a flat sawtooth.
  static LevelPace paceFor(int level) {
    if (level <= tutorialBand) return LevelPace.learning;
    if (level > length) return LevelPace.endless;
    if (level == springsFrom ||
        level == guardsFrom ||
        level == 41 ||
        level == faultsFrom ||
        level == stakeFrom ||
        level == sentriesFrom ||
        level == heelFrom) {
      return LevelPace.introduction;
    }
    if (level == 6 ||
        level == springsFrom + 1 ||
        level == guardsFrom + 1 ||
        level == 42 ||
        level == faultsFrom + 1 ||
        level == stakeFrom + 1 ||
        level == sentriesFrom + 1 ||
        level == heelFrom + 1) {
      return LevelPace.practice;
    }
    if (level == foundationEnd ||
        level == pressureEnd ||
        level == masteryEnd ||
        level == collapseEnd ||
        level == length) {
      return LevelPace.challenge;
    }
    const breathers = {
      13, 16, 19, 25, 28, 31, 34, 37, 44, 47, 50, 53, 56, 59, //
      67, 70, 73, 76, 79, //
      87, 90, 93, 96, 99,
    };
    if (breathers.contains(level)) return LevelPace.breather;
    const challenges = {
      8,
      12,
      15,
      18,
      24,
      27,
      30,
      33,
      36,
      39,
      43,
      46,
      49,
      52,
      55,
      58,
      66,
      69,
      72,
      75,
      78,
      86,
      89,
      92,
      95,
      98,
    };
    if (challenges.contains(level)) return LevelPace.challenge;
    return LevelPace.combination;
  }

  /// Past the campaign, Collapse's slope keeps going — but every value has a
  /// floor.
  ///
  /// An unbounded ramp reaches a point no play can survive, and an endless mode
  /// that becomes arithmetically impossible is not difficulty, it is a wall with
  /// a number on it. These floors sit just beyond the hardest campaign level, so
  /// the climb is still felt without becoming a lie.
  static LevelRules _endless(int level, {int? seed}) {
    final beyond = level - length;
    final t = 1 - math.pow(0.97, beyond).toDouble();
    return LevelRules(
      level: level,
      seed: seed ?? seedFor(level),
      columns: 12,
      rows: math.min(29, 27 + (beyond ~/ 12)),
      // Capped rather than merely approached. `t` tends to 1 without reaching
      // it, so these land a rounding error above their ceiling instead of on
      // it — and the ceiling is a real limit, not a decoration.
      anchorDensity: math.min(0.44, 0.42 + 0.02 * t),
      heavyDensity: math.min(0.34, 0.32 + 0.02 * t),
      springDensity: 0.10,
      faultDensity: math.min(0.25, 0.22 + 0.03 * t),
      sentries: 2,
      guards: 3,
      guardSpeed: math.min(1.25, 1.10 + 0.15 * t),
      treats: 4,
      powerups: 3,
      offeredPowerups: _masteryPowerups,
      powerupRotation: level,
      treatSeconds: 1.3,
      treatTaps: 1,
      regrowth: true,
      regrowDelay: math.max(3.2, 3.8 - 0.6 * t),
      fog: true,
      budget: true,
      budgetMultiplier: math.max(1.03, 1.06 - 0.03 * t),
      hunger: true,
      hungerSecondsPerCell: math.max(0.78, 0.85 - 0.07 * t),
      pace: LevelPace.endless,
    );
  }

  /// Which powerups a level may drop.
  /// Keyed on the level rather than the band, because STAKE arrives two levels
  /// into Collapse rather than with it — a band-keyed pool would offer it on 61
  /// and 62, before the level that introduces it.
  static List<PickupKind> poolFor(int level) {
    if (level <= foundationEnd) {
      return _foundationPowerups;
    }
    if (level <= pressureEnd) {
      return _pressurePowerups;
    }
    if (level < stakeFrom) {
      return _masteryPowerups;
    }
    if (level < heelFrom) {
      return _collapsePowerups;
    }
    return _vigilPowerups;
  }

  /// The banner for a level, or null on the great majority that introduce
  /// nothing.
  static String? introductionAt(int level) => switch (level) {
    springsFrom => 'Springs throw her the way she was already walking',
    guardsFrom => 'Patrols sweep the field. She will not walk into the light',
    faultsFrom => 'Cracked tiles close on their own. Carve late, keep moving',
    stakeFrom => 'STAKE pins one open tile open for good. Arm it from the HUD',
    sentriesFrom =>
      'Warded lights refuse your taps. Wait for the sweep to pass',
    heelFrom => 'HEEL holds her still for a moment. Arm it from the HUD',
    41 => 'DIG breaks one riveted tile. Arm it from the HUD',
    _ => null,
  };

  static List<PickupKind> _powerupsFor(LevelSignature signature, int level) {
    final pool = poolFor(level);
    final preferred = switch (signature) {
      LevelSignature.openTrail => const [
        PickupKind.sprint,
        PickupKind.radiusPlus,
      ],
      LevelSignature.closingTrail => const [
        PickupKind.freeze,
        PickupKind.radiusPlus,
      ],
      // Sprint first, and that is the point of the whole type: a crack is only
      // a short cut if you can cross it before it shuts, which finally gives
      // the campaign's weakest powerup a board it is the right answer to.
      LevelSignature.faultLine => const [
        PickupKind.sprint,
        PickupKind.stake,
        PickupKind.freeze,
      ],
      // HEEL first: a warded board is a question about timing, and holding her
      // still is the only direct answer the game has to one.
      LevelSignature.warded => const [
        PickupKind.heel,
        PickupKind.scent,
        PickupKind.freeze,
      ],
      LevelSignature.heavyGround =>
        level <= foundationEnd
            ? const [PickupKind.radiusPlus, PickupKind.freeze]
            : const [PickupKind.blast, PickupKind.radiusPlus],
      LevelSignature.springLine => const [PickupKind.sprint, PickupKind.freeze],
      LevelSignature.nightWatch => const [PickupKind.scent, PickupKind.freeze],
      LevelSignature.supplyRun ||
      LevelSignature.gauntlet ||
      LevelSignature.lesson => pool,
      LevelSignature.breach => const [
        PickupKind.dig,
        PickupKind.blast,
        PickupKind.scent,
      ],
    };
    return [
      for (final kind in preferred)
        if (pool.contains(kind)) kind,
    ];
  }

  static double _lerp((double, double) range, double t) =>
      range.$1 + (range.$2 - range.$1) * t;

  static int _lerpInt((int, int) range, double t) =>
      (range.$1 + (range.$2 - range.$1) * t).round();
}

extension on LevelSignature {
  double get anchorDelta => switch (this) {
    LevelSignature.openTrail => -0.03,
    LevelSignature.heavyGround => -0.012,
    LevelSignature.breach => 0.025,
    _ => 0,
  };

  double get heavyDelta => switch (this) {
    LevelSignature.openTrail => -0.02,
    LevelSignature.heavyGround => 0.045,
    _ => 0,
  };

  double get springMultiplier => switch (this) {
    LevelSignature.springLine => 1.65,
    _ => 1,
  };

  double get faultMultiplier => switch (this) {
    LevelSignature.faultLine => 1.7,
    _ => 1,
  };

  int get guardBonus => switch (this) {
    LevelSignature.nightWatch => 1,
    _ => 0,
  };

  int get sentryBonus => switch (this) {
    LevelSignature.warded => 1,
    _ => 0,
  };

  int get extraTreats => switch (this) {
    LevelSignature.supplyRun => 1,
    _ => 0,
  };

  int get extraPowerups => switch (this) {
    LevelSignature.supplyRun => 1,
    _ => 0,
  };

  double get regrowDelta => switch (this) {
    LevelSignature.closingTrail => -0.65,
    _ => 0,
  };
}

extension on LevelPace {
  double get budgetRelief => switch (this) {
    LevelPace.introduction => 0.16,
    LevelPace.practice => 0.11,
    LevelPace.combination => 0.035,
    LevelPace.breather => 0.15,
    _ => 0,
  };

  double get hungerRelief => switch (this) {
    LevelPace.introduction => 0.16,
    LevelPace.practice => 0.11,
    LevelPace.combination => 0.035,
    LevelPace.breather => 0.15,
    _ => 0,
  };

  double get regrowRelief => switch (this) {
    LevelPace.introduction => 0.9,
    LevelPace.practice => 0.65,
    LevelPace.combination => 0.2,
    LevelPace.breather => 0.85,
    _ => 0,
  };

  double get anchorRelief => switch (this) {
    LevelPace.introduction => 0.03,
    LevelPace.practice => 0.02,
    LevelPace.combination => 0.006,
    LevelPace.breather => 0.025,
    _ => 0,
  };

  double get heavyRelief => switch (this) {
    LevelPace.introduction => 0.02,
    LevelPace.practice => 0.015,
    LevelPace.combination => 0.005,
    LevelPace.breather => 0.02,
    _ => 0,
  };

  double get obstacleMultiplier => switch (this) {
    LevelPace.introduction => 0.65,
    LevelPace.practice => 0.75,
    LevelPace.breather => 0.72,
    LevelPace.combination => 0.92,
    _ => 1,
  };

  int get guardRelief => switch (this) {
    LevelPace.practice || LevelPace.breather => 1,
    _ => 0,
  };

  double get guardSpeedRelief => switch (this) {
    LevelPace.introduction => 0.10,
    LevelPace.practice => 0.08,
    LevelPace.breather => 0.08,
    LevelPace.combination => 0.02,
    _ => 0,
  };
}
