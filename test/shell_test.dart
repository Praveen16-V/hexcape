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

    test('rows alternate direction', () {
      // A serpentine, not a carriage return. Every row ending where the next
      // begins is what keeps the trail continuous.
      final first = MapLayout.coordFor(1);
      final endOfRow = MapLayout.coordFor(MapLayout.perRow);
      final startOfNext = MapLayout.coordFor(MapLayout.perRow + 1);
      expect(endOfRow.r, first.r);
      expect(startOfNext.r, first.r + 1);
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
    test('none of them plays differently', () {
      // The whole reason this is safe to hand out for stars. If a pet ever
      // carries a number, every level is balanced against whichever one the
      // player happens to have.
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

    test('a saved pet that no longer exists falls back rather than vanishing', () {
      // A build that renames or drops a pet would otherwise leave a player
      // with an invisible dog and no way to fix it from inside the game.
      expect(Pets.byId('a-pet-from-an-older-build').id, Pets.scout.id);
      expect(Pets.byId(null).id, Pets.scout.id);
    });

    test('a saved pet the player has not earned is not honoured', () {
      final locked = Pets.all.last;
      expect(locked.starsRequired, greaterThan(0));
      expect(Pets.byId(locked.id, stars: 0).id, Pets.scout.id);
      expect(
        Pets.byId(locked.id, stars: locked.starsRequired).id,
        locked.id,
      );
    });

    test('unlocking is inclusive of the threshold', () {
      final pet = Pets.all[1];
      expect(Pets.isUnlocked(pet, pet.starsRequired - 1), isFalse);
      expect(Pets.isUnlocked(pet, pet.starsRequired), isTrue);
    });
  });
}
