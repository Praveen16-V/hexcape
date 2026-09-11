import 'dart:typed_data';
import 'dart:ui';

import '../../gen/silhouette.dart';
import '../../hex/hex_layout.dart';

/// The outline of a level's board, small enough to sit inside one map tile.
///
/// Every generated board is cut to one of twelve silhouettes — a bone, a fish,
/// a paw, a key — and until now the only place that was ever said out loud was
/// one line on the detail sheet. On the map it does the work that a hundred
/// numbers cannot: level 27 stops being "the one after 26" and becomes the one
/// cut to a key.
///
/// Cheap by construction. Twelve paths, each built once on first use and then
/// only ever transformed into place, so a tile costs an `addPath` rather than
/// a shape computation. The outlines come from [shaped] — the same public
/// function the generator uses — so the glyph really is a miniature of the
/// board it names, and stays one if the masks are ever redrawn.
class SilhouetteGlyphs {
  const SilhouetteGlyphs._();

  /// Sampling resolution. Fine enough for a bone to read as a bone at 40 px,
  /// coarse enough that the union of cells stays a clean blob rather than a
  /// gravel path.
  static const _columns = 9;
  static const _rows = 13;

  static final Map<FieldShape, Path> _cache = {};

  /// The silhouette as a path inside a 1×1 box centred on the origin.
  static Path unitGlyphFor(FieldShape shape) => _cache[shape] ??= _build(shape);

  static Path _build(FieldShape shape) {
    final cells = shaped(shape: shape, columns: _columns, rows: _rows);
    // Unit layout: the cells tile exactly, so filling their union with the
    // default non-zero winding gives one solid blob rather than a honeycomb.
    const layout = HexLayout(size: 1, origin: Offset.zero);
    final hex = HexLayout.pathFromCorners(HexLayout.cornersAt(Offset.zero, 1));
    final blob = Path();
    for (final cell in cells) {
      blob.addPath(hex, layout.toPixel(cell));
    }
    if (cells.isEmpty) {
      return blob;
    }
    final bounds = blob.getBounds();
    final span = bounds.longestSide;
    if (span <= 0) {
      return blob;
    }
    // Centre on the origin, then scale the longer axis down to 1.
    final scale = 1 / span;
    return blob.transform(
      _matrix(
        scale: scale,
        dx: -bounds.center.dx * scale,
        dy: -bounds.center.dy * scale,
      ),
    );
  }

  /// Places the unit glyph on a tile: scaled to [size] across, centred on
  /// [centre].
  static Float64List placement(Offset centre, double size) =>
      _matrix(scale: size, dx: centre.dx, dy: centre.dy);

  /// A column-major 4×4 of a uniform scale followed by a translation.
  ///
  /// Written out rather than pulled from a matrix library because that is all
  /// this needs, and `Path.transform` wants the sixteen doubles either way.
  static Float64List _matrix({
    required double scale,
    required double dx,
    required double dy,
  }) => Float64List.fromList(<double>[
    scale, 0, 0, 0, //
    0, scale, 0, 0,
    0, 0, 1, 0,
    dx, dy, 0, 1,
  ]);
}
