import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/systems/regrowth_system.dart';

import 'sim/simulated_player.dart' show playCampaignLevel;

/// The reported failure: *"stuck in between a 2-tile gap when there is a
/// riveted tile, and a combination of riveted and other tiles."*
///
/// Rivets are the one permanently solid tile, so a wedge bounded by them is
/// permanent in a way the same wedge against ordinary ground never is: no tap
/// can change the field, nothing bumps the field version, and the aim that
/// wedged her is re-fed sixty times a second forever. On every other tile the
/// player's next tap shakes her loose and the bug is invisible.
///
/// These are the physical tests. [sealed_in_test.dart] owns the other half of
/// the contract — the pocket that really is her own size still ends the run.
///
/// The sweep below ran 4992 starting positions across 24 random rivet pockets.
/// Before the fix she stood in a seam for a second and a quarter or longer in
/// 37 of them, worst case 2.77s and still counting when the run was cut; after
/// it, none of them, and the placement of last resort never fired once.
const _layout = HexLayout(size: 22, origin: Offset(400, 400));
const _dt = 1 / 60;

/// Solid rivet everywhere inside [radius] except [open], which is cleared.
///
/// Rivets rather than plain ground on purpose: it removes every escape the
/// real fix must not be allowed to lean on. Nothing can be tapped, nothing
/// regrows, the field version never moves.
HexGrid _rivetField({
  required Iterable<HexCoord> open,
  required HexCoord exit,
  int radius = 6,
}) {
  final coords = HexCoord.zero.disc(radius);
  final grid = HexGrid(
    cells: {for (final c in coords) c: HexCell(c, HexType.anchor)},
    start: open.first,
    exit: exit,
    truePath: [open.first, exit],
  );
  for (final c in open) {
    grid.at(c)!
      ..type = HexType.plain
      ..clear(0);
  }
  return grid;
}

