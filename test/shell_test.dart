import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/hexcape_game.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/pets.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_grid.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/theme/palette.dart';
import 'package:hexcape/ui/level_map.dart';

void main() {
  group('The directional hint', () {
    test('points around a wall, not through it', () {
      // A straight line to the food is cheaper to compute and wrong: it aims
      // squarely at whichever anchor stands between here and there, which is
      // the one moment a hint has to be right.
      final cells = <HexCoord, HexCell>{
        for (var q = -1; q <= 3; q++)
          for (var r = -1; r <= 1; r++)
            HexCoord(q, r): HexCell(HexCoord(q, r), HexType.plain),
      };
      // A wall dead ahead, with the only way through one row down.
      cells[const HexCoord(1, 0)]!.type = HexType.anchor;
      cells[const HexCoord(1, -1)]!.type = HexType.anchor;
      final grid = HexGrid(
        cells: cells,
        start: const HexCoord(0, 0),
        exit: const HexCoord(3, 0),
        truePath: const [],
      );

      // The straight-line neighbour is the anchor; the routed one is not.
      final straight = const HexCoord(1, 0);
      expect(grid.isTraversableInPrinciple(straight), isFalse);

      HexCoord? best;
      var bestDistance = grid.distanceToExit(const HexCoord(0, 0));
      for (final n in const HexCoord(0, 0).neighbours) {
        if (!grid.isTraversableInPrinciple(n)) {
          continue;
        }
        final d = grid.distanceToExit(n);
        if (d < bestDistance) {
          bestDistance = d;
          best = n;
        }
      }
      expect(best, isNotNull, reason: 'no way round the wall was found');
      expect(best, isNot(straight));
      expect(
        grid.distanceToExit(best!),
        lessThan(grid.distanceToExit(const HexCoord(0, 0))),
        reason: 'the hint pointed somewhere no closer to the food',
      );
    });

    test('the delay is long enough to be about being lost, not thinking', () {
      // A nudge that arrives while the player is still reading the board is
      // not help, it is interruption.
      expect(HexcapeGame.hintAfter, greaterThanOrEqualTo(5.0));
    });
  });

  group('The campaign map', () {
    test('every level gets its own tile', () {
      // Two levels on one hex would make one of them unreachable by tapping,
      // and which one would depend on iteration order.
      final seen = <HexCoord>{};
      for (var level = 1; level <= MapLayout.tiles; level++) {
        expect(
          seen.add(MapLayout.coordFor(level)),
          isTrue,
          reason: 'level $level shares a tile',
        );
      }
      expect(seen.length, MapLayout.tiles);
    });

    test('the trail never jumps', () {
      // Consecutive levels are neighbours, so the line drawn between them
      // reads as a path rather than as wire flung across the board.
      for (var level = 2; level <= MapLayout.tiles; level++) {
        expect(
          MapLayout.coordFor(level).distanceTo(MapLayout.coordFor(level - 1)),
          1,
          reason: 'level $level is not beside level ${level - 1}',
        );
      }
    });

    test('the trail only ever goes downhill', () {
      // Rows never climb back. This is what lets a chapter be a contiguous
      // block of rows, which is what lets its header sit above its own tiles.
      for (var level = 2; level <= MapLayout.tiles; level++) {
        final step = MapLayout.rowOf(level) - MapLayout.rowOf(level - 1);
        expect(
          step,
          anyOf(0, 1),
          reason: 'level $level jumps ${step > 0 ? 'down' : 'back up'} a row',
        );
      }
    });

    test('a row is walked once, in one direction', () {
      // The countability the old five-per-row snake was built for, kept. A row
      // that doubled back would put level 43 behind level 45 and make finding
      // either of them a search.
      for (var level = 2; level <= MapLayout.tiles; level++) {
        final here = MapLayout.coordFor(level);
        final before = MapLayout.coordFor(level - 1);
        if (here.r != before.r) {
          continue;
        }
        final direction = here.q - before.q;
        expect(
          direction.abs(),
          1,
          reason: 'level $level did not step sideways',
        );
        // Walk the rest of this row and check it keeps going the same way.
        for (var next = level + 1; next <= MapLayout.tiles; next++) {
          final step = MapLayout.coordFor(next);
          if (step.r != here.r) {
            break;
          }
          expect(
            (step.q - MapLayout.coordFor(next - 1).q).sign,
            direction.sign,
            reason: 'row ${here.r} turns round at level $next',
          );
        }
      }
    });

    test('every chapter starts on a row of its own', () {
      // The defect this layout was built to make impossible: Learning and
      // Foundation both began on row zero, so the map painted both their names
      // at one identical point and stroked row zero's ground plate twice.
      final rows = <int, CampaignBand>{};
      for (final band in CampaignBand.values) {
        final span = MapLayout.rowsOf(band);
        for (var row = span.firstRow; row <= span.lastRow; row++) {
          final other = rows[row];
          expect(
            other,
            isNull,
            reason: '${band.label} shares row $row with ${other?.label}',
          );
          rows[row] = band;
        }
      }
    });

    test('the trail meanders rather than ruling lines', () {
      // What makes six chapters look like six places. Without this the layout
      // could quietly regress to a fixed-width grid and nothing would notice.
      final lengths = <int, int>{};
      for (var level = 1; level <= MapLayout.tiles; level++) {
        lengths.update(MapLayout.rowOf(level), (n) => n + 1, ifAbsent: () => 1);
      }
      expect(
        lengths.values.toSet().length,
        greaterThanOrEqualTo(3),
        reason: 'every row the same length is a spreadsheet, not a trail',
      );
      final leftEdges = <CampaignBand, int>{};
      for (final band in CampaignBand.values) {
        final levels = MapLayout.levelsOf(band);
        var least = 1 << 30;
        for (var level = levels.first; level <= levels.last; level++) {
          final c = MapLayout.coordFor(level);
          least = math.min(least, 2 * c.q + c.r);
        }
        leftEdges[band] = least;
      }
      expect(
        leftEdges.values.toSet().length,
        greaterThanOrEqualTo(2),
        reason: 'chapters that all start at the same column read as one block',
      );
    });

    test('the map never grows wider than a small phone', () {
      // The hex size is derived from this, so a walk that wandered wider would
      // silently shrink every tile on a 320px screen rather than failing here.
      expect(MapLayout.columnSpan, lessThanOrEqualTo(5));
    });

    test('the row count is the row count', () {
      // The constant this replaced was `length / perRow`, which was one short
      // of the rows actually drawn — and nothing noticed, because nothing read
      // it.
      expect(MapLayout.rowCount, MapLayout.rowOf(MapLayout.tiles) + 1);
    });

    test('a tap finds the level under it', () {
      final layout = HexLayout(size: 30, origin: const Offset(60, 60));
      for (var level = 1; level <= MapLayout.tiles; level += 7) {
        final centre = layout.toPixel(MapLayout.coordFor(level));
        expect(MapLayout.levelAt(centre, layout), level);
        // And a little off centre still lands on the same tile.
        expect(MapLayout.levelAt(centre.translate(6, -6), layout), level);
      }
    });

    test('a tap off the trail selects nothing', () {
      final layout = HexLayout(size: 30, origin: const Offset(60, 60));
      // Far below the last tile there is no board at all.
      final beyond = layout
          .toPixel(MapLayout.coordFor(MapLayout.tiles))
          .translate(0, 400);
      expect(MapLayout.levelAt(beyond, layout), isNull);
    });

    test('the map covers the campaign and one way past it', () {
      expect(MapLayout.tiles, Campaign.length + 1);
      expect(
        Campaign.bandOf(MapLayout.tiles),
        CampaignBand.endless,
        reason: 'the last tile should be the way into endless',
      );
    });

    test('every band has a colour and a first level', () {
      for (final band in CampaignBand.values) {
        expect(Palette.forBand(band), isNotNull);
        expect(band.label, isNotEmpty);
        expect(Campaign.bandOf(Campaign.firstOf(band)), band);
      }
    });

    test('bands run in order and cover every level', () {
      var previous = CampaignBand.tutorial;
      for (var level = 1; level <= Campaign.length + 5; level++) {
        final band = Campaign.bandOf(level);
        expect(
          band.index,
          greaterThanOrEqualTo(previous.index),
          reason: 'level $level went backwards to ${band.label}',
        );
        previous = band;
      }
      expect(previous, CampaignBand.endless);
    });
  });

  group('Pets', () {
    test('each leans a run differently rather than outright stronger', () {
      // The shape the redesign allows and no more: a pet may tilt a run
      // toward a style, but hers must never be the number that makes her the
      // strictly right one.
      for (final pet in Pets.all) {
        expect(pet.id, isNotEmpty);
        expect(pet.name, isNotEmpty);
        expect(pet.blurb, isNotEmpty);
      }
    });

    test('exactly one is free, and the rest cost more as they go', () {
      expect(Pets.all.first, Pets.scout);
      expect(Pets.scout.starsRequired, 0);
      var previous = -1;
      for (final pet in Pets.all) {
        expect(
          pet.starsRequired,
          greaterThan(previous),
          reason: '${pet.name} costs no more than the one before it',
        );
        previous = pet.starsRequired;
      }
    });

    test('every pet is reachable inside the campaign', () {
      // A pet priced above every star the game can award is not a reward, it
      // is a taunt.
      final maxStars = Campaign.length * 3;
      for (final pet in Pets.all) {
        expect(
          pet.starsRequired,
          lessThanOrEqualTo(maxStars),
          reason: '${pet.name} needs more stars than exist',
        );
      }
    });

    test('ids are unique', () {
      expect(Pets.all.map((p) => p.id).toSet().length, Pets.all.length);
    });

    test(
      'a saved pet that no longer exists falls back rather than vanishing',
      () {
        // A build that renames or drops a pet would otherwise leave a player
        // with an invisible dog and no way to fix it from inside the game.
        expect(Pets.byId('a-pet-from-an-older-build').id, Pets.scout.id);
        expect(Pets.byId(null).id, Pets.scout.id);
      },
    );

    test('a saved pet the player has not earned is not honoured', () {
      final locked = Pets.all.last;
      expect(locked.starsRequired, greaterThan(0));
      expect(Pets.byId(locked.id, stars: 0).id, Pets.scout.id);
      expect(Pets.byId(locked.id, stars: locked.starsRequired).id, locked.id);
    });

    test('unlocking is inclusive of the threshold', () {
      final pet = Pets.all[1];
      expect(Pets.isUnlocked(pet, pet.starsRequired - 1), isFalse);
      expect(Pets.isUnlocked(pet, pet.starsRequired), isTrue);
    });
  });
}
