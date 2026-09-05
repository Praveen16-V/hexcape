import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Progress', () {
    test('starts at level one with nothing recorded', () async {
      final progress = await Progress.load();
      expect(progress.unlocked, 1);
      expect(progress.totalStars, 0);
      expect(progress.recordFor(1).played, isFalse);
      expect(progress.isUnlocked(1), isTrue);
      expect(progress.isUnlocked(2), isFalse);
    });

    test('finishing a level unlocks the next one', () async {
      final progress = await Progress.load();
      await progress.recordWin(level: 1, stars: 2, taps: 14, time: 11.5);

      expect(progress.unlocked, 2);
      expect(progress.isUnlocked(2), isTrue);
      expect(progress.isUnlocked(3), isFalse);
      expect(progress.recordFor(1).stars, 2);
      expect(progress.recordFor(1).bestTaps, 14);
    });

    test('a worse replay never overwrites a better result', () async {
      // The rule that matters most here. Losing a three-star run by casually
      // replaying it is the kind of thing a player never forgives, and it fails
      // silently — nothing crashes, the number is just quietly worse.
      final progress = await Progress.load();
      await progress.recordWin(level: 3, stars: 3, taps: 20, time: 15.0);
      await progress.recordWin(level: 3, stars: 1, taps: 44, time: 39.0);

      final record = progress.recordFor(3);
      expect(record.stars, 3, reason: 'stars were downgraded');
      expect(record.bestTaps, 20, reason: 'a worse tap count was kept');
      expect(record.bestTime, 15.0, reason: 'a slower time was kept');
    });

    test('a better replay does improve each field independently', () async {
      final progress = await Progress.load();
      await progress.recordWin(level: 4, stars: 2, taps: 30, time: 22.0);
      await progress.recordWin(level: 4, stars: 3, taps: 33, time: 18.0);

      final record = progress.recordFor(4);
      expect(record.stars, 3, reason: 'better stars should take');
      expect(record.bestTaps, 30, reason: 'the better tap count still stands');
      expect(record.bestTime, 18.0, reason: 'the faster time should take');
    });

    test('replaying an old level does not lock later ones again', () async {
      final progress = await Progress.load();
      await progress.recordWin(level: 1, stars: 3, taps: 10, time: 8.0);
      await progress.recordWin(level: 2, stars: 3, taps: 12, time: 9.0);
      expect(progress.unlocked, 3);

      await progress.recordWin(level: 1, stars: 1, taps: 25, time: 20.0);
      expect(progress.unlocked, 3, reason: 'progress went backwards');
    });

    test('everything survives a reload', () async {
      final first = await Progress.load();
      await first.recordWin(level: 1, stars: 3, taps: 11, time: 9.5);
      await first.recordWin(level: 2, stars: 2, taps: 19, time: 14.0);
      await first.choosePet('fox');

      final second = await Progress.load();
      expect(second.unlocked, 3);
      expect(second.totalStars, 5);
      expect(second.recordFor(1).stars, 3);
      expect(second.recordFor(1).bestTaps, 11);
      expect(second.recordFor(2).bestTime, 14.0);
      expect(second.pet, 'fox');
    });

    test('total stars adds up across levels', () async {
      final progress = await Progress.load();
      await progress.recordWin(level: 1, stars: 3, taps: 10, time: 8.0);
      await progress.recordWin(level: 2, stars: 2, taps: 10, time: 8.0);
      await progress.recordWin(level: 3, stars: 1, taps: 10, time: 8.0);
      expect(progress.totalStars, 6);
      expect(progress.completedLevels, 3);
      expect(progress.masteredLevels, 1);
    });

    test('the furthest endless clear is the only endless progress', () async {
      final progress = await Progress.load();
      await progress.recordEndlessClear(level: 114);
      expect(progress.endlessBest, 114);

      await progress.recordEndlessClear(level: 110);
      expect(progress.endlessBest, 114, reason: 'the furthest still stands');
      expect(progress.recordFor(114).played, isFalse);
      expect(progress.totalStars, 0);
      expect(progress.unlocked, 1);
    });

    test('legacy endless records cannot add campaign stars', () async {
      SharedPreferences.setMockInitialValues({
        'lvl_2_stars': 2,
        'lvl_114_stars': 3,
      });
      final progress = await Progress.load();
      expect(progress.totalStars, 2);
      expect(progress.completedLevels, 1);
      expect(progress.masteredLevels, 0);
    });

    test('reset clears everything', () async {
      final progress = await Progress.load();
      await progress.recordWin(level: 5, stars: 3, taps: 10, time: 8.0);
      await progress.reset();

      expect(progress.unlocked, 1);
      expect(progress.totalStars, 0);
      expect(progress.recordFor(5).played, isFalse);
    });
  });
}
