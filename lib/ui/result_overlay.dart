import 'package:flutter/material.dart';

import '../game/entitlements.dart';
import '../game/hexcape_game.dart';
import '../game/level_rules.dart';
import '../l10n/strings.dart';
import '../theme/palette.dart';

/// The end-of-run panel. Not a screen — it slides in over the level so retry
/// stays one tap away, which is the loop the core mechanic depends on (§14: no
/// energy, no lives, learn by failing).
class ResultOverlay extends StatefulWidget {
  const ResultOverlay({
    required this.game,
    required this.onMap,
    required this.onHome,
    required this.onUnlock,
    required this.owned,
    required this.dailyStreak,
    super.key,
  });

  final HexcapeGame game;

  /// Back to the campaign map.
  final VoidCallback onMap;
  final VoidCallback onHome;

  /// Opens the offer, on finishing the last free level.
  final VoidCallback onUnlock;

  /// Whether the full campaign is bought.
  final bool owned;

  /// The daily streak *after* this run has been recorded, so a win can name the
  /// number it just produced.
  final int dailyStreak;

  @override
  State<ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends State<ResultOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final won = game.phase == GamePhase.won;

    final endless = game.isEndless;
    final zen = game.tuning.zenMode;
    // A daily borrows an authored level's number, so every campaign milestone
    // below has to exclude it explicitly. Without this a daily drawn from level
    // 60 announces "Every level cleared", and one drawn from level 21 offers a
    // free player the trial they may already have spent.
    final daily = game.daily;
    final clearedDepth = endless
        ? (won ? game.depth : (game.depth > 1 ? game.depth - 1 : 0))
        : 0;
    final storedBest = _bestDepth(game);
    final bestDepth = clearedDepth > storedBest ? clearedDepth : storedBest;
    final finishedCampaign = won && game.isFinalLevel && daily == null;
    // The end of the free game. Framed as a milestone reached rather than a
    // wall hit — twenty levels is a whole game, and telling someone who just
    // finished one that they have run out is the wrong note entirely.
    final finishedFree =
        won &&
        !widget.owned &&
        daily == null &&
        game.levelNumber == Entitlements.freeThrough;

    // The free look past the wall, being played right now.
    //
    // Retry is deliberately still offered here, and on a loss it stays the
    // primary action. The trial exists to let someone *experience* Pressure,
    // and a player whose one look ended in a loss has experienced only the
    // loss — selling to them at that moment is both meaner and less persuasive
    // than letting them clear it first. Leaving for the map is what ends it.
    final trialRun =
        !widget.owned &&
        !endless &&
        daily == null &&
        game.levelNumber == Entitlements.trialLevel;

    final (title, blurb) = switch (game.phase) {
      GamePhase.won when zen => (
        'Practice complete',
        'Zen results are not saved. Play the scored version when you are ready.',
      ),
      GamePhase.won when endless => (
        'Depth ${game.depth} cleared',
        'Continue deeper, or begin a fresh run from depth one.',
      ),
      // The one ending the game has. Sixty levels deserve more than the same
      // word that follows every other one of them.
      GamePhase.won when finishedCampaign => (
        Strings.campaignDone,
        Strings.campaignDoneHint,
      ),
      GamePhase.won when daily != null => (
        Strings.dailyCleared,
        widget.dailyStreak > 1
            ? '${widget.dailyStreak} days in a row.'
            : 'Come back tomorrow for the next one.',
      ),
      GamePhase.won when finishedFree => (
        Strings.freeCampaignDone,
        Strings.freeCampaignDoneHint,
      ),
      GamePhase.won when trialRun => (
        Strings.trialCleared,
        Strings.trialClearedHint,
      ),
      GamePhase.won => (Strings.levelComplete, null),
      // In endless a loss ends the *run*, which is the thing being scored.
      // Calling it "boxed in" describes the last board and buries the number
      // the player was actually playing for.
      _ when endless => (
        Strings.runEnded,
        clearedDepth == 0
            ? 'No depth cleared this run.'
            : 'Cleared through depth $clearedDepth.',
      ),
      GamePhase.crushed => (Strings.crushed, Strings.crushedHint),
      GamePhase.starved => (Strings.starved, Strings.starvedHint),
      GamePhase.softLocked =>
        game.lockedByBudget
            ? (Strings.outOfTaps, Strings.outOfTapsHint)
            : (Strings.softLocked, Strings.softLockedHint),
      _ => ('', null),
    };

