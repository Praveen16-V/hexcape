// Synthesises every sound in the game into assets/audio as 16-bit mono WAVs.
//
// Run with:  dart run tool/generate_audio.dart
//
// Nothing here is a placeholder. The game's look is geometric and abstract, so
// synthesised sound is the honest match for it — and generating the tap notes
// means they can be tuned to an actual scale, which is what the streak runs on.
//
// Every dial worth turning lives in [Tuning] below, so re-tuning after hearing
// it on a phone costs one edit and one command.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// The knobs. Change these, re-run, listen.
class Tuning {
  Tuning._();

  static const sampleRate = 22050;

  /// Overall headroom. Everything is normalised then scaled by this, so nothing
  /// clips and the mix sits below the system volume.
  static const masterGain = 0.72;

  /// The streak scale: C major pentatonic, rising about an octave and a half.
  /// Pentatonic because consecutive notes cannot land on a dissonant interval,
  /// however fast the player taps — a chromatic run would sound wrong at speed.
  static const scaleHz = <double>[
    523.25, // C5
    587.33, // D5
    659.25, // E5
    783.99, // G5
    880.00, // A5
    1046.50, // C6
    1174.66, // D6
    1318.51, // E6
  ];

  /// Tap click: short and bright, with a noise transient for the attack.
  static const tapDuration = 0.16;
  static const tapDecay = 0.045;
  static const tapNoiseAmount = 0.28;

  /// The heartbeat under the low-hunger crescendo.
  static const heartbeatHz = 62.0;

  // -------------------------------------------------------------------------
  // The music bed.
  // -------------------------------------------------------------------------

  /// Seconds per bar, and how many bars the loop runs for. Sixty beats per
  /// minute leaves room for the player's tap rhythm while still giving the dog
  /// a gentle travelling pulse.
  static const musicBarSeconds = 4.0;
  static const musicBars = 8;

  /// One voiced chord per bar. The bass descends C-B-A-G-F-E-D-G while the
  /// upper voices move by small intervals; that makes the loop feel like a
  /// journey without turning it into a tune that becomes tiring on repeat.
  static const musicChords = <List<double>>[
    [130.81, 196.00, 246.94, 293.66], // Cmaj9
    [123.47, 196.00, 246.94, 329.63], // G6 / B
    [110.00, 164.81, 261.63, 392.00], // Am7
    [98.00, 164.81, 246.94, 293.66], // Em7 / G
    [87.31, 130.81, 164.81, 196.00], // Fmaj9
    [82.41, 130.81, 196.00, 261.63], // C / E
    [73.42, 110.00, 130.81, 174.61], // Dm7
    [98.00, 146.83, 196.00, 261.63], // Gsus4
  ];

  /// The lead stays below the tap streak and uses a full C-major palette. The
  /// F and B are brief passing colour; the strong notes remain pentatonic.
  static const musicMelodyHz = <double>[
    261.63, // C4
    293.66, // D4
    329.63, // E4
    349.23, // F4
    392.00, // G4
    440.00, // A4
    493.88, // B4
    523.25, // C5
  ];
}

// ---------------------------------------------------------------------------
// Synthesis primitives
// ---------------------------------------------------------------------------

final _rng = math.Random(20260904);

int get _rate => Tuning.sampleRate;

/// Percussive envelope: near-instant attack, exponential decay. [attack] is
/// kept non-zero so nothing starts on a discontinuity, which is what makes a
/// synthesised hit click unpleasantly.
double _env(double t, {double attack = 0.002, required double decay}) {
  if (t < attack) {
    return t / attack;
  }
  return math.exp(-(t - attack) / decay);
}

