import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/difficulty.dart';
import '../game/entitlements.dart';
import '../game/haptics.dart';
import '../game/level_rules.dart';
import '../game/pets.dart';
import '../game/progress.dart';
import '../l10n/strings.dart';
import '../theme/palette.dart';
import 'campaign/chapter_header.dart';
import 'campaign/map_geometry.dart';
import 'campaign/map_layout.dart';
import 'campaign/map_painter.dart';
import 'home_dog.dart';

export 'campaign/map_layout.dart' show MapLayout;

/// The campaign map (§12.1).
///
/// A hundred levels as one continuous trail carved through a hex field, in
/// chapters. The page it replaces drew them as a hundred and one identical
/// **circles** on a five-per-row snake, which made level 12 and level 47 the
/// same picture with a different number on it, and which showed progress as
/// three grey dots under three millimetres across.
///
/// Three ideas carry the redesign:
///
/// * **The map is made of the board.** A level you have beaten is an open pit,
///   a level ahead of you is solid rock in its chapter's colour, and a level
///   behind the paywall is riveted. The player learned that vocabulary in the
///   first three levels; the map had been ignoring it.
/// * **Every level looks like itself.** Each tile carries the silhouette its
///   board is actually cut to, so the map has a bone in it, and a key, and a
///   fish — see [SilhouetteGlyphs].
/// * **Chapters, not a scroll.** Six bands with real headings and a rail to
///   jump between them, instead of one twenty-one-row grid with a tint change
///   in the middle of it.
class LevelMap extends StatefulWidget {
  const LevelMap({
    required this.progress,
    required this.onSelect,
    required this.onBack,
    required this.showToken,
    super.key,
  });

  final Progress progress;
  final ValueChanged<int> onSelect;
  final VoidCallback onBack;

  /// Bumped by the shell every time the map is opened, which is the cue to
  /// bring the frontier back into view.
  final int showToken;

  @override
  State<LevelMap> createState() => _LevelMapState();
}

class _LevelMapState extends State<LevelMap> {
  ScrollController? _scroll;
  int _scrolledToken = -1;
  double _builtWidth = 0;
  double _builtScale = 0;
  MapGeometry? _geometry;

  /// The chapter currently under the eye, which is not the same question as
  /// which chapter holds the frontier. Held as a notifier so that scrolling
  /// rebuilds the rail and nothing else.
  final ValueNotifier<CampaignBand> _visible = ValueNotifier(
    CampaignBand.tutorial,
  );

  @override
  void dispose() {
    _scroll?.dispose();
    _visible.dispose();
    super.dispose();
  }

  void _trackVisibleBand() {
    final controller = _scroll;
    final geometry = _geometry;
    if (controller == null || geometry == null || !controller.hasClients) {
      return;
    }
    // A chapter counts as the one you are reading once its header has passed
    // the top of the viewport, which is where its tiles begin.
    final offset = controller.offset + geometry.headerExtent;
    var found = CampaignBand.values.first;
    for (final band in CampaignBand.values) {
      if (geometry.offsetOf(Campaign.firstOf(band)) <= offset) {
        found = band;
      }
    }
    _visible.value = found;
  }

  int get _frontier => math.min(widget.progress.unlocked, MapLayout.tiles);

  /// Creates the controller already pointing at the frontier.
  ///
  /// Deliberately an `initialScrollOffset` rather than a jump afterwards: the
  /// page this replaced painted the top of the map on its first frame and then
  /// snapped, because the only way it knew where to go was a post-frame
  /// callback. Here the offset is closed-form, so the first frame is already
  /// right.
  ScrollController _controllerFor(MapGeometry geometry, double viewport) {
    final target = geometry.offsetOf(_frontier) - viewport * 0.42;
    final max = math.max(0.0, geometry.totalExtent - viewport);
    return ScrollController(initialScrollOffset: target.clamp(0.0, max));
  }

