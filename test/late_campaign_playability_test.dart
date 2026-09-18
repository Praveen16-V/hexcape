import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/difficulty.dart';

import 'food_balance_benchmark_test.dart' show runFoodRoute;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'levels 71 to 100 can be finished in both modes with or without a treat',
    () {
      for (var n = 71; n <= 100; n++) {
        for (final difficulty in Difficulty.values) {
          for (final food in [false, true]) {
            final result = runFoodRoute(n, null, food, difficulty: difficulty);
            final context = 'level $n ${difficulty.label}, food detour: $food';
            expect(result['phase'], 'won', reason: context);
            if (!food) {
              expect(
                result['remaining'],
                greaterThanOrEqualTo(5),
                reason: '$context needs room to read the board',
              );
            }
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