List<double> _tone(
  double freq,
  double seconds, {
  required double decay,
  double attack = 0.002,
  double harmonic2 = 0.0,
  double harmonic3 = 0.0,
  double freqEnd = 0,
}) {
  final n = (seconds * _rate).round();
  final out = List<double>.filled(n, 0);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    final progress = n <= 1 ? 0.0 : i / (n - 1);
    final f = freqEnd > 0 ? freq + (freqEnd - freq) * progress : freq;
    phase += 2 * math.pi * f / _rate;
    final e = _env(t, attack: attack, decay: decay);
    out[i] =
        (math.sin(phase) +
            harmonic2 * math.sin(phase * 2) +
            harmonic3 * math.sin(phase * 3)) *
        e;
  }
  return out;
}

List<double> _noise(
  double seconds, {
  required double decay,
  double attack = 0.001,
  double lowpassHz = 6000,
}) {
  final n = (seconds * _rate).round();
  final out = List<double>.filled(n, 0);
  // One-pole lowpass, so the noise reads as a material rather than as hiss.
  final dt = 1 / _rate;
  final rc = 1 / (2 * math.pi * lowpassHz);
  final alpha = dt / (rc + dt);
  var last = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    final white = _rng.nextDouble() * 2 - 1;
    last += alpha * (white - last);
    out[i] = last * _env(t, attack: attack, decay: decay);
  }
  return out;
}

List<double> _mix(List<List<double>> layers, {List<double>? gains}) {
  final length = layers.fold<int>(0, (a, b) => math.max(a, b.length));
  final out = List<double>.filled(length, 0);
  for (var l = 0; l < layers.length; l++) {
    final g = gains == null ? 1.0 : gains[l];
    final layer = layers[l];
    for (var i = 0; i < layer.length; i++) {
      out[i] += layer[i] * g;
    }
  }
  return out;
}

List<double> _sequence(List<(double offset, List<double> samples)> parts) {
  var length = 0;
  for (final part in parts) {
    length = math.max(length, (part.$1 * _rate).round() + part.$2.length);
  }
  final out = List<double>.filled(length, 0);
  for (final part in parts) {
    final start = (part.$1 * _rate).round();
    for (var i = 0; i < part.$2.length; i++) {
      out[start + i] += part.$2[i];
    }
  }
  return out;
}

/// Normalise every sound to the same peak, then drop it to the master gain.
///
/// Normalising after mixing is what makes clipping impossible: the loudest
/// sample becomes 1.0 and is then scaled down, so nothing can exceed full scale
/// no matter how many layers a sound has.
List<double> _finish(List<double> samples) {
  var peak = 0.0;
  for (final s in samples) {
    peak = math.max(peak, s.abs());
  }
  if (peak < 1e-9) {
    return samples;
  }
  return [for (final s in samples) s / peak * Tuning.masterGain];
}

