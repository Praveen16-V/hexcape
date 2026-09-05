import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/pickup.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/hex/hex_cell.dart';
import 'package:hexcape/ui/reference_sheet.dart';

void main() {
  group('The reference', () {
    test('every tile type is explained', () {
      // A new hex type must not be able to reach players without an entry. The
      // game's only other explanations are transient — a tutorial step, an
      // eight-second line, a one-off banner — so this page is the only place a
      // returning player can look something up.
      final documented = {
        for (final entry in allReferenceEntries)
          if (entry.hex != null) entry.hex!,
      };
      expect(documented, HexType.values.toSet());
    });

    test('every pickup is explained', () {
      final documented = {
        for (final entry in allReferenceEntries)
          if (entry.pickup != null) entry.pickup!,
      };
      expect(documented, PickupKind.values.toSet());
    });

    test('every entry draws something', () {
      // An entry with no hex, no pickup and no icon renders an empty box.
      for (final entry in allReferenceEntries) {
        expect(
          entry.hex != null || entry.pickup != null || entry.icon != null,
          isTrue,
          reason: '"${entry.name}" has nothing to draw',
        );
        expect(entry.name, isNotEmpty);
        expect(entry.blurb, isNotEmpty);
      }
    });

    test('nothing is explained before the campaign introduces it', () {
      // A level-three player opening this should not read about patrols they
      // will not meet for another eighteen levels.
      for (final entry in allReferenceEntries) {
        expect(
          entry.unlocksAt,
          greaterThanOrEqualTo(1),
          reason: '"${entry.name}" unlocks before the game starts',
        );
        expect(
          entry.unlocksAt,
          lessThanOrEqualTo(Campaign.length),
          reason: '"${entry.name}" is never reachable',
        );
      }
      final springs = allReferenceEntries.firstWhere((e) => e.name == 'Spring');
      expect(springs.unlocksAt, Campaign.springsFrom);
      final patrols = allReferenceEntries.firstWhere((e) => e.name == 'Patrol');
      expect(patrols.unlocksAt, Campaign.guardsFrom);
    });

    test('the page grows as the campaign does, and never shrinks', () {
      var previous = 0;
      for (var level = 1; level <= Campaign.length; level++) {
        final count = referenceFor(level).length;
        expect(
          count,
          greaterThanOrEqualTo(previous),
          reason: 'level $level shows fewer entries than level ${level - 1}',
        );
        previous = count;
      }
      expect(
        referenceFor(Campaign.length).length,
        allReferenceEntries.length,
        reason: 'something is never shown, even at the end of the campaign',
      );
    });

    test('a brand new player is shown something, but not everything', () {
      final opening = referenceFor(1);
      expect(opening, isNotEmpty, reason: 'an empty page is not a reference');
      expect(opening.length, lessThan(allReferenceEntries.length));
    });

    test('every section is used', () {
      final used = allReferenceEntries.map((e) => e.section).toSet();
      expect(
        used,
        ReferenceSection.values.toSet(),
        reason: 'an empty section renders as a heading with nothing under it',
      );
    });
  });
}
