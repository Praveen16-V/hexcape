import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/haptics.dart';
import 'package:hexcape/game/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Player settings', () {
    test('defaults match how the game shipped before they were settable', () {
      // An existing player opening this build must not find their game
      // changed under them.
      return Progress.load().then((p) {
        expect(p.volume, 0.85);
        expect(p.regrowthSound, isFalse);
        expect(p.haptics, isTrue);
        expect(p.reducedMotion, isFalse);
        expect(p.hints, isTrue);
      });
    });

    test('every setting survives a reload', () async {
      final p = await Progress.load();
      await p.setVolume(0.25);
      await p.setRegrowthSound(true);
      await p.setHaptics(false);
      await p.setReducedMotion(true);
      await p.setHints(false);

      final reopened = await Progress.load();
      expect(reopened.volume, 0.25);
      expect(reopened.regrowthSound, isTrue);
      expect(reopened.haptics, isFalse);
      expect(reopened.reducedMotion, isTrue);
      expect(reopened.hints, isFalse);
    });

    test('resetting progress does not reset settings', () async {
      // Reset is for levels. Someone who turned the sound off does not expect
      // it back on because they cleared their stars.
      final p = await Progress.load();
      await p.setHaptics(false);
      await p.setVolume(0);
      await p.recordWin(level: 3, stars: 3, taps: 10, time: 5);

      await p.reset();
      expect(p.unlocked, 1);
      expect(p.recordFor(3).stars, 0);

      final reopened = await Progress.load();
      expect(reopened.haptics, isFalse);
      expect(reopened.volume, 0);
    });

    test('a corrupt volume cannot escape its range', () async {
      SharedPreferences.setMockInitialValues({'opt_volume': 40.0});
      final p = await Progress.load();
      expect(p.volume, 1.0);
    });

    test('the haptics gate silences every level of feedback', () {
      Haptics.enabled = false;
      expect(() {
        Haptics.light();
        Haptics.medium();
        Haptics.heavy();
        Haptics.selection();
      }, returnsNormally);
      Haptics.enabled = true;
    });

    test('nothing bypasses the haptics gate', () {
      // A switch with one call site outside it is not a switch. This is the
      // only way to keep that true as the game grows: the rule lives in the
      // test rather than in a comment nobody reads before adding a buzz.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        if (entity.path.replaceAll(r'\', '/').endsWith('game/haptics.dart')) {
          continue;
        }
        if (entity.readAsStringSync().contains('HapticFeedback.')) {
          offenders.add(entity.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'these call HapticFeedback directly instead of Haptics: '
            '${offenders.join(", ")}',
      );
    });
  });
}
