import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/haptics.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/ui/settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Player settings', () {
    test('defaults match how the game shipped before they were settable', () {
      // An existing player opening this build must not find their game
      // changed under them.
      return Progress.load().then((p) {
        expect(p.volume, 0.85);
        expect(p.haptics, isTrue);
        expect(p.music, isTrue);
        expect(p.reducedMotion, isFalse);
        expect(p.hints, isTrue);
      });
    });

    test('every setting survives a reload', () async {
      final p = await Progress.load();
      await p.setVolume(0.25);
      await p.setMusic(false);
      await p.setHaptics(false);
      await p.setReducedMotion(true);
      await p.setHints(false);
      await p.setDeveloperTools(true);

      final reopened = await Progress.load();
      expect(reopened.volume, 0.25);
      expect(reopened.music, isFalse);
      expect(reopened.haptics, isFalse);
      expect(reopened.reducedMotion, isTrue);
      expect(reopened.hints, isFalse);
      expect(reopened.developerTools, isTrue);
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

    test('the tuning panel is never shown without the setting', () {
      // It used to be added unconditionally, so every player got twenty sliders
      // and a button that erases their save. Same enforcement as the haptics
      // gate: the rule lives here rather than in a comment above the call.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final source = entity.readAsStringSync();
        var index = source.indexOf('overlays.add(Overlays.debug)');
        while (index != -1) {
          // The guard has to be close by — inside the same short method.
          final before = source.substring(index < 240 ? 0 : index - 240, index);
          if (!before.contains('developerTools')) {
            offenders.add('${entity.path} @ $index');
          }
          index = source.indexOf('overlays.add(Overlays.debug)', index + 1);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'the debug overlay is added unguarded at: '
            '${offenders.join(", ")}',
      );
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
        reason:
            'these call HapticFeedback directly instead of Haptics: '
            '${offenders.join(", ")}',
      );
    });
  });

  group('The unlock-all switch in the sheet', () {
    Future<void> open(WidgetTester tester, Progress progress) =>
        tester.pumpWidget(
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

    testWidgets('is not there for a player who has not asked for it', (
      tester,
    ) async {
      // It opens the paid campaign. A player must not be able to find it by
      // scrolling through their own settings.
      final progress = await Progress.load();
      expect(progress.developerTools, isFalse);
      await open(tester, progress);
      expect(find.text('Unlock all stages'), findsNothing);
    });

    testWidgets('nor is the switch that reveals it', (tester) async {
      // The row above it is the real leak: a player who finds "Developer tools"
      // is two taps from the whole paid campaign. Since the store listing sells
      // 80 levels, this test is guarding revenue, not tidiness.
      final progress = await Progress.load();
      await open(tester, progress);
      expect(find.text('Developer tools'), findsNothing);
    });

    testWidgets('seven taps on the title bring it back', (tester) async {
      // The panel has to stay reachable in a release build: every playtest of
      // this project is one, so compiling it out would cost more than it saves.
      final progress = await Progress.load();
      await open(tester, progress);

      final title = find.text('SETTINGS');
      for (var i = 0; i < 6; i++) {
        await tester.tap(title);
      }
      await tester.pumpAndSettle();
      expect(
        find.text('Developer tools'),
        findsNothing,
        reason: 'six taps is not seven',
      );

      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.text('Developer tools'), findsOneWidget);
    });

    testWidgets('a sheet reopened after the gesture starts hidden again', (
      tester,
    ) async {
      // The count lives in the widget state, so closing the sheet drops it.
      // Without that a player could accumulate seven taps over a week.
      final progress = await Progress.load();
      await open(tester, progress);
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.text('SETTINGS'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Developer tools'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, progress);
      expect(find.text('Developer tools'), findsNothing);
    });

    testWidgets('but stays put once the panel is actually in use', (
      tester,
    ) async {
      // Having turned it on, we should not have to tap our way back in on every
      // visit for the rest of the playtest.
      final progress = await Progress.load();
      await progress.setDeveloperTools(true);
      await open(tester, progress);
      expect(find.text('Developer tools'), findsOneWidget);
    });

    testWidgets('appears once developer tools are on, and toggles', (
      tester,
    ) async {
      final progress = await Progress.load();
      await progress.setDeveloperTools(true);
      await open(tester, progress);

      final row = find.text('Unlock all stages');
      expect(row, findsOneWidget);
      final sw = find.descendant(
        of: find.ancestor(of: row, matching: find.byType(Row)).first,
        matching: find.byType(Switch),
      );
      // Scrolled to first: the sheet is taller than a test viewport, and a
      // switch nobody can reach is not a switch.
      await tester.ensureVisible(sw);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(sw).value, isFalse);

      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(progress.unlockAllLevels, isTrue);
    });
  });
}
