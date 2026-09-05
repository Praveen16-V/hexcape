import 'package:flutter/material.dart';

import '../game/hexcape_game.dart';
import '../l10n/strings.dart';
import '../theme/palette.dart';

/// A way out of a level that is not losing it.
///
/// Until this existed the HUD had no buttons at all, so a player mid-run could
/// only finish the level or fail it — the sole exit was the Android system back
/// gesture, which is invisible, absent on other platforms, and used to throw
/// the run away on the way out.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    required this.game,
    required this.onMap,
    required this.onReference,
    super.key,
  });

  final HexcapeGame game;
  final VoidCallback onMap;
  final VoidCallback onReference;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Opaque enough to read against, sheer enough that the board is still
      // there behind it — a pause should feel like stopping, not like leaving.
      color: Palette.background.withValues(alpha: 0.88),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  Strings.paused,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  game.isEndless
                      ? 'ENDLESS · ${Strings.depth} ${game.depth}'
                      : game.tuning.zenMode
                      ? 'ZEN PRACTICE · ${Strings.level} ${game.levelNumber}'
                      : '${Strings.level} ${game.levelNumber}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),
                _PauseButton(
                  label: Strings.resume,
                  primary: true,
                  onPressed: game.resumeRun,
                ),
                const SizedBox(height: 10),
                _PauseButton(
                  label: Strings.restart,
                  onPressed: () {
                    game.resumeRun();
                    game.retry();
                  },
                ),
                const SizedBox(height: 10),
                _PauseButton(label: Strings.reference, onPressed: onReference),
                const SizedBox(height: 10),
                _PauseButton(label: Strings.leaveLevel, onPressed: onMap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: primary
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Palette.dogBody,
                foregroundColor: Palette.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: Text(label, style: _style),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.8),
                side: BorderSide(color: Palette.lockedEdge),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: Text(label, style: _style),
            ),
    );
  }

  static const _style = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
  );
}
