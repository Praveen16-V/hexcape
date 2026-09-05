import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/daily.dart';
import '../game/level_rules.dart';
import '../game/pets.dart';
import '../game/progress.dart';
import '../l10n/strings.dart';
import '../theme/palette.dart';
import 'home_dog.dart';
import 'level_map.dart' show MapLayout;

/// The game's front door.
///
/// Kept separate from `LevelMap` (`lib/ui/level_map.dart`): a hundred levels to
/// choose from is a chooser, not a title screen. This is what a returning
/// player actually wants on opening the app — one obvious thing to do next,
/// the dog she's running, and the daily board and the offer within a tap —
/// with the campaign itself one tap further behind a dedicated screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.progress,
    required this.pet,
    required this.onPlay,
    required this.onCampaign,
    this.onTutorial,
    required this.onDaily,
    required this.onPets,
    required this.onSettings,
    required this.onReference,
    required this.onUnlock,
    super.key,
  });

  final Progress progress;

  /// Whoever the player is currently running (§9.2). Read fresh on every
  /// build rather than cached: the pet picker can change it while this screen
  /// sits behind the map.
  final Pet pet;

  /// Plays the frontier level — the same one the old play bar named. Goes
  /// through the existing level-detail sheet, so Zen and resume-in-progress
  /// behave exactly as they did when this button lived on the map.
  final VoidCallback onPlay;

  /// Opens the hundred-level campaign map.
  final VoidCallback onCampaign;
  final VoidCallback? onTutorial;

  /// Starts today's board.
  final VoidCallback onDaily;

  final VoidCallback onPets;
  final VoidCallback onSettings;
  final VoidCallback onReference;

  /// Opens the offer. Shown on this screen only while the game is unbought.
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final frontier = math.min(progress.unlocked, MapLayout.tiles);
    final endless = frontier > Campaign.length;
    final band = Campaign.bandOf(frontier);
    final identity = Campaign.identityFor(frontier);
    final colour = Palette.forBand(band);
    final bestDepth = progress.endlessBest > Campaign.length
        ? progress.endlessBest - Campaign.length
        : 0;

    final daily = Daily.forDate(DateTime.now());
    final dailyCleared = progress.hasClearedDaily(daily);
    final streak = progress.dailyStreakAsOf(DateTime.now());

    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            return SingleChildScrollView(
              child: SizedBox(
                height: math.max(
                  constraints.maxHeight,
                  scale > 1.4 ? 560 * scale : 0,
                ),
                child: Column(
                  children: [
                    _TopBar(
                      stars: progress.totalStars,
                      maxStars: Campaign.length * 3,
                      onPets: onPets,
                      onSettings: onSettings,
                      onReference: onReference,
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Center(
                          child: HomeDog(
                            pet: pet,
                            reducedMotion: progress.reducedMotion,
                            size: math.min(
                              constraints.maxWidth * 0.62,
                              constraints.maxHeight * 0.68,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Text(
                      'HEXCAPE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Text(
                        Strings.tagline,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (onTutorial != null)
                      TextButton.icon(
                        onPressed: onTutorial,
                        icon: const Icon(Icons.touch_app_outlined, size: 18),
                        label: const Text('Learn to play'),
                        style: TextButton.styleFrom(
                          foregroundColor: Palette.dogBody,
                        ),
                      )
                    else
                      const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: _Chip(
                              icon: dailyCleared
                                  ? Icons.check_circle_outline
                                  : Icons.today_outlined,
                              label: dailyCleared
                                  ? Strings.dailyDone
                                  : Strings.dailyTitle,
                              trailing: streak > 0 ? '$streak🔥' : null,
                              colour: dailyCleared
                                  ? Palette.hudDim
                                  : Palette.forBand(daily.band),
                              onTap: onDaily,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Chip(
                              icon: Icons.hexagon_outlined,
                              label: Strings.campaign,
                              trailing: '$frontier/${MapLayout.tiles}',
                              colour: Palette.hudText,
                              onTap: onCampaign,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: onPlay,
                          style: FilledButton.styleFrom(
                            backgroundColor: colour,
                            foregroundColor: Palette.background,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              endless
                                  ? (bestDepth > 0
                                        ? 'ENDLESS  ·  BEST D$bestDepth'
                                        : 'ENDLESS')
                                  : 'LEVEL $frontier  ·  ${identity.title.toUpperCase()}',
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 28,
                      child: progress.ownsFullGame
                          ? null
                          // Always reachable, never loud. One line under Play rather
                          // than a bar of its own — a game with one thing to sell can
                          // afford to say so once, quietly.
                          : TextButton(
                              onPressed: onUnlock,
                              style: TextButton.styleFrom(
                                foregroundColor: Palette.bandPressure,
                                padding: EdgeInsets.zero,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Unlock full game',
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.stars,
    required this.maxStars,
    required this.onPets,
    required this.onSettings,
    required this.onReference,
  });

  final int stars;
  final int maxStars;
  final VoidCallback onPets;
  final VoidCallback onSettings;
  final VoidCallback onReference;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 6, 0),
      child: Row(
        children: [
          Semantics(
            label: 'Campaign mastery: $stars of $maxStars stars',
            child: Row(
              children: [
                Icon(Icons.circle, size: 9, color: Palette.treat),
                const SizedBox(width: 5),
                Text(
                  '$stars/$maxStars',
                  style: TextStyle(
                    color: Palette.treat,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _IconButton(
            onPressed: onPets,
            icon: Icons.pets,
            colour: Palette.dogBody,
            tooltip: 'Pets',
          ),
          _IconButton(
            onPressed: onReference,
            icon: Icons.help_outline,
            colour: Colors.white70,
            tooltip: 'How it works',
          ),
          _IconButton(
            onPressed: onSettings,
            icon: Icons.tune,
            colour: Colors.white70,
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.onPressed,
    required this.icon,
    required this.colour,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final Color colour;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      color: colour,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    );
  }
}

/// One of the two destinations below the hero — the daily board and the
/// campaign map — small enough that both sit in a single row rather than
/// stacking as bars of their own.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: colour,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: colour.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 7),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
