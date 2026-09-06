import 'package:flutter/material.dart';

import '../game/difficulty.dart';
import '../theme/palette.dart';

/// The two-mode picker: the adventure or the gauntlet.
///
/// Shared by the settings sheet and the level detail sheet rather than written
/// twice: the two are the same control making the same promise, and the moment
/// they are separate widgets is the moment one of them gets a fourth option or
/// a different word for Normal.
class DifficultyPicker extends StatelessWidget {
  const DifficultyPicker({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final Difficulty value;

  /// Null while [enabled] is false, which is how the trial level pins itself to
  /// Normal without the row vanishing and leaving the player wondering.
  final ValueChanged<Difficulty>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final d in Difficulty.values) ...[
              Expanded(
                child: _Pill(
                  label: d.label,
                  selected: d == value,
                  enabled: enabled,
                  onTap: () => onChanged?.call(d),
                ),
              ),
              if (d != Difficulty.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value.description,
          style: TextStyle(
            color: Colors.white.withValues(alpha: enabled ? 0.42 : 0.28),
            fontSize: 12,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected && enabled;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? Palette.dogBody.withValues(alpha: 0.18)
                : Palette.lockedTile,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? Palette.dogBody : Palette.lockedEdge,
              width: active ? 1.6 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? Palette.dogBody
                    : Colors.white.withValues(alpha: enabled ? 0.62 : 0.3),
                fontSize: 13,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
