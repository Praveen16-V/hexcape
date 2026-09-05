import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/daily.dart';
import '../game/entitlements.dart';
import '../game/level_rules.dart';
import '../game/progress.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_layout.dart';
import '../l10n/strings.dart';
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
class LevelMap extends StatefulWidget {
  const LevelMap({
    required this.progress,
    required this.onSelect,
    required this.onPets,
    required this.onSettings,
    required this.onReference,
    required this.onUnlock,
    required this.onDaily,
    super.key,
  });

  final Progress progress;

  /// A tile was chosen. Locked levels are passed through too — the sheet is
  /// where a locked level explains itself, and silence taught nobody anything.
  final void Function(int level) onSelect;
  final VoidCallback onPets;
  final VoidCallback onSettings;
  final VoidCallback onReference;

  /// Opens the offer. Shown on the map only while the game is unbought.
  final VoidCallback onUnlock;

  /// Starts today's board.
  final VoidCallback onDaily;

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
  bool _scrolledToFrontier = false;

  @override
  void dispose() {
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final frontier = math.min(progress.unlocked, MapLayout.tiles);

    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              stars: progress.totalStars,
              maxStars: Campaign.length * 3,
              mastered: progress.masteredLevels,
              onPets: widget.onPets,
              onSettings: widget.onSettings,
              onReference: widget.onReference,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // The hex size comes from the width, so the trail always
                  // spans the screen and the board never needs to scroll
                  // sideways — a map you can lose sideways is a map you get
                  // lost on.
                  final hex = constraints.maxWidth / (MapLayout.perRow + 1.2);
                  final layout = HexLayout(
                    size: hex / math.sqrt(3),
                    origin: Offset(hex * 0.85, hex * 0.85),
                  );
                  final height =
                      layout.toPixel(MapLayout.coordFor(MapLayout.tiles)).dy +
                      hex * 1.6;

                  _scrollToFrontierOnce(
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
                              phase: _pulse.value,
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
            _DailyBar(
              daily: Daily.forDate(DateTime.now()),
              cleared: progress.hasClearedDaily(Daily.forDate(DateTime.now())),
              streak: progress.dailyStreakAsOf(DateTime.now()),
              onPlay: widget.onDaily,
            ),
            // Always reachable, never loud.
            //
            // Dismissing the paywall used to leave exactly one way back to it:
            // tapping a locked tile. Someone who has decided to think about it
            // should not have to remember which tile that was, and a game with
            // one thing to sell can afford to say so once, quietly, in a strip
            // the width of the screen.
            if (!progress.ownsFullGame)
              _UnlockStrip(
                paidLevels: Campaign.length - Entitlements.freeThrough,
                onUnlock: widget.onUnlock,
              ),
            _PlayBar(
              level: frontier,
              bestDepth: progress.endlessBest > Campaign.length
                  ? progress.endlessBest - Campaign.length
                  : 0,
              onPlay: () => widget.onSelect(frontier),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens on where the player actually is, not at level one.
  ///
  /// Someone forty levels in should not have to scroll past forty tiles they
  /// have already finished to reach the one they were about to play.
  void _scrollToFrontierOnce(
    HexLayout layout,
    int frontier,
    double viewportHeight,
  ) {
    if (_scrolledToFrontier) {
      return;
    }
    _scrolledToFrontier = true;
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
    _fill.color = unlocked
        ? colour.withValues(alpha: campaignPlayed ? 0.24 : 0.13)
        : forSale
        ? colour.withValues(alpha: 0.07)
        : Palette.lockedTile;
    canvas.drawPath(hex, _fill);

    _stroke
      ..color = unlocked
          ? colour.withValues(alpha: isFrontier ? 0.95 : 0.6)
          : forSale
          ? colour.withValues(alpha: 0.34)
          : Palette.lockedEdge
      ..strokeWidth = isFrontier ? 2.6 : 1.5
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(hex, _stroke);

    if (!unlocked) {
      _paintLock(canvas, centre, forSale ? colour : Palette.lockedEdge);
      return;
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
    }
  }

  void _paintLock(Canvas canvas, Offset centre, Color colour) {
    final s = layout.size * 0.22;
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

class _Header extends StatelessWidget {
  const _Header({
    required this.stars,
    required this.maxStars,
    required this.mastered,
    required this.onPets,
    required this.onSettings,
    required this.onReference,
  });

  final int stars;
  final int maxStars;
  final int mastered;
  final VoidCallback onPets;
  final VoidCallback onSettings;
  final VoidCallback onReference;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 6, 4),
      child: Row(
        children: [
          // Shrinks rather than collides. Three icon buttons plus a star count
          // left the title no room, and the fixed 22pt wordmark ran straight
          // into the number beside it.
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'HEXCAPE',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            label:
                'Campaign mastery: $stars of $maxStars stars, '
                '$mastered levels mastered',
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
          const Spacer(),
          _HeaderButton(
            onPressed: onPets,
            icon: Icons.pets,
            colour: Palette.dogBody,
            tooltip: 'Pets',
          ),
          _HeaderButton(
            onPressed: onReference,
            icon: Icons.help_outline,
            colour: Colors.white70,
            tooltip: 'How it works',
          ),
          _HeaderButton(
            onPressed: onSettings,
            icon: Icons.tune,
            colour: Colors.white70,
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Compact enough that three of them fit beside a wordmark.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.onPressed,
    required this.icon,
    required this.colour,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final Color colour;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      color: colour,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    );
  }
}

/// Today's board.
///
/// Sits above the campaign's own Play button rather than in a menu, because a
/// daily nobody sees is a daily nobody plays — and the streak is the only
/// number in the game that decays, so it has to be in front of the player
/// every time they open the app.
class _DailyBar extends StatelessWidget {
  const _DailyBar({
    required this.daily,
    required this.cleared,
    required this.streak,
    required this.onPlay,
  });

  final DailyChallenge daily;
  final bool cleared;
  final int streak;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colour = Palette.forBand(daily.band);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPlay,
          style: OutlinedButton.styleFrom(
            foregroundColor: cleared ? Palette.hudDim : colour,
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(
              color: (cleared ? Palette.lockedEdge : colour).withValues(
                alpha: cleared ? 1 : 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                cleared ? Icons.check_circle_outline : Icons.today_outlined,
                size: 17,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    cleared
                        ? '${Strings.dailyDone.toUpperCase()}  ·  '
                              '${daily.band.label.toUpperCase()}'
                        : '${Strings.dailyTitle.toUpperCase()}  ·  '
                              '${daily.band.label.toUpperCase()}',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              if (streak > 0) ...[
                const SizedBox(width: 8),
                Semantics(
                  label: '$streak day streak',
                  child: Text(
                    '$streak🔥',
                    style: TextStyle(
                      color: Palette.treat,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The standing route back to the offer.
///
/// A strip rather than a button: it sits under the trail it is talking about,
/// says how much more of it there is, and does not compete with Play. No badge,
/// no price, no countdown — the sheet it opens is where the numbers live.
class _UnlockStrip extends StatelessWidget {
  const _UnlockStrip({required this.paidLevels, required this.onUnlock});

  final int paidLevels;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onUnlock,
          style: TextButton.styleFrom(
            foregroundColor: Palette.bandPressure,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
              side: BorderSide(
                color: Palette.bandPressure.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$paidLevels MORE LEVELS  ·  PRESSURE, MASTERY, ENDLESS',
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayBar extends StatelessWidget {
  const _PlayBar({
    required this.level,
    required this.bestDepth,
    required this.onPlay,
  });

  final int level;

  /// Deepest endless run so far. Shown on the button rather than tucked into a
  /// stats screen: it is the only score endless has, and a score nobody sees
  /// is not one anybody chases.
  final int bestDepth;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final endless = level > Campaign.length;
    final band = Campaign.bandOf(level);
    final identity = Campaign.identityFor(level);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: onPlay,
          style: FilledButton.styleFrom(
            backgroundColor: Palette.forBand(band),
            foregroundColor: Palette.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              endless
                  ? (bestDepth > 0 ? 'ENDLESS  ·  BEST D$bestDepth' : 'ENDLESS')
                  : 'LEVEL $level  ·  ${identity.title.toUpperCase()}',
              maxLines: 1,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
