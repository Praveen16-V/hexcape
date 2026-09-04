import 'dart:ui';

/// Who you are running (§9.2).
///
/// Pets are a coat of paint and nothing more: no pet is faster, reaches further
/// or eats less. That is deliberate. The moment one of them plays better than
/// another, every level is balanced against whichever the player happens to have
/// unlocked, and a reward for progress quietly becomes a tax on not having it.
/// They cost stars, so they are a reason to go back and finish a level properly
/// rather than a reason to be stronger next time.
class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.blurb,
    required this.body,
    required this.dark,
    required this.nose,
    required this.starsRequired,
  });

  final String id;
  final String name;

  /// One line, in the voice of the thing rather than the mechanic.
  final String blurb;

  final Color body;
  final Color dark;
  final Color nose;

  /// Stars across the campaign needed to unlock. Zero for the starter.
  final int starsRequired;

  /// The soft halo under her, derived rather than authored — one fewer colour
  /// per pet to keep in tune with the other two.
  Color get glow => body.withValues(alpha: 0.4);
}

class Pets {
  Pets._();

  static const scout = Pet(
    id: 'scout',
    name: 'Scout',
    blurb: 'Started all this by following her nose',
    body: Color(0xFFF0A868),
    dark: Color(0xFFC97F44),
    nose: Color(0xFF2A1B12),
    starsRequired: 0,
  );

  static const all = <Pet>[
    scout,
    Pet(
      id: 'ember',
      name: 'Ember',
      blurb: 'Runs hot, stops for nothing',
      body: Color(0xFFFF9A6B),
      dark: Color(0xFFC4522E),
      nose: Color(0xFF2A1210),
      starsRequired: 20,
    ),
    Pet(
      id: 'frost',
      name: 'Frost',
      blurb: 'Walks the cold end of the field',
      body: Color(0xFFB6DCF2),
      dark: Color(0xFF6E9CC4),
      nose: Color(0xFF16202E),
      starsRequired: 55,
    ),
    Pet(
      id: 'moss',
      name: 'Moss',
      blurb: 'Older than the tunnels',
      body: Color(0xFFA8DCA8),
      dark: Color(0xFF5E9C66),
      nose: Color(0xFF15221A),
      starsRequired: 100,
    ),
    Pet(
      id: 'dusk',
      name: 'Dusk',
      blurb: 'Only ever seen on the way out',
      body: Color(0xFFC8AEF0),
      dark: Color(0xFF8A6EC4),
      nose: Color(0xFF1C1628),
      starsRequired: 150,
    ),
  ];

  /// Never returns null, and never returns a pet the player has not earned.
  ///
  /// A saved id can outlive the thing it names — a build that renames or drops
  /// a pet would otherwise leave a player with an invisible dog and no way to
  /// fix it from inside the game.
  static Pet byId(String? id, {int stars = 1 << 30}) {
    for (final pet in all) {
      if (pet.id == id && pet.starsRequired <= stars) {
        return pet;
      }
    }
    return scout;
  }

  static bool isUnlocked(Pet pet, int stars) => stars >= pet.starsRequired;
}
