import 'package:flutter/material.dart';

import '../../game/level_rules.dart';
import '../../l10n/strings.dart';
import '../../theme/palette.dart';

/// The heading a chapter of the campaign opens with.
///
/// The map this replaced had band "headers" that were ten-pixel words painted
/// into a thirty-pixel gutter *by the canvas*, last, on top of the tiles they
/// named — and two of them, Learning and Foundation, were painted at one
/// identical point because both bands began on row zero. Making a header a real
/// widget in its own sliver fixes all of that by construction: it cannot
/// overlap a tile, it cannot collide with another header, it scales with the
/// system text size, and a screen reader can find it.
///
/// Pinned, with one extent, because [MapGeometry.offsetOf] needs a chapter's
/// height to be knowable before anything is laid out.
class ChapterHeader extends SliverPersistentHeaderDelegate {
  const ChapterHeader({
    required this.band,
    required this.extent,
    required this.stars,
    required this.maxStars,
    required this.cleared,
    required this.levels,
    required this.showTrial,
    required this.onTrial,
  });

  final CampaignBand band;
  final double extent;
  final int stars;
  final int maxStars;
  final int cleared;
  final ({int first, int last}) levels;

  /// The one free look past the paywall, advertised where it can actually be
  /// read. It used to be drawn as a tile identical to an unlocked one, which is
  /// to say advertised nowhere at all.
  final bool showTrial;
  final VoidCallback onTrial;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final colour = Palette.forBand(band);
    final range = band == CampaignBand.endless
        ? 'BEYOND ${Campaign.length}'
        : 'LEVELS ${levels.first}–${levels.last}';
    return Container(
      height: extent,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        color: Palette.background,
        border: Border(
          bottom: BorderSide(color: colour.withValues(alpha: 0.22)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The title line carries the name and the score, and nothing else.
          // The level range reads better beside the description anyway, and
          // putting it here made three pieces of unshrinkable text compete for
          // one row — which at double text size on a small phone is an
          // overflow rather than a compromise.
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    band.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colour,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.2,
                    ),
                  ),
                ),
              ),
              if (maxStars > 0) ...[
                const SizedBox(width: 8),
                Icon(Icons.circle, size: 8, color: Palette.goalGlow),
                const SizedBox(width: 5),
                Text(
                  '$stars/$maxStars',
                  maxLines: 1,
                  style: TextStyle(
                    color: Palette.goalGlow,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Flexible(
            child: Text(
              '$range · ${Strings.bandBlurb(band)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Palette.hudText.withValues(alpha: 0.75),
                fontSize: 11,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (showTrial)
            _TrialChip(onTap: onTrial)
          else if (maxStars > 0)
            // A bar per chapter, where a bar means exactly one thing. The page
            // this replaced had a single bar plotting how *far* you had walked
            // sitting beside a number counting how *well* — two questions in
            // one row, neither answered.
            _ChapterBar(
              fraction: maxStars == 0 ? 0 : stars / maxStars,
              colour: colour,
              cleared: cleared,
              total: levels.last - levels.first + 1,
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(ChapterHeader oldDelegate) =>
      oldDelegate.band != band ||
      oldDelegate.extent != extent ||
      oldDelegate.stars != stars ||
      oldDelegate.cleared != cleared ||
      oldDelegate.showTrial != showTrial;
}

class _ChapterBar extends StatelessWidget {
  const _ChapterBar({
    required this.fraction,
    required this.colour,
    required this.cleared,
    required this.total,
  });

  final double fraction;
  final Color colour;
  final int cleared;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$cleared of $total levels cleared in this chapter',
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Palette.lockedTile,
                valueColor: AlwaysStoppedAnimation(colour),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$cleared/$total',
            style: TextStyle(
              color: Palette.hudDim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrialChip extends StatelessWidget {
  const _TrialChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Palette.goalGlow.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.goalGlow.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_open_rounded, size: 12, color: Palette.goalGlow),
            const SizedBox(width: 6),
            Text(
              Strings.campaignFreeLook,
              style: TextStyle(
                color: Palette.goalGlow,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