Uint8List _wav(List<double> samples) {
  final dataBytes = samples.length * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, _rate, Endian.little);
  bytes.setUint32(28, _rate * 2, Endian.little); // byte rate
  bytes.setUint16(32, 2, Endian.little); // block align
  bytes.setUint16(34, 16, Endian.little); // bits
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(44 + i * 2, v, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// The sounds
// ---------------------------------------------------------------------------

/// One rung of the streak scale: a bright pluck with a click on the front.
List<double> tapNote(double hz) => _mix(
  [
    _tone(
      hz,
      Tuning.tapDuration,
      decay: Tuning.tapDecay,
      harmonic2: 0.3,
      harmonic3: 0.12,
    ),
    _noise(0.012, decay: 0.004, lowpassHz: 9000),
  ],
  gains: [1.0, Tuning.tapNoiseAmount],
);

/// A heavy hex refusing to break the first time: same gesture as a tap, an
/// octave down and choked, so it reads as *that tile held* rather than as a
/// missed input.
List<double> crack() => _mix(
  [
    _tone(196, 0.14, decay: 0.035, harmonic2: 0.5, harmonic3: 0.3),
    _noise(0.05, decay: 0.02, lowpassHz: 2600),
  ],
  gains: [0.8, 0.7],
);

/// Tapping an anchor. Dead, low, and over immediately — nothing gave.
List<double> thunk() => _mix(
  [
    _tone(92, 0.1, decay: 0.022, harmonic2: 0.2),
    _noise(0.035, decay: 0.012, lowpassHz: 900),
  ],
  gains: [1.0, 0.5],
);

/// The pulse before a hex closes. Soft and high so it warns without nagging.
List<double> warn() => _tone(1244, 0.07, decay: 0.022, attack: 0.006);

/// A hex snapping shut: pitch falling as it seals.
List<double> snap() => _mix(
  [
    _tone(880, 0.09, decay: 0.03, freqEnd: 320),
    _noise(0.045, decay: 0.014, lowpassHz: 4200),
  ],
  gains: [0.9, 0.55],
);

/// Treat: a quick two-note lift.
List<double> treat() => _sequence([
  (0.0, _tone(880, 0.13, decay: 0.05, harmonic2: 0.25)),
  (0.075, _tone(1318.51, 0.18, decay: 0.07, harmonic2: 0.25)),
]);

/// Powerup: three notes, a plain major arpeggio so it reads as clearly good.
List<double> powerup() => _sequence([
  (0.0, _tone(523.25, 0.14, decay: 0.05)),
  (0.065, _tone(659.25, 0.14, decay: 0.05)),
  (0.13, _tone(783.99, 0.26, decay: 0.09, harmonic2: 0.3)),
]);

/// Dinner. Two crunches and a contented note underneath.
List<double> chomp() => _sequence([
  (0.0, _noise(0.09, decay: 0.03, lowpassHz: 3200)),
  (0.11, _noise(0.1, decay: 0.035, lowpassHz: 2600)),
  (0.12, _tone(392, 0.4, decay: 0.16, harmonic2: 0.4, harmonic3: 0.15)),
]);

/// Out of steam: a slow sag.
List<double> starve() =>
    _tone(440, 0.6, decay: 0.28, attack: 0.02, freqEnd: 196, harmonic2: 0.2);

/// The field closing over her.
List<double> crush() => _mix(
  [
    _noise(0.45, decay: 0.16, lowpassHz: 700),
    _tone(70, 0.45, decay: 0.18, harmonic2: 0.35),
  ],
  gains: [0.7, 1.0],
);

/// A bark.
///
/// The first attempt was two swept tones and sounded like a swanee whistle,
/// because a bark is not a tone with a pitch bend. Three things make it read as
/// an animal:
///
/// * a **noise transient** on the front — the burst of air before any pitch
///   exists at all, which is most of what the ear identifies;
/// * a **rich harmonic body**, since vocal folds produce a buzz nearer a sawtooth
///   than a sine, so the harmonics have to be strong and many;
/// * a **fast pitch arc** that rises and falls inside a tenth of a second, with
///   most of the energy on the way down.
///
/// Formant shaping — the resonances a mouth and throat impose on that buzz — is
/// approximated by mixing two band-limited noise layers over the harmonics. This
/// is a good deal closer than a swept tone. Whether it is *close enough* is not
/// something I can judge without ears.
List<double> bark() {
  final body = <double>[];
  final n = (0.17 * _rate).round();
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    final u = i / n;
    // Up fast, down slower: the shape of a single "ruff".
    final f = u < 0.18
        ? 340 + 300 * (u / 0.18)
        : 640 - 330 * ((u - 0.18) / 0.82);
    var phase = 0.0;
    phase = 2 * math.pi * f * t;
    // Many harmonics at falling amplitude, which is a buzz rather than a hum.
    var v = 0.0;
    for (var h = 1; h <= 9; h++) {
      v += math.sin(phase * h) / h;
    }
    final env = u < 0.06 ? u / 0.06 : math.exp(-(u - 0.06) * 6.5);
    body.add(v * env);
  }

  return _sequence([
    // The air before the voice.
    (0.0, _noise(0.035, decay: 0.012, lowpassHz: 5200)),
    (0.0, body),
    // Two formant-ish bands over the top, standing in for a mouth.
    (0.005, _noise(0.09, decay: 0.035, lowpassHz: 1100)),
    (0.005, _noise(0.07, decay: 0.028, lowpassHz: 2600)),
  ]);
}

