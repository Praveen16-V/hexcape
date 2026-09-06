import 'package:flutter/material.dart';

import '../game/progress.dart';
import '../theme/palette.dart';
import 'difficulty_picker.dart';

/// The player's own settings, as distinct from the debug panel.
///
/// The debug panel has thirty sliders for tuning a game that is still being
/// designed, and shipping it as the only way to reach the volume would be
/// handing a player the controls to break their own game. This is the short
/// list: the things someone might actually want to change about how the game
/// treats *them*.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    required this.progress,
    required this.onChanged,
    required this.onRestore,
    super.key,
  });

  final Progress progress;

  /// Called after every change, so the live game picks it up immediately
  /// rather than at the next level.
  final VoidCallback onChanged;

  /// Re-checks the purchase with the store. Null when billing is unavailable on
  /// this device, in which case the row is not shown at all rather than offered
  /// and then failing.
  final Future<void> Function()? onRestore;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  Progress get _p => widget.progress;

  Future<void> _apply(Future<void> Function() write) async {
    await write();
    if (!mounted) {
      return;
    }
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Palette.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.lockedEdge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'SETTINGS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Difficulty',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DifficultyPicker(
              value: _p.difficulty,
              onChanged: (d) => _apply(() => _p.setDifficulty(d)),
            ),
            const SizedBox(height: 16),
            _Slider(
              label: 'Volume',
              value: _p.volume,
              display: _p.volume <= 0 ? 'Off' : '${(_p.volume * 100).round()}%',
              onChanged: (v) => _apply(() => _p.setVolume(v)),
            ),
            _Toggle(
              label: 'Regrowth sound',
              blurb:
                  'The warning before a tile snaps shut. Off by default — '
                  'you still feel it.',
              value: _p.regrowthSound,
              onChanged: (v) => _apply(() => _p.setRegrowthSound(v)),
            ),
            _Toggle(
              label: 'Vibration',
              blurb: 'Taps, cracks, warnings and impacts.',
              value: _p.haptics,
              onChanged: (v) => _apply(() => _p.setHaptics(v)),
            ),
            _Toggle(
              label: 'Reduced motion',
              blurb: 'No screen shake, no freeze frames, no fade to grey.',
              value: _p.reducedMotion,
              onChanged: (v) => _apply(() => _p.setReducedMotion(v)),
            ),
            _Toggle(
              label: 'Nudges',
              blurb:
                  'An arrow points the way when you have been stuck a while.',
              value: _p.hints,
              onChanged: (v) => _apply(() => _p.setHints(v)),
            ),
            if (widget.onRestore != null) ...[
              const SizedBox(height: 4),
              // Someone who reinstalls, or picks up a second device, needs a way
              // to get back what they paid for that does not involve paying
              // again. It is required policy on iOS and simply correct here.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onRestore,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Restore purchase'),
                  style: TextButton.styleFrom(
                    foregroundColor: Palette.dogBody,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Divider(color: Palette.lockedEdge, height: 1),
            const SizedBox(height: 10),
            _Toggle(
              label: 'Developer tools',
              blurb:
                  'The tuning panel: sliders, a level jump, and a button '
                  'that erases your progress. Off unless you mean it.',
              value: _p.developerTools,
              onChanged: (v) => _apply(() => _p.setDeveloperTools(v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.blurb,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String blurb;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  blurb,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Palette.dogBody,
          ),
        ],
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              display,
              style: TextStyle(
                color: Palette.dogBody,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          onChanged: onChanged,
          activeColor: Palette.dogBody,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
