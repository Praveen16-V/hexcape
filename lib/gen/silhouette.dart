import 'dart:collection';
import 'dart:math' as math;

import '../hex/hex_coord.dart';

const double _sqrt3 = 1.7320508075688772;

/// The unit-space pixel centre of [c] — the layout with `size == 1` and the
/// origin at zero. Shapes are defined here rather than in screen pixels so a
/// level's silhouette is identical on every device, and a resize rescales the
/// field instead of regenerating it.
({double x, double y}) unitCentre(HexCoord c) =>
    (x: _sqrt3 * c.q + _sqrt3 / 2 * c.r, y: 1.5 * c.r);

typedef UnitBounds = ({double minX, double maxX, double minY, double maxY});

UnitBounds unitBounds(Iterable<HexCoord> coords) {
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  for (final c in coords) {
    final p = unitCentre(c);
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

/// The outlines a level can be cut to (§3.3).
///
/// Held back until solvability checking was solid, which it now thoroughly is.
/// Sixty levels of the same ellipse is the single most repetitive thing about a
/// generated campaign, and a silhouette costs nothing to vary.
enum FieldShape { ellipse, bone, fish, paw, crescent, diamond }

/// An elliptical blob [columns] hexes wide and [rows] tall.
///
/// Taller than it is wide because width is what constrains hex size on a
/// portrait phone: a circle would scale to the same hexes and leave the bottom
/// third of the screen empty.
Set<HexCoord> ellipse({required int columns, required int rows}) {
  final a = columns * _sqrt3 / 2;
  final b = rows * 1.5 / 2;
  final searchRadius = columns + rows;

  final out = <HexCoord>{};
  for (final c in HexCoord.zero.disc(searchRadius)) {
    final p = unitCentre(c);
    final nx = p.x / a;
    final ny = p.y / b;
    if (nx * nx + ny * ny <= 1.0) {
      out.add(c);
    }
  }
  return out;
}

/// The shapes, drawn where they are read.
///
/// An ASCII mask is the right representation here precisely because it is
/// legible: a bone that does not look like a bone is obvious in the source,
/// which no amount of parametric curve-fitting would be. Every mask is taller
/// than wide, matching the screen.
const _masks = <FieldShape, List<String>>{
  FieldShape.bone: [
    '.XXX...XXX.',
    'XXXXX.XXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    '.XXXXXXXXX.',
    '...XXXXX...',
    '...XXXXX...',
    '...XXXXX...',
    '...XXXXX...',
    '...XXXXX...',
    '...XXXXX...',
    '...XXXXX...',
    '...XXXXX...',
    '.XXXXXXXXX.',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXX.XXXXX',
    '.XXX...XXX.',
  ],
  FieldShape.fish: [
    '....XXX....',
    '...XXXXX...',
    '..XXXXXXX..',
    '.XXXXXXXXX.',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    '.XXXXXXXXX.',
    '.XXXXXXXXX.',
    '..XXXXXXX..',
    '..XXXXXXX..',
    '...XXXXX...',
    '...XXXXX...',
    '....XXX....',
    '.X.XXXXX.X.',
    'XXXXXXXXXXX',
    'XXX.XXX.XXX',
  ],
  FieldShape.paw: [
    '.XX.....XX.',
    'XXXX...XXXX',
    'XXXX...XXXX',
    'XXXXX.XXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    '.XXXXXXXXX.',
    '..XXXXXXX..',
    '..XXXXXXX..',
    '.XXXXXXXXX.',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    '.XXXXXXXXX.',
    '.XXXXXXXXX.',
    '..XXXXXXX..',
    '...XXXXX...',
  ],
  FieldShape.crescent: [
    '...XXXX....',
    '..XXXXXX...',
    '.XXXXXXX...',
    'XXXXXXX....',
    'XXXXXX.....',
    'XXXXX......',
    'XXXXX......',
    'XXXX.......',
    'XXXX.......',
    'XXXX.......',
    'XXXX.......',
    'XXXXX......',
    'XXXXX......',
    'XXXXXX.....',
    'XXXXXXX....',
    '.XXXXXXX...',
    '..XXXXXX...',
    '...XXXX....',
  ],
  FieldShape.diamond: [
    '.....X.....',
    '....XXX....',
    '...XXXXX...',
    '..XXXXXXX..',
    '.XXXXXXXXX.',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    'XXXXXXXXXXX',
    '.XXXXXXXXX.',
    '..XXXXXXX..',
    '...XXXXX...',
    '....XXX....',
    '.....X.....',
  ],
};

/// Cuts a field to [shape], sized to [columns] by [rows].
///
/// Always returns a **single connected region**: the mask is sampled, then only
/// the largest connected piece is kept. A shape with a detached corner would
/// otherwise generate a board with an island the dog can never reach, and no
/// amount of careful ASCII art is a substitute for guaranteeing that.
Set<HexCoord> shaped({
  required FieldShape shape,
  required int columns,
  required int rows,
}) {
  if (shape == FieldShape.ellipse) {
    return ellipse(columns: columns, rows: rows);
  }
  final mask = _masks[shape]!;
  final a = columns * _sqrt3 / 2;
  final b = rows * 1.5 / 2;
  final maskRows = mask.length;
  final maskCols = mask.first.length;

  final hit = <HexCoord>{};
  for (final c in HexCoord.zero.disc(columns + rows)) {
    final p = unitCentre(c);
    if (p.x.abs() > a || p.y.abs() > b) {
      continue;
    }
    final u = (p.x + a) / (2 * a);
    final v = (p.y + b) / (2 * b);
    final col = (u * maskCols).floor().clamp(0, maskCols - 1);
    final row = (v * maskRows).floor().clamp(0, maskRows - 1);
    if (mask[row][col] == 'X') {
      hit.add(c);
    }
  }
  return _largestRegion(hit);
}

Set<HexCoord> _largestRegion(Set<HexCoord> cells) {
  final unvisited = Set<HexCoord>.from(cells);
  var best = <HexCoord>{};
  while (unvisited.isNotEmpty) {
    final seed = unvisited.first;
    final region = <HexCoord>{seed};
    final queue = Queue<HexCoord>()..add(seed);
    unvisited.remove(seed);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final n in current.neighbours) {
        if (unvisited.remove(n)) {
          region.add(n);
          queue.add(n);
        }
      }
    }
    if (region.length > best.length) {
      best = region;
    }
  }
  return best;
}

/// Which outline a level wears.
///
/// The tutorial always gets the plain ellipse: a player learning what a tile
/// does should not also be working out why the board is fish-shaped. Everything
/// after that is chosen by seed, so a level's outline is as fixed as its layout.
FieldShape shapeFor(int level, int seed, {int tutorialBand = 5}) {
  if (level <= tutorialBand) {
    return FieldShape.ellipse;
  }
  const cycle = [
    FieldShape.ellipse,
    FieldShape.bone,
    FieldShape.diamond,
    FieldShape.fish,
    FieldShape.ellipse,
    FieldShape.paw,
    FieldShape.crescent,
    FieldShape.diamond,
  ];
  return cycle[(seed ~/ 7) % cycle.length];
}
