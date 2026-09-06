import 'package:flutter/material.dart';

import '../components/glyphs.dart';
import '../entities/pickup.dart';
import '../game/level_rules.dart';
import '../hex/hex_cell.dart';
import '../hex/hex_layout.dart';
import '../theme/palette.dart';

/// What everything in the game does.
///
/// Every explanation the game gives is transient: a tutorial step that runs
/// once, a `teaches` line that shows for eight seconds, a banner that fires on
/// one level and never again. That works the first time and leaves a player
/// coming back after a week with nowhere to look up what a ringed tile is, or
/// what SCENT does.
///
/// **Entries appear only once the campaign has introduced them.** The reference
/// follows the same one-idea-at-a-time rule the campaign does — a level-three
/// player opening this should not read about patrols they will not meet for
/// another eighteen levels.
class ReferenceSheet extends StatelessWidget {
  const ReferenceSheet({required this.unlocked, super.key});

  /// The highest level the player has reached, which is what gates the entries.
  final int unlocked;

  @override
  Widget build(BuildContext context) {
    final entries = referenceFor(unlocked);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Palette.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.lockedEdge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'HOW IT WORKS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 18),
            for (final section in ReferenceSection.values)
              if (entries.any((e) => e.section == section)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                  child: Text(
                    section.label.toUpperCase(),
                    style: TextStyle(
                      color: Palette.hudDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                for (final entry in entries.where((e) => e.section == section))
                  _EntryRow(entry: entry),
                const SizedBox(height: 14),
              ],
          ],
        ),
      ),
    );
  }
}

enum ReferenceSection {
  hexes('Tiles'),
  obstacles('In your way'),
  pickups('Worth a detour'),
  rules('The rules');

  const ReferenceSection(this.label);

  final String label;
}

/// One thing the game contains, and what it does.
class ReferenceEntry {
  const ReferenceEntry({
    required this.section,
    required this.name,
    required this.blurb,
    this.hex,
    this.pickup,
    this.icon,
    this.unlocksAt = 1,
  });

  final ReferenceSection section;
  final String name;
  final String blurb;

  /// Drawn as its real tile, if it is one.
  final HexType? hex;

  /// Drawn with its real glyph, if it is one.
  final PickupKind? pickup;

  /// For the things that are neither — a patrol, a rule.
  final IconData? icon;

  /// The campaign level that introduces it.
  final int unlocksAt;
}

/// Every entry the player has met, in order.
///
/// Exposed rather than private so a test can assert that no hex type, pickup or
/// obstacle exists without an entry — a new mechanic should not be able to
/// arrive without an explanation.
List<ReferenceEntry> referenceFor(int unlocked) => [
  for (final e in allReferenceEntries)
    if (e.unlocksAt <= unlocked) e,
];

/// What a tile is, for the in-place inspector.
///
/// The same entries the sheet is built from rather than a second set of copy.
/// One description of a spring means the card and the sheet cannot drift, and
/// `screens_test` already refuses to let a type exist without one.
ReferenceEntry? referenceForHex(HexType type) => _byHex[type];

ReferenceEntry? referenceForPickup(PickupKind kind) => _byPickup[kind];

/// Built once rather than scanned per call. The notice and inspector cards ask
/// on every frame they are on screen, and the sheet is seventy entries long.
final Map<HexType, ReferenceEntry> _byHex = {
  for (final e in allReferenceEntries)
    if (e.hex != null) e.hex!: e,
};

final Map<PickupKind, ReferenceEntry> _byPickup = {
  for (final e in allReferenceEntries)
    if (e.pickup != null) e.pickup!: e,
};

/// An entry drawn as the game itself draws it.
///
/// Public because the inspector card shows the same mark the sheet does, and a
/// hand-drawn lookalike is exactly how a legend starts lying about the board.
class ReferenceMark extends StatelessWidget {
  const ReferenceMark({required this.entry, this.size = 46, super.key});

  final ReferenceEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: entry.icon != null
          ? Icon(entry.icon, color: Palette.dogBody, size: size * 0.52)
          : CustomPaint(painter: _EntryPainter(entry)),
    );
  }
}

