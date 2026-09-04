import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_layout.dart';

void main() {
  group('HexCoord', () {
    test('every coordinate has six distinct neighbours, all one step away', () {
      for (final c in const HexCoord(3, -2).disc(3)) {
        final neighbours = c.neighbours;
        expect(neighbours, hasLength(6));
        expect(neighbours.toSet(), hasLength(6));
        for (final n in neighbours) {
          expect(c.distanceTo(n), 1, reason: '$c -> $n');
        }
      }
    });

    test('cube coordinates always sum to zero', () {
      for (final c in HexCoord.zero.disc(5)) {
        expect(c.q + c.r + c.s, 0);
      }
    });

    test('distance is symmetric and zero only on itself', () {
      final coords = HexCoord.zero.disc(4);
      for (final a in coords) {
        expect(a.distanceTo(a), 0);
        for (final b in coords) {
          expect(a.distanceTo(b), b.distanceTo(a));
        }
      }
    });

    test('disc size matches the closed form used for openness', () {
      for (var r = 0; r <= 6; r++) {
        expect(HexCoord.zero.disc(r), hasLength(HexCoord.discSize(r)));
        expect(const HexCoord(-4, 7).disc(r), hasLength(HexCoord.discSize(r)));
      }
    });

    test('disc contains exactly the cells within the radius', () {
      const centre = HexCoord(2, 1);
      final disc = centre.disc(3).toSet();
      for (final c in centre.disc(6)) {
        expect(disc.contains(c), centre.distanceTo(c) <= 3, reason: '$c');
      }
    });
  });

  group('HexLayout', () {
    const layout = HexLayout(size: 19.0, origin: Offset(200, 400));

    test('pixel conversion round-trips for every cell in a wide field', () {
      for (final c in HexCoord.zero.disc(12)) {
        expect(layout.toHex(layout.toPixel(c)), c);
      }
    });

    test('an arbitrary point resolves to the hex whose centre is nearest', () {
      final rng = math.Random(7);
      for (var i = 0; i < 2000; i++) {
        final p = Offset(
          rng.nextDouble() * 800 - 200,
          rng.nextDouble() * 900 - 200,
        );
        final hit = layout.toHex(p);
        final hitDist = (layout.toPixel(hit) - p).distance;
        // No neighbouring centre may be closer than the one we picked.
        for (final other in hit.disc(2)) {
          final d = (layout.toPixel(other) - p).distance;
          expect(d, greaterThanOrEqualTo(hitDist - 1e-9), reason: '$p -> $hit');
        }
      }
    });

    test('adjacent cells sit exactly one hex width or row apart', () {
      const c = HexCoord(0, 0);
      final centre = layout.toPixel(c);
      for (final n in c.neighbours) {
        final d = (layout.toPixel(n) - centre).distance;
        expect(d, closeTo(layout.width, 1e-9));
      }
    });

    test('corners sit on the circumradius and enclose the inradius', () {
      const c = HexCoord(1, -2);
      final centre = layout.toPixel(c);
      final corners = layout.corners(c);
      expect(corners, hasLength(6));
      for (final corner in corners) {
        expect((corner - centre).distance, closeTo(layout.size, 1e-9));
      }
      expect(layout.inradius, lessThan(layout.size));
    });

    test('scaling corners scales the radius, not the shape', () {
      const c = HexCoord(0, 3);
      final centre = layout.toPixel(c);
      for (final corner in layout.corners(c, scale: 1.1)) {
        expect((corner - centre).distance, closeTo(layout.size * 1.1, 1e-9));
      }
    });
  });
}
