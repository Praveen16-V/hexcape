import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/difficulty.dart';
import '../game/entitlements.dart';
import '../game/haptics.dart';
import '../game/level_rules.dart';
import '../game/progress.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_layout.dart';
import '../theme/palette.dart';

/// Where each level sits on the map.
///
/// The campaign is a *place*, not a list. The levels are hexes on a hex board,
/// laid out as a trail that doubles back on itself, so the map is made of the
/// same material as the game — which is the whole point of it being diegetic
/// rather than a scrolling menu of buttons.
///
/// The trail runs left to right, then right to left on the next row. A snake
/// rather than a meander: a wandering path looks prettier in a mock-up and is
/// worse to use, because a player looking for level 43 has to search for it
/// instead of counting rows.
class MapLayout {
  const MapLayout._();

  /// Levels per row. Five is what fits a portrait phone at a size where the
  /// number, the stars and the lock are all still readable.
  static const perRow = 5;

  static int get rows => (Campaign.length / perRow).ceil();

  /// Total tiles, campaign plus the single endless gateway at the end.
  static int get tiles => Campaign.length + 1;

  static HexCoord coordFor(int level) {
    final index = level - 1;
    final row = index ~/ perRow;
    final within = index % perRow;
    // Odd rows run backwards, so the trail never jumps across the board.
    final column = row.isEven ? within : perRow - 1 - within;
    // Odd-r offset to axial, which keeps the rows visually rectangular
    // instead of shearing off to one side as the board grows.
    return HexCoord(column - ((row - (row & 1)) ~/ 2), row);
  }

  /// The level under a point, or null if the tap missed every tile.
  static int? levelAt(Offset point, HexLayout layout) {
    final coord = layout.toHex(point);
    for (var level = 1; level <= tiles; level++) {
      if (coordFor(level) == coord) {
        return level;
      }
    }
    return null;
  }
}

/// The campaign map (§12.1).
///
/// Reached from the home screen rather than being the app's front door itself
/// — a hundred levels to choose from is a chooser, not a title screen. Play,
/// the daily board and the unlock offer all live there now; this screen is
/// only for picking a level.
class LevelMap extends StatefulWidget {
  const LevelMap({
    required this.progress,
    required this.onSelect,
    required this.onBack,
    required this.showToken,
    super.key,
  });

  final Progress progress;

  /// A tile was chosen. Locked levels are passed through too — the sheet is
  /// where a locked level explains itself, and silence taught nobody anything.
  final void Function(int level) onSelect;

  /// Returns to the home screen.
  final VoidCallback onBack;

  /// Bumped by the parent every time this screen is navigated to. The map
  /// stays mounted for the app's life (§ below), so without this a scroll
  /// position set on first launch would never move again — clearing a run and
  /// coming back here would leave the view wherever it happened to be, not on
  /// the new frontier.
  final int showToken;

  @override
  State<LevelMap> createState() => _LevelMapState();
}

