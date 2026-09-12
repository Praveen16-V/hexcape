/// How hard the campaign plays, on top of the level number.
///
/// [Campaign] already encodes one difficulty curve — six bands of interpolated
/// parameters, nudged by [LevelPace]'s relief beats. This is a second axis
/// folded into the same clamp expressions rather than a second set of levels:
/// two hand-tuned campaigns would mean two curves to author, two fairness
/// sweeps to pass, and two chances to get the monotonicity wrong.
///
/// **There are two modes, and each has a stance.**
///
/// **Normal is the adventure.** Through the three tutorial stages it is a
/// mathematical no-op — `Campaign.rulesFor(n)` and
/// `Campaign.rulesFor(n, difficulty: normal)` produce identical rules for
/// n ≤ [tutorialLevels], which `difficulty_test` asserts. From stage 4 onward
/// Normal *tightens itself*, a little: the campaign proper was chosen to feel
/// adventurous rather than padded, so a modest pressure runs on top of the
/// authored bands. It is still the reference curve — every record, save file
/// and star in an old save is compared against it.
///
/// **Hard is the steeper parallel trail.** Stages 1–20 retain the original
/// brutal tuning. The paid campaign then opens at one quarter of the full
/// Normal-to-Hard gap and grows through authored milestones until stage 100 is
/// exactly as hard as it was before the gradual-curve rebuild. This keeps Hard
/// distinct without making the first patrol board carry the whole endgame
/// penalty at once.
///
/// **Difficulty moves the board now.** The old invariant ("one seeded board,
/// only pressure changes") is retired from stage 4 onward: the same seed under
/// two modes generates two fields. What is kept is *where* the difference is
/// allowed to live — scales and counts applied after the seeded draws' values
/// are computed, so a density never shifts which RNG values land where inside
/// its own generation call. Records carry their mode badge ('H') because the
/// boards themselves differ; the daily stays Normal, so one board for everyone
/// still holds.
enum Difficulty {
  normal(
    'Normal',
    'The campaign as an adventure: tutorial stages guide you, then the '
        'ground starts pushing back. Fair, and honest about it.',
  ),
  hard(
    'Hard',
    'A steeper trail: pressure grows from the first patrol to lean budgets, '
        'fast lights, deep fog, and no hints at the final vigil.',
  );

  const Difficulty(this.label, this.description);

  final String label;
  final String description;

  /// The campaign's scripted opening trio. Mirrored from
  /// [Campaign.tutorialBand] rather than imported, because level_rules already
  /// imports this file and the dependency must run one way. The difficulty
  /// tests pin the number so a change made either side is caught.
  static const tutorialLevels = 3;

  /// How much of the full Normal-to-Hard gap applies after stage 20.
  ///
  /// The earlier campaign is intentionally frozen for save and authored-board
  /// compatibility. Endless also retains the complete Hard profile.
  double _hardFactor(int level) {
    if (this != Difficulty.hard) return 0;
    if (level <= 20 || level >= 100) return 1;

    double segment(int from, int to, double a, double b) {
      final t = (level - from) / (to - from);
      return a + (b - a) * t.clamp(0.0, 1.0);
    }

    if (level <= 40) return segment(21, 40, 0.25, 0.45);
    if (level <= 60) return segment(40, 60, 0.45, 0.65);
    if (level <= 80) return segment(60, 80, 0.65, 0.85);
    return segment(80, 100, 0.85, 1.0);
  }

  /// Ordering for "did this run beat the record", where a clear on the harder
  /// setting is the better result.
  int get rank => index;

  /// Added to the tap budget. Through the tutorial both modes leave it alone —
  /// a scripted lesson is not the place for a difficulty knob — and from stage
  /// 4 Normal carries its small adventurer's tax while Hard carries a punitive
  /// one. Floored by the caller at [budgetFloor].
  double budgetRelief(int level) => switch ((this, level > tutorialLevels)) {
    (Difficulty.normal, true) => -0.04,
    (Difficulty.normal, false) => 0,
    (Difficulty.hard, true) when level <= 20 => -0.20,
    (Difficulty.hard, true) => -0.04 - 0.16 * _hardFactor(level),
    (Difficulty.hard, false) => 0,
  };

