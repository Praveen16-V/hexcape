import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/ui/level_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('each campaign beat is explained before play', (tester) async {
    SharedPreferences.setMockInitialValues({
      'unlocked': Campaign.length + 1,
      'owns_full': true,
    });
    final progress = await Progress.load();
    const examples = {
      9: LevelPace.introduction,
      10: LevelPace.practice,
      11: LevelPace.combination,
      12: LevelPace.challenge,
      13: LevelPace.breather,
    };
    for (final entry in examples.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LevelDetail(
              level: entry.key,
              progress: progress,
              inProgress: false,
              onPlay:
                  ({required zen, required difficulty, required restart}) {},
              onUnlock: () {},
            ),
          ),
        ),
      );
      expect(
        find.textContaining(entry.value.label.toUpperCase()),
        findsOneWidget,
      );
      expect(find.textContaining(entry.value.description), findsOneWidget);
      expect(find.text('${entry.value.label} pace'), findsOneWidget);
      expect(find.text(Campaign.identityFor(entry.key).title), findsOneWidget);
      expect(
        find.textContaining(
          Campaign.identityFor(entry.key).signature.description,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('pace explanation remains usable on a narrow large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'unlocked': Campaign.length + 1,
      'owns_full': true,
    });
    final progress = await Progress.load();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: LevelDetail(
              level: Campaign.length,
              progress: progress,
              inProgress: false,
              onPlay:
                  ({required zen, required difficulty, required restart}) {},
              onUnlock: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('CHALLENGE'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
