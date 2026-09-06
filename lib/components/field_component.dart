import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../entities/guard.dart';
import '../entities/pickup.dart';
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
    _renderLamps(canvas, layout);
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

    // Marks for the new ground, one batched path each. The rule they all obey
    // is the one the rivet set: nothing is told apart by colour alone.
    final mireMarks = Path();
    final thicketMarks = Path();
    final sleeperMarks = Path();
    final foxfireMarks = Path();
    final foxfireGlow = Path();
    final iceMarks = Path();
    final eddyMarks = Path();
    final magnetMarks = Path();
    final hardpanMarks = Path();
    final overgrowthMarks = Path();
    final tremorMarks = Path();
    final gateMarks = Path();
    final switchMarks = Path();
    final mirrorMarks = Path();
    final mirrorChargedMarks = Path();
    final thornFills = Path();
    final alarmMarks = Path();
    final thatchMarks = Path();
    final thatchCrossed = Path();
    final scaffoldMarks = Path();

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
      // The nine hundred million marks of the new ground, each a separate
      // batched path so none is ever told apart by colour alone. Every one is
      // drawn on the solid face: all of these cells mean something only until
      // they open.
      if (cell.isSolid && cell.revealed) {
        final s = layout.size;
        switch (shown) {
          case HexType.mire:
            // Two soft pools — ground you sink into as you watch.
            mireMarks.addOval(Rect.fromEllipse(
              center: centre.translate(-s * 0.16, s * 0.10),
              radiusX: s * 0.26,
              radiusY: s * 0.15,
            ));
            mireMarks.addOval(Rect.fromEllipse(
              center: centre.translate(s * 0.20, -s * 0.14),
              radiusX: s * 0.18,
              radiusY: s * 0.10,
            ));
          case HexType.thicket:
            // Three blades of grass: this cell wants the one next to it read.
            thicketMarks
              ..moveTo(centre.dx - s * 0.3, centre.dy + s * 0.3)
              ..lineTo(centre.dx - s * 0.3, centre.dy - s * 0.16)
              ..moveTo(centre.dx, centre.dy + s * 0.3)
              ..lineTo(centre.dx, centre.dy - s * 0.34)
              ..moveTo(centre.dx + s * 0.3, centre.dy + s * 0.3)
              ..lineTo(centre.dx + s * 0.3, centre.dy - s * 0.16);
          case HexType.sleeper:
            // A closed eye. What sleeps here is awake everywhere around it.
            sleeperMarks
              ..moveTo(centre.dx - s * 0.34, centre.dy - s * 0.05)
              ..quadraticBezierTo(
                centre.dx,
                centre.dy + s * 0.30,
                centre.dx + s * 0.34,
                centre.dy - s * 0.05,
              )
              ..moveTo(centre.dx, centre.dy + s * 0.10)
              ..lineTo(centre.dx, centre.dy + s * 0.22);
          case HexType.foxfire:
            foxfireMarks.addOval(Rect.fromCircle(
              center: centre.translate(s * 0.16, -s * 0.14),
              radius: s * 0.10,
            ));
            foxfireMarks.addOval(Rect.fromCircle(
              center: centre.translate(-s * 0.18, s * 0.02),
              radius: s * 0.08,
            ));
            foxfireMarks.addOval(Rect.fromCircle(
              center: centre.translate(s * 0.02, s * 0.20),
              radius: s * 0.06,
            ));
            foxfireGlow.addOval(Rect.fromCircle(center: centre, radius: s * 0.5));
          case HexType.ice:
            // Three parallel streaks skimmed across the face.
            iceMarks
              ..moveTo(centre.dx - s * 0.36, centre.dy - s * 0.10)
              ..lineTo(centre.dx + s * 0.22, centre.dy - s * 0.34)
              ..moveTo(centre.dx - s * 0.26, centre.dy + s * 0.10)
              ..lineTo(centre.dx + s * 0.36, centre.dy - s * 0.14)
              ..moveTo(centre.dx - s * 0.10, centre.dy + s * 0.34)
              ..lineTo(centre.dx + s * 0.40, centre.dy + s * 0.10);
          case HexType.eddy:
            // One hooked sweep curving off-centre — the current made visible.
            eddyMarks
              ..moveTo(centre.dx + s * 0.30, centre.dy + s * 0.05)
              ..arcToPoint(
                Offset(centre.dx - s * 0.30, centre.dy + s * 0.10),
                radius: Radius.circular(s * 0.32),
              )
              ..moveTo(centre.dx - s * 0.30, centre.dy + s * 0.10)
              ..lineTo(centre.dx - s * 0.16, centre.dy + s * 0.02)
              ..moveTo(centre.dx - s * 0.30, centre.dy + s * 0.10)
              ..lineTo(centre.dx - s * 0.22, centre.dy + s * 0.26);
          case HexType.magnet:
            // An arrow pulled to the middle of its own tile.
            magnetMarks
              ..moveTo(centre.dx - s * 0.34, centre.dy + s * 0.22)
              ..lineTo(centre.dx, centre.dy)
              ..lineTo(centre.dx + s * 0.34, centre.dy + s * 0.22)
              ..moveTo(centre.dx - s * 0.06, centre.dy + s * 0.22)
              ..lineTo(centre.dx + s * 0.06, centre.dy + s * 0.22);
          case HexType.hardpan:
            // A shield stamped on the face. Its damage is told by the ring
            // count above, which asks hex_field how much it carries.
            if (cell.hits == 0) {
              hardpanMarks
                ..moveTo(centre.dx - s * 0.24, centre.dy - s * 0.12)
                ..lineTo(centre.dx + s * 0.24, centre.dy - s * 0.12)
                ..quadraticBezierTo(
                  centre.dx + s * 0.24,
                  centre.dy + s * 0.22,
                  centre.dx,
                  centre.dy + s * 0.34,
                )
                ..quadraticBezierTo(
                  centre.dx - s * 0.24,
                  centre.dy + s * 0.22,
                  centre.dx - s * 0.24,
                  centre.dy - s * 0.12,
                );
            }
          case HexType.overgrowth:
            // A heart with two tendrils still in the ground.
            overgrowthMarks
              ..moveTo(centre.dx, centre.dy + s * 0.24)
              ..cubicTo(
                centre.dx - s * 0.44, centre.dy,
                centre.dx - s * 0.20, centre.dy - s * 0.34,
                centre.dx, centre.dy - s * 0.10,
              )
              ..cubicTo(
                centre.dx + s * 0.20, centre.dy - s * 0.34,
                centre.dx + s * 0.44, centre.dy,
                centre.dx, centre.dy + s * 0.24,
              )
              ..moveTo(centre.dx - s * 0.10, centre.dy + s * 0.24)
              ..lineTo(centre.dx - s * 0.16, centre.dy + s * 0.44)
              ..moveTo(centre.dx + s * 0.10, centre.dy + s * 0.24)
              ..lineTo(centre.dx + s * 0.16, centre.dy + s * 0.44);
          case HexType.tremor:
            tremorMarks
              ..moveTo(centre.dx - s * 0.28, centre.dy + s * 0.12)
              ..lineTo(centre.dx - s * 0.10, centre.dy + s * 0.12)
              ..lineTo(centre.dx - s * 0.02, centre.dy - s * 0.30)
              ..lineTo(centre.dx + s * 0.10, centre.dy + s * 0.12)
              ..lineTo(centre.dx + s * 0.28, centre.dy + s * 0.12);
          case HexType.gate:
            // A barred door with a keyhole — it will not answer a tap. A
            // lifted lockbar draws as bare ground: the bars are the door, and
            // once the door is up the hex is ordinary clay.
            if (!cell.gateOpen) {
              gateMarks
                ..moveTo(centre.dx - s * 0.30, centre.dy - s * 0.30)
                ..lineTo(centre.dx + s * 0.30, centre.dy - s * 0.30)
                ..lineTo(centre.dx + s * 0.30, centre.dy + s * 0.24)
                ..moveTo(centre.dx - s * 0.30, centre.dy - s * 0.30)
                ..lineTo(centre.dx - s * 0.30, centre.dy + s * 0.24)
                ..moveTo(centre.dx, centre.dy - s * 0.05)
                ..lineTo(centre.dx, centre.dy + s * 0.18)
                ..moveTo(centre.dx - s * 0.30, centre.dy + s * 0.24)
                ..lineTo(centre.dx + s * 0.30, centre.dy + s * 0.24);
              gateMarks.addOval(Rect.fromCircle(
                center: centre.translate(0, -s * 0.12),
                radius: s * 0.09,
              ));
            }
          case HexType.switchTile:
            // A paw you can press.
            switchMarks.addOval(Rect.fromEllipse(
              center: centre.translate(0, s * 0.10),
              radiusX: s * 0.16,
              radiusY: s * 0.12,
            ));
            for (final toe in [
              centre.translate(-s * 0.18, -s * 0.12),
              centre.translate(0, -s * 0.18),
              centre.translate(s * 0.18, -s * 0.12),
            ]) {
              switchMarks.addOval(Rect.fromCircle(center: toe, radius: s * 0.06));
            }
          case HexType.mirror:
            // A crescent, filled in as its half of the pair is answered.
            final path = Path()
              ..moveTo(centre.dx + s * 0.16, centre.dy - s * 0.34)
              ..arcToPoint(
                Offset(centre.dx + s * 0.16, centre.dy + s * 0.34),
                radius: Radius.circular(s * 0.52),
                largeArc: true,
              )
              ..arcToPoint(
                Offset(centre.dx + s * 0.16, centre.dy - s * 0.34),
                radius: Radius.circular(s * 0.34),
                clockwise: false,
              );
            if (cell.charged) {
              mirrorChargedMarks.addPath(path, Offset.zero);
            } else {
              mirrorMarks.addPath(path, Offset.zero);
            }
          case HexType.thorn:
            thornFills.addPath(thornMarkPath(centre, s), Offset.zero);
          case HexType.alarm:
            alarmMarks
              ..moveTo(centre.dx, centre.dy - s * 0.34)
              ..lineTo(centre.dx, centre.dy - s * 0.22)
              ..moveTo(centre.dx - s * 0.24, centre.dy - s * 0.06)
              ..arcToPoint(
                Offset(centre.dx + s * 0.24, centre.dy - s * 0.06),
                radius: Radius.circular(s * 0.25),
              )
              ..moveTo(centre.dx - s * 0.30, centre.dy - s * 0.06)
              ..lineTo(centre.dx + s * 0.30, centre.dy - s * 0.06)
              ..moveTo(centre.dx, centre.dy + s * 0.06)
              ..lineTo(centre.dx, centre.dy + s * 0.16);
            alarmMarks.addOval(Rect.fromCircle(
              center: centre.translate(0, s * 0.22),
              radius: s * 0.06,
            ));
          case HexType.thatch:
            // Two crossing strands; a tick once she has been — it remembers.
            thatchMarks
              ..moveTo(centre.dx - s * 0.3, centre.dy - s * 0.1)
              ..lineTo(centre.dx + s * 0.3, centre.dy + s * 0.1)
              ..moveTo(centre.dx + s * 0.3, centre.dy - s * 0.1)
              ..lineTo(centre.dx - s * 0.3, centre.dy + s * 0.1);
            if (cell.crossed) {
              thatchCrossed.addOval(Rect.fromCircle(
                center: centre.translate(0, -s * 0.24),
                radius: s * 0.07,
              ));
            }
          case HexType.scaffold:
            // A fuse running through a row of powder dots.
            for (var i = -1; i <= 1; i++) {
              scaffoldMarks.addOval(Rect.fromCircle(
                center: centre.translate(s * 0.26 * i, 0),
                radius: s * 0.055,
              ));
            }
            scaffoldMarks
              ..moveTo(centre.dx - s * 0.26, centre.dy + s * 0.14)
              ..lineTo(centre.dx + s * 0.26, centre.dy + s * 0.14);
          default:
            break; // plain, heavy, anchor, spring, fault, slope, sunken carry theirs above
        }
      }
    }

    // Foxfire is the one tile allowed to glow while solid: it promises light.
    if (foxfireGlow.computeMetrics().isNotEmpty) {
      _fill
        ..color = Palette.foxfireGlow.withValues(alpha: 0.16)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, layout.size * 0.5);
      canvas.drawPath(foxfireGlow, _fill);
      _fill.maskFilter = null;
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

    // The new fields' marks. Every one is drawn with the same discipline as
    // the rivet: a shape, in the type's edge hue, never the colour alone.
    _fill.color = Palette.mireEdge.withValues(alpha: 0.45);
    canvas.drawPath(mireMarks, _fill);

    _stroke
      ..color = Palette.thicketEdge.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(thicketMarks, _stroke);

    _stroke
      ..color = Palette.sleeperEdge.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    canvas.drawPath(sleeperMarks, _stroke);

    _fill.color = Palette.foxfireEdge.withValues(alpha: 0.95);
    canvas.drawPath(foxfireMarks, _fill);

    _stroke
      ..color = Palette.iceEdge.withValues(alpha: 0.55)
      ..strokeWidth = 1.3;
    canvas.drawPath(iceMarks, _stroke);

    _stroke
      ..color = Palette.eddyEdge.withValues(alpha: 0.85)
      ..strokeWidth = 1.7;
    canvas.drawPath(eddyMarks, _stroke);

    _stroke
      ..color = Palette.magnetEdge.withValues(alpha: 0.85)
      ..strokeWidth = 1.6;
    canvas.drawPath(magnetMarks, _stroke);

    _stroke
      ..color = Palette.hardpanEdge.withValues(alpha: 0.9)
      ..strokeWidth = 2.1;
    canvas.drawPath(hardpanMarks, _stroke);

    _stroke
      ..color = Palette.overgrowthEdge.withValues(alpha: 0.9)
      ..strokeWidth = 1.8;
    canvas.drawPath(overgrowthMarks, _stroke);

    _stroke
      ..color = Palette.tremorEdge.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    canvas.drawPath(tremorMarks, _stroke);

    _stroke
      ..color = Palette.gateEdge.withValues(alpha: 0.9)
      ..strokeWidth = 1.7;
    canvas.drawPath(gateMarks, _stroke);

    _fill.color = Palette.switchEdge.withValues(alpha: 0.85);
    canvas.drawPath(switchMarks, _fill);

    _fill.color = Palette.mirrorEdge.withValues(alpha: 0.30);
    canvas.drawPath(mirrorMarks, _fill);
    // Charged halves burn brighter — the pair agreeing reads at a glance.
    _fill.color = Palette.mirrorEdge.withValues(alpha: 0.9);
    canvas.drawPath(mirrorChargedMarks, _fill);

    _fill.color = Palette.thornEdge.withValues(alpha: 0.85);
    canvas.drawPath(thornFills, _fill);

    _stroke
      ..color = Palette.alarmEdge.withValues(alpha: 0.9)
      ..strokeWidth = 1.6;
    canvas.drawPath(alarmMarks, _stroke);

    _stroke
      ..color = Palette.thatchEdge.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    canvas.drawPath(thatchMarks, _stroke);
    _fill.color = Palette.thatchEdge.withValues(alpha: 0.9);
    canvas.drawPath(thatchCrossed, _fill);

    _stroke
      ..color = Palette.scaffoldEdge.withValues(alpha: 0.8)
      ..strokeWidth = 1.4;
    canvas.drawPath(scaffoldMarks, _stroke);

    _stroke.strokeCap = StrokeCap.butt;
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

  /// The lights (§6.1): the lit ground, then the lamp itself.
  ///
  /// The *colour of the ground* keeps only two meanings — red is where she
  /// will not go, pale is where your taps will not land — whatever the kind of
  /// lamp standing on it. The colour of the lamp is the flavour of the light,
  /// per kind, so a player can name what is coming without mistaking what it
  /// forbids.
  void _renderGuards(Canvas canvas, HexLayout layout) {
    if (game.guards.isEmpty) {
      return;
    }
    final hex = _hexFor(layout);

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
      final p = Palette.forLight(guard.kind);
      final flare = 1 + guard.alertFlash * 0.7;
      final lit = guard.lampOn ? 1.0 : 0.25;
      final pulse = 0.8 + 0.2 * math.sin(game.elapsed * 4);
      final s = layout.size;

      _fill
        ..color = p.withValues(alpha: 0.30 * pulse * lit)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.5);
      canvas.drawCircle(centre, s * 0.75 * flare, _fill);
      _fill.maskFilter = null;

      switch (guard.kind) {
        case GuardKind.beacon:
          // A standing lantern: post, glow, cap. The first light whose red
          // ground is *announced* safe — the lesson the patrol phase taught
          // is "red is where she will not go", not "red is danger".
          _fill.color = p.withValues(alpha: 0.9 * lit);
          canvas.drawRect(
            Rect.fromCenter(center: centre, width: s * 0.22, height: s * 0.72),
            _fill,
          );
          _fill.color = Palette.beaconGlow.withValues(alpha: 0.7 * lit);
          canvas.drawRect(
            Rect.fromCenter(
              center: centre.translate(0, -s * 0.16),
              width: s * 0.12,
              height: s * 0.24,
            ),
            _fill,
          );
          _stroke
            ..color = p
            ..strokeWidth = 1.6;
          canvas.drawLine(
            centre.translate(-s * 0.2, s * 0.38),
            centre.translate(s * 0.2, s * 0.38),
            _stroke,
          );
        case GuardKind.spinner:
          // A vane with four blades, turning at its own lean — the beat shown
          // on the handle, so the endpoint orbit needs no watching.
          canvas.save();
          canvas.translate(centre.dx, centre.dy);
          canvas.rotate(guard.leadAngle);
          for (var i = 0; i < 4; i++) {
            canvas.rotate(math.pi / 2);
            _stroke
              ..color = p.withValues(alpha: 0.9 * lit)
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round;
            canvas.drawLine(Offset.zero, Offset(s * 0.30, 0), _stroke);
          }
          _stroke.strokeCap = StrokeCap.butt;
          _fill.color = Palette.background;
          canvas.drawCircle(Offset.zero, s * 0.10, _fill);
          canvas.restore();
        case GuardKind.runner:
          // A dash: the comma of a lamp, thrown. The helium it promises shows
          // in the trail of after-images behind it.
          for (var i = 1; i <= 2; i++) {
            _fill.color = p.withValues(alpha: 0.16 / i * lit);
            canvas.drawOval(
              Rect.fromCenter(
                center: centre - guard.velocityIn(layout) * (0.055 * i),
                width: s * 0.5,
                height: s * 0.26,
              ),
              _fill,
            );
          }
          _fill.color = p.withValues(alpha: 0.95 * lit);
          canvas.drawOval(
            Rect.fromCenter(center: centre, width: s * 0.56, height: s * 0.30),
            _fill,
          );
        case GuardKind.blinker:
          // The only lamp whose *absence* is announced: a lamp with a shutter,
          // ringed by the tick marks it will keep time to.
          _fill.color = p.withValues(alpha: 0.9 * lit);
          canvas.drawOval(
            Rect.fromCenter(center: centre, width: s * 0.6, height: s * 0.36),
            _fill,
          );
          for (var i = -1; i <= 1; i++) {
            final a = i * 0.9 - math.pi / 2;
            _stroke
              ..color = p.withValues(alpha: 0.6 * lit)
              ..strokeWidth = 1.3;
            canvas.drawLine(
              centre + Offset(math.cos(a), math.sin(a)) * s * 0.34,
              centre + Offset(math.cos(a), math.sin(a)) * s * 0.46,
              _stroke,
            );
          }
        case GuardKind.warden:
          // The big eye, unhurried and shortly followed by the floor changing.
          // A doubled rim so it reads as the basilisk of the set.
          _fill.color = p.withValues(alpha: 0.9 * lit);
          canvas.drawOval(
            Rect.fromCenter(center: centre, width: s * 0.78, height: s * 0.46),
            _fill,
          );
          _stroke
            ..color = p.withValues(alpha: 0.85 * lit)
            ..strokeWidth = 1.8;
          canvas.drawOval(
            Rect.fromCenter(center: centre, width: s * 0.94, height: s * 0.56),
            _stroke,
          );
          _fill.color = Palette.background;
          canvas.drawCircle(centre, s * 0.15, _fill);
        case GuardKind.patrol:
        case GuardKind.sentry:
          // An eye rather than a person: it is a light, and a body would
          // suggest it could be walked around.
          _fill.color = p.withValues(alpha: 0.9);
          canvas.drawOval(
            Rect.fromCenter(
              center: centre,
              width: s * 0.66 * flare,
              height: s * 0.40 * flare,
            ),
            _fill,
          );
          _fill.color = Palette.background;
          canvas.drawCircle(centre, s * 0.13 * flare, _fill);
          // A sentry carries a bar through its pupil — the "no" the colour
          // would otherwise carry alone.
          if (guard.kind == GuardKind.sentry) {
            _stroke
              ..color = p
              ..strokeWidth = 1.6;
            canvas.drawLine(
              centre.translate(-s * 0.30, 0),
              centre.translate(s * 0.30, 0),
              _stroke,
            );
          }
      }
    }
  }

  /// Lamps planted by the BEACON charge: a small glow holding ground known.
  ///
  /// Drawn after the fog, with the pickups — a lamp exists precisely because
  /// the dark is the opponent, and dimming the answer with the question would
  /// be absurd.
  void _renderLamps(Canvas canvas, HexLayout layout) {
    for (final coord in game.beaconsLit) {
      final centre = layout.toPixel(coord);
      final s = layout.size;
      final breathe = 0.85 + 0.15 * math.sin(game.elapsed * 2.2 + coord.q);
      _fill
        ..color = Palette.lampGlow.withValues(alpha: 0.16 * breathe)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.5);
      canvas.drawCircle(centre, s * ActiveEffects.beaconRadius * 1.1, _fill);
      _fill.maskFilter = null;
      _fill.color = Palette.lampGlow.withValues(alpha: 0.9);
      canvas.drawCircle(centre, s * 0.10, _fill);
      _stroke
        ..color = Palette.lampGlow.withValues(alpha: 0.7)
        ..strokeWidth = 1.4;
      canvas.drawCircle(centre, s * 0.22, _stroke);
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

  // The palette answers the top and edge of every tile itself; the skirt is
  // the top drawn through shadow, derived the same way everywhere so the fake
  // depth keeps coming from one direction of light.
  static Color _topOf(HexType type) => Palette.forHex(type);

  static Color _sideOf(HexType type) =>
      Color.lerp(Palette.forHex(type), const Color(0xFF05070F), 0.42)!;

  static Color _edgeOf(HexType type) => Palette.edgeOf(type);

  /// Darkness away from the dog: one gradient drawn over the finished board.
  ///
  /// Gloom levels double the penalty of being away from her, so the pool of
  /// light shrinks to the ring nearest the eye. Night eyes undo the doubling —
  /// the fog stays her own size, the board stops pretending otherwise.
  void _renderLight(Canvas canvas, HexLayout layout) {
    if (!game.tuning.fogEnabled) {
      return;
    }
    final gloom = game.tuning.gloomEnabled &&
        !game.powerups.hasPassive(PickupKind.nightEyes);
    final reach = game.revealRadius;
    final centre = game.dog.position + game.juice.offset;
    final size = game.size;
    _fill.shader = Gradient.radial(
      centre,
      reach * (gloom ? 1.7 : 2.4),
      [
        const Color(0x00000000),
        Palette.background.withValues(alpha: gloom ? 0.72 : 0.55),
      ],
      gloom ? const [0.30, 1.0] : const [0.35, 1.0],
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