const allReferenceEntries = <ReferenceEntry>[
  // ── The four rules, first: everything else on this page is a verb of
  // one of these.
  ReferenceEntry(
    section: ReferenceSection.rules,
    name: 'She never stops',
    blurb:
        'You do not move her. You open ground, and she drifts toward '
        'whatever opens — faster across open space, slower in a tight channel. '
        'The small arrow shows where she is aiming on open ground.',
    icon: Icons.pets,
  ),
  ReferenceEntry(
    section: ReferenceSection.rules,
    name: 'Taps are rationed',
    blurb:
        'Each level grants a few more taps than the best possible route '
        'needs. Stars measure how little of that allowance you spent.',
    icon: Icons.touch_app,
    unlocksAt: 4,
  ),
  ReferenceEntry(
    section: ReferenceSection.rules,
    name: 'Fog',
    blurb:
        'You only see what she is near. Some taps are always spent finding '
        'out where the walls are — that is priced in.',
    icon: Icons.blur_on,
    unlocksAt: 5,
  ),
  ReferenceEntry(
    section: ReferenceSection.rules,
    name: 'Hunger',
    blurb:
        'The bar drains while you play. Treats top it up. Run it out and '
        'the run ends, however many taps you have left.',
    icon: Icons.timer,
    unlocksAt: 5,
  ),
  ReferenceEntry(
    section: ReferenceSection.rules,
    name: 'Held tools',
    blurb:
        'Charges you pick up wait in a row above her. Tap one to arm it — '
        'your next tile tap spends it — and tap it again to put it down '
        'unspent. Holding one costs nothing.',
    icon: Icons.backpack,
    unlocksAt: Campaign.foundationEnd + 1,
  ),
  ReferenceEntry(
    section: ReferenceSection.rules,
    name: 'Pets',
    blurb:
        'Each leans the run toward a style — one spots out sooner, one runs '
        'hotter, one leaves the ground slower to close — but none of them is '
        'the strictly right one. Stars buy the company, not a shortcut.',
    icon: Icons.pets,
    unlocksAt: 0,
  ),
  ReferenceEntry(
    section: ReferenceSection.rules,
    name: 'Two ways in',
    blurb:
        'Normal is the adventure; Hard is the gauntlet — heavier ground, '
        'leaner supplies, faster lights, deeper dark. The first three '
        'tutoring levels read the same either way, and the letter by your '
        'stars says which of the two paid for them.',
    icon: Icons.fitness_center,
  ),

  // ── Tiles, in the order the campaign introduces them.
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Plain',
    blurb: 'One tap clears it. She walks into whatever opens.',
    hex: HexType.plain,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Ringed',
    blurb:
        'Two taps. Pushing through three of these costs more than going '
        'around them — which is the whole reason a route is worth thinking '
        'about.',
    hex: HexType.heavy,
    unlocksAt: 3,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Riveted',
    blurb:
        'Never clears. These are the walls, and what you leave standing is '
        'as much a choice as what you open. DIG is the one answer.',
    hex: HexType.anchor,
    unlocksAt: 3,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Mire',
    blurb:
        'She crosses at half speed. Cheap in taps, dear on the clock — a '
        'time tax, paid in one currency only.',
    hex: HexType.mire,
    unlocksAt: Campaign.mireFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Spring',
    blurb:
        'Clears in one tap like a plain tile, then throws her several cells '
        'the way she was already walking. A gift if you set it up, a problem '
        'if you did not.',
    hex: HexType.spring,
    unlocksAt: Campaign.springsFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Thicket',
    blurb:
        'Its neighbours stay disguised until the thicket itself is cleared — '
        'fog you must carve through, cheap and blinding at once.',
    hex: HexType.thicket,
    unlocksAt: Campaign.thicketFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Sleeper',
    blurb:
        'Shows its true face only when she is right beside it. Plain until '
        'proven ruined — read the closed eye before stepping in.',
    hex: HexType.sleeper,
    unlocksAt: Campaign.sleeperFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Foxfire',
    blurb:
        'Shines in the fog exactly like a reward. It is just a tile. The '
        'detour was the whole trap, and you took it.',
    hex: HexType.foxfire,
    unlocksAt: Campaign.foxfireFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Cracked',
    blurb:
        'Clears in one tap, then closes again on its own — wherever it is, '
        'whether or not anything is beside it. A line of them is the short '
        'way through, but only if you run it in one go.',
    hex: HexType.fault,
    unlocksAt: Campaign.faultsFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Thatch',
    blurb:
        'Clears in one tap, then knits shut the moment she steps off it: a '
        'braid you cross once and never again. Carry a REWIND for the door '
        'you did not mean to close behind her.',
    hex: HexType.thatch,
    unlocksAt: Campaign.thatchFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Drift ice',
    blurb:
        'She keeps her heading on it — no steering until she is off. Free '
        'speed in one direction, priced in certainty.',
    hex: HexType.ice,
    unlocksAt: Campaign.iceFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Alarm bell',
    blurb:
        'Stepping on it whips every light on the board to a half-again '
        'speed for a short squall. A shortcut that angers the lights.',
    hex: HexType.alarm,
    unlocksAt: Campaign.alarmFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Slope',
    blurb:
        'Clears in one tap, then pushes her the way the arrow points — not '
        'the way she was walking. The only tile you can aim in advance, so '
        'read it before you open it. HEEL will hold her out of one.',
    hex: HexType.slope,
    unlocksAt: Campaign.slopesFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Hardpan',
    blurb:
        'Three taps, when everything around it costs one. PAIRWORK halves '
        'the tax; MAUL answers it outright. The late campaign’s tollbooth.',
    hex: HexType.hardpan,
    unlocksAt: Campaign.hardpanFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Overgrowth heart',
    blurb:
        'Not tappable — DIG only. While it stands, everything within two '
        'rings closes twice as fast. Kill the heart and the whole field '
        'forgives you at once.',
    hex: HexType.overgrowth,
    unlocksAt: Campaign.overgrowthFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Eddy',
    blurb:
        'Open ground that shoves her off her line as she crosses. Not '
        'dangerous — unparking. Carve past fast, or lean on it to rake a '
        'corner.',
    hex: HexType.eddy,
    unlocksAt: Campaign.eddyFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Scaffold',
    blurb:
        'Only clearable while she is still far from it — too close and it '
        'is unstable ground. It must be answered early, from range. REACH’s '
        'first real job.',
    hex: HexType.scaffold,
    unlocksAt: Campaign.scaffoldFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Magnet bloom',
    blurb:
        'Open ground that pulls her toward its centre while she stands on '
        'it. A well you only enter willingly — an aimable gathering force.',
    hex: HexType.magnet,
    unlocksAt: Campaign.magnetFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Sunken',
    blurb:
        'Only clears when something beside it is already open, so you cannot '
        'reach across it — you have to carve up to it a tile at a time.',
    hex: HexType.sunken,
    unlocksAt: Campaign.sunkenFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Lockbar gate',
    blurb:
        'Stays solid until its paired switch tile somewhere on the board is '
        'opened, then it is one more plain tap. The route is ordered before '
        'it is priced.',
    hex: HexType.gate,
    unlocksAt: Campaign.gateFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Switch',
    blurb:
        'One tap, and every lockbar tied to its crest lifts for good. The '
        'whole mechanic is in where it is standing, not in what it costs.',
    hex: HexType.switchTile,
    unlocksAt: Campaign.gateFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Mirror lock',
    blurb:
        'A tap charges it; it opens only when its twin, far across the '
        'board, has also been charged — and then both give at once. Long '
        'division for a route. ECHO is the shortcut that exists for it.',
    hex: HexType.mirror,
    unlocksAt: Campaign.mirrorFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Thornpad',
    blurb:
        'Stepping on it squares two seconds off her clock. Never blocks, '
        'always bites — a shortcut with a toll on it.',
    hex: HexType.thorn,
    unlocksAt: Campaign.thornFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.hexes,
    name: 'Tremor vent',
    blurb:
        'On a slow drumbeat, it hurls every closing on the board two seconds '
        'nearer its snap. Two taps silence it; living with it means the '
        'board breathes in and you breathe around it.',
    hex: HexType.tremor,
    unlocksAt: Campaign.tremorFrom,
  ),

  // ── Lights, in the same introducing order.
  ReferenceEntry(
    section: ReferenceSection.obstacles,
    name: 'Regrowth',
    blurb:
        'Cleared tiles grow back from the outside in. You get a ghost, then '
        'two pulses, then it snaps shut. She can always escape until the snap.',
    icon: Icons.grid_on,
    unlocksAt: 2,
  ),
  ReferenceEntry(
    section: ReferenceSection.obstacles,
    name: 'Patrol',
    blurb:
        'A light that sweeps a fixed route. She will not walk into it, and '
        'if it catches her it costs three seconds. You cannot clear it away — '
        'you wait for it.',
    icon: Icons.visibility,
    unlocksAt: Campaign.guardsFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.obstacles,
    name: 'Warded light',
    blurb:
        'A pale light that sweeps like a patrol, but does the opposite: she '
        'walks through it freely and it never bites — your taps are what it '
        'refuses. Wait for it to pass, or HEEL and time the gap.',
    icon: Icons.highlight,
    unlocksAt: Campaign.sentriesFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.obstacles,
    name: 'Spinner',
    blurb:
        'A light orbiting a pivot, its windows opening and closing around a '
        'single cell. It never turns back, so the beat it keeps is honest.',
    icon: Icons.autorenew,
    unlocksAt: Campaign.spinnerFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.obstacles,
    name: 'Blinker',
    blurb:
        'A fixed patch that breathes on a metronome: fully lit, fully dark. '
        'Pure rhythm taps — everything about it is *when*.',
    icon: Icons.bolt,
    unlocksAt: Campaign.blinkerFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.obstacles,
    name: 'Standing beacon',
    blurb:
        'One lit patch that never moves or sleeps. Tiles inside it will not '
        'take taps — the route through its ground is walked, never carved.',
    icon: Icons.lightbulb_circle,
    unlocksAt: Campaign.beaconFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.obstacles,
    name: 'Runner',
    blurb:
        'A dash of light down a corridor, with a long proud pause at each '
        'end. The fastest thing in the field is also the easiest to read.',
    icon: Icons.east,
    unlocksAt: Campaign.runnerFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.obstacles,
    name: 'Warden',
    blurb:
        'A slow light whose wake closes ground behind her. The corridor is '
        'not safe twice — cross it, or outrun what it grows over.',
    icon: Icons.remove_red_eye,
    unlocksAt: Campaign.wardenFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.obstacles,
    name: 'The gloom',
    blurb:
        'Sundown on a whole band: beyond the lamps, everything sits at half '
        'reach. LANTERN is a window; NIGHT EYES is forever.',
    icon: Icons.nightlight,
    unlocksAt: Campaign.gloomFrom,
  ),

  // ── Pickups, in the order the campaign offers them.
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Treat',
    blurb:
        'Buys back seconds and taps. Worth less as the campaign climbs, so '
        'it stays a decision rather than a refund.',
    pickup: PickupKind.treat,
    unlocksAt: 4,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Freeze',
    blurb:
        'Regrowth stops for five seconds. Buys safety with the one thing it '
        'cannot refill: time.',
    pickup: PickupKind.freeze,
    unlocksAt: 4,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Reach',
    blurb:
        'Your taps reach further for eight seconds, so more of the route '
        'can be carved from one spot.',
    pickup: PickupKind.radiusPlus,
    unlocksAt: 4,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Sprint',
    blurb: 'She moves faster for six seconds. The answer to the clock.',
    pickup: PickupKind.sprint,
    unlocksAt: 6,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Ration',
    blurb:
        'Taps, with no seconds attached at all. The budget rescue that does '
        'not pretend to be food.',
    pickup: PickupKind.ration,
    unlocksAt: Campaign.rationFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Lantern',
    blurb:
        'The fog parts wider for a while — not one route lit, but the whole '
        'map near her laid open to be read.',
    pickup: PickupKind.lantern,
    unlocksAt: Campaign.lanternFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Pairwork',
    blurb:
        'For a while, every tap strikes the same tile twice. Brambles fall '
        'in one; hardpan in one and a half. Still one tap spent.',
    pickup: PickupKind.pairwork,
    unlocksAt: Campaign.pairworkFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Scent',
    blurb:
        'Lights the cheapest way through for five seconds. The only one '
        'that buys knowledge instead of resources.',
    pickup: PickupKind.scent,
    unlocksAt: Campaign.foundationEnd + 1,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Slowbeat',
    blurb:
        'Every light on the board sweeps at half speed for a while. The '
        'whole rhythm section plays along, once.',
    pickup: PickupKind.slowbeat,
    unlocksAt: Campaign.slowbeatFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Cloak',
    blurb:
        'Patrol light goes through her. She may walk the lit ground, '
        'unbitten, until the film wears off.',
    pickup: PickupKind.cloak,
    unlocksAt: Campaign.cloakFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Blast',
    blurb:
        'Held until you spend it. Tap BLAST above to arm it; your next tile '
        'tap clears a whole cluster.',
    pickup: PickupKind.blast,
    unlocksAt: Campaign.foundationEnd + 1,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Trowel',
    blurb:
        'The next tap opens the tapped tile and the two straight beyond it — '
        'a corridor carved with one decision. BLAST\’s line-minded cousin.',
    pickup: PickupKind.trowel,
    unlocksAt: Campaign.trowelFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Harvest',
    blurb:
        'The nearest unclaimed pickup walks to you. Skin the detour economy: '
        'the fox-glow in the fog it never falls for.',
    pickup: PickupKind.harvest,
    unlocksAt: Campaign.harvestFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Whistle',
    blurb:
        'She walks three cells back along the trail she actually walked. '
        'Not a steering wheel — a forgiveness.',
    pickup: PickupKind.whistle,
    unlocksAt: Campaign.whistleFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Dig',
    blurb:
        'Held until you spend it. Tap DIG above to arm it, then tap a riveted '
        'tile to break the only wall that can be removed. An overgrowth '
        'heart answers only this, too.',
    pickup: PickupKind.dig,
    unlocksAt: Campaign.pressureEnd + 1,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Maul',
    blurb:
        'The next tap breaks whatever is clearable in one strike — hardpan, '
        'even one mirror half, alone. The single answer to the deep taxes.',
    pickup: PickupKind.maul,
    unlocksAt: Campaign.maulFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Rewind',
    blurb:
        'The last tiles the field closed — crackline, braid, regrowth, any '
        'of it — close no longer. It reopens the map, not a decision.',
    pickup: PickupKind.rewind,
    unlocksAt: Campaign.rewindFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Surepaws',
    blurb:
        'For a while she answers the throw tiles not at all: no spring, no '
        'slope, no ice, no undertow. Full control through a hazard lane.',
    pickup: PickupKind.surepaws,
    unlocksAt: Campaign.surepawsFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Stake',
    blurb:
        'Held until you spend it. Tap STAKE above to arm it, then tap an open '
        'tile to hold it open for the rest of the run — no regrowth, no crack. '
        'One tile, so choose the one that must not close.',
    pickup: PickupKind.stake,
    unlocksAt: Campaign.stakeFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Wardown',
    blurb:
        'Taps land through sentry light for a while. The pale glare stops '
        'being a wall and starts being decoration.',
    pickup: PickupKind.wardown,
    unlocksAt: Campaign.wardownFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Heel',
    blurb:
        'Held until you spend it. Tap HEEL above to arm it, then tap as normal '
        '— the tile opens and she stands still for a moment instead of walking '
        'into it. The one way to choose your moment.',
    pickup: PickupKind.heel,
    unlocksAt: Campaign.heelFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Echo',
    blurb:
        'The next tap also strikes the tile mirrored across her, if that '
        'tile will take a strike. One decision, two banks of the river.',
    pickup: PickupKind.echo,
    unlocksAt: Campaign.echoFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Seed',
    blurb:
        'Tamp one plain tile into a permanent wall — the only tool that '
        'makes ground worse, wisely. The field refuses if it would seal '
        'her in.',
    pickup: PickupKind.seed,
    unlocksAt: Campaign.seedFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Mole',
    blurb:
        'Any one tile you have revealed, anywhere, opens. The reach of the '
        'whole board, exactly once.',
    pickup: PickupKind.mole,
    unlocksAt: Campaign.moleFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Beacon',
    blurb:
        'Plant a lamp where she stands; the ground there stays lit for the '
        'rest of the run. Light the crossroads you keep coming back to.',
    pickup: PickupKind.beacon,
    unlocksAt: Campaign.beaconDropFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Waystone',
    blurb:
        'The broad nudge toward the food holds for the rest of the run — '
        'the hint that the lost button asks for, already answered.',
    pickup: PickupKind.waystone,
    unlocksAt: Campaign.waystoneFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Night eyes',
    blurb:
        'The pool of light around her stays wider for the rest of the run. '
        'The gloom\’s answer that does not switch off.',
    pickup: PickupKind.nightEyes,
    unlocksAt: Campaign.nightEyesFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Pouch',
    blurb: 'The next treat pays double. One merciful merchant, one deal.',
    pickup: PickupKind.pouch,
    unlocksAt: Campaign.pouchFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Ironpaw heart',
    blurb:
        'For the rest of the run, thornpads and alarm bells no longer fire '
        'when she crosses. Walk the toll road.',
    pickup: PickupKind.ironpaw,
    unlocksAt: Campaign.ironpawFrom,
  ),
  ReferenceEntry(
    section: ReferenceSection.pickups,
    name: 'Keepsake',
    blurb:
        'One mercy, carried: the first time this run would end — crushed or '
        'starved — it breaks instead, giving ground or seconds, whichever '
        'was owed.',
    pickup: PickupKind.keepsake,
    unlocksAt: Campaign.keepsakeFrom,
  ),
];

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final ReferenceEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReferenceMark(entry: entry),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.blurb,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the entry using the game's own drawing code, never a lookalike.
class _EntryPainter extends CustomPainter {
  _EntryPainter(this.entry);

