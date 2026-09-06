import 'package:shared_preferences/shared_preferences.dart';

import 'daily.dart';
import 'difficulty.dart';
import 'level_rules.dart';

/// What a player has done with one level.
class LevelRecord {
  const LevelRecord({
    this.stars = 0,
    this.bestTaps = 0,
    this.bestTime = 0,
    this.difficulty = Difficulty.normal,
  });

  final int stars;

  /// Zero means never finished.
  final int bestTaps;
  final double bestTime;

  /// The setting [stars] was earned on.
  ///
  /// Stars are scored against the level's *own* tap budget, and Hard tightens
  /// that budget: three stars on Hard are strictly the harder trophy, never a
  /// cheaper one. Recording which setting paid for them is what the map's
  /// 'H' badge reads — a Hard clear beside a Normal clear is a different
  /// thing, and the file should know the difference.
  ///
  /// Records written before this existed read as [Difficulty.normal], which is
  /// what they were.
  final Difficulty difficulty;

  bool get played => stars > 0;
}

/// Everything that has to survive closing the app.
///
/// Reads go through an in-memory cache so the game loop never touches storage;
/// writes go straight out, because a player who closes the app immediately after
/// a good run should still have it next time.
class Progress {
  Progress._(this._prefs);

  final SharedPreferences _prefs;

  static const _unlockedKey = 'unlocked';
  static const _endlessKey = 'endless_best';
  static const _petKey = 'pet';

  // Player settings. Separate keys rather than one blob so a new setting never
  // has to migrate the old ones, and a corrupt value costs one toggle rather
  // than all of them.
  static const _volumeKey = 'opt_volume';
  static const _regrowthSoundKey = 'opt_regrowth_sound';
  static const _hapticsKey = 'opt_haptics';
  static const _reducedMotionKey = 'opt_reduced_motion';
  static const _hintsKey = 'opt_hints';
  static const _difficultyKey = 'opt_difficulty';
  static const _difficultyChosenKey = 'opt_difficulty_chosen';
  static const _developerKey = 'opt_developer';
  static const _zoomKey = 'opt_zoom';
  static const _ownedKey = 'owns_full';
  static const _trialKey = 'trial_used';

  // The daily. Three keys rather than one blob, matching the settings above:
  // a corrupt value costs one of them rather than the streak and the record
  // together.
  static const _dailyLastKey = 'daily_last';
  static const _dailyStreakKey = 'daily_streak';
  static const _dailyBestKey = 'daily_best_streak';

  final Map<int, LevelRecord> _records = {};

  static Future<Progress> load() async {
    final progress = Progress._(await SharedPreferences.getInstance());
    progress._readAll();
    return progress;
  }

