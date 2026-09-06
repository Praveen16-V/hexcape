import 'package:flutter/material.dart';

import '../game/difficulty.dart';
import '../game/entitlements.dart';
import '../game/level_rules.dart';
import '../game/progress.dart';
import '../gen/silhouette.dart';
import '../l10n/strings.dart';
import '../theme/palette.dart';
import 'difficulty_picker.dart';

/// What a level is, before you commit to it.
///
/// Tapping a tile used to start the level instantly, and a locked tile did
/// nothing at all — not even say why. This also gives `bestTaps` and `bestTime`
/// somewhere to go: both were computed, merged and written to storage on every
/// win and then read by nothing, so a player's records were invisible to them.
class LevelDetail extends StatefulWidget {
  const LevelDetail({
    required this.level,
    required this.progress,
    required this.inProgress,
    required this.onPlay,
    required this.onUnlock,
    this.initialDifficulty = Difficulty.normal,
    this.initialZen = false,
    super.key,
  });

  final int level;
  final Progress progress;

  /// Whether this exact level is already built and mid-run, in which case the
  /// primary action resumes it rather than throwing it away.
  final bool inProgress;

  /// The mode of the run that can be resumed. Switching the toggle means the
  /// existing board must be rebuilt, so the action stops calling itself Resume.
  final bool initialZen;

  /// The difficulty this sheet opens on: the player's setting, or the one a
  /// resumable run is already being played at.
  final Difficulty initialDifficulty;

  /// [zen], [difficulty] and [restart] are the choices this sheet can make.
  final void Function({
    required bool zen,
    required Difficulty difficulty,
    required bool restart,
  })
  onPlay;

  /// Opens the offer, for a level that is past the free campaign.
  final VoidCallback onUnlock;

  @override
  State<LevelDetail> createState() => _LevelDetailState();
}

class _LevelDetailState extends State<LevelDetail> {
  late bool _zen;
  late Difficulty _difficulty;

