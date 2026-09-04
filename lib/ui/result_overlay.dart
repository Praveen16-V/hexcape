import 'package:flutter/material.dart';

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
    super.key,
  });

  final HexcapeGame game;

  /// Back to the campaign map.
  final VoidCallback onMap;

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
    final finishedCampaign = won && game.isFinalLevel;

    final (title, blurb) = switch (game.phase) {
      // The one ending the game has. Sixty levels deserve more than the same
      // word that follows every other one of them.
      GamePhase.won when finishedCampaign => (
        Strings.campaignDone,
        Strings.campaignDoneHint,
      ),
      GamePhase.won => (Strings.levelComplete, null),
      // In endless a loss ends the *run*, which is the thing being scored.
      // Calling it "boxed in" describes the last board and buries the number
      // the player was actually playing for.
      _ when endless => (
        Strings.runEnded,
        'She got to depth ${game.depth}.',
      ),
      GamePhase.crushed => (Strings.crushed, Strings.crushedHint),
      GamePhase.starved => (Strings.starved, Strings.starvedHint),
      GamePhase.softLocked =>
        game.lockedByBudget
            ? (Strings.outOfTaps, Strings.outOfTapsHint)
            : (Strings.softLocked, Strings.softLockedHint),
      _ => ('', null),
    };

    return Align(
      alignment: Alignment.bottomCenter,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
          decoration: const BoxDecoration(
            color: Color(0xF2121826),
            border: Border(top: BorderSide(color: Palette.plainEdge)),
          ),
          child: SafeArea(
            top: false,
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
                    style: const TextStyle(color: Palette.hudDim, fontSize: 13),
                  ),
                ],
                if (won) ...[
                  const SizedBox(height: 14),
                  _Stars(count: game.stars),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (endless)
                      _Metric(
                        label: Strings.reached,
                        value: 'D${game.depth}',
                      ),
                    if (endless)
                      _Metric(
                        label: Strings.deepest,
                        value: 'D${_bestDepth(game)}',
                      ),
                    _Metric(label: Strings.tapsUsed, value: '${game.taps}'),
                    if (!endless) _Metric(label: Strings.par, value: '${game.par}'),
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
                        label: Strings.retry,
                        primary: true,
                        onPressed: game.retry,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Button(
                        // Onward on a win, reroll on a loss — the button that
                        // moves you forward should never be the one you reach
                        // for after failing. Endless is the exception: a run is
                        // the unit there, so the way forward from a loss is a
                        // fresh run rather than the same board again.
                        label: finishedCampaign
                            ? Strings.enterEndless
                            : endless && !won
                            ? Strings.newRun
                            : won
                            ? Strings.nextLevel
                            : Strings.newLevel,
                        onPressed: endless && !won
                            ? game.startEndlessRun
                            : won
                            ? game.nextLevel
                            : game.regenerate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
