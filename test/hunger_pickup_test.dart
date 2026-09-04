import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/systems/hunger_system.dart';
import 'package:hexcape/systems/pickup_system.dart';

void main() {
  group('HungerSystem', () {
    test('capacity scales with the length of the journey', () {
      final hunger = HungerSystem();
      hunger.reset(par: 20, secondsPerCell: 1.7);
      expect(hunger.capacity, closeTo(34, 1e-9));
      expect(hunger.remaining, hunger.capacity);
      expect(hunger.fraction, 1.0);

      // A longer route gets proportionally longer, so a bigger level is not
      // automatically a harder one.
      hunger.reset(par: 40, secondsPerCell: 1.7);
      expect(hunger.capacity, closeTo(68, 1e-9));
    });

    test('drains to empty and reports starvation exactly at zero', () {
      final hunger = HungerSystem()..reset(par: 10, secondsPerCell: 1.0);
      expect(hunger.isStarved, isFalse);

      for (var i = 0; i < 9 * 60; i++) {
        hunger.drain(1 / 60);
      }
      expect(hunger.isStarved, isFalse, reason: 'a second still left');
      expect(hunger.remaining, closeTo(1.0, 0.02));

      for (var i = 0; i < 70; i++) {
        hunger.drain(1 / 60);
      }
      expect(hunger.isStarved, isTrue);
      expect(hunger.fraction, 0);
    });

    test('the low warning fires once, not once per frame', () {
      final hunger = HungerSystem()..reset(par: 10, secondsPerCell: 1.0);
      var warnings = 0;
      for (var i = 0; i < 10 * 60; i++) {
        if (hunger.drain(1 / 60)) {
          warnings++;
        }
      }
      expect(warnings, 1, reason: 'one pulse into the red, not a buzzing HUD');
    });

    test('a treat refills without ever overfilling the bar', () {
      final hunger = HungerSystem()..reset(par: 10, secondsPerCell: 1.0);
      for (var i = 0; i < 5 * 60; i++) {
        hunger.drain(1 / 60);
      }
      expect(hunger.remaining, closeTo(5, 0.02));

      hunger.feed(3);
      expect(hunger.remaining, closeTo(8, 0.02));

      // A bar that could read past full would make the gauge meaningless.
      hunger.feed(100);
      expect(hunger.remaining, hunger.capacity);
      expect(hunger.fraction, 1.0);
    });

    test('feeding out of the red re-arms the warning', () {
      final hunger = HungerSystem()..reset(par: 10, secondsPerCell: 1.0);
      var warnings = 0;
      for (var i = 0; i < 8 * 60; i++) {
        if (hunger.drain(1 / 60)) {
          warnings++;
        }
      }
      expect(warnings, 1);

      hunger.feed(6);
      for (var i = 0; i < 8 * 60; i++) {
        if (hunger.drain(1 / 60)) {
          warnings++;
        }
      }
      expect(
        warnings,
        2,
        reason: 'the second slide into the red must warn too',
      );
    });
  });

  group('ActiveEffects', () {
    test('a powerup runs for its duration and then stops', () {
      final effects = ActiveEffects()..grant(PickupKind.freeze);
      expect(effects.regrowthPaused, isTrue);

      effects.update(PickupKind.freeze.duration - 0.1);
      expect(effects.regrowthPaused, isTrue);

      effects.update(0.2);
      expect(effects.regrowthPaused, isFalse);
    });

    test('each powerup changes only its own thing', () {
      final effects = ActiveEffects();
      expect(effects.tapRadiusMultiplier, 1.0);
      expect(effects.speedMultiplier, 1.0);
      expect(effects.regrowthPaused, isFalse);
      expect(effects.scentActive, isFalse);

      effects.grant(PickupKind.radiusPlus);
      expect(effects.tapRadiusMultiplier, ActiveEffects.radiusMultiplier);
      expect(effects.speedMultiplier, 1.0);
      expect(effects.regrowthPaused, isFalse);

      effects.grant(PickupKind.sprint);
      expect(effects.speedMultiplier, ActiveEffects.sprintMultiplier);
      expect(effects.regrowthPaused, isFalse);

      effects.grant(PickupKind.freeze);
      expect(effects.regrowthPaused, isTrue);

      effects.grant(PickupKind.scent);
      expect(effects.scentActive, isTrue);
    });

    test('sprint speeds her up rather than slowing her down', () {
      // The powerup it replaces capped her speed, which on a hunger clock spent
      // the one resource the player is always short of. If this ever reads
      // below 1 again, that regression is back.
      expect(ActiveEffects.sprintMultiplier, greaterThan(1.0));
    });

    test('charges are held until spent, not run down by time', () {
      final effects = ActiveEffects()..grant(PickupKind.blast);
      expect(effects.has(PickupKind.blast), isTrue);
      expect(effects.leading, isNull, reason: 'a charge has no time to show');

      // Any amount of time passing leaves it untouched.
      effects.update(600);
      expect(effects.has(PickupKind.blast), isTrue);

      expect(effects.spend(PickupKind.blast), isTrue);
      expect(effects.has(PickupKind.blast), isFalse);
      expect(effects.spend(PickupKind.blast), isFalse);
    });

    test('charges stack and are spent one at a time', () {
      final effects = ActiveEffects()
        ..grant(PickupKind.dig)
        ..grant(PickupKind.dig);
      expect(effects.chargesOf(PickupKind.dig), 2);
      expect(effects.spend(PickupKind.dig), isTrue);
      expect(effects.chargesOf(PickupKind.dig), 1);
      expect(effects.heldCharges.single.count, 1);

      effects.clear();
      expect(effects.heldCharges, isEmpty);
    });

    test('every powerup is either timed or a charge, never neither', () {
      // A kind that is neither would be granted and then silently do nothing.
      for (final kind in PickupKind.values.where((k) => k.isPowerup)) {
        expect(
          kind.isCharge || kind.duration > 0,
          isTrue,
          reason: '${kind.name} does nothing when granted',
        );
      }
    });

    test('a treat is not a powerup and grants no duration', () {
      final effects = ActiveEffects()..grant(PickupKind.treat);
      expect(effects.leading, isNull);
      expect(effects.isActive(PickupKind.treat), isFalse);
    });

    test('the ring follows whichever effect has longest to run', () {
      final effects = ActiveEffects()
        ..grant(PickupKind.freeze)
        ..grant(PickupKind.radiusPlus);

      // Radius+ lasts longer than freeze, so it owns the ring.
      expect(effects.leading!.kind, PickupKind.radiusPlus);
      expect(effects.leading!.fraction, closeTo(1.0, 1e-9));

      effects.update(PickupKind.radiusPlus.duration / 2);
      expect(effects.leading!.fraction, closeTo(0.5, 1e-9));

      effects.clear();
      expect(effects.leading, isNull);
    });
  });

  group('PickupSystem', () {
    List<HexCoord> routeOf(GeneratedLevel level) =>
        Pathfinder.cheapestPath(
          level.grid.start,
          level.grid.exit,
          level.grid.isTraversableInPrinciple,
          (c) => level.grid.cells[c]!.type.hitsRequired,
        ) ??
        const [];

    test('pickups sit off the route, never on it', () {
      // On the route they would be collected in passing, which is scenery
      // rather than a decision.
      for (var seed = 0; seed < 60; seed++) {
        final level = LevelGenerator.generate(LevelSpec(seed: seed));
        final route = routeOf(level).toSet();
        for (final pickup in level.pickups) {
          expect(
            route.contains(pickup.coord),
            isFalse,
            reason: 'seed $seed put a ${pickup.kind.name} on the ideal route',
          );
        }
      }
    });

    test('every pickup can actually be reached', () {
      for (var seed = 0; seed < 60; seed++) {
        final level = LevelGenerator.generate(
          LevelSpec(seed: seed, anchorDensity: 0.35),
        );
        for (final pickup in level.pickups) {
          expect(
            Pathfinder.reachable(
              level.grid.start,
              pickup.coord,
              level.grid.isTraversableInPrinciple,
            ),
            isTrue,
            reason: 'seed $seed sealed a ${pickup.kind.name} behind anchors',
          );
        }
      }
    });

    test('pickups spread out instead of clustering in one corner', () {
      for (var seed = 0; seed < 40; seed++) {
        final level = LevelGenerator.generate(LevelSpec(seed: seed));
        final coords = [for (final p in level.pickups) p.coord];
        for (var i = 0; i < coords.length; i++) {
          for (var j = i + 1; j < coords.length; j++) {
            expect(
              coords[i].distanceTo(coords[j]),
              greaterThanOrEqualTo(PickupSystem.minSpacing),
              reason: 'seed $seed clustered two pickups',
            );
          }
        }
      }
    });

    test('never on the dog or the food', () {
      for (var seed = 0; seed < 60; seed++) {
        final level = LevelGenerator.generate(LevelSpec(seed: seed));
        for (final pickup in level.pickups) {
          expect(pickup.coord, isNot(level.grid.start), reason: 'seed $seed');
          expect(pickup.coord, isNot(level.grid.exit), reason: 'seed $seed');
        }
      }
    });

    test('the same seed always scatters them the same way', () {
      for (final seed in [0, 7, 99]) {
        final a = LevelGenerator.generate(LevelSpec(seed: seed)).pickups;
        final b = LevelGenerator.generate(LevelSpec(seed: seed)).pickups;
        expect(a.length, b.length);
        for (var i = 0; i < a.length; i++) {
          expect(a[i].coord, b[i].coord);
          expect(a[i].kind, b[i].kind);
        }
      }
    });

    test('the requested mix is what gets placed', () {
      final level = LevelGenerator.generate(
        const LevelSpec(seed: 3, treats: 3, powerups: 2),
      );
      final treats = level.pickups.where((p) => p.kind == PickupKind.treat);
      final powerups = level.pickups.where((p) => p.kind.isPowerup);
      expect(treats.length, 3);
      expect(powerups.length, 2);
      // Cycling the kinds keeps a level from offering the same thing twice.
      expect(powerups.map((p) => p.kind).toSet().length, 2);
    });

    test('collecting takes a pickup once and only once', () {
      final level = LevelGenerator.generate(const LevelSpec(seed: 5));
      final pickups = level.pickups;
      expect(pickups, isNotEmpty);
      final target = pickups.first;

      expect(PickupSystem.collect(pickups, const HexCoord(999, 999)), isNull);

      final taken = PickupSystem.collect(pickups, target.coord);
      expect(taken, same(target));
      expect(target.collected, isTrue);
      expect(target.collectFlash, 1);

      expect(
        PickupSystem.collect(pickups, target.coord),
        isNull,
        reason: 'a treat must not pay out twice',
      );
    });

    test('a level with no pickups asked for places none', () {
      final level = LevelGenerator.generate(
        const LevelSpec(seed: 11, treats: 0, powerups: 0),
      );
      expect(level.pickups, isEmpty);
    });

    test('placement survives a heavily anchored board', () {
      final rng = math.Random(1);
      for (var seed = 0; seed < 30; seed++) {
        final level = LevelGenerator.generate(
          LevelSpec(seed: seed, anchorDensity: 0.45),
        );
        expect(level.pickups.length, lessThanOrEqualTo(5));
        // It may place fewer when the board is tight, but never duplicates.
        final coords = [for (final p in level.pickups) p.coord];
        expect(coords.toSet().length, coords.length);
      }
      expect(rng.nextInt(2), anyOf(0, 1));
    });
  });
}
