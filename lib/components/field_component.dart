import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../game/hexcape_game.dart';
import '../hex/hex_cell.dart';
import '../hex/hex_coord.dart';
import 'glyphs.dart';
import '../hex/hex_layout.dart';
import '../theme/palette.dart';

/// Draws the hex field, the editable ring, and the food.
///
/// Every hex is painted by this one component rather than by 160-odd child
/// components, because draw order carries meaning here: rows are painted top to
/// bottom so each row's extruded skirt is covered by the row in front of it.
/// The field then reads as a solid slab, and anything you clear reads as a pit
/// carved into it — which is §9.4's fake depth doing real work, not decoration.
class FieldComponent extends Component {
  FieldComponent(this.game) : super(priority: 0);

  final HexcapeGame game;

  late List<HexCell> _drawOrder = const [];
  int _drawOrderVersion = -1;

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// One hex outline at the origin, reused for every cell.
  ///
  /// Rebuilt only when the board is resized. Building a corner list and a Path
  /// per hex per frame meant roughly seven hundred allocations and fifteen
  /// hundred draw calls every frame on a full board — enough GC churn to drop
  /// frames, and dropped frames are exactly what makes sound and haptics feel
  /// late.
  Path? _hexPath;
  double _hexPathSize = -1;

  Path _hexFor(HexLayout layout) {
    if (_hexPath == null || _hexPathSize != layout.size) {
      _hexPathSize = layout.size;
      _hexPath = HexLayout.pathFromCorners(
        HexLayout.cornersAt(Offset.zero, layout.size * 0.985),
      );
    }
    return _hexPath!;
  }

  @override
  void render(Canvas canvas) {
    final layout = game.layout;
    _renderVignette(canvas);

    _refreshDrawOrder();
    _renderField(canvas, layout);

    for (final cell in _drawOrder) {
      _renderOverlays(canvas, cell, _centreOf(cell, layout), layout);
    }

    // Light is one radial scrim over the finished board rather than a tint on
    // every hex. Per-cell tinting is what forced a colour change per tile and
    // made batching impossible — and a gradient is the better picture anyway,
    // being smooth where a per-cell value is quantised by definition.
    _renderScent(canvas, layout);
    _renderGuards(canvas, layout);
    _renderLight(canvas, layout);
    _renderHint(canvas, layout);

    _renderTutorialTarget(canvas, layout);
    _renderPickups(canvas, layout);
    _renderTapRing(canvas, layout);
    _renderGoal(canvas, layout);
    if (game.tuning.showTruePath) {
      _renderTruePath(canvas, layout);
    }
  }