  @override
  void initState() {
    super.initState();
    _zen = widget.initialZen;
    _difficulty = widget.initialDifficulty;
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final record = widget.progress.recordFor(level);
    final access = Entitlements.accessTo(
      level,
      unlocked: widget.progress.unlocked,
      owned: widget.progress.ownsFullGame,
      trialUsed: widget.progress.trialUsed,
    );
    final trial = access == LevelAccess.trial;
    // The one free look past the paywall is pinned to Normal. It exists to show
    // what the level actually is before asking for money, and a preview the
    // player can quietly soften — or sharpen — is not that.
    final difficulty = trial ? Difficulty.normal : _difficulty;
    final rules = Campaign.rulesFor(level, difficulty: difficulty);
    // The trial is playable, so it takes the same body as an open level — the
    // records, the brief, the play button. Only the framing above it differs.
    final unlocked = access == LevelAccess.open || trial;
    final band = Campaign.bandOf(level);
    final endless = level > Campaign.length;
    final colour = Palette.forBand(band);
    final identity = rules.identity;
    final canResume =
        widget.inProgress &&
        _zen == widget.initialZen &&
        difficulty == widget.initialDifficulty;

    return Container(
      decoration: const BoxDecoration(
        color: Palette.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 18),
              Text(
                endless
                    ? 'ENDLESS · DEPTH ${level - Campaign.length}'
                    : '${band.label.toUpperCase()} · LEVEL $level',
                style: TextStyle(
                  color: colour,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                endless ? 'Endless' : identity.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!rules.isTutorial) ...[
                const SizedBox(height: 5),
                Text(
                  '${identity.signature.label.toUpperCase()} · '
                  '${identity.signature.description}',
                  style: TextStyle(
                    color: colour.withValues(alpha: 0.78),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${rules.pace.label.toUpperCase()} · '
                  '${rules.pace.description}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                // The outline, said out loud.
                //
                // Boards have been cut to bones and fish for a long time and
                // nothing ever mentioned it, which made the whole silhouette
                // system invisible to the person it was built for — a player
                // sees one board at a time and has no way to know the shape was
                // chosen rather than incidental.
                if (rules.shape != FieldShape.ellipse) ...[
                  const SizedBox(height: 3),
                  Text(
                    'CUT TO A ${rules.shape.label.toUpperCase()}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.34),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),

              if (access == LevelAccess.needsPurchase)
                _ForSale(onUnlock: widget.onUnlock)
              else if (!unlocked)
                _Locked(level: level)
              else ...[
                if (trial) ...[
                  const _TrialBanner(),
                  const SizedBox(height: 14),
                ],
                if (endless)
                  _EndlessRecord(
                    bestLevel: widget.progress.endlessBestOn(difficulty),
                  )
                else if (record.played)
                  _Records(record: record)
                else
                  Text(
                    'Not played yet.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 14),
                _ModeBrief(
                  endless: endless,
                  mastery: band == CampaignBand.mastery,
                  completed: widget.progress.completedLevels,
                  mastered: widget.progress.masteredLevels,
                ),
                const SizedBox(height: 14),
                LevelContainsChips(rules: rules),
                const SizedBox(height: 18),
                // Not offered on the three guided levels, which ignore the
                // setting: a lesson that has to land is not a negotiation.
                if (!rules.isTutorial) ...[
                  DifficultyPicker(
                    value: difficulty,
                    enabled: !trial,
                    onChanged: (d) => setState(() => _difficulty = d),
                  ),
                  const SizedBox(height: 14),
                ],
                // Only offered where it means something: with regrowth switched
                // off already, "no regrowth" is not a mode.
                if (rules.regrowth && !endless) ...[
                  _ZenToggle(
                    value: _zen,
                    onChanged: (v) => setState(() => _zen = v),
                  ),
                  const SizedBox(height: 14),
                ],
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () => widget.onPlay(
                      zen: _zen,
                      difficulty: difficulty,
                      restart: false,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: colour,
                      foregroundColor: Palette.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      canResume
                          ? 'RESUME'
                          : _zen
                          ? 'PRACTICE'
                          : trial
                          ? Strings.trialPlay
                          : endless
                          ? 'START RUN'
                          : 'PLAY',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ),
                if (canResume)
                  TextButton(
                    onPressed: () => widget.onPlay(
                      zen: _zen,
                      difficulty: difficulty,
                      restart: true,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.5),
                    ),
                    child: const Text('Start it over'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EndlessRecord extends StatelessWidget {
  const _EndlessRecord({required this.bestLevel});

  final int bestLevel;

  @override
  Widget build(BuildContext context) {
    final best = bestLevel > Campaign.length ? bestLevel - Campaign.length : 0;
    return Text(
      best > 0 ? 'Deepest clear: D$best' : 'No endless depth cleared yet.',
      style: TextStyle(
        color: best > 0
            ? Palette.goalGlow
            : Colors.white.withValues(alpha: 0.45),
        fontSize: 13,
        fontWeight: best > 0 ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}

class _ModeBrief extends StatelessWidget {
  const _ModeBrief({
    required this.endless,
    required this.mastery,
    required this.completed,
    required this.mastered,
  });

  final bool endless;
  final bool mastery;
  final int completed;
  final int mastered;

  @override
  Widget build(BuildContext context) {
    final label = endless
        ? 'ENDLESS RUN'
        : mastery
        ? 'MASTERY · $mastered/${Campaign.length} THREE-STAR CLEARS'
        : 'CAMPAIGN · $completed/${Campaign.length} CLEARED';
    final description = endless
        ? 'Every run starts at depth 1. Each clear advances one depth; a loss '
              'ends the run. Only the deepest clear is saved, and there are no stars.'
        : 'Finish to unlock the next level. Stars measure tap efficiency; '
              'time affects survival, not the rating.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.lockedEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: endless ? Palette.goalGlow : Palette.treat,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    // Levels unlock strictly in order, so there is exactly one thing to do.
    return Row(
      children: [
        Icon(Icons.lock, color: Palette.lockedEdge, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Finish level ${level - 1} to open this one.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

/// Past the free campaign.
///
/// Kept distinct from [_Locked] on purpose: one is "you have not got here yet"
/// and the other is "this is for sale", and answering the wrong one tells a
/// player to do something they cannot.
/// The free look, offered.
///
/// Framed as an invitation rather than a restriction. "One free run" is a gift;
/// "you only get one" is a rule, and the same fact told the second way makes
/// the game sound like it is rationing itself.
class _TrialBanner extends StatelessWidget {
  const _TrialBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Palette.bandPressure.withValues(alpha: 0.10),
        border: Border.all(color: Palette.bandPressure.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Strings.trialTitle.toUpperCase(),
            style: TextStyle(
              color: Palette.bandPressure,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            Strings.trialBlurb,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForSale extends StatelessWidget {
  const _ForSale({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Part of the full campaign — Pressure, Mastery and Endless.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: onUnlock,
            style: OutlinedButton.styleFrom(
              foregroundColor: Palette.dogBody,
              side: BorderSide(color: Palette.dogBody.withValues(alpha: 0.6)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: const Text(
              'SEE WHAT IS IN IT',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Records extends StatelessWidget {
  const _Records({required this.record});

  final LevelRecord record;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Stars(count: record.stars),
        const SizedBox(width: 18),
        _Figure(label: 'Best taps', value: '${record.bestTaps}'),
        const SizedBox(width: 18),
        _Figure(
          label: 'Best time',
          value: '${record.bestTime.toStringAsFixed(1)}s',
        ),
        // Named only where it is not Normal, so the ordinary case stays a clean
        // row of three figures rather than every level explaining itself.
        if (record.difficulty != Difficulty.normal) ...[
          const SizedBox(width: 18),
          _Figure(label: 'Earned on', value: record.difficulty.label),
        ],
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(
              i < count ? Icons.circle : Icons.circle_outlined,
              size: 12,
              color: i < count
                  ? Palette.treat
                  : Palette.treat.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Palette.hudDim,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// What this level is carrying, read straight off its rules.
///
/// Not a spoiler: the board is still hidden by fog, and knowing a level has
/// patrols is the same thing the banner already tells you the moment you arrive.
/// It is the difference between choosing a level and being handed one.
/// The pressures this level actually applies, as tags.
///
/// Public so a test can hold it against [LevelRules] directly: the row is
/// derived from the rules rather than authored per level, and the failure it
/// had — three mechanics missing for as long as it existed — is invisible from
/// the outside and silent in every screenshot.
class LevelContainsChips extends StatelessWidget {
  const LevelContainsChips({required this.rules, super.key});

  final LevelRules rules;

  @override
  Widget build(BuildContext context) {
    // Every pressure the level actually applies, and *only* the ones it does.
    // Heavy ground, cracked ground and sentries were missing here for as long
    // as this row has existed, so a Collapse level's brief promised nothing
    // about the mechanic the whole band is built on.
    final tags = <String>[
      '${rules.pace.label} pace',
      if (rules.regrowth) 'Regrowth',
      if (rules.fog) 'Fog',
      if (rules.hunger) 'Clock',
      if (rules.budget) 'Tap budget',
      if (rules.anchorDensity > 0) 'Walls',
      if (rules.heavyDensity > 0) 'Heavy ground',
      if (rules.springDensity > 0) 'Springs',
      if (rules.faultDensity > 0) 'Cracked ground',
      if (rules.slopeDensity > 0) 'Slopes',
      if (rules.sunkenDensity > 0) 'Sunken ground',
      if (rules.guards > 0) 'Patrols',
      if (rules.sentries > 0) 'Warded lights',
    ];
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Palette.lockedEdge),
            ),
            child: Text(
              tag,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _ZenToggle extends StatelessWidget {
  const _ZenToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Zen',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                // Said plainly, because a mode that quietly does not count is
                // worse than one that does not exist.
                'Nothing grows back. Practice only — no stars, no unlock.',
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
          activeThumbColor: Palette.freeze,
        ),
      ],
    );
  }
}
