import 'dart:math' as math;

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// What kind of thing a sound is, so categories can be silenced independently.
///
/// The regrowth cues turned out to tread on the tap notes in play — they fire
/// in waves while the player is tapping fastest — so they can be muted on their
/// own while the taps, which are the player's own action answering back, keep
/// their voice.
enum SoundGroup {
  /// Direct answers to a tap: the scale, a heavy holding, a wall refusing.
  tap,

  /// The field acting on its own: regrowth warning and closing.
  field,

  /// One-off moments — pickups, endings, her reactions. Rare enough that they
  /// never collide with rapid tapping.
  event,

  /// The heartbeat under the endgame.
  ambient,
}

/// Every sound the game can make. Names match the files written by
/// `tool/generate_audio.dart`.
enum Sound {
  crack,
  thunk,
  warn,
  snap,
  treat,
  powerup,
  chomp,
  starve,
  crush,
  bark,
  whimper,
  heartbeat,
}

extension SoundGrouping on Sound {
  SoundGroup get group => switch (this) {
    Sound.crack || Sound.thunk => SoundGroup.tap,
    Sound.warn || Sound.snap => SoundGroup.field,
    Sound.heartbeat => SoundGroup.ambient,
    _ => SoundGroup.event,
  };
}

/// Sound playback.
///
/// Everything is loaded into an [AudioPool] up front and played in
/// `PlayerMode.lowLatency`, which on Android routes through SoundPool rather
/// than MediaPlayer. That distinction is the whole ballgame for a tap-driven
/// game: a tap sound arriving 100ms late reads as the game ignoring you, and
/// the streak's rising scale falls apart entirely if the notes lag the taps.
///
/// Failures here are swallowed on purpose. A device that cannot open an audio
/// stream should still be perfectly playable — sound is the polish layer, not
/// the game.
class Sfx {
  Sfx({this.enabled = true});

  bool enabled;

  /// Scales every sound. Zero silences without unloading anything.
  double volume = 1.0;

  /// Groups that stay silent. Their cues still fire — see [play] — so the
  /// haptics paired with them are unaffected.
  Set<SoundGroup> mutedGroups = const {};

  final Map<String, AudioPool> _pools = {};
  final Map<String, Duration> _durations = {};
  final Map<String, double> _lastPlayed = {};
  double _now = 0;
  bool _ready = false;

  /// Used when a clip's real duration can't be read back. Long enough for any
  /// of these short cues to finish before the player is reclaimed.
  static const _fallbackDuration = Duration(milliseconds: 800);

  /// Padding on top of a clip's real duration before its player goes back to
  /// the pool, so the tail of the sound is never cut short by reclaiming it
  /// too early.
  static const _releaseMargin = Duration(milliseconds: 150);

  /// Advances the throttle clock. Driven from the game loop rather than a
  /// stopwatch so it pauses with the game.
  void tick(double dt) => _now += dt;

  /// How many rungs the streak scale has. Matches the generated `tap_NN` files.
  static const noteCount = 8;

  /// The note a streak of [streak] plays. Caps at the top of the scale rather
  /// than wrapping: a chain that keeps climbing forever stops reading as an
  /// achievement and starts sounding like a mistake.
  static int noteFor(int streak) => streak.clamp(0, noteCount - 1);

  Future<void> load() async {
    if (_ready) {
      return;
    }
    final names = <String>[
      for (var i = 0; i < noteCount; i++) 'tap_${i.toString().padLeft(2, '0')}',
      for (final sound in Sound.values) sound.name,
    ];
    for (final name in names) {
      try {
        final pool = await AudioPool.createFromAsset(
          path: '$name.wav',
          audioCache: FlameAudio.audioCache,
          // Two players per sound: enough for a second tap to start before the
          // first has finished ringing, without holding open a stream each.
          maxPlayers: 2,
          playerMode: PlayerMode.lowLatency,
        );
        _pools[name] = pool;
        // PlayerMode.lowLatency never auto-recycles its players (see
        // _playNamed) — read the clip's real length once up front so we know
        // when it's safe to reclaim one after playback.
        _durations[name] = await pool.getDuration() ?? _fallbackDuration;
      } catch (error) {
        debugPrint('hexcape: could not load $name.wav ($error)');
      }
    }
    _ready = true;
  }

