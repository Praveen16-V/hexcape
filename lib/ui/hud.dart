import 'package:flutter/material.dart';

import '../game/hexcape_game.dart';
import '../l10n/strings.dart';
import '../entities/pickup.dart';
import '../theme/palette.dart';

/// Taps, par and the clock, plus the one-idea-at-a-time onboarding line.
///
/// Kept plain and fast per §12.2 — over-styling a utility surface only adds
/// friction. It rebuilds on a ticker because the values behind it change every
/// frame inside the game loop, not in Flutter state.
class Hud extends StatefulWidget {
  const Hud({required this.game, super.key});

  final HexcapeGame game;

  @override
  State<Hud> createState() => _HudState();
}

class _HudState extends State<Hud> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        final game = widget.game;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Reserve room on the right for the floating debug button so
                // the two never overlap.
                Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Row(
                    children: [
                      // Taps *remaining*, not taps used. The number that
                      // creates tension is the one running out.
                      _Stat(
                        // Past the campaign the number restarts as a depth.
                        // "Level 78" says nothing; "depth 18" is a score, and
                        // it is the thing endless is actually played for.
                        label: game.isEndless ? Strings.depth : Strings.level,
                        value: game.isEndless
                            ? '${game.depth}'
                            : '${game.levelNumber}',
                      ),
                      const SizedBox(width: 22),
                      // A level that does not ration taps counts them up
                      // instead of down: a budget readout on a level with no
                      // budget is a rule the player is being asked to obey for
                      // no reason.
                      if (game.budgetLimited)
                        _Stat(
                          label: Strings.tapsLeft,
                          value: '${game.tapsLeft}',
                          trailing: '/ ${game.tapBudget}',
                          alert: game.tapsLeft <= game.tapBudget * 0.25,
                        )
                      else
                        _Stat(label: Strings.taps, value: '${game.taps}'),
                      const SizedBox(width: 26),
                      _Stat(
                        label: Strings.time,
                        value: _formatTime(game.levelTime),
                      ),
                      const Spacer(),
                      // The openness meter used to live here. It was a
                      // playtesting readout for the speed curve, and with a
                      // level number and a chain to show as well there is no
                      // longer room for a number only I ever read.
                      if (game.tuning.zenMode)
                        const _Chip(label: 'ZEN')
                      else
                        _ChainPips(streak: game.streak.streak),
                    ],
                  ),
                ),
                if (game.tuning.hungerEnabled) ...[
                  const SizedBox(height: 10),
                  _HungerBar(
                    fraction: game.hunger.fraction,
                    seconds: game.hunger.remaining,
                  ),
                ],
                if (game.powerups.heldCharges.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _Charges(held: game.powerups.heldCharges),
                ],
                const Spacer(),
                _Hint(text: _hintFor(game)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// §12.5: teach tap, then drift, then regrowth — never all three at once.
  static String? _hintFor(HexcapeGame game) {
    if (game.isOver) {
      return null;
    }
    // A running script owns the line entirely: it is saying something specific
    // about right now, which beats any general advice.
    final script = game.tutorial;
    if (script != null && !script.isDone) {
      return script.prompt;
    }

    // Something just happened that needs words — a charge waiting to be spent,
    // or a mechanic appearing for the first time. Both are about this moment,
    // so they outrank the level's standing lesson.
    final banner = game.banner;
    if (banner != null) {
      return banner;
    }

    // A teaching level says its own line, for as long as the lesson is live.
    // The generic hints below were written when there was one level and
    // everything arrived at once; a level that exists to introduce anchors
    // should not be talking about drift.
    final teaches = game.rules.teaches;
    if (teaches != null && game.levelTime < 8) {
      return teaches;
    }
    if (game.taps == 0) {
      return Strings.hintTapToClear;
    }
    if (game.taps < 4) {
      return Strings.hintDrift;
    }
    final firstRegrowth = game.firstRegrowthAt;
    if (firstRegrowth != null && game.elapsed - firstRegrowth < 5.5) {
      return Strings.hintRegrowth;
    }
    return null;
  }

  static String _formatTime(double seconds) {
    final total = seconds.floor();
    final minutes = total ~/ 60;
    final rest = total % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

/// Charges in hand.
///
/// Unlike the timed powerups — which show themselves as a ring closing round
/// her, where the player is already looking — a charge has nothing to show. It
/// sits there until it is spent, so it needs a place on the HUD or the player
/// forgets they have it.
class _Charges extends StatelessWidget {
  const _Charges({required this.held});

  final List<({PickupKind kind, int count})> held;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in held) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Palette.forPickup(entry.kind).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: Palette.forPickup(entry.kind).withValues(alpha: 0.55),
              ),
            ),
            child: Text(
              entry.count > 1
                  ? '${entry.kind.label} x${entry.count}'
                  : entry.kind.label,
              style: TextStyle(
                color: Palette.forPickup(entry.kind),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// The tap chain, as pips rather than a number.
///
/// Deliberately quiet. The chain is carried by sound, shard size and haptics —
/// this only exists so a player can see *what* just reset, and a big flashing
/// counter would pull attention off the field, which is where the game is.
class _ChainPips extends StatelessWidget {
  const _ChainPips({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    const shown = 5;
    final lit = streak.clamp(0, shown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          streak > shown ? 'CHAIN $streak' : 'CHAIN',
          style: TextStyle(
            color: streak > 0 ? Palette.dogBody : Palette.hudDim,
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            for (var i = 0; i < shown; i++)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < lit ? Palette.dogBody : Palette.plainTop,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The clock (§2.2). A bar rather than a number on purpose: a bare countdown
/// invites panic-tapping, which §12.4 warns against, while a draining bar reads
/// as her running out of steam.
class _HungerBar extends StatelessWidget {
  const _HungerBar({required this.fraction, required this.seconds});

  final double fraction;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final low = fraction <= 0.25;
    final colour = Color.lerp(
      Palette.hungerLow,
      Palette.hungerFull,
      (fraction / 0.45).clamp(0.0, 1.0),
    )!;
    return Row(
      children: [
        Text(
          Strings.hunger,
          style: TextStyle(
            color: low ? Palette.danger : Palette.hudDim,
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                backgroundColor: Palette.plainTop,
                valueColor: AlwaysStoppedAnimation(colour),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text(
            '${seconds.ceil()}s',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: low ? Palette.danger : Palette.hudDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.trailing,
    this.alert = false,
  });

  final String label;
  final String value;
  final String? trailing;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: alert ? Palette.danger : Palette.hudDim,
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                color: alert ? Palette.danger : Palette.hudText,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              Text(
                trailing!,
                style: const TextStyle(
                  color: Palette.hudDim,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Palette.plainEdge),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Palette.hudText,
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: text == null
          ? const SizedBox(height: 20, width: double.infinity)
          : SizedBox(
              key: ValueKey(text),
              height: 20,
              width: double.infinity,
              child: Center(
                child: Text(
                  text!,
                  style: const TextStyle(
                    color: Palette.hudDim,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
    );
  }
}
