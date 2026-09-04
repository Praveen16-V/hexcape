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