/// Tired and unhappy.
List<double> whimper() =>
    _tone(620, 0.34, decay: 0.15, attack: 0.03, freqEnd: 400, harmonic2: 0.18);

/// Lub-dub. Played on a timer that tightens as she tires.
List<double> heartbeat() => _sequence([
  (0.0, _tone(Tuning.heartbeatHz, 0.13, decay: 0.045, attack: 0.004)),
  (0.16, _tone(Tuning.heartbeatHz * 0.85, 0.16, decay: 0.055, attack: 0.004)),
]);

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// The music bed
// ---------------------------------------------------------------------------

/// Adds [samples] into [out] at [offset] seconds, **wrapping past the end**.
///
/// The wrap is the entire trick behind a seamless loop. A note struck near the
/// end of the last bar has a two-second tail; written normally that tail is
/// either truncated — a click every time the loop repeats — or it lengthens
/// the file so the loop no longer lines up with the bar. Folding it back onto
/// the opening instead means the tail is *already playing* when the loop
/// restarts, which is exactly what it would be doing if the music simply
/// carried on. There is no seam to hear because there is no seam.
void _addWrapped(List<double> out, double offset, List<double> samples) {
  if (out.isEmpty) return;
  final start = (offset * _rate).round();
  for (var i = 0; i < samples.length; i++) {
    out[(start + i) % out.length] += samples[i];
  }
}

/// A warm sustained voice built from two slightly detuned fundamentals, an
/// octave and a quiet fifth. Their slow beating gives the bed movement without
/// the brittle organ quality of stacked plain sine waves.
List<double> _warmPad(double freq, double seconds, {double colour = 0}) {
  final n = (seconds * _rate).round();
  final out = List<double>.filled(n, 0);
  final attack = math.min(1.15, seconds * 0.30);
  final release = math.min(1.8, seconds * 0.40);
  var phaseA = 0.0;
  var phaseB = 0.0;
  var phaseOctave = 0.0;
  var phaseFifth = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    final double e;
    if (t < attack) {
      e = 0.5 - 0.5 * math.cos(math.pi * t / attack);
    } else if (t > seconds - release) {
      final u = (seconds - t) / release;
      e = 0.5 - 0.5 * math.cos(math.pi * u.clamp(0.0, 1.0));
    } else {
      e = 1.0;
    }
    final drift = math.sin(t * 0.47 + colour) * 0.0012;
    phaseA += 2 * math.pi * freq * (0.997 + drift) / _rate;
    phaseB += 2 * math.pi * freq * (1.003 - drift) / _rate;
    phaseOctave += 2 * math.pi * freq * 2.001 / _rate;
    phaseFifth += 2 * math.pi * freq * 1.498 / _rate;
    final shimmer = 0.82 + 0.18 * math.sin(t * 0.71 + colour * 2);
    out[i] =
        (0.48 * math.sin(phaseA) +
            0.44 * math.sin(phaseB) +
            0.13 * shimmer * math.sin(phaseOctave) +
            0.09 * math.sin(phaseFifth)) *
        e;
  }
  return out;
}

/// A round nylon-string pluck. Independent partial decays remove the electronic
/// 'beep' of a single oscillator and leave a soft wooden attack.
List<double> _nylonPluck(double freq, {double seconds = 1.65}) {
  final n = (seconds * _rate).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    final attack = (t / 0.008).clamp(0.0, 1.0);
    final fundamental = math.sin(2 * math.pi * freq * t) * math.exp(-t * 2.15);
    final second =
        math.sin(2 * math.pi * freq * 2.01 * t + 0.25) * math.exp(-t * 4.2);
    final third =
        math.sin(2 * math.pi * freq * 3.02 * t + 0.7) * math.exp(-t * 7.0);
    out[i] = attack * (fundamental * 0.78 + second * 0.24 + third * 0.09);
  }
  final finger = _noise(0.028, decay: 0.008, lowpassHz: 2600);
  for (var i = 0; i < finger.length; i++) {
    out[i] += finger[i] * 0.11;
  }
  return out;
}

