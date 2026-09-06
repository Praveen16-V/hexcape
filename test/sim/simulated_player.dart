import 'dart:math' as math;
import 'dart:ui';

import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/systems/hunger_system.dart';
import 'package:hexcape/systems/input_system.dart';
import 'package:hexcape/systems/pickup_system.dart';
import 'package:hexcape/systems/regrowth_system.dart';
import 'package:hexcape/systems/reveal_system.dart';
import 'package:hexcape/systems/softlock_system.dart';

/// Roughly the hex size the game lands on for a 480x1056 logical phone.
const layout = HexLayout(size: 23.7, origin: Offset.zero);

/// Taps for a level that does not ration them, matching the game's own.
const _unlimitedTaps = 1 << 20;

class SimResult {
  SimResult({
    required this.won,
    required this.taps,
    required this.seconds,
    required this.budget,
    required this.ranDry,
    required this.hungerCapacity,
    this.guardHits = 0,
    this.springLaunches = 0,
    this.reason = 'won',
  });

  final String reason;
  final bool won;
  final int taps;
  final double seconds;
  final int budget;

  /// Seconds of hunger this level was given, for the clock fairness gate.
  final double hungerCapacity;

  /// Whether the taps ran out before she reached the bone. Winning after that
  /// happens is the near-miss the budget exists to create.
  final bool ranDry;

  /// How many times a patrol caught her, and how many springs threw her.
  final int guardHits;
  final int springLaunches;

  int get spare => budget - taps;
}

