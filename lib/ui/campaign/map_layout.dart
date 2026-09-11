import 'dart:ui';

import '../../game/level_rules.dart';
import '../../hex/hex_coord.dart';
import '../../hex/hex_layout.dart';

/// Where each level sits on the campaign map.
///
/// The campaign is a *place*, not a list. The levels are hexes on a hex board,
/// laid out as one continuous trail, so the map is made of the same material as
/// the game — which is the whole point of it being diegetic rather than a
/// scrolling menu of buttons.
///
/// **Order is countable; the chapters are what differ.** The trail this
/// replaced ran five to a row, every row, for the whole hundred — and the
/// reason it gave was a good one:
///
/// > a wandering path looks prettier in a mock-up and is worse to use, because
/// > a player looking for level 43 has to search for it instead of counting
/// > rows.
///
/// That argument is kept. Within a row the trail still runs one way, and rows
/// still alternate, so counting works exactly as it did. What changes is that
/// the row *length* and the band of columns a chapter may use are now the
/// chapter's own, so Foundation and Vigil are visibly different stretches of
/// country instead of the same grid with a different tint. Finding level 43 is
/// counting; recognising where you are is looking.
///
/// ## How the walk is described
///
/// Everything here is done in axial coordinates and one derived integer, the
/// **half-column** `h = 2q + r`. That is exactly twice the tile's x position in
/// units of `size * sqrt3 / 2`, because [HexLayout.toPixel] places x at
/// `size * sqrt3 * (q + r/2)`. Working in `h` makes "how far left is this" a
/// plain integer comparison instead of a float, and makes the four moves the
/// walker has trivial:
///
/// | move | axial delta | Δh | Δrow |
/// |---|---|---|---|
/// | east | `(1, 0)` | +2 | 0 |
/// | west | `(-1, 0)` | −2 | 0 |
/// | drop right | `(0, 1)` | +1 | +1 |
/// | drop left | `(-1, 1)` | −1 | +1 |
///
/// `h` and `row` always share a parity — every move above preserves that — so
/// `q = (h - row) / 2` is always a whole number and never needs rounding.
class MapLayout {
  const MapLayout._();

  /// The hard left and right walls, in half-columns. Nothing may leave these,
  /// whatever a chapter's own window says, because they are what guarantees the
  /// map fits a small phone: see [columnSpan].
  static const _loH = 0;
  static const _hiH = 10;

  /// Total tiles, campaign plus the single endless gateway at the end.
  static int get tiles => Campaign.length + 1;

  /// How many hexes wide the map is, measured centre to centre.
  ///
  /// Provably five, because [_loH] and [_hiH] are walls the walker cannot pass
  /// rather than a tendency it has. The layout code sizes hexes against this,
  /// so a future change to the walk that widened it would quietly squeeze the
  /// tiles on a 320 px screen — hence the test that pins it.
  static int get columnSpan => (_hiH - _loH) ~/ 2;

  /// The columns a chapter keeps to, in half-columns.
  ///
  /// This is the whole of a band's shape on the map. Narrow reads as a
  /// corridor, wide reads as open country, and an offset window leans the
  /// chapter to one side of the screen so the seam between two bands is visible
  /// before you have read a word of the header.
  ///
  /// The walker converges on a new window rather than teleporting into it, so
  /// these do not have to be reachable in one step from each other — but
  /// neighbouring windows that overlap make for a gentler seam.
  static ({int lo, int hi}) _windowFor(CampaignBand band) => switch (band) {
    // Three guided levels, dead centre, with room on both sides: a short stub
    // of trail that visibly is not the campaign proper yet.
    CampaignBand.tutorial => (lo: 3, hi: 7),
    CampaignBand.foundation => (lo: 0, hi: 8),
    CampaignBand.pressure => (lo: 2, hi: 10),
    // Full width. Mastery is the band that uses everything taught so far, and
    // it is the widest country on the map for the same reason.
    CampaignBand.mastery => (lo: 0, hi: 10),
    CampaignBand.collapse => (lo: 0, hi: 8),
    // Narrowing again. Vigil is about waiting in a watched corridor.
    CampaignBand.vigil => (lo: 2, hi: 8),
    CampaignBand.endless => (lo: 3, hi: 7),
  };

  /// How many *further* tiles this row gets after the one just dropped onto.
  ///
  /// Zero is a jog — a single tile, then down again — and it is what keeps the
  /// trail from ruling straight lines across every chapter. Derived from the
  /// row and the band rather than a counter, so the map is the same shape for
  /// everyone and stays the same shape between builds.
  static int _runFor(int row, CampaignBand band, {required bool allowJog}) {
    final n = _mix(row * 31 + band.index * 7919);
    // A jog is rare on purpose, and never follows another one. Frequent jogs
    // read as a staircase rather than a meander, and they cost real scroll
    // height: a hundred tiles at two to a row is a page twice as long as at
    // four. [allowJog] is what enforces "never twice running" — the caller
    // refuses one when the row above was already a jog, or when this row is a
    // chapter's first and has a header sitting over it.
    if (allowJog && n % 11 == 10) {
      return 0;
    }
    return 3 + n % 3;
  }

  /// The murmur3 finaliser, masked to 32 bits at every step.
  ///
  /// Deliberately local rather than [Campaign.seedFor]: the shape of the map is
  /// a presentation decision, and coupling it to the seed that generates boards
  /// would mean a change to one silently redrew the other.
  static int _mix(int value) {
    var x = value & 0xFFFFFFFF;
    x ^= x >> 16;
    x = (x * 0x85EBCA6B) & 0xFFFFFFFF;
    x ^= x >> 13;
    x = (x * 0xC2B2AE35) & 0xFFFFFFFF;
    x ^= x >> 16;
    return x & 0x7FFFFFFF;
  }

