import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/level_rules.dart';

/// How much of the campaign each mechanic is actually in play for.
Map<String, int> _reach() {
  final counts = <String, int>{};
  void bump(String k) => counts[k] = (counts[k] ?? 0) + 1;
  for (var n = 1; n <= Campaign.length; n++) {
    final r = Campaign.rulesFor(n);
    if (r.faultDensity > 0) bump('fault');
    if (r.sentries > 0) bump('sentry');
    if (r.springDensity > 0) bump('spring');
    if (r.guards > 0) bump('patrol');
    for (final p in r.offeredPowerups) {
      bump(p.name);
    }
  }
  return counts;
}

/// Whether two levels are arithmetically indistinguishable.
///
/// Deliberately a numeric comparison rather than a bucketed fingerprint. The
/// bucketed version kept flagging levels whose densities genuinely differed by
/// a third but happened to fall either side of no boundary, and kept missing
/// the thing it was written for. What actually went wrong in Collapse and Vigil
/// was *pinning*: budget, hunger and regrowth held at a constant by the band
/// records, leaving one axis to carry forty levels. Two levels that differ by
/// less than these tolerances are the same board with a different silhouette.
bool _sameBoard(LevelRules a, LevelRules b) {
  bool near(double x, double y, double tolerance) => (x - y).abs() < tolerance;
  return near(a.anchorDensity, b.anchorDensity, 0.01) &&
      near(a.heavyDensity, b.heavyDensity, 0.01) &&
      near(a.springDensity, b.springDensity, 0.01) &&
      near(a.faultDensity, b.faultDensity, 0.01) &&
      near(a.slopeDensity, b.slopeDensity, 0.01) &&
      near(a.sunkenDensity, b.sunkenDensity, 0.01) &&
      a.guards == b.guards &&
      a.sentries == b.sentries &&
      near(a.regrowDelay, b.regrowDelay, 0.15) &&
      near(a.budgetMultiplier, b.budgetMultiplier, 0.02) &&
      near(a.hungerSecondsPerCell, b.hungerSecondsPerCell, 0.02) &&
      a.offeredPowerups.join() == b.offeredPowerups.join();
}

