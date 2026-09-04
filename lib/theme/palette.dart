import 'dart:ui';

import '../entities/pickup.dart';
import '../game/level_rules.dart';

/// Colours for the whole game (§9.1). Dark ground so the glowing dog and the
/// gold goal read instantly, and so large flat fills stay cheap to render.
class Palette {
  Palette._();

  static const background = Color(0xFF0A0E1A);
  static const backgroundVignette = Color(0xFF05070F);

  // Plain hexes — the clearable default.
  static const plainTop = Color(0xFF1E2A44);
  static const plainSide = Color(0xFF182440);
  static const plainEdge = Color(0xFF2F4066);

  // Heavy hexes — two taps to clear. Denser and warmer than plain, and always
  // carrying a doubled inner ring so they are never told apart from anchors by
  // colour alone (§5).
  static const heavyTop = Color(0xFF2A3352);
  static const heavySide = Color(0xFF1B2138);
  static const heavyEdge = Color(0xFF4A5C8C);
  static const heavyCrack = Color(0xFF8FA6D8);

  // Anchor hexes — never clearable. Darker and colder than plain, and always
  // carrying a rivet mark so they are never distinguished by colour alone (§5).
  static const anchorTop = Color(0xFF141821);
  static const anchorSide = Color(0xFF0B0D13);
  static const anchorEdge = Color(0xFF3A4252);
  static const anchorRivet = Color(0xFF5A6478);

  // Regrowth warning states (§10).
  static const regrowGhost = Color(0x332F4066);
  static const regrowPulse = Color(0xFF4A6BA8);
  static const shockwave = Color(0xFF6E90D0);

  // Dog (§9.2).
  static const dogBody = Color(0xFFF0A868);
  static const dogBodyDark = Color(0xFFC97F44);
  static const dogGlow = Color(0x66F0A868);
  static const dogNose = Color(0xFF2A1B12);
  static const pawprint = Color(0xFFF0A868);

  // Goal (§9.3).
  static const goalBone = Color(0xFFFFE9B8);
  static const goalGlow = Color(0xFFFFCF5C);

  // Pickups (§6.2). Each also carries its own glyph, so they are never told
  // apart by colour alone.
  static const treat = Color(0xFFFFD98A);
  static const treatGlow = Color(0xFFFFB43F);
  static const freeze = Color(0xFF8FD8FF);
  static const radiusPlus = Color(0xFFC9A6FF);
  static const sprint = Color(0xFF8FE3B0);
  static const scent = Color(0xFFFFA6D8);
  static const blast = Color(0xFFFF8A5C);
  static const dig = Color(0xFFD8C08A);

  // Obstacles (§6.1).
  static const springTop = Color(0xFF2E5A57);
  static const springSide = Color(0xFF1B3A38);
  static const springEdge = Color(0xFF6FE0D0);
  static const guard = Color(0xFFFF6B6B);
  static const guardLight = Color(0x33FF6B6B);

  /// The colour of a pickup, in one place. This switch used to be copied into
  /// the field renderer, the powerup ring and back again, so adding a kind meant
  /// finding all of them.
  static Color forPickup(PickupKind kind) => switch (kind) {
    PickupKind.treat => treat,
    PickupKind.freeze => freeze,
    PickupKind.radiusPlus => radiusPlus,
    PickupKind.sprint => sprint,
    PickupKind.scent => scent,
    PickupKind.blast => blast,
    PickupKind.dig => dig,
  };

  // The campaign map (§12.1). One colour per band, so the climb reads as four
  // stretches with characters of their own rather than sixty numbered tiles.
  static const bandTutorial = Color(0xFF7FA8E0);
  static const bandFoundation = Color(0xFF6FD0A8);
  static const bandPressure = Color(0xFFE8B04B);
  static const bandMastery = Color(0xFFE0708A);
  static const bandEndless = Color(0xFFB48AE0);

  static Color forBand(CampaignBand band) => switch (band) {
    CampaignBand.tutorial => bandTutorial,
    CampaignBand.foundation => bandFoundation,
    CampaignBand.pressure => bandPressure,
    CampaignBand.mastery => bandMastery,
    CampaignBand.endless => bandEndless,
  };

  /// A level the player has not reached yet. Still legible — a map that hides
  /// what is coming gives the player nothing to climb toward.
  static const lockedTile = Color(0xFF1A2136);
  static const lockedEdge = Color(0xFF2A3552);

  // Hunger (§2.2's clock).
  static const hungerFull = Color(0xFFE8B04B);
  static const hungerLow = Color(0xFFE05A5A);

  // Interface.
  static const tapRing = Color(0x33A8C4FF);
  static const tapRingActive = Color(0x66A8C4FF);
  static const hudText = Color(0xFFB9C6E4);
  static const hudDim = Color(0xFF64748B);
  static const danger = Color(0xFFE05A5A);
  static const truePathDebug = Color(0x554ADE80);
}