  static bool _inside(int h, ({int lo, int hi}) window) =>
      h >= window.lo && h <= window.hi;

  /// How far [h] is from [window], zero when it is already inside.
  static int _outside(int h, ({int lo, int hi}) window) {
    if (h < window.lo) {
      return window.lo - h;
    }
    if (h > window.hi) {
      return h - window.hi;
    }
    return 0;
  }

  static List<HexCoord>? _path;
  static Map<HexCoord, int>? _byCoord;

  static void _build() {
    final path = <HexCoord>[];
    final byCoord = <HexCoord, int>{};

    // Row 0, and h must share row 0's parity. Four is the even column inside
    // the tutorial's window with the most room on either side of it.
    var h = 4;
    var row = 0;
    var heading = 1;
    var wasJog = false;
    var runLeft = _runFor(0, CampaignBand.tutorial, allowJog: false);

    void place(int level) {
      // q = (h - row) / 2, exact because h and row always share a parity.
      final coord = HexCoord((h - row) ~/ 2, row);
      path.add(coord);
      byCoord[coord] = level;
    }

    place(1);

    for (var level = 2; level <= tiles; level++) {
      final band = Campaign.bandOf(level);
      final window = _windowFor(band);
      // A chapter always starts on a row of its own. That is what makes band
      // row ranges disjoint, which in turn is what makes a chapter header a
      // thing that can sit above its own tiles without ever landing on
      // somebody else's — the failure the old map had, where Learning and
      // Foundation both began on row zero and painted their labels at one
      // identical point.
      final startsBand = level == Campaign.firstOf(band);

      var drop = startsBand || runLeft == 0;
      if (!drop) {
        final nextH = h + 2 * heading;
        // A step is allowed when it stays inside the walls and either keeps to
        // the chapter's window or is at least walking back toward it — the
        // latter is how the walker recovers after a seam has left it outside.
        final allowed =
            nextH >= _loH &&
            nextH <= _hiH &&
            (_inside(nextH, window) ||
                _outside(nextH, window) < _outside(h, window));
        drop = !allowed;
      }

      if (drop) {
        // Of the two ways down, take whichever ends up nearest the chapter's
        // window; break a tie in the direction we were already walking, which
        // is what makes an ordinary row change read as a serpentine rather
        // than as a stagger.
        var best = heading > 0 ? 1 : -1;
        var bestScore = 1 << 30;
        for (final step in const [1, -1]) {
          final candidate = h + step;
          if (candidate < _loH || candidate > _hiH) {
            continue;
          }
          final score =
              _outside(candidate, window) * 2 +
              (step == (heading > 0 ? 1 : -1) ? 0 : 1);
          if (score < bestScore) {
            bestScore = score;
            best = step;
          }
        }
        h += best;
        row++;
        // Turn into whichever half of the chapter has more room, rather than
        // simply reversing.
        //
        // Reversing is right in the middle of a row and wrong at its end, and
        // the end is where drops happen. Landing one column from the left wall
        // and dutifully turning left gives a row one tile long, then another,
        // then another — the walker ticking down the edge of the map instead of
        // crossing it. Reading the room first makes an ordinary row change a
        // serpentine and keeps a jog from stranding itself against a wall.
        final roomEast = window.hi - h;
        final roomWest = h - window.lo;
        heading = _outside(h, window) > 0
            // Still outside the new chapter's columns: walk toward them rather
            // than turning around, or the seam would zigzag on the spot.
            ? (h < window.lo ? 1 : -1)
            : roomEast == roomWest
            ? -heading
            : (roomEast > roomWest ? 1 : -1);
        runLeft = _runFor(row, band, allowJog: !wasJog && !startsBand);
        wasJog = runLeft == 0;
      } else {
        h += 2 * heading;
        runLeft--;
      }
      place(level);
    }

    _path = path;
    _byCoord = byCoord;
  }

  static List<HexCoord> get _coords {
    if (_path == null) {
      _build();
    }
    return _path!;
  }

  static Map<HexCoord, int> get _levels {
    if (_byCoord == null) {
      _build();
    }
    return _byCoord!;
  }

  static HexCoord coordFor(int level) => _coords[level - 1];

  /// The row [level] sits on, counting from the top of the map.
  static int rowOf(int level) => coordFor(level).r;

  /// How many rows the whole map occupies.
  ///
  /// Derived rather than divided. The constant this replaces was computed as
  /// `length / perRow` and was one short of the rows actually drawn, which
  /// nothing noticed because nothing read it.
  static int get rowCount => rowOf(tiles) + 1;

  /// The first and last level of [band], the endless gateway included.
  static ({int first, int last}) levelsOf(CampaignBand band) {
    final first = Campaign.firstOf(band);
    if (band == CampaignBand.endless) {
      return (first: first, last: tiles);
    }
    final next = CampaignBand.values[band.index + 1];
    return (first: first, last: Campaign.firstOf(next) - 1);
  }

  /// The rows [band] occupies. Disjoint from every other band's by
  /// construction — see the `startsBand` forced drop in [_build].
  static ({int firstRow, int lastRow}) rowsOf(CampaignBand band) {
    final levels = levelsOf(band);
    return (firstRow: rowOf(levels.first), lastRow: rowOf(levels.last));
  }

  /// The level under a point, or null if the tap missed every tile.
  ///
  /// One hex round-trip and one map lookup, rather than walking the whole trail
  /// asking each tile whether it was the one.
  static int? levelAt(Offset point, HexLayout layout) =>
      _levels[layout.toHex(point)];
}
