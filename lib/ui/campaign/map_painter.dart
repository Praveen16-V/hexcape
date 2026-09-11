import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../game/difficulty.dart';
import '../../game/entitlements.dart';
import '../../game/level_rules.dart';
import '../../game/progress.dart';
import '../../gen/silhouette.dart';
import '../../hex/hex_layout.dart';
import '../../l10n/strings.dart';
import '../../theme/palette.dart';
import 'map_layout.dart';
import 'silhouette_glyphs.dart';

/// What the map knows about one level, packed for cheap comparison.
///
/// Immutable and value-compared, because this is what decides whether the
/// chapter repaints. The page this replaced compared the animation phase, the
/// frontier and the hex size — but never the player's record — so a star earned
/// on a level already cleared did not redraw the tile that showed it, and with
/// reduced motion on (which pins the phase) it never redrew at all.
@immutable
class MapTile {
  const MapTile({
    required this.level,
    required this.stars,
    required this.hard,
    required this.access,
    required this.shape,
  });

  final int level;
  final int stars;
  final bool hard;
  final LevelAccess access;
  final FieldShape shape;

  bool get played => stars > 0;
  bool get finale => level % 10 == 0 && level <= Campaign.length;
  bool get endless => level > Campaign.length;

  @override
  bool operator ==(Object other) =>
      other is MapTile &&
      other.level == level &&
      other.stars == stars &&
      other.hard == hard &&
      other.access == access &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(level, stars, hard, access, shape);
}

/// One chapter's tiles, gathered once per build.
@immutable
class ChapterModel {
  const ChapterModel({
    required this.band,
    required this.tiles,
    required this.frontier,
  });

  final CampaignBand band;
  final List<MapTile> tiles;
  final int frontier;

  static ChapterModel of(
    CampaignBand band,
    Progress progress, {
    required int frontier,
  }) {
    final range = MapLayout.levelsOf(band);
    return ChapterModel(
      band: band,
      frontier: frontier,
      tiles: [
        for (var level = range.first; level <= range.last; level++)
          _tileFor(level, progress),
      ],
    );
  }

  static MapTile _tileFor(int level, Progress progress) {
    final record = progress.recordFor(level);
    return MapTile(
      level: level,
      stars: record.stars,
      hard: record.difficulty == Difficulty.hard,
      access: Entitlements.accessTo(
        level,
        unlocked: progress.unlocked,
        owned: progress.ownsFullGame,
        trialUsed: progress.trialUsed,
        unlockAll: progress.unlockAllLevels,
      ),
      shape: shapeFor(
        level,
        Campaign.seedFor(level),
        tutorialBand: Campaign.tutorialBand,
      ),
    );
  }
}

/// Paints one chapter of the campaign map.
///
/// The map is made of the same material as the board, and that is the whole
/// idea: **behind you is open ground you carved, ahead of you is rock.** A
/// level you have beaten is a pit, exactly as a cleared cell is during a run; a
/// level you have not reached is a solid tile in its chapter's colour; and a
/// level behind the paywall is riveted, which is the game's own way of saying a
/// tap cannot touch this. None of that needed inventing — it is the vocabulary
/// the player already learned in the first three levels.
///
/// Drawing follows `field_component.dart`: accumulate one [Path] per material,
/// then draw each once, in the order pits → skirts → tops → edges → marks. A
/// chapter is twenty tiles and about fourteen draw calls. The page this
/// replaced allocated a fresh `Path` and laid out a fresh `TextPainter` per
/// tile, per frame, for all hundred and one tiles, forever — to animate a
/// single blurred halo.
class ChapterPainter extends CustomPainter {
  ChapterPainter({
    required this.model,
    required this.layout,
    required this.labelStyle,
    required this.labelScale,
    required this.onSelect,
    required this.showGlyphs,
  });

  final ChapterModel model;
  final HexLayout layout;
  final TextStyle labelStyle;
  final double labelScale;
  final ValueChanged<int> onSelect;

  /// Suppressed on narrow screens: a silhouette under about 26 px is mush, and
  /// mush is worse than an honest empty tile.
  final bool showGlyphs;