class _LevelMapState extends State<LevelMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  final ScrollController _scroll = ScrollController();

  /// The [LevelMap.showToken] this screen last centred its scroll for. Distinct
  /// from the token's own initial value so the very first build still scrolls.
  int? _scrolledToken;

  @override
  void dispose() {
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final reducedMotion =
        progress.reducedMotion || MediaQuery.disableAnimationsOf(context);
    if (reducedMotion) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
    final frontier = math.min(progress.unlocked, MapLayout.tiles);

    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: Column(
          children: [
            _CampaignBar(
              stars: progress.totalStars,
              maxStars: Campaign.length * 3,
              onBack: widget.onBack,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // The hex size comes from the width, so the trail always
                  // spans the screen and the board never needs to scroll
                  // sideways — a map you can lose sideways is a map you get
                  // lost on.
                  const labelGutter = 30.0;
                  final hex =
                      (constraints.maxWidth - labelGutter) /
                      (MapLayout.perRow + 1.2);
                  final layout = HexLayout(
                    size: hex / math.sqrt(3),
                    origin: Offset(labelGutter + hex * 0.85, hex * 0.85),
                  );
                  final height =
                      layout.toPixel(MapLayout.coordFor(MapLayout.tiles)).dy +
                      hex * 1.6;

                  _maybeScrollToFrontier(
                    layout,
                    frontier,
                    constraints.maxHeight,
                  );

                  return SingleChildScrollView(
                    controller: _scroll,
                    child: SizedBox(
                      height: height,
                      width: constraints.maxWidth,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final level = MapLayout.levelAt(
                            details.localPosition,
                            layout,
                          );
                          if (level != null) {
                            Haptics.selection();
                            widget.onSelect(level);
                          }
                        },
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) => CustomPaint(
                            painter: _MapPainter(
                              layout: layout,
                              progress: progress,
                              frontier: frontier,
                              phase: reducedMotion ? 0.5 : _pulse.value,
                              owned: progress.ownsFullGame,
                              trialUsed: progress.trialUsed,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens on where the player actually is, not at level one, and re-centres
  /// every time [LevelMap.showToken] changes — this screen stays mounted for
  /// the app's life, so without that it would only ever do this once.
  ///
  /// Someone forty levels in should not have to scroll past forty tiles they
  /// have already finished to reach the one they were about to play.
  void _maybeScrollToFrontier(
    HexLayout layout,
    int frontier,
    double viewportHeight,
  ) {
    if (_scrolledToken == widget.showToken) {
      return;
    }
    _scrolledToken = widget.showToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) {
        return;
      }
      final y = layout.toPixel(MapLayout.coordFor(frontier)).dy;
      _scroll.jumpTo(
        (y - viewportHeight / 2).clamp(0.0, _scroll.position.maxScrollExtent),
      );
    });
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.layout,
    required this.progress,
    required this.frontier,
    required this.phase,
    required this.owned,
    required this.trialUsed,
  });

  final HexLayout layout;
  final Progress progress;
  final int frontier;
  final double phase;

  /// Passed in rather than read off [progress] so [shouldRepaint] can see it
  /// change — buying the game has to repaint forty tiles.
  final bool owned;

  /// Passed in for the same reason as [owned]: spending the trial changes how
  /// one tile draws, and [shouldRepaint] cannot see it on [progress].
  final bool trialUsed;

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    _paintTrail(canvas);
    for (var level = 1; level <= MapLayout.tiles; level++) {
      _paintTile(canvas, level);
    }
    _paintBandLabels(canvas);
  }

  /// Names the six bands along the trail's left margin, so the climb ahead
  /// reads as stretches with characters of their own rather than one column
  /// of identical grey padlocks. Endless is left unlabelled here — its single
  /// tile already carries its own glyph.
  void _paintBandLabels(Canvas canvas) {
    const bands = CampaignBand.values;
    var labelBottom = 0.0;
    for (var i = 0; i < bands.length - 1; i++) {
      final band = bands[i];
      final first = Campaign.firstOf(band);
      if (first > MapLayout.tiles) {
        break;
      }
      final last = math.min(
        Campaign.firstOf(bands[i + 1]) - 1,
        MapLayout.tiles,
      );
      final yStart = layout.toPixel(MapLayout.coordFor(first)).dy;
      final yEnd = layout.toPixel(MapLayout.coordFor(last)).dy;
      labelBottom = _paintVerticalLabel(
        canvas,
        band.label.toUpperCase(),
        (yStart + yEnd) / 2,
        Palette.forBand(band),
        labelBottom,
      );
    }
  }

  double _paintVerticalLabel(
    Canvas canvas,
    String text,
    double y,
    Color colour,
    double previousBottom,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: colour.withValues(alpha: 0.90),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    final centreY = math.max(y, previousBottom + 12 + painter.width / 2);
    _stroke
      ..color = colour
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(3, centreY - painter.width / 2),
      Offset(3, centreY + painter.width / 2),
      _stroke,
    );
    canvas.translate(15, centreY);
    canvas.rotate(-math.pi / 2);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
    return centreY + painter.width / 2;
  }

  /// The line joining one level to the next. Drawn under the tiles, so it
  /// reads as ground they sit on rather than wire between them.
  void _paintTrail(Canvas canvas) {
    final path = Path();
    for (var level = 1; level <= MapLayout.tiles; level++) {
      final centre = layout.toPixel(MapLayout.coordFor(level));
      if (level == 1) {
        path.moveTo(centre.dx, centre.dy);
      } else {
        path.lineTo(centre.dx, centre.dy);
      }
    }
    _stroke
      ..color = Palette.lockedEdge
      ..strokeWidth = layout.size * 0.30
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, _stroke);

    // The stretch already walked, lit in its own band colours.
    for (var level = 2; level <= math.min(frontier, MapLayout.tiles); level++) {
      final a = layout.toPixel(MapLayout.coordFor(level - 1));
      final b = layout.toPixel(MapLayout.coordFor(level));
      _stroke
        ..color = Palette.forBand(Campaign.bandOf(level)).withValues(alpha: 0.5)
        ..strokeWidth = layout.size * 0.30;
      canvas.drawLine(a, b, _stroke);
    }
  }

  void _paintTile(Canvas canvas, int level) {
    final centre = layout.toPixel(MapLayout.coordFor(level));
    final access = Entitlements.accessTo(
      level,
      unlocked: progress.unlocked,
      owned: progress.ownsFullGame,
      trialUsed: progress.trialUsed,
    );
    final trial = access == LevelAccess.trial;
    // A trial tile is drawn as playable, because it is. Drawing a padlock on
    // the one level we are inviting them into would be the map contradicting
    // the offer.
    final unlocked = access == LevelAccess.open || trial;
    final forSale = access == LevelAccess.needsPurchase;
    final record = progress.recordFor(level);
    final isEndless = level > Campaign.length;
    final campaignPlayed = !isEndless && record.played;
    final band = Campaign.bandOf(level);
    final colour = Palette.forBand(band);
    final isFrontier = level == frontier;

    final hex = HexLayout.pathFromCorners(
      HexLayout.cornersAt(centre, layout.size * 0.92),
    );

    if (isFrontier) {
      // Where the player is. A slow breath rather than a flash: the map is a
      // place to sit and choose, not something shouting for a tap.
      final swell = 0.5 + 0.5 * math.sin(phase * math.pi * 2);
      _fill
        ..color = colour.withValues(alpha: 0.16 + 0.12 * swell)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, layout.size * 0.55);
      canvas.drawCircle(centre, layout.size * (1.15 + 0.12 * swell), _fill);
      _fill.maskFilter = null;
    }

    // A tile you have not bought keeps its band colour. The grey plate says
    // "not yet"; this has to say "more", and a padlock over forty levels of
    // game reads as a wall rather than an offer.
    //
    // A tile you simply haven't reached yet gets the same grey plate, but
    // tinted with a whisper of its own band's colour rather than flat locked
    // grey — the unclimbed trail should hint at the character ahead, not read
    // as one undifferentiated wall.
    _fill.color = unlocked
        ? colour.withValues(alpha: campaignPlayed ? 0.24 : 0.13)
        : forSale
        ? colour.withValues(alpha: 0.07)
        : Color.lerp(Palette.lockedTile, colour, 0.14)!;
    canvas.drawPath(hex, _fill);

    _stroke
      ..color = unlocked
          ? colour.withValues(alpha: isFrontier ? 0.95 : 0.6)
          : forSale
          ? colour.withValues(alpha: 0.34)
          : Color.lerp(Palette.lockedEdge, colour, 0.20)!
      ..strokeWidth = isFrontier ? 2.6 : 1.5
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(hex, _stroke);

    if (!unlocked) {
      _paintLabel(
        canvas,
        centre.translate(0, -layout.size * 0.24),
        isEndless ? '∞' : '$level',
        colour: Palette.hudText,
        size: layout.size * 0.48,
        weight: FontWeight.w600,
      );
      _paintLock(
        canvas,
        centre.translate(0, layout.size * 0.38),
        Color.lerp(colour, Palette.hudText, 0.55)!,
        scale: 0.65,
      );
      return;
    }
    if (isFrontier) {
      _fill.color = Palette.hudText;
      final tip = centre.translate(0, -layout.size * 0.62);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(tip.dx - layout.size * 0.13, tip.dy - layout.size * 0.17)
          ..lineTo(tip.dx + layout.size * 0.13, tip.dy - layout.size * 0.17)
          ..close(),
        _fill,
      );
    }

    _paintLabel(
      canvas,
      centre.translate(0, campaignPlayed ? -layout.size * 0.16 : 0),
      isEndless ? '∞' : '$level',
      colour: isEndless ? colour : Colors.white.withValues(alpha: 0.92),
      size: isEndless ? layout.size * 0.85 : layout.size * 0.58,
      weight: FontWeight.w700,
    );

    if (campaignPlayed) {
      _paintStars(canvas, centre, record.stars, colour);
      // One letter beside the stars where they were not earned on Normal. The
      // detail sheet is where it says the word; here there is room for a mark
      // and nothing more, and a tile that stayed silent about it would make the
      // star row quietly mean two different things.
      if (record.difficulty != Difficulty.normal) {
        _paintLabel(
          canvas,
          // Clear of the third star: the row ends at 0.26 plus its own radius,
          // and a letter touching the last ring reads as part of it. With two
          // modes the mark is univocal: absence means Normal, ‘H’ means Hard.
          Offset(centre.dx + layout.size * 0.5, centre.dy + layout.size * 0.44),
          'H',
          colour: colour.withValues(alpha: 0.75),
          size: layout.size * 0.24,
          weight: FontWeight.w800,
        );
      }
    }
  }

  void _paintLock(
    Canvas canvas,
    Offset centre,
    Color colour, {
    double scale = 1,
  }) {
    final s = layout.size * 0.22 * scale;
    _stroke
      ..color = colour
      ..strokeWidth = 2;
    // A shackle over a body: small, and deliberately unemphatic.
    canvas.drawArc(
      Rect.fromCenter(
        center: centre.translate(0, -s * 0.75),
        width: s * 1.1,
        height: s * 1.1,
      ),
      math.pi,
      math.pi,
      false,
      _stroke,
    );
    _fill.color = colour;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: centre.translate(0, s * 0.25),
          width: s * 1.6,
          height: s * 1.2,
        ),
        Radius.circular(s * 0.25),
      ),
      _fill,
    );
  }

  void _paintStars(Canvas canvas, Offset centre, int stars, Color colour) {
    final r = layout.size * 0.10;
    final gap = r * 2.6;
    final y = centre.dy + layout.size * 0.44;
    for (var i = 0; i < 3; i++) {
      final x = centre.dx + (i - 1) * gap;
      if (i < stars) {
        _fill.color = colour;
        canvas.drawCircle(Offset(x, y), r, _fill);
      } else {
        _stroke
          ..color = colour.withValues(alpha: 0.35)
          ..strokeWidth = 1.2;
        canvas.drawCircle(Offset(x, y), r, _stroke);
      }
    }
  }

  void _paintLabel(
    Canvas canvas,
    Offset centre,
    String text, {
    required Color colour,
    required double size,
    FontWeight weight = FontWeight.w600,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: colour,
          fontSize: size,
          fontFamily: 'Roboto',
          fontWeight: weight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      centre - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.phase != phase ||
      old.frontier != frontier ||
      old.owned != owned ||
      old.trialUsed != trialUsed ||
      old.layout.size != layout.size;
}

/// The slim bar above the trail: a way back to the home screen, and the same
/// mastery count that used to share space with a wordmark this screen no
/// longer needs — the home screen carries that now.
class _CampaignBar extends StatelessWidget {
  const _CampaignBar({
    required this.stars,
    required this.maxStars,
    required this.onBack,
  });

  final int stars;
  final int maxStars;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 20, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 21),
            color: Colors.white70,
            tooltip: 'Home',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'CAMPAIGN',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Campaign mastery: $stars of $maxStars stars',
            child: Row(
              children: [
                Icon(Icons.circle, size: 9, color: Palette.treat),
                const SizedBox(width: 5),
                Text(
                  '$stars/$maxStars',
                  style: TextStyle(
                    color: Palette.treat,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
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