  void _revealFrontier(MapGeometry geometry, double viewport) {
    final controller = _scroll;
    if (controller == null || !controller.hasClients) {
      return;
    }
    final max = math.max(0.0, geometry.totalExtent - viewport);
    controller.animateTo(
      (geometry.offsetOf(_frontier) - viewport * 0.42).clamp(0.0, max),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToBand(CampaignBand band, MapGeometry geometry, double viewport) {
    final controller = _scroll;
    if (controller == null || !controller.hasClients) {
      return;
    }
    final max = math.max(0.0, geometry.totalExtent - viewport);
    Haptics.selection();
    controller.animateTo(
      geometry.offsetOf(Campaign.firstOf(band)).clamp(0.0, max),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutCubic,
    );
  }

  void _select(int level) {
    Haptics.selection();
    widget.onSelect(level);
  }

  int _starsIn(CampaignBand band) {
    if (band == CampaignBand.endless) {
      return 0;
    }
    final range = MapLayout.levelsOf(band);
    var total = 0;
    for (var level = range.first; level <= range.last; level++) {
      total += widget.progress.recordFor(level).stars;
    }
    return total;
  }

  int _clearedIn(CampaignBand band) {
    if (band == CampaignBand.endless) {
      return 0;
    }
    final range = MapLayout.levelsOf(band);
    var total = 0;
    for (var level = range.first; level <= range.last; level++) {
      if (widget.progress.recordFor(level).stars > 0) {
        total++;
      }
    }
    return total;
  }

  int get _hardClears {
    var total = 0;
    for (var level = 1; level <= Campaign.length; level++) {
      final record = widget.progress.recordFor(level);
      if (record.stars > 0 && record.difficulty == Difficulty.hard) {
        total++;
      }
    }
    return total;
  }

  /// The band holding the one free look, if it is still unspent.
  CampaignBand? get _trialBand {
    if (widget.progress.ownsFullGame || widget.progress.trialUsed) {
      return null;
    }
    for (final band in CampaignBand.values) {
      final range = MapLayout.levelsOf(band);
      for (var level = range.first; level <= range.last; level++) {
        final access = Entitlements.accessTo(
          level,
          unlocked: widget.progress.unlocked,
          owned: widget.progress.ownsFullGame,
          trialUsed: widget.progress.trialUsed,
          unlockAll: widget.progress.unlockAllLevels,
        );
        if (access == LevelAccess.trial) {
          return band;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final pet = Pets.byId(
      widget.progress.pet,
      stars: widget.progress.totalStars,
    );
    final trialBand = _trialBand;

    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final geometry = MapGeometry.fit(
              width: constraints.maxWidth,
              textScale: scale,
            );
            _geometry = geometry;
            // The viewport is what is left once the fixed chrome has taken its
            // share. Approximated rather than measured because it only ever
            // feeds a scroll offset, and being a few pixels out there is
            // invisible.
            final viewport = math.max(120.0, constraints.maxHeight - 208);

            final changed =
                _builtWidth != constraints.maxWidth || _builtScale != scale;
            if (_scroll == null || changed) {
              // A resize or rotation moves every offset on the page, so the
              // controller is rebuilt around the new geometry rather than left
              // pointing at a position that no longer means anything. The old
              // page never re-centred at all.
              final previous = _scroll;
              _scroll = _controllerFor(geometry, viewport)
                ..addListener(_trackVisibleBand);
              _builtWidth = constraints.maxWidth;
              _builtScale = scale;
              _scrolledToken = widget.showToken;
              if (previous != null) {
                previous.removeListener(_trackVisibleBand);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => previous.dispose(),
                );
              }
              _visible.value = Campaign.bandOf(_frontier);
            } else if (_scrolledToken != widget.showToken) {
              _scrolledToken = widget.showToken;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _revealFrontier(geometry, viewport),
              );
            }

            return Column(
              children: [
                _CampaignBar(
                  progress: widget.progress,
                  frontier: _frontier,
                  hardClears: _hardClears,
                  onBack: widget.onBack,
                ),
                ValueListenableBuilder<CampaignBand>(
                  valueListenable: _visible,
                  builder: (context, current, _) => _BandRail(
                    current: current,
                    starsIn: _starsIn,
                    onTap: (band) => _jumpToBand(band, geometry, viewport),
                  ),
                ),
                Expanded(
                  child: CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      for (final band in CampaignBand.values) ...[
                        // Deliberately not pinned. Seven pinned headers stack:
                        // by the time you are in Mastery, four of them are
                        // parked at the top eating three hundred pixels of a
                        // phone screen, and the map is a letterbox. The band
                        // rail above carries "which chapter am I in" instead,
                        // and it tracks the scroll rather than the frontier.
                        SliverPersistentHeader(
                          delegate: ChapterHeader(
                            band: band,
                            extent: geometry.headerExtent,
                            stars: _starsIn(band),
                            maxStars: band == CampaignBand.endless
                                ? 0
                                : (MapLayout.levelsOf(band).last -
                                          MapLayout.levelsOf(band).first +
                                          1) *
                                      3,
                            cleared: _clearedIn(band),
                            levels: MapLayout.levelsOf(band),
                            showTrial: trialBand == band,
                            onTrial: () {
                              final range = MapLayout.levelsOf(band);
                              _select(range.first);
                            },
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _Chapter(
                            band: band,
                            geometry: geometry,
                            progress: widget.progress,
                            frontier: _frontier,
                            labelScale: clampLabelScale(scale),
                            pet: pet,
                            onSelect: _select,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _ContinueBar(
                  frontier: _frontier,
                  onTap: () => _select(_frontier),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One chapter's canvas, plus the dog when this is the chapter she is standing
/// in.
///
/// A sliver each rather than one canvas for the whole campaign, which is what
/// makes viewport culling structural: a chapter outside the cache extent is
/// never painted, and the worst case on screen is about forty tiles instead of
/// a hundred and one.
class _Chapter extends StatelessWidget {
  const _Chapter({
    required this.band,
    required this.geometry,
    required this.progress,
    required this.frontier,
    required this.labelScale,
    required this.pet,
    required this.onSelect,
  });

  final CampaignBand band;
  final MapGeometry geometry;
  final Progress progress;
  final int frontier;
  final double labelScale;
  final Pet pet;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final layout = geometry.layoutFor(band);
    final model = ChapterModel.of(band, progress, frontier: frontier);
    final holdsDog = Campaign.bandOf(frontier) == band;
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    return SizedBox(
      height: geometry.extentOf(band),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTapUp: (details) {
                  final level = MapLayout.levelAt(
                    details.localPosition,
                    layout,
                  );
                  // A tap within half a hex of a seam can name a level from the
                  // chapter next door; that chapter's own canvas owns it.
                  if (level != null && Campaign.bandOf(level) == band) {
                    onSelect(level);
                  }
                },
                child: CustomPaint(
                  painter: ChapterPainter(
                    model: model,
                    layout: layout,
                    labelStyle: base,
                    labelScale: labelScale,
                    onSelect: onSelect,
                    showGlyphs: geometry.hex >= 26,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          if (holdsDog)
            _FrontierDog(
              centre: layout.toPixel(MapLayout.coordFor(frontier)),
              hex: geometry.hex,
              pet: pet,
              reducedMotion: progress.reducedMotion,
            ),
        ],
      ),
    );
  }
}

/// Where you are, drawn as who you are.
///
/// A widget over the canvas rather than a figure inside it, and that is a
/// performance decision as much as a visual one: it leaves the chapter canvas
/// with nothing to animate, so it repaints when progress changes and not
/// otherwise. The page this replaced ran an 1800 ms controller over the whole
/// board forever to pulse one blurred halo, laying out every level number again
/// on every frame of it.
class _FrontierDog extends StatelessWidget {
  const _FrontierDog({
    required this.centre,
    required this.hex,
    required this.pet,
    required this.reducedMotion,
  });

  final Offset centre;
  final double hex;
  final Pet pet;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final size = hex * 1.5;
    return Positioned(
      left: centre.dx - size / 2,
      // Her feet land a little above the tile's middle, so she stands on the
      // face of it rather than straddling its lower edge.
      top: centre.dy - size * 0.74,
      width: size,
      height: size,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: HomeDog(pet: pet, size: size, reducedMotion: reducedMotion),
        ),
      ),
    );
  }
}

/// The rail that makes a hundred levels navigable.
///
/// The page this replaced had no way to move about it at all: finding level
/// three from level ninety was a thumb and a long scroll.
class _BandRail extends StatelessWidget {
  const _BandRail({
    required this.current,
    required this.starsIn,
    required this.onTap,
  });

  final CampaignBand current;
  final int Function(CampaignBand) starsIn;
  final ValueChanged<CampaignBand> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final band in CampaignBand.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _BandChip(
                band: band,
                selected: band == current,
                stars: starsIn(band),
                onTap: () => onTap(band),
              ),
            ),
        ],
      ),
    );
  }
}

class _BandChip extends StatelessWidget {
  const _BandChip({
    required this.band,
    required this.selected,
    required this.stars,
    required this.onTap,
  });

  final CampaignBand band;
  final bool selected;
  final int stars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = Palette.forBand(band);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Jump to ${band.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: selected ? 0.22 : 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colour.withValues(alpha: selected ? 0.9 : 0.28),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            band.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colour,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _CampaignBar extends StatelessWidget {
  const _CampaignBar({
    required this.progress,
    required this.frontier,
    required this.hardClears,
    required this.onBack,
  });

  final Progress progress;
  final int frontier;
  final int hardClears;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 21),
                color: Palette.hudText,
                tooltip: 'Home',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  Strings.campaignTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Three labelled facts instead of one bar that plotted how far you had
          // walked beside a number counting how well you had walked it.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _Stat(
                  label: Strings.campaignCleared,
                  value: '${progress.completedLevels}/${Campaign.length}',
                  colour: Palette.hudText,
                ),
                _Stat(
                  label: Strings.campaignMastered,
                  value: '${progress.masteredLevels}',
                  colour: Palette.bandVigil,
                ),
                _Stat(
                  label: Strings.campaignStars,
                  value: '${progress.totalStars}/${Campaign.length * 3}',
                  colour: Palette.goalGlow,
                ),
                if (hardClears > 0)
                  _Stat(
                    label: Strings.campaignHard,
                    value: '$hardClears',
                    colour: Palette.dogBody,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.colour});

  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Palette.hudDim,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              value,
              style: TextStyle(
                color: colour,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.frontier, required this.onTap});

  final int frontier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final band = Campaign.bandOf(frontier);
    final colour = Palette.forBand(band);
    final title = frontier > Campaign.length
        ? 'ENDLESS TRAIL'
        : Campaign.identityFor(frontier).title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Material(
        color: Palette.plainTop,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: colour, width: 3)),
            ),
            child: Row(
              children: [
                Icon(Icons.play_arrow_rounded, size: 20, color: colour),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CONTINUE · LEVEL $frontier',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Palette.hudText.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: Palette.hudDim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
