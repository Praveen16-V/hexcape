import 'dart:math' as math;

/// Axial coordinates `(q, r)` for a pointy-top hexagonal grid.
///
/// The implicit third cube coordinate is `s = -q - r`, which is what makes
/// distance and rounding cheap. See §13.2 of the design spec.
class HexCoord {
  const HexCoord(this.q, this.r);

  final int q;
  final int r;

  int get s => -q - r;

  static const zero = HexCoord(0, 0);

  /// The six axial direction vectors, ordered clockwise from "east".
  ///
  /// Index order matters: [neighbour] and the renderer both rely on it.
  static const directions = <HexCoord>[
    HexCoord(1, 0), // east
    HexCoord(1, -1), // north-east
    HexCoord(0, -1), // north-west
    HexCoord(-1, 0), // west
    HexCoord(-1, 1), // south-west
    HexCoord(0, 1), // south-east
  ];

  HexCoord operator +(HexCoord other) => HexCoord(q + other.q, r + other.r);

  HexCoord operator -(HexCoord other) => HexCoord(q - other.q, r - other.r);

  HexCoord neighbour(int direction) => this + directions[direction];

  List<HexCoord> get neighbours => [for (final d in directions) this + d];

  int distanceTo(HexCoord other) {
    final dq = (q - other.q).abs();
    final dr = (r - other.r).abs();
    final ds = (s - other.s).abs();
    return (dq + dr + ds) ~/ 2;
  }

  /// Every coordinate within [radius] steps, this one included.
  List<HexCoord> disc(int radius) {
    final out = <HexCoord>[];
    for (var dq = -radius; dq <= radius; dq++) {
      final lo = math.max(-radius, -dq - radius);
      final hi = math.min(radius, -dq + radius);
      for (var dr = lo; dr <= hi; dr++) {
        out.add(HexCoord(q + dq, r + dr));
      }
    }
    return out;
  }

  /// The number of cells in a disc of [radius]: `1 + 3r(r + 1)`.
  static int discSize(int radius) => 1 + 3 * radius * (radius + 1);

  @override
  bool operator ==(Object other) =>
      other is HexCoord && other.q == q && other.r == r;

  @override
  int get hashCode => Object.hash(q, r);

  @override
  String toString() => 'HexCoord($q, $r)';
}

/// A non-integral hex position, produced when converting a pixel back to the
/// grid. [round] snaps it to the nearest real cell.
class FractionalHex {
  const FractionalHex(this.q, this.r);

  final double q;
  final double r;

  double get s => -q - r;

  /// Cube rounding: round all three coordinates, then repair the one that
  /// moved furthest so the `q + r + s == 0` invariant survives.
  HexCoord round() {
    var rq = q.roundToDouble();
    var rr = r.roundToDouble();
    final rs = s.roundToDouble();

    final dq = (rq - q).abs();
    final dr = (rr - r).abs();
    final ds = (rs - s).abs();

    if (dq > dr && dq > ds) {
      rq = -rr - rs;
    } else if (dr > ds) {
      rr = -rq - rs;
    }
    return HexCoord(rq.toInt(), rr.toInt());
  }
}
