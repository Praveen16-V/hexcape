import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/glyphs.dart';
import '../game/board_camera.dart';
import '../game/hexcape_game.dart';
import '../game/tutorial.dart';
import '../l10n/strings.dart';
import '../entities/pickup.dart';
import '../hex/hex_cell.dart';
import '../hex/hex_coord.dart';
import 'reference_sheet.dart';
import '../theme/palette.dart';

/// The size of every square control in the HUD's top-right corner, and the gap
/// between them.
///
/// Shared with [DebugPanel], which floats in the same row from a separate
/// overlay and therefore cannot inherit the alignment — it has to be told.
/// Forty-eight is the touch target the rest of the app uses; the old debug
/// button was forty, which was both under the minimum and visibly out of line
/// with the two beside it.
const double _controlSize = 48;
const double _controlGap = 2;

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
                    // Reserve room on the right for the floating debug
                    // button, but only when there is one. Holding the gap open
                    // for a button players never see cost the HUD a control's
                    // width of every screen. Exactly one control plus the gap,
                    // so the three of them sit as one evenly spaced row.
                    Padding(
                      padding: EdgeInsets.only(
                        right: game.tuning.developerTools
                            ? _controlSize + _controlGap
                            : 0,
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
                            // Lit while the level-four card is naming it, so
                            // the sentence and the button are one gesture.
                            nudge:
                                game.tutorialHighlight !=
                                    TutorialHighlight.zoomControl
                                ? 0
                                : game.tuning.reducedMotion
                                ? 1
                                : (math.sin(_ticker.value * math.pi * 2) + 1) /
                                      2,
                            onPressed: () {
                              game.cycleZoom();
                              setState(() {});
                            },
                          ),
                          // The way off a level that is not winning or losing
                          // it.
                          const SizedBox(width: _controlGap),
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
                  ],
                ),
                // The tools she is carrying float in the gap beside the board
                // rather than sitting in the header. In the header they were
                // part of the measured block the board is framed *inside*, so
                // collecting a blast re-framed the whole map a little smaller
                // — the board flinched at the exact moment the player's eye
                // was on it. Here they take flexible space, which the insets
                // do not count, so picking one up costs the map nothing.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _ChargeRail(
                      held: game.powerups.heldCharges,
                      passives: game.powerups.heldPassives,
                      selected: game.powerups.selectedCharge,
                      isFresh: game.powerups.isFresh,
                      pulse: game.tuning.reducedMotion ? 0 : _ticker.value,
                      onToggle: game.toggleCharge,
                      onInspect: game.inspectPickup,
                    ),
                  ),
                ),
                // The card takes the hint's slot rather than stacking above it.
                // Below the board because covering the tile the player is
                // touching is the one place the answer must not go — and in
                // *this* slot because it is the same thing the hint line is: a
                // sentence at the bottom, sized into the HUD insets so the
                // board is never squeezed by surprise. Showing both at once
                // would be two voices answering different questions.
                SizedBox(
                  key: _hintKey,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Holds the slot open at exactly the height a card needs,
                      // at whatever text size the player is using. The insets
                      // below are measured from this box, and measuring the
                      // live message instead meant the board re-framed every
                      // time a message arrived, left, or cross-faded -- which
                      // is the flicker. Reserving the worst case is what the
                      // comment above has always claimed to do.
                      const _NoticeSlotFloor(),
                      if (game.inspecting != null)
                        _InspectorCard(
                          inspecting: game.inspecting!,
                          fade: (game.inspectFor / 0.6).clamp(0.0, 1.0),
                        )
                      else if (!game.isOver && !(game.tutorial?.isDone ?? true))
                        TutorialCard(game: game)
                      // The guaranteed read window: nothing outranks a receipt
                      // until it has been up long enough to read.
                      else if (game.pickupNoticeReadFor > 0)
                        _HudNoticeCard(
                          notice: game.pickupNotice!,
                          fade: _pickupFade(game),
                        )
                      else if (game.foodReceipt != null)
                        GameHint(
                          text: game.foodReceipt,
                          reducedMotion: game.tuning.reducedMotion,
                        )
                      else if (game.banner == null &&
                          game.proximityNotice != null)
                        _HudNoticeCard(
                          notice: game.proximityNotice!,
                          fade: (game.proximityNoticeFor / 0.35).clamp(
                            0.0,
                            1.0,
                          ),
                        )
                      // Past the read window the card stays for as long as the
                      // power-up does -- a charge until it is spent, an effect
                      // until it runs out -- but yields to anything above.
                      else if (game.pickupNotice != null)
                        _HudNoticeCard(
                          notice: game.pickupNotice!,
                          fade: _pickupFade(game),
                        )
                      else
                        GameHint(
                          text: _hintFor(game),
                          reducedMotion: game.tuning.reducedMotion,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Full while the power-up is live, fading only over its last moments. The
  /// game holds [HexcapeGame.pickupNoticeFor] clear of zero for exactly as long
  /// as there is something to describe.
  static double _pickupFade(HexcapeGame game) =>
      (game.pickupNoticeFor / HexcapeGame.pickupNoticeFadeSeconds).clamp(
        0.0,
        1.0,
      );

  /// How long she must actually be standing still with nowhere to go before
  /// the HUD says so. Long enough to sit out the ordinary pauses between one
  /// cell opening and the next; short enough that a player who has genuinely
  /// stopped is not left reading an empty screen.
  static const _waitBeforeNaming = 0.8;

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

    // Outranks the banner and the level's own lesson, because it is the only
    // line that explains why the board has gone quiet. A patrol beats it: that
    // wait ends on its own, so naming the light is the more useful of the two.
    if (game.dog.nowhereToGoFor >= _waitBeforeNaming && !game.dog.isLaunched) {
      return Strings.hintNowhereToGo;
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
      child: _NoticeChrome(
        edge: notice.pickup != null
            ? Palette.forPickup(notice.pickup!)
            : Palette.lockedEdge,
        mark: ReferenceMark(entry: entry, size: _NoticeChrome.markSize),
        name: entry.name.toUpperCase(),
        effect: effect,
      ),
    );
  }
}

