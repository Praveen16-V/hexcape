import 'dart:math' as math;
import 'dart:ui';

import 'hex_coord.dart';

const double _sqrt3 = 1.7320508075688772;

/// Converts between axial hex coordinates and screen pixels for a
/// **pointy-top** layout (flat sides left and right, corners top and bottom).
///
/// Pointy-top is the right choice for a portrait phone: rows stack tightly
/// vertically, so a tall silhouette wastes less screen than flat-top would.
class HexLayout {
  const HexLayout({required this.size, required this.origin});

  /// Circumradius — centre to any corner. Everything else derives from this.
  final double size;

  /// Where axial `(0, 0)` lands in pixels.
  final Offset origin;

  /// Full width of one hex (flat side to flat side).
  double get width => _sqrt3 * size;

  /// Full height of one hex (corner to corner).
  double get height => 2 * size;

  /// Vertical distance between adjacent rows.
  double get rowSpacing => 1.5 * size;

  /// Centre to the middle of an edge — the largest circle that fits inside.
  double get inradius => _sqrt3 / 2 * size;

  Offset toPixel(HexCoord c) => Offset(
    origin.dx + size * (_sqrt3 * c.q + _sqrt3 / 2 * c.r),
    origin.dy + size * (1.5 * c.r),
  );

  HexCoord toHex(Offset p) {
    final x = (p.dx - origin.dx) / size;
    final y = (p.dy - origin.dy) / size;
    return FractionalHex(_sqrt3 / 3 * x - y / 3, 2 / 3 * y).round();
  }

  /// The six corners of the hex centred at [centre], clockwise from the
  /// upper-right. Radius is scaled by [scale] so the renderer can pulse a hex
  /// without recomputing geometry.
  static List<Offset> cornersAt(
    Offset centre,
    double size, {
    double scale = 1.0,
  }) {
    final r = size * scale;
    return [
      for (var i = 0; i < 6; i++)
        Offset(
          centre.dx + r * math.cos((math.pi / 3) * i - math.pi / 6),
          centre.dy + r * math.sin((math.pi / 3) * i - math.pi / 6),
        ),
    ];
  }

  List<Offset> corners(HexCoord c, {double scale = 1.0}) =>
      cornersAt(toPixel(c), size, scale: scale);

  static Path pathFromCorners(List<Offset> corners) {
    final path = Path()..moveTo(corners[0].dx, corners[0].dy);
    for (var i = 1; i < corners.length; i++) {
      path.lineTo(corners[i].dx, corners[i].dy);
    }
    return path..close();
  }

  Path pathFor(HexCoord c, {double scale = 1.0}) =>
      pathFromCorners(corners(c, scale: scale));
}
