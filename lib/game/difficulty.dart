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
/// **Hard is brutal — including its board.** Past the tutorial it is not the
/// same field with tighter numbers: the ground itself is heavier, the lights
/// more numerous, and the supply economy thinner. Walls, brambles, hazards and
/// the whole rebuilt family place at 1.3×, treats and powerups drop one fewer
/// apiece, and what a treat pays shrinks. The floors in `Campaign._band` keep
/// the one promise hardness must not break: a board that remains completable.
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
    'Brutal by design: leanest possible budgets, a punishing clock, twice the '
        'lights at speed, deep fog, and no hints. Winnable — barely.',
  );

  const Difficulty(this.label, this.description);

  final String label;
  final String description;

  /// The campaign's scripted opening trio. Mirrored from
  /// [Campaign.tutorialBand] rather than imported, because level_rules already
  /// imports this file and the dependency must run one way. The difficulty
  /// tests pin the number so a change made either side is caught.
  static const tutorialLevels = 3;

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
    (Difficulty.hard, true) => -0.20,
    (Difficulty.hard, false) => 0,
  };

  /// The budget can never drop below this multiple of par, difficulty
  /// included. On Normal it is the campaign's own fairness floor — two spare
  /// taps over optimal play at every point in the sweep. On Hard it is par
  /// itself: the run remains completable, but only if the route is read
  /// essentially perfectly, which is the whole promise of the mode.
  double get budgetFloor => switch (this) {
    Difficulty.normal => 1.06,
    Difficulty.hard => 1.0,
  };

  /// Added to the seconds-per-cell hunger clock. Floored at [hungerFloor] for
  /// the same reason the budget is floored.
  double hungerRelief(int level) => switch ((this, level > tutorialLevels)) {
    (Difficulty.normal, true) => -0.04,
    (Difficulty.normal, false) => 0,
    (Difficulty.hard, true) => -0.22,
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
    (Difficulty.hard, true) => 0.45,
    (Difficulty.hard, false) => 0,
  };

  /// Added to the light counts, floored at one by the caller wherever the
  /// mechanic has been introduced. Hard doubles the working guard; Normal
  /// does not touch what it generates — the board stays the campaign's.
  int guardDelta(int level) => switch ((this, level > tutorialLevels)) {
    (Difficulty.normal, true) => 0,
    (Difficulty.normal, false) => 0,
    (Difficulty.hard, true) => 2,
    (Difficulty.hard, false) => 0,
  };

  /// Added to the regrowth delay, floored at [regrowFloor]: the warning
  /// animation is fixed, so this number controls how much of the three-second
  /// body of the close she is shown.
  double regrowRelief(int level) => switch ((this, level > tutorialLevels)) {
    (Difficulty.normal, true) => -0.3,
    (Difficulty.normal, false) => 0,
    (Difficulty.hard, true) => -1.4,
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
  double revealMultiplierFor(int level) => switch ((this, level > tutorialLevels)) {
    (Difficulty.normal, true) => 0.92,
    (Difficulty.normal, false) => 1.0,
    (Difficulty.hard, true) => 0.6,
    (Difficulty.hard, false) => 1.0,
  };

  /// What the ground charges for standing on it: patrol bites and thorn bites
  /// alike. A number, never a board change — the difficulty invariant (one
  /// seeded board, two pressures) holds.
  double get biteScale => switch (this) {
    Difficulty.normal => 1.0,
    Difficulty.hard => 1.6,
  };

  /// How long rhythm windows stay open: alarm hurries, and the effective beat
  /// of blinkers and runner pauses as it is felt through the shared light pace.
  double get rhythmScale => switch (this) {
    Difficulty.normal => 1.0,
    Difficulty.hard => 0.7,
  };

  /// How heavily the board itself lies: the multiplier on every placed
  /// obstacle density (walls, brambles, hazards, the rebuilt family's denser
  /// ground). Normal is one — the campaign as authored. Hard's heavier ground
  /// scales placement, not prices: the route is still *there*, seeded from the
  /// same stream; there is simply less plain room around it.
  ///
  /// Deliberately not level-aware: the tutorial never reaches the band logic
  /// [Campaign.rulesFor] applies this in, so its zero-shift is structural
  /// rather than another branch to reason about.
  double get obstacleDensityScale => switch (this) {
    Difficulty.normal => 1.0,
    Difficulty.hard => 1.3,
  };

  /// Treats entering the field, shifted. Hard runs hungrier: one less bone in
  /// the grass, floored by the campaign at one so the supply, however lean,
  /// exists.
  int get supplyDelta => switch (this) {
    Difficulty.normal => 0,
    Difficulty.hard => -1,
  };

  /// Powerups entering the field, shifted. The tools answer is what arrives,
  /// not when — the pool gating stays the campaign's on both modes, so a Hard
  /// board is never denied the charge that answers its own tile.
  int get powerupDelta => switch (this) {
    Difficulty.normal => 0,
    Difficulty.hard => -1,
  };

  /// What a treat pays in taps, shifted. Floored at one by the campaign, so a
  /// snack never becomes pure time and skips a budget the level rationed.
  int get treatTapDelta => switch (this) {
    Difficulty.normal => 0,
    Difficulty.hard => -1,
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
