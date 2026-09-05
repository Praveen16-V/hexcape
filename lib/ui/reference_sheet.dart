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

const allReferenceEntries = <ReferenceEntry>[
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
        'as much a choice as what you open.',
    hex: HexType.anchor,
    unlocksAt: 3,
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
    name: 'Regrowth',
    blurb:
        'Cleared tiles grow back from the outside in. You get a ghost, then '
        'two pulses, then it snaps shut. She can always escape until the snap.',
    icon: Icons.grid_on,
    unlocksAt: 2,
  ),
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
    name: 'Scent',
    blurb:
        'Lights the cheapest way through for five seconds. The only one '
        'that buys knowledge instead of resources.',
    pickup: PickupKind.scent,
    unlocksAt: Campaign.foundationEnd + 1,
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
    name: 'Dig',
    blurb:
        'Held until you spend it. Tap DIG above to arm it, then tap a riveted '
        'tile to break the only wall that can be removed.',
    pickup: PickupKind.dig,
    unlocksAt: Campaign.pressureEnd + 1,
  ),
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
          SizedBox(
            width: 46,
            height: 46,
            child: entry.icon != null
                ? Icon(entry.icon, color: Palette.dogBody, size: 24)
                : CustomPaint(painter: _EntryPainter(entry)),
          ),
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
      fill.color = _topOf(hex);
      canvas.drawPath(path, fill);
      stroke.color = _edgeOf(hex);
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
    }
  }

  static Color _topOf(HexType type) => switch (type) {
    HexType.plain => Palette.plainTop,
    HexType.heavy => Palette.heavyTop,
    HexType.anchor => Palette.anchorTop,
    HexType.spring => Palette.springTop,
  };

  static Color _edgeOf(HexType type) => switch (type) {
    HexType.plain => Palette.plainEdge,
    HexType.heavy => Palette.heavyEdge,
    HexType.anchor => Palette.anchorEdge,
    HexType.spring => Palette.springEdge,
  };

  @override
  bool shouldRepaint(_EntryPainter old) => old.entry != entry;
}