/// Room for her body at [p], recomputed here rather than calling
/// [Dog.clearanceAt], so a wrong implementation cannot make its own probe pass.
double _clearance(Offset p, HexGrid grid) {
  var room = double.infinity;
  for (final n in _layout.toHex(p).neighbours) {
    if (!grid.blocks(n)) {
      continue;
    }
    final corners = _layout.corners(n);
    for (var i = 0; i < corners.length; i++) {
      final d = _distanceToSegment(p, corners[i], corners[(i + 1) % 6]);
      if (d < room) {
        room = d;
      }
    }
  }
  return room;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  if (lengthSquared < 1e-9) {
    return (p - a).distance;
  }
  final ap = p - a;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// What one run looked like. Everything the wedge contract is stated in.
class _Run {
  double worstWedged = 0;
  HexCoord worstAt = HexCoord.zero;

  /// Frames that moved her further than half a hex. At drift speed one frame
  /// covers about a tenth of one, so anything over this is the placement of
  /// last resort firing, not walking.
  int snaps = 0;
  /// The furthest she moved in any one frame. Bounded by the circumradius:
  /// the placement of last resort puts her on the centre of a cell she is
  /// already inside, so nothing may ever move her further than that.
  double longestStep = 0;
  bool everInWall = false;
  double enclosedFor = 0;

  /// The longest unbroken stretch she spent stopped in the gap between two
  /// tiles — the reported symptom, stated as a duration.
  ///
  /// Measured over time rather than sampled at the end, because passing
  /// through a seam slowly is just walking: she crosses zero speed every time
  /// she turns around in a pocket, and catching her on that frame says
  /// nothing. Standing there is the bug.
  double worstStraddle = 0;
}

_Run _drive(
  Dog dog,
  HexGrid grid, {
  required double seconds,
  TuningConfig? tuning,
  bool regrowthActive = false,
  RegrowthSystem? regrowth,
  bool eddy = false,
  bool Function()? stopWhen,
}) {
  final config = tuning ?? TuningConfig();
  final run = _Run();
  var now = 0.0;
  var straddle = 0.0;

  while (now < seconds) {
    now += _dt;
    final before = dog.position;
    dog.update(
      dt: _dt,
      grid: grid,
      layout: _layout,
      tuning: config,
      fieldVersion: 1,
      regrowthActive: regrowthActive,
    );
    if (eddy) {
      // Exactly how hexcape_game.dart applies a continuous push: after the
      // dog's own update, straight into her velocity, and stood down while she
      // is wedged.
      final under = grid.at(dog.cell);
      if (under != null && under.type.pushesContinuously && dog.wedgedFor <= 0) {
        final centre = _layout.toPixel(dog.cell);
        final away = dog.position - centre;
        if (away.distance > 1e-4) {
          final push = _layout.width * 1.35 * _dt / away.distance;
          dog.velocity += away * push;
        }
      }
    }
    regrowth?.update(
      dt: _dt,
      now: now,
      grid: grid,
      tuning: config,
      dogCell: dog.cell,
      dogOccupiedCells: dog.occupiedCells(_layout),
    );

    final step = (dog.position - before).distance;
    if (step > run.longestStep) {
      run.longestStep = step;
    }
    if (step > _layout.size * 0.5) {
      run.snaps++;
    }
    if (dog.wedgedFor > run.worstWedged) {
      run.worstWedged = dog.wedgedFor;
      run.worstAt = dog.cell;
    }
    if (grid.blocks(_layout.toHex(dog.position))) {
      run.everInWall = true;
    }
    if (dog.enclosedFor > run.enclosedFor) {
      run.enclosedFor = dog.enclosedFor;
    }
    if (dog.speed <= _layout.width * 0.15 &&
        (!grid.isPassable(dog.cell) ||
            (dog.position - _layout.toPixel(dog.cell)).distance >=
                _layout.size * 0.12)) {
      straddle += _dt;
      if (straddle > run.worstStraddle) {
        run.worstStraddle = straddle;
        run.worstAt = dog.cell;
      }
    } else {
      straddle = 0;
    }
    if (stopWhen != null && stopWhen()) {
      break;
    }
  }
  return run;
}

/// She is standing on a tile rather than straddling the seam between two.
void _expectSettled(Dog dog, HexGrid grid, {double within = 0.12}) {
  expect(
    grid.isPassable(dog.cell),
    isTrue,
    reason: 'she settled on ${dog.cell}, which is not open ground',
  );
  expect(
    (dog.position - _layout.toPixel(dog.cell)).distance,
    lessThan(_layout.size * within),
    reason: 'she stopped straddling the seam instead of standing on a tile',
  );
}

/// How much room her body has over the stretch of the aim it is about to
/// occupy: half a hex, which is several frames of drift.
///
/// Deliberately not the whole line. An aim is a bearing, not a promise about
/// anywhere it happens to point — smoothing and the throat funnel both name
/// targets well past the ground she is crossing, and the solver is entitled
/// to slide her along a wall further out. What must never happen is the next
/// few frames of travel being steered into one.
double _clearanceAhead(Offset from, Offset aim, HexGrid grid) {
  final delta = aim - from;
  if (delta.distance < 1e-6) {
    return double.infinity;
  }
  final reach = math.min(delta.distance, _layout.inradius);
  var worst = double.infinity;
  const samples = 24;
  for (var i = 1; i <= samples; i++) {
    final p = from + (delta / delta.distance) * (reach * i / samples);
    final room = _clearance(p, grid);
    if (room < worst) {
      worst = room;
    }
  }
  return worst;
}

/// The wedge budget: the gentle recovery starts at 0.25 s and the placement of
/// last resort at 0.9 s, so anything past this means neither worked.
const _wedgeBudget = 1.2;

void main() {
  test('a two-cell rivet pocket never leaves her wedged on the seam', () {
    // The report, at its smallest. Run with regrowth off, which is the case
    // f8044b0 deliberately does not cover: there the field closing in ends the
    // run, here nothing closes and nothing ever will, so the only acceptable
    // outcome is that she frees herself.
    const here = HexCoord.zero;
    final beside = HexCoord.directions[0];
    final grid = _rivetField(open: [here, beside], exit: const HexCoord(0, -4));

    final dog = Dog(
      // Parked on the shared edge, where depenetration can leave her for a
      // frame when a cell snaps shut against her.
      position: (_layout.toPixel(here) + _layout.toPixel(beside)) / 2,
      cell: here,
    )..hasBeenFree = true;

    final run = _drive(dog, grid, seconds: 10);

    expect(run.everInWall, isFalse, reason: 'she ended up inside a rivet');
    expect(
      run.worstWedged,
      lessThan(_wedgeBudget),
      reason: 'she went nowhere for ${run.worstWedged}s at ${run.worstAt}',
    );
    expect(
      run.worstStraddle,
      lessThan(_wedgeBudget),
      reason: 'she stood in the gap for ${run.worstStraddle}s',
    );
    _expectSettled(dog, grid, within: 0.1);
  });

  test('she is never aimed down a line her body cannot take', () {
    // The seam geometry, exactly. Between the centres of (0,0) and (2,-1) the
    // straight line does not merely pass near the shared edge of (1,0) and
    // (1,-1) — it contains it, same bearing and collinear endpoints. With a
    // rivet on one side, every sample sits on the boundary and hex rounding
    // picks a side by floating point luck. Approving that line aims her down a
    // path her body overlaps by its whole radius.
    const start = HexCoord.zero;
    const middle = HexCoord(1, -1);
    const far = HexCoord(2, -1);
    final grid = _rivetField(open: const [start, middle, far], exit: far);

    final dog = Dog(position: _layout.toPixel(start), cell: start);
    final tuning = TuningConfig();
    var now = 0.0;
    var worstAim = double.infinity;

    while (now < 10 && dog.cell != far) {
      now += _dt;
      dog.update(
        dt: _dt,
        grid: grid,
        layout: _layout,
        tuning: tuning,
        fieldVersion: 1,
        regrowthActive: false,
      );
      final aim = dog.movementAim;
      if (aim != null) {
        final room = _clearanceAhead(dog.position, aim, grid);
        if (room < worstAim) {
          worstAim = room;
        }
      }
    }

    expect(
      worstAim,
      greaterThanOrEqualTo(Dog.collisionRadius(_layout) * 0.85),
      reason: 'the aim ran her body through a rivet face',
    );
    expect(
      dog.cell,
      far,
      reason: 'she never crossed the pinched throat at all',
    );
  });

  test('she threads a pinched throat from any starting offset', () {
    // A sixty degree bend whose throat has a rivet at both corners: exactly
    // one `size` of passage against a body of 0.68, so an off-axis entry has
    // almost no margin. She has to get through from wherever momentum left her.
    const a = HexCoord.zero;
    const b = HexCoord(1, 0);
    const c = HexCoord(1, 1);
    final failures = <String>[];

    for (var turn = 0; turn < 12; turn++) {
      for (final scale in const [0.0, 0.2, 0.4, 0.6]) {
        final angle = turn * math.pi / 6;
        final offset = Offset(math.cos(angle), math.sin(angle)) *
            (_layout.size * scale);
        final start = _layout.toPixel(a) + offset;
        final grid = _rivetField(open: const [a, b, c], exit: c);
        if (grid.blocks(_layout.toHex(start))) {
          continue;
        }
        final dog = Dog(position: start, cell: _layout.toHex(start));
        final run = _drive(
          dog,
          grid,
          seconds: 15,
          stopWhen: () => dog.cell == c,
        );
        if (dog.cell != c) {
          failures.add(
            'turn $turn scale $scale ended ${dog.cell} '
            'worst wedge ${run.worstWedged.toStringAsFixed(2)}s',
          );
        }
      }
    }

    expect(failures, isEmpty, reason: failures.join('; '));
  });

  test('no rivet pocket wedges her, whatever its shape', () {
    // The exact geometry that triggers a wedge was never pinned down, so this
    // sweeps for it instead: random pockets, every open cell, eight bearings,
    // three offsets, with the exit inside the pocket and again walled off
    // outside it — which are two different branches of route selection.
    const seed = 20260911;
    final rng = math.Random(seed);
    final failures = <String>[];
    var cases = 0;
    var worst = 0.0;
    var worstWhere = '';
    var worstStand = 0.0;
    var snaps = 0;

    for (var shape = 0; shape < 24; shape++) {
      final pocket = _growPocket(rng);
      for (final exitInside in const [true, false]) {
        final exit = exitInside ? pocket.last : const HexCoord(0, -5);
        for (final home in pocket) {
          for (var turn = 0; turn < 8; turn++) {
            for (final scale in const [0.0, 0.25, 0.45]) {
              final angle = turn * math.pi / 4;
              final offset = Offset(math.cos(angle), math.sin(angle)) *
                  (_layout.size * scale);
              final start = _layout.toPixel(home) + offset;
              final grid = _rivetField(open: pocket, exit: exit);
              if (grid.blocks(_layout.toHex(start))) {
                continue;
              }
              cases++;
              final dog = Dog(
                position: start,
                cell: _layout.toHex(start),
              )..hasBeenFree = true;
              final run = _drive(dog, grid, seconds: 4);
              snaps += run.snaps;

              if (run.worstWedged > worst) {
                worst = run.worstWedged;
                worstWhere = 'shape $shape $pocket at ${run.worstAt}';
              }
              if (run.worstStraddle > worstStand) {
                worstStand = run.worstStraddle;
              }
              final where =
                  'seed $seed shape $shape pocket $pocket '
                  'exitInside $exitInside home $home turn $turn scale $scale';
              if (run.worstWedged >= _wedgeBudget) {
                failures.add(
                  '$where: wedged ${run.worstWedged.toStringAsFixed(2)}s',
                );
              } else if (run.everInWall) {
                failures.add('$where: ended up inside a rivet');
              } else if (run.worstStraddle >= _wedgeBudget) {
                // The reported symptom exactly: stopped, in the gap between
                // two tiles. Still travelling through a seam is just walking.
                failures.add(
                  '$where: stood in a seam for '
                  '${run.worstStraddle.toStringAsFixed(2)}s',
                );
              } else if (run.longestStep > _layout.size) {
                failures.add(
                  '$where: one frame moved her '
                  '${(run.longestStep / _layout.size).toStringAsFixed(2)} hexes',
                );
              } else if (run.snaps > 1) {
                // The assertion that stops this fix degenerating into
                // "teleport her whenever she is slow". Placement is the last
                // resort; if it is doing the work, the aim is still wrong.
                failures.add('$where: ${run.snaps} snaps');
              }
            }
          }
        }
      }
    }

    // ignore: avoid_print
    print(
      'rivet pockets: $cases cases, worst wedge '
      '${worst.toStringAsFixed(2)}s at $worstWhere, '
      'worst seam stand ${worstStand.toStringAsFixed(2)}s, $snaps snaps',
    );
    expect(
      failures,
      isEmpty,
      reason: '${failures.length} of $cases cases failed:\n'
          '${failures.take(8).join('\n')}',
    );
  });

  test('an eddy in a rivet pocket still lets her settle', () {
    // A swirl's job is to deny her a resting place. Inside a pocket walled by
    // rivets that means shoving her at a wall that will never open, in exactly
    // the opposite direction to the one recovery the game sanctions — so the
    // tile has to stand down while she is wedged, or the two fight forever.
    const here = HexCoord.zero;
    final beside = HexCoord.directions[0];
    final grid = _rivetField(open: [here, beside], exit: const HexCoord(0, -4));
    grid.at(here)!.type = HexType.eddy;

    final dog = Dog(
      position: (_layout.toPixel(here) + _layout.toPixel(beside)) / 2,
      cell: here,
    )..hasBeenFree = true;

    final run = _drive(dog, grid, seconds: 10, eddy: true);

    expect(
      run.worstWedged,
      lessThan(_wedgeBudget),
      reason: 'the swirl held her against a rivet for ${run.worstWedged}s',
    );
    expect(run.worstStraddle, lessThan(_wedgeBudget));
    _expectSettled(dog, grid);
  });

  test('freeing her does not defeat the crush', () {
    // The other half of the contract. Settling her onto one tile shrinks her
    // footprint, which briefly makes the pocket look like it has a way out —
    // the grace period must still run once regrowth seals the tile she left.
    const here = HexCoord.zero;
    final beside = HexCoord.directions[0];
    final grid = _rivetField(open: [here, beside], exit: const HexCoord(0, -4));

    final dog = Dog(
      position: (_layout.toPixel(here) + _layout.toPixel(beside)) / 2,
      cell: here,
    )..hasBeenFree = true;
    final tuning = TuningConfig()..regrowDelay = 0.3;

    _drive(
      dog,
      grid,
      seconds: 30,
      tuning: tuning,
      regrowthActive: true,
      regrowth: RegrowthSystem(),
      stopWhen: () => dog.enclosedFor >= tuning.suffocateSeconds,
    );

    expect(
      dog.enclosedFor,
      greaterThanOrEqualTo(tuning.suffocateSeconds),
      reason: 'she had nowhere to step and the run never ended',
    );
    expect(
      grid.at(dog.cell)!.isSolid,
      isFalse,
      reason: 'the fairness rule still holds: the ground under her never snaps',
    );
  });

  test('a wedge in ground she could stand in frees her rather than kills', () {
    // The design constraint, stated as a test. This pocket is comfortably
    // bigger than her body, so being stuck in it is a collision failure and
    // nothing else — ending the run here would be answering the wrong question.
    final pocket = <HexCoord>[
      HexCoord.zero,
      HexCoord.directions[0],
      HexCoord.directions[1],
      HexCoord.directions[2],
    ];
    final grid = _rivetField(open: pocket, exit: const HexCoord(0, -5));

    // Pressed into the corner between two rivets.
    final start = _layout.toPixel(HexCoord.zero) +
        Offset(math.cos(math.pi / 2), math.sin(math.pi / 2)) *
            (_layout.size * 0.55);
    final dog = Dog(position: start, cell: _layout.toHex(start))
      ..hasBeenFree = true;

    final run = _drive(dog, grid, seconds: 8);

    expect(
      run.enclosedFor,
      0,
      reason: 'she was crushed for a wedge she should have walked out of',
    );
    expect(run.worstWedged, lessThan(_wedgeBudget));
    _expectSettled(dog, grid);
  });

  test('no campaign level wedges her on the boards that ship', () {
    // The hand-built pockets above are the shapes reasoning found. This is the
    // check that the shapes the generator actually produces agree, played the
    // way the budget is balanced against -- three tap rhythms across every
    // level the campaign gives rivets to, which is all of them.
    final worst = <String, double>{};
    var runs = 0;

    for (var level = 1; level <= 40; level++) {
      if (Campaign.rulesFor(level).anchorDensity <= 0) {
        continue;
      }
      for (final interval in const [0.16, 0.22, 0.34]) {
        runs++;
        final result = playCampaignLevel(level, tapInterval: interval);
        final key = 'level $level at ${interval}s';
        if (result.maxWedged > (worst[key] ?? 0)) {
          worst[key] = result.maxWedged;
        }
      }
    }

    final over = worst.entries.where((e) => e.value >= _wedgeBudget).toList();
    final peak = worst.values.fold(0.0, math.max);
    // ignore: avoid_print
    print(
      'campaign: $runs runs over ${worst.length} level/rhythm pairs, '
      'worst wedge ${peak.toStringAsFixed(2)}s',
    );
    expect(
      over,
      isEmpty,
      reason: over
          .map((e) => '${e.key}: ${e.value.toStringAsFixed(2)}s')
          .join(', '),
    );
  });

  test('a frozen field does not run the crush clock', () {
    // FREEZE holds the field still and charges the clock for it. The game used
    // to derive "is regrowth running" twice, and the copy the dog was given
    // dropped the freeze term — so she could be crushed by ground that was not
    // moving, while holding the tool whose whole promise is the opposite.
    final grid = _rivetField(
      open: const [HexCoord.zero],
      exit: const HexCoord(0, -4),
    );
    final dog = Dog(position: _layout.toPixel(HexCoord.zero), cell: HexCoord.zero)
      ..hasBeenFree = true;
    final tuning = TuningConfig();

    final run = _drive(
      dog,
      grid,
      seconds: tuning.suffocateSeconds * 2,
      tuning: tuning,
    );

    expect(
      run.enclosedFor,
      0,
      reason: 'the clock ran while the field was frozen',
    );
  });
}

/// A connected pocket of two to six cells, grown at random inside three rings.
List<HexCoord> _growPocket(math.Random rng) {
  final pocket = <HexCoord>[HexCoord.zero];
  final target = 2 + rng.nextInt(5);
  var guard = 0;
  while (pocket.length < target && guard++ < 60) {
    final from = pocket[rng.nextInt(pocket.length)];
    final next = from + HexCoord.directions[rng.nextInt(6)];
    if (pocket.contains(next) || next.distanceTo(HexCoord.zero) > 3) {
      continue;
    }
    pocket.add(next);
  }
  return pocket;
}