/// The box every notice is drawn in, and the only place its metrics live.
///
/// Shared with [_NoticeSlotFloor] so the reserved height and the real card
/// cannot drift apart: a floor that guessed at padding and line heights would
/// be wrong at the first text-size change, which is the one case it exists for.
class _NoticeChrome extends StatelessWidget {
  const _NoticeChrome({
    required this.edge,
    required this.mark,
    required this.name,
    required this.effect,
  });

  static const markSize = 30.0;

  /// Two lines of effect copy is what the card reserves and what the floor
  /// measures. Anything longer is elided rather than allowed to resize the slot.
  static const effectLines = 2;

  final Color edge;
  final Widget mark;
  final String name;
  final String effect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.background.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: edge),
      ),
      child: Row(
        children: [
          mark,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                  maxLines: effectLines,
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
    );
  }
}

/// An invisible card, laid out but never seen, that keeps the message slot a
/// fixed height.
///
/// The HUD reports this slot's height to the game as a board inset. Measuring
/// whatever message happened to be showing meant the board re-framed itself
/// every time one arrived or left -- a plain hint line and a notice card are
/// not the same height -- and again on every frame of the 260 ms cross-fade
/// between them. Reserving the tallest transient message costs a fixed strip of
/// screen and buys a board that never moves.
class _NoticeSlotFloor extends StatelessWidget {
  const _NoticeSlotFloor();

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: Opacity(
        opacity: 0,
        child: _NoticeChrome(
          edge: Palette.lockedEdge,
          mark: SizedBox.square(dimension: _NoticeChrome.markSize),
          name: '',
          // As many lines as a real card reserves; the text is never read.
          effect: '\n',
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
/// Magnify the board, in one tap, at any time.
///
/// It carries its own factor under the glass. A bare magnifier is a control a
/// player has to *try* to find out what it does and what state it is in; the
/// number turns it into a readout they can check at a glance — and it is the
/// same number the board is drawn at, so it also explains the board.
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.zoom,
    required this.onPressed,
    this.nudge = 0,
  });

  final double zoom;

  /// 0 normally; breathing between 0 and 1 while the game is pointing this
  /// control out to a player who has never used it.
  final double nudge;

  final VoidCallback onPressed;