  /// The budget can never drop below this multiple of par, difficulty
  /// included. On Normal it is the campaign's own fairness floor — two spare
  /// taps over optimal play at every point in the sweep. On Hard it is par
  /// itself: the run remains completable, but only if the route is read
  /// essentially perfectly, which is the whole promise of the mode.
  double budgetFloorFor(int level) => switch (this) {
    Difficulty.normal => 1.06,
    Difficulty.hard when level <= 20 => 1.0,
    Difficulty.hard when level <= 40 => 1.07,
    Difficulty.hard when level <= 80 => 1.01,
    Difficulty.hard => 1.0,
  };

  /// Added to the seconds-per-cell hunger clock. Floored at [hungerFloor] for
  /// the same reason the budget is floored.
  double hungerRelief(int level) => switch ((this, level > tutorialLevels)) {
    (Difficulty.normal, true) => -0.04,
    (Difficulty.normal, false) => 0,
    (Difficulty.hard, true) when level <= 20 => -0.22,
    (Difficulty.hard, true) => -0.04 - 0.18 * _hardFactor(level),
    (Difficulty.hard, false) => 0,
  };

  /// The hunger floor in seconds per cell. Below Normal's 0.85 even a flawless
  /// run starves inside the campaign's largest boards; 0.72 is the hostile end
  /// that stays competitive one board at a time.
  double get hungerFloor => switch (this) {
    Difficulty.normal => 0.85,
    Difficulty.hard => 0.72,
  };

  /// Added to patrol speed. The caller widens its own ceiling by exactly this
  /// much, so Hard's cap is Normal's cap plus one Hard step rather than a new
  /// number invented here.
  double guardSpeedDelta(int level) => switch ((this, level > tutorialLevels)) {
    (Difficulty.normal, true) => 0.05,
    (Difficulty.normal, false) => 0,
    (Difficulty.hard, true) when level <= 20 => 0.45,
    (Difficulty.hard, true) => 0.05 + 0.40 * _hardFactor(level),
    (Difficulty.hard, false) => 0,
  };

  /// Added to the light counts, floored at one by the caller wherever the
  /// mechanic has been introduced. Hard doubles the working guard; Normal
  /// does not touch what it generates — the board stays the campaign's.
  int guardDelta(int level) => switch ((this, level > tutorialLevels)) {
    (Difficulty.normal, true) => 0,
    (Difficulty.normal, false) => 0,
    (Difficulty.hard, true) when level <= 20 => 2,
    (Difficulty.hard, true) => (2 * _hardFactor(level)).round(),
    (Difficulty.hard, false) => 0,
  };

  /// Added to the regrowth delay, floored at [regrowFloor]: the warning
  /// animation is fixed, so this number controls how much of the three-second
  /// body of the close she is shown.
  double regrowRelief(int level) => switch ((this, level > tutorialLevels)) {
    (Difficulty.normal, true) => -0.3,
    (Difficulty.normal, false) => 0,
    (Difficulty.hard, true) when level <= 20 => -1.4,
    (Difficulty.hard, true) => -0.3 - 1.1 * _hardFactor(level),
    (Difficulty.hard, false) => 0,
  };

  /// The regrowth delay floor. 3.2 is the campaign's own; under Hard the field
  /// closes in after 2.4 s of warning, which is still readable and nothing
  /// more.
  double get regrowFloor => switch (this) {
    Difficulty.normal => 3.2,
    Difficulty.hard => 2.4,
  };

