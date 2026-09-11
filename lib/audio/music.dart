import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// The looping bed, written by `tool/generate_audio.dart`.
const kMusicAsset = 'music_theme.wav';

/// The music bed: one loop, running for as long as the app is open.
///
/// **Separate from `Sfx`, and not merely for tidiness.** Every cue there
/// goes through an `AudioPool` in `PlayerMode.lowLatency`, which on Android is
/// SoundPool — right for a tap that must answer within a frame, and wrong for
/// a thirty-second loop, which SoundPool would hold decoded in memory in its
/// entirety. Music wants the streaming player and a release mode that repeats;
/// those are different objects with different rules, so this is a different
/// class.
///
/// Three things it has to get right:
///
/// 1. **It never interrupts the game.** Every call is fire-and-forget and every
///    failure is swallowed. A device that cannot open a second audio stream
///    still plays perfectly; music is the last layer of polish, not a feature
///    anything waits on.
/// 2. **It survives navigation.** The loop belongs to the app, not to a screen,
///    so moving between the home screen, the map and a level does not restart
///    it. Restarting the bed on every screen change is the single most
///    noticeable thing background music can get wrong.
/// 3. **It gets out of the way during play.** See [duckedFraction].
class Music {
  Music({this.enabled = true});

  /// The player's own switch, from Settings.
  bool enabled;

  /// The master volume, shared with the sound effects. One slider turning
  /// everything down
  /// is what a player means by "volume"; the music toggle is what they mean by
  /// "not this bit".
  double volume = 1.0;

  /// Whether a level is currently being played.
  bool inLevel = false;

  bool _started = false;
  bool _initialised = false;

  /// How loud the bed sits under everything else at full master volume.
  ///
  /// Low, and deliberately so. It is competing with a tap scale the player is
  /// driving themselves, and anything that makes them wonder whether a note was
  /// theirs has already failed.
  static const baseGain = 0.34;

  /// What the bed drops to while a level is running.
  ///
  /// The tap notes are the game's most important sound — they are the player's
  /// own action answering back, and the streak is *read* through them — and the
  /// heartbeat under low hunger is a warning that has to cut through. Both live
  /// in the same octaves as the bed's melody, so rather than trusting the
  /// harmony to keep them apart, the bed simply steps back. Menus get the full
  /// level; play gets a third of it.
  static const duckedFraction = 0.35;

  /// The gain the loop should be playing at right now.
  double get target => !enabled || volume <= 0
      ? 0
      : volume * baseGain * (inLevel ? duckedFraction : 1);

  /// The gain the player is actually hearing, so [apply] can tell whether it
  /// has anything to do. Starts at a value [target] can never hold.
  double _applied = -1;

  /// Starts the loop, re-levels it, or does nothing — whichever is called for.
  ///
  /// **Cheap and idempotent, which is what lets the caller be stupid.** Screen
  /// changes, settings changes and rebuilds all want the same thing to happen
  /// ("make the music match the state"), and none of them should have to work
  /// out which of start, duck, or stop that means today. Calling this from a
  /// `build` is safe: if nothing has moved, it returns without touching the
  /// player.
  Future<void> apply() async {
    if (target == _applied) {
      return;
    }
    _applied = target;
    if (target <= 0) {
      await _silence();
      return;
    }
    if (!_started) {
      await _start();
      return;
    }
    try {
      await FlameAudio.bgm.audioPlayer.setVolume(target);
    } catch (error) {
      debugPrint('hexcape: could not set music volume ($error)');
    }
  }

  /// Never ask for audio focus, and never react to losing it.
  ///
  /// Both halves matter, and the second one is why this is set in three places
  /// rather than one. `AndroidAudioFocus.none` is the courteous answer to
  /// someone playing a podcast — a puzzle game has no business stopping it —
  /// but it is also the difference between the bed playing and the bed never
  /// being heard at all: with any other setting, audioplayers pauses this
  /// player whenever another app holds focus, and on a phone that has had
  /// YouTube open at some point that day, *that is all the time*. Measured on
  /// a real device: the loop went straight to `state:paused` on a cold launch
  /// and stayed there.
  ///
  /// Set on the **global** scope rather than on the player, and that detail is
  /// load-bearing twice over. `Bgm.play` opens with `audioPlayer.release()`,
  /// which tears down the native player and any context set on it at
  /// initialize time — so a per-player context does not survive to the player
  /// that actually holds the loop. And re-applying one *after* `play` is worse
  /// than useless: reconfiguring an Android player mid-stream re-prepares it,
  /// which on the device under test stopped the music two seconds in. The
  /// global scope is set once, before anything is playing, and nothing has to
  /// be touched again.
  static final _context = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  /// Applies that context app-wide, before anything has made a sound.
  ///
  /// **Called from `main` rather than from [apply], and the timing is the
  /// whole point.** `Sfx.load` builds twenty `AudioPool`s as the game loads,
  /// each with an `AudioPlayer` of its own, and a player created before this
  /// runs takes the default context — which asks for `AUDIOFOCUS_GAIN`. The
  /// result on a real device was the game taking focus away from *itself*: the
  /// tap pools grabbed it, the bed was told it had lost it, and the music went
  /// to `state:paused` on the home screen with nothing else playing.
  ///
  /// Setting it globally before `runApp` means every player minted afterwards
  /// inherits it, and there is no order of construction that can get this
  /// wrong.
  static Future<void> configureSession() async {
    try {
      await AudioPlayer.global.setAudioContext(_context);
    } catch (error) {
      debugPrint('hexcape: could not set the audio session ($error)');
    }
  }

  Future<void> _start() async {
    try {
      if (!_initialised) {
        await FlameAudio.bgm.initialize(audioContext: _context);
        _initialised = true;
      }
      await FlameAudio.bgm.play(kMusicAsset, volume: target);
      // Re-asserted after the source is set, and it has to be. `Bgm.play`
      // calls `setReleaseMode(loop)` *before* `setSource`, and on Android
      // preparing a new source resets the looping flag — so the bed played
      // exactly one pass and stopped. Measured: a 32,817 ms track, which is
      // the loop once, then silence for the rest of the session.
      //
      // Safe to call here where re-applying the audio *context* was not: this
      // only flips MediaPlayer's looping flag, where the context rewrites the
      // player's attributes and re-prepares it mid-stream.
      await FlameAudio.bgm.audioPlayer.setReleaseMode(ReleaseMode.loop);
      _started = true;
    } catch (error) {
      debugPrint('hexcape: could not start music ($error)');
    }
  }

  /// Stops rather than pauses when the music is switched off.
  ///
  /// Pausing would leave a decoded thirty-second buffer and an open stream
  /// sitting there for a player who has said they do not want it, which is
  /// exactly the wrong reading of "off".
  Future<void> _silence() async {
    if (!_started) {
      return;
    }
    _started = false;
    try {
      await FlameAudio.bgm.stop();
    } catch (error) {
      debugPrint('hexcape: could not stop music ($error)');
    }
  }

  /// Whether the bed is currently sounding. For tests and the settings row.
  bool get playing => _started;

  Future<void> dispose() async {
    _started = false;
    _applied = -1;
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {
      // Nothing useful to do while tearing down.
    }
  }
}