/// Plays a level the way a competent player would: follow the *cheapest* route
/// (heavy hexes cost two taps, so the fewest-cells route is not always the
/// cheapest), open the next cell in front of her whenever it is inside the tap
/// radius, tap at a human rate, and let the drift do the rest.
///
/// Not an optimal player — she carves the route in front of her rather than
/// planning around regrowth — which is the point. The budget has to tolerate
/// competent play, not only perfect play.
///
/// **What this model does not do is as important as what it does.** It never
/// detours for a treat, never spends a dig on the wall that is actually in the
/// way, and never times a run to slip past a patrol. Those all take knowledge
/// it does not have, so every number it reports is a *floor*: a real player who
/// does any of them has an easier time than this. What it does model in full
/// are the things that happen *to* her whether she understands them or not —
/// regrowth, the clock, patrols, springs — because a floor that ignores the
/// hazards is not a floor, it is a fantasy.
SimResult play({
  required LevelSpec spec,
  required TuningConfig tuning,
  required bool regrowth,
  double tapInterval = 0.22,
  double limit = 70,
  bool hungerKills = true,
  bool budgetLimited = true,
}) {
  final level = LevelGenerator.generate(spec);
  final grid = level.grid;

  grid.at(grid.start)!.clear(0);
  final dog = Dog(position: layout.toPixel(grid.start), cell: grid.start);

  RevealSystem.reveal(
    grid: grid,
    layout: layout,
    dogPosition: layout.toPixel(grid.start),
    dogCell: grid.start,
    radius: RevealSystem.radiusFor(
      tuning.tapRadiusFor(layout.width),
      tuning.revealFactor,
    ),
  );

  final regrowthSystem = RegrowthSystem();
  final softlock = SoftlockSystem();
  final hunger = HungerSystem()
    ..reset(par: level.par, secondsPerCell: tuning.hungerSecondsPerCell);
  final powerups = ActiveEffects();
  final pickups = level.pickups;
  final guards = level.guards;

  var budget = budgetLimited
      ? (level.par * tuning.budgetMultiplier).ceil()
      : _unlimitedTaps;
  var guardedCells = <HexCoord>{};
  var caughtCooldown = 0.0;
  var springCooldown = 0.0;
  var guardHits = 0;
  var springLaunches = 0;
  var fieldVersion = 1;
  var taps = 0;
  var now = 0.0;
  var nextTapAt = 0.0;
  var lastProgressAt = 0.0;
  var bestDistance = grid.distanceToExit(grid.start);
  const dt = 1 / 60;

  SimResult finish(bool won, String reason) => SimResult(
    won: won,
    taps: taps,
    seconds: now,
    budget: budget,
    ranDry: taps >= budget,
    hungerCapacity: hunger.capacity,
    guardHits: guardHits,
    springLaunches: springLaunches,
    reason: reason,
  );

  while (now < limit) {
    now += dt;

    if (now >= nextTapAt && taps < budget) {
      final editable = InputSystem.editableCells(
        grid: grid,
        layout: layout,
        dogPosition: dog.position,
        tapRadius:
            tuning.tapRadiusFor(layout.width) * powerups.tapRadiusMultiplier,
      ).toList();

      // Carve locally toward the bone. The player can only edit within a
      // thumb's reach of the dog, so a global route is the wrong model: it
      // happily picks a cheap breakout point on the far side of the cleared
      // area and then nothing on it is ever in reach.
      //
      // Prefer cells that close the gap to the bone, and among those the
      // cheaper ones — which is what makes a heavy wall worth stepping around.
      // Straight hex distance, not the anchor-aware field: she can see where
      // the bone is, not what stands between.
      int score(HexCoord c) =>
          c.distanceTo(grid.exit) * 2 + grid.remainingCost(c);

      final here = dog.cell.distanceTo(grid.exit);
      HexCoord? pick(bool Function(HexCoord) accept) {
        HexCoord? best;
        for (final c in editable) {
          if (!accept(c)) {
            continue;
          }
          if (best == null || score(c) < score(best)) {
            best = c;
          }
        }
        return best;
      }

      // Carve when she stops making progress, rather than trying to guess how
      // much road is left.
      //
      // Counting "open cells nearer the bone" looks reasonable and is quietly
      // wrong twice over: cells behind an anchor wall are nearer in straight
      // hex distance but useless to her, and a pocket she has been cut off from
      // still counts. Both make the player wait for a journey that never
      // happens. Watching whether she actually closes the gap cannot lie.
      final target = now - lastProgressAt < 0.35
          ? null
          : pick((c) => c.distanceTo(grid.exit) < here) ??
                pick((c) => c.distanceTo(grid.exit) == here) ??
                pick((_) => true);

      if (target != null) {
        // A blast is strictly better than the tap it replaces, and needs no
        // judgement to use — so a competent player spends it the moment they
        // have one. Dig and scent are deliberately never used: knowing *which*
        // wall to break, or reading a route through fog, is exactly the
        // knowledge this model lacks.
        if (powerups.spend(PickupKind.blast)) {
          for (final c in target.disc(ActiveEffects.blastRadius)) {
            final cell = grid.at(c);
            if (cell != null && cell.isClearable) {
              cell
                ..revealed = true
                ..clear(now);
              fieldVersion++;
            }
          }
        } else if (grid.at(target)!.hit(now)) {
          fieldVersion++;
        }
        taps++;
        nextTapAt = now + tapInterval;
      }
    }

    hunger.drain(dt);
    powerups.update(dt);

    caughtCooldown = math.max(0, caughtCooldown - dt);
    springCooldown = math.max(0, springCooldown - dt);

    // Patrols step before she does, exactly as the game orders it, so the
    // ground she refuses to enter is where the light is now.
    if (guards.isNotEmpty) {
      for (final guard in guards) {
        guard.update(dt);
      }
      guardedCells = {
        for (final guard in guards)
          for (final c in guard.lit)
            if (grid.contains(c)) c,
      };
    }

    dog.update(
      dt: dt,
      grid: grid,
      layout: layout,
      tuning: tuning,
      fieldVersion: fieldVersion,
      regrowthActive: regrowth,
      speedMultiplier: powerups.speedMultiplier,
      blocked: guardedCells,
    );

    if (springCooldown <= 0 &&
        !dog.isLaunched &&
        grid.at(dog.cell)?.type == HexType.spring) {
      var direction = dog.velocity;
      if (direction.distance < 1e-3) {
        direction = Offset(math.cos(dog.facing), math.sin(dog.facing));
      }
      springCooldown = 0.6;
      dog.launch(direction, layout.width * 8.5);
      springLaunches++;
    }

    if (caughtCooldown <= 0 && guardedCells.contains(dog.cell)) {
      caughtCooldown = 1.6;
      hunger.bite(3.0);
      guardHits++;
      Offset? nearest;
      var bestGuard = double.infinity;
      for (final guard in guards) {
        final p = guard.positionIn(layout);
        final d = (p - dog.position).distanceSquared;
        if (d < bestGuard) {
          bestGuard = d;
          nearest = p;
        }
      }
      if (nearest != null) {
        dog.launch(dog.position - nearest, layout.width * 5.5, duration: 0.22);
      }
    }

    // She only picks up what she happens to walk over: this model never
    // detours for a treat, so the clock has to survive without them. That makes
    // every number below a floor rather than a best case.
    final taken = PickupSystem.collect(pickups, dog.cell);
    if (taken != null) {
      if (taken.kind == PickupKind.treat) {
        hunger.feed(tuning.treatSeconds);
        budget += tuning.treatTaps.round();
      } else {
        powerups.grant(taken.kind);
      }
    }

    RevealSystem.reveal(
      grid: grid,
      layout: layout,
      dogPosition: dog.position,
      dogCell: dog.cell,
      radius: math.max(
        RevealSystem.radiusFor(
          tuning.tapRadiusFor(layout.width),
          tuning.revealFactor,
        ),
        tuning.tapRadiusFor(layout.width) * powerups.tapRadiusMultiplier * 1.2,
      ),
    );

    // Progress means closing the gap along a route that actually exists, so
    // this uses the anchor-aware field the dog herself steers on.
    final gap = grid.distanceToExit(dog.cell);
    if (gap < bestDistance) {
      bestDistance = gap;
      lastProgressAt = now;
    }

    if (regrowth && !powerups.regrowthPaused) {
      final events = regrowthSystem.update(
        dt: dt,
        now: now,
        grid: grid,
        tuning: tuning,
        dogCell: dog.cell,
      );
      if (events.fieldChanged) {
        fieldVersion++;
      }
    }

    if (dog.enclosedFor >= tuning.suffocateSeconds) {
      return finish(false, 'boxed in');
    }
    if (hungerKills && hunger.isStarved) {
      return finish(false, 'starved');
    }
    if (dog.hasReachedExit(grid)) {
      return finish(true, 'won');
    }
    // The budget-aware soft-lock, checked every frame exactly as the game does.
    // Only testing it once the taps ran out let a stalled run spin to the time
    // limit and report as a timeout, which hides whether it was a real loss.
    if (softlock.check(
      grid: grid,
      dogCell: dog.cell,
      fieldVersion: fieldVersion,
      tapsLeft: budget - taps,
      pickups: pickups,
      treatTaps: tuning.treatTaps.round(),
      blastCharges: powerups.chargesOf(PickupKind.blast),
      digCharges: powerups.chargesOf(PickupKind.dig),
    )) {
      final reachable = Pathfinder.reachable(
        dog.cell,
        grid.exit,
        grid.isTraversableInPrinciple,
      );
      return finish(false, reachable ? 'out of taps' : 'no route');
    }
  }
  return finish(false, 'stalled');
}

