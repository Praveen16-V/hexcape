import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/audio/music.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/ui/settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The generated loop, read straight off disk.
///
/// A build artefact rather than a hand-made asset — `tool/generate_audio.dart`
/// writes it — so these tests check the properties the synthesis is *for*,
/// which is the only thing that would notice if a tuning change quietly
/// wrecked it.
({int rate, List<int> samples}) _readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
  final channels = data.getUint16(22, Endian.little);
  final rate = data.getUint32(24, Endian.little);
  final bits = data.getUint16(34, Endian.little);
  expect(channels, 1, reason: 'the loop is mono');
  expect(bits, 16);
  final count = data.getUint32(40, Endian.little) ~/ 2;
  return (
    rate: rate,
    samples: [
      for (var i = 0; i < count; i++) data.getInt16(44 + i * 2, Endian.little),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('The generated loop', () {
    test('exists, is mono, and runs a whole number of bars', () {
      final file = File('assets/audio/$kMusicAsset');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run: dart run tool/generate_audio.dart',
      );
      final wav = _readWav(file.path);
      final seconds = wav.samples.length / wav.rate;
      expect(
        seconds,
        greaterThan(20),
        reason: 'short enough to notice looping',
      );
      // 8 bars of 4 seconds. A loop that is not a whole number of bars puts
      // the melody's first note on a different beat every time round.
      expect(seconds % 4, closeTo(0, 0.01));
    });

    test('joins to itself without a click', () {
      // The property the wrap-around in `_addWrapped` exists to create, and the
      // one thing about this file a listener would certainly notice if it
      // broke: a step at the loop point is an audible tick, once every pass,
      // forever.
      final wav = _readWav('assets/audio/$kMusicAsset');
      final s = wav.samples;

      // How far the waveform normally travels between one sample and the next.
      final deltas = <int>[
        for (var i = 0; i + 1 < s.length; i += 7) (s[i + 1] - s[i]).abs(),
      ]..sort();
      final worstInside = deltas.last;
      final seam = (s.first - s.last).abs();

      expect(
        seam,
        lessThan(worstInside),
        reason:
            'the join jumps $seam, more than the $worstInside the waveform '
            'ever moves inside the file — that is an audible click',
      );
    });

    test('leaves headroom and never clips', () {
      final wav = _readWav('assets/audio/$kMusicAsset');
      var peak = 0;
      for (final sample in wav.samples) {
        if (sample.abs() > peak) peak = sample.abs();
      }
      expect(peak, lessThan(32767), reason: 'the master gain was exceeded');
      expect(
        peak,
        greaterThan(16000),
        reason: 'so quiet that the 16-bit floor is audible as hiss',
      );
    });
  });

  group('The music bed', () {
    test('is silent when switched off, whatever the volume', () {
      final music = Music()
        ..enabled = false
        ..volume = 1.0;
      expect(music.target, 0);
    });

    test('is silent when the volume is down, whatever the switch', () {
      final music = Music()
        ..enabled = true
        ..volume = 0;
      expect(music.target, 0);
    });

    test('steps back during a level and returns in the menus', () {
      final music = Music()
        ..enabled = true
        ..volume = 1.0;
      final menu = music.target;
      music.inLevel = true;
      final level = music.target;

      expect(menu, greaterThan(0));
      expect(
        level,
        lessThan(menu),
        reason: 'the bed did not get out of the tap scale\'s way',
      );
      expect(level, greaterThan(0), reason: 'ducking is not muting');
      expect(level / menu, closeTo(Music.duckedFraction, 1e-9));
    });

    test('follows the master volume', () {
      final loud = Music()..volume = 1.0;
      final quiet = Music()..volume = 0.25;
      expect(quiet.target, closeTo(loud.target * 0.25, 1e-9));
    });
  });

  group('The setting', () {
    test('defaults to on, and survives a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await Progress.load();
      expect(p.music, isTrue, reason: 'music should be on out of the box');
      await p.setMusic(false);
      expect((await Progress.load()).music, isFalse);
    });

    test('is not wiped by resetting progress', () async {
      // Settings are deliberately not progress. Someone who turned the music
      // off does not expect it back on because they cleared their levels.
      SharedPreferences.setMockInitialValues({});
      final p = await Progress.load();
      await p.setMusic(false);
      await p.reset();
      expect((await Progress.load()).music, isFalse);
    });

    testWidgets('can be switched off from the settings page', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final progress = await Progress.load();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsSheet(
                progress: progress,
                onChanged: () {},
                onRestore: null,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Music'), findsOneWidget);
      final toggle = find.descendant(
        of: find
            .ancestor(of: find.text('Music'), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      );
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(progress.music, isFalse, reason: 'the toggle did not stick');
    });
  });
}
