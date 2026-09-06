import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/pets.dart';

void main() {
  group('Pets', () {
    test('every pet carries a perk — the whole point of the redesign', () {
      // A pet that only changes colour is the old mistake. The test exists so
      // a new pet cannot be added without saying what she does differently.
      for (final pet in Pets.all) {
        expect(pet.perk.name, isNotEmpty, reason: '${pet.name} has no perk name');
        expect(pet.perk.short, isNotEmpty, reason: '${pet.name} has no perk lore');
        final doesSomething = pet.perk.speedScale != 1.0 ||
            pet.perk.revealScale != 1.0 ||
            pet.perk.regrowDelta != 0 ||
            pet.perk.hintBeforeBy != 0 ||
            pet.perk.extraTreats != 0;
        expect(doesSomething, isTrue, reason: '${pet.name} does nothing');
      }
    });

    test('the starter is free, and stars always buy a pet', () {
      expect(Pets.scout.starsRequired, 0);
      expect(Pets.byId(null), Pets.scout);
      expect(Pets.byId('ember', stars: 19), Pets.scout);
      expect(Pets.byId('ember', stars: 20).id, 'ember');
      // An id from a dead build must degrade, never vanish.
      expect(Pets.byId('sasquatch'), Pets.scout);
    });

    test("perks stay small enough not to break the campaign's floors", () {
      for (final pet in Pets.all) {
        expect(pet.perk.speedScale, lessThanOrEqualTo(1.08));
        expect(pet.perk.revealScale, lessThanOrEqualTo(1.2));
        expect(pet.perk.regrowDelta, lessThanOrEqualTo(0.5));
        expect(pet.perk.extraTreats, lessThanOrEqualTo(1));
      }
    });
  });
}