/// The original harness: one default board, identified by seed.
///
/// Kept exactly as it was so the numbers the tuning tests print stay comparable
/// with every run before patrols and springs existed.
SimResult playSeed({
  required int seed,
  required bool regrowth,
  double tapInterval = 0.22,
  double limit = 70,
  double? budgetMultiplier,
  bool hungerKills = true,
  double? hungerPerCell,
  bool pickups = true,
}) {
  final tuning = TuningConfig();
  if (budgetMultiplier != null) {
    tuning.budgetMultiplier = budgetMultiplier;
  }
  if (hungerPerCell != null) {
    tuning.hungerSecondsPerCell = hungerPerCell;
  }
  return play(
    spec: LevelSpec(
      seed: seed,
      treats: pickups ? 3 : 0,
      powerups: pickups ? 2 : 0,
    ),
    tuning: tuning,
    regrowth: regrowth,
    tapInterval: tapInterval,
    limit: limit,
    hungerKills: hungerKills,
  );
}

/// The tuning a campaign level actually runs with, mirroring the game's own
/// `_applyRules`. If these two ever disagree, the sweep is measuring a game
/// nobody is playing.
TuningConfig tuningFor(LevelRules r) => TuningConfig()
  ..regrowthEnabled = r.regrowth
  ..fogEnabled = r.fog
  ..budgetEnabled = r.budget
  ..hungerEnabled = r.hunger
  ..anchorDensity = r.anchorDensity
  ..heavyDensity = r.heavyDensity
  ..springDensity = r.springDensity
  ..guardCount = r.guards
  ..guardSpeed = r.guardSpeed
  ..treatSeconds = r.treatSeconds
  ..treatTaps = r.treatTaps.toDouble()
  ..regrowDelay = r.regrowDelay
  ..budgetMultiplier = r.budgetMultiplier
  ..faultDensity = r.faultDensity
  ..hungerSecondsPerCell = r.hungerSecondsPerCell;

LevelSpec specFor(LevelRules r) => LevelSpec(
  seed: r.seed,
  columns: r.columns,
  rows: r.rows,
  anchorDensity: r.anchorDensity,
  heavyDensity: r.heavyDensity,
  springDensity: r.springDensity,
  faultDensity: r.faultDensity,
  slopeDensity: r.slopeDensity,
  sunkenDensity: r.sunkenDensity,
  hardpanDensity: r.hardpanDensity,
  thatchDensity: r.thatchDensity,
  overgrowthDensity: r.overgrowthDensity,
  tremorDensity: r.tremorDensity,
  iceDensity: r.iceDensity,
  mireDensity: r.mireDensity,
  eddyDensity: r.eddyDensity,
  magnetDensity: r.magnetDensity,
  thicketDensity: r.thicketDensity,
  sleeperDensity: r.sleeperDensity,
  foxfireDensity: r.foxfireDensity,
  scaffoldDensity: r.scaffoldDensity,
  thornDensity: r.thornDensity,
  alarmDensity: r.alarmDensity,
  gatePairs: r.gatePairs,
  mirrorPairs: r.mirrorPairs,
  gloom: r.gloom,
  guards: r.guards,
  sentries: r.sentries,
  beacons: r.beacons,
  spinners: r.spinners,
  runners: r.runners,
  blinkers: r.blinkers,
  wardens: r.wardens,
  guardSpeed: r.guardSpeed,
  treats: r.treats,
  powerups: r.powerups,
  treatSeconds: r.treatSeconds,
  treatTaps: r.treatTaps,
  offeredPowerups: r.offeredPowerups,
  powerupRotation: r.powerupRotation,
  shape: r.shape,
);

/// One campaign level, played exactly as it ships.
SimResult playCampaignLevel(
  int level, {
  double tapInterval = 0.22,
  double limit = 90,
}) {
  final rules = Campaign.rulesFor(level);
  return play(
    spec: specFor(rules),
    tuning: tuningFor(rules),
    regrowth: rules.regrowth,
    tapInterval: tapInterval,
    limit: limit,
    hungerKills: rules.hunger,
    budgetLimited: rules.budget,
  );
}