  double get _hex => layout.size;

  final Map<String, TextPainter> _labels = {};

  @override
  void paint(Canvas canvas, Size size) {
    final band = Palette.forBand(model.band);
    final depth = Offset(0, _hex * 0.26);
    // Two hex paths: one inset a hair for solid tiles so their edges read
    // separately, and one at full size for pits, so a run of cleared levels
    // merges into a single carved corridor with no hairline seams in it.
    final tile = HexLayout.pathFromCorners(
      HexLayout.cornersAt(Offset.zero, _hex * 0.94),
    );
    final full = HexLayout.pathFromCorners(
      HexLayout.cornersAt(Offset.zero, _hex),
    );
    final rivetHex = HexLayout.pathFromCorners(
      HexLayout.cornersAt(Offset.zero, _hex * 0.3),
    );
    final ringHex = HexLayout.pathFromCorners(
      HexLayout.cornersAt(Offset.zero, _hex * 0.52),
    );

    final pits = Path();
    final pitRims = Path();
    final openTops = Path();
    final openSkirts = Path();
    final openEdges = Path();
    final lockedTops = Path();
    final lockedSkirts = Path();
    final lockedEdges = Path();
    final rivetTops = Path();
    final rivetSkirts = Path();
    final rivetEdges = Path();
    final rivets = Path();
    final rivetDots = Path();
    final finaleRings = Path();
    final frontierRing = Path();
    final trialRing = Path();
    final glyphsOnPit = Path();
    final glyphsOnRock = Path();

    for (final t in model.tiles) {
      final centre = layout.toPixel(MapLayout.coordFor(t.level));

      if (t.played) {
        pits.addPath(full, centre);
        pitRims.addPath(tile, centre);
      } else if (t.access == LevelAccess.needsPurchase) {
        rivetTops.addPath(tile, centre);
        rivetSkirts.addPath(tile, centre + depth);
        rivetEdges.addPath(tile, centre);
        rivets.addPath(rivetHex, centre);
        rivetDots.addOval(Rect.fromCircle(center: centre, radius: _hex * 0.09));
      } else if (t.access == LevelAccess.needsProgress) {
        lockedTops.addPath(tile, centre);
        lockedSkirts.addPath(tile, centre + depth);
        lockedEdges.addPath(tile, centre);
      } else {
        openTops.addPath(tile, centre);
        openSkirts.addPath(tile, centre + depth);
        openEdges.addPath(tile, centre);
      }

      if (t.finale) {
        finaleRings.addPath(ringHex, centre);
      }
      if (t.level == model.frontier) {
        frontierRing.addPath(tile, centre);
      }
      if (t.access == LevelAccess.trial) {
        trialRing.addPath(tile, centre);
      }
      // The motif is skipped for open ground, which is the default cut and by
      // far the most common. Drawing it would put the same round blob on two
      // tiles in five and drown the shapes that actually say something — the
      // bone, the key, the paw. An empty tile reads as ordinary ground, which
      // is exactly what it is.
      if (showGlyphs && !t.endless && t.shape != FieldShape.ellipse) {
        final glyph = SilhouetteGlyphs.unitGlyphFor(
          t.shape,
        ).transform(SilhouetteGlyphs.placement(centre, _hex * 0.82));
        (t.played ? glyphsOnPit : glyphsOnRock).addPath(glyph, Offset.zero);
      }
    }

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()..style = PaintingStyle.stroke;

    // Skirts first, so each row's depth face is covered by the row in front.
    fill.color = Palette.sunkFace(_rockTop(band));
    canvas.drawPath(lockedSkirts, fill);
    fill.color = Palette.sunkFace(_openTop(band));
    canvas.drawPath(openSkirts, fill);
    fill.color = Palette.sunkFace(_rivetTop(band));
    canvas.drawPath(rivetSkirts, fill);

    fill.color = Palette.pit;
    canvas.drawPath(pits, fill);

    fill.color = _rockTop(band);
    canvas.drawPath(lockedTops, fill);
    fill.color = _openTop(band);
    canvas.drawPath(openTops, fill);
    fill.color = _rivetTop(band);
    canvas.drawPath(rivetTops, fill);

    if (showGlyphs) {
      // Quiet on purpose. The motif is texture that tells two tiles apart at a
      // glance, not a thing to be read — the number and the stars are what the
      // eye is for, and a glyph that competes with them makes the tile busier
      // without making it more useful.
      fill.color = band.withValues(alpha: 0.09);
      canvas.drawPath(glyphsOnRock, fill);
      fill.color = band.withValues(alpha: 0.17);
      canvas.drawPath(glyphsOnPit, fill);
    }

    stroke
      ..color = Color.lerp(
        Palette.lockedEdge,
        band,
        0.20,
      )!.withValues(alpha: 0.5)
      ..strokeWidth = 1.1;
    canvas.drawPath(lockedEdges, stroke);

    // The editable edge from the board, reused verbatim: on the field it means
    // "your tap can land here", and on the map it means "you may play this".
    stroke
      ..color = Palette.plainEdge.withValues(alpha: 0.95)
      ..strokeWidth = 1.6;
    canvas.drawPath(openEdges, stroke);

    stroke
      ..color = Palette.anchorEdge
      ..strokeWidth = 1.4;
    canvas.drawPath(rivetEdges, stroke);
    stroke
      ..color = Palette.anchorRivet.withValues(alpha: 0.85)
      ..strokeWidth = 1.4;
    canvas.drawPath(rivets, stroke);
    fill.color = Palette.anchorRivet.withValues(alpha: 0.5);
    canvas.drawPath(rivetDots, fill);

    stroke
      ..color = band.withValues(alpha: 0.22)
      ..strokeWidth = 1.2;
    canvas.drawPath(pitRims, stroke);

    // The heavy tile's doubled ring, reused for a band finale — the board
    // already teaches that a ring inside a tile means "this one asks more".
    stroke
      ..color = band.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    canvas.drawPath(finaleRings, stroke);

    stroke
      ..color = Palette.goalGlow
      ..strokeWidth = 2.0;
    canvas.drawPath(trialRing, stroke);

    stroke
      ..color = band.withValues(alpha: 0.95)
      ..strokeWidth = 2.6;
    canvas.drawPath(frontierRing, stroke);

    _paintTrail(canvas, band);

    for (final t in model.tiles) {
      _paintTileDetail(canvas, t, band);
    }
  }

