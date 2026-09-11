import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Progress> _progress([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return Progress.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('The snapshot', () {
    test('carries progress and deliberately leaves settings behind', () async {
      final p = await _progress();
      await p.recordWin(level: 4, stars: 3, taps: 11, time: 9.5);
      await p.setVolume(0.1);
      await p.setZoom(2.0);
      await p.choosePet('ember');

      final snap = p.toSnapshot();
      expect(snap['v'], Progress.snapshotVersion);
      expect(snap['unlocked'], 5);
      expect(snap['pet'], 'ember');
      expect((snap['levels']! as Map)['4'], isNotNull);

      // Comfort settings belong to the phone, not the player. A tablet is not
      // wrong to be louder than a handset.
      expect(snap.keys, isNot(contains('opt_volume')));
      expect(snap.keys, isNot(contains('opt_zoom')));
      // The purchase is Play's record, re-queried every launch. A copy here
      // would only be a second answer that can disagree.
      expect(snap.keys, isNot(contains('owns_full')));
    });

    test('survives a round trip through JSON', () async {
      final p = await _progress();
      await p.recordWin(
        level: 7,
        stars: 2,
        taps: 20,
        time: 14.25,
        difficulty: Difficulty.hard,
      );
      final decoded =
          jsonDecode(jsonEncode(p.toSnapshot())) as Map<String, Object?>;

      final fresh = await _progress();
      expect(await fresh.mergeSnapshot(decoded), isTrue);
      expect(fresh.recordFor(7).stars, 2);
      expect(fresh.recordFor(7).bestTaps, 20);
      expect(fresh.recordFor(7).bestTime, 14.25);
      expect(fresh.recordFor(7).difficulty, Difficulty.hard);
      expect(fresh.unlocked, 8);
    });
  });

  group('The merge only ever improves', () {
    test('a reinstall takes everything back from the cloud', () async {
      final old = await _progress();
      await old.recordWin(level: 20, stars: 3, taps: 24, time: 19.0);
      await old.setTrialUsed();
      final snap = old.toSnapshot();

      // A fresh install: nothing but the purchase, which Play restored.
      final fresh = await _progress({'owns_full': true});
      expect(fresh.unlocked, 1);
      await fresh.mergeSnapshot(snap);

      expect(fresh.unlocked, 21);
      expect(fresh.recordFor(20).stars, 3);
      expect(fresh.trialUsed, isTrue, reason: 'a reinstall re-armed the trial');
    });

    test('a stale cloud save cannot take anything away', () async {
      // The case that would be unforgivable: an old phone syncs a save from
      // before the player got good, and the current device loses its records.
      final stale = await _progress();
      await stale.recordWin(level: 5, stars: 1, taps: 30, time: 25.0);
      final staleSnap = stale.toSnapshot();

      final current = await _progress();
      await current.recordWin(level: 5, stars: 3, taps: 12, time: 8.0);
      await current.recordWin(level: 6, stars: 2, taps: 15, time: 11.0);

      await current.mergeSnapshot(staleSnap);

      expect(current.recordFor(5).stars, 3, reason: 'stars went backwards');
      expect(current.recordFor(5).bestTaps, 12, reason: 'best taps lost');
      expect(current.recordFor(5).bestTime, 8.0, reason: 'best time lost');
      expect(current.unlocked, 7, reason: 'the frontier went backwards');
      expect(current.recordFor(6).stars, 2, reason: 'a level was dropped');
    });

    test('two devices played offline end up with the union', () async {
      final phone = await _progress();
      await phone.recordWin(level: 3, stars: 3, taps: 8, time: 6.0);
      await phone.recordWin(level: 4, stars: 1, taps: 40, time: 30.0);

      final tablet = await _progress();
      await tablet.recordWin(level: 4, stars: 3, taps: 14, time: 10.0);
      await tablet.recordWin(level: 5, stars: 2, taps: 18, time: 13.0);

      // Each takes the other's snapshot. Order must not matter.
      final fromPhone = phone.toSnapshot();
      final fromTablet = tablet.toSnapshot();
      await phone.mergeSnapshot(fromTablet);
      await tablet.mergeSnapshot(fromPhone);

      for (final p in [phone, tablet]) {
        expect(p.recordFor(3).stars, 3);
        expect(p.recordFor(4).stars, 3);
        expect(p.recordFor(4).bestTaps, 14);
        expect(p.recordFor(5).stars, 2);
        expect(p.unlocked, 6);
      }
    });

    test('merging twice changes nothing the first merge did not', () async {
      final source = await _progress();
      await source.recordWin(level: 9, stars: 2, taps: 21, time: 16.0);
      final snap = source.toSnapshot();

      final target = await _progress();
      expect(await target.mergeSnapshot(snap), isTrue);
      expect(
        await target.mergeSnapshot(snap),
        isFalse,
        reason: 'a repeat merge reported a change it did not make',
      );
    });

    test('equal stars hand the badge to the harder setting', () async {
      final hard = await _progress();
      await hard.recordWin(
        level: 12,
        stars: 2,
        taps: 25,
        time: 20.0,
        difficulty: Difficulty.hard,
      );
      final snap = hard.toSnapshot();

      final normal = await _progress();
      await normal.recordWin(level: 12, stars: 2, taps: 22, time: 18.0);
      await normal.mergeSnapshot(snap);

      // The better numbers are local; the badge is the harder clear's.
      expect(normal.recordFor(12).bestTaps, 22);
      expect(normal.recordFor(12).difficulty, Difficulty.hard);
    });

    test(
      'the daily streak follows whichever device cleared one last',
      () async {
        final ahead = await _progress({
          'daily_last': '2026-09-10',
          'daily_streak': 6,
          'daily_best_streak': 6,
        });
        final behind = await _progress({
          'daily_last': '2026-09-02',
          'daily_streak': 2,
          'daily_best_streak': 9,
        });

        await behind.mergeSnapshot(ahead.toSnapshot());
        expect(behind.dailyLastCleared, '2026-09-10');
        expect(behind.dailyStreak, 6);
        // A record, so it is the higher of the two rather than the later one.
        expect(behind.dailyBestStreak, 9);
      },
    );

    test('a snapshot from a newer build is left alone', () async {
      final p = await _progress();
      await p.recordWin(level: 2, stars: 1, taps: 9, time: 7.0);
      final before = p.unlocked;

      final future = {
        'v': Progress.snapshotVersion + 1,
        'unlocked': 99,
        'levels': <String, Object?>{},
      };
      expect(await p.mergeSnapshot(future), isFalse);
      expect(
        p.unlocked,
        before,
        reason: 'an older build guessed at a newer save',
      );
    });

    test('junk does not corrupt a good save', () async {
      final p = await _progress();
      await p.recordWin(level: 8, stars: 3, taps: 15, time: 12.0);
      for (final junk in <Map<String, Object?>>[
        {},
        {'v': 'one'},
        {'v': 1, 'unlocked': 'lots'},
        {'v': 1, 'levels': 'not a map'},
        {
          'v': 1,
          'levels': {
            'eight': {'stars': 3},
          },
        },
        {
          'v': 1,
          'levels': {
            '8': {'stars': null, 'taps': 'x'},
          },
        },
      ]) {
        await p.mergeSnapshot(junk);
      }
      expect(p.recordFor(8).stars, 3);
      expect(p.recordFor(8).bestTaps, 15);
      expect(p.unlocked, 9);
    });
  });

  group('Reopening a campaign that was paid for', () {
    test('opens every chapter, but only for an owner', () async {
      final free = await _progress();
      expect(
        await free.openBoughtCampaign(),
        isFalse,
        reason: 'a free player was handed the paid campaign',
      );
      expect(free.unlocked, 1);

      final owner = await _progress({'owns_full': true});
      expect(await owner.openBoughtCampaign(), isTrue);
      expect(owner.unlocked, Campaign.length);
    });

    test('never lowers a frontier the player already earned', () async {
      final p = await _progress({
        'owns_full': true,
        'unlocked': Campaign.length + 5,
      });
      expect(await p.openBoughtCampaign(), isFalse);
      expect(p.unlocked, Campaign.length + 5, reason: 'endless progress lost');
    });
  });
}