    late final String primaryLabel;
    late final VoidCallback primaryAction;
    String? secondaryLabel;
    VoidCallback? secondaryAction;
    if (zen) {
      primaryLabel = 'Practice again';
      primaryAction = game.retry;
      secondaryLabel = 'Play for stars';
      secondaryAction = game.startScoredRun;
    } else if (endless) {
      primaryLabel = won ? 'Continue' : Strings.newRun;
      primaryAction = won ? game.nextLevel : game.startEndlessRun;
      if (won) {
        secondaryLabel = Strings.newRun;
        secondaryAction = game.startEndlessRun;
      }
    } else if (daily != null) {
      // Neither `nextLevel` nor `regenerate` belongs here: there is exactly one
      // daily board, and both would silently replace it with something else
      // while the panel still said "daily".
      primaryLabel = won ? Strings.backToMap : Strings.retry;
      primaryAction = won ? widget.onMap : game.retry;
      if (!won) {
        secondaryLabel = Strings.backToMap;
        secondaryAction = widget.onMap;
      }
    } else if (trialRun) {
      // Never `game.nextLevel` from here. It calls `startLevel` directly and so
      // bypasses the entitlement gate entirely — offering it on a won trial
      // would hand out level 22 for nothing.
      if (won) {
        primaryLabel = Strings.seeWhatIsNext;
        primaryAction = widget.onUnlock;
        secondaryLabel = Strings.retry;
        secondaryAction = game.retry;
      } else {
        primaryLabel = Strings.retry;
        primaryAction = game.retry;
        secondaryLabel = Strings.seeWhatIsNext;
        secondaryAction = widget.onUnlock;
      }
    } else {
      primaryLabel = Strings.retry;
      primaryAction = game.retry;
      secondaryLabel = finishedFree
          ? Strings.seeWhatIsNext
          : finishedCampaign
          ? Strings.enterEndless
          : won
          ? Strings.nextLevel
          : Strings.newLevel;
      secondaryAction = finishedFree
          ? widget.onUnlock
          : won
          ? game.nextLevel
          : game.regenerate;
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic)),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
          decoration: const BoxDecoration(
            color: Color(0xF2121826),
            border: Border(top: BorderSide(color: Palette.plainEdge)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: won ? Palette.goalGlow : Palette.danger,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (blurb != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      blurb,
                      style: const TextStyle(
                        color: Palette.hudDim,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (zen || endless || daily != null) ...[
                    const SizedBox(height: 9),
                    Text(
                      zen
                          ? 'ZEN PRACTICE · NOT SAVED'
                          : daily != null
                          ? 'DAILY · ${daily.band.label.toUpperCase()} · NO STARS'
                          : 'ENDLESS RUN · NO STARS',
                      style: TextStyle(
                        color: zen
                            ? Palette.freeze
                            : daily != null
                            ? Palette.treat
                            : Palette.goalGlow,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                  if (won && !zen && !endless && daily == null) ...[
                    const SizedBox(height: 14),
                    _Stars(count: game.stars),
                    const SizedBox(height: 6),
                    Text(
                      '3 stars at ${game.starTargets.three} taps or fewer · '
                      '2 stars at ${game.starTargets.two} or fewer',
                      style: const TextStyle(
                        color: Palette.hudDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (endless)
                        _Metric(label: 'Cleared', value: 'D$clearedDepth'),
                      if (endless)
                        _Metric(label: 'Best clear', value: 'D$bestDepth'),
                      _Metric(label: Strings.tapsUsed, value: '${game.taps}'),
                      if (!endless)
                        _Metric(label: Strings.par, value: '${game.par}'),
                      _Metric(
                        label: Strings.bestChain,
                        value: '${game.streak.best}',
                      ),
                      _Metric(
                        label: Strings.timeTaken,
                        value: '${game.levelTime.toStringAsFixed(1)}s',
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _Button(
                          label: primaryLabel,
                          primary: true,
                          onPressed: primaryAction,
                        ),
                      ),
                      if (secondaryLabel != null &&
                          secondaryAction != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Button(
                            label: secondaryLabel,
                            onPressed: secondaryAction,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onHome,
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Main Menu'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Palette.hudText,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Quieter than the other two, and always present. Leaving is
                  // never the thing the panel is pushing you toward, but a player
                  // who wants out of a level they keep losing should not have to
                  // win it first.
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: widget.onMap,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.5),
                      ),
                      child: const Text(
                        Strings.backToMap,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int _bestDepth(HexcapeGame game) {
  final best = game.progress?.endlessBest ?? 0;
  return best > Campaign.length ? best - Campaign.length : 0;
}

/// Stars come from taps, not time (§12.4) — efficient carving is the skill,
/// and rating on the clock would just reward panic-tapping.
class _Stars extends StatelessWidget {
  const _Stars({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(
              i < count ? Icons.star_rounded : Icons.star_outline_rounded,
              color: i < count ? Palette.goalGlow : Palette.hudDim,
              size: 30,
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Palette.hudDim,
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Palette.hudText,
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: primary ? Palette.dogBody : Palette.plainTop,
        foregroundColor: primary ? const Color(0xFF1A1008) : Palette.hudText,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}
