import 'dart:math' as math;

import 'package:flutter/material.dart';

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
class LevelMap extends StatefulWidget {
  const LevelMap({
    required this.progress,
    required this.onPlay,
    required this.onPets,
    required this.onSettings,
    super.key,
  });

  final Progress progress;
  final void Function(int level) onPlay;
  final VoidCallback onPets;
  final VoidCallback onSettings;

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
              onPets: widget.onPets,
              onSettings: widget.onSettings,
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
                      layout.toPixel(
                        MapLayout.coordFor(MapLayout.tiles),
                      ).dy +
                      hex * 1.6;

                  _scrollToFrontierOnce(layout, frontier, constraints.maxHeight);

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
                          if (level != null && progress.isUnlocked(level)) {
                            widget.onPlay(level);
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
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            _PlayBar(
              level: frontier,
              bestDepth: progress.endlessBest > Campaign.length
                  ? progress.endlessBest - Campaign.length
                  : 0,
              onPlay: () => widget.onPlay(frontier),
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
  });

  final HexLayout layout;
  final Progress progress;
  final int frontier;
  final double phase;

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
    final unlocked = progress.isUnlocked(level);
    final record = progress.recordFor(level);
    final isEndless = level > Campaign.length;
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

    _fill.color = unlocked
        ? colour.withValues(alpha: record.played ? 0.24 : 0.13)
        : Palette.lockedTile;
    canvas.drawPath(hex, _fill);

    _stroke
      ..color = unlocked
          ? colour.withValues(alpha: isFrontier ? 0.95 : 0.6)
          : Palette.lockedEdge
      ..strokeWidth = isFrontier ? 2.6 : 1.5
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(hex, _stroke);

    if (!unlocked) {
      _paintLock(canvas, centre);
      return;
    }

    _paintLabel(
      canvas,
      centre.translate(0, record.played ? -layout.size * 0.16 : 0),
      isEndless ? '∞' : '$level',
      colour: isEndless ? colour : Colors.white.withValues(alpha: 0.92),
      size: isEndless ? layout.size * 0.85 : layout.size * 0.58,
      weight: FontWeight.w700,
    );

    if (record.played) {
      _paintStars(canvas, centre, record.stars, colour);
    }
  }

  void _paintLock(Canvas canvas, Offset centre) {
    final s = layout.size * 0.22;
    _stroke
      ..color = Palette.lockedEdge
      ..strokeWidth = 2;
    // A shackle over a body: small, and deliberately unemphatic.
    canvas.drawArc(
      Rect.fromCenter(center: centre.translate(0, -s * 0.75), width: s * 1.1, height: s * 1.1),
      math.pi,
      math.pi,
      false,
      _stroke,
    );
    _fill.color = Palette.lockedEdge;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre.translate(0, s * 0.25), width: s * 1.6, height: s * 1.2),
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
      old.layout.size != layout.size;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.stars,
    required this.maxStars,
    required this.onPets,
    required this.onSettings,
  });

  final int stars;
  final int maxStars;
  final VoidCallback onPets;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
      child: Row(
        children: [
          const Text(
            'HEXCAPE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          Text(
            '$stars / $maxStars',
            style: TextStyle(
              color: Palette.treat,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.circle, size: 10, color: Palette.treat),
          IconButton(
            onPressed: onPets,
            icon: const Icon(Icons.pets),
            color: Palette.dogBody,
            tooltip: 'Pets',
          ),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.tune),
            color: Colors.white70,
            tooltip: 'Settings',
          ),
        ],
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
          child: Text(
            endless
                ? (bestDepth > 0 ? 'ENDLESS  ·  BEST D$bestDepth' : 'ENDLESS')
                : '${band.label.toUpperCase()}  ·  LEVEL $level',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}