/// Bell-like lead with inharmonic upper partials and a soft mallet transient.
List<double> _kalimba(double freq, {double seconds = 2.4}) {
  final n = (seconds * _rate).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    final attack = (t / 0.006).clamp(0.0, 1.0);
    out[i] =
        attack *
        (math.sin(2 * math.pi * freq * t) * math.exp(-t * 1.75) +
            0.26 *
                math.sin(2 * math.pi * freq * 2.73 * t + 0.4) *
                math.exp(-t * 5.4) +
            0.12 *
                math.sin(2 * math.pi * freq * 4.08 * t + 1.1) *
                math.exp(-t * 8.0));
  }
  return out;
}

List<double> _warmBass(double freq) {
  final n = (2.5 * _rate).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    final e = (t / 0.035).clamp(0.0, 1.0) * math.exp(-t * 1.15);
    out[i] =
        (math.sin(2 * math.pi * freq * t) +
            0.22 * math.sin(2 * math.pi * freq * 2 * t)) *
        e;
  }
  return out;
}

List<double> _handDrum({double accent = 1}) => _mix(
  [
    _tone(92, 0.34, decay: 0.095, attack: 0.004, freqEnd: 58),
    _noise(0.075, decay: 0.022, lowpassHz: 1250),
  ],
  gains: [0.72 * accent, 0.16 * accent],
);

List<double> _brush() => _mix(
  [
    _noise(0.12, decay: 0.035, attack: 0.008, lowpassHz: 5200),
    _tone(310, 0.08, decay: 0.022, attack: 0.004),
  ],
  gains: [0.24, 0.035],
);

/// Adds a quiet wrapped room tail. Wrapping is essential: a conventional echo
/// would be cut off at the file boundary and expose the loop every 32 seconds.
void _room(List<double> out, List<double> source) {
  for (final echo in const [(0.19, 0.12), (0.37, 0.075), (0.61, 0.045)]) {
    final delay = (echo.$1 * _rate).round();
    for (var i = 0; i < source.length; i++) {
      out[(i + delay) % out.length] += source[i] * echo.$2;
    }
  }
}

double _softClip(double sample) {
  final e = math.exp(sample * 2);
  return (e - 1) / (e + 1);
}

