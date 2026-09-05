import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/daily.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/pets.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The daily challenge.
///
/// Two things are being protected here, and the second matters more than the
/// first. One: the same day has to give everyone the same board, forever, or
/// the streak is measuring different games for different people. Two: a daily
/// borrows an authored level's *number* in order to borrow its difficulty, and
/// must never write anything that number owns.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Today’s board', () {
    test('is the same board for the whole day, in any time zone', () {
      // Same UTC day, three very different local instants.
      final a = Daily.forDate(DateTime.utc(2026, 3, 14, 0, 0, 1));
      final b = Daily.forDate(DateTime.utc(2026, 3, 14, 12, 30));
      final c = Daily.forDate(DateTime.utc(2026, 3, 14, 23, 59, 59));
      for (final other in [b, c]) {
        expect(other.id, a.id);
        expect(other.sourceLevel, a.sourceLevel);
        expect(other.rules.seed, a.rules.seed);
      }
      expect(a.id, '2026-03-14');
    });

    test('is drawn from the paid bands only', () {
      // The whole argument for the daily being free is that it shows a free
      // player something they cannot otherwise reach. A board from the free
      // twenty would be a chore instead of a look over the wall.
      for (var day = 0; day < 400; day++) {
        final daily = Daily.forDate(
          DateTime.utc(2026).add(Duration(days: day)),
        );
        expect(
          daily.sourceLevel,
          inInclusiveRange(Daily.firstSource, Daily.lastSource),
          reason: 'day $day drew level ${daily.sourceLevel}',
        );
        expect(daily.sourceLevel, greaterThan(Campaign.foundationEnd));
      }
    });

    test('is never a board the campaign already uses', () {
      // Borrowing the level's seed as well as its rules would hand the player a
      // board they may have solved already, which is the one thing a daily
      // cannot be.
      for (var day = 0; day < 200; day++) {
        final daily = Daily.forDate(
          DateTime.utc(2026).add(Duration(days: day)),
        );
        expect(
          daily.rules.seed,
          isNot(Campaign.seedFor(daily.sourceLevel)),
          reason: 'day $day reused level ${daily.sourceLevel}’s own board',
        );
      }
    });

    test('keeps the difficulty of the level it borrows', () {
      // The daily has no balance of its own on purpose — it is tuned by the
      // campaign curve, so there is nothing separate to keep in step.
      final daily = Daily.forDate(DateTime.utc(2026, 6, 1));
      final source = Campaign.rulesFor(daily.sourceLevel);
      expect(daily.rules.budgetMultiplier, source.budgetMultiplier);
      expect(daily.rules.hungerSecondsPerCell, source.hungerSecondsPerCell);
      expect(daily.rules.guards, source.guards);
      expect(daily.rules.regrowDelay, source.regrowDelay);
    });

    test('moves around rather than settling on one level', () {
      final levels = {
        for (var day = 0; day < 60; day++)
          Daily.forDate(
            DateTime.utc(2026).add(Duration(days: day)),
          ).sourceLevel,
      };
      // Not a distribution test — just proof the mixer is mixing at all.
      expect(levels.length, greaterThan(10));
    });
  });

  group('The streak', () {
    Future<Progress> fresh() async {
      SharedPreferences.setMockInitialValues({});
      return Progress.load();
    }

    DailyChallenge on(int y, int m, int d) =>
        Daily.forDate(DateTime.utc(y, m, d));

    test('starts at one and climbs on consecutive days', () async {
      final p = await fresh();
      expect(p.dailyStreak, 0);
      await p.recordDailyClear(on(2026, 3, 1));
      expect(p.dailyStreak, 1);
      await p.recordDailyClear(on(2026, 3, 2));
      expect(p.dailyStreak, 2);
      await p.recordDailyClear(on(2026, 3, 3));
      expect(p.dailyStreak, 3);
      expect(p.dailyBestStreak, 3);
    });

    test('resets after a missed day, and keeps the best', () async {
      final p = await fresh();
      await p.recordDailyClear(on(2026, 3, 1));
      await p.recordDailyClear(on(2026, 3, 2));
      // 3 March missed.
      await p.recordDailyClear(on(2026, 3, 4));
      expect(p.dailyStreak, 1);
      expect(p.dailyBestStreak, 2);
    });

    test('cannot be advanced twice by replaying the same board', () async {
      // Retrying a daily that is already cleared is allowed — it is a puzzle —
      // but it is not a second day.
      final p = await fresh();
      await p.recordDailyClear(on(2026, 3, 1));
      await p.recordDailyClear(on(2026, 3, 1));
      await p.recordDailyClear(on(2026, 3, 1));
      expect(p.dailyStreak, 1);
    });

    test('reads as broken once a day has been missed', () async {
      // The stored value is deliberately not decayed; only the displayed one
      // is, so the number never changes while nobody is playing.
      final p = await fresh();
      await p.recordDailyClear(on(2026, 3, 1));
      await p.recordDailyClear(on(2026, 3, 2));

      expect(p.dailyStreakAsOf(DateTime.utc(2026, 3, 2)), 2, reason: 'today');
      expect(
        p.dailyStreakAsOf(DateTime.utc(2026, 3, 3)),
        2,
        reason: 'still live with today left to play',
      );
      expect(
        p.dailyStreakAsOf(DateTime.utc(2026, 3, 4)),
        0,
        reason: 'a whole day was missed',
      );
      expect(p.dailyStreak, 2, reason: 'the stored streak is left alone');
    });

    test('knows whether today has been cleared', () async {
      final p = await fresh();
      expect(p.hasClearedDaily(on(2026, 3, 1)), isFalse);
      await p.recordDailyClear(on(2026, 3, 1));
      expect(p.hasClearedDaily(on(2026, 3, 1)), isTrue);
      expect(p.hasClearedDaily(on(2026, 3, 2)), isFalse);
    });

    test('survives a restart', () async {
      final p = await fresh();
      await p.recordDailyClear(on(2026, 3, 1));
      final reopened = await Progress.load();
      expect(reopened.dailyStreak, 1);
      expect(reopened.dailyLastCleared, '2026-03-01');
    });
  });

  group('A daily is not a campaign level', () {
    test('clearing one grants no stars and unlocks nothing', () async {
      // The property the whole feature rests on. A daily borrows level 47's
      // rules; it must not hand out level 47's star, and it must not advance
      // the unlock chain to 48.
      SharedPreferences.setMockInitialValues({});
      final p = await Progress.load();
      final before = p.unlocked;

      final daily = Daily.forDate(DateTime.utc(2026, 5, 5));
      await p.recordDailyClear(daily);

      expect(p.totalStars, 0);
      expect(p.completedLevels, 0);
      expect(p.masteredLevels, 0);
      expect(p.unlocked, before);
      expect(p.recordFor(daily.sourceLevel).played, isFalse);
      expect(p.endlessBest, 0);
    });

    test('the win path checks the daily before anything else', () {
      // Ordering, not behaviour, and it is not reachable from a unit test: the
      // daily arm has to come before the endless and campaign arms or a daily
      // falls through into `recordWin` with a borrowed level number. Asserting
      // it on the source is ugly and is still better than not asserting it.
      final source = File('lib/game/hexcape_game.dart').readAsStringSync();
      final win = source.substring(source.indexOf('void _win()'));
      final daily = win.indexOf('recordDailyClear');
      final endless = win.indexOf('recordEndlessClear');
      final campaign = win.indexOf('recordWin');

      expect(daily, greaterThan(-1), reason: 'the daily is never recorded');
      expect(
        daily,
        lessThan(endless),
        reason: 'a daily past level 60 would record an endless clear',
      );
      expect(
        daily,
        lessThan(campaign),
        reason: 'a daily would record a campaign win',
      );
    });
  });

  group('The home screen still fits', () {
    Widget homeFor(Progress progress) => MaterialApp(
      home: HomeScreen(
        progress: progress,
        pet: Pets.scout,
        onPlay: () {},
        onCampaign: () {},
        onDaily: () {},
        onPets: () {},
        onSettings: () {},
        onReference: () {},
        onUnlock: () {},
      ),
    );

    testWidgets('with the daily chip and the unlock offer both present', (
      tester,
    ) async {
      // The worst case: an unbought game shows the daily chip *and* the
      // unlock offer beneath a play button that was already there. On a
      // small phone that is everything the home screen has, all at once.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({'unlocked': 12});
      final progress = await Progress.load();
      await tester.pumpWidget(homeFor(progress));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('DAILY CHALLENGE'), findsOneWidget);
      expect(find.text('Unlock full game'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with the game bought, the offer is gone', (tester) async {
      SharedPreferences.setMockInitialValues({
        'unlocked': 12,
        'owns_full': true,
      });
      final progress = await Progress.load();
      await tester.pumpWidget(homeFor(progress));

      expect(tester.takeException(), isNull);
      expect(find.text('Unlock full game'), findsNothing);
      expect(find.textContaining('DAILY CHALLENGE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