  /// Fires the cue for [sound], unless it already fired within [minInterval]
  /// seconds.
  ///
  /// The return value means *the cue passed its throttle* — deliberately not
  /// "a sound came out". Callers pair haptics with it, and haptics have to keep
  /// working when the volume is down: tying them to actual playback would mean
  /// muting the game silently removed half its feedback.
  bool play(Sound sound, {double gain = 1.0, double minInterval = 0}) =>
      _playNamed(
        sound.name,
        gain,
        minInterval,
        audible: !mutedGroups.contains(sound.group),
      );

  /// The streak note. [streak] of zero is the root of the scale. Never
  /// throttled — this one is the player's own action answering back, and it is
  /// the single sound that must never be dropped or delayed.
  void playTap(int streak, {double gain = 1.0}) {
    final index = noteFor(streak);
    _playNamed('tap_${index.toString().padLeft(2, '0')}', gain, 0);
  }

  bool _playNamed(
    String name,
    double gain,
    double minInterval, {
    bool audible = true,
  }) {
    // Throttle first, and independently of volume, so the cue timing a caller
    // hangs a haptic off is identical whether or not the sound is audible.
    if (minInterval > 0) {
      final last = _lastPlayed[name];
      if (last != null && _now - last < minInterval) {
        return false;
      }
    }
    _lastPlayed[name] = _now;

    if (!enabled || !audible || volume <= 0) {
      return true;
    }
    final pool = _pools[name];
    if (pool == null) {
      return true;
    }
    // Fire and forget: awaiting playback inside the game loop would stall a
    // frame for the sake of a sound effect. In PlayerMode.lowLatency, AudioPool
    // never reclaims a player on its own (that's only wired up for other
    // player modes), so without this the pool would silently mint a brand-new
    // native player on every single call and never free it — the backlog is
    // what eventually reads as taps' sound and haptics arriving later and
    // later. Scheduling the returned stop function once the clip has actually
    // finished is what lets the pool reuse its players instead.
    final duration = _durations[name] ?? _fallbackDuration;
    pool
        .start(volume: (volume * gain).clamp(0.0, 1.0))
        .then((stop) {
          Future.delayed(duration + _releaseMargin, stop).catchError((_) {});
        })
        .catchError((_) {});
    return true;
  }

  void dispose() {
    for (final pool in _pools.values) {
      pool.dispose();
    }
    _pools.clear();
    _ready = false;
  }
}

/// The heartbeat under the endgame.
///
/// §11 asked for "a rising ambient tone as regrowth closes in". A looping drone
/// would mean loop artefacts and a permanently open stream; a heartbeat that
/// tightens as she tires says the same thing about mounting pressure and also
/// says something true about *her*.
///
/// Silent while she is comfortable, so the early game keeps its calm and the
/// first thump is itself a warning.
class Heartbeat {
  /// Above this fraction of hunger, nothing plays at all.
  static const startsBelow = 0.55;

  static const slowestInterval = 1.4;
  static const fastestInterval = 0.35;

  double _sinceLastBeat = 0;

  /// Seconds between beats at the given hunger fraction. Monotonically shorter
  /// as the bar empties.
  static double intervalAt(double hungerFraction) {
    final t = (1 - hungerFraction / startsBelow).clamp(0.0, 1.0);
    return slowestInterval + (fastestInterval - slowestInterval) * t;
  }

  /// Volume swells as the interval tightens, so the crescendo is heard as well
  /// as counted.
  static double gainAt(double hungerFraction) {
    final t = (1 - hungerFraction / startsBelow).clamp(0.0, 1.0);
    return 0.45 + 0.55 * t;
  }

  /// Advances the timer. Returns true on the frames a beat should sound.
  bool update(double dt, double hungerFraction) {
    if (hungerFraction >= startsBelow || hungerFraction <= 0) {
      _sinceLastBeat = math.max(_sinceLastBeat, intervalAt(hungerFraction));
      return false;
    }
    _sinceLastBeat += dt;
    if (_sinceLastBeat >= intervalAt(hungerFraction)) {
      _sinceLastBeat = 0;
      return true;
    }
    return false;
  }

  void reset() => _sinceLastBeat = 0;
}
