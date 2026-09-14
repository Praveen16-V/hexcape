import 'package:flutter/material.dart';

import '../game/cloud_save.dart';
import '../game/progress.dart';
import '../theme/palette.dart';
import 'difficulty_picker.dart';

/// The glyph every way into a panel of settings wears: the player's sheet, off
/// the home bar, and the tuning panel that floats over a level.
///
/// They were two different icons — sliders on the home bar, a gear over the
/// board — so one idea looked like two depending on which screen you were
/// standing on, which is the one thing an icon may never do. Declared once so
/// they cannot drift apart again.
const settingsIcon = Icons.settings_rounded;

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
    this.cloud,
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

  /// Progress sync, or null in the tests and previews that do not have one.
  ///
  /// The row it draws is the **only** place in the game that can open a Play
  /// Games sign-in sheet. Everywhere else, sync either already has a session
  /// or does nothing at all — which is what keeps "no accounts, no sign-up"
  /// true for every player who does not come here and ask.
  final CloudSave? cloud;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

/// Taps on the title that reveal the developer row.
///
/// Long enough that nobody arrives by fidgeting, short enough to do one-handed
/// while holding a test device.
const _devGestureTaps = 7;

class _SettingsSheetState extends State<SettingsSheet> {
  Progress get _p => widget.progress;

  /// Counts taps on the SETTINGS title. Not persisted, and the state goes with
  /// the sheet, so closing it puts the count back to zero — a player cannot
  /// accumulate seven taps across a week of visits.
  int _titleTaps = 0;

  /// Whether this sitting has earned the developer row. Ored with the stored
  /// [Progress.developerTools] below, so once the panel is genuinely in use it
  /// stays visible without re-entering the gesture every time.
  bool _devRevealed = false;

  void _tapTitle() {
    if (_devRevealed || _p.developerTools) {
      return;
    }
    _titleTaps++;
    if (_titleTaps >= _devGestureTaps) {
      setState(() => _devRevealed = true);
    }
  }

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
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
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
              // The way into the developer row. Opaque so the whole line is the
              // target, and deliberately silent — no counter, no "3 more taps",
              // nothing a curious player could follow to the end.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _tapTitle,
                child: const Text(
                  'SETTINGS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                  ),
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
                display: _p.volume <= 0
                    ? 'Off'
                    : '${(_p.volume * 100).round()}%',
                onChanged: (v) => _apply(() => _p.setVolume(v)),
              ),
              _Toggle(
                label: 'Music',
                blurb:
                    'A quiet loop under the menus, and quieter still while you '
                    'are playing.',
                value: _p.music,
                onChanged: (v) => _apply(() => _p.setMusic(v)),
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
              if (widget.cloud != null) ...[
                const SizedBox(height: 4),
                _SyncRow(cloud: widget.cloud!, progress: _p),
              ],
              // Hidden once the game is owned, and that is not merely tidiness.
              // `Store.init` already calls `restorePurchases` on every launch,
              // so this button is for the run where that failed — and the only
              // state it can change is an entitlement the app does not yet
              // have. To someone who already owns the game it is a control
              // that cannot do anything, worded like a transaction.
              //
              // The comment this replaces called it required policy. That is
              // Apple's rule, and it applies to a build this game does not
              // have: hexcape ships to Play only, where the launch query above
              // is what restores the entitlement.
              if (widget.onRestore != null && !_p.ownsFullGame) ...[
                const SizedBox(height: 4),
                // Someone who reinstalls, or picks up a second device, needs a
                // way to get back what they paid for that does not involve
                // paying again, for the run where the automatic restore did
                // not land.
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
              // Everything below here is ours, not the player's, and it is not
              // in the sheet at all until the title gesture asks for it. The
              // panel it opens holds a level jump and a button that erases a
              // save; the switch under it opens the paid campaign outright.
              // Scrolling to the bottom of your own settings must not be a way
              // to find either.
              if (_devRevealed || _p.developerTools) ...[
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
                // Nested inside the developer switch rather than sitting beside
                // it, so reaching the paid campaign costs the gesture *and* a
                // deliberate toggle. At that point it grants nothing the level
                // jump in the same panel does not already give away.
                if (_p.developerTools)
                  _Toggle(
                    label: 'Unlock all stages',
                    blurb:
                        'Every level playable, in any order, for testing. Your '
                        'real progress is untouched and comes back when this '
                        'goes off.',
                    value: _p.unlockAllLevels,
                    onChanged: (v) => _apply(() => _p.setUnlockAllLevels(v)),
                  ),
              ],
            ],
          ),
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

/// The progress-sync row: one line of state and one thing to do about it.
///
/// Worded around *progress*, never around an account. A player reading this
/// wants to know whether their stars are safe if the phone goes in a river;
/// "sign in to Google Play Games" answers a question they did not ask.
class _SyncRow extends StatefulWidget {
  const _SyncRow({required this.cloud, required this.progress});

  final CloudSave cloud;
  final Progress progress;

  @override
  State<_SyncRow> createState() => _SyncRowState();
}

class _SyncRowState extends State<_SyncRow> {
  @override
  void initState() {
    super.initState();
    widget.cloud.addListener(_onCloud);
  }

  @override
  void dispose() {
    widget.cloud.removeListener(_onCloud);
    super.dispose();
  }

  void _onCloud() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cloud = widget.cloud;
    final blurb = cloud.busy
        ? 'Syncing…'
        : cloud.error != null
        // The message itself is a plugin string and can be anything, so it is
        // not shown. What a player can act on is "it did not work, try again".
        ? 'Could not sync just now. Your progress is safe on this phone.'
        : cloud.signedIn
        ? 'Your stars and levels follow your Google account to any phone.'
        : 'Off. Progress lives only on this phone — reinstalling loses it.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              cloud.signedIn ? Icons.cloud_done : Icons.cloud_off,
              size: 18,
              color: cloud.signedIn
                  ? Palette.dogBody
                  : Colors.white.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 8),
            const Text(
              'Back up progress',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Text(
            blurb,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              // Disabled rather than hidden while busy: a row that vanishes
              // mid-tap is how a player ends up signing in twice.
              onPressed: cloud.busy
                  ? null
                  : cloud.signedIn
                  ? cloud.sync
                  : cloud.connect,
              style: TextButton.styleFrom(
                foregroundColor: Palette.dogBody,
                padding: EdgeInsets.zero,
              ),
              child: Text(cloud.signedIn ? 'Sync now' : 'Turn on'),
            ),
          ),
        ),
      ],
    );
  }
}
