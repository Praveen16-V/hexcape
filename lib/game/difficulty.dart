/// How hard the campaign plays, on top of the level number.
///
/// [Campaign] already encodes one difficulty curve — six bands of interpolated
/// parameters, nudged by [LevelPace]'s relief beats. This is a second axis
/// folded into the same clamp expressions rather than a second set of levels:
/// three hand-tuned campaigns would mean three curves to author, three fairness
/// sweeps to pass, and three chances to get the monotonicity wrong.
///
/// **[normal] is a mathematical no-op.** Every value below is zero or one for
/// it, so `Campaign.rulesFor(n)` and `Campaign.rulesFor(n, difficulty: normal)`
/// produce identical rules. That is what keeps every existing save file, star
/// record and test meaningful under this change, and `difficulty_test` asserts
/// it across all hundred levels.
///
/// **Difficulty never touches a density.** Anchors, heavies, springs, faults and
/// pickups are all placed from one shared RNG stream in `LevelGenerator`, so
/// changing any of them would shift every draw after it and move the treats.
/// The knobs here are either absent from generation entirely (budget, hunger,
/// regrowth, fog, hints) or drawn from the guards' own separate stream — so all
/// three difficulties play the *same board*, and only its pressure changes.
enum Difficulty {
  easy(
    'Easy',
    'More taps, more time, and slower patrols. The same boards with room to '
        'think.',
  ),
  normal('Normal', 'The campaign as it was designed to be played.'),
  hard('Hard', 'Tighter budgets, faster patrols, thicker fog, and no hints.');

  const Difficulty(this.label, this.description);

  final String label;
  final String description;

  /// Ordering for "did this run beat the record", where a clear on a harder
  /// setting is the better result. Declaration order would do it, but naming it
  /// makes the comparisons in [Progress] read as intent rather than trivia.
  int get rank => index;

  /// Added to the tap budget. Floored by the caller at the campaign's own 1.06,
  /// below which `campaign_sweep_test` says a level demands provably optimal
  /// play — so Hard buys nothing on Collapse and Vigil, which are already
  /// pinned there, and leans on patrols and fog instead.
  double get budgetRelief => switch (this) {
    Difficulty.easy => 0.20,
    Difficulty.normal => 0,
    Difficulty.hard => -0.10,
  };

  /// Added to the seconds-per-cell hunger clock. Floored at 0.85 for the same
  /// reason, and pinned flat across the last two bands for the same reason.
  double get hungerRelief => switch (this) {
    Difficulty.easy => 0.15,
    Difficulty.normal => 0,
    Difficulty.hard => -0.08,
  };

  /// Added to patrol speed. The caller widens its own ceiling by exactly this
  /// much, so Hard's cap is Normal's cap plus one Hard step rather than a new
  /// number invented here.
  double get guardSpeedDelta => switch (this) {
    Difficulty.easy => -0.15,
    Difficulty.normal => 0,
    Difficulty.hard => 0.15,
  };

  /// Added to the guard and sentry counts, floored at one by the caller
  /// wherever the mechanic has been introduced: Easy makes a patrol level
  /// quieter, never a patrol level with no patrols, because a lesson the
  /// campaign has already taught should not silently un-teach itself.
  int get guardDelta => switch (this) {
    Difficulty.easy => -1,
    Difficulty.normal => 0,
    Difficulty.hard => 1,
  };

  /// Added to the regrowth delay, floored at the campaign's own 3.2.
  double get regrowRelief => switch (this) {
    Difficulty.easy => 1.0,
    Difficulty.normal => 0,
    Difficulty.hard => -0.5,
  };

  /// Scales how far the fog is pushed back. Applied to `tuning` at level start
  /// rather than through [LevelRules], which has no authored value for it.
  double get revealMultiplier => switch (this) {
    Difficulty.easy => 1.3,
    Difficulty.normal => 1.0,
    Difficulty.hard => 0.8,
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
    // Anything unreadable reads as the setting the game shipped with, which is
    // also the one that changes nothing.
    orElse: () => Difficulty.normal,
  );
}
