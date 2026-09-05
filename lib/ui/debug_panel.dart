import 'package:flutter/material.dart';

import '../game/hexcape_game.dart';
import '../game/tuning.dart';
import '../l10n/strings.dart';
import '../theme/palette.dart';

/// Live tuning (§16). Every value here is one the spec lists as unresolved and
/// needing a real device — tap radius, drift speed, momentum, regrowth rate.
/// Shipping the sliders means they get dialled in by feel in one sitting
/// instead of one constant at a time.
class DebugPanel extends StatefulWidget {
  const DebugPanel({required this.game, super.key});

  final HexcapeGame game;

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  bool _open = false;

  TuningConfig get _tuning => widget.game.tuning;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 6, right: 8),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topRight,
            child: _open ? _panel() : _collapsedButton(),
          ),
        ),
      ),
    );
  }

  Widget _collapsedButton() {
    return IconButton(
      onPressed: () => setState(() => _open = true),
      icon: const Icon(Icons.tune_rounded, size: 20),
      color: Palette.hudDim,
      tooltip: Strings.debug,
    );
  }

  Widget _panel() {
    return Container(
      width: 268,
      constraints: const BoxConstraints(maxHeight: 560),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xF20D1220),
        border: Border.all(color: Palette.plainEdge),
        borderRadius: BorderRadius.circular(12),
      ),
      // Scrollable: the panel now carries enough sliders to overflow a short
      // screen, and a clipped slider is worse than no slider.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  Strings.debug,
                  style: TextStyle(
                    color: Palette.hudDim,
                    fontSize: 10,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'seed ${widget.game.seed}',
                  style: const TextStyle(color: Palette.hudDim, fontSize: 10),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => setState(() => _open = false),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Palette.hudDim,
                  ),
                ),
              ],
            ),
            // Jumping levels is the difference between playtesting a
            // sixty-level curve and playing fifty-nine levels to reach the one
            // in question.
            _frameStats(),
            _levelJump(),
            _toggle(
              Strings.followCampaign,
              _tuning.followCampaign,
              (v) => _tuning.followCampaign = v,
            ),
            _slider(
              Strings.tapRadius,
              _tuning.tapRadius,
              TuningConfig.tapRadiusRange,
              (v) => _tuning.tapRadius = v,
              unit: 'px',
            ),
            _slider(
              Strings.driftMin,
              _tuning.driftMin,
              TuningConfig.driftRange,
              (v) => _tuning.driftMin = v.clamp(0.2, _tuning.driftMax),
              unit: 'hex/s',
              decimals: 2,
            ),
            _slider(
              Strings.driftMax,
              _tuning.driftMax,
              TuningConfig.driftRange,
              (v) => _tuning.driftMax = v.clamp(_tuning.driftMin, 6.0),
              unit: 'hex/s',
              decimals: 2,
            ),
            _slider(
              Strings.momentum,
              _tuning.momentum,
              TuningConfig.momentumRange,
              (v) => _tuning.momentum = v,
              decimals: 1,
            ),
            _slider(
              Strings.regrowDelay,
              _tuning.regrowDelay,
              TuningConfig.regrowDelayRange,
              (v) => _tuning.regrowDelay = v,
              unit: 's',
              decimals: 1,
            ),
            _slider(
              Strings.suffocate,
              _tuning.suffocateSeconds,
              TuningConfig.suffocateRange,
              (v) => _tuning.suffocateSeconds = v,
              unit: 's',
              decimals: 1,
            ),
            _slider(
              Strings.revealFactor,
              _tuning.revealFactor,
              TuningConfig.revealFactorRange,
              (v) => _tuning.revealFactor = v,
              unit: 'x tap',
              decimals: 1,
            ),
            _slider(
              Strings.budgetMultiplier,
              _tuning.budgetMultiplier,
              TuningConfig.budgetRange,
              (v) => _tuning.budgetMultiplier = v,
              unit: 'x par',
              decimals: 2,
              note: 'next level',
            ),
            _slider(
              Strings.hungerPerCell,
              _tuning.hungerSecondsPerCell,
              TuningConfig.hungerRange,
              (v) => _tuning.hungerSecondsPerCell = v,
              unit: 's/cell',
              decimals: 2,
              note: 'next level',
            ),
            _slider(
              Strings.treatSeconds,
              _tuning.treatSeconds,
              TuningConfig.treatSecondsRange,
              (v) => _tuning.treatSeconds = v,
              unit: 's',
              decimals: 1,
            ),
            _slider(
              Strings.treatTaps,
              _tuning.treatTaps,
              TuningConfig.treatTapsRange,
              (v) => _tuning.treatTaps = v,
              decimals: 0,
            ),
            _slider(
              Strings.treatCount,
              _tuning.treatCount,
              TuningConfig.pickupCountRange,
              (v) => _tuning.treatCount = v,
              decimals: 0,
              note: 'next level',
            ),
            _slider(
              Strings.powerupCount,
              _tuning.powerupCount,
              TuningConfig.pickupCountRange,
              (v) => _tuning.powerupCount = v,
              decimals: 0,
              note: 'next level',
            ),
            _slider(
              Strings.anchorDensity,
              _tuning.anchorDensity,
              TuningConfig.anchorDensityRange,
              (v) => _tuning.anchorDensity = v,
              decimals: 2,
              // Density only takes effect on the next level, so changing it
              // never reshuffles the field out from under a run in progress.
              note: 'next level',
            ),
            _slider(
              Strings.heavyDensity,
              _tuning.heavyDensity,
              TuningConfig.heavyDensityRange,
              (v) => _tuning.heavyDensity = v,
              decimals: 2,
              note: 'next level',
            ),
            _slider(
              Strings.volume,
              _tuning.volume,
              TuningConfig.volumeRange,
              (v) => _tuning.volume = v,
              decimals: 2,
            ),
            _slider(
              Strings.juiceScale,
              _tuning.juiceScale,
              TuningConfig.shakeRange,
              (v) => _tuning.juiceScale = v,
              decimals: 2,
            ),
            _toggle(
              Strings.regrowthSound,
              _tuning.regrowthSound,
              (v) => _tuning.regrowthSound = v,
            ),
            _toggle(
              Strings.zenMode,
              _tuning.zenMode,
              (v) => _tuning.zenMode = v,
            ),
            _toggle(
              Strings.showTruePath,
              _tuning.showTruePath,
              (v) => _tuning.showTruePath = v,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _action(Strings.replay, widget.game.retry)),
                const SizedBox(width: 8),
                Expanded(
                  child: _action(Strings.regenerate, widget.game.regenerate),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _frameStats() {
    final game = widget.game;
    final ms = game.frameMs;
    final worst = game.worstFrameMs;
    // 16.7ms is one frame at 60fps; past about 20 the drop is visible.
    final bad = ms > 20 || worst > 50;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Text(
            'frame ${ms.toStringAsFixed(1)}ms  '
            '(${(1000 / ms).round()}fps)',
            style: TextStyle(
              color: bad ? Palette.danger : Palette.hudDim,
              fontSize: 10,
            ),
          ),
          const Spacer(),
          Text(
            'worst ${worst.toStringAsFixed(0)}ms',
            style: TextStyle(
              color: bad ? Palette.danger : Palette.hudDim,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => setState(game.resetFrameStats),
            child: const Icon(
              Icons.refresh_rounded,
              size: 13,
              color: Palette.hudDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelJump() {
    final game = widget.game;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Text(
            'Level',
            style: TextStyle(color: Palette.hudText, fontSize: 11),
          ),
          const Spacer(),
          _step('‹', () {
            if (game.levelNumber > 1) {
              game.startLevel(level: game.levelNumber - 1);
            }
          }),
          SizedBox(
            width: 40,
            child: Text(
              '${game.levelNumber}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Palette.hudText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _step('›', () => game.startLevel(level: game.levelNumber + 1)),
          const SizedBox(width: 8),
          // Asks first. Every star, every best time and every unlocked level,
          // gone on one tap of an unlabelled glyph, was not a defensible thing
          // to leave lying around even in a developer tool.
          _step('↺', _confirmReset),
        ],
      ),
    );
  }

  Future<void> _confirmReset() async {
    final game = widget.game;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.background,
        title: const Text('Erase all progress?'),
        content: const Text(
          'Every star, best time and unlocked level goes. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Palette.danger),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await game.progress?.reset();
    game.startLevel(level: 1);
    if (mounted) {
      setState(() {});
    }
  }

  Widget _step(String glyph, VoidCallback onTap) => InkWell(
    onTap: () => setState(onTap),
    child: Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Palette.plainEdge),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        glyph,
        style: const TextStyle(color: Palette.hudText, fontSize: 14),
      ),
    ),
  );

  Widget _slider(
    String label,
    double value,
    (double, double) range,
    void Function(double) apply, {
    String unit = '',
    int decimals = 0,
    String? note,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(color: Palette.hudText, fontSize: 11),
              ),
              if (note != null) ...[
                const SizedBox(width: 5),
                Text(
                  '($note)',
                  style: const TextStyle(color: Palette.hudDim, fontSize: 9),
                ),
              ],
              const Spacer(),
              Text(
                '${value.toStringAsFixed(decimals)}$unit',
                style: const TextStyle(color: Palette.hudDim, fontSize: 11),
              ),
            ],
          ),
          SizedBox(
            height: 22,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: Palette.tapRingActive,
                inactiveTrackColor: Palette.plainTop,
                thumbColor: Palette.hudText,
              ),
              child: Slider(
                value: value.clamp(range.$1, range.$2),
                min: range.$1,
                max: range.$2,
                onChanged: (v) => setState(() => _tuning.set((_) => apply(v))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, void Function(bool) apply) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Palette.hudText, fontSize: 11),
          ),
          const Spacer(),
          Transform.scale(
            scale: 0.72,
            child: Switch(
              value: value,
              activeThumbColor: Palette.dogBody,
              onChanged: (v) => setState(() => _tuning.set((_) => apply(v))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: () => setState(onPressed),
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.hudText,
        side: const BorderSide(color: Palette.plainEdge),
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
