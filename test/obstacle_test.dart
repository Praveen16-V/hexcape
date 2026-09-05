import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/entities/guard.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/gen/silhouette.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/systems/guard_system.dart';

final _layout = HexLayout(size: 24, origin: const Offset(400, 400));

HexGrid _gridOf(Map<HexCoord, HexCell> cells, {HexCoord? exit}) => HexGrid(
  cells: cells,
  start: cells.keys.first,
  exit: exit ?? cells.keys.last,
  truePath: const [],
);

void main() {
  group('Springs', () {
    test('cost one tap, exactly like a plain hex', () {
      // If a spring cost two, par would quietly rise on every board carrying
      // one and the budget would stop matching the level.
      expect(HexType.spring.hitsRequired, HexType.plain.hitsRequired);
      expect(HexType.spring.isClearableType, isTrue);
    });

    test('never block a level', () {
      for (var seed = 0; seed < 24; seed++) {
        final level = LevelGenerator.generate(
          LevelSpec(
            seed: seed,
            columns: 12,
            rows: 25,
            anchorDensity: 0.34,
            heavyDensity: 0.26,
            springDensity: 0.10,
            shape: FieldShape.values[seed % FieldShape.values.length],
          ),
        );
        expect(
          Pathfinder.reachable(
            level.grid.start,
            level.grid.exit,
            level.grid.isTraversableInPrinciple,
          ),
          isTrue,
          reason: 'seed $seed has no route',
        );
      }
    });

    test('are never placed adjacent to one another', () {
      // Two springs side by side would fling her off the first into the second
      // and out of the player's hands entirely.
      for (var seed = 0; seed < 20; seed++) {
        final level = LevelGenerator.generate(
          LevelSpec(seed: seed, springDensity: 0.14),
        );
        final springs = [
          for (final cell in level.grid.all)
            if (cell.type == HexType.spring) cell.coord,
        ];
        for (final a in springs) {
          for (final b in springs) {
            if (a == b) {
              continue;
            }
            expect(a.distanceTo(b), greaterThanOrEqualTo(2));
          }
        }
      }
    });

    test('never sit on the opening or the food', () {
      for (var seed = 0; seed < 20; seed++) {
        final level = LevelGenerator.generate(
          LevelSpec(seed: seed, springDensity: 0.14),
        );
        expect(level.grid.at(level.grid.start)!.type, isNot(HexType.spring));
        expect(level.grid.at(level.grid.exit)!.type, isNot(HexType.spring));
      }
    });

    test('a launch overrides her steering', () {
      final dog = Dog(
        position: const Offset(400, 400),
        cell: const HexCoord(0, 0),
      );
      dog.launch(const Offset(1, 0), 200);
      expect(dog.isLaunched, isTrue);
      expect(dog.velocity.dx, closeTo(200, 1e-6));
      expect(dog.velocity.dy, closeTo(0, 1e-6));
    });

    test('a launch from a standstill does nothing', () {
      // Direction comes from the way she was already walking. Firing her
      // somewhere arbitrary because she happened to be still would be a
      // teleport, not a spring.
      final dog = Dog(
        position: const Offset(400, 400),
        cell: const HexCoord(0, 0),
      );
      dog.launch(Offset.zero, 200);
      expect(dog.isLaunched, isFalse);
      expect(dog.velocity, Offset.zero);
    });

    test('a launched dog cannot pass through a wall on a dropped frame', () {
      // Collision tests the cell she is moving *into*, which is only sound
      // while one frame's travel is under a hex. At a steady sixty frames a
      // launch covers about a seventh of a hex and nothing can go wrong — but
      // a single long frame carries her most of two cells, and she steps clean
      // over the wall between them. Dropped frames are not hypothetical here;
      // they are the stutter that started this whole round of work.
      final cells = <HexCoord, HexCell>{
        for (var q = -4; q <= 4; q++)
          for (var r = -4; r <= 4; r++)
            HexCoord(q, r): HexCell(HexCoord(q, r), HexType.plain),
      };
      final grid = _gridOf(cells, exit: const HexCoord(4, 0));
      for (var q = 0; q <= 4; q++) {
        grid.at(HexCoord(q, 0))!.clear(0);
      }
      // ...then wall the corridor off three cells along.
      grid.at(const HexCoord(3, 0))!.resetToSolid();

      final dog = Dog(
        position: _layout.toPixel(const HexCoord(0, 0)),
        cell: const HexCoord(0, 0),
      );
      dog.launch(const Offset(1, 0), _layout.width * 9);

      final tuning = TuningConfig();
      // A 200ms hitch, which is roughly what the frame-time readout showed
      // before the renderer was batched.
      for (var i = 0; i < 8; i++) {
        dog.update(
          dt: 0.2,
          grid: grid,
          layout: _layout,
          tuning: tuning,
          fieldVersion: 1,
          regrowthActive: false,
        );
        expect(
          grid.at(dog.cell)?.isSolid ?? true,
          isFalse,
          reason: 'she ended up inside solid rock at step $i',
        );
        expect(dog.cell.q, lessThan(3), reason: 'she tunnelled past the wall');
      }
    });
  });

  group('Patrols', () {
    test('a patrol walks its route and comes back', () {
      final guard = Guard(
        patrol: const [HexCoord(0, 0), HexCoord(1, 0), HexCoord(2, 0)],
        cellsPerSecond: 1,
      );
      final visited = <HexCoord>[];
      for (var i = 0; i < 8; i++) {
        visited.add(guard.cell);
        guard.update(1);
      }
      expect(visited, const [
        HexCoord(0, 0),
        HexCoord(1, 0),
        HexCoord(2, 0),
        HexCoord(1, 0),
        HexCoord(0, 0),
        HexCoord(1, 0),
        HexCoord(2, 0),
        HexCoord(1, 0),
      ]);
    });

    test('a patrol never runs off its route however long it walks', () {
      final guard = Guard(
        patrol: const [HexCoord(0, 0), HexCoord(1, 0)],
        cellsPerSecond: 3.7,
      );
      for (var i = 0; i < 5000; i++) {
        guard.update(1 / 60);
        expect(guard.index, inInclusiveRange(0, 1));
      }
    });

    test('the lit ground matches where the lamp is drawn', () {
      // Held at the old cell for a whole step, the drawn lamp and the forbidden
      // ground disagree by up to a full hex and being caught looks like a bug.
      final guard = Guard(
        patrol: const [HexCoord(0, 0), HexCoord(1, 0)],
        cellsPerSecond: 1,
      );
      expect(guard.litCentre, const HexCoord(0, 0));
      guard.update(0.75);
      expect(guard.litCentre, const HexCoord(1, 0));
    });

    test('the light covers the cell it is on and everything touching it', () {
      final guard = Guard(
        patrol: const [HexCoord(0, 0), HexCoord(1, 0)],
        cellsPerSecond: 1,
      );
      expect(guard.lit.toSet(), {
        const HexCoord(0, 0),
        ...const HexCoord(0, 0).neighbours,
      });
    });

    test('patrols keep clear of both ends of the board', () {
      for (var seed = 0; seed < 24; seed++) {
        final level = LevelGenerator.generate(
          LevelSpec(seed: seed, columns: 12, rows: 25, guards: 3),
        );
        for (final guard in level.guards) {
          for (final cell in guard.patrol) {
            expect(
              cell.distanceTo(level.grid.start),
              greaterThanOrEqualTo(GuardSystem.clearanceFromStart),
              reason: 'seed $seed patrols the opening',
            );
            expect(
              cell.distanceTo(level.grid.exit),
              greaterThanOrEqualTo(GuardSystem.clearanceFromExit),
              reason: 'seed $seed patrols the food',
            );
          }
        }
      }
    });

    test('a patrol is a sweep, not a knot', () {
      // An unbiased random walk on a hex grid coils into a two-cell blob, which
      // is a guard standing still with extra steps.
      var totalSpan = 0;
      var count = 0;
      for (var seed = 0; seed < 30; seed++) {
        final level = LevelGenerator.generate(
          LevelSpec(seed: seed, columns: 12, rows: 25, guards: 2),
        );
        for (final guard in level.guards) {
          totalSpan += guard.patrol.first.distanceTo(guard.patrol.last);
          count++;
        }
      }
      expect(count, greaterThan(10), reason: 'no patrols were placed at all');
      expect(totalSpan / count, greaterThan(2.0));
    });

    test('a level asked for no guards has none', () {
      final level = LevelGenerator.generate(const LevelSpec(seed: 4));
      expect(level.guards, isEmpty);
    });

    test('she refuses lit ground but never her own cell', () {
      // Standing in the light is something that happens *to* her. Treating her
      // own cell as impassable would leave the steering flood with no source at
      // all and freeze her exactly when she most needs to move.
      final cells = <HexCoord, HexCell>{
        for (var q = 0; q <= 4; q++)
          HexCoord(q, 0): HexCell(HexCoord(q, 0), HexType.plain),
      };
      final grid = _gridOf(cells, exit: const HexCoord(4, 0));
      for (final cell in grid.all) {
        cell.clear(0);
      }
      final dog = Dog(
        position: _layout.toPixel(const HexCoord(0, 0)),
        cell: const HexCoord(0, 0),
      );
      final tuning = TuningConfig();
      for (var i = 0; i < 30; i++) {
        dog.update(
          dt: 1 / 60,
          grid: grid,
          layout: _layout,
          tuning: tuning,
          fieldVersion: 1,
          regrowthActive: false,
          blocked: {const HexCoord(0, 0), const HexCoord(2, 0)},
        );
      }
      // She is free to move despite standing in the light, and has not crossed
      // the lit cell blocking her way to the food.
      expect(dog.cell.q, lessThan(2));
    });
  });

  group('Campaign gating', () {
    test('the tutorial meets neither springs nor patrols', () {
      for (var n = 1; n <= Campaign.tutorialBand; n++) {
        final rules = Campaign.rulesFor(n);
        expect(rules.springDensity, 0);
        expect(rules.guards, 0);
        expect(rules.faultDensity, 0);
      }
    });

    test('each obstacle arrives once and then stays', () {
      for (var n = 1; n < Campaign.springsFrom; n++) {
        expect(Campaign.rulesFor(n).springDensity, 0, reason: 'springs at $n');
      }
      for (var n = 1; n < Campaign.guardsFrom; n++) {
        expect(Campaign.rulesFor(n).guards, 0, reason: 'guards at $n');
      }
      for (var n = 1; n < Campaign.faultsFrom; n++) {
        expect(Campaign.rulesFor(n).faultDensity, 0, reason: 'faults at $n');
      }
      for (var n = Campaign.guardsFrom; n <= Campaign.length; n++) {
        expect(Campaign.rulesFor(n).guards, greaterThan(0));
        expect(Campaign.rulesFor(n).springDensity, greaterThan(0));
      }
      for (var n = Campaign.faultsFrom; n <= Campaign.length; n++) {
        expect(Campaign.rulesFor(n).faultDensity, greaterThan(0));
      }
    });

    test('the level that announces cracked ground actually has some', () {
      // Same floor, same reason as springs below: the band curve starts at
      // zero, so the level carrying the banner would otherwise promise a
      // mechanic the player never meets.
      final rules = Campaign.rulesFor(Campaign.faultsFrom);
      final level = LevelGenerator.generate(
        LevelSpec(
          seed: rules.seed,
          columns: rules.columns,
          rows: rules.rows,
          anchorDensity: rules.anchorDensity,
          heavyDensity: rules.heavyDensity,
          faultDensity: rules.faultDensity,
          shape: rules.shape,
        ),
      );
      final faults = level.grid.all
          .where((c) => c.type == HexType.fault)
          .length;
      expect(faults, greaterThanOrEqualTo(4), reason: 'only $faults faults');
    });

    test('the level that announces springs actually has some', () {
      // The band curve starts at zero density, so without a floor the level
      // carrying the banner generated a single spring on a 143-cell board — a
      // promise of a mechanic the player then never meets.
      final rules = Campaign.rulesFor(Campaign.springsFrom);
      final level = LevelGenerator.generate(
        LevelSpec(
          seed: rules.seed,
          columns: rules.columns,
          rows: rules.rows,
          anchorDensity: rules.anchorDensity,
          heavyDensity: rules.heavyDensity,
          springDensity: rules.springDensity,
          shape: rules.shape,
        ),
      );
      final springs = level.grid.all
          .where((c) => c.type == HexType.spring)
          .length;
      expect(springs, greaterThanOrEqualTo(3));
    });

    test('a mechanic is announced on the level it appears, and only there', () {
      expect(Campaign.rulesFor(Campaign.springsFrom).introduces, isNotNull);
      expect(Campaign.rulesFor(Campaign.guardsFrom).introduces, isNotNull);
      expect(Campaign.rulesFor(Campaign.pressureEnd + 1).introduces, isNotNull);
      // Announced anywhere else, the banner becomes noise the player learns to
      // ignore before it says something that matters.
      var announced = 0;
      for (var n = 1; n <= Campaign.length; n++) {
        if (Campaign.rulesFor(n).introduces != null) {
          announced++;
        }
      }
      expect(announced, 5);
    });

    test('the powerup pool only ever widens', () {
      var previous = <PickupKind>{};
      for (var n = 1; n <= Campaign.length + 20; n++) {
        final pool = Campaign.poolFor(n).toSet();
        expect(
          previous.difference(pool),
          isEmpty,
          reason: 'level $n withdrew a powerup the player had already met',
        );
        previous = pool;
      }
    });

    test('a pool never offers a treat or the same thing twice', () {
      // Treats are placed by count, not drawn from the powerup cycle; one
      // leaking into the pool would silently cost the level a powerup.
      for (var n = 1; n <= Campaign.length + 20; n++) {
        final pool = Campaign.poolFor(n);
        expect(pool, everyElement(isNot(PickupKind.treat)));
        expect(pool.toSet().length, pool.length, reason: 'duplicate at $n');
      }
    });

    test('levels do not all lead with the same powerup', () {
      final leads = <PickupKind>{};
      for (var n = Campaign.pressureEnd; n <= Campaign.length; n++) {
        final rules = Campaign.rulesFor(n);
        final pool = rules.offeredPowerups.where((k) => k.isPowerup).toList();
        leads.add(pool[rules.powerupRotation % pool.length]);
      }
      expect(leads.length, greaterThan(2));
    });

    test('every campaign level generates, is solvable, and drops only what it '
        'has unlocked', () {
      for (var n = 1; n <= Campaign.length; n += 3) {
        final rules = Campaign.rulesFor(n);
        final level = LevelGenerator.generate(
          LevelSpec(
            seed: rules.seed,
            columns: rules.columns,
            rows: rules.rows,
            anchorDensity: rules.anchorDensity,
            heavyDensity: rules.heavyDensity,
            springDensity: rules.springDensity,
            guards: rules.guards,
            guardSpeed: rules.guardSpeed,
            treats: rules.treats,
            powerups: rules.powerups,
            offeredPowerups: rules.offeredPowerups,
            powerupRotation: rules.powerupRotation,
            shape: rules.shape,
          ),
        );
        expect(level.par, greaterThan(0), reason: 'level $n');
        expect(
          Pathfinder.reachable(
            level.grid.start,
            level.grid.exit,
            level.grid.isTraversableInPrinciple,
          ),
          isTrue,
          reason: 'level $n has no route',
        );
        for (final pickup in level.pickups) {
          if (pickup.kind.isPowerup) {
            expect(
              rules.offeredPowerups,
              contains(pickup.kind),
              reason: 'level $n dropped a powerup it had not unlocked',
            );
          }
        }
      }
    });
  });

  group('Digging a wall', () {
    test('removing an anchor rebuilds the distances she steers by', () {
      // exitDistance used to be `late final`, so a dug wall left her routing
      // around a hole that was no longer there.
      final cells = <HexCoord, HexCell>{
        for (var q = 0; q <= 4; q++)
          HexCoord(q, 0): HexCell(HexCoord(q, 0), HexType.plain),
      };
      cells[const HexCoord(2, 0)]!.type = HexType.anchor;
      final grid = _gridOf(cells, exit: const HexCoord(4, 0));

      expect(grid.distanceToExit(const HexCoord(0, 0)), greaterThan(1000));

      cells[const HexCoord(2, 0)]!.type = HexType.plain;
      grid.invalidateTopology();
      expect(grid.distanceToExit(const HexCoord(0, 0)), 4);
    });
  });
}