  void _readAll() {
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith('lvl_')) {
        continue;
      }
      final parts = key.split('_');
      if (parts.length != 3) {
        continue;
      }
      final level = int.tryParse(parts[1]);
      if (level == null) {
        continue;
      }
      final existing = _records[level] ?? const LevelRecord();
      _records[level] = switch (parts[2]) {
        'stars' => LevelRecord(
          stars: _prefs.getInt(key) ?? 0,
          bestTaps: existing.bestTaps,
          bestTime: existing.bestTime,
          difficulty: existing.difficulty,
        ),
        'taps' => LevelRecord(
          stars: existing.stars,
          bestTaps: _prefs.getInt(key) ?? 0,
          bestTime: existing.bestTime,
          difficulty: existing.difficulty,
        ),
        'time' => LevelRecord(
          stars: existing.stars,
          bestTaps: existing.bestTaps,
          bestTime: _prefs.getDouble(key) ?? 0,
          difficulty: existing.difficulty,
        ),
        'diff' => LevelRecord(
          stars: existing.stars,
          bestTaps: existing.bestTaps,
          bestTime: existing.bestTime,
          difficulty: Difficulty.fromKey(_prefs.getString(key)),
        ),
        _ => existing,
      };
    }
  }

  /// The highest level the player may start. Always at least one.
  int get unlocked => (_prefs.getInt(_unlockedKey) ?? 1).clamp(1, 1 << 20);

  /// The deepest endless board cleared, both modes counted together.
  ///
  /// A Hard clear is the strictly harder feat of the same generated run, so
  /// folding the two costs the record nothing; what the two-mode design won't
  /// accept is a third number to celebrate.
  int get endlessBest => _prefs.getInt(_endlessKey) ?? 0;

  /// The deepest endless board cleared on one setting. With two modes both of
  /// which crown the deeper run, this is simply [endlessBest] — kept as a call
  /// site compatible name because three files already ask the question.
  int endlessBestOn(Difficulty difficulty) => endlessBest;

  String get pet => _prefs.getString(_petKey) ?? 'dog';

  LevelRecord recordFor(int level) => _records[level] ?? const LevelRecord();

  /// Stars belong to the authored campaign. Old builds wrote ordinary level
  /// records for endless depths; filtering here keeps those legacy records
  /// from becoming an unlimited source of pet unlocks.
  int get totalStars => _records.entries
      .where((entry) => entry.key >= 1 && entry.key <= Campaign.length)
      .fold(0, (sum, entry) => sum + entry.value.stars);

  int get completedLevels => _records.entries
      .where(
        (entry) =>
            entry.key >= 1 &&
            entry.key <= Campaign.length &&
            entry.value.played,
      )
      .length;

  int get masteredLevels => _records.entries
      .where(
        (entry) =>
            entry.key >= 1 &&
            entry.key <= Campaign.length &&
            entry.value.stars == 3,
      )
      .length;

  bool isUnlocked(int level) => level <= unlocked;

  /// Records a finished level.
  ///
  /// **Every field only ever improves.** A replay that goes worse must never
  /// overwrite a good result — losing a three-star run by replaying it casually
  /// is the kind of thing a player never forgives, and it is the one rule in
  /// persistence that is easy to get wrong silently.
  Future<void> recordWin({
    required int level,
    required int stars,
    required int taps,
    required double time,
    Difficulty difficulty = Difficulty.normal,
  }) async {
    if (level > Campaign.length) {
      await recordEndlessClear(level: level, difficulty: difficulty);
      return;
    }
    final existing = recordFor(level);
    final beatsStars = stars > existing.stars;
    final merged = LevelRecord(
      stars: beatsStars ? stars : existing.stars,
      // Zero means "never finished", so any real result beats it.
      bestTaps: existing.bestTaps == 0 || taps < existing.bestTaps
          ? taps
          : existing.bestTaps,
      bestTime: existing.bestTime == 0 || time < existing.bestTime
          ? time
          : existing.bestTime,
      // Follows the stars, because it exists to say what they cost. A run that
      // beats the star count owns the badge outright; one that merely matches
      // it upgrades the badge only by having done it on a harder setting. What
      // this rules out is the one that would sting: a casual replay
      // downgrading a Hard-earned mark on a level already finished.
      difficulty: beatsStars
          ? difficulty
          : stars == existing.stars &&
                difficulty.rank > existing.difficulty.rank
          ? difficulty
          : existing.difficulty,
    );
    _records[level] = merged;

    await _prefs.setInt('lvl_${level}_stars', merged.stars);
    await _prefs.setInt('lvl_${level}_taps', merged.bestTaps);
    await _prefs.setDouble('lvl_${level}_time', merged.bestTime);
    await _prefs.setString('lvl_${level}_diff', merged.difficulty.storageKey);

    if (level + 1 > unlocked) {
      await _prefs.setInt(_unlockedKey, level + 1);
    }
  }

  /// Records only the deepest endless board cleared. Endless has no stars,
  /// per-level records or unlock chain: every new run starts at depth one and
  /// the single score is how far that run got.
  Future<void> recordEndlessClear({
    required int level,
    Difficulty difficulty = Difficulty.normal,
  }) async {
    if (level <= Campaign.length || level <= endlessBestOn(difficulty)) {
      return;
    }
    await _prefs.setInt(_endlessKey, level);
  }

  Future<void> choosePet(String name) => _prefs.setString(_petKey, name);

  // -------------------------------------------------------------------------
  // Settings. Defaults match how the game shipped before they were settable, so
  // an existing player's game does not change under them the first time they
  // open this build.
  // -------------------------------------------------------------------------

  double get volume => (_prefs.getDouble(_volumeKey) ?? 0.85).clamp(0.0, 1.0);
  Future<void> setVolume(double v) => _prefs.setDouble(_volumeKey, v);

  /// Whether regrowth makes a sound. Off by default: the player asked for the
  /// warning to be felt rather than heard, because it overlapped the tap sound.
  bool get regrowthSound => _prefs.getBool(_regrowthSoundKey) ?? false;
  Future<void> setRegrowthSound(bool on) =>
      _prefs.setBool(_regrowthSoundKey, on);

  bool get haptics => _prefs.getBool(_hapticsKey) ?? true;
  Future<void> setHaptics(bool on) => _prefs.setBool(_hapticsKey, on);

  /// Screen shake, hit-stop and the desaturation on a loss.
  bool get reducedMotion => _prefs.getBool(_reducedMotionKey) ?? false;
  Future<void> setReducedMotion(bool on) =>
      _prefs.setBool(_reducedMotionKey, on);

  bool get hints => _prefs.getBool(_hintsKey) ?? true;
  Future<void> setHints(bool on) => _prefs.setBool(_hintsKey, on);

  /// How far the board is magnified, as a [BoardCamera] step.
  ///
  /// A comfort setting rather than a per-level one, so it persists like volume
  /// does: a player who needs the board bigger needs it bigger tomorrow too.
  double get zoom => (_prefs.getDouble(_zoomKey) ?? 1.0).clamp(1.0, 3.0);
  Future<void> setZoom(double v) => _prefs.setDouble(_zoomKey, v);

  /// How hard the campaign plays. Defaults to the setting the game shipped
  /// with, so an existing player's game does not change under them.
  Difficulty get difficulty =>
      Difficulty.fromKey(_prefs.getString(_difficultyKey));

  Future<void> setDifficulty(Difficulty d) async {
    await _prefs.setString(_difficultyKey, d.storageKey);
    await _prefs.setBool(_difficultyChosenKey, true);
  }

  /// Whether the player has been asked to pick a difficulty yet.
  ///
  /// A separate flag rather than "is the difficulty key absent", because those
  /// stop being the same question the moment someone picks Normal: the stored
  /// value would be indistinguishable from the default and they would be asked
  /// again on the next launch.
  ///
  /// True for existing players, who have been playing the campaign as authored
  /// and should not be interrupted to be told they were on Normal all along.
  bool get difficultyChosen =>
      _prefs.getBool(_difficultyChosenKey) ?? unlocked > 1;

  /// The tuning panel.
  ///
  /// **Off by default, and it has to stay that way.** The panel is a developer
  /// tool — twenty sliders that can make the game unwinnable and a button that
  /// erases every star the player has earned. It was shipping to players
  /// unconditionally, one tap from their save.
  ///
  /// A setting rather than `kDebugMode`, because every playtest of this project
  /// has been a *release* build and the panel's level jump is how the later
  /// levels get reached. Compiling it out would take the tool away from the one
  /// person using it. Nobody turns this on by accident.
  bool get developerTools => _prefs.getBool(_developerKey) ?? false;
  Future<void> setDeveloperTools(bool on) => _prefs.setBool(_developerKey, on);

  /// Whether the full campaign has been bought.
  ///
  /// A **cache**, not the record. Google's purchase stream is the record; this
  /// exists so a player who has paid can still play on a plane. It is refreshed
  /// from `restorePurchases()` on every launch, so a stale true survives at most
  /// until the next time the device can reach Play — and a stale *false* is
  /// corrected the moment it can.
  ///
  /// Forgeable on a rooted device, and deliberately so: engineering against that
  /// for a single-player puzzle game costs more than it protects.
  bool get ownsFullGame => _prefs.getBool(_ownedKey) ?? false;
  Future<void> setOwnsFullGame(bool owned) => _prefs.setBool(_ownedKey, owned);

  /// Whether the one free look past the paywall has been taken.
  ///
  /// Spent when the trial level *starts*, not when it ends. Ending it would
  /// mean backing out returned the trial, which makes it replayable forever
  /// through the one route the player is guaranteed to find. Starting it is a
  /// deliberate act — the detail sheet says plainly that it is a single try —
  /// so there is nothing to protect them from here.
  bool get trialUsed => _prefs.getBool(_trialKey) ?? false;
  Future<void> setTrialUsed() => _prefs.setBool(_trialKey, true);

  // -------------------------------------------------------------------------
  // The daily challenge.
  // -------------------------------------------------------------------------

  /// The `YYYY-MM-DD` of the last daily cleared, or empty for none.
  String get dailyLastCleared => _prefs.getString(_dailyLastKey) ?? '';

  /// Consecutive days cleared, ending on [dailyLastCleared].
  ///
  /// Note this is **not** decayed on read: a player who misses a day still
  /// sees their old streak until they next clear one, at which point it resets
  /// to 1. Expiring it in the getter would mean the number quietly changed
  /// while nobody was playing, and the honest place to break the news is the
  /// run that broke it. [dailyStreakAsOf] is the display-time view.
  int get dailyStreak => _prefs.getInt(_dailyStreakKey) ?? 0;

  int get dailyBestStreak => _prefs.getInt(_dailyBestKey) ?? 0;

  bool hasClearedDaily(DailyChallenge daily) => dailyLastCleared == daily.id;

  /// The streak as it stands on [today] — zero once a day has been missed.
  ///
  /// What the UI shows, so a lapsed streak does not keep advertising itself as
  /// live. The stored value is left alone; only the reading of it changes.
  int dailyStreakAsOf(DateTime today) {
    final last = _parseDay(dailyLastCleared);
    if (last == null) {
      return 0;
    }
    final day = Daily.dayNumber(Daily.today(today));
    final since = day - Daily.dayNumber(last);
    // Today's own clear, or yesterday's with today still to play.
    return since <= 1 ? dailyStreak : 0;
  }

  /// Records a cleared daily. Idempotent: clearing the same day twice — by
  /// retrying a board already won — must not advance the streak twice.
  Future<void> recordDailyClear(DailyChallenge daily) async {
    if (dailyLastCleared == daily.id) {
      return;
    }
    final last = _parseDay(dailyLastCleared);
    final continues = last != null && Daily.isDayBefore(last, daily.date);
    final streak = continues ? dailyStreak + 1 : 1;

    await _prefs.setString(_dailyLastKey, daily.id);
    await _prefs.setInt(_dailyStreakKey, streak);
    if (streak > dailyBestStreak) {
      await _prefs.setInt(_dailyBestKey, streak);
    }
  }

  static DateTime? _parseDay(String id) {
    if (id.isEmpty) {
      return null;
    }
    final parts = id.split('-');
    if (parts.length != 3) {
      return null;
    }
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) {
      return null;
    }
    return DateTime.utc(y, m, d);
  }

  /// Wipes everything. Only reachable from the debug panel.
  Future<void> reset() async {
    _records.clear();
    for (final key in _prefs.getKeys().toList()) {
      // Settings and the purchase are deliberately not wiped. Reset is for
      // progress: someone who turned the sound off does not expect it back on
      // because they cleared their levels, and erasing progress is emphatically
      // not un-buying the game.
      // The trial goes with progress rather than with the purchase: it is only
      // reachable by clearing twenty levels, so a wiped save that kept it spent
      // would deny the free look to a playthrough that has earned it again.
      if (key.startsWith('lvl_') ||
          key == _unlockedKey ||
          key == _endlessKey ||
          key == _trialKey ||
          key == _dailyLastKey ||
          key == _dailyStreakKey ||
          key == _dailyBestKey ||
          key == _petKey) {
        await _prefs.remove(key);
      }
    }
  }
}