  Color _openTop(Color band) => Color.lerp(Palette.plainTop, band, 0.35)!;
  Color _rockTop(Color band) => Color.lerp(Palette.lockedTile, band, 0.14)!;
  Color _rivetTop(Color band) => Color.lerp(Palette.anchorTop, band, 0.10)!;

  /// Pawprints along the trail — lit over ground already walked, faint over
  /// ground still ahead, so the line reads as a route rather than as wire.
  void _paintTrail(Canvas canvas, Color band) {
    final range = MapLayout.levelsOf(model.band);
    final fill = Paint()..style = PaintingStyle.fill;
    for (var level = range.first; level < range.last; level++) {
      final from = layout.toPixel(MapLayout.coordFor(level));
      final to = layout.toPixel(MapLayout.coordFor(level + 1));
      final walked = level < model.frontier;
      fill.color = walked
          ? Palette.pawprint.withValues(alpha: 0.34)
          : Palette.lockedEdge.withValues(alpha: 0.35);
      for (final t in const [0.36, 0.64]) {
        canvas.drawCircle(
          Offset.lerp(from, to, t)!,
          _hex * (walked ? 0.055 : 0.04),
          fill,
        );
      }
    }
  }

  void _paintTileDetail(Canvas canvas, MapTile tile, Color band) {
    final centre = layout.toPixel(MapLayout.coordFor(tile.level));
    if (tile.endless) {
      _label(canvas, '∞', centre, _hex * 0.72, band);
      return;
    }

    final locked =
        tile.access == LevelAccess.needsProgress ||
        tile.access == LevelAccess.needsPurchase;
    final colour = tile.played
        ? Palette.hudText
        : locked
        ? Palette.hudDim
        : Colors.white;
    // A cleared tile carries its stars, so its number steps up to make room —
    // and the frontier tile has the dog standing on it, so its number steps
    // *down* to where the stars would have been. Leaving it in the middle put
    // the one number the player most wants to read under a dog.
    final numberAt = tile.played
        ? centre.translate(0, -_hex * 0.18)
        : tile.level == model.frontier
        ? centre.translate(0, _hex * 0.44)
        : centre;
    _label(
      canvas,
      '${tile.level}',
      numberAt,
      tile.level == model.frontier ? _hex * 0.38 : _hex * 0.5,
      colour,
    );

    if (tile.played) {
      _paintStars(canvas, tile, centre.translate(0, _hex * 0.42));
    }
  }

