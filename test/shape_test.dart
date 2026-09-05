import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/gen/pathfinder.dart';
import 'package:hexcape/gen/silhouette.dart';
import 'package:hexcape/hex/hex_coord.dart';

void main() {
  group('Field shapes', () {
    test('every shape is one connected region of playable size', () {
      // A detached corner would put an island on the board that the dog can
      // never reach, and no amount of careful ASCII art guarantees that on a hex
      // grid — the largest-region filter does.
      for (final shape in FieldShape.values) {
        final cells = shaped(shape: shape, columns: 11, rows: 23);
        expect(
          cells.length,
          greaterThan(80),
          reason: '${shape.name} too small',
        );

        final seen = <HexCoord>{cells.first};
        final queue = <HexCoord>[cells.first];
        while (queue.isNotEmpty) {
          for (final n in queue.removeLast().neighbours) {
            if (cells.contains(n) && seen.add(n)) {
              queue.add(n);
            }
          }
        }
        expect(
          seen.length,
          cells.length,
          reason: '${shape.name} has an unreachable island',
        );
      }
    });

    test('every shape keeps enough board to be a level', () {
      // The sampling and the largest-region filter between them can quietly
      // amputate a shape: a thin tail or a narrow shaft either vanishes into the
      // hex grid or survives detached and is thrown away. A mask that loses half
      // its board is not a silhouette, it is a corridor, and a corridor has no
      // route choices in it.
      final reference = ellipse(columns: 12, rows: 27).length;
      for (final shape in FieldShape.values) {
        final cells = shaped(shape: shape, columns: 12, rows: 27);
        expect(
          cells.length / reference,
          greaterThan(0.6),
          reason:
              '${shape.name} keeps only '
              '${(cells.length / reference * 100).round()}% of a full board',
        );
      }
    });

    test('every shape has a name to show the player', () {
      for (final shape in FieldShape.values) {
        expect(shape.label, isNotEmpty);
        expect(shape.label, isNot(shape.name), reason: 'raw enum name shown');
      }
    });

    test('shapes actually differ from one another', () {
      final sets = {
        for (final shape in FieldShape.values)
          shape: shaped(shape: shape, columns: 11, rows: 23),
      };
      for (final a in FieldShape.values) {
        for (final b in FieldShape.values) {
          if (a == b) {
            continue;
          }
          expect(
            sets[a],
            isNot(sets[b]),
            reason: '${a.name} and ${b.name} are the same board',
          );
        }
      }
    });

    test('the tutorial is always the plain ellipse', () {
      // Someone still learning what a tile does should not also be working out
      // why the board is fish-shaped.
      for (var level = 1; level <= Campaign.tutorialBand; level++) {
        expect(Campaign.rulesFor(level).shape, FieldShape.ellipse);
      }
    });

    test('a level always wears the same shape', () {
      for (final level in [7, 19, 33, 52, 88]) {
        expect(Campaign.rulesFor(level).shape, Campaign.rulesFor(level).shape);
      }
    });

    test('the campaign is not all one outline', () {
      final shapes = {
        for (var level = 6; level <= Campaign.length; level++)
          Campaign.rulesFor(level).shape,
      };
      expect(
        shapes.length,
        greaterThan(2),
        reason: 'a campaign of one silhouette is the thing this fixes',
      );
    });

    test('every shaped level still generates a solvable board', () {
      for (final shape in FieldShape.values) {
        for (var seed = 0; seed < 12; seed++) {
          final generated = LevelGenerator.generate(
            LevelSpec(
              seed: seed,
              columns: 11,
              rows: 23,
              anchorDensity: 0.3,
              heavyDensity: 0.22,
              shape: shape,
            ),
          );
          expect(
            Pathfinder.reachable(
              generated.grid.start,
              generated.grid.exit,
              generated.grid.isTraversableInPrinciple,
            ),
            isTrue,
            reason: '${shape.name} seed $seed has no route',
          );
          expect(generated.par, greaterThan(0));
        }
      }
    });
  });
}
