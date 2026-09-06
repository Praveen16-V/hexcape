import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/guard.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/systems/guard_system.dart';

void main() {
  group('The new tiles', () {
    test('hardpan and tremor cost what their faces promise', () {
      expect(HexType.hardpan.hitsRequired, 3);
      expect(HexType.heavy.hitsRequired, 2);
      expect(HexType.tremor.hitsRequired, 2);
      expect(HexType.plain.hitsRequired, 1);
      expect(HexType.thatch.hitsRequired, 1);
    });

    test('walls refuse taps, and refuse in the shared vocabulary', () {
      for (final wall in const [HexType.anchor, HexType.overgrowth]) {
        expect(wall.blocksTaps, isTrue, reason: '$wall is a wall');
        expect(wall.isDiggable, isTrue, reason: '$wall answers only DIG');
      }
      final gate = HexCell(const HexCoord(0, 0), HexType.gate);
      // A closed gate reports neither wall nor hit: it has its own answer.
      expect(gate.isLockedGate, isTrue);
      expect(gate.isClearable, isFalse);
      gate.gateOpen = true; // its switch was flipped, so the crest heard it
      expect(gate.isLockedGate, isFalse);
      expect(gate.isClearable, isTrue);
    });

    test('a mirror opens only when the pair agrees', () {
      final a = HexCell(const HexCoord(0, 0), HexType.mirror)
        ..partner = const HexCoord(3, 3)
        ..link = 1;
      final b = HexCell(const HexCoord(3, 3), HexType.mirror)
        ..partner = const HexCoord(0, 0)
        ..link = 1;
      expect(a.hit(0), isFalse); // a charge is not an opening
      expect(a.charged, isTrue);
      expect(a.isPassable, isFalse);
      // Charging the twin while the first is armed completes the pair.
      expect(b.hit(0), isFalse);
      expect(b.charged, isTrue);
      // Completion is the game's job when it sees the pair agree — bar/mirror
      // state lives on the cells; _carveMirror is the keeper of the rule.
      a.clear(0);
      b.clear(0);
      expect(a.isPassable, isTrue);
      expect(b.isPassable, isTrue);
    });

    test('contact ground is typed apart from throw tiles', () {
      for (final t in HexType.values) {
        final isContactHazard = t == HexType.thorn || t == HexType.alarm;
        expect(
          t.throwsHer || t.pushesContinuously ? isContactHazard : true,
          isTrue,
          reason: '$t cannot both throw and bite',
        );
      }
    });

    test('the push tiles announce themselves', () {
      expect(HexType.eddy.pushesContinuously, isTrue);
      expect(HexType.magnet.pushesContinuously, isTrue);
      expect(HexType.ice.pushesContinuously, isFalse);
    });
  });

  group('The new lights', () {
    HexCoord c(int q, int r) => HexCoord(q, r);

    Guard unit(GuardKind kind, List<HexCoord> route, {double speed = 2}) =>
        Guard(patrol: route, kind: kind, cellsPerSecond: speed);

    test('every kind blocks exactly one of the two doors', () {
      expect(unit(GuardKind.patrol, [c(0, 0), c(1, 0)]).blocksDog, isTrue);
      expect(unit(GuardKind.patrol, [c(0, 0), c(1, 0)]).wardsTaps, isFalse);
      expect(unit(GuardKind.sentry, [c(0, 0), c(1, 0)]).blocksDog, isFalse);
      expect(unit(GuardKind.sentry, [c(0, 0), c(1, 0)]).wardsTaps, isTrue);
      expect(unit(GuardKind.beacon, [c(0, 0)]).blocksDog, isFalse);
      expect(unit(GuardKind.beacon, [c(0, 0)]).wardsTaps, isTrue);
      expect(unit(GuardKind.blinker, [c(0, 0)]).wardsTaps, isTrue);
      expect(unit(GuardKind.spinner, [c(0, 0), c(1, 0)]).blocksDog, isTrue);
      expect(unit(GuardKind.runner, [c(0, 0), c(3, 0)]).blocksDog, isTrue);
      expect(unit(GuardKind.warden, [c(0, 0), c(1, 0)]).blocksDog, isTrue);
    });

    test('a blinker keeps its beat', () {
      final guard = unit(GuardKind.blinker, [c(0, 0)]);
      // Dark first, by contract: the off-half opens the rhythm.
      guard.update(Guard.blinkDark - 0.01);
      expect(guard.lampOn, isFalse);
      expect(guard.lit, isEmpty);
      guard.update(0.02);
      expect(guard.lampOn, isTrue);
      expect(guard.lit, isNotEmpty);
      guard.update(Guard.blinkLit + Guard.blinkDark - 0.04);
      expect(guard.lampOn, isTrue);
    });

    test('a runner pauses at its ends', () {
      final guard = unit(GuardKind.runner, [c(0, 0), c(3, 0)], speed: 2.5);
      var t = 0.0;
      var sawPause = false;
      for (var i = 0; i < 600; i++) {
        guard.update(1 / 60);
        t += 1 / 60;
        if (guard.windUp > 0) {
          sawPause = true;
        }
        if (sawPause && guard.windUp == 0 && t > 3) {
          break;
        }
      }
      expect(sawPause, isTrue, reason: 'the keep-back bow must appear');
    });

    test('a spinner never turns around', () {
      final ring = [c(1, 0), c(0, 1), c(-1, 1), c(-1, 0), c(0, -1), c(1, -1)];
      final guard = unit(GuardKind.spinner, ring, speed: 1.5);
      final seen = <int>{};
      for (var i = 0; i < 400; i++) {
        guard.update(1 / 60);
        seen.add(guard.index);
      }
      expect(seen.length, greaterThan(4), reason: 'the ring completes');
      expect(guard.loops, isTrue);
    });

    test('the light placements stay mixed when asked for several kinds', () {
      final grid = LevelGenerator.generate(
        LevelSpec(
          seed: 77,
          columns: 13,
          rows: 11,
          guards: 1,
          blinkers: 1,
          runners: 1,
          wardens: 1,
        ),
      ).grid;
      final guards = GuardSystem.place(
        grid: grid,
        rng: math.Random(99),
        count: 1,
        blinkers: 1,
        runners: 1,
        wardens: 1,
      );
      final kinds = {for (final g in guards) g.kind};
      expect(kinds.length, guards.length);
    });
  });

  group('The new pickups', () {
    test('the roster is thirty, no more and no fewer', () {
      expect(PickupKind.values.length, 30);
    });

    test('charges classify themselves', () {
      for (final kind in PickupKind.values) {
        if (kind.isCharge) {
          expect(kind.isPassive, isFalse);
          if (!kind.needsTarget) {
            // The board-blind four: time, not place.
            expect(
              const [
                PickupKind.rewind,
                PickupKind.harvest,
                PickupKind.whistle,
                PickupKind.beacon,
              ].contains(kind),
              isTrue,
              reason: '$kind needs no target and is not one of the four',
            );
          }
        }
      }
    });

    test('passives last the run and are spent on use', () {
      final effects = ActiveEffects();
      effects.grant(PickupKind.ironpaw);
      effects.grant(PickupKind.pouch);
      expect(effects.hasPassive(PickupKind.ironpaw), isTrue);
      expect(effects.hasPassive(PickupKind.pouch), isTrue);
      // Pouch is a one-shot; ironpaw is forever.
      expect(effects.consumePassive(PickupKind.pouch), isTrue);
      expect(effects.hasPassive(PickupKind.pouch), isFalse);
      effects.update(60);
      expect(effects.hasPassive(PickupKind.ironpaw), isTrue);
    });

    test('timed flags tick down and nothing else', () {
      final effects = ActiveEffects();
      effects.grant(PickupKind.cloak);
      effects.grant(PickupKind.wardown);
      expect(effects.cloakActive, isTrue);
      expect(effects.wardownActive, isTrue);
      effects.update(PickupKind.cloak.duration + 0.01);
      expect(effects.cloakActive, isFalse);
      expect(effects.wardownActive, isFalse);
    });
  });

  group('Campaign gating', () {
    test('mire exists where the campaign promises it, never before', () {
      final early = Campaign.rulesFor(4);
      final mid = Campaign.rulesFor(8);
      expect(early.mireDensity, 0);
      expect(mid.mireDensity, greaterThan(0));
    });

    test('the privacy of lights: count tables only fire past the gate', () {
      final before = Campaign.rulesFor(Campaign.blinkerFrom - 1);
      final at = Campaign.rulesFor(Campaign.blinkerFrom);
      expect(before.blinkers, 0);
      expect(at.blinkers, 1);
    });

    test('the gloom is a band, not a sprinkle', () {
      expect(Campaign.rulesFor(Campaign.gloomFrom - 1).gloom, isFalse);
      expect(Campaign.rulesFor(Campaign.gloomFrom).gloom, isTrue);
    });
  });
}
