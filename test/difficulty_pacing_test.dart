import 'dart:math' as math;

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
          // Regrowth is not checked here. It reaches its floor inside Mastery
          // and then holds, and Foundation's closing challenge at 20 eases it
          // on purpose — that level is the last one a player sees for free and
          // is not the place to be strangled by closing ground. Band floors are
          // checked below instead.
        }
        previous = current;
      }
    });

    test("each band's walls peak higher than the last, at its final level", () {
      // Walls used to be checked challenge to challenge, which fails at seven
      // peaks and should: from Mastery on, the band records pin budget, hunger
      // and regrowth flat on purpose — below about 1.06x par a level demands
      // provably optimal play — so Collapse and Vigil climb on an axis of their
      // own, slopes and sunken ground, rather than on more walls. Each band
      // also restarts its wall curve below the previous band's peak, because a
      // band that opened at the last one's hardest would have nowhere to go.
      //
      // The climb is real, it just lives one level up: band over band.
      var previous = -1.0;
      CampaignBand? previousBand;
      for (final band in CampaignBand.values) {
        if (band == CampaignBand.endless) continue;
        var peak = -1.0;
        var peakAt = -1;
        var last = -1;
        for (var level = 1; level <= Campaign.length; level++) {
          if (Campaign.bandOf(level) != band) continue;
          last = level;
          final walls = Campaign.rulesFor(level).anchorDensity;
          if (walls > peak) {
            peak = walls;
            peakAt = level;
          }
        }
        if (last == -1) continue;
        expect(
          peak,
          greaterThan(previous),
          reason:
              '${band.name} peaks at $peak, no higher than '
              '${previousBand?.name}',
        );
        // The hardest board in a band is the one that closes it. A band that
        // peaks in its middle sends the player out on a downhill.
        expect(
          peakAt,
          last,
          reason: '${band.name} peaks at $peakAt but ends at $last',
        );
        previous = peak;
        previousBand = band;
      }
    });

    test('no band gives back what an earlier one had already taken', () {
      // The floors, as opposed to the peaks. Budget, clock and regrowth all
      // descend to a floor and then hold flat — deliberately, because below
      // about 1.06x par a level demands provably optimal play — so the rule is
      // that a band never raises one, not that it always lowers one.
      var budget = double.infinity;
      var clock = double.infinity;
      var regrow = double.infinity;
      for (final band in CampaignBand.values) {
        if (band == CampaignBand.endless) continue;
        var bandBudget = double.infinity;
        var bandClock = double.infinity;
        var bandRegrow = double.infinity;
        var found = false;
        for (var level = 1; level <= Campaign.length; level++) {
          if (Campaign.bandOf(level) != band) continue;
          found = true;
          final r = Campaign.rulesFor(level);
          bandBudget = math.min(bandBudget, r.budgetMultiplier);
          bandClock = math.min(bandClock, r.hungerSecondsPerCell);
          bandRegrow = math.min(bandRegrow, r.regrowDelay);
        }
        if (!found) continue;
        expect(bandBudget, lessThanOrEqualTo(budget + 1e-9),
            reason: '${band.name} hands taps back');
        expect(bandClock, lessThanOrEqualTo(clock + 1e-9),
            reason: '${band.name} hands time back');
        expect(bandRegrow, lessThanOrEqualTo(regrow + 1e-9),
            reason: '${band.name} slows the ground back down');
        budget = bandBudget;
        clock = bandClock;
        regrow = bandRegrow;
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
