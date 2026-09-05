import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/ui/level_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Campaign identity', () {
    test('all sixty levels have unique authored names', () {
      final names = {
        for (var level = 1; level <= Campaign.length; level++)
          Campaign.identityFor(level).title,
      };
      expect(names.length, Campaign.length);
    });

    test('the authored signature cadence covers each gameplay focus', () {
      expect(Campaign.signatureFor(1), LevelSignature.lesson);
      expect(Campaign.signatureFor(6), LevelSignature.openTrail);
      expect(Campaign.signatureFor(7), LevelSignature.closingTrail);
      expect(Campaign.signatureFor(11), LevelSignature.heavyGround);
      expect(Campaign.signatureFor(14), LevelSignature.springLine);
      expect(Campaign.signatureFor(32), LevelSignature.nightWatch);
      expect(Campaign.signatureFor(34), LevelSignature.supplyRun);
      expect(Campaign.signatureFor(41), LevelSignature.breach);
      expect(Campaign.signatureFor(60), LevelSignature.gauntlet);
    });

    test('signatures produce the gameplay promise in their rules', () {
      final open = Campaign.rulesFor(6);
      final closing = Campaign.rulesFor(7);
      final heavy = Campaign.rulesFor(11);
      final spring = Campaign.rulesFor(14);
      final watch = Campaign.rulesFor(32);
      final supply = Campaign.rulesFor(34);
      final breach = Campaign.rulesFor(41);

      expect(open.anchorDensity, lessThan(Campaign.rulesFor(8).anchorDensity));
      expect(closing.offeredPowerups, contains(PickupKind.freeze));
      expect(
        heavy.heavyDensity,
        greaterThan(Campaign.rulesFor(10).heavyDensity),
      );
      expect(
        spring.springDensity,
        greaterThan(Campaign.rulesFor(13).springDensity),
      );
      expect(watch.guards, greaterThan(Campaign.rulesFor(31).guards));
      expect(
        supply.treats + supply.powerups,
        greaterThan(
          Campaign.rulesFor(33).treats + Campaign.rulesFor(33).powerups,
        ),
      );
      expect(breach.offeredPowerups.first, PickupKind.dig);
      expect(breach.introduces, contains('DIG'));
      expect(breach.pace, LevelPace.introduction);
      expect(Campaign.rulesFor(42).pace, LevelPace.practice);
    });

    test('focused pickup pools never offer a locked mechanic early', () {
      for (var level = 1; level <= Campaign.length; level++) {
        final rules = Campaign.rulesFor(level);
        for (final kind in rules.offeredPowerups) {
          expect(
            Campaign.poolFor(level),
            contains(kind),
            reason: 'level $level offered ${kind.name} too soon',
          );
        }
      }
    });

    test('endless depth has a stable generated identity', () {
      final identity = Campaign.identityFor(Campaign.length + 13);
      expect(identity.title, 'Depth 13');
      expect(identity.signature, LevelSignature.gauntlet);
    });
  });

  testWidgets('the map play bar names the current level', (tester) async {
    SharedPreferences.setMockInitialValues({'unlocked': 32, 'owns_full': true});
    final progress = await Progress.load();
    await tester.pumpWidget(
      MaterialApp(
        home: LevelMap(
          progress: progress,
          onSelect: (_) {},
          onPets: () {},
          onSettings: () {},
          onReference: () {},
          onUnlock: () {},
          onDaily: () {},
        ),
      ),
    );
    expect(find.text('LEVEL 32  ·  NIGHT ROUTE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
