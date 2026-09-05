import 'package:shared_preferences/shared_preferences.dart';

import 'level_rules.dart';

/// What a player has done with one level.
class LevelRecord {
  const LevelRecord({this.stars = 0, this.bestTaps = 0, this.bestTime = 0});

  final int stars;

  /// Zero means never finished.
  final int bestTaps;
  final double bestTime;

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
  static const _developerKey = 'opt_developer';
  static const _ownedKey = 'owns_full';

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
        ),
        'taps' => LevelRecord(
          stars: existing.stars,
          bestTaps: _prefs.getInt(key) ?? 0,
          bestTime: existing.bestTime,
        ),
        'time' => LevelRecord(
          stars: existing.stars,
          bestTaps: existing.bestTaps,
          bestTime: _prefs.getDouble(key) ?? 0,
        ),
        _ => existing,
      };
    }
  }

  /// The highest level the player may start. Always at least one.
  int get unlocked => (_prefs.getInt(_unlockedKey) ?? 1).clamp(1, 1 << 20);

  int get endlessBest => _prefs.getInt(_endlessKey) ?? 0;

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
  }) async {
    if (level > Campaign.length) {
      await recordEndlessClear(level: level);
      return;
    }
    final existing = recordFor(level);
    final merged = LevelRecord(
      stars: stars > existing.stars ? stars : existing.stars,
      // Zero means "never finished", so any real result beats it.
      bestTaps: existing.bestTaps == 0 || taps < existing.bestTaps
          ? taps
          : existing.bestTaps,
      bestTime: existing.bestTime == 0 || time < existing.bestTime
          ? time
          : existing.bestTime,
    );
    _records[level] = merged;

    await _prefs.setInt('lvl_${level}_stars', merged.stars);
    await _prefs.setInt('lvl_${level}_taps', merged.bestTaps);
    await _prefs.setDouble('lvl_${level}_time', merged.bestTime);

    if (level + 1 > unlocked) {
      await _prefs.setInt(_unlockedKey, level + 1);
    }
  }

  /// Records only the deepest endless board cleared. Endless has no stars,
  /// per-level records or unlock chain: every new run starts at depth one and
  /// the single score is how far that run got.
  Future<void> recordEndlessClear({required int level}) async {
    if (level <= Campaign.length || level <= endlessBest) {
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

  /// Wipes everything. Only reachable from the debug panel.
  Future<void> reset() async {
    _records.clear();
    for (final key in _prefs.getKeys().toList()) {
      // Settings and the purchase are deliberately not wiped. Reset is for
      // progress: someone who turned the sound off does not expect it back on
      // because they cleared their levels, and erasing progress is emphatically
      // not un-buying the game.
      if (key.startsWith('lvl_') ||
          key == _unlockedKey ||
          key == _endlessKey ||
          key == _petKey) {
        await _prefs.remove(key);
      }
    }
  }
}
