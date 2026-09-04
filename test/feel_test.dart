import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/audio/sfx.dart';
import 'package:hexcape/game/juice.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/systems/streak_system.dart';

/// A straight corridor of plain cells, so "closer to the bone" is unambiguous.
HexGrid _field({HexCoord exit = const HexCoord(0, -6), int radius = 6}) {
  final coords = HexCoord.zero.disc(radius);
  return HexGrid(
    cells: {for (final c in coords) c: HexCell(c, HexType.plain)},
    start: HexCoord.zero,
    exit: exit,
    truePath: [HexCoord.zero, exit],
  );
}

void main() {
  group('StreakSystem', () {
    test('climbs on taps that close the gap to the bone', () {
      final grid = _field();
      final streak = StreakSystem();

      for (var i = 1; i <= 4; i++) {
        final outcome = streak.register(
          grid: grid,
          tapped: HexCoord(0, -i),
          dogCell: HexCoord(0, -i + 1),
          carved: true,
        );
        expect(outcome, StreakOutcome.advanced);
        expect(streak.streak, i);
      }
      expect(streak.best, 4);
    });

    test('a sideways carve breaks the chain', () {
      final grid = _field();
      final streak = StreakSystem()
        ..register(
          grid: grid,
          tapped: const HexCoord(0, -1),
          dogCell: HexCoord.zero,
          carved: true,
        );
      expect(streak.streak, 1);

      // Same distance from the bone: progress in no direction that matters.
      final outcome = streak.register(
        grid: grid,
        tapped: const HexCoord(1, 0),
        dogCell: HexCoord.zero,
        carved: true,
      );
      expect(outcome, StreakOutcome.broken);
      expect(streak.streak, 0);
      expect(streak.best, 1, reason: 'the best so far still stands');
    });

    test('a tap that carves nothing is wasted, not merely broken', () {
      final grid = _field();
      final streak = StreakSystem()
        ..register(
          grid: grid,
          tapped: const HexCoord(0, -1),
          dogCell: HexCoord.zero,
          carved: true,
        );

      final outcome = streak.register(
        grid: grid,
        tapped: const HexCoord(0, -1),
        dogCell: HexCoord.zero,
        carved: false,
      );
      expect(outcome, StreakOutcome.wasted);
      expect(streak.streak, 0);
    });

    test('a cell closer only through a wall does not count', () {
      // Straight hex distance would reward carving into an anchor face just
      // because the bone lies beyond it. The chain uses the anchor-aware field
      // the dog actually steers on.
      final grid = _field();
      for (final cell in grid.all) {
        if (cell.coord.r == -2) {
          cell.type = HexType.anchor;
        }
      }
      final streak = StreakSystem();

      final outcome = streak.register(
        grid: grid,
        tapped: const HexCoord(0, -1),
        dogCell: HexCoord.zero,
        carved: true,
      );
      expect(
        outcome,
        StreakOutcome.broken,
        reason: 'that direction is sealed, so it is not progress',
      );
    });

    test('intensity rises with the chain and then saturates', () {
      // A corridor long enough to actually chain ten taps down; walking off the
      // edge of the board would break the chain rather than extend it.
      final grid = _field(exit: const HexCoord(0, -12), radius: 12);
      final streak = StreakSystem();
      expect(streak.intensity, 0);

      for (var i = 1; i <= 4; i++) {
        streak.register(
          grid: grid,
          tapped: HexCoord(0, -i),
          dogCell: HexCoord(0, -i + 1),
          carved: true,
        );
      }
      expect(streak.intensity, closeTo(0.5, 1e-9));

      for (var i = 5; i <= 12; i++) {
        streak.register(
          grid: grid,
          tapped: HexCoord(0, -i),
          dogCell: HexCoord(0, -i + 1),
          carved: true,
        );
      }
      expect(streak.intensity, 1.0);
    });
  });

  group('Sfx note selection', () {
    test('walks up the scale and then holds at the top', () {
      expect(Sfx.noteFor(0), 0);
      expect(Sfx.noteFor(3), 3);
      expect(Sfx.noteFor(Sfx.noteCount - 1), Sfx.noteCount - 1);
      // Never wraps: a chain that restarted the scale would sound like a
      // mistake rather than an achievement.
      expect(Sfx.noteFor(50), Sfx.noteCount - 1);
      expect(Sfx.noteFor(-3), 0);
    });
  });

  group('Sfx cue gating', () {
    test('cues still fire when the volume is down', () {
      // Haptics are paired with these cues. Muting the game must not silently
      // remove half its feedback, so the gate has to be about throttling, not
      // about whether a sound came out.
      final sfx = Sfx()..volume = 0;
      expect(sfx.play(Sound.snap), isTrue);
      expect(sfx.play(Sound.warn), isTrue);
    });

    test('the throttle applies whether audible or not', () {
      final sfx = Sfx()..volume = 0;
      expect(sfx.play(Sound.warn, minInterval: 0.4), isTrue);
      expect(
        sfx.play(Sound.warn, minInterval: 0.4),
        isFalse,
        reason: 'a second cue inside the window must be suppressed',
      );

      sfx.tick(0.5);
      expect(sfx.play(Sound.warn, minInterval: 0.4), isTrue);
    });

    test('muting the field keeps its haptic cue firing', () {
      // The whole point of the split: regrowth is felt but not heard. If muting
      // a group also swallowed its cue, the warning haptic (§11) would vanish
      // along with the sound.
      final sfx = Sfx()
        ..volume = 0.85
        ..mutedGroups = const {SoundGroup.field};

      expect(sfx.play(Sound.warn), isTrue);
      expect(sfx.play(Sound.snap), isTrue);
    });

    test('sounds are grouped so the right things mute together', () {
      // Crack and thunk answer a tap and belong with the notes, not with the
      // field acting on its own.
      expect(Sound.crack.group, SoundGroup.tap);
      expect(Sound.thunk.group, SoundGroup.tap);
      expect(Sound.warn.group, SoundGroup.field);
      expect(Sound.snap.group, SoundGroup.field);
      expect(Sound.heartbeat.group, SoundGroup.ambient);
      expect(Sound.chomp.group, SoundGroup.event);
      expect(Sound.bark.group, SoundGroup.event);
    });

    test('one sound throttling never gates another', () {
      final sfx = Sfx()..volume = 0;
      expect(sfx.play(Sound.warn, minInterval: 0.4), isTrue);
      expect(sfx.play(Sound.snap, minInterval: 0.4), isTrue);
    });
  });

  group('Heartbeat', () {
    test('stays silent while she is comfortable', () {
      final beat = Heartbeat();
      var beats = 0;
      for (var i = 0; i < 60 * 10; i++) {
        if (beat.update(1 / 60, 0.9)) {
          beats++;
        }
      }
      expect(beats, 0, reason: 'the early game should keep its calm');
    });

    test('quickens monotonically as the bar empties', () {
      var previous = double.infinity;
      for (final fraction in [0.55, 0.45, 0.35, 0.25, 0.15, 0.05, 0.0]) {
        final interval = Heartbeat.intervalAt(fraction);
        expect(interval, lessThanOrEqualTo(previous), reason: '$fraction');
        previous = interval;
      }
      expect(Heartbeat.intervalAt(0), closeTo(Heartbeat.fastestInterval, 1e-9));
    });

    test('and gets louder as it gets faster', () {
      expect(Heartbeat.gainAt(0.1), greaterThan(Heartbeat.gainAt(0.5)));
      expect(Heartbeat.gainAt(0.0), lessThanOrEqualTo(1.0));
    });

    test('beats roughly at the interval it advertises', () {
      final beat = Heartbeat();
      const fraction = 0.2;
      var beats = 0;
      const seconds = 20.0;
      for (var i = 0; i < seconds * 60; i++) {
        if (beat.update(1 / 60, fraction)) {
          beats++;
        }
      }
      final expected = seconds / Heartbeat.intervalAt(fraction);
      expect(beats, closeTo(expected, 2));
    });
  });

  group('Juice', () {
    test('hit-stop stops the simulation and then hands time back', () {
      final juice = Juice()..freeze(0.05);
      expect(juice.isFrozen, isTrue);
      expect(juice.consume(1 / 60), 0, reason: 'frozen frames advance nothing');

      for (var i = 0; i < 5; i++) {
        juice.consume(1 / 60);
      }
      expect(juice.isFrozen, isFalse);
      expect(juice.consume(1 / 60), closeTo(1 / 60, 1e-9));
    });

    test('shake decays away rather than rattling for ever', () {
      final juice = Juice()..shake(10);
      expect(juice.shakeAmount, 10);

      for (var i = 0; i < 60; i++) {
        juice.consume(1 / 60);
      }
      expect(juice.shakeAmount, 0);
      expect(juice.offset, Offset.zero);
    });

    test('scale of zero disables both, for anyone who wants it still', () {
      final juice = Juice(scale: 0)
        ..shake(20)
        ..freeze(0.2);
      expect(juice.shakeAmount, 0);
      expect(juice.isFrozen, isFalse);
      expect(juice.consume(1 / 60), closeTo(1 / 60, 1e-9));
    });

    test('a bigger shake wins over a smaller one already running', () {
      final juice = Juice()
        ..shake(3)
        ..shake(9);
      expect(juice.shakeAmount, 9);
      juice.shake(2);
      expect(
        juice.shakeAmount,
        9,
        reason: 'a small kick must not damp a big one',
      );
    });
  });

  group('Generated audio', () {
    // The one property of sound that can be checked without ears: that every
    // file the game asks for exists, is a well-formed 16-bit mono WAV, and
    // actually contains signal. Whether it sounds *good* is not testable here
    // and is not pretended to be.
    final expected = <String>[
      for (var i = 0; i < Sfx.noteCount; i++)
        'tap_${i.toString().padLeft(2, '0')}',
      for (final sound in Sound.values) sound.name,
    ];

    test('every sound the game references has a file', () {
      for (final name in expected) {
        expect(
          File('assets/audio/$name.wav').existsSync(),
          isTrue,
          reason: '$name.wav is missing — run tool/generate_audio.dart',
        );
      }
    });

    test('each one is a valid mono 16-bit WAV carrying real signal', () {
      for (final name in expected) {
        final bytes = File('assets/audio/$name.wav').readAsBytesSync();
        expect(bytes.length, greaterThan(44), reason: name);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF', reason: name);
        expect(
          String.fromCharCodes(bytes.sublist(8, 12)),
          'WAVE',
          reason: name,
        );

        final view = ByteData.sublistView(bytes);
        expect(view.getUint16(22, Endian.little), 1, reason: '$name channels');
        expect(view.getUint16(34, Endian.little), 16, reason: '$name bits');
        expect(
          view.getUint32(40, Endian.little),
          bytes.length - 44,
          reason: '$name data chunk size disagrees with the file',
        );

        var peak = 0;
        for (var i = 44; i + 1 < bytes.length; i += 2) {
          final sample = view.getInt16(i, Endian.little).abs();
          if (sample > peak) {
            peak = sample;
          }
        }
        expect(peak, greaterThan(3000), reason: '$name is silent or near it');
        expect(peak, lessThanOrEqualTo(32767), reason: '$name clips');
      }
    });
  });
}