  /// '1x', '1.6x', '2.2x' — trailing zeroes are noise on a control this small.
  String get _label {
    final text = zoom.toStringAsFixed(1);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}x';
  }

  @override
  Widget build(BuildContext context) {
    final fit = zoom <= BoardCamera.minZoom;
    final colour = fit ? Palette.hudDim : Palette.hudText;
    final lit = nudge > 0
        ? Color.lerp(colour, Palette.goalGlow, nudge)
        : colour;
    return Semantics(
      button: true,
      label: 'Board zoom $_label, tap to magnify',
      child: Tooltip(
        message: fit ? 'Zoom in (now $_label)' : 'Zoom ($_label)',
        child: InkResponse(
          onTap: onPressed,
          radius: 26,
          child: Container(
            width: _controlSize,
            height: _controlSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // The offer, made visible: while the hint line names this
              // control, the control answers to it.
              color: Palette.goalGlow.withValues(alpha: 0.16 * nudge),
              border: nudge > 0
                  ? Border.all(
                      color: Palette.goalGlow.withValues(
                        alpha: 0.45 + 0.55 * nudge,
                      ),
                      width: 1.5,
                    )
                  : null,
            ),
            // One glyph, centred, exactly like the two beside it. The factor
            // used to be printed under it, and that is what broke the row:
            // the icon and its caption centred as a block, so the magnifier
            // floated above the pause bars and the whole corner read as three
            // controls on three different lines. The state it was spelling out
            // is already carried by the icon — a magnifier at fit, the spread
            // arrows once magnified — with the exact step in the tooltip and
            // read out in full by a screen reader.
            child: Icon(
              fit ? Icons.zoom_in_rounded : Icons.zoom_out_map_rounded,
              size: 22,
              color: lit,
            ),
          ),
        ),
      ),
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
      constraints: const BoxConstraints(
        minWidth: _controlSize,
        minHeight: _controlSize,
      ),
      icon: const Icon(Icons.pause_rounded, size: 22),
      color: Palette.hudDim,
      tooltip: 'Pause game',
    );
  }
}

/// The tools she is carrying, floating beside the board.
///
/// Unlike the timed powerups — which show themselves as a ring closing round
/// her, where the player is already looking — a charge has nothing to show. It
/// sits there until it is spent, so it needs a place on the HUD or the player
/// forgets they have it.
///
/// Three things had to be true of that place. It must not be part of the
/// measured header, or arriving would shrink the board. It must be *found*
/// without reading the hint line, so a newly collected tool pulses until it
/// has been armed once. And it must say what it holds in the same language the
/// board used — the same glyph that was lying in the grass a second ago, not a
/// word for it.
///
/// Laid out as a vertical wrap rather than a column: boards are far taller
/// than they are wide, so the spare room on screen is at the sides, and a wrap
/// starts a second stack inward instead of overflowing when a run is carrying
/// an unusual number of tools.
class _ChargeRail extends StatelessWidget {
  const _ChargeRail({
    required this.held,
    required this.passives,
    required this.selected,
    required this.isFresh,
    required this.pulse,
    required this.onToggle,
    required this.onInspect,
  });

  final List<({PickupKind kind, int count})> held;
  final List<PickupKind> passives;
  final PickupKind? selected;

  /// Whether this kind has been collected and never armed.
  final bool Function(PickupKind) isFresh;

  /// The HUD's shared one-second phase, or zero when the player has asked for
  /// less motion. Everything that breathes here breathes together.
  final double pulse;

  final ValueChanged<PickupKind> onToggle;

  /// Hold one to be told what it does. The tooltip stays the *action* — arm or
  /// disarm — because that is what the button does; what the tool is for is a
  /// different question and gets the same card the board gives.
  final ValueChanged<PickupKind> onInspect;

  @override
  Widget build(BuildContext context) {
    if (held.isEmpty && passives.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      direction: Axis.vertical,
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final entry in held)
          _ChargeButton(
            kind: entry.kind,
            count: entry.count,
            armed: selected == entry.kind,
            fresh: isFresh(entry.kind),
            pulse: pulse,
            onToggle: () => onToggle(entry.kind),
            onInspect: () => onInspect(entry.kind),
          ),
        for (final kind in passives)
          _PassiveChip(kind: kind, onInspect: () => onInspect(kind)),
      ],
    );
  }
}

/// One tool in hand: glyph, count, and its own state.
///
/// Fixed width on purpose. It floats over the board, so it may not grow with
/// the text scale the way a header chip can — the words inside shrink to fit
/// instead, and the full label is carried by the tooltip and by semantics,
/// where a screen reader reads it out in full.
class _ChargeButton extends StatelessWidget {
  const _ChargeButton({
    required this.kind,
    required this.count,
    required this.armed,
    required this.fresh,
    required this.pulse,
    required this.onToggle,
    required this.onInspect,
  });

  final PickupKind kind;
  final int count;
  final bool armed;
  final bool fresh;
  final double pulse;
  final VoidCallback onToggle;
  final VoidCallback onInspect;

  static const _size = 56.0;

