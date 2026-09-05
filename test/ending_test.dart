import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Depth as the player sees it, mirroring what the HUD and the map compute.
int _depth(int level) => level - Campaign.length;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Finishing the campaign', () {
    test('level sixty is the last authored level, and the only ending', () {
      expect(Campaign.bandOf(Campaign.length), CampaignBand.mastery);
      expect(Campaign.bandOf(Campaign.length + 1), CampaignBand.endless);
    });

    test('endless is counted in depth, starting at one', () {
      // "Level 61" is not a score. Depth is, and it has to start at one rather
      // than zero or the first endless board reads as no progress at all.
      expect(_depth(Campaign.length + 1), 1);
      expect(_depth(Campaign.length + 18), 18);
    });

    test('the deepest run is remembered and only ever improves', () async {
      final p = await Progress.load();
      expect(p.endlessBest, 0);

      await p.recordEndlessClear(level: Campaign.length + 5);
      expect(_depth(p.endlessBest), 5);

      // A shallower run afterwards must not overwrite it.
      await p.recordEndlessClear(level: Campaign.length + 2);
      expect(_depth(p.endlessBest), 5);

      final reopened = await Progress.load();
      expect(_depth(reopened.endlessBest), 5);
      expect(reopened.totalStars, 0);
      expect(reopened.recordFor(Campaign.length + 5).played, isFalse);
    });

    test('campaign levels never touch the endless record', () async {
      final p = await Progress.load();
      await p.recordWin(level: Campaign.length, stars: 3, taps: 20, time: 9);
      expect(
        p.endlessBest,
        lessThanOrEqualTo(Campaign.length),
        reason: 'beating the campaign is not an endless run',
      );
      expect(
        p.endlessBest > Campaign.length ? 1 : 0,
        0,
        reason: 'the map would show a depth nobody reached',
      );
    });

    test('beating the last level unlocks endless', () async {
      final p = await Progress.load();
      await p.recordWin(level: Campaign.length, stars: 3, taps: 20, time: 9);
      expect(p.isUnlocked(Campaign.length + 1), isTrue);
    });

    test('endless rules keep coming, and keep getting harder', () {
      // The floors exist so endless never becomes arithmetically impossible,
      // but nothing may get *easier* on the way down.
      var budget = double.infinity;
      var clock = double.infinity;
      for (var n = Campaign.length + 1; n <= Campaign.length + 200; n++) {
        final rules = Campaign.rulesFor(n);
        expect(rules.isEndless, isTrue);
        expect(rules.budgetMultiplier, lessThanOrEqualTo(budget + 1e-9));
        expect(rules.hungerSecondsPerCell, lessThanOrEqualTo(clock + 1e-9));
        expect(rules.budgetMultiplier, greaterThan(1.0));
        expect(rules.hungerSecondsPerCell, greaterThan(0));
        budget = rules.budgetMultiplier;
        clock = rules.hungerSecondsPerCell;
      }
    });
  });
}
