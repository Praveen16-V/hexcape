import 'package:flutter/material.dart';

import '../game/board_camera.dart';
import '../game/hexcape_game.dart';
import '../game/tutorial.dart';
import '../l10n/strings.dart';
import '../entities/pickup.dart';
import '../hex/hex_cell.dart';
import '../hex/hex_coord.dart';
import 'reference_sheet.dart';
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
  final _headerKey = GlobalKey();
  final _hintKey = GlobalKey();

  void _measure(EdgeInsets safe) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final header = _headerKey.currentContext?.size;
      final hint = _hintKey.currentContext?.size;
      if (header == null || hint == null) return;
      widget.game.setHudInsets(
        EdgeInsets.fromLTRB(
          safe.left + 14,
          safe.top + 12 + header.height + 12,
          safe.right + 14,
          safe.bottom + 20 + hint.height + 12,
        ),
      );
    });
  }

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
        _measure(MediaQuery.paddingOf(context));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  key: _headerKey,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Reserve room on the right for the floating debug button, but
                    // only when there is one. Holding the gap open for a button
                    // players never see cost the HUD 40 logical pixels of every
                    // screen.
                    Padding(
                      padding: EdgeInsets.only(
                        right: game.tuning.developerTools ? 40 : 0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final scale =
                                    MediaQuery.textScalerOf(context).scale(22) /
                                    22;
                                final compact =
                                    constraints.maxWidth < 390 * scale;
                                final statWidth = compact
                                    ? (constraints.maxWidth - 12) / 2
                                    : null;
                                return Wrap(
                                  spacing: compact ? 12 : 18,
                                  runSpacing: 10,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    // Taps *remaining*, not taps used. The number that
                                    // creates tension is the one running out.
                                    SizedBox(
                                      width: statWidth,
                                      child: _Stat(
                                        // Past the campaign the number restarts as a depth.
                                        // "Level 78" says nothing; "depth 18" is a score, and
                                        // it is the thing endless is actually played for.
                                        label: game.isEndless
                                            ? Strings.depth
                                            : Strings.level,
                                        value: game.isEndless
                                            ? '${game.depth}'
                                            : '${game.levelNumber}',
                                      ),
                                    ),
                                    // A level that does not ration taps counts them up
                                    // instead of down: a budget readout on a level with no
                                    // budget is a rule the player is being asked to obey for
                                    // no reason.
                                    if (game.budgetLimited)
                                      SizedBox(
                                        width: statWidth,
                                        child: _Stat(
                                          label: Strings.tapsLeft,
                                          value: '${game.tapsLeft}',
                                          trailing: compact
                                              ? null
                                              : '/ ${game.tapBudget}',
                                          alert:
                                              game.tapsLeft <=
                                              game.tapBudget * 0.25,
                                        ),
                                      )
                                    else
                                      SizedBox(
                                        width: statWidth,
                                        child: _Stat(
                                          label: Strings.taps,
                                          value: '${game.taps}',
                                        ),
                                      ),
                                    if (!compact)
                                      _Stat(
                                        label: Strings.time,
                                        value: _formatTime(game.levelTime),
                                      ),
                                    // The openness meter used to live here. It was a
                                    // playtesting readout for the speed curve, and with a
                                    // level number and a chain to show as well there is no
                                    // longer room for a number only I ever read.
                                    if (game.tuning.zenMode)
                                      const _Chip(label: 'ZEN PRACTICE')
                                    else if (!compact)
                                      _ChainPips(streak: game.streak.streak),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          _ZoomButton(
                            zoom: game.boardCamera.zoom,
                            onPressed: () {
                              game.cycleZoom();
                              setState(() {});
                            },
                          ),
                          // The way off a level that is not winning or losing
                          // it.
                          const SizedBox(width: 2),
                          _PauseButton(onPressed: game.pauseRun),
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
                      _Charges(
                        held: game.powerups.heldCharges,
                        selected: game.powerups.selectedCharge,
                        onToggle: game.toggleCharge,
                        onInspect: game.inspectPickup,
                      ),
                    ],
                    if (game.powerups.heldPassives.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _Passives(
                        held: game.powerups.heldPassives,
                        onInspect: game.inspectPickup,
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                // The card takes the hint's slot rather than stacking above it.
                // Below the board because covering the tile the player is
                // touching is the one place the answer must not go — and in
                // *this* slot because it is the same thing the hint line is: a
                // sentence at the bottom, sized into the HUD insets so the
                // board is never squeezed by surprise. Showing both at once
                // would be two voices answering different questions.
                SizedBox(
                  key: _hintKey,
                  child: game.inspecting != null
                      ? _InspectorCard(
                          inspecting: game.inspecting!,
                          fade: (game.inspectFor / 0.6).clamp(0.0, 1.0),
                        )
                      : !game.isOver && !(game.tutorial?.isDone ?? true)
                      ? TutorialCard(game: game)
                      : game.pickupNotice != null
                      ? _HudNoticeCard(
                          notice: game.pickupNotice!,
                          fade: (game.pickupNoticeFor / 0.18).clamp(0.0, 1.0),
                        )
                      : game.foodReceipt != null
                      ? GameHint(
                          text: game.foodReceipt,
                          reducedMotion: game.tuning.reducedMotion,
                        )
                      : game.banner == null && game.proximityNotice != null
                      ? _HudNoticeCard(
                          notice: game.proximityNotice!,
                          fade: (game.proximityNoticeFor / 0.35).clamp(
                            0.0,
                            1.0,
                          ),
                        )
                      : GameHint(
                          text: _hintFor(game),
                          reducedMotion: game.tuning.reducedMotion,
                        ),
                ),
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

    if (game.dog.waitingForPatrol && !game.dog.isLaunched) {
      return 'Patrol ahead — she avoids the light';
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

class _HudNoticeCard extends StatelessWidget {
  const _HudNoticeCard({required this.notice, required this.fade});

  final HudNotice notice;
  final double fade;

  @override
  Widget build(BuildContext context) {
    final entry = notice.pickup != null
        ? referenceForPickup(notice.pickup!)
        : notice.hex != null
        ? referenceForHex(notice.hex!)
        : null;
    if (entry == null) return const SizedBox.shrink();
    final chargeHint =
        notice.kind == HudNoticeKind.pickup && notice.pickup?.isCharge == true
        ? notice.pickup!.readyHint
        : null;
    final sentenceEnd = entry.blurb.indexOf('.');
    final effect =
        chargeHint ??
        (sentenceEnd < 0
            ? entry.blurb
            : entry.blurb.substring(0, sentenceEnd + 1));
    return Opacity(
      opacity: fade,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Palette.background.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notice.pickup != null
                ? Palette.forPickup(notice.pickup!)
                : Palette.lockedEdge,
          ),
        ),
        child: Row(
          children: [
            ReferenceMark(entry: entry, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    effect,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Palette.hudDim,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the tile under the player's finger is.
///
/// Every explanation the game gives is otherwise transient — a tutorial step
/// that runs once, a `teaches` line that shows for eight seconds, a banner on
/// one level and never again — or else it is behind the pause menu, which means
/// stopping the run to ask. This is the third thing: the answer, where the
/// question was asked, without leaving the level.
///
/// The copy and the drawing both come from [allReferenceEntries], so this
/// cannot describe a spring differently than the reference sheet does.
class _InspectorCard extends StatelessWidget {
  const _InspectorCard({required this.inspecting, required this.fade});

  final ({HexCoord coord, PickupKind? pickup, HexType? hex}) inspecting;
  final double fade;

  @override
  Widget build(BuildContext context) {
    final pickup = inspecting.pickup;
    final hex = inspecting.hex;
    final entry = pickup != null
        ? referenceForPickup(pickup)
        : hex != null
        ? referenceForHex(hex)
        : null;

    // Ground she has not been near yet. The fog is the mechanic; answering
    // through it would be answering the wrong question.
    final name = entry?.name ?? 'Unknown ground';
    final blurb =
        entry?.blurb ??
        'She has not been close enough to see what this is yet.';

    return Opacity(
      opacity: fade,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: Palette.background.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.lockedEdge, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry != null)
              ReferenceMark(entry: entry, size: 34)
            else
              const SizedBox(
                width: 34,
                height: 34,
                child: Icon(Icons.blur_on, color: Palette.hudDim, size: 20),
              ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    blurb,
                    // Bounded by how big the text already is. At ordinary
                    // sizes the whole explanation fits; at double scale an
                    // unbounded blurb would eat the board it is describing, and
                    // the full text is always a pause away in the reference
                    // sheet.
                    maxLines: MediaQuery.textScalerOf(context).scale(12) > 16
                        ? 2
                        : 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.56),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Magnify the board.
///
/// The largest board is twelve columns by twenty-nine rows, and fitting all of
/// it on a small phone leaves a hex under twenty pixels across. This is the
/// answer to that, and it is a cycle rather than a slider because the only two
/// states worth having mid-level are "big enough to read" and "show me
/// everything" — one tap each.
///
/// It changes nothing about the rules. Reach is measured in hex widths, so the
/// set of tiles a tap can clear is identical at every step.
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.zoom, required this.onPressed});

  final double zoom;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fit = zoom <= BoardCamera.minZoom;
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.standard,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(
        fit ? Icons.zoom_in_rounded : Icons.zoom_out_map_rounded,
        size: 22,
      ),
      color: fit ? Palette.hudDim : Palette.hudText,
      tooltip: fit ? 'Zoom in' : 'Zoom (${zoom.toStringAsFixed(1)}x)',
    );
  }
}

/// Stop the run.
///
/// Deliberately small and unemphatic. It has to be reachable at all times, and
/// it must never compete for attention with the board — the game is played by
/// looking at the field, not at the chrome.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.standard,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: const Icon(Icons.pause_rounded, size: 22),
      color: Palette.hudDim,
      tooltip: 'Pause game',
    );
  }
}

/// Charges in hand.
///
/// Unlike the timed powerups — which show themselves as a ring closing round
/// her, where the player is already looking — a charge has nothing to show. It
/// sits there until it is spent, so it needs a place on the HUD or the player
/// forgets they have it.
class _Charges extends StatelessWidget {
  const _Charges({
    required this.held,
    required this.selected,
    required this.onToggle,
    required this.onInspect,
  });

  final List<({PickupKind kind, int count})> held;
  final PickupKind? selected;
  final ValueChanged<PickupKind> onToggle;

  /// Hold one to be told what it does. The tooltip stays the *action* — arm or
  /// disarm — because that is what the button does; what the tool is for is a
  /// different question and gets the same card the board gives.
  final ValueChanged<PickupKind> onInspect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in held)
          Builder(
            builder: (context) {
              final armed = selected == entry.kind;
              final colour = Palette.forPickup(entry.kind);
              return Semantics(
                button: true,
                selected: armed,
                label: '${entry.kind.label}, ${entry.count} held',
                child: Tooltip(
                  message: '${armed ? 'Disarm' : 'Arm'} ${entry.kind.label}',
                  child: OutlinedButton(
                    onPressed: () => onToggle(entry.kind),
                    onLongPress: () => onInspect(entry.kind),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: colour,
                      backgroundColor: colour.withValues(
                        alpha: armed ? 0.3 : 0.12,
                      ),
                      side: BorderSide(
                        color: colour.withValues(alpha: armed ? 1 : 0.55),
                        width: armed ? 2 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (armed) ...[
                          const Icon(Icons.check_rounded, size: 15),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          entry.count > 1
                              ? '${entry.kind.label} x${entry.count}'
                              : entry.kind.label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// The run's ambient protection, as small chips rather than buttons.
///
/// Passives cannot be toggled — they are owned once found — so these are
/// announcements, not controls. They exist because everything else in the HUD
/// is either a clock or a decision; a waystone, a heart, should be *findable*
/// on the screen, or a player after a week's gap will forget they carry it.
class _Passives extends StatelessWidget {
  const _Passives({required this.held, required this.onInspect});

  final List<PickupKind> held;
  final ValueChanged<PickupKind> onInspect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final kind in held)
          Builder(
            builder: (context) {
              final colour = Palette.forPickup(kind);
              return Semantics(
                label: '${kind.label}, in effect',
                child: Tooltip(
                  message: kind.label,
                  child: GestureDetector(
                    onLongPress: () => onInspect(kind),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colour.withValues(alpha: 0.10),
                        border: Border.all(
                          color: colour.withValues(alpha: 0.45),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        kind.label,
                        style: TextStyle(
                          color: colour,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
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
          mainAxisSize: MainAxisSize.min,
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
        Text(
          '${seconds.ceil()}s',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: low ? Palette.danger : Palette.hudDim,
            fontSize: 11,
            fontWeight: FontWeight.w600,
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
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
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

/// Wrapping instruction shared by the HUD and rendering checks.
class GameHint extends StatelessWidget {
  const GameHint({required this.text, this.reducedMotion = false, super.key});

  final String? text;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      child: text == null
          ? const SizedBox(height: 20, width: double.infinity)
          : SizedBox(
              key: ValueKey(text),
              width: double.infinity,
              child: Center(
                child: Text(
                  text!,
                  textAlign: TextAlign.center,
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

/// The lesson lives outside the board; HUD measurement reserves its space.
class TutorialCard extends StatelessWidget {
  const TutorialCard({required this.game, super.key});
  final HexcapeGame game;

  @override
  Widget build(BuildContext context) {
    final script = game.tutorial!;
    final step = script.current!;
    final reading = step.advance == TutorialAdvance.onContinue;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.38,
      ),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF172235),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Palette.dogBody),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'LEARN TO PLAY - ${script.stepNumber}/${script.stepCount}',
                      style: const TextStyle(
                        color: Palette.dogBody,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      script.skip();
                      game.tutorialTarget = null;
                    },
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: Palette.hudText),
                    ),
                  ),
                ],
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  game.foodReceipt == null
                      ? step.prompt
                      : '${game.foodReceipt} - ${step.prompt}',
                  style: const TextStyle(
                    color: Palette.hudText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (reading)
                FilledButton(
                  onPressed: () {
                    script.continueLesson();
                    game.tutorialTarget = script.targetCell(
                      game.grid,
                      game.dog,
                      game.pickups,
                    );
                  },
                  child: Text(
                    script.stepNumber == script.stepCount
                        ? "Let's play"
                        : 'Continue',
                  ),
                )
              else
                Text(
                  step.advance == TutorialAdvance.onTap
                      ? 'Tap the marked tile on the board to continue.'
                      : 'Open a route so your dog can reach the marked treat.',
                  style: const TextStyle(color: Palette.hudText, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