/// The looping bed.
///
/// A warm, quietly adventurous eight-bar loop: breathing strings, a travelling
/// nylon ostinato, rounded bass, restrained hand percussion, and a short
/// kalimba answer. The arrangement grows across the loop and thins again before
/// the seam, giving it shape without competing with play.
List<double> music() {
  final barSeconds = Tuning.musicBarSeconds;
  final total = barSeconds * Tuning.musicBars;
  final n = (total * _rate).round();
  final pads = List<double>.filled(n, 0);
  final bass = List<double>.filled(n, 0);
  final strings = List<double>.filled(n, 0);
  final lead = List<double>.filled(n, 0);
  final percussion = List<double>.filled(n, 0);

  const arpeggio = [0, 2, 1, 3, 2, 1, 3, 2];
  for (var c = 0; c < Tuning.musicChords.length; c++) {
    final at = c * barSeconds;
    final voices = Tuning.musicChords[c];
    for (var v = 0; v < voices.length; v++) {
      _addWrapped(
        pads,
        at - 0.16 + v * 0.045,
        _warmPad(voices[v], barSeconds * 1.32, colour: c + v * 0.4),
      );
    }
    _addWrapped(bass, at, _warmBass(voices.first / 2));
    _addWrapped(bass, at + barSeconds / 2, _warmBass(voices.first / 2));

    // The first bar is intentionally open; the picked pattern arrives once the
    // harmony is established and becomes lighter again at the cadence.
    if (c > 0) {
      for (var step = 0; step < arpeggio.length; step++) {
        var hz = voices[arpeggio[(step + c) % arpeggio.length]];
        while (hz < 185) {
          hz *= 2;
        }
        final human = ((c * 17 + step * 11) % 7 - 3) * 0.004;
        _addWrapped(
          strings,
          at + step * barSeconds / 8 + human,
          _nylonPluck(hz),
        );
      }
    }

    if (c >= 2 && c <= 6) {
      _addWrapped(percussion, at, _handDrum(accent: c == 4 ? 1.15 : 1));
      _addWrapped(percussion, at + barSeconds / 2, _handDrum(accent: 0.72));
      for (var beat = 1; beat < 8; beat += 2) {
        _addWrapped(percussion, at + beat * barSeconds / 8, _brush());
      }
    }
  }

  // Two short call-and-response phrases, with rests doing as much work as the
  // notes. The last bar is melody-free so the return to bar one can breathe.
  const phrase = <(int, double, int, double)>[
    (1, 1.0, 4, 0.78),
    (1, 2.5, 5, 0.66),
    (2, 0.5, 7, 0.88),
    (2, 2.0, 5, 0.62),
    (3, 1.0, 4, 0.72),
    (4, 0.5, 2, 0.68),
    (4, 1.5, 3, 0.58),
    (4, 2.5, 4, 0.80),
    (5, 0.5, 5, 0.74),
    (5, 2.0, 7, 0.92),
    (6, 0.5, 4, 0.70),
    (6, 2.0, 1, 0.62),
    (6, 3.0, 0, 0.78),
  ];
  for (final note in phrase) {
    final at = note.$1 * barSeconds + note.$2 * (barSeconds / 4);
    final voice = _kalimba(Tuning.musicMelodyHz[note.$3]);
    _addWrapped(lead, at, [for (final sample in voice) sample * note.$4]);
  }

  final room = List<double>.filled(n, 0);
  _room(room, strings);
  _room(room, lead);

  final mixed = _mix(
    [pads, bass, strings, lead, percussion, room],
    gains: [0.22, 0.25, 0.20, 0.17, 0.16, 0.55],
  );
  // A very gentle tape-like rounding catches stacked attacks while preserving
  // the quiet detail. `_finish` still owns the final peak and headroom.
  final ceiling = _softClip(1.18);
  return [for (final sample in mixed) _softClip(sample * 1.18) / ceiling];
}

void main() {
  final dir = Directory('assets/audio');
  dir.createSync(recursive: true);

  final sounds = <String, List<double>>{
    for (var i = 0; i < Tuning.scaleHz.length; i++)
      'tap_${i.toString().padLeft(2, '0')}': tapNote(Tuning.scaleHz[i]),
    'crack': crack(),
    'thunk': thunk(),
    'warn': warn(),
    'snap': snap(),
    'treat': treat(),
    'powerup': powerup(),
    'chomp': chomp(),
    'starve': starve(),
    'crush': crush(),
    'bark': bark(),
    'whimper': whimper(),
    'heartbeat': heartbeat(),
    'music_theme': music(),
  };

  var total = 0;
  for (final entry in sounds.entries) {
    final bytes = _wav(_finish(entry.value));
    File('${dir.path}/${entry.key}.wav').writeAsBytesSync(bytes);
    total += bytes.length;
    stdout.writeln(
      '${entry.key.padRight(12)} '
      '${(entry.value.length / _rate * 1000).round().toString().padLeft(4)}ms  '
      '${(bytes.length / 1024).toStringAsFixed(1)}KB',
    );
  }
  stdout.writeln(
    '\n${sounds.length} files, ${(total / 1024).toStringAsFixed(1)}KB total',
  );
}
