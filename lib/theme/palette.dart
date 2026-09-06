import 'dart:ui';

import '../entities/guard.dart';
import '../entities/pickup.dart';
import '../game/level_rules.dart';
import '../hex/hex_cell.dart';

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
  static const stake = Color(0xFF9FE8C0);
  static const heel = Color(0xFFFFC4E0);
  // The rebuilt set. Same rule: one colour per kind *and* its own glyph.
  static const ration = Color(0xFFE8C898);
  static const lantern = Color(0xFFFFE27A);
  static const cloak = Color(0xFF9FA8C8);
  static const slowbeat = Color(0xFF7FD0E8);
  static const wardown = Color(0xFFE8E2FF);
  static const surepaws = Color(0xFFC8B090);
  static const pairwork = Color(0xFFF0B878);
  static const trowel = Color(0xFFA8C498);
  static const maul = Color(0xFFD8A0A0);
  static const echo = Color(0xFFB8E0E8);
  static const rewind = Color(0xFF9EC8FF);
  static const mole = Color(0xFFC8A888);
  static const harvest = Color(0xFFFFE8A0);
  static const whistle = Color(0xFFF0F0F0);
  static const seed = Color(0xFF7A9A70);
  static const beaconPickup = Color(0xFFFFF0B0);
  static const pouch = Color(0xFFD8B088);
  static const ironpaw = Color(0xFFB0BCCF);
  static const nightEyes = Color(0xFF8898E8);
  static const keepsake = Color(0xFFFF9FB0);
  static const waystone = Color(0xFF9FE0D0);

  // Obstacles (§6.1).
  static const springTop = Color(0xFF2E5A57);
  static const springSide = Color(0xFF1B3A38);
  static const springEdge = Color(0xFF6FE0D0);
  static const guard = Color(0xFFFF6B6B);
  static const guardLight = Color(0x33FF6B6B);

  /// Sentries. A cold searchlight white-blue, as far from the patrol's red as
  /// the palette allows: the two sweep identically and do completely different
  /// things, so colour is the only thing telling a player which one is coming.
  static const sentry = Color(0xFFC8D8FF);
  static const sentryLight = Color(0x2AC8D8FF);

  /// Faults. A warm rust against the field's blues and the spring's teal, so
  /// "this ground is temporary" reads at a glance and never at the same hue as
  /// the one obstacle that helps you.
  static const faultTop = Color(0xFF4A2F2A);
  static const faultSide = Color(0xFF2E1B18);
  static const faultEdge = Color(0xFFD9603F);

  /// Slopes. A warm amber that reads as *motion* rather than as danger — it is
  /// the one obstacle besides a spring that gives you something, and it must
  /// not be mistaken for the rust of ground that is about to leave.
  static const slopeTop = Color(0xFF4C4326);
  static const slopeSide = Color(0xFF2C2716);
  static const slopeEdge = Color(0xFFE0B457);

  /// Sunken ground. Deliberately the dimmest tile on the board: it is ground
  /// you cannot reach yet, and it should read as being further away than
  /// everything around it.
  static const sunkenTop = Color(0xFF232C3E);
  static const sunkenSide = Color(0xFF141A27);
  static const sunkenEdge = Color(0xFF5C7398);

  // The rebuilt tile set. Every type gets its own triple; every one also
  // carries a mark on the tile so nothing is told apart by colour alone.
  /// Hardpan: slab-cool, heavier than heavy. The seams carry the count.
  static const hardpanTop = Color(0xFF303A56);
  static const hardpanSide = Color(0xFF1E2438);
  static const hardpanEdge = Color(0xFF5C6C9C);

  /// Thatch: the one-cross braid, straw-dark so it never reads as wood.
  static const thatchTop = Color(0xFF3E3626);
  static const thatchSide = Color(0xFF262017);
  static const thatchEdge = Color(0xFF9C8A5A);

  /// Overgrowth heart: the deepest green on the board, alive.
  static const overgrowthTop = Color(0xFF1C3626);
  static const overgrowthSide = Color(0xFF102118);
  static const overgrowthEdge = Color(0xFF4CA06A);

  /// Tremor vent: ember inside basalt.
  static const tremorTop = Color(0xFF3A2626);
  static const tremorSide = Color(0xFF241616);
  static const tremorEdge = Color(0xFFE07050);
  static const tremorCore = Color(0xFFFFA068);

  /// Drift ice: the palest, coldest top on the board.
  static const iceTop = Color(0xFF3A4C68);
  static const iceSide = Color(0xFF232E44);
  static const iceEdge = Color(0xFF9FD0F0);

  /// Mire: deep umber, suction-dark.
  static const mireTop = Color(0xFF342A22);
  static const mireSide = Color(0xFF201A14);
  static const mireEdge = Color(0xFF8A6A4A);

  /// Eddy: the teal of springs turned outward — a repulsor reads as spring's
  /// family because both are motion tiles, but cooler and ringed outward.
  static const eddyTop = Color(0xFF24444C);
  static const eddySide = Color(0xFF152930);
  static const eddyEdge = Color(0xFF5AC0C8);

  /// Magnet bloom: violet where eddy is teal — attraction against repulsion.
  static const magnetTop = Color(0xFF362A50);
  static const magnetSide = Color(0xFF211A32);
  static const magnetEdge = Color(0xFFB48AE0);

  /// Thicket: near-plain, because its whole trick is concealing what is
  /// behind it; the leaf strokes carry the type.
  static const thicketTop = Color(0xFF28364A);
  static const thicketSide = Color(0xFF1A2334);
  static const thicketEdge = Color(0xFF6A8A5A);

  /// Sleeper: plainer than plain, one shade off — indistinguishable at a
  /// glance, legible on a stare, exactly the lie it is hired to tell.
  static const sleeperTop = Color(0xFF21304C);
  static const sleeperSide = Color(0xFF1B2742);
  static const sleeperEdge = Color(0xFF364872);

  /// Foxfire: plain ground wearing a pickup's jacket. The tile beneath is
  /// deliberately unremarkable — the lie is in the glow, not the slab.
  static const foxfireTop = Color(0xFF24304A);
  static const foxfireSide = Color(0xFF161E30);
  static const foxfireEdge = Color(0xFF8AA0C8);

  /// Scaffold: pale and high, standing off the ground.
  static const scaffoldTop = Color(0xFF42465A);
  static const scaffoldSide = Color(0xFF282A3A);
  static const scaffoldEdge = Color(0xFFA8B0D0);

  /// Thorn pad: ash-grey with points — the one tile that bites standing.
  static const thornTop = Color(0xFF3A3540);
  static const thornSide = Color(0xFF241F28);
  static const thornEdge = Color(0xFFC87878);

  /// Alarm bell: brass. The only warm-metal tile on the board, so the ring it
  /// makes is visible before it is heard.
  static const alarmTop = Color(0xFF4A3A20);
  static const alarmSide = Color(0xFF2C2212);
  static const alarmEdge = Color(0xFFE8C060);

  /// Lockbar gate: iron-cold, the crossbar is the mark.
  static const gateTop = Color(0xFF2A3348);
  static const gateSide = Color(0xFF1A2030);
  static const gateEdge = Color(0xFF7A90C0);

  /// Switch tile: one stud, lit when tripped.
  static const switchTop = Color(0xFF33302A);
  static const switchSide = Color(0xFF201E1A);
  static const switchEdge = Color(0xFFD0C070);

  /// Mirror lock: pearl-pale, twinned with its partner's thread.
  static const mirrorTop = Color(0xFF39404E);
  static const mirrorSide = Color(0xFF22262E);
  static const mirrorEdge = Color(0xFFD0DAE8);

  /// Guard-family lights beyond patrol red and sentry blue. One hue per
  /// behaviour so the sweep tells you the rule before you read the glyph.
  static const beaconLight = Color(0xFFFFE9A0);
  static const beaconGlow = Color(0x2AFFE9A0);
  static const spinnerLight = Color(0xFFFFA06B);
  static const spinnerGlow = Color(0x33FFA06B);
  static const runnerLight = Color(0xFFFF8898);
  static const runnerGlow = Color(0x33FF8898);
  static const blinkerLight = Color(0xFFB8C8E8);
  static const blinkerGlow = Color(0x26B8C8E8);
  static const wardenLight = Color(0xFFD04848);
  static const wardenGlow = Color(0x38D04848);

  /// Terrain: the gloom band's extra dimness, applied over the whole strip.
  static const gloomShade = Color(0x5505070F);

  /// The lamp a BEACON charge plants: the same warm pillar, carried by you.
  static const lampGlow = Color(0xFFFFE9A0);

  /// Herbaceous wisps: the one solid tile that lights its own face, so the
  /// gloom mechanic always shows the player at least one thing in the dark.
  static const foxfireGlow = Color(0xFF96B3FF);

  /// The colour of a *lamp* by its kind — what the light looks like, never
  /// what the ground under its beam means (that stays red / pale, by rule).
  static Color forLight(GuardKind kind) => switch (kind) {
    GuardKind.patrol => guard,
    GuardKind.sentry => sentry,
    GuardKind.beacon => beaconLight,
    GuardKind.spinner => spinnerLight,
    GuardKind.runner => runnerLight,
    GuardKind.blinker => blinkerLight,
    GuardKind.warden => wardenLight,
  };

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
    PickupKind.stake => stake,
    PickupKind.heel => heel,
    PickupKind.ration => ration,
    PickupKind.lantern => lantern,
    PickupKind.cloak => cloak,
    PickupKind.slowbeat => slowbeat,
    PickupKind.wardown => wardown,
    PickupKind.surepaws => surepaws,
    PickupKind.pairwork => pairwork,
    PickupKind.trowel => trowel,
    PickupKind.maul => maul,
    PickupKind.echo => echo,
    PickupKind.rewind => rewind,
    PickupKind.mole => mole,
    PickupKind.harvest => harvest,
    PickupKind.whistle => whistle,
    PickupKind.seed => seed,
    PickupKind.beacon => beaconPickup,
    PickupKind.pouch => pouch,
    PickupKind.ironpaw => ironpaw,
    PickupKind.nightEyes => nightEyes,
    PickupKind.keepsake => keepsake,
    PickupKind.waystone => waystone,
  };

  // The campaign map (§12.1). One colour per band, so the climb reads as four
  // stretches with characters of their own rather than one long numbered list.
  static const bandTutorial = Color(0xFF7FA8E0);
  static const bandFoundation = Color(0xFF6FD0A8);
  static const bandPressure = Color(0xFFE8B04B);
  static const bandMastery = Color(0xFFE0708A);
  static const bandCollapse = Color(0xFFD9603F);
  static const bandVigil = Color(0xFFC8D8FF);
  static const bandEndless = Color(0xFFB48AE0);

  static Color forBand(CampaignBand band) => switch (band) {
    CampaignBand.tutorial => bandTutorial,
    CampaignBand.foundation => bandFoundation,
    CampaignBand.pressure => bandPressure,
    CampaignBand.mastery => bandMastery,
    CampaignBand.collapse => bandCollapse,
    CampaignBand.vigil => bandVigil,
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

  /// The tile's face colour, in one place — the twin of [forPickup], for the
  /// same reason: three renderers want this switch, and one home keeps them
  /// true.
  static Color forHex(HexType type) => switch (type) {
    HexType.plain => plainTop,
    HexType.heavy => heavyTop,
    HexType.hardpan => hardpanTop,
    HexType.anchor => anchorTop,
    HexType.overgrowth => overgrowthTop,
    HexType.spring => springTop,
    HexType.fault => faultTop,
    HexType.thatch => thatchTop,
    HexType.slope => slopeTop,
    HexType.ice => iceTop,
    HexType.mire => mireTop,
    HexType.eddy => eddyTop,
    HexType.magnet => magnetTop,
    HexType.sunken => sunkenTop,
    HexType.scaffold => scaffoldTop,
    HexType.thicket => thicketTop,
    HexType.sleeper => sleeperTop,
    HexType.foxfire => foxfireTop,
    HexType.thorn => thornTop,
    HexType.alarm => alarmTop,
    HexType.tremor => tremorTop,
    HexType.gate => gateTop,
    HexType.switchTile => switchTop,
    HexType.mirror => mirrorTop,
  };

  /// The tile's mark/rim colour, the hue every one of its glyphs is drawn in.
  static Color edgeOf(HexType type) => switch (type) {
    HexType.plain => plainEdge,
    HexType.heavy => heavyEdge,
    HexType.hardpan => hardpanEdge,
    HexType.anchor => anchorEdge,
    HexType.overgrowth => overgrowthEdge,
    HexType.spring => springEdge,
    HexType.fault => faultEdge,
    HexType.thatch => thatchEdge,
    HexType.slope => slopeEdge,
    HexType.ice => iceEdge,
    HexType.mire => mireEdge,
    HexType.eddy => eddyEdge,
    HexType.magnet => magnetEdge,
    HexType.sunken => sunkenEdge,
    HexType.scaffold => scaffoldEdge,
    HexType.thicket => thicketEdge,
    HexType.sleeper => sleeperEdge,
    HexType.foxfire => foxfireEdge,
    HexType.thorn => thornEdge,
    HexType.alarm => alarmEdge,
    HexType.tremor => tremorEdge,
    HexType.gate => gateEdge,
    HexType.switchTile => switchEdge,
    HexType.mirror => mirrorEdge,
  };
}