  final ReferenceEntry entry;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final hex = entry.hex;
    if (hex != null) {
      final r = size.width * 0.42;
      final path = HexLayout.pathFromCorners(HexLayout.cornersAt(centre, r));
      fill.color = Palette.forHex(hex);
      canvas.drawPath(path, fill);
      stroke.color = Palette.edgeOf(hex);
      canvas.drawPath(path, stroke);
      _paintHexMark(canvas, hex, centre, r, fill, stroke);
      return;
    }

    final pickup = entry.pickup;
    if (pickup != null) {
      final colour = Palette.forPickup(pickup);
      fill.color = colour;
      stroke.color = colour;
      drawPickupGlyph(
        canvas,
        pickup,
        centre: centre,
        size: size.width * 0.26,
        fill: fill,
        stroke: stroke,
      );
    }
  }

  /// The rivets and rings that tell the tile types apart on the board.
  void _paintHexMark(
    Canvas canvas,
    HexType hex,
    Offset centre,
    double r,
    Paint fill,
    Paint stroke,
  ) {
    switch (hex) {
      case HexType.plain:
        break;
      case HexType.heavy:
        stroke.color = Palette.heavyEdge;
        canvas.drawPath(
          HexLayout.pathFromCorners(HexLayout.cornersAt(centre, r * 0.5)),
          stroke,
        );
      case HexType.anchor:
        stroke.color = Palette.anchorRivet;
        canvas.drawPath(
          HexLayout.pathFromCorners(HexLayout.cornersAt(centre, r * 0.42)),
          stroke,
        );
        fill.color = Palette.anchorRivet;
        canvas.drawCircle(centre, r * 0.13, fill);
      case HexType.spring:
        stroke.color = Palette.springEdge;
        for (var i = 0; i < 3; i++) {
          final y = centre.dy + r * (0.34 - i * 0.3);
          canvas.drawPath(
            Path()
              ..moveTo(centre.dx - r * 0.38, y)
              ..lineTo(centre.dx, y - r * 0.3)
              ..lineTo(centre.dx + r * 0.38, y),
            stroke,
          );
        }
      case HexType.fault:
        stroke.color = Palette.faultEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.12, centre.dy - r * 0.5)
            ..lineTo(centre.dx + r * 0.16, centre.dy - r * 0.12)
            ..lineTo(centre.dx - r * 0.14, centre.dy + r * 0.12)
            ..lineTo(centre.dx + r * 0.12, centre.dy + r * 0.5),
          stroke,
        );
      case HexType.slope:
        // An arrow, because the direction *is* the mechanic. The sheet draws
        // it pointing right; on the board it points wherever the cell does.
        stroke.color = Palette.slopeEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.44, centre.dy)
            ..lineTo(centre.dx + r * 0.34, centre.dy)
            ..moveTo(centre.dx + r * 0.04, centre.dy - r * 0.3)
            ..lineTo(centre.dx + r * 0.38, centre.dy)
            ..lineTo(centre.dx + r * 0.04, centre.dy + r * 0.3),
          stroke,
        );
      case HexType.sunken:
        // Nested rings, receding. Ground that is further away than it looks.
        stroke.color = Palette.sunkenEdge;
        for (final scale in [0.62, 0.4]) {
          canvas.drawPath(
            HexLayout.pathFromCorners(HexLayout.cornersAt(centre, r * scale)),
            stroke,
          );
        }
      case HexType.mire:
        fill.color = Palette.mireEdge.withValues(alpha: 0.5);
        canvas.drawOval(
          Rect.fromCenter(
            center: centre.translate(-r * 0.16, r * 0.10),
            width: r * 0.60,
            height: r * 0.34,
          ),
          fill,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: centre.translate(r * 0.22, -r * 0.14),
            width: r * 0.40,
            height: r * 0.22,
          ),
          fill,
        );
      case HexType.thicket:
        stroke.color = Palette.thicketEdge;
        for (final spec in [(-0.34, -0.18), (0.0, -0.40), (0.34, -0.18)]) {
          canvas.drawPath(
            Path()
              ..moveTo(centre.dx + r * spec.$1, centre.dy + r * 0.34)
              ..lineTo(centre.dx + r * spec.$1, centre.dy + r * spec.$2),
            stroke,
          );
        }
      case HexType.sleeper:
        stroke.color = Palette.sleeperEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.38, centre.dy - r * 0.05)
            ..quadraticBezierTo(
              centre.dx,
              centre.dy + r * 0.34,
              centre.dx + r * 0.38,
              centre.dy - r * 0.05,
            )
            ..moveTo(centre.dx, centre.dy + r * 0.12)
            ..lineTo(centre.dx, centre.dy + r * 0.26),
          stroke,
        );
      case HexType.foxfire:
        fill.color = Palette.foxfireEdge;
        for (final spec in [
          (0.18, -0.16, 0.11),
          (-0.20, 0.02, 0.09),
          (0.02, 0.22, 0.07),
        ]) {
          canvas.drawCircle(
            centre.translate(r * spec.$1, r * spec.$2),
            r * spec.$3,
            fill,
          );
        }
      case HexType.ice:
        stroke.color = Palette.iceEdge.withValues(alpha: 0.7);
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.40, centre.dy - r * 0.10)
            ..lineTo(centre.dx + r * 0.24, centre.dy - r * 0.36)
            ..moveTo(centre.dx - r * 0.28, centre.dy + r * 0.12)
            ..lineTo(centre.dx + r * 0.40, centre.dy - r * 0.14)
            ..moveTo(centre.dx - r * 0.10, centre.dy + r * 0.38)
            ..lineTo(centre.dx + r * 0.42, centre.dy + r * 0.12),
          stroke,
        );
      case HexType.eddy:
        stroke.color = Palette.eddyEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx + r * 0.32, centre.dy + r * 0.05)
            ..arcToPoint(
              Offset(centre.dx - r * 0.32, centre.dy + r * 0.10),
              radius: Radius.circular(r * 0.34),
            )
            ..moveTo(centre.dx - r * 0.32, centre.dy + r * 0.10)
            ..lineTo(centre.dx - r * 0.18, centre.dy + r * 0.02)
            ..moveTo(centre.dx - r * 0.32, centre.dy + r * 0.10)
            ..lineTo(centre.dx - r * 0.24, centre.dy + r * 0.28),
          stroke,
        );
      case HexType.magnet:
        stroke.color = Palette.magnetEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.36, centre.dy + r * 0.24)
            ..lineTo(centre.dx, centre.dy)
            ..lineTo(centre.dx + r * 0.36, centre.dy + r * 0.24)
            ..moveTo(centre.dx - r * 0.07, centre.dy + r * 0.24)
            ..lineTo(centre.dx + r * 0.07, centre.dy + r * 0.24),
          stroke,
        );
      case HexType.hardpan:
        stroke.color = Palette.hardpanEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.26, centre.dy - r * 0.12)
            ..lineTo(centre.dx + r * 0.26, centre.dy - r * 0.12)
            ..quadraticBezierTo(
              centre.dx + r * 0.26,
              centre.dy + r * 0.24,
              centre.dx,
              centre.dy + r * 0.36,
            )
            ..quadraticBezierTo(
              centre.dx - r * 0.26,
              centre.dy + r * 0.24,
              centre.dx - r * 0.26,
              centre.dy - r * 0.12,
            ),
          stroke,
        );
      case HexType.overgrowth:
        stroke.color = Palette.overgrowthEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx, centre.dy + r * 0.26)
            ..cubicTo(
              centre.dx - r * 0.46,
              centre.dy,
              centre.dx - r * 0.20,
              centre.dy - r * 0.36,
              centre.dx,
              centre.dy - r * 0.10,
            )
            ..cubicTo(
              centre.dx + r * 0.20,
              centre.dy - r * 0.36,
              centre.dx + r * 0.46,
              centre.dy,
              centre.dx,
              centre.dy + r * 0.26,
            )
            ..moveTo(centre.dx - r * 0.10, centre.dy + r * 0.26)
            ..lineTo(centre.dx - r * 0.16, centre.dy + r * 0.46)
            ..moveTo(centre.dx + r * 0.10, centre.dy + r * 0.26)
            ..lineTo(centre.dx + r * 0.16, centre.dy + r * 0.46),
          stroke,
        );
      case HexType.tremor:
        stroke.color = Palette.tremorEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.30, centre.dy + r * 0.12)
            ..lineTo(centre.dx - r * 0.10, centre.dy + r * 0.12)
            ..lineTo(centre.dx - r * 0.02, centre.dy - r * 0.34)
            ..lineTo(centre.dx + r * 0.10, centre.dy + r * 0.12)
            ..lineTo(centre.dx + r * 0.30, centre.dy + r * 0.12),
          stroke,
        );
      case HexType.gate:
        stroke.color = Palette.gateEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.32, centre.dy - r * 0.32)
            ..lineTo(centre.dx + r * 0.32, centre.dy - r * 0.32)
            ..lineTo(centre.dx + r * 0.32, centre.dy + r * 0.26)
            ..moveTo(centre.dx - r * 0.32, centre.dy - r * 0.32)
            ..lineTo(centre.dx - r * 0.32, centre.dy + r * 0.26)
            ..moveTo(centre.dx, centre.dy - r * 0.05)
            ..lineTo(centre.dx, centre.dy + r * 0.18)
            ..moveTo(centre.dx - r * 0.32, centre.dy + r * 0.26)
            ..lineTo(centre.dx + r * 0.32, centre.dy + r * 0.26),
          stroke,
        );
        stroke.color = Palette.gateEdge;
        canvas.drawCircle(centre.translate(0, -r * 0.13), r * 0.09, stroke);
      case HexType.switchTile:
        fill.color = Palette.switchEdge;
        canvas.drawOval(
          Rect.fromCenter(
            center: centre.translate(0, r * 0.10),
            width: r * 0.34,
            height: r * 0.26,
          ),
          fill,
        );
        for (final toe in [
          centre.translate(-r * 0.18, -r * 0.12),
          centre.translate(0, -r * 0.18),
          centre.translate(r * 0.18, -r * 0.12),
        ]) {
          canvas.drawCircle(toe, r * 0.06, fill);
        }
      case HexType.mirror:
        stroke.color = Palette.mirrorEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx + r * 0.17, centre.dy - r * 0.36)
            ..arcToPoint(
              Offset(centre.dx + r * 0.17, centre.dy + r * 0.36),
              radius: Radius.circular(r * 0.54),
              largeArc: true,
            )
            ..arcToPoint(
              Offset(centre.dx + r * 0.17, centre.dy - r * 0.36),
              radius: Radius.circular(r * 0.36),
              clockwise: false,
            ),
          stroke,
        );
      case HexType.thorn:
        fill.color = Palette.thornEdge.withValues(alpha: 0.85);
        canvas.drawPath(thornMarkPath(centre, r), fill);
      case HexType.alarm:
        stroke.color = Palette.alarmEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx, centre.dy - r * 0.36)
            ..lineTo(centre.dx, centre.dy - r * 0.24)
            ..moveTo(centre.dx - r * 0.26, centre.dy - r * 0.06)
            ..arcToPoint(
              Offset(centre.dx + r * 0.26, centre.dy - r * 0.06),
              radius: Radius.circular(r * 0.27),
            )
            ..moveTo(centre.dx - r * 0.32, centre.dy - r * 0.06)
            ..lineTo(centre.dx + r * 0.32, centre.dy - r * 0.06)
            ..moveTo(centre.dx, centre.dy + r * 0.06)
            ..lineTo(centre.dx, centre.dy + r * 0.16),
          stroke,
        );
        fill.color = Palette.alarmEdge;
        canvas.drawCircle(centre.translate(0, r * 0.24), r * 0.06, fill);
      case HexType.thatch:
        stroke.color = Palette.thatchEdge;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r * 0.32, centre.dy - r * 0.10)
            ..lineTo(centre.dx + r * 0.32, centre.dy + r * 0.10)
            ..moveTo(centre.dx + r * 0.32, centre.dy - r * 0.10)
            ..lineTo(centre.dx - r * 0.32, centre.dy + r * 0.10),
          stroke,
        );
      case HexType.scaffold:
        stroke.color = Palette.scaffoldEdge;
        for (var i = -1; i <= 1; i++) {
          canvas.drawCircle(
            centre.translate(r * 0.28 * i, 0),
            r * 0.06,
            stroke,
          );
        }
        canvas.drawLine(
          centre.translate(-r * 0.28, r * 0.16),
          centre.translate(r * 0.28, r * 0.16),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_EntryPainter old) => old.entry != entry;
}