  void _paintStars(Canvas canvas, MapTile tile, Offset at) {
    final gap = _hex * 0.26;
    final radius = _hex * 0.085;
    final fill = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 3; i++) {
      final centre = at.translate((i - 1) * gap, 0);
      if (i < tile.stars) {
        fill.color = tile.hard ? Palette.dogBody : Palette.goalGlow;
        canvas.drawCircle(centre, radius, fill);
      } else {
        canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = Palette.hudDim.withValues(alpha: 0.7),
        );
      }
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset centre,
    double size,
    Color colour,
  ) {
    final fontSize = size * labelScale;
    final key = '$text|${fontSize.toStringAsFixed(1)}|${colour.toARGB32()}';
    final painter = _labels[key] ??= (TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(
          fontSize: fontSize,
          color: colour,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout());
    painter.paint(
      canvas,
      centre.translate(-painter.width / 2, -painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(ChapterPainter oldDelegate) =>
      oldDelegate.layout.size != layout.size ||
      oldDelegate.layout.origin != layout.origin ||
      oldDelegate.labelScale != labelScale ||
      oldDelegate.showGlyphs != showGlyphs ||
      oldDelegate.model.frontier != model.frontier ||
      !listEquals(oldDelegate.model.tiles, model.tiles);

  @override
  bool shouldRebuildSemantics(ChapterPainter oldDelegate) =>
      shouldRepaint(oldDelegate);

  /// One node per level, so the hundred tiles stop being bare pixels.
  ///
  /// [SemanticsProperties.sortKey] is load-bearing rather than tidy: the trail
  /// meanders, so geometric traversal order is not level order, and without an
  /// explicit key a screen reader would walk a row left to right and then jump
  /// backwards through the one below it.
  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final tile in model.tiles)
          CustomPainterSemantics(
            rect: Rect.fromCenter(
              center: layout.toPixel(MapLayout.coordFor(tile.level)),
              width: layout.width,
              height: layout.height,
            ),
            properties: SemanticsProperties(
              button: true,
              enabled: tile.access != LevelAccess.needsProgress,
              label: _semanticsFor(tile),
              // Required alongside a label: a semantics node carrying text with no
              // direction to read it in trips an assertion in the framework.
              textDirection: TextDirection.ltr,
              sortKey: OrdinalSortKey(tile.level.toDouble()),
              onTap: () => onSelect(tile.level),
            ),
          ),
      ];

  String _semanticsFor(MapTile tile) => Strings.mapTile(
    level: tile.level,
    title: tile.endless ? 'Endless' : Campaign.identityFor(tile.level).title,
    band: model.band.label,
    stars: tile.stars,
    played: tile.played,
    hard: tile.hard,
    frontier: tile.level == model.frontier,
    lockedByProgress: tile.access == LevelAccess.needsProgress,
    lockedByPurchase: tile.access == LevelAccess.needsPurchase,
    trial: tile.access == LevelAccess.trial,
  );
}

/// How far the map's canvas text is allowed to follow the system text scale.
///
/// Deliberately short of the real scaler. A number at 2× cannot fit inside a
/// hexagon, and a tile whose label has burst its tile is less readable than one
/// that never grew. The honest answer for a player who needs large text is the
/// chapters sheet and the semantics tree, both of which scale without limit —
/// not a `48` spilling over its neighbours.
const double maxLabelScale = 1.3;

double clampLabelScale(double scale) => math.min(scale, maxLabelScale);
