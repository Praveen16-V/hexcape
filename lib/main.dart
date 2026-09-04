import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/haptics.dart';
import 'game/hexcape_game.dart';
import 'game/pets.dart';
import 'game/progress.dart';
import 'game/tuning.dart';
import 'l10n/strings.dart';
import 'theme/palette.dart';
import 'ui/debug_panel.dart';
import 'ui/hud.dart';
import 'ui/level_map.dart';
import 'ui/pet_picker.dart';
import 'ui/result_overlay.dart';
import 'ui/settings_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Palette.background,
    ),
  );
  // Loaded before the first frame so the game can open on the level the player
  // actually got to, rather than starting at one and jumping.
  final progress = await Progress.load();
  runApp(HexcapeApp(progress: progress));
}

class HexcapeApp extends StatelessWidget {
  const HexcapeApp({required this.progress, super.key});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Strings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.dogBody,
          brightness: Brightness.dark,
        ),
      ),
      home: GameShell(progress: progress),
    );
  }
}

/// Map and level, in one widget.
///
/// Deliberately **not** a `Navigator` with two routes. The game is one long-lived
/// [HexcapeGame]: it owns loaded audio, a running loop and a level in progress,
/// and pushing a route over it would tear the `GameWidget` down and rebuild it on
/// every visit to the map. Keeping both children mounted and swapping which one
/// is on screen means going to the map costs nothing and comes back to exactly
/// what was there, which is what a paused level should do.
class GameShell extends StatefulWidget {
  const GameShell({required this.progress, super.key});

  final Progress progress;

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell>
    with SingleTickerProviderStateMixin {
  late final TuningConfig _tuning = TuningConfig();
  late final HexcapeGame _game = HexcapeGame(tuning: _tuning)
    ..progress = widget.progress
    ..pet = Pets.byId(
      widget.progress.pet,
      stars: widget.progress.totalStars,
    );

  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  /// Whether the level is on screen. The map is what you get when it is not.
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _applySettings();
  }

  /// Copies the player's settings onto the live game.
  ///
  /// Called on launch and after every change, rather than read where they are
  /// used: the tuning object is what the whole game already reads, so pushing
  /// into it means a setting takes effect mid-level instead of at the next one.
  void _applySettings() {
    final p = widget.progress;
    _tuning
      ..volume = p.volume
      ..regrowthSound = p.regrowthSound
      ..reducedMotion = p.reducedMotion
      ..hintsEnabled = p.hints;
    Haptics.enabled = p.haptics;
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SettingsSheet(
        progress: widget.progress,
        onChanged: _applySettings,
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _openLevel(int level) {
    _game.paused = false;
    setState(() => _playing = true);
    _game.requestLevel(level);
  }

  void _openMap() {
    // Paused rather than merely hidden: an offstage widget still gets its
    // ticks, so without this the hunger clock would keep running on a level
    // nobody is looking at.
    _game.paused = true;
    setState(() => _playing = false);
  }

  Future<void> _openPets() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PetPicker(
        stars: widget.progress.totalStars,
        selected: _game.pet.id,
        onSelected: (pet) {
          widget.progress.choosePet(pet.id);
          setState(() => _game.pet = pet);
        },
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = GameWidget<HexcapeGame>(
      game: _game,
      overlayBuilderMap: {
        Overlays.hud: (_, game) => Hud(game: game),
        Overlays.debug: (_, game) => DebugPanel(game: game),
        Overlays.result: (_, game) =>
            ResultOverlay(game: game, onMap: _openMap),
      },
    );

    return PopScope(
      // Back goes to the map from a level, and only leaves the app from the
      // map itself. Backing out of the game entirely mid-run would throw away
      // a level the player was in the middle of.
      canPop: !_playing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _playing) {
          _openMap();
        }
      },
      child: Scaffold(
        backgroundColor: Palette.background,
        body: Stack(
          children: [
            Offstage(
              offstage: _playing,
              child: TickerMode(
                enabled: !_playing,
                child: LevelMap(
                  progress: widget.progress,
                  onPlay: _openLevel,
                  onPets: _openPets,
                  onSettings: _openSettings,
                ),
              ),
            ),
            Offstage(
              offstage: !_playing,
              child: TickerMode(
                enabled: _playing,
                child: AnimatedBuilder(
                  animation: _ticker,
                  builder: (context, child) {
                    // The screen desaturates as the run ends (§10). Applying
                    // the filter only when it is actually doing something keeps
                    // the saveLayer it costs off every normal frame.
                    final despair = _game.isReady && !_tuning.reducedMotion
                        ? _game.despair
                        : 0.0;
                    if (despair < 0.01) {
                      return child!;
                    }
                    return ColorFiltered(
                      colorFilter: ColorFilter.matrix(
                        _saturation(1 - despair * 0.85),
                      ),
                      child: child!,
                    );
                  },
                  child: game,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Luminance-preserving saturation matrix. [s] of 1 is untouched, 0 is grey.
List<double> _saturation(double s) {
  const rw = 0.2126;
  const gw = 0.7152;
  const bw = 0.0722;
  final r = (1 - s) * rw;
  final g = (1 - s) * gw;
  final b = (1 - s) * bw;
  return [
    r + s, g, b, 0, 0, //
    r, g + s, b, 0, 0, //
    r, g, b + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}
