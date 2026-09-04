import 'package:flutter/material.dart';

import '../game/pets.dart';
import '../theme/palette.dart';

/// Choosing who you run (§9.2).
///
/// Locked pets are shown, not hidden. The whole reason they cost stars is to
/// give a finished level a reason to be replayed properly, and a reward nobody
/// can see is not a reason to do anything.
class PetPicker extends StatefulWidget {
  const PetPicker({
    required this.stars,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final int stars;
  final String selected;
  final void Function(Pet pet) onSelected;

  @override
  State<PetPicker> createState() => _PetPickerState();
}

class _PetPickerState extends State<PetPicker> {
  late String _selected = widget.selected;

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
            Row(
              children: [
                const Text(
                  'PETS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.stars} stars',
                  style: TextStyle(
                    color: Palette.treat,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Every pet plays exactly the same. This is a coat, not an edge.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            for (final pet in Pets.all) ...[
              _PetRow(
                pet: pet,
                unlocked: Pets.isUnlocked(pet, widget.stars),
                selected: pet.id == _selected,
                onTap: () {
                  if (!Pets.isUnlocked(pet, widget.stars)) {
                    return;
                  }
                  setState(() => _selected = pet.id);
                  widget.onSelected(pet);
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _PetRow extends StatelessWidget {
  const _PetRow({
    required this.pet,
    required this.unlocked,
    required this.selected,
    required this.onTap,
  });

  final Pet pet;
  final bool unlocked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? pet.body.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? pet.body.withValues(alpha: 0.8)
                : Palette.lockedEdge,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: unlocked
                    ? pet.body
                    : Palette.lockedTile,
                border: Border.all(
                  color: unlocked ? pet.dark : Palette.lockedEdge,
                  width: 2,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    style: TextStyle(
                      color: unlocked
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unlocked
                        ? pet.blurb
                        : '${pet.starsRequired} stars to unlock',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.42),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: pet.body, size: 20)
            else if (!unlocked)
              Icon(Icons.lock, color: Palette.lockedEdge, size: 18),
          ],
        ),
      ),
    );
  }
}
