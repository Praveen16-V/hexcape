import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/entitlements.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('What the player may play', () {
    test('the free game is free, bought or not', () {
      // The one rule that must never break. A regression here charges people
      // for the demo.
      for (var level = 1; level <= Entitlements.freeThrough; level++) {
        for (final owned in [true, false]) {
          expect(
            Entitlements.accessTo(level, unlocked: 60, owned: owned),
            LevelAccess.open,
            reason: 'level $level was gated with owned=$owned',
          );
        }
      }
    });

    test('the free band ends exactly on a band boundary', () {
      // If the cut ever lands mid-band the player stops in the middle of a
      // difficulty ramp, with the band's own name still on screen.
      expect(Entitlements.freeThrough, Campaign.foundationEnd);
      expect(
        Campaign.bandOf(Entitlements.freeThrough),
        isNot(Campaign.bandOf(Entitlements.freeThrough + 1)),
        reason: 'the last free level and the first paid one are the same band',
      );
    });

    test('past the free band, unbought levels report the purchase', () {
      for (
        var level = Entitlements.freeThrough + 1;
        level <= Campaign.length + 5;
        level++
      ) {
        expect(
          Entitlements.accessTo(level, unlocked: 999, owned: false),
          LevelAccess.needsPurchase,
          reason: 'level $level did not ask to be bought',
        );
      }
    });

    test('a level that is both unreached and unbought asks to be bought', () {
      // It is the one the player can actually act on. Telling them to finish a
      // level they cannot open is a dead end.
      expect(
        Entitlements.accessTo(40, unlocked: 1, owned: false),
        LevelAccess.needsPurchase,
      );
    });

    test('buying does not skip the campaign', () {
      // Ownership opens the *band*, not the levels. Someone who pays at level
      // 20 still has to play 21 before 22.
      expect(
        Entitlements.accessTo(40, unlocked: 21, owned: true),
        LevelAccess.needsProgress,
      );
      expect(
        Entitlements.accessTo(21, unlocked: 21, owned: true),
        LevelAccess.open,
      );
    });

    test('owning never reduces access', () {
      for (var level = 1; level <= Campaign.length + 5; level++) {
        for (final unlocked in [1, 20, 21, 60, 80]) {
          final free = Entitlements.accessTo(
            level,
            unlocked: unlocked,
            owned: false,
          );
          final paid = Entitlements.accessTo(
            level,
            unlocked: unlocked,
            owned: true,
          );
          if (free == LevelAccess.open) {
            expect(
              paid,
              LevelAccess.open,
              reason: 'buying closed level $level at unlocked=$unlocked',
            );
          }
        }
      }
    });

    test('endless is part of the purchase', () {
      expect(
        Entitlements.accessTo(Campaign.length + 1, unlocked: 999, owned: false),
        LevelAccess.needsPurchase,
      );
      expect(
        Entitlements.accessTo(Campaign.length + 1, unlocked: 999, owned: true),
        LevelAccess.open,
      );
    });

    test('with no store at all, the free game still plays', () {
      // Billing is unavailable on some devices and absent offline. `owned`
      // false is exactly that state, and it must not lock anything free.
      for (var level = 1; level <= Entitlements.freeThrough; level++) {
        expect(
          Entitlements.canPlay(level, unlocked: level, owned: false),
          isTrue,
        );
      }
    });
  });

  group('What the reference may reveal', () {
    test('an unbought player is not shown the paid mechanics', () {
      // Sitting at the paywall, `unlocked` is 21 — one past the free band — so
      // an unclamped reference would hand them the patrol entry.
      expect(
        Entitlements.revealCeiling(unlocked: 21, owned: false),
        Entitlements.freeThrough,
      );
      expect(
        Entitlements.revealCeiling(unlocked: 60, owned: false),
        Entitlements.freeThrough,
      );
    });

    test('it never reveals more than the player has reached', () {
      for (final unlocked in [1, 5, 20, 21, 60]) {
        for (final owned in [true, false]) {
          expect(
            Entitlements.revealCeiling(unlocked: unlocked, owned: owned),
            lessThanOrEqualTo(unlocked),
            reason: 'ceiling ran ahead of progress at $unlocked/$owned',
          );
        }
      }
    });

    test('buying reveals the rest', () {
      expect(Entitlements.revealCeiling(unlocked: 60, owned: true), 60);
    });
  });

  group('The purchase, stored', () {
    test('defaults to not owned', () async {
      final p = await Progress.load();
      expect(p.ownsFullGame, isFalse);
    });

    test('survives a reload', () async {
      final p = await Progress.load();
      await p.setOwnsFullGame(true);
      final reopened = await Progress.load();
      expect(reopened.ownsFullGame, isTrue);
    });

    test('erasing progress is not un-buying the game', () async {
      final p = await Progress.load();
      await p.setOwnsFullGame(true);
      await p.recordWin(level: 3, stars: 3, taps: 10, time: 5);

      await p.reset();
      expect(p.unlocked, 1, reason: 'progress should have gone');
      expect(
        p.ownsFullGame,
        isTrue,
        reason: 'the player was refunded by a debug button',
      );
    });
  });

  group('The store integration', () {
    test('the product id is a single constant, referenced once', () {
      // A mismatch between this and the id in Play Console is silent: the
      // product simply never loads and the paywall shows no price.
      final source = File('lib/game/store.dart').readAsStringSync();
      expect(source, contains("kFullGameId = 'hexcape.full'"));
      // Used for the query and for filtering the purchase stream, and nowhere
      // is the literal repeated.
      expect(
        RegExp("'hexcape.full'").allMatches(source).length,
        1,
        reason: 'the product id is written out more than once',
      );
    });

    test('every purchase is completed', () {
      // An uncompleted purchase is redelivered forever and auto-refunded by
      // Google after a few days, which turns a sale into a support problem.
      final source = File('lib/game/store.dart').readAsStringSync();
      expect(
        RegExp('completePurchase').allMatches(source).length,
        greaterThanOrEqualTo(2),
        reason: 'purchases for other products must be completed too',
      );
    });
  });

  group('The one free look past the wall', () {
    test('is offered on the first paid level, once it has been earned', () {
      expect(
        Entitlements.accessTo(
          Entitlements.trialLevel,
          unlocked: Entitlements.trialLevel,
          owned: false,
          trialUsed: false,
        ),
        LevelAccess.trial,
      );
    });

    test('sits exactly where patrols start', () {
      // The offer's central claim is that what follows puts patrols in her way.
      // If these ever drift apart the trial stops demonstrating the thing being
      // sold, which is its entire reason for existing.
      expect(Entitlements.trialLevel, Campaign.guardsFrom);
      expect(Campaign.rulesFor(Entitlements.trialLevel).guards, greaterThan(0));
    });

    test('has to be earned, not merely reached for', () {
      // Someone still on level three is not owed the free look: spending it
      // there skips the twenty levels that give it its weight.
      expect(
        Entitlements.accessTo(
          Entitlements.trialLevel,
          unlocked: 3,
          owned: false,
          trialUsed: false,
        ),
        LevelAccess.needsPurchase,
      );
    });

    test('is spent once, and only covers the one level', () {
      expect(
        Entitlements.accessTo(
          Entitlements.trialLevel,
          unlocked: 99,
          owned: false,
          trialUsed: true,
        ),
        LevelAccess.needsPurchase,
      );
      // The level after it is never free, spent or not.
      for (final used in [true, false]) {
        expect(
          Entitlements.accessTo(
            Entitlements.trialLevel + 1,
            unlocked: 99,
            owned: false,
            trialUsed: used,
          ),
          LevelAccess.needsPurchase,
          reason: 'trialUsed=$used leaked the level past the trial',
        );
      }
    });

    test('is playable, and callers that ignore it are unaffected', () {
      expect(
        Entitlements.canPlay(
          Entitlements.trialLevel,
          unlocked: Entitlements.trialLevel,
          owned: false,
          trialUsed: false,
        ),
        isTrue,
      );
      // The default is "already spent", so nothing that has not been taught
      // about the trial can hand it out by accident.
      expect(
        Entitlements.canPlay(
          Entitlements.trialLevel,
          unlocked: Entitlements.trialLevel,
          owned: false,
        ),
        isFalse,
      );
    });

    test('never changes anything for someone who has bought the game', () {
      for (final used in [true, false]) {
        expect(
          Entitlements.accessTo(
            Entitlements.trialLevel,
            unlocked: 99,
            owned: true,
            trialUsed: used,
          ),
          LevelAccess.open,
        );
      }
    });

    test('lifts the reference ceiling by exactly the level it covers', () {
      expect(
        Entitlements.revealCeiling(unlocked: 99, owned: false),
        Entitlements.freeThrough,
      );
      expect(
        Entitlements.revealCeiling(unlocked: 99, owned: false, trialUsed: true),
        Entitlements.trialLevel,
      );
    });

    test('survives a restart, and comes back with a wiped save', () async {
      SharedPreferences.setMockInitialValues({});
      final progress = await Progress.load();
      expect(progress.trialUsed, isFalse);
      await progress.setTrialUsed();
      expect((await Progress.load()).trialUsed, isTrue);

      // Reset is for progress, and the trial is only reachable by clearing
      // twenty levels — a wiped save has to be able to earn it again.
      await progress.reset();
      expect((await Progress.load()).trialUsed, isFalse);
    });

    test('resetting progress does not un-buy the game', () async {
      SharedPreferences.setMockInitialValues({});
      final progress = await Progress.load();
      await progress.setOwnsFullGame(true);
      await progress.reset();
      expect((await Progress.load()).ownsFullGame, isTrue);
    });
  });
}