  @override
  Widget build(BuildContext context) {
    final colour = Palette.forPickup(kind);
    // One breath a second, shared by both states. Armed glows because the next
    // tap on the board is about to mean something else; fresh glows because
    // the player has not looked over here yet.
    final breath = (math.sin(pulse * math.pi * 2) + 1) / 2;
    final glow = armed
        ? 0.45 + 0.35 * breath
        : fresh
        ? 0.30 + 0.45 * breath
        : 0.0;
    return Semantics(
      button: true,
      selected: armed,
      label: armed
          ? '${kind.label} armed, $count held'
          : fresh
          ? '${kind.label} collected, $count held, not armed yet'
          : '${kind.label}, $count held',
      child: Tooltip(
        message: '${armed ? 'Disarm' : 'Arm'} ${kind.label}',
        child: GestureDetector(
          onTap: onToggle,
          onLongPress: onInspect,
          child: Container(
            width: _size,
            constraints: const BoxConstraints(minHeight: _size),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: BoxDecoration(
              color: Color.lerp(
                const Color(0xE60E1422),
                colour.withValues(alpha: 0.34),
                armed ? 1.0 : 0.18,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colour.withValues(
                  alpha: armed
                      ? 1.0
                      : fresh
                      ? (0.55 + 0.45 * breath)
                      : 0.5,
                ),
                width: armed ? 2 : 1,
              ),
              boxShadow: [
                if (glow > 0)
                  BoxShadow(
                    color: colour.withValues(alpha: glow * 0.55),
                    blurRadius: 14 + 6 * breath,
                    spreadRadius: armed ? 1.5 : 0.5,
                  ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 26,
                  width: 26,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // The same drawing the pickup had on the board, so the
                      // button is recognisably the thing she just ran over.
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GlyphPainter(kind: kind, colour: colour),
                        ),
                      ),
                      if (count > 1)
                        Positioned(
                          right: -6,
                          bottom: -4,
                          child: _CountBadge(count: count, colour: colour),
                        ),
                      if (armed)
                        Positioned(
                          left: -7,
                          top: -5,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 13,
                            color: colour,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: _size - 10,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      kind.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: colour.withValues(alpha: armed ? 1 : 0.85),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                // The two states a player must never have to read the hint
                // line to tell apart: a tool just collected and not yet found,
                // and a tool that has taken over the next tap. A tool merely
                // sitting in hand says nothing — a resting button with a word
                // under it is just noise on top of the board.
                if (fresh || armed) ...[
                  const SizedBox(height: 2),
                  SizedBox(
                    width: _size - 10,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        armed ? 'TAP TILE' : 'NEW',
                        maxLines: 1,
                        style: TextStyle(
                          color: armed
                              ? colour
                              : colour.withValues(alpha: 0.5 + 0.5 * breath),
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How many of a tool are in hand, when it is more than one.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.colour});

  final int count;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xF20E1422),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colour.withValues(alpha: 0.8), width: 1),
      ),
      child: Text(
        'x$count',
        style: TextStyle(
          color: colour,
          fontSize: 8,
          height: 1.1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The run's ambient protection, as small chips rather than buttons.
///
/// Passives cannot be toggled — they are owned once found — so these are
/// announcements, not controls. They exist because everything else in the HUD
/// is either a clock or a decision; a waystone, a heart, should be *findable*
/// on the screen, or a player after a week's gap will forget they carry it.
/// They ride the same rail as the charges, one size down, because they answer
/// the same question more quietly: what am I carrying?
class _PassiveChip extends StatelessWidget {
  const _PassiveChip({required this.kind, required this.onInspect});

  final PickupKind kind;
  final VoidCallback onInspect;

  @override
  Widget build(BuildContext context) {
    final colour = Palette.forPickup(kind);
    return Semantics(
      label: '${kind.label}, in effect',
      child: Tooltip(
        message: kind.label,
        child: GestureDetector(
          onTap: onInspect,
          onLongPress: onInspect,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xCC0E1422),
              shape: BoxShape.circle,
              border: Border.all(
                color: colour.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: CustomPaint(
              painter: _GlyphPainter(kind: kind, colour: colour),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a pickup with the game's own drawing code, never a lookalike, so the
/// HUD and the board can never drift apart.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.kind, required this.colour});

  final PickupKind kind;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = colour;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = colour;
    drawPickupGlyph(
      canvas,
      kind,
      centre: Offset(size.width / 2, size.height / 2),
      size: size.shortestSide * 0.30,
      fill: fill,
      stroke: stroke,
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.colour != colour;
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
                  switch (step.advance) {
                    TutorialAdvance.onTap =>
                      'Tap the glowing tile on the board to continue.',
                    TutorialAdvance.onReach =>
                      'Open a route so your dog can reach the marked treat.',
                    // The watching beats are the ones that need the player to
                    // do nothing at all, which is exactly the instruction a
                    // player will not follow unless it is given.
                    TutorialAdvance.onWatch => 'Keep an eye on the board.',
                    TutorialAdvance.onRegrow =>
                      step.target == TutorialTarget.recentlyOpened
                          ? 'Watch the marked tile on the board.'
                          : 'Keep an eye on the board.',
                    TutorialAdvance.onContinue => '',
                  },
                  style: const TextStyle(color: Palette.hudText, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
