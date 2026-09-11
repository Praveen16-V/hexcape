import 'dart:math' as math;
import 'dart:ui';

import '../../game/level_rules.dart';
import '../../hex/hex_layout.dart';
import 'map_layout.dart';

/// Every measurement the campaign map needs, worked out once per layout pass.
///
/// A value type on purpose. The map is a scroll view of seven chapters, and
/// scrolling to a level means knowing its offset *before* anything has been
/// laid out — so the height of a chapter and the height of its header both have
/// to be closed-form functions rather than something a render object discovers.
/// That is also what lets the chapter headers be pinned slivers: a pinned
/// header has to declare one extent, and [headerExtent] is it.
class MapGeometry {
  MapGeometry._({
    required this.hex,
    required this.leftInset,
    required this.headerExtent,
  });

  /// Below this a two-digit level number stops being readable inside its tile.
  static const minHex = 22.0;

  /// Above this the map stops being a map and becomes a mile of scrolling. The
  /// old page had no ceiling at all: on a 1280 px window it drew five nodes at
  /// a 200 px pitch down four thousand pixels of canvas.
  static const maxHex = 46.0;

  static const _sidePad = 12.0;
  static const _topPad = 10.0;

  /// Circumradius of one tile — [HexLayout.size].
  final double hex;

  /// Left margin, which also centres the map when the screen is wider than the
  /// trail needs.
  final double leftInset;

  /// Height of one chapter header. Constant across chapters so [offsetOf] can
  /// stay closed-form.
  final double headerExtent;

  factory MapGeometry.fit({required double width, required double textScale}) {
    // The trail is `columnSpan` hexes wide centre to centre, plus half a hex of
    // tile either side — so `columnSpan + 1` hex widths of content.
    final usable = math.max(1.0, width - 2 * _sidePad);
    final wanted = usable / (_sqrt3 * (MapLayout.columnSpan + 1));
    final hex = wanted.clamp(minHex, maxHex);
    final content = _sqrt3 * hex * (MapLayout.columnSpan + 1);
    return MapGeometry._(
      hex: hex,
      leftInset: math.max(_sidePad, (width - content) / 2),
      // Enough for the band name, its range, its line of copy and its bar,
      // with the system text scale carried through. A pinned header declares
      // one extent and must honour it, so this is sized against the content
      // rather than guessed at.
      headerExtent: (76 + 42 * (textScale - 1)).clamp(76.0, 160.0),
    );
  }

  static const _sqrt3 = 1.7320508075688772;

  double get rowSpacing => 1.5 * hex;

  /// The depth skirt under the bottom row, matching the board's own
  /// `size * 0.26` (see `field_component.dart`).
  double get _skirt => hex * 0.26;

  /// A hex layout whose origin is already shifted so that painting a chapter
  /// can use the map's own coordinates unchanged.
  ///
  /// This is what keeps `MapLayout.levelAt(point, layout)` usable as-is inside
  /// a per-chapter canvas: the band's first row lands at y = 0 in its own
  /// sliver, and the round trip through [HexLayout.toHex] still names the right
  /// tile.
  HexLayout layoutFor(CampaignBand band) {
    final rows = MapLayout.rowsOf(band);
    return HexLayout(
      size: hex,
      origin: Offset(
        leftInset + _sqrt3 / 2 * hex,
        _topPad + hex - rows.firstRow * rowSpacing,
      ),
    );
  }

  /// How tall [band]'s canvas is.
  double extentOf(CampaignBand band) {
    final rows = MapLayout.rowsOf(band);
    final spanned = rows.lastRow - rows.firstRow;
    return _topPad + spanned * rowSpacing + 2 * hex + _skirt + _topPad;
  }

  /// Scroll offset that puts [level] at the top of the viewport.
  ///
  /// Exact, because every chapter before it contributes exactly one header and
  /// one canvas, and a pinned header's extent does not vary with scroll.
  double offsetOf(int level) {
    final band = Campaign.bandOf(level);
    var offset = 0.0;
    for (final other in CampaignBand.values) {
      if (other == band) {
        break;
      }
      offset += headerExtent + extentOf(other);
    }
    final rows = MapLayout.rowsOf(band);
    return offset +
        headerExtent +
        _topPad +
        (MapLayout.rowOf(level) - rows.firstRow) * rowSpacing;
  }

  /// Total height of the scrollable content.
  double get totalExtent => CampaignBand.values.fold(
    0.0,
    (sum, band) => sum + headerExtent + extentOf(band),
  );
}
