import 'package:shared_preferences/shared_preferences.dart';

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

  int get totalStars =>
      _records.values.fold(0, (sum, record) => sum + record.stars);

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
    if (level > endlessBest) {
      await _prefs.setInt(_endlessKey, level);
    }
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

  /// Wipes everything. Only reachable from the debug panel.
  Future<void> reset() async {
    _records.clear();
    for (final key in _prefs.getKeys().toList()) {
      // Settings are deliberately not wiped. Reset is for progress; someone
      // who has turned the sound off does not expect that to come back on
      // because they cleared their levels.
      if (key.startsWith('lvl_') ||
          key == _unlockedKey ||
          key == _endlessKey ||
          key == _petKey) {
        await _prefs.remove(key);
      }
    }
  }
}