  /// The board, in about a dozen draw calls instead of fifteen hundred.
  ///
  /// Cells accumulate into one path per material and each is drawn once. The
  /// pass order is what makes the fake depth work and is unchanged: holes, then
  /// the skirts that extrude into them, then the tops that cover the skirt of
  /// the row behind. Batching is safe precisely *because* of that order — a
  /// skirt is only ever visible over a hole, and a solid top always covers the
  /// skirt behind it, so all-holes then all-skirts then all-tops is the same
  /// image as drawing cell by cell.
  void _renderField(Canvas canvas, HexLayout layout) {
    final hex = _hexFor(layout);
    final depth = Offset(0, layout.size * 0.26);

    final pits = Path();
    final skirts = {for (final t in HexType.values) t: Path()};
    final tops = {for (final t in HexType.values) t: Path()};
    final edges = {for (final t in HexType.values) t: Path()};
    final editableEdges = Path();
    final rivets = Path();
    final rivetDots = Path();
    final heavyRings = Path();
    final crackedRings = Path();
    final springMarks = Path();
    final faultMarks = Path();
    final slopeMarks = Path();
    final sunkenMarks = Path();

    final rivetHex = HexLayout.pathFromCorners(
      HexLayout.cornersAt(Offset.zero, layout.size * 0.3),
    );
    final ringHex = HexLayout.pathFromCorners(
      HexLayout.cornersAt(Offset.zero, layout.size * 0.52),
    );
    final sunkenInner = HexLayout.pathFromCorners(
      HexLayout.cornersAt(Offset.zero, layout.size * 0.55),
    );
    final sunkenCore = HexLayout.pathFromCorners(
      HexLayout.cornersAt(Offset.zero, layout.size * 0.34),
    );

    for (final cell in _drawOrder) {
      final centre = _centreOf(cell, layout);
      if (!cell.isSolid) {
        pits.addPath(hex, centre);
        continue;
      }
      // An unrevealed cell draws as plain. Anything else hands the player the
      // obstacle map before they have earned any of it (§2.1).
      final shown = cell.revealed ? cell.type : HexType.plain;
      skirts[shown]!.addPath(hex, centre + depth);
      tops[shown]!.addPath(hex, centre);
      if (game.editable.contains(cell.coord)) {
        editableEdges.addPath(hex, centre);
      } else {
        edges[shown]!.addPath(hex, centre);
      }
      if (shown == HexType.anchor) {
        rivets.addPath(rivetHex, centre);
        rivetDots.addOval(
          Rect.fromCircle(center: centre, radius: layout.size * 0.09),
        );
      } else if (shown == HexType.heavy) {
        (cell.hits > 0 ? crackedRings : heavyRings).addPath(ringHex, centre);
      }
      if (shown == HexType.fault) {
        // A jagged split down the hex. Drawn on the *solid* cell, which is the
        // only moment the warning is worth anything: once it is open the
        // regrowth ghost and its two pulses take over, and by then the decision
        // to commit has already been made.
        final s = layout.size;
        faultMarks
          ..moveTo(centre.dx - s * 0.10, centre.dy - s * 0.42)
          ..lineTo(centre.dx + s * 0.14, centre.dy - s * 0.10)
          ..lineTo(centre.dx - s * 0.12, centre.dy + s * 0.10)
          ..lineTo(centre.dx + s * 0.10, centre.dy + s * 0.42);
      }
      if (shown == HexType.slope) {
        // An arrow along the direction this cell actually pushes, not a
        // decorative one. The whole difference between a slope and a spring is
        // that you can read a slope before you commit to it, and the arrow is
        // where that promise is kept.
        final s = layout.size;
        final step = layout.toPixel(
          cell.coord + HexCoord.directions[cell.slopeDirection],
        );
        final away = step - centre;
        final length = away.distance;
        if (length > 1e-6) {
          final unit = away / length;
          // Perpendicular, for the two barbs of the head.
          final side = Offset(-unit.dy, unit.dx);
          final tip = centre + unit * (s * 0.46);
          final tail = centre - unit * (s * 0.42);
          final base = centre + unit * (s * 0.10);
          slopeMarks
            ..moveTo(tail.dx, tail.dy)
            ..lineTo(tip.dx, tip.dy)
            ..moveTo(base.dx + side.dx * s * 0.26, base.dy + side.dy * s * 0.26)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(
              base.dx - side.dx * s * 0.26,
              base.dy - side.dy * s * 0.26,
            );
        }
      }
      if (shown == HexType.sunken) {
        // Rings receding inward: ground that is further away than it looks,
        // and cannot be reached across. Whether it is reachable *right now* is
        // already answered by the editable highlight, which asks the grid.
        sunkenMarks
          ..addPath(sunkenInner, centre)
          ..addPath(sunkenCore, centre);
      }
      if (shown == HexType.spring) {
        // Three nested chevrons pointing up out of the hex: a coil under
        // tension. Drawn on solid and open springs alike, because the player
        // needs to know one is there *before* deciding to open it.
        final s = layout.size;
        for (var i = 0; i < 3; i++) {
          final y = centre.dy + s * (0.30 - i * 0.26);
          springMarks
            ..moveTo(centre.dx - s * 0.34, y)
            ..lineTo(centre.dx, y - s * 0.26)
            ..lineTo(centre.dx + s * 0.34, y);
        }
      }
    }

    _fill.color = const Color(0xFF070A14);
    canvas.drawPath(pits, _fill);

    for (final type in HexType.values) {
      _fill.color = _sideOf(type);
      canvas.drawPath(skirts[type]!, _fill);
    }
    for (final type in HexType.values) {
      _fill.color = _topOf(type);
      canvas.drawPath(tops[type]!, _fill);
    }

    _stroke.strokeWidth = 1.1;
    for (final type in HexType.values) {
      _stroke.color = _edgeOf(type).withValues(alpha: 0.5);
      canvas.drawPath(edges[type]!, _stroke);
    }
    _stroke
      ..color = Palette.plainEdge.withValues(alpha: 0.95)
      ..strokeWidth = 1.6;
    canvas.drawPath(editableEdges, _stroke);

    // Anchors carry a rivet and heavy tiles a doubled ring, so neither is ever
    // told apart by colour alone (§5).
    _stroke
      ..color = Palette.anchorRivet.withValues(alpha: 0.85)
      ..strokeWidth = 1.4;
    canvas.drawPath(rivets, _stroke);
    _fill.color = Palette.anchorRivet.withValues(alpha: 0.5);
    canvas.drawPath(rivetDots, _fill);

    _stroke
      ..color = Palette.heavyEdge.withValues(alpha: 0.7)
      ..strokeWidth = 1.7;
    canvas.drawPath(heavyRings, _stroke);
    _stroke
      ..color = Palette.heavyCrack.withValues(alpha: 0.9)
      ..strokeWidth = 1.1;
    canvas.drawPath(crackedRings, _stroke);

    _stroke
      ..color = Palette.springEdge.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(springMarks, _stroke);

    _stroke
      ..color = Palette.faultEdge.withValues(alpha: 0.85)
      ..strokeWidth = 1.6;
    canvas.drawPath(faultMarks, _stroke);

    _stroke
      ..color = Palette.slopeEdge.withValues(alpha: 0.9)
      ..strokeWidth = 1.6;
    canvas.drawPath(slopeMarks, _stroke);
    _stroke.strokeCap = StrokeCap.butt;

    _stroke
      ..color = Palette.sunkenEdge.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    canvas.drawPath(sunkenMarks, _stroke);
  }