void main() {
  group('The campaign has a wide vocabulary, not a long one', () {
    test('every mechanic is in play for a substantial part of the run', () {
      final reach = _reach();
      // Cracked ground, warded light, STAKE and HEEL used to arrive at 61, 81,
      // 63 and 83 — so a player who finished the campaign met the last two on
      // eighteen levels out of a hundred, and levels 21 to 60 drew from one
      // unchanging bag for forty levels running. These floors are what stops
      // that from creeping back.
      expect(reach['fault'], greaterThanOrEqualTo(60));
      expect(reach['sentry'], greaterThanOrEqualTo(40));
      expect(reach['stake'], greaterThanOrEqualTo(40));
      expect(reach['heel'], greaterThanOrEqualTo(30));
      expect(reach['dig'], greaterThanOrEqualTo(30));
    });

    test('the middle of the campaign keeps meeting new ideas', () {
      // The stretch that used to be forty levels of the same eight mechanics.
      final introductions = [
        for (var n = 21; n <= 60; n++)
          if (Campaign.introductionAt(n) != null) n,
      ];
      expect(
        introductions.length,
        greaterThanOrEqualTo(4),
        reason: 'levels 21-60 are the bulk of the campaign; they cannot be one '
            'idea repeated. Introductions found: $introductions',
      );
    });

    test('a tool never arrives before the pressure it answers', () {
      // The whole shape of the teaching ladder: meet the hazard, practise it,
      // then be handed the answer.
      expect(Campaign.stakeFrom, greaterThan(Campaign.faultsFrom));
      expect(Campaign.heelFrom, greaterThan(Campaign.sentriesFrom));
      expect(Campaign.digFrom, greaterThan(Campaign.guardsFrom));
      for (var n = 1; n < Campaign.stakeFrom; n++) {
        expect(Campaign.poolFor(n), isNot(contains(PickupKind.stake)));
      }
      for (var n = 1; n < Campaign.heelFrom; n++) {
        expect(Campaign.poolFor(n), isNot(contains(PickupKind.heel)));
      }
    });

    test('past the campaign every tool is on the table', () {
      // Endless runs cracked ground and two sentries; withholding the two
      // tools that answer them is not difficulty.
      final endless = Campaign.rulesFor(Campaign.length + 20);
      expect(endless.offeredPowerups, contains(PickupKind.stake));
      expect(endless.offeredPowerups, contains(PickupKind.heel));
    });
  });

  group('Levels are not wallpaper', () {
    test('adjacent levels are rarely the same board twice', () {
      final same = <String>[];
      for (var n = 5; n <= Campaign.length; n++) {
        if (_sameBoard(Campaign.rulesFor(n - 1), Campaign.rulesFor(n))) {
          same.add('${n - 1}/$n');
        }
      }
      // A handful is expected and deliberate: a hazard's introduction and the
      // practice beat after it are meant to be the same board twice.
      expect(
        same.length,
        lessThanOrEqualTo(10),
        reason: 'identical adjacent pairs: $same',
      );
    });

    test('no stretch of the campaign is one board repeated', () {
      // The failure this exists to catch was structural rather than sloppy:
      // Collapse and Vigil pin budget, hunger and regrowth flat at Mastery's
      // floors — below about 1.06x par a level demands provably optimal play —
      // so those forty levels had a single axis left to vary on, and whole runs
      // of them came out arithmetically identical. Giving each of those bands an
      // obstacle of its own is what fixed it; this stops it closing back up.
      final twins = <int, List<int>>{};
      for (var a = 4; a <= Campaign.length; a++) {
        for (var b = a + 1; b <= Campaign.length; b++) {
          if (_sameBoard(Campaign.rulesFor(a), Campaign.rulesFor(b))) {
            twins.putIfAbsent(a, () => []).add(b);
          }
        }
      }
      final wallpaper = {
        for (final e in twins.entries)
          if (e.value.length >= 3) e.key: e.value,
      };
      expect(
        wallpaper,
        isEmpty,
        reason: 'levels with three or more twins: $wallpaper',
      );
    });

    test('no signature is authored and then never used', () {
      final used = <LevelSignature, int>{};
      for (var n = 1; n <= Campaign.length; n++) {
        final s = Campaign.signatureFor(n);
        used[s] = (used[s] ?? 0) + 1;
      }
      for (final signature in LevelSignature.values) {
        expect(
          used[signature] ?? 0,
          greaterThanOrEqualTo(2),
          reason: '$signature is described to the player but barely happens',
        );
      }
      expect(
        used[LevelSignature.gauntlet]!,
        lessThanOrEqualTo(Campaign.length ~/ 2),
        reason: 'gauntlet is the absence of a signature; if half the campaign '
            'is one, most levels have no character of their own',
      );
    });

    test('a signature actually changes the board it lands on', () {
      // Contrast, not merely presence. Each of these spikes its own axis and
      // pulls the others down, which is what makes a level read as being about
      // one thing.
      final fault = Campaign.rulesFor(68);
      final spring = Campaign.rulesFor(64);
      final heavy = Campaign.rulesFor(65);
      expect(Campaign.signatureFor(68), LevelSignature.faultLine);
      expect(Campaign.signatureFor(64), LevelSignature.springLine);
      expect(Campaign.signatureFor(65), LevelSignature.heavyGround);

      expect(fault.faultDensity, greaterThan(spring.faultDensity));
      expect(spring.springDensity, greaterThan(fault.springDensity));
      expect(heavy.heavyDensity, greaterThan(fault.heavyDensity));
      // And each one is *materially* more open than the band's undiluted peak,
      // not merely a hair under it. The suppression is the load-bearing half of
      // a signature: a spring level with the band's full wall density is a
      // gauntlet that happens to have springs, because momentum has nowhere to
      // land. A margin the pace relief alone could produce would not prove it.
      final gauntlet = Campaign.rulesFor(66);
      expect(Campaign.signatureFor(66), LevelSignature.gauntlet);
      expect(gauntlet.anchorDensity - fault.anchorDensity, greaterThan(0.03));
      expect(gauntlet.anchorDensity - spring.anchorDensity, greaterThan(0.03));
      expect(gauntlet.heavyDensity - fault.heavyDensity, greaterThan(0.03));
      // The spikes, held against the same undiluted peak.
      expect(spring.springDensity, greaterThan(gauntlet.springDensity * 1.5));
      expect(fault.faultDensity, greaterThan(gauntlet.faultDensity * 1.5));
    });
  });
}
