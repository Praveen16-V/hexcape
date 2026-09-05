import 'dart:convert';
import 'dart:io';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/daily.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tuning.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/systems/input_system.dart';
import 'package:hexcape/systems/pickup_system.dart';

class _Tap extends TapDownEvent {
  _Tap(HexcapeGame game, Offset point)
    : _point = Vector2(point.dx, point.dy),
      super(1, game, TapDownDetails(globalPosition: point));
  final Vector2 _point;
  @override
  Vector2 get canvasPosition => _point;
}

/// Route-informed benchmark: real input, steering and hazards, with full-board
/// planning knowledge. Never moves the dog or credits uncollected food.
Map<String, Object?> runFoodRoute(
  int number,
  DailyChallenge? daily,
  bool food,
) {
  final game = HexcapeGame(tuning: TuningConfig())
    ..onGameResize(Vector2(390, 844));
  game.overlays.addEntry(Overlays.result, (_, _) => const SizedBox());
  // Initialize the daily synchronously; startDailyRun queues a Flutter frame.
  game.daily = daily;
  game.startLevel(level: number);
  expect(game.seed, daily?.rules.seed ?? Campaign.rulesFor(number).seed);
  game.tutorial?.skip();
  final costs = PickupSystem.detourCosts(game.grid);
  final treats = game.pickups.where((p) => p.kind == PickupKind.treat).toList();
  final avoid = treats.map((p) => p.coord).toSet();
  final candidates =
      treats.where((p) => p.coord.distanceTo(game.grid.start) >= 3).toList()
        ..sort(
          (a, b) =>
              ((costs[a.coord]?.steps ?? 99) * 3 + (costs[a.coord]?.taps ?? 99))
                  .compareTo(
                    (costs[b.coord]?.steps ?? 99) * 3 +
                        (costs[b.coord]?.taps ?? 99),
                  ),
        );
  final target = food && candidates.isNotEmpty ? candidates.first : null;
  var now = 0.0, nextTap = 0.0;
  var tapsRefunded = 0;
  final initialBudget = game.tapBudget;
  const dt = 1 / 60;
  while (now < 90 && !game.isOver) {
    if (now >= nextTap) {
      nextTap = now + 0.22;
      final goal = target != null && !target.collected
          ? target.coord
          : game.grid.exit;
      List<HexCoord>? route(bool avoidFood) => Pathfinder.cheapestPath(
        game.dog.cell,
        goal,
        (c) =>
            game.grid.isTraversableInPrinciple(c) &&
            (!avoidFood || !avoid.contains(c) || c == game.dog.cell),
        (c) => game.grid.remainingCost(c) + 1,
      );
      final path = route(!food) ?? route(false);
      if (path != null) {
        for (final coord in path.skip(1)) {
          if (!game.grid.isClearable(coord)) continue;
          final point = game.layout.toPixel(coord);
          final hit = InputSystem.resolve(
            point: point,
            grid: game.grid,
            layout: game.layout,
            dogPosition: game.dog.position,
            tapRadius: game.effectiveTapRadius,
            warded: game.wardedCells,
          );
          if (hit.outcome == TapOutcome.hit && hit.coord == coord) {
            game.onTapDown(_Tap(game, point));
          }
          break;
        }
      }
    }
    game.update(dt);
    now += dt;
  }
  tapsRefunded = game.tapBudget - initialBudget;
  return {
    'id': daily?.id ?? 'level-$number',
    'level': number,
    'seed': game.seed,
    'band': Campaign.bandOf(number).name,
    'pace': game.rules.pace.name,
    'strategy': food ? 'food' : 'direct',
    'phase': game.phase.name,
    'time': game.levelTime,
    'capacity': game.hunger.capacity,
    'remaining': game.hunger.remaining,
    'taps': game.taps,
    'foodAvailable': treats.length,
    'foodCollected': treats.where((p) => p.collected).length,
    'targetCollected': target?.collected,
    'secondsRefunded': game.foodSecondsRefunded,
    'tapsRefunded': tapsRefunded,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('normal-input hunger benchmark', () {
    final rows = <Map<String, Object?>>[];
    final limit =
        int.tryParse(Platform.environment['FOOD_LEVEL_LIMIT'] ?? '') ??
        Campaign.length;
    for (var n = 1; n <= limit; n++) {
      for (final food in [false, true]) {
        rows.add(runFoodRoute(n, null, food));
      }
    }
    if (limit == Campaign.length) {
      for (var day = 0; day < 30; day++) {
        final daily = Daily.forDate(
          DateTime.utc(2026, 9, 1).add(Duration(days: day)),
        );
        for (final food in [false, true]) {
          rows.add(runFoodRoute(daily.sourceLevel, daily, food));
        }
      }
    }
    final name = Platform.environment['FOOD_REPORT'] ?? 'current';
    final file = File('build/balance/$name.json')
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
    final won = rows.where((r) => r['phase'] == 'won').length;
    debugPrint(
      '${rows.length} normal-input runs: $won wins; report ${file.path}',
    );
    expect(rows.every((r) => (r['time'] as double).isFinite), isTrue);
    if (limit == Campaign.length) {
      final dailySeeds = rows
          .where((r) => !(r['id'] as String).startsWith('level-'))
          .map((r) => r['seed'])
          .toSet();
      expect(
        dailySeeds.length,
        30,
        reason: 'Daily probe must use 30 actual boards',
      );
      final matched = <(Map<String, Object?>, Map<String, Object?>)>[];
      for (var i = 0; i < rows.length; i += 2) {
        final direct = rows[i], food = rows[i + 1];
        if (direct['phase'] == 'won' &&
            food['phase'] == 'won' &&
            (food['foodCollected'] as int) > (direct['foodCollected'] as int)) {
          matched.add((direct, food));
        }
      }
      expect(matched.length, greaterThan(20));
      expect(
        matched
                .where(
                  (p) =>
                      (p.$2['remaining'] as double) >
                      (p.$1['remaining'] as double),
                )
                .length /
            matched.length,
        greaterThanOrEqualTo(0.8),
        reason: 'Food must usually pay for its detour',
      );
      expect(
        rows.where(
          (r) =>
              (r['level'] as int) > 20 &&
              r['phase'] == 'won' &&
              r['foodCollected'] == 0,
        ),
        isNotEmpty,
        reason: 'Efficient harder runs must still allow skipping food',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
