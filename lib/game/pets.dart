import 'dart:ui';

/// Who you are running (§9.2), and the one habit of hers that runs with you.
///
/// Pets were a coat of paint and nothing more, and the file said so. That was
/// the wrong deal for the player: a thing that costs a hundred stars and does
/// nothing is decoration wearing a price tag. So each pet now brings one perk
/// — always small, always on, and deliberately a *style* rather than a
/// strength tier. No pet makes the board easier in the way a harder-to-earn
/// one does; each leans the run toward a different way lots of people like to
/// play. Later pets cost more stars, so they are a reason to finish levels
/// properly rather than a reason to be stronger next time.
///
/// Perks live here, in named numbers, because the balance question "how much
/// is a pet allowed to matter" is answered once, here, not at five call sites.
/// Every value is a small scale or an early shift — never a new mechanic —
/// so the campaign's own floors and sweeps remain the law underneath them.
class PetPerk {
  const PetPerk._({
    required this.name,
    required this.short,
    this.speedScale = 1.0,
    this.revealScale = 1.0,
    this.regrowDelta = 0,
    this.hintBeforeBy = 0,
    this.extraTreats = 0,
  });

  /// What the carousel shows. One line of copy, because that's all the room
  /// the picker has — the shape of the boon, not its arithmetic.
  final String name;

  /// The one-line voice of the perk, read after the pet's own blurb.
  final String short;

  /// Multiplies the speed steering would otherwise give her. >1 is a faster
  /// dog: a flat gift, but speed also means faster mistakes, which is why it
  /// is a style rather than a pure boon.
  final double speedScale;

  /// Multiplies how far her light (and the tap ring's *reveal* sibling) reach.
  final double revealScale;

  /// Seconds longer the field waits before growing her route back in. Small,
  /// because the demonstration is the animation, not the countdown.
  final double regrowDelta;

  /// Seconds sooner the "which way is the food" nudge appears. An information
  /// gift: the hint is *there*, it just stops being a punishment for patience.
  final double hintBeforeBy;

  /// Extra treats seeded into the level. A supply-biased pet, worth it where
  /// the supply is taxed by the mode the player is running.
  final int extraTreats;
}

class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.blurb,
    required this.perk,
    required this.body,
    required this.dark,
    required this.nose,
    required this.starsRequired,
  });

  final String id;
  final String name;

  /// One line, in the voice of the thing rather than the mechanic.
  final String blurb;

  /// What she does differently. Never null: a pet with no perk is the old
  /// mistake again with a new coat.
  final PetPerk perk;

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
    blurb: 'Started all this by following her nose.',
    perk: PetPerk._(
      name: 'Nose ahead',
      short: 'The "this way" nudge arrives two seconds sooner.',
      hintBeforeBy: 2.0,
    ),
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
      blurb: 'Runs hot, stops for nothing.',
      perk: PetPerk._(
        name: 'Hotfoot',
        short: 'A little faster everywhere — including the mistakes.',
        speedScale: 1.05,
      ),
      body: Color(0xFFFF9A6B),
      dark: Color(0xFFC4522E),
      nose: Color(0xFF2A1210),
      starsRequired: 20,
    ),
    Pet(
      id: 'frost',
      name: 'Frost',
      blurb: 'Walks the cold end of the field.',
      perk: PetPerk._(
        name: 'Cool blood',
        short: 'The field takes a breath longer to close back in.',
        regrowDelta: 0.3,
      ),
      body: Color(0xFFB6DCF2),
      dark: Color(0xFF6E9CC4),
      nose: Color(0xFF16202E),
      starsRequired: 55,
    ),
    Pet(
      id: 'moss',
      name: 'Moss',
      blurb: 'Older than the tunnels.',
      perk: PetPerk._(
        name: 'Forager',
        short: 'Finds one extra bone buried in every board she digs.',
        extraTreats: 1,
      ),
      body: Color(0xFFA8DCA8),
      dark: Color(0xFF5E9C66),
      nose: Color(0xFF15221A),
      starsRequired: 100,
    ),
    Pet(
      id: 'dusk',
      name: 'Dusk',
      blurb: 'Only ever seen on the way out.',
      perk: PetPerk._(
        name: 'Dusk sight',
        short: 'Her pool of light reaches a little further than yours.',
        revealScale: 1.12,
      ),
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
