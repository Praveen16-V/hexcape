import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/daily.dart';
import 'game/entitlements.dart';
import 'game/haptics.dart';
import 'game/hexcape_game.dart';
import 'game/pets.dart';
import 'game/progress.dart';
import 'game/store.dart';
import 'game/tuning.dart';
import 'l10n/strings.dart';
import 'theme/palette.dart';
import 'ui/debug_panel.dart';
import 'ui/home_screen.dart';
import 'ui/hud.dart';
import 'ui/level_detail.dart';
import 'ui/level_map.dart';
import 'ui/pause_overlay.dart';
import 'ui/paywall_sheet.dart';
import 'ui/pet_picker.dart';
import 'ui/reference_sheet.dart';
import 'ui/result_overlay.dart';
import 'ui/settings_sheet.dart';

/// Which of the three mutually-exclusive screens is on top.
///
/// Not a `Navigator` route for any of them — see [GameShell] — so this is the
/// only thing that actually changes when the player moves between them.
enum _Screen { home, campaign, level }

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

/// Home, map and level, in one widget.
///
/// Deliberately **not** a `Navigator` with three routes. The game is one
/// long-lived [HexcapeGame]: it owns loaded audio, a running loop and a level
/// in progress, and pushing a route over it would tear the `GameWidget` down
/// and rebuild it on every visit to the map. Keeping all three children
/// mounted and swapping which one is on screen means moving between them
/// costs nothing and comes back to exactly what was there, which is what a
/// paused level should do.
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
    ..pet = Pets.byId(widget.progress.pet, stars: widget.progress.totalStars);

  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  /// Which of the three screens is on top. Starts on the home screen, always.
  _Screen _screen = _Screen.home;

  /// Bumped every time the campaign map is opened, so it re-centres on the
  /// frontier each time rather than only once ever — it stays mounted for the
  /// app's life, so `didUpdateWidget` is the only way it can tell it has been
  /// navigated to again.
  int _campaignToken = 0;

  late final Store _store = Store(widget.progress);

  /// The level currently built and running, if any.
  ///
  /// Without this, going to the map and coming back called `requestLevel`,
  /// which *rebuilds the board* — so stepping out of a level for two seconds
  /// silently threw away the run. Now the same level in progress is resumed.
  int? _activeLevel;

  /// The frontier level — the furthest the player has reached — clamped to
  /// what actually exists. What Play, on the home screen, plays.
  int get _frontier => math.min(widget.progress.unlocked, MapLayout.tiles);

  @override
  void initState() {
    super.initState();
    _applySettings();
    // Nothing awaits this. The free game must never wait on billing, which is
    // unavailable on some devices and absent entirely offline.
    _store
      ..addListener(_onStore)
      ..start();
  }

  void _onStore() {
    if (mounted) {
      setState(() {});
    }
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
      ..hintsEnabled = p.hints
      ..developerTools = p.developerTools;
    Haptics.enabled = p.haptics;
    if (_game.isReady) {
      _game.syncDeveloperTools();
    }
  }

  Future<void> _openReference() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ReferenceSheet(
        // Clamped: someone sitting at the paywall should not be handed the
        // patrol entry for a band they have not bought.
        unlocked: Entitlements.revealCeiling(
          unlocked: widget.progress.unlocked,
          owned: widget.progress.ownsFullGame,
          trialUsed: widget.progress.trialUsed,
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SettingsSheet(
        progress: widget.progress,
        onChanged: _applySettings,
        onRestore: _store.available ? _store.restore : null,
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _store
      ..removeListener(_onStore)
      ..dispose();
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _openPaywall() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PaywallSheet(store: _store),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _selectLevel(int level) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => LevelDetail(
        level: level,
        progress: widget.progress,
        inProgress: _activeLevel == level && _game.isReady && !_game.isOver,
        initialZen: _activeLevel == level && _game.isReady && !_game.isOver
            ? _tuning.zenMode
            : false,
        onUnlock: () {
          Navigator.of(context).pop();
          _openPaywall();
        },
        onPlay: ({required bool zen, required bool restart}) {
          Navigator.of(context).pop();
          // Compared before it is written, or the comparison is always false.
          // Switching Zen on has to rebuild the board: the run in progress was
          // played under the other set of rules and its result would be
          // recorded — or not recorded — under this one.
          final modeChanged = zen != _tuning.zenMode;
          _tuning.zenMode = zen;
          _openLevel(level, restart: restart || modeChanged);
        },
      ),
    );
  }

  void _openLevel(int level, {bool restart = false}) {
    final resuming =
        !restart && _activeLevel == level && _game.isReady && !_game.isOver;

    // Checked here as well as in the two places that offer the button, because
    // this is the one function every route into a level goes through — the map,
    // the detail sheet, "next level" and the debug jump alike.
    //
    // Skipped entirely when resuming: **a run already in progress belongs to
    // the player, whatever the entitlement now says.** The trial spends itself
    // on the way in, so re-checking here would read as `needsPurchase` and
    // bounce someone to the paywall for stepping out to the map and back in the
    // middle of the very level the trial had just given them.
    if (!resuming) {
      final access = Entitlements.accessTo(
        level,
        unlocked: widget.progress.unlocked,
        owned: widget.progress.ownsFullGame,
        trialUsed: widget.progress.trialUsed,
      );
      switch (access) {
        case LevelAccess.needsPurchase:
          _openPaywall();
          return;
        case LevelAccess.needsProgress:
          // Not an offer. Telling someone to buy a level they simply have not
          // reached is the one thing the access split exists to prevent.
          return;
        case LevelAccess.trial:
          widget.progress.setTrialUsed();
        case LevelAccess.open:
          break;
      }
    }

    setState(() => _screen = _Screen.level);
    if (resuming) {
      _game.resumeRun();
      return;
    }
    _activeLevel = level;
    _game.paused = false;
    _game.requestLevel(level);
  }

  /// Starts today's board.
  ///
  /// `_activeLevel` is cleared rather than set: a daily borrows a campaign
  /// level's number, and leaving it set would make the detail sheet for that
  /// level offer to "resume" a run that is not it.
  void _openDaily() {
    _activeLevel = null;
    _tuning.zenMode = false;
    setState(() => _screen = _Screen.level);
    _game.paused = false;
    _game.startDailyRun(Daily.forDate(DateTime.now()));
  }

  /// Opens the hundred-level campaign map — what pause and a result screen's
  /// "back to map" both mean, and what the home screen's own Campaign chip
  /// opens.
  void _openCampaign() {
    // Paused rather than merely hidden: an offstage widget still gets its
    // ticks, so without this the hunger clock would keep running on a level
    // nobody is looking at.
    _game.paused = true;
    setState(() {
      _screen = _Screen.campaign;
      _campaignToken++;
    });
  }

  /// Back to the front door.
  void _openHome() {
    _game.paused = true;
    setState(() => _screen = _Screen.home);
  }

  Future<void> _openPets() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PetPicker(
        stars: widget.progress.totalStars,
        owned: widget.progress.ownsFullGame,
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
        Overlays.result: (_, game) => ResultOverlay(
          game: game,
          onMap: _openCampaign,
          onHome: _openHome,
          owned: widget.progress.ownsFullGame,
          dailyStreak: widget.progress.dailyStreak,
          onUnlock: _openPaywall,
        ),
        Overlays.pause: (_, game) => PauseOverlay(
          game: game,
          onMap: () {
            game.resumeRun();
            _openCampaign();
          },
          onHome: () {
            game.resumeRun();
            _openHome();
          },
          onReference: _openReference,
        ),
      },
    );

    return PopScope(
      // Back leaves the campaign map for home, the level for the campaign map
      // (by way of the pause screen), and only leaves the app from home
      // itself. Backing out of the game entirely mid-run would throw away a
      // level the player was in the middle of.
      canPop: _screen == _Screen.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        switch (_screen) {
          case _Screen.home:
            break; // unreachable: canPop is true here.
          case _Screen.campaign:
            _openHome();
          case _Screen.level:
            // Back opens the pause screen rather than dropping straight to
            // the map. Leaving is a choice worth making on purpose, and it is
            // now one of four things the player might want here.
            if (_game.isPausedByPlayer || _game.isOver) {
              _openCampaign();
            } else {
              _game.pauseRun();
            }
        }
      },
      child: Scaffold(
        backgroundColor: Palette.background,
        body: Stack(
          children: [
            Offstage(
              offstage: _screen != _Screen.home,
              child: TickerMode(
                enabled: _screen == _Screen.home,
                child: HomeScreen(
                  progress: widget.progress,
                  pet: _game.pet,
                  onPlay: () => _selectLevel(_frontier),
                  onCampaign: _openCampaign,
                  onTutorial: () {
                    _tuning.zenMode = false;
                    _openLevel(1, restart: true);
                  },
                  onDaily: _openDaily,
                  onPets: _openPets,
                  onSettings: _openSettings,
                  onReference: _openReference,
                  onUnlock: _openPaywall,
                ),
              ),
            ),
            Offstage(
              offstage: _screen != _Screen.campaign,
              child: TickerMode(
                enabled: _screen == _Screen.campaign,
                child: LevelMap(
                  progress: widget.progress,
                  onSelect: _selectLevel,
                  onBack: _openHome,
                  showToken: _campaignToken,
                ),
              ),
            ),
            Offstage(
              offstage: _screen != _Screen.level,
              child: TickerMode(
                enabled: _screen == _Screen.level,
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
