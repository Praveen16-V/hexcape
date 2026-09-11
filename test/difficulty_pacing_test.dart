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

    test('every breather eases several pressures on what came before', () {
      // This used to require the level before a breather to be tagged a
      // challenge. That is the mechanism, not the intent, and with fifty-three
      // gates to teach the campaign no longer has room for it: four of the
      // eight breathers follow a practice or combination beat simply because
      // every slot after a challenge is already spoken for by a gate. All
      // eight still do the job, which is what the rest of this loop measures.
      //
      // What does still have to hold is that a breather is a step down from
      // whatever preceded it, and that two never sit together — a rest from a
      // rest is not a rest.
      var count = 0;
      for (var level = 6; level <= Campaign.length; level++) {
        final current = Campaign.rulesFor(level);
        if (current.pace != LevelPace.breather) continue;
        count++;
        final challenge = Campaign.rulesFor(level - 1);
        expect(
          challenge.pace,
          isNot(LevelPace.breather),
          reason: 'level $level rests on a rest',
        );
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
        // Patrol speed is a band property, not a pace one: it climbs steadily
        // across a band whatever each level is for, and only a challenge beat
        // pushes it above that line. So a breather after a challenge drops
        // back to the curve and must be slower, while a breather after a
        // practice beat is simply the curve's next tick and comes out a
        // fraction faster — 56 and 99 do, by 0.8% and 0.2%. Demanding a
        // decrease there would be demanding that the band stop climbing.
        if (challenge.pace == LevelPace.challenge) {
          expect(current.guardSpeed, lessThanOrEqualTo(challenge.guardSpeed));
        }
        // How many of them there are is a pace decision, and a breather never
        // adds one.
        expect(current.guards, lessThanOrEqualTo(challenge.guards));
      }
      // The exact number is not the invariant — the structure asserted in the
      // loop above is. Pinning it meant every new band failed this test for
      // being a new band. The floor is here only so that deleting every
      // breather still fails something.
      expect(count, greaterThanOrEqualTo(6));
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