  /// Scales how far the fog is pushed back. Applied to `tuning` at level start
  /// rather than through [LevelRules], which has no authored value for it. On
  /// Normal the shift arrives with the campaign proper, like everything else;
  /// in the tutorial the fog remains exactly what the script expects.
  double revealMultiplierFor(int level) =>
      switch ((this, level > tutorialLevels)) {
        (Difficulty.normal, true) => 0.92,
        (Difficulty.normal, false) => 1.0,
        (Difficulty.hard, true) when level <= 20 => 0.6,
        (Difficulty.hard, true) => 0.92 - 0.32 * _hardFactor(level),
        (Difficulty.hard, false) => 1.0,
      };

  /// What the ground charges for standing on it: patrol bites and thorn bites
  /// alike. A number, never a board change — the difficulty invariant (one
  /// seeded board, two pressures) holds.
  double biteScaleFor(int level) => switch (this) {
    Difficulty.normal => 1.0,
    Difficulty.hard when level <= 20 => 1.6,
    Difficulty.hard => 1.0 + 0.6 * _hardFactor(level),
  };

  /// How long rhythm windows stay open: alarm hurries, and the effective beat
  /// of blinkers and runner pauses as it is felt through the shared light pace.
  double rhythmScaleFor(int level) => switch (this) {
    Difficulty.normal => 1.0,
    Difficulty.hard when level <= 20 => 0.7,
    Difficulty.hard => 1.0 - 0.3 * _hardFactor(level),
  };

  /// How heavily the board itself lies: the multiplier on every placed
  /// obstacle density (walls, brambles, hazards, the rebuilt family's denser
  /// ground). Normal is one — the campaign as authored. Hard's heavier ground
  /// scales placement, not prices: the route is still *there*, seeded from the
  /// same stream; there is simply less plain room around it. After stage 20 the
  /// multiplier grows from 1.075 to 1.3.
  double obstacleDensityScaleFor(int level) => switch (this) {
    Difficulty.normal => 1.0,
    Difficulty.hard when level <= 20 => 1.3,
    Difficulty.hard => 1.0 + 0.3 * _hardFactor(level),
  };

  /// Treats entering the field, shifted. Hard runs hungrier: one less bone in
  /// the grass, floored by the campaign at one so the supply, however lean,
  /// exists.
  int supplyDeltaFor(int level) => switch (this) {
    Difficulty.normal => 0,
    Difficulty.hard when level <= 20 => -1,
    Difficulty.hard => _hardFactor(level) >= 0.5 ? -1 : 0,
  };

  /// Powerups entering the field, shifted. The tools answer is what arrives,
  /// not when — the pool gating stays the campaign's on both modes, so a Hard
  /// board is never denied the charge that answers its own tile.
  int powerupDeltaFor(int level) => switch (this) {
    Difficulty.normal => 0,
    Difficulty.hard when level <= 20 => -1,
    Difficulty.hard => _hardFactor(level) >= 0.5 ? -1 : 0,
  };

  /// What a treat pays in taps, shifted. Floored at one by the campaign, so a
  /// snack never becomes pure time and skips a budget the level rationed.
  int treatTapDeltaFor(int level) => switch (this) {
    Difficulty.normal => 0,
    Difficulty.hard when level <= 20 => -1,
    Difficulty.hard => _hardFactor(level) >= 0.5 ? -1 : 0,
  };

  /// Whether the directional hint is withheld for the run.
  ///
  /// Read at the point of use rather than written into `tuning.hintsEnabled`,
  /// which mirrors the player's own persisted setting — overwriting it would
  /// make their toggle appear to reset itself.
  bool get suppressesHints => this == Difficulty.hard;

  /// Stored in preferences by name, so reordering the enum cannot silently
  /// reinterpret saved records.
  String get storageKey => name;

  static Difficulty fromKey(String? key) => values.firstWhere(
    (d) => d.name == key,
    // Anything unreadable — including 'easy', saved by builds from before the
    // two-mode campaign — reads as the setting the game now ships with.
    orElse: () => Difficulty.normal,
  );
}