  /// The nudge for a player who has stopped getting anywhere (§8).
  ///
  /// A chevron out at the edge of her reach, pointing the way the route goes.
  /// Drawn *after* the light scrim rather than before it, unlike everything
  /// else on the board: a hint dimmed by the very fog it exists to answer would
  /// be least visible exactly when it is needed.
  void _renderHint(Canvas canvas, HexLayout layout) {
    if (!game.hintVisible) {
      return;
    }
    final target = game.hintTarget;
    if (target == null) {
      return;
    }
    final from = game.dog.position;
    final delta = layout.toPixel(target) - from;
    if (delta.distance < 1e-3) {
      return;
    }
    final direction = delta / delta.distance;
    final strength = game.hintStrength;
    // Drifting outward and fading, so it reads as pointing somewhere rather
    // than marking the spot it sits on.
    final breath = (game.elapsed * 1.1) % 1.0;
    final reach = layout.size * (1.6 + breath * 0.9);
    final centre = from + direction * reach;
    final angle = math.atan2(direction.dy, direction.dx);

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(angle);
    final s = layout.size * 0.34;
    _stroke
      ..color = Palette.goalGlow.withValues(
        alpha: strength * (1 - breath) * 0.85,
      )
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(-s * 0.5, -s)
        ..lineTo(s * 0.55, 0)
        ..lineTo(-s * 0.5, s),
      _stroke,
    );
    canvas.restore();
    _stroke.strokeCap = StrokeCap.butt;
  }

  /// Scent (§6.2): the cheapest way through, as a line of fading motes.
  ///
  /// Drawn *before* the light scrim so the fog still dims the far end of it.
  /// Lighting the whole route at full strength would hand the player the shape
  /// of the unexplored board, which is the one thing the fog exists to withhold
  /// — this shows the direction without giving away the map.
  void _renderScent(Canvas canvas, HexLayout layout) {
    final path = game.scentPath;
    if (path.length < 2) {
      return;
    }
    _fill.maskFilter = MaskFilter.blur(BlurStyle.normal, layout.size * 0.22);
    for (var i = 1; i < path.length; i++) {
      // A travelling shimmer, so it reads as a direction rather than a wall of
      // dots — the eye follows the motion outward.
      final along = i / path.length;
      final wave = 0.55 + 0.45 * math.sin(game.elapsed * 3.4 - along * 5.5);
      final fade = (1 - along * 0.55).clamp(0.0, 1.0);
      _fill.color = Palette.scent.withValues(alpha: 0.55 * fade * wave);
      canvas.drawCircle(
        layout.toPixel(path[i]),
        layout.size * (0.13 + 0.05 * wave),
        _fill,
      );
    }
    _fill.maskFilter = null;
  }

  /// Patrols (§6.1): the lit ground, then the lamp itself.
  ///
  /// Drawn after the field and before the light scrim, so the fog dims a
  /// distant patrol exactly as it dims everything else — a guard the player can
  /// see across an unexplored board would give away the shape of it.
  void _renderGuards(Canvas canvas, HexLayout layout) {
    if (game.guards.isEmpty) {
      return;
    }
    final hex = _hexFor(layout);

    // The two lights are drawn as two passes rather than one, because they mean
    // opposite things: red ground is where she will not go, pale ground is
    // where your taps will not land. A player has to be able to tell at a
    // glance which of the two is sweeping toward them.
    _paintLitGround(
      canvas,
      hex,
      layout,
      game.guardedCells,
      Palette.guardLight,
      Palette.guard,
    );
    _paintLitGround(
      canvas,
      hex,
      layout,
      game.wardedCells,
      Palette.sentryLight,
      Palette.sentry,
    );

    for (final guard in game.guards) {
      final centre = guard.positionIn(layout);
      final flare = 1 + guard.alertFlash * 0.7;
      final pulse = 0.8 + 0.2 * math.sin(game.elapsed * 4);
      final colour = guard.isSentry ? Palette.sentry : Palette.guard;

      _fill
        ..color = colour.withValues(alpha: 0.30 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, layout.size * 0.5);
      canvas.drawCircle(centre, layout.size * 0.75 * flare, _fill);
      _fill.maskFilter = null;

      // An eye rather than a person: it is a light, and a body would suggest it
      // could be walked around.
      _fill.color = colour.withValues(alpha: 0.9);
      canvas.drawOval(
        Rect.fromCenter(
          center: centre,
          width: layout.size * 0.66 * flare,
          height: layout.size * 0.40 * flare,
        ),
        _fill,
      );
      _fill.color = Palette.background;
      canvas.drawCircle(centre, layout.size * 0.13 * flare, _fill);

      // A sentry carries a bar through its pupil — the "no" that the colour
      // alone would be carrying otherwise, for the same reason every hex type
      // has a mark as well as a shade.
      if (guard.isSentry) {
        _stroke
          ..color = colour
          ..strokeWidth = 1.6;
        canvas.drawLine(
          centre.translate(-layout.size * 0.30, 0),
          centre.translate(layout.size * 0.30, 0),
          _stroke,
        );
      }
    }
  }

  void _paintLitGround(
    Canvas canvas,
    Path hex,
    HexLayout layout,
    Set<HexCoord> cells,
    Color fill,
    Color edge,
  ) {
    if (cells.isEmpty) {
      return;
    }
    final lit = Path();
    for (final coord in cells) {
      lit.addPath(hex, layout.toPixel(coord));
    }
    _fill.color = fill;
    canvas.drawPath(lit, _fill);
    _stroke
      ..color = edge.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    canvas.drawPath(lit, _stroke);
  }

  static Color _topOf(HexType type) => switch (type) {
    HexType.plain => Palette.plainTop,
    HexType.heavy => Palette.heavyTop,
    HexType.anchor => Palette.anchorTop,
    HexType.spring => Palette.springTop,
    HexType.fault => Palette.faultTop,
    HexType.slope => Palette.slopeTop,
    HexType.sunken => Palette.sunkenTop,
  };

  static Color _sideOf(HexType type) => switch (type) {
    HexType.plain => Palette.plainSide,
    HexType.heavy => Palette.heavySide,
    HexType.anchor => Palette.anchorSide,
    HexType.spring => Palette.springSide,
    HexType.fault => Palette.faultSide,
    HexType.slope => Palette.slopeSide,
    HexType.sunken => Palette.sunkenSide,
  };

  static Color _edgeOf(HexType type) => switch (type) {
    HexType.plain => Palette.plainEdge,
    HexType.heavy => Palette.heavyEdge,
    HexType.anchor => Palette.anchorEdge,
    HexType.spring => Palette.springEdge,
    HexType.fault => Palette.faultEdge,
    HexType.slope => Palette.slopeEdge,
    HexType.sunken => Palette.sunkenEdge,
  };

  /// Darkness away from the dog: one gradient drawn over the finished board.
  void _renderLight(Canvas canvas, HexLayout layout) {
    if (!game.tuning.fogEnabled) {
      return;
    }
    final reach = game.revealRadius;
    final centre = game.dog.position + game.juice.offset;
    final size = game.size;
    _fill.shader = Gradient.radial(
      centre,
      reach * 2.4,
      [const Color(0x00000000), Palette.background.withValues(alpha: 0.55)],
      const [0.35, 1.0],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), _fill);
    _fill.shader = null;
  }

  /// One slab, for the few cells mid-regrowth that need their own scale and
  /// opacity. Everything else goes through the batch.
  void _drawSingleSlab(
    Canvas canvas,
    HexCell cell,
    Offset centre,
    HexLayout layout,
    double opacity,
    double scale,
  ) {
    final shown = cell.revealed ? cell.type : HexType.plain;
    final path = HexLayout.pathFromCorners(
      HexLayout.cornersAt(centre, layout.size * 0.985 * scale),
    );
    _fill.color = _sideOf(shown).withValues(alpha: opacity);
    canvas.drawPath(path.shift(Offset(0, layout.size * 0.26)), _fill);
    _fill.color = _topOf(shown).withValues(alpha: opacity);
    canvas.drawPath(path, _fill);
    _stroke
      ..color = _edgeOf(shown).withValues(alpha: opacity * 0.5)
      ..strokeWidth = 1.1;
    canvas.drawPath(path, _stroke);
  }

  /// Rows front-to-back. Sorted once per level, not per frame.
  void _refreshDrawOrder() {
    if (_drawOrderVersion == game.levelVersion) {
      return;
    }
    _drawOrderVersion = game.levelVersion;
    _drawOrder = game.grid.all.toList()
      ..sort((a, b) {
        final byRow = a.coord.r.compareTo(b.coord.r);
        return byRow != 0 ? byRow : a.coord.q.compareTo(b.coord.q);
      });
  }

  void _renderVignette(Canvas canvas) {
    final size = game.size;
    // Shake moves the board, so the vignette is drawn oversized and offset back
    // against it — otherwise a hard edge of unpainted background slides in from
    // the side on every impact.
    final shake = game.juice.offset;
    final rect = Rect.fromLTWH(
      -shake.dx - 24,
      -shake.dy - 24,
      size.x + 48,
      size.y + 48,
    );

    final hunger = game.hunger.fraction;
    var urgency = 0.0;
    if (game.tuning.hungerEnabled && hunger < 0.25 && !game.isOver) {
      urgency = 1 - hunger / 0.25;
    }

    // Being walled in is a countdown, not a stall. Without this the screen looks
    // exactly as it does when she is simply waiting to be tapped out, which is
    // why it reads as the dog being stuck rather than about to be crushed.
    final boxedIn = game.dog.enclosedFor > 0 && !game.isOver;
    if (boxedIn) {
      urgency = math.max(
        urgency,
        0.45 +
            0.55 *
                (game.dog.enclosedFor / game.tuning.suffocateSeconds).clamp(
                  0.0,
                  1.0,
                ),
      );
    }

    var edge = Palette.backgroundVignette;
    if (urgency > 0) {
      final pulse = 0.5 + 0.5 * math.sin(game.elapsed * (5 + urgency * 9));
      edge = Color.lerp(
        Palette.backgroundVignette,
        Palette.danger,
        urgency * (0.2 + 0.3 * pulse),
      )!;
    }

    _fill.shader = Gradient.radial(
      Offset(size.x / 2, size.y * 0.45),
      size.y * 0.72,
      [Palette.background, edge],
      const [0.0, 1.0],
    );
    canvas.drawRect(rect, _fill);
    _fill.shader = null;
  }

  Offset _centreOf(HexCell cell, HexLayout layout) {
    final centre = layout.toPixel(cell.coord);
    if (cell.rejectShake <= 0) {
      return centre;
    }
    final shake =
        math.sin(cell.rejectShake * math.pi * 8) *
        cell.rejectShake *
        layout.size *
        0.14;
    return Offset(centre.dx + shake, centre.dy);
  }

  void _renderOverlays(
    Canvas canvas,
    HexCell cell,
    Offset centre,
    HexLayout layout,
  ) {
    switch (cell.state) {
      case CellState.solid:
        _drawSnapEcho(canvas, cell, centre, layout);
      case CellState.open:
        _drawClearFlash(canvas, cell, centre, layout);
      case CellState.regrowing:
        _drawRegrowth(canvas, cell, centre, layout);
    }
  }

  /// How brightly a point is lit, by how close it is to the dog.
  ///
  /// Separate from what the player *knows*: a far-off revealed anchor still
  /// draws as an anchor, just dimly. Floored well above zero so the far field
  /// keeps reading as a silhouette instead of going black — the goal is a pool
  /// of light around her, not a torch in a cave.
  /// The beat right after a tap: the hex swells about 10% and fades out while
  /// the shards fly (§10). The shards themselves are in the effects layer.
  void _drawClearFlash(
    Canvas canvas,
    HexCell cell,
    Offset centre,
    HexLayout layout,
  ) {
    if (cell.clearBurst <= 0) {
      return;
    }
    final t = cell.clearBurst;
    // Warmer and brighter the higher the chain, so the field itself shows the
    // streak building rather than leaving it entirely to the ear.
    final heat = game.streak.intensity;
    _fill.color = Color.lerp(
      Palette.plainTop,
      Palette.dogBody,
      heat * 0.55,
    )!.withValues(alpha: t * (0.75 + heat * 0.25));
    canvas.drawPath(
      HexLayout.pathFromCorners(
        HexLayout.cornersAt(centre, layout.size * (1 + 0.10 * (1 - t))),
      ),
      _fill,
    );
  }

  /// The echo left on a hex that has just snapped shut. The travelling ring
  /// lives in the effects layer; this is the flash on the tile itself.
  void _drawSnapEcho(
    Canvas canvas,
    HexCell cell,
    Offset centre,
    HexLayout layout,
  ) {
    if (cell.snapRipple <= 0) {
      return;
    }
    _stroke
      ..color = Palette.shockwave.withValues(alpha: cell.snapRipple * 0.3)
      ..strokeWidth = 1.4;
    canvas.drawPath(
      HexLayout.pathFromCorners(HexLayout.cornersAt(centre, layout.size * 0.9)),
      _stroke,
    );
  }

  /// The three-stage regrowth warning (§10). The pulses are the fairness
  /// contract: a cell never blocks anything the player was not shown first.
  void _drawRegrowth(
    Canvas canvas,
    HexCell cell,
    Offset centre,
    HexLayout layout,
  ) {
    final t = cell.regrowT;

    if (t < RegrowAnim.ghostEnd) {
      // Stage 1 — a faint outline ghost fades in.
      final u = t / RegrowAnim.ghostEnd;
      _stroke
        ..color = Palette.regrowGhost.withValues(alpha: 0.18 + u * 0.25)
        ..strokeWidth = 1.4;
      canvas.drawPath(
        HexLayout.pathFromCorners(
          HexLayout.cornersAt(centre, layout.size * 0.94),
        ),
        _stroke,
      );
      return;
    }

    if (t < RegrowAnim.pulseEnd) {
      // Stage 2 — two warning pulses.
      final u =
          (t - RegrowAnim.ghostEnd) /
          (RegrowAnim.pulseEnd - RegrowAnim.ghostEnd);
      final pulse =
          (math.sin(u * math.pi * 2 * RegrowAnim.pulseCount - math.pi / 2) +
              1) /
          2;
      final scale = 0.86 + pulse * 0.12;
      _fill.color = Palette.regrowPulse.withValues(alpha: 0.10 + pulse * 0.28);
      canvas.drawPath(
        HexLayout.pathFromCorners(
          HexLayout.cornersAt(centre, layout.size * scale),
        ),
        _fill,
      );
      _stroke
        ..color = Palette.regrowPulse.withValues(alpha: 0.35 + pulse * 0.45)
        ..strokeWidth = 1.2 + pulse * 1.4;
      canvas.drawPath(
        HexLayout.pathFromCorners(
          HexLayout.cornersAt(centre, layout.size * scale),
        ),
        _stroke,
      );
      return;
    }

    // Stage 3 — snap to full, overshooting slightly on the way in.
    final u = (t - RegrowAnim.pulseEnd) / (1 - RegrowAnim.pulseEnd);
    _drawSingleSlab(
      canvas,
      cell,
      centre,
      layout,
      0.45 + u * 0.55,
      1.10 - u * 0.10,
    );
  }

  /// The editable radius, drawn as a dashed ring around the dog. This is how
  /// §2.1 gets taught with no text at all (§12.5): the player can see the
  /// boundary of what they are allowed to change.
  void _renderTapRing(Canvas canvas, HexLayout layout) {
    final centre = game.dog.position;
    final radius = game.effectiveTapRadius;
    const segments = 34;
    _stroke
      ..color = game.tapRingFlash > 0
          ? Color.lerp(
              Palette.tapRing,
              Palette.tapRingActive,
              game.tapRingFlash,
            )!
          : Palette.tapRing
      ..strokeWidth = 1.3;

    final sweep = (math.pi * 2) / segments;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, _stroke);
    }
  }

  /// The tile the tutorial is pointing at.
  ///
  /// Drawn after the light scrim so it is never dimmed by distance — a hint the
  /// fog can hide is not a hint.
  void _renderTutorialTarget(Canvas canvas, HexLayout layout) {
    final target = game.tutorialTarget;
    if (target == null) {
      return;
    }
    final centre = layout.toPixel(target);
    final pulse = game.tuning.reducedMotion
        ? 0.5
        : 0.5 + 0.5 * math.sin(game.elapsed * 4.5);
    _stroke
      ..color = Palette.dogBody.withValues(alpha: 0.55 + 0.45 * pulse)
      ..strokeWidth = 2.0 + pulse;
    canvas.drawPath(
      HexLayout.pathFromCorners(
        HexLayout.cornersAt(centre, layout.size * (0.9 + 0.1 * pulse)),
      ),
      _stroke,
    );
    _fill
      ..color = Palette.dogBody.withValues(alpha: 0.16 * pulse)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, layout.size * 0.4);
    canvas.drawCircle(centre, layout.size * 0.8, _fill);
    _fill.maskFilter = null;
    // An opaque pointer makes the interactive target distinct from pickups.
    final tip = centre.translate(0, -layout.size * (0.55 + pulse * 0.12));
    _fill.color = Palette.hudText;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - layout.size * 0.22, tip.dy - layout.size * 0.28)
        ..lineTo(tip.dx + layout.size * 0.22, tip.dy - layout.size * 0.28)
        ..close(),
      _fill,
    );
  }

  /// Treats and powerups (§6.2).
  ///
  /// Drawn at full brightness and **ignoring the fog**, unlike hex types. That
  /// asymmetry is the point: the reward is known, the cost of reaching it is
  /// not, so the player weighs a detour whose price they cannot yet see. A
  /// pickup hidden until you arrived would not be a decision at all.
  void _renderPickups(Canvas canvas, HexLayout layout) {
    for (final pickup in game.pickups) {
      if (pickup.collected && pickup.collectFlash <= 0) {
        continue;
      }
      final centre = layout.toPixel(pickup.coord);
      final taken = pickup.collected;
      // On collection it swells and fades rather than blinking out.
      final scale = taken ? 1 + (1 - pickup.collectFlash) * 0.8 : 1.0;
      final alpha = taken ? pickup.collectFlash : 1.0;
      final colour = Palette.forPickup(pickup.kind);
      final size = layout.size * 0.30 * scale;
      final pulse = 0.85 + 0.15 * math.sin(game.elapsed * 3 + pickup.coord.q);

      _fill
        ..color = colour.withValues(alpha: 0.24 * alpha * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, layout.size * 0.35);
      canvas.drawCircle(centre, layout.size * 0.4 * scale, _fill);
      _fill.maskFilter = null;

      _stroke
        ..color = colour.withValues(alpha: alpha)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      _fill.color = colour.withValues(alpha: alpha);

      drawPickupGlyph(
        canvas,
        pickup.kind,
        centre: centre,
        size: size,
        fill: _fill,
        stroke: _stroke,
      );
    }
  }

  /// The food (§9.3): a bone with a gentle gold glow so the goal is always
  /// locatable, dimmed while it is still buried under a solid hex.
  void _renderGoal(Canvas canvas, HexLayout layout) {
    final grid = game.grid;
    final centre = layout.toPixel(grid.exit);
    // Only slightly dimmed while still buried. Treats are bones too, and at
    // the old 0.42 they out-shone the goal — leaving the one thing the whole
    // run is aimed at as the dimmest bone on the board.
    final buried = grid.at(grid.exit)?.isSolid ?? false;
    final opacity = buried ? 0.82 : 1.0;
    final breathe = 0.85 + 0.15 * math.sin(game.elapsed * 2.4);

    canvas.save();
    canvas.translate(centre.dx, centre.dy);

    // A wider, stronger halo than any pickup gets, so the goal stays the most
    // prominent thing on the field however many treats are scattered about.
    _fill
      ..color = Palette.goalGlow.withValues(alpha: 0.5 * opacity * breathe)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, layout.size * 0.7);
    canvas.drawCircle(Offset.zero, layout.size * 0.8, _fill);
    _fill.maskFilter = null;

    canvas.rotate(-0.38);
    _fill.color = Palette.goalBone.withValues(alpha: opacity);
    canvas.drawPath(bonePath(layout.size), _fill);
    canvas.restore();
  }

  /// Developer overlay only. The player never sees this — the discovery loop
  /// is the game (§8).
  void _renderTruePath(Canvas canvas, HexLayout layout) {
    _fill.color = Palette.truePathDebug;
    for (final coord in game.grid.truePath) {
      canvas.drawCircle(layout.toPixel(coord), layout.size * 0.16, _fill);
    }
  }
}
