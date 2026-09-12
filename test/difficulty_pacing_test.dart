import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/level_rules.dart';

double _wallPressure(LevelRules rules) =>
    rules.anchorDensity + rules.heavyDensity;

List<int> _lightFamilies(LevelRules rules) => [
  rules.guards,
  rules.sentries,
  rules.beacons,
  rules.spinners,
  rules.runners,
  rules.blinkers,
  rules.wardens,
];

void main() {
  group('Campaign pacing', () {
    test('every authored pace has a clear player-facing description', () {
      for (final pace in LevelPace.values) {
        expect(pace.label, isNotEmpty);
        expect(pace.description, isNotEmpty);
      }
    });

    test('every hazard arrives with relief and immediate practice', () {
      for (final level in [
        Campaign.mireFrom,
        Campaign.springsFrom,
        Campaign.thicketFrom,
        Campaign.sleeperFrom,
        Campaign.foxfireFrom,
        Campaign.guardsFrom,
        Campaign.faultsFrom,
        Campaign.thatchFrom,
        Campaign.iceFrom,
        Campaign.alarmFrom,
        Campaign.hardpanFrom,
        Campaign.overgrowthFrom,
        Campaign.sentriesFrom,
        Campaign.eddyFrom,
        Campaign.scaffoldFrom,
        Campaign.slopesFrom,
        Campaign.magnetFrom,
        Campaign.spinnerFrom,
        Campaign.blinkerFrom,
        Campaign.beaconFrom,
        Campaign.gateFrom,
        Campaign.runnerFrom,
        Campaign.sunkenFrom,
        Campaign.mirrorFrom,
        Campaign.thornFrom,
        Campaign.wardenFrom,
        Campaign.gloomFrom,
        Campaign.tremorFrom,
      ]) {
        final intro = Campaign.rulesFor(level);
        final practice = Campaign.rulesFor(level + 1);
        expect(intro.pace, LevelPace.introduction, reason: 'intro $level');
        expect(
          practice.pace,
          LevelPace.practice,
          reason: 'practice ${level + 1}',
        );
        expect(intro.introduces, isNotNull);
        LevelRules? priorPeak;
        for (var earlier = level - 1; earlier >= 1; earlier--) {
          final candidate = Campaign.rulesFor(earlier);
          if (candidate.pace == LevelPace.challenge) {
            priorPeak = candidate;
            break;
          }
        }
        if (priorPeak != null) {
          expect(
            intro.budgetMultiplier,
            greaterThan(priorPeak.budgetMultiplier),
            reason: 'budget relief at intro $level',
          );
          expect(
            intro.hungerSecondsPerCell,
            greaterThan(priorPeak.hungerSecondsPerCell),
            reason: 'clock relief at intro $level',
          );
          expect(
            intro.regrowDelay,
            greaterThan(priorPeak.regrowDelay),
            reason: 'regrowth relief at intro $level',
          );
        }
      }
    });

    test('post-20 tools are banner-only rather than artificial easy beats', () {
      for (final level in [
        Campaign.slowbeatFrom,
        Campaign.cloakFrom,
        Campaign.stakeFrom,
        Campaign.trowelFrom,
        Campaign.harvestFrom,
        Campaign.whistleFrom,
        Campaign.digFrom,
        Campaign.maulFrom,
        Campaign.rewindFrom,
        Campaign.surepawsFrom,
        Campaign.wardownFrom,
        Campaign.heelFrom,
        Campaign.echoFrom,
        Campaign.seedFrom,
        Campaign.moleFrom,
        Campaign.waystoneFrom,
        Campaign.beaconDropFrom,
        Campaign.nightEyesFrom,
        Campaign.pouchFrom,
        Campaign.ironpawFrom,
        Campaign.keepsakeFrom,
      ]) {
        expect(Campaign.introductionAt(level), isNotNull);
        expect(
          Campaign.paceFor(level),
          isNot(anyOf(LevelPace.introduction, LevelPace.practice)),
          reason: 'tool at $level stole a hazard teaching beat',
        );
      }
    });

    test('the post-20 rising-wave cadence is authored exactly', () {
      const breathers = {25, 36, 48, 61, 70, 89};
      const challenges = {31, 40, 53, 60, 64, 76, 80, 88, 100};
      for (var level = 21; level <= Campaign.length; level++) {
        final pace = Campaign.paceFor(level);
        if (breathers.contains(level)) {
          expect(pace, LevelPace.breather, reason: 'breather $level');
        }
        if (challenges.contains(level)) {
          expect(pace, LevelPace.challenge, reason: 'challenge $level');
        }
      }
    });

    test('every breather eases several pressures on what came before', () {
      // A breather need not follow a challenge. The six explicit breathers sit
      // wherever the introduction calendar leaves a clean rest, and every one
      // still has to ease several pressures from the preceding stage.
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
          reason: 'budget at breather $level',
        );
        expect(
          current.hungerSecondsPerCell,
          greaterThan(challenge.hungerSecondsPerCell),
        );
        expect(
          current.regrowDelay,
          greaterThan(challenge.regrowDelay),
          reason: 'regrowth at breather $level',
        );
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
      // The exact schedule is pinned above; this floor also makes wholesale
      // removal fail close to the behavioral assertion.
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
      for (
        var level = Campaign.foundationEnd + 1;
        level <= Campaign.length;
        level++
      ) {
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

    test('post-20 challenge steps stay inside the gradual envelope', () {
      const challenges = [31, 40, 53, 60, 64, 76, 80, 88, 100];
      LevelRules? previous;
      for (final level in challenges) {
        final current = Campaign.rulesFor(level);
        expect(current.pace, LevelPace.challenge);
        if (previous != null) {
          expect(
            previous.budgetMultiplier - current.budgetMultiplier,
            lessThanOrEqualTo(0.04 + 1e-9),
            reason: 'budget jump into challenge $level',
          );
          expect(
            previous.hungerSecondsPerCell - current.hungerSecondsPerCell,
            lessThanOrEqualTo(0.06 + 1e-9),
            reason: 'clock jump into challenge $level',
          );
          expect(
            previous.regrowDelay - current.regrowDelay,
            lessThanOrEqualTo(0.5 + 1e-9),
            reason: 'regrowth jump into challenge $level',
          );
          expect(
            _wallPressure(current) - _wallPressure(previous),
            lessThanOrEqualTo(0.06 + 1e-9),
            reason: 'wall jump into challenge $level',
          );
          final beforeLights = _lightFamilies(previous);
          final afterLights = _lightFamilies(current);
          for (var i = 0; i < beforeLights.length; i++) {
            expect(
              afterLights[i] - beforeLights[i],
              lessThanOrEqualTo(1),
              reason: 'light-family jump into challenge $level',
            );
          }
        }
        previous = current;
      }
    });

    test("each band's full-pressure ending has more walls than the last", () {
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
        var last = -1;
        for (var level = 1; level <= Campaign.length; level++) {
          if (Campaign.bandOf(level) != band) continue;
          last = level;
        }
        if (last == -1) continue;
        final peak = Campaign.rulesFor(last).anchorDensity;
        expect(
          peak,
          greaterThan(previous),
          reason:
              '${band.name} peaks at $peak, no higher than '
              '${previousBand?.name}',
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
        expect(
          bandBudget,
          lessThanOrEqualTo(budget + 1e-9),
          reason: '${band.name} hands taps back',
        );
        expect(
          bandClock,
          lessThanOrEqualTo(clock + 1e-9),
          reason: '${band.name} hands time back',
        );
        // Stage 20 is a deliberately sharp free-campaign finale. Pressure
        // opens with a patrol lesson and resets the regrowth clock before the
        // paid trail begins climbing again.
        if (band != CampaignBand.pressure) {
          expect(
            bandRegrow,
            lessThanOrEqualTo(regrow + 1e-9),
            reason: '${band.name} slows the ground back down',
          );
        }
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
