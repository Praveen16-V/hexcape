import 'package:flutter/material.dart';

import '../game/difficulty.dart';
import '../theme/palette.dart';

/// The one-time question, asked before the first level.
///
/// Asked on the way in rather than left to be discovered in Settings, because
/// the players this exists for are the ones who stall out and stop — and
/// somebody who has already put the game down does not go looking through a
/// settings sheet for permission to keep playing.
///
/// Deliberately not dismissible, and deliberately without a default already
/// selected: three taps' worth of choice is cheap, and a picker that can be
/// waved away is one most people will wave away.
class DifficultyIntro extends StatelessWidget {
  const DifficultyIntro({required this.onChoose, super.key});

  final ValueChanged<Difficulty> onChoose;

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<Difficulty> onChoose,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => DifficultyIntro(onChoose: onChoose),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Palette.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'HOW WOULD YOU LIKE TO PLAY?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The same hundred-level journey. Hard lays heavier ground, '
                  'leaner supplies and a merciless clock over it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                for (final d in Difficulty.values) ...[
                  _Card(difficulty: d, onTap: () => onChoose(d)),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                Text(
                  'You can change this any time in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 12,
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

class _Card extends StatelessWidget {
  const _Card({required this.difficulty, required this.onTap});

  final Difficulty difficulty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Palette.lockedTile,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.lockedEdge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              difficulty.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              difficulty.description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
