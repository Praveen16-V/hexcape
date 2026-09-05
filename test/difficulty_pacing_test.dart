import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/level_rules.dart';

void main() {
  group('Campaign pacing', () {
    test('every authored pace has a clear player-facing description', () {
      for (final pace in LevelPace.values) {
        expect(pace.label, isNotEmpty);
        expect(pace.description, isNotEmpty);
      }
    });

    test('mechanics arrive with relief and a practice level afterward', () {
      // All of them, not just the first two: level 41 and the fault
      // introduction were never checked, and an introduction that fails to
      // relieve is exactly the regression this test exists to catch.
      for (final level in [
        Campaign.springsFrom,
        Campaign.guardsFrom,
        41,
        Campaign.faultsFrom,
      ]) {
        final before = Campaign.rulesFor(level - 1);
        final intro = Campaign.rulesFor(level);
        final practice = Campaign.rulesFor(level + 1);
        expect(intro.pace, LevelPace.introduction);
        expect(practice.pace, LevelPace.practice);
        expect(intro.introduces, isNotNull);
        expect(intro.budgetMultiplier, greaterThan(before.budgetMultiplier));
        expect(
          intro.hungerSecondsPerCell,
          greaterThan(before.hungerSecondsPerCell),
        );
        expect(intro.regrowDelay, greaterThan(before.regrowDelay));
        expect(intro.anchorDensity, lessThan(before.anchorDensity));
      }
    });

    test('every breather follows a challenge and eases several pressures', () {
      var count = 0;
      for (var level = 6; level <= Campaign.length; level++) {
        final current = Campaign.rulesFor(level);
        if (current.pace != LevelPace.breather) continue;
        count++;
        final challenge = Campaign.rulesFor(level - 1);
        expect(challenge.pace, LevelPace.challenge, reason: 'level $level');
        expect(
          current.budgetMultiplier,
          greaterThan(challenge.budgetMultiplier),
        );
        expect(
          current.hungerSecondsPerCell,
          greaterThan(challenge.hungerSecondsPerCell),
        );
        expect(current.regrowDelay, greaterThan(challenge.regrowDelay));
        expect(current.anchorDensity, lessThan(challenge.anchorDensity));
        expect(current.heavyDensity, lessThan(challenge.heavyDensity));
        expect(current.guardSpeed, lessThanOrEqualTo(challenge.guardSpeed));
        expect(current.guards, lessThanOrEqualTo(challenge.guards));
      }
      // The exact number is not the invariant — the structure asserted in the
      // loop above is. Pinning it meant every new band failed this test for
      // being a new band.
      expect(count, greaterThanOrEqualTo(14));
    });

    test('each band ends at full challenge pressure', () {
      for (final level in [
        Campaign.foundationEnd,
        Campaign.pressureEnd,
        Campaign.masteryEnd,
        Campaign.collapseEnd,
      ]) {
        expect(Campaign.rulesFor(level).pace, LevelPace.challenge);
      }
    });

    test('challenge peaks keep becoming harder', () {
      LevelRules? previous;
      for (var level = 6; level <= Campaign.length; level++) {
        final current = Campaign.rulesFor(level);
        if (current.pace != LevelPace.challenge) continue;
        if (previous != null) {
          expect(
            current.budgetMultiplier,
            lessThanOrEqualTo(previous.budgetMultiplier),
            reason: 'budget at challenge $level',
          );
          expect(
            current.hungerSecondsPerCell,
            lessThanOrEqualTo(previous.hungerSecondsPerCell),
            reason: 'clock at challenge $level',
          );
          expect(
            current.regrowDelay,
            lessThanOrEqualTo(previous.regrowDelay),
            reason: 'regrowth at challenge $level',
          );
          expect(
            current.anchorDensity,
            greaterThanOrEqualTo(previous.anchorDensity),
            reason: 'walls at challenge $level',
          );
        }
        previous = current;
      }
    });

    test('tutorial and endless keep their own pacing identities', () {
      for (var level = 1; level <= Campaign.tutorialBand; level++) {
        expect(Campaign.rulesFor(level).pace, LevelPace.learning);
      }
      for (final level in [Campaign.length + 1, 140, 1000]) {
        expect(Campaign.rulesFor(level).pace, LevelPace.endless);
      }
    });
  });
}
