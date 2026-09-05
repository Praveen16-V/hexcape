import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import '../audio/sfx.dart';
import '../components/dog_component.dart';
import '../components/effects_component.dart';
import '../components/field_component.dart';
import '../entities/dog.dart';
import '../entities/guard.dart';
import '../entities/pickup.dart';
import '../gen/level_generator.dart';
import '../gen/pathfinder.dart';
import '../gen/silhouette.dart';
import '../hex/hex_cell.dart';
import '../hex/hex_coord.dart';
import '../hex/hex_grid.dart';
import '../hex/hex_layout.dart';
import '../systems/input_system.dart';
import '../systems/hunger_system.dart';
import '../systems/pickup_system.dart';
import '../systems/regrowth_system.dart';
import '../systems/streak_system.dart';
import '../systems/reveal_system.dart';
import '../systems/softlock_system.dart';
import '../theme/palette.dart';
import 'daily.dart';
import 'haptics.dart';
import 'juice.dart';
import 'level_rules.dart';
import 'pets.dart';
import 'progress.dart';
import 'tutorial.dart';
import 'tuning.dart';

const _sqrt3 = 1.7320508075688772;

enum GamePhase {
  /// Generated and drawn, but nothing moves until the first tap. Gives the
  /// player a moment to read the field, and means the boxed-in timer cannot
  /// run before they have had a chance to do anything (§12.5).
  idle,

  playing,

  /// Reached the food. The shatter wave is running.
  won,

  /// The field closed in (§10).
  crushed,

  /// The hunger bar ran out. Too slow, rather than too wasteful.
  starved,

  /// No route to the food remains from here (§4).
  softLocked,
}

/// Overlay keys, matched by [GameWidget.overlayBuilderMap].
class Overlays {
  Overlays._();
  static const hud = 'hud';
  static const debug = 'debug';
  static const result = 'result';
  static const pause = 'pause';
}

/// The star rating, as a pure function of the three numbers it depends on.
///
/// Separated from the game so it can be checked across every level in the
/// campaign without standing up a running game — which is how the old fixed
/// bands were able to be wrong for thirty levels without anything noticing.
///
/// [budget] is null on a level that does not ration taps.
int starsFor({required int taps, required int par, int? budget}) {
  final used = math.max(0, taps - par);
  if (used == 0) {
    return 3;
  }
  // A level with no budget still has to rate, or the tutorial would hand out
  // three stars for anything at all; it borrows a nominal allowance so the
  // rating means the same thing everywhere.
  final ceiling = budget ?? (par * 1.5).ceil();
  final allowance = math.max(2, ceiling - par);
  final fraction = used / allowance;
  if (fraction <= threeStarShare) {
    return 3;
  }
  if (fraction <= twoStarShare) {
    return 2;
  }
  return 1;
}

/// Inclusive tap cutoffs for the two visible mastery bands.
({int three, int two}) starTargetsFor({required int par, int? budget}) {
  final ceiling = budget ?? (par * 1.5).ceil();
  final allowance = math.max(2, ceiling - par);
  int cutoff(double share) => par + (allowance * share + 1e-9).floor();
  return (three: cutoff(threeStarShare), two: cutoff(twoStarShare));
}

/// The share of a level's allowance each band covers.
const threeStarShare = 0.35;
const twoStarShare = 0.75;

class HexcapeGame extends FlameGame with TapCallbacks {
  HexcapeGame({required this.tuning});

  final TuningConfig tuning;

  late GeneratedLevel level;
  late HexGrid grid;
  late HexLayout layout;
  late Dog dog;

  final math.Random _idleRng = math.Random();
  final RegrowthSystem _regrowth = RegrowthSystem();
  final HungerSystem hunger = HungerSystem();

  /// Powerups currently running. Deliberately not folded into [tuning] — that
  /// holds the player's settings, and an expiring effect must never leave them
  /// permanently changed.
  final ActiveEffects powerups = ActiveEffects();

  final StreakSystem streak = StreakSystem();
  final Juice juice = Juice();
  final Sfx sfx = Sfx();
  final Heartbeat _heartbeat = Heartbeat();

  /// 1 -> 0 after she spots the bone. Drives the alert pose.
  double barkFlash = 0;

  /// 1 -> 0 after a treat. Drives the tail wag.
  double wagBoost = 0;

  /// 1 -> 0 after something snapped shut beside her. Drives the flinch.
  double startleFlash = 0;

  /// Seconds until she might bark again of her own accord.
  double _nextIdleBark = 0;

  bool _spottedBone = false;

  List<Pickup> pickups = const [];

  /// Patrols, and the ground they are lighting this frame (§6.1).
  ///
  /// The lit set is recomputed once per update rather than asked for whenever
  /// something wants it: the dog reads it, the renderer reads it and the catch
  /// check reads it, and all three must agree about the same instant.
  List<Guard> guards = const [];
  Set<HexCoord> guardedCells = const {};

  /// Stops one patrol from billing her every frame she stands in its light.
  double _caughtCooldown = 0;

  /// Stops two springs from volleying her back and forth with no input.
  double _springCooldown = 0;

  /// The route scent is currently lighting, and the field it was computed for.
  ///
  /// Recomputed when the board changes rather than every frame: a Dijkstra over
  /// two hundred cells is cheap but not free, and scent runs for five seconds —
  /// three hundred frames of solving the same problem.
  List<HexCoord> scentPath = const [];
  int _scentFieldVersion = -1;

  /// Seconds since anything useful happened — no hex opened, and she has not
  /// reached a new cell. Drives the directional hint (§8).
  double sinceProgress = 0;

  /// How long a player is left to work it out before being nudged.
  ///
  /// Long on purpose. The hint answers being *lost*, which is a real state the
  /// fog can produce; it must not answer *thinking*, which is the game. Seven
  /// seconds of nothing at all is well past deliberation.
  static const hintAfter = 7.0;

  /// The coat she is wearing (§9.2). Purely cosmetic — see [Pet].
  Pet pet = Pets.scout;

  /// A transient line at the top of the board, for things that need words.
  String? banner;
  double bannerFor = 0;
  final SoftlockSystem _softlock = SoftlockSystem();
  final EffectsComponent effects = EffectsComponent();

  GamePhase phase = GamePhase.idle;

  /// Bumped when a whole new level is built. The renderer uses it to know when
  /// to re-sort its draw order.
  int levelVersion = 0;

  /// Bumped whenever any cell changes state, so the dog knows to re-route and
  /// the soft-lock check knows to re-run.
  int fieldVersion = 0;

  /// Always-running clock. Drives idle animation and regrowth timestamps.
  double elapsed = 0;

  /// Play-time only. This is the one shown to the player, and it deliberately
  /// does not drive the star rating (§12.4).
  double levelTime = 0;

  int taps = 0;
  int seed = 0;

  /// Which level of the campaign is being played. Past [Campaign.length] this
  /// is an endless run.
  int levelNumber = 1;

  late LevelRules rules;

  /// The scripted opening, on tutorial levels only.
  Tutorial? tutorial;

  /// The cell the tutorial is pointing at, resolved each frame for the renderer.
  HexCoord? tutorialTarget;

  /// Saved progress, or null before it has loaded.
  Progress? progress;

  bool get isLastCampaignLevel => levelNumber >= Campaign.length;

  /// Taps allowed this run, derived from par. Spending them all does not end
  /// the run — see [_updateRun].
  int tapBudget = 0;

  int get tapsLeft => math.max(0, tapBudget - taps);

  /// Cells the player could clear right now, cached each frame for the
  /// renderer.
  Set<HexCoord> editable = const {};

  /// 1 -> 0 flash on the tap ring, so an out-of-range tap teaches the rule.
  double tapRingFlash = 0;

  /// 0 -> 1 as the dog gives up. Drives the dropped ears and closed eye.
  double despair = 0;

  /// Whether the run ended because the taps ran out rather than because the
  /// anchors left no route at all. The two failures deserve different words —
  /// one is your fault, the other is the board's.
  bool lockedByBudget = false;

  /// When the field first started closing in. The onboarding line about
  /// regrowth is shown against this, so the third idea is taught at the moment
  /// it becomes true rather than on a tap count (§12.5).
  double? firstRegrowthAt;

  double _winWave = 0;
  double _crushWave = 0;
  bool _ready = false;

  int get par => level.par;

  /// Stars from taps, never from the clock (§12.4).
  ///
  /// Measured against the **allowance the level granted** — the gap between par
  /// and the budget — rather than against fixed multiples of par.
  ///
  /// Fixed multiples were quietly broken at both ends of the campaign. The
  /// bands were 1.05x par for three stars and 1.25x for two, but the budget
  /// falls to 1.06x par by level sixty: with par 30 the budget was 32 taps and
  /// the three-star cutoff was also 32, so *every* win at level sixty scored
  /// full marks, and one star had been unreachable since about level thirty-three
  /// because you would have run out of taps before you could score that badly.
  ///
  /// Worse, a treat raises [tapBudget] but never par, so under the old rule
  /// spending the taps a treat granted pushed you into a lower band. The reward
  /// was wired to cost you a star.
  ///
  /// Scaling to the allowance fixes both: it fits a 1.70x band and a 1.06x band
  /// without either collapsing, and a treat widens the allowance it is measured
  /// against instead of eating into it.
  int get stars =>
      starsFor(taps: taps, par: par, budget: budgetLimited ? tapBudget : null);

  ({int three, int two}) get starTargets =>
      starTargetsFor(par: par, budget: budgetLimited ? tapBudget : null);

  /// Rolling frame time, in milliseconds.
  ///
  /// Here because "it feels smoother now" is not a measurement, and the stutter
  /// that prompted this came and went with load rather than with any one level.
  double frameMs = 16.7;
  double worstFrameMs = 0;

  void _trackFrame(double dt) {
    final ms = dt * 1000;
    // Long enough to smooth the noise, short enough to show a stall arriving.
    frameMs += (ms - frameMs) * 0.08;
    if (ms > worstFrameMs) {
      worstFrameMs = ms;
    }
  }

  void resetFrameStats() => worstFrameMs = 0;

  bool get isReady => _ready;

  /// The reach a tap actually has right now, Radius+ included. Everything that
  /// asks about the tap radius must go through this, or the ring on screen and
  /// the rule being enforced would drift apart.
  double get effectiveTapRadius => baseTapRadius * powerups.tapRadiusMultiplier;

  double get baseTapRadius => tuning.tapRadiusFor(layout.width);

  EdgeInsets _hudInsets = const EdgeInsets.fromLTRB(14, 96, 14, 48);
  EdgeInsets get hudInsets => _hudInsets;

  /// The HUD reports its measured bounds, including safe areas and text scale.
  void setHudInsets(EdgeInsets insets) {
    if (_hudInsets == insets) return;
    _hudInsets = insets;
    if (_ready) _recomputeLayout();
  }

  bool get isOver =>
      phase == GamePhase.won ||
      phase == GamePhase.crushed ||
      phase == GamePhase.starved ||
      phase == GamePhase.softLocked;

  @override
  Color backgroundColor() => Palette.background;

  @override
  Future<void> onLoad() async {
    // Awaited before the first frame so the opening taps are never the silent
    // ones — a game that starts mute and finds its voice a second later feels
    // broken rather than loading.
    await sfx.load();
    await addAll([FieldComponent(this), effects, DogComponent(this)]);
    // Whatever the map asked for while audio was still loading, else wherever
    // the player got to. Without honouring the request here, tapping a level
    // during the first second of the app would generate it and then have it
    // silently replaced by this line.
    startLevel(level: _requestedLevel ?? progress?.unlocked ?? 1);
    overlays.add(Overlays.hud);
    syncDeveloperTools();
  }

  /// The daily board being played, or null on a campaign or endless run.
  ///
  /// Sticky across [retry] and [regenerate] — retrying today's board is still
  /// today's board — and cleared by every route that starts something else.
  DailyChallenge? daily;

  bool get isDaily => daily != null;

  /// Starts today's board. Its [levelNumber] is the level it borrows its rules
  /// from, so everything that reasons about difficulty keeps working; only what
  /// gets *written* at the end differs.
  /// Deferred by a frame like [requestLevel], and for the same reason: the
  /// board is fitted to the widget's size, which is stale at the moment the map
  /// hands over.
  void startDailyRun(DailyChallenge challenge) {
    daily = challenge;
    _request(challenge.sourceLevel);
  }

  /// Builds a level and resets everything that belongs to a run.
  void startLevel({int? level, bool reuseSeed = false}) {
    levelNumber = level ?? levelNumber;
    rules = daily?.rules ?? Campaign.rulesFor(levelNumber);
    if (tuning.followCampaign) {
      _applyRules(rules);
    }
    seed = rules.seed;

    this.level = LevelGenerator.generate(
      LevelSpec(
        seed: rules.seed,
        columns: rules.columns,
        rows: rules.rows,
        anchorDensity: tuning.anchorDensity,
        heavyDensity: tuning.heavyDensity,
        springDensity: tuning.springDensity,
        faultDensity: tuning.faultDensity,
        guards: tuning.guardCount,
        guardSpeed: tuning.guardSpeed,
        treats: tuning.treatCount.round(),
        powerups: tuning.powerupCount.round(),
        treatSeconds: tuning.treatSeconds,
        treatTaps: tuning.treatTaps.round(),
        offeredPowerups: rules.offeredPowerups,
        powerupRotation: rules.powerupRotation,
        shape: rules.shape,
      ),
    );
    grid = this.level.grid;
    levelVersion++;
    fieldVersion++;

    _recomputeLayout();

    // The dog starts standing in the one open cell on the board. Everything
    // else is solid, so the route is discovered rather than read (§3.2).
    grid.at(grid.start)!.clear(0);
    dog = Dog(position: layout.toPixel(grid.start), cell: grid.start);

    // A level with no budget still has one, set out of reach, so every path
    // that reasons about affordability keeps working untouched.
    tapBudget = tuning.budgetEnabled
        ? (this.level.par * tuning.budgetMultiplier).ceil()
        : _unlimitedTaps;
    pickups = this.level.pickups;
    guards = this.level.guards;
    guardedCells = const {};
    scentPath = const [];
    _scentFieldVersion = -1;
    _caughtCooldown = 0;
    _springCooldown = 0;
    powerups.clear();
    hunger.reset(
      par: this.level.par,
      secondsPerCell: tuning.hungerSecondsPerCell,
    );
    if (tuning.fogEnabled) {
      _revealAround();
    } else {
      for (final cell in grid.all) {
        cell.revealed = true;
      }
    }

    tutorial = Tutorial.forLevel(levelNumber);
    tutorialTarget = null;
    overlays.remove(Overlays.pause);
    paused = false;

    phase = GamePhase.idle;
    elapsed = 0;
    levelTime = 0;
    taps = 0;
    despair = 0;
    firstRegrowthAt = null;
    lockedByBudget = false;
    _winWave = 0;
    _crushWave = 0;
    tapRingFlash = 0;
    editable = const {};

    effects.clear();
    streak.reset();
    juice.reset();
    _heartbeat.reset();
    barkFlash = 0;
    wagBoost = 0;
    startleFlash = 0;
    _nextIdleBark = 6 + _idleRng.nextDouble() * 10;
    _spottedBone = false;
    sinceProgress = 0;
    banner = rules.introduces;
    bannerFor = banner == null ? 0 : 6;
    _softlock.reset();
    overlays.remove(Overlays.result);
    _ready = true;
  }

  /// Say one line, briefly. Used for the charge powerups, which wait for a tap
  /// and so have to tell the player that they are waiting, and for the level a
  /// mechanic first appears on.
  void announce(String text, {double seconds = 4}) {
    if (text.isEmpty) {
      return;
    }
    banner = text;
    bannerFor = seconds;
  }

  /// Whether the player has stopped the run themselves.
  ///
  /// Distinct from Flame's [paused], which the shell also sets when the map is
  /// on screen. Only this one means "the player asked for a break", and only
  /// this one puts an overlay up.
  bool get isPausedByPlayer => overlays.isActive(Overlays.pause);

  void pauseRun() {
    if (!_ready || isOver || isPausedByPlayer) {
      return;
    }
    paused = true;
    overlays.add(Overlays.pause);
  }

  void resumeRun() {
    overlays.remove(Overlays.pause);
    paused = false;
  }

  /// Shows or hides the tuning panel to match the setting. Called on load and
  /// whenever the setting changes, so turning it on does not require a restart.
  void syncDeveloperTools() {
    if (tuning.developerTools) {
      overlays.add(Overlays.debug);
    } else {
      overlays.remove(Overlays.debug);
    }
  }

  int? _requestedLevel;

  /// Asked for by the map.
  ///
  /// Deferred by a frame on purpose. The level is fitted to the widget's size,
  /// and the game widget has not been laid out yet at the moment the map hands
  /// over — generating here would fit the board to a stale size and then have
  /// to rescale it on the very next frame.
  void requestLevel(int level) {
    // The map only ever asks for campaign levels. Without this, going from a
    // daily to a campaign level would keep the daily's rules and record the
    // clear against the wrong thing.
    daily = null;
    _request(level);
  }

  void _request(int level) {
    _requestedLevel = level;
    if (!_ready) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_requestedLevel != null) {
        startLevel(level: _requestedLevel);
        _requestedLevel = null;
      }
    });
  }

  void retry() => startLevel(reuseSeed: true);

  void regenerate() => startLevel();

  /// Onward. Past the end of the campaign this keeps going into endless.
  void nextLevel() {
    daily = null;
    startLevel(level: levelNumber + 1);
  }

  /// Past the authored campaign.
  bool get isEndless => levelNumber > Campaign.length;

  /// How far past them. Endless is counted in depth rather than level number
  /// because "level 78" says nothing, while "depth 18" is a score.
  int get depth => levelNumber - Campaign.length;

  /// The last authored level. Finishing it is the only ending the game has.
  bool get isFinalLevel => levelNumber == Campaign.length;

  /// Back to the top of endless. A run is the unit there, not a level, so
  /// losing at depth 12 and retrying that one board would be scoring a
  /// marathon by the last mile.
  void startEndlessRun() {
    daily = null;
    startLevel(level: Campaign.length + 1);
  }

  /// Replays this authored level under its scored rules after Zen practice.
  void startScoredRun() {
    tuning.zenMode = false;
    retry();
  }

  /// Taps for a level that does not ration them. Large enough never to bind,
  /// small enough that arithmetic on it cannot overflow anything.
  static const _unlimitedTaps = 1 << 20;

  bool get budgetLimited => tapBudget < _unlimitedTaps;

  /// Copies a level's definition into the live tuning values, so every existing
  /// read of [tuning] keeps working and the debug panel keeps editing exactly
  /// what is running.
  void _applyRules(LevelRules r) {
    tuning
      ..regrowthEnabled = r.regrowth
      ..fogEnabled = r.fog
      ..budgetEnabled = r.budget
      ..hungerEnabled = r.hunger
      ..anchorDensity = r.anchorDensity
      ..heavyDensity = r.heavyDensity
      ..springDensity = r.springDensity
      ..faultDensity = r.faultDensity
      ..guardCount = r.guards
      ..guardSpeed = r.guardSpeed
      ..treatCount = r.treats.toDouble()
      ..powerupCount = r.powerups.toDouble()
      ..treatSeconds = r.treatSeconds
      ..treatTaps = r.treatTaps.toDouble()
      ..regrowDelay = r.regrowDelay
      ..budgetMultiplier = r.budgetMultiplier
      ..hungerSecondsPerCell = r.hungerSecondsPerCell;
  }

  /// Fit the silhouette to the screen. The shape itself is defined in
  /// resolution-independent units, so a resize rescales the same level rather
  /// than generating a different one.
  void _recomputeLayout() {
    final previous = _ready ? layout : null;
    final bounds = unitBounds(grid.cells.keys);

    // Cell positions are centres, so allow half a hex of bleed on every side.
    final unitWidth = (bounds.maxX - bounds.minX) + _sqrt3;
    final unitHeight = (bounds.maxY - bounds.minY) + 2.0;

    final availableWidth = math.max(1.0, size.x - _hudInsets.horizontal);
    final availableHeight = math.max(1.0, size.y - _hudInsets.vertical);
    final hexSize = math.min(
      availableWidth / unitWidth,
      availableHeight / unitHeight,
    );

    final unitCentreX = (bounds.minX + bounds.maxX) / 2;
    final unitCentreY = (bounds.minY + bounds.maxY) / 2;
    final screenCentre = Offset(
      _hudInsets.left + availableWidth / 2,
      _hudInsets.top + availableHeight / 2,
    );

    layout = HexLayout(
      size: hexSize,
      origin:
          screenCentre - Offset(unitCentreX * hexSize, unitCentreY * hexSize),
    );

    // Carry the dog across the rescale so a resize mid-run is not a teleport.
    if (previous != null) {
      final unit = Offset(
        (dog.position.dx - previous.origin.dx) / previous.size,
        (dog.position.dy - previous.origin.dy) / previous.size,
      );
      dog.position = layout.origin + unit * layout.size;
      dog.velocity *= layout.size / previous.size;
    }
  }

  @override
  void renderTree(Canvas canvas) {
    final shake = juice.offset;
    if (shake == Offset.zero) {
      super.renderTree(canvas);
      return;
    }
    canvas.save();
    canvas.translate(shake.dx, shake.dy);
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (_ready) {
      _recomputeLayout();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_ready) {
      return;
    }

    // Hit-stop freezes the simulation but not the presentation: shards keep
    // flying and flashes keep fading, so the pause reads as weight rather than
    // as the game hanging.
    _trackFrame(dt);
    sfx.tick(dt);
    sfx.volume = tuning.volume;
    sfx.mutedGroups = tuning.regrowthSound
        ? const <SoundGroup>{}
        : const {SoundGroup.field};
    juice.scale = tuning.reducedMotion ? 0 : tuning.juiceScale;
    final step = juice.consume(dt);

    elapsed += dt;
    tapRingFlash = math.max(0, tapRingFlash - dt * 3.2);
    barkFlash = math.max(0, barkFlash - dt * 1.6);
    wagBoost = math.max(0, wagBoost - dt * 0.9);
    startleFlash = math.max(0, startleFlash - dt * 4.0);
    if (bannerFor > 0) {
      bannerFor -= dt;
      if (bannerFor <= 0) {
        banner = null;
      }
    }
    _decayCellVisuals(dt);

    if (step <= 0) {
      return;
    }
    dt = step;

    switch (phase) {
      case GamePhase.idle:
      case GamePhase.playing:
        _updateRun(dt);
      case GamePhase.won:
        _updateWin(dt);
      case GamePhase.crushed:
        _updateCrush(dt);
      case GamePhase.starved:
        despair = math.min(1, despair + dt * 2.4);
      case GamePhase.softLocked:
        despair = math.min(1, despair + dt * 3);
    }
  }

  void _updateRun(double dt) {
    final playing = phase == GamePhase.playing;
    if (playing) {
      levelTime += dt;
    }

    // Freeze holds the field still without stopping the clock, so it buys
    // safety at the price of the one resource it cannot refill.
    final regrowthActive =
        playing &&
        tuning.regrowthEnabled &&
        !tuning.zenMode &&
        !powerups.regrowthPaused;

    if (playing) {
      powerups.update(dt);
      if (tuning.hungerEnabled && hunger.drain(dt)) {
        // One pulse as the bar enters the red, not one per frame (§11).
        Haptics.medium();
        sfx.play(Sound.whimper, gain: 0.8);
      }
      if (tuning.hungerEnabled && _heartbeat.update(dt, hunger.fraction)) {
        sfx.play(Sound.heartbeat, gain: Heartbeat.gainAt(hunger.fraction));
      }
    }

    _caughtCooldown = math.max(0, _caughtCooldown - dt);
    _springCooldown = math.max(0, _springCooldown - dt);

    // Patrols step before she does, so the ground she is refusing to enter is
    // where the light is *now* rather than where it was last frame. The other
    // order leaves her walking into a cell the light has already reached.
    if (guards.isNotEmpty) {
      if (playing) {
        for (final guard in guards) {
          guard.update(dt);
        }
      }
      guardedCells = {
        for (final guard in guards)
          for (final c in guard.lit)
            if (grid.contains(c)) c,
      };
    }

    // Captured before she moves, not after: taken afterwards it can only ever
    // equal her current cell, and the hint would never see her make progress.
    final wasIn = dog.cell;

    // The dog moves first, so regrowth sees the cell she is in *now*. Running
    // it the other way round leaves a one-frame window in which she can step
    // into a cell that is already past its snap threshold and get sealed inside
    // a wall.
    dog.update(
      dt: dt,
      grid: grid,
      layout: layout,
      tuning: tuning,
      fieldVersion: fieldVersion,
      regrowthActive: playing && tuning.regrowthEnabled && !tuning.zenMode,
      speedMultiplier: powerups.speedMultiplier,
      blocked: guardedCells,
    );

    _updateScent();
    _collectPickups();
    _checkSpring();
    if (playing) {
      _checkCaught();
    }
    _noticeBone();

    if (playing) {
      _nextIdleBark -= dt;
      if (_nextIdleBark <= 0) {
        // Occasionally, for no reason at all. A character who only ever reacts
        // is a state machine; one who sometimes just says something is a dog.
        _nextIdleBark = 9 + _idleRng.nextDouble() * 14;
        if (!isOver && dog.speed > 1) {
          barkFlash = 0.7;
          sfx.play(Sound.bark, gain: 0.5);
        }
      }
    }

    sinceProgress += dt;
    if (dog.cell != wasIn) {
      sinceProgress = 0;
    }

    final script = tutorial;
    if (script != null && !script.isDone) {
      if (playing) {
        script.update(dt, grid, dog, pickups);
      }
      tutorialTarget = script.targetCell(grid, dog, pickups);
    } else {
      tutorialTarget = null;
    }

    // Regrowth only runs once the player has actually started, so the field
    // never closes in on someone still reading it.
    if (regrowthActive) {
      final events = _regrowth.update(
        dt: dt,
        now: elapsed,
        grid: grid,
        tuning: tuning,
        dogCell: dog.cell,
      );
      if (events.warned.isNotEmpty) {
        firstRegrowthAt ??= elapsed;
        // Throttled, and quiet. Regrowth warnings fire in waves — a whole ring
        // of cells can enter their pulse on one frame, and several rings can be
        // in flight at once. Unthrottled they flood the platform channel, which
        // both drowns the player's own taps and queues them behind a backlog of
        // effects. The felt warning (§11) is worth one pulse, not twenty.
        if (sfx.play(Sound.warn, gain: 0.35, minInterval: 0.4)) {
          Haptics.selection();
        }
      }
      if (events.fieldChanged) {
        fieldVersion++;
        for (final coord in events.snapped) {
          effects.ripple(layout.toPixel(coord), layout.size);
        }
        juice.shake(2.4);
        // A tile slamming shut within reach of her is worth a flinch. Reacting
        // only to things that happen *to her* is what stops the animation
        // becoming decoration.
        for (final coord in events.snapped) {
          if (coord.distanceTo(dog.cell) <= 2) {
            startleFlash = 1;
            break;
          }
        }
        if (sfx.play(Sound.snap, gain: 0.5, minInterval: 0.28)) {
          Haptics.medium();
        }
      }
    } else if (tuning.zenMode) {
      _regrowth.settleForZen(grid);
    }

    editable = InputSystem.editableCells(
      grid: grid,
      layout: layout,
      dogPosition: dog.position,
      tapRadius: effectiveTapRadius,
    ).toSet();

    if (tuning.fogEnabled) {
      _revealAround();
    }

    if (dog.cell == grid.exit &&
        (dog.position - layout.toPixel(grid.exit)).distance <
            layout.inradius * 0.75) {
      _win();
      return;
    }

    if (dog.enclosedFor > 0 && phase == GamePhase.playing) {
      // Audible as well as visible, and quickening as the grace period runs
      // out, so there is no mistaking a countdown for a stall.
      final closeness = (dog.enclosedFor / tuning.suffocateSeconds).clamp(
        0.0,
        1.0,
      );
      sfx.play(
        Sound.warn,
        gain: 0.5 + closeness * 0.5,
        minInterval: 0.45 - closeness * 0.28,
      );
    }

    if (dog.enclosedFor >= tuning.suffocateSeconds) {
      _crush();
      return;
    }

    if (playing && tuning.hungerEnabled && hunger.isStarved) {
      _starve();
      return;
    }

    // Running out of taps does not end the run: if what she has already been
    // given still reaches the bone, she gets there. The run ends only when the
    // food becomes provably unaffordable, which is what this now measures.
    if (playing &&
        _softlock.check(
          grid: grid,
          dogCell: dog.cell,
          fieldVersion: fieldVersion,
          tapsLeft: tapsLeft,
          pickups: pickups,
          treatTaps: tuning.treatTaps.round(),
          blastCharges: powerups.chargesOf(PickupKind.blast),
          digCharges: powerups.chargesOf(PickupKind.dig),
        )) {
      lockedByBudget = Pathfinder.reachable(
        dog.cell,
        grid.exit,
        grid.isTraversableInPrinciple,
      );
      phase = GamePhase.softLocked;
      sfx.play(Sound.starve, gain: 0.8);
      Haptics.heavy();
      overlays.add(Overlays.result);
    }
  }

  /// Whether the nudge is showing, and how strongly.
  ///
  /// Never during the tutorial: a script is already saying something specific
  /// about right now, and two sources of guidance disagreeing is worse than
  /// neither.
  bool get hintVisible =>
      tuning.hintsEnabled &&
      tuning.fogEnabled &&
      phase == GamePhase.playing &&
      !isOver &&
      (tutorial?.isDone ?? true) &&
      sinceProgress >= hintAfter;

  double get hintStrength =>
      ((sinceProgress - hintAfter) / 1.2).clamp(0.0, 1.0);

  /// Which way the food is, routed around walls (§8).
  ///
  /// The neighbour that is fewest steps from the food, taken straight off the
  /// field the dog already steers by. A straight line to the exit would be
  /// cheaper still and would be wrong: it points *into* whichever anchor stands
  /// between here and there, which is the one moment a hint has to be right.
  ///
  /// Only a direction, never the route. The fog is the game; a hint that drew
  /// the way through would be a button that plays the level.
  HexCoord? get hintTarget {
    final here = dog.cell;
    HexCoord? best;
    var bestDistance = grid.distanceToExit(here);
    for (final n in here.neighbours) {
      if (!grid.isTraversableInPrinciple(n)) {
        continue;
      }
      final d = grid.distanceToExit(n);
      if (d < bestDistance) {
        bestDistance = d;
        best = n;
      }
    }
    return best;
  }

  double get revealRadius => math.max(
    RevealSystem.radiusFor(baseTapRadius, tuning.revealFactor),
    effectiveTapRadius * 1.2,
  );

  void _revealAround() => RevealSystem.reveal(
    grid: grid,
    layout: layout,
    dogPosition: dog.position,
    dogCell: dog.cell,
    radius: revealRadius,
  );

  void _win() {
    phase = GamePhase.won;
    dog.velocity = Offset.zero;
    // Zen switches off regrowth, which is most of the pressure in the game. A
    // Zen win recorded as a normal one would quietly devalue every star earned
    // the hard way, so it is practice: nothing is written, nothing unlocks. The
    // level detail sheet says so before the run starts.
    if (!tuning.zenMode) {
      // Checked before everything else, and it must stay that way. A daily
      // borrows an authored level's number to borrow its difficulty; falling
      // through to the campaign write would hand out that level's star and
      // advance the unlock chain for a board the player reached from the map's
      // daily tile.
      final today = daily;
      if (today != null) {
        progress?.recordDailyClear(today);
      } else if (isEndless) {
        progress?.recordEndlessClear(level: levelNumber);
      } else {
        progress?.recordWin(
          level: levelNumber,
          stars: stars,
          taps: taps,
          time: levelTime,
        );
      }
    }
    // The one moment in the game that has earned a freeze.
    juice.freeze(0.07);
    juice.shake(5);
    sfx.play(Sound.chomp);
    Haptics.medium();
    effects.shatter(
      layout.toPixel(grid.exit),
      layout.size,
      colour: Palette.goalGlow,
      boost: 1.4,
    );
  }

  /// Remaining hexes shatter in a wave rolling outward from the food (§10),
  /// then the results panel slides in.
  void _updateWin(double dt) {
    final previous = _winWave;
    _winWave += dt * 11;

    for (final cell in grid.all) {
      if (cell.isSolid) {
        final d = cell.coord.distanceTo(grid.exit).toDouble();
        if (d >= previous && d < _winWave) {
          cell.state = CellState.open;
          cell.clearBurst = 1;
          effects.shatter(layout.toPixel(cell.coord), layout.size, boost: 0.8);
        }
      }
    }

    if (_winWave > 9 && !overlays.isActive(Overlays.result)) {
      overlays.add(Overlays.result);
    }
  }

  /// Too slow, as distinct from too wasteful or standing still. Each ending
  /// gets its own wording so a loss is never ambiguous about what caused it.
  void _starve() {
    phase = GamePhase.starved;
    dog.velocity = Offset.zero;
    sfx.play(Sound.starve);
    Haptics.heavy();
    overlays.add(Overlays.result);
  }

  /// She spots dinner. The moment the bone first enters the pocket she can
  /// actually walk through is the most exciting beat in a run, and until now it
  /// passed completely unmarked.
  /// How close she has to get before she smells dinner.
  static const _boneScent = 3;

  void _noticeBone() {
    // Distance, not visibility. The first version waited for the exit cell to
    // be *cleared*, which only happens in the last instant before she walks in
    // — so the bark fired a heartbeat before the win and nobody ever saw it.
    if (_spottedBone || phase != GamePhase.playing) {
      return;
    }
    if (grid.distanceToExit(dog.cell) > _boneScent) {
      return;
    }
    _spottedBone = true;
    barkFlash = 1;
    sfx.play(Sound.bark);
    Haptics.light();
  }

  void _collectPickups() {
    final taken = PickupSystem.collect(pickups, dog.cell);
    if (taken == null) {
      return;
    }
    switch (taken.kind) {
      case PickupKind.treat:
        wagBoost = 1;
        sfx.play(Sound.treat);
        hunger.feed(tuning.treatSeconds);
        // Taps as well as seconds: the fog guarantees some are spent finding
        // walls, so exploring has to be able to pay for itself.
        tapBudget += tuning.treatTaps.round();
      case PickupKind.freeze:
      case PickupKind.radiusPlus:
      case PickupKind.sprint:
      case PickupKind.scent:
      case PickupKind.blast:
      case PickupKind.dig:
        sfx.play(Sound.powerup);
        powerups.grant(taken.kind);
        // Charges wait for a tap, so they need to say so. Timed effects show
        // themselves as the ring closing round her and need no words.
        if (taken.kind.isCharge) {
          announce(taken.kind.readyHint);
        }
    }
    effects.shatter(
      layout.toPixel(taken.coord),
      layout.size,
      colour: Palette.goalGlow,
      boost: 1.2,
    );
    Haptics.light();
  }

  /// The one powerup that buys knowledge rather than resources.
  void _updateScent() {
    if (!powerups.scentActive) {
      if (scentPath.isNotEmpty) {
        scentPath = const [];
        _scentFieldVersion = -1;
      }
      return;
    }
    // Her cell counts as part of the field for this: she moves along the route
    // while it is lit, and a path drawn from where she was is worse than none.
    final signature = fieldVersion * 31 + dog.cell.hashCode;
    if (signature == _scentFieldVersion) {
      return;
    }
    _scentFieldVersion = signature;
    scentPath =
        Pathfinder.cheapestPath(
          dog.cell,
          grid.exit,
          grid.isTraversableInPrinciple,
          (c) => grid.cells[c]?.remainingHits ?? (1 << 20),
        ) ??
        const [];
  }

  /// Springs (§6.1). Fires on *entering* an open spring, never while standing
  /// on one, so she is thrown once rather than pinned to it.
  void _checkSpring() {
    if (_springCooldown > 0 || dog.isLaunched) {
      return;
    }
    if (grid.at(dog.cell)?.type != HexType.spring) {
      return;
    }
    // The direction she was already going. A spring adds distance to a
    // decision the player already made; it does not make the decision.
    var direction = dog.velocity;
    if (direction.distance < 1e-3) {
      direction = Offset(math.cos(dog.facing), math.sin(dog.facing));
    }
    _springCooldown = 0.6;
    dog.launch(direction, layout.width * _springHexesPerSecond);
    juice.shake(3.2);
    effects.shatter(layout.toPixel(dog.cell), layout.size, boost: 1.1);
    sfx.play(Sound.powerup, gain: 0.7);
    Haptics.medium();
  }

  /// How fast a spring throws her, in hex widths per second. Paired with the
  /// launch duration in [Dog.launch] this is roughly three cells of travel
  /// before steering takes over — far enough to feel like a throw, short enough
  /// that she is not gone.
  static const _springHexesPerSecond = 8.5;

  /// Seconds a patrol costs her. Charged to the clock rather than the tap
  /// budget: a patrol takes *time*, which is the resource waiting for one also
  /// spends, so the punishment and the alternative are priced in the same
  /// currency.
  static const guardBiteSeconds = 3.0;

  void _checkCaught() {
    if (_caughtCooldown > 0 || !guardedCells.contains(dog.cell)) {
      return;
    }
    _caughtCooldown = 1.6;
    if (tuning.hungerEnabled) {
      hunger.bite(guardBiteSeconds);
    }
    startleFlash = 1;
    barkFlash = 1;
    juice.shake(4.2);
    sfx.play(Sound.bark, gain: 0.85);
    Haptics.heavy();

    // Shoved out of the light rather than merely billed for standing in it, so
    // being caught is something she visibly survives.
    final nearest = _nearestGuardPosition();
    if (nearest != null) {
      dog.launch(dog.position - nearest, layout.width * 5.5, duration: 0.22);
    }
  }

  Offset? _nearestGuardPosition() {
    Offset? best;
    var bestDistance = double.infinity;
    for (final guard in guards) {
      final p = guard.positionIn(layout);
      final d = (p - dog.position).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = p;
        guard.alertFlash = 1;
      }
    }
    return best;
  }

  /// Spends a held charge, if one applies to what was just tapped. Returns
  /// whether it did, in which case the tap is finished.
  bool _spendCharge(TapOutcome outcome, HexCoord coord) {
    if (outcome == TapOutcome.anchor &&
        powerups.spendSelected(PickupKind.dig)) {
      _dig(coord);
      return true;
    }
    if ((outcome == TapOutcome.hit || outcome == TapOutcome.nothingToClear) &&
        powerups.spendSelected(PickupKind.blast)) {
      _blast(coord);
      return true;
    }
    return false;
  }

  /// Arms or puts away a held tool from the HUD. This is deliberately separate
  /// from collection: picking something up must never change what the player's
  /// next board tap does.
  void toggleCharge(PickupKind kind) {
    if (isOver) {
      return;
    }
    final armed = powerups.toggleCharge(kind);
    if (armed) {
      announce(kind.hint);
    } else if (powerups.has(kind)) {
      announce('${kind.label} put away');
    }
    Haptics.light();
  }

  /// One tap, a cluster of hexes.
  ///
  /// Heavy hexes go in whole rather than merely cracking: a blast that left a
  /// ring of half-broken heavies behind it would cost the player *more* taps
  /// than it saved on a dense board, which is the opposite of what the pickup
  /// promises.
  void _blast(HexCoord centre) {
    if (phase == GamePhase.idle) {
      phase = GamePhase.playing;
    }
    taps++;
    var opened = 0;
    for (final coord in centre.disc(ActiveEffects.blastRadius)) {
      final cell = grid.at(coord);
      if (cell == null || !cell.isClearable) {
        continue;
      }
      cell
        ..revealed = true
        ..clear(elapsed);
      effects.shatter(layout.toPixel(coord), layout.size, boost: 1.3);
      opened++;
    }
    if (opened > 0) {
      fieldVersion++;
    }
    juice
      ..freeze(0.05)
      ..shake(5.5);
    sfx.play(Sound.crush, gain: 0.8);
    Haptics.heavy();
    tapRingFlash = 1;
    // A blast is not a carve, so it does not extend a chain. Letting it would
    // make the chain a measure of how many powerups were held rather than of
    // how well the board was read.
    streak.register(
      grid: grid,
      tapped: centre,
      dogCell: dog.cell,
      carved: false,
    );
  }

  /// The only thing in the game that removes an anchor.
  void _dig(HexCoord coord) {
    if (phase == GamePhase.idle) {
      phase = GamePhase.playing;
    }
    taps++;
    grid.at(coord)!
      ..type = HexType.plain
      ..revealed = true
      ..clear(elapsed);
    // Walls define every distance on the board, so removing one invalidates the
    // field she steers by. Without this she keeps routing around a hole.
    grid.invalidateTopology();
    fieldVersion++;
    effects.shatter(layout.toPixel(coord), layout.size, boost: 1.6);
    juice
      ..freeze(0.06)
      ..shake(6);
    sfx.play(Sound.crush);
    Haptics.heavy();
    tapRingFlash = 1;
    streak.register(
      grid: grid,
      tapped: coord,
      dogCell: dog.cell,
      carved: false,
    );
  }

  void _crush() {
    phase = GamePhase.crushed;
    dog.velocity = Offset.zero;
    juice.freeze(0.06);
    juice.shake(4.5);
    sfx.play(Sound.crush);
    Haptics.heavy();
  }

  /// The field closes in around the dog with the regrowth animation running
  /// fast. Never an instant modal (§10).
  void _updateCrush(double dt) {
    despair = math.min(1, despair + dt * 3.4);
    final previous = _crushWave;
    _crushWave += dt * 7;

    for (final cell in grid.all) {
      if (!cell.isSolid) {
        final d = cell.coord.distanceTo(dog.cell).toDouble();
        if (d >= previous && d < _crushWave && cell.coord != dog.cell) {
          cell.resetToSolid();
          cell.snapRipple = 1;
          effects.ripple(layout.toPixel(cell.coord), layout.size);
        }
      }
    }

    if (_crushWave > 4 && !overlays.isActive(Overlays.result)) {
      overlays.add(Overlays.result);
    }
  }

  void _decayCellVisuals(double dt) {
    for (final cell in grid.all) {
      if (cell.clearBurst > 0) {
        cell.clearBurst = math.max(0, cell.clearBurst - dt * 4.5);
      }
      if (cell.snapRipple > 0) {
        cell.snapRipple = math.max(0, cell.snapRipple - dt * 2.6);
      }
      if (cell.rejectShake > 0) {
        cell.rejectShake = math.max(0, cell.rejectShake - dt * 3.4);
      }
      if (cell.crackFlash > 0) {
        cell.crackFlash = math.max(0, cell.crackFlash - dt * 2.2);
      }
    }
    for (final pickup in pickups) {
      if (pickup.collectFlash > 0) {
        pickup.collectFlash = math.max(0, pickup.collectFlash - dt * 2.0);
      }
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!_ready || isOver) {
      return;
    }

    final point = Offset(event.canvasPosition.x, event.canvasPosition.y);
    final result = InputSystem.resolve(
      point: point,
      grid: grid,
      layout: layout,
      dogPosition: dog.position,
      tapRadius: effectiveTapRadius,
    );

    // A gated tutorial step refuses everything but the tile it is pointing at,
    // so the lesson cannot be skimmed past. It costs nothing — a refused tap is
    // not a wasted one.
    final script = tutorial;
    final targetBeforeTap = script?.targetCell(grid, dog, pickups);
    if (script != null &&
        result.coord != null &&
        !script.allowsTap(result.coord!, grid, dog, pickups)) {
      tapRingFlash = 1;
      return;
    }

    // Charges are spent by tapping, so they are decided before the tap is
    // classified — a blast does not care whether the hex under the finger was
    // going to open, and a dig only fires on the one outcome a normal tap can
    // do nothing with.
    if (result.coord != null &&
        tapsLeft > 0 &&
        _spendCharge(result.outcome, result.coord!)) {
      return;
    }

    switch (result.outcome) {
      case TapOutcome.hit:
        if (tapsLeft == 0) {
          // Out of taps. She keeps walking on whatever is already open.
          tapRingFlash = 1;
          streak.register(
            grid: grid,
            tapped: result.coord!,
            dogCell: dog.cell,
            carved: false,
          );
          return;
        }
        if (phase == GamePhase.idle) {
          phase = GamePhase.playing;
        }
        taps++;
        final cell = grid.at(result.coord!)!;
        final centre = layout.toPixel(result.coord!);
        final opened = cell.hit(elapsed);

        // One decision drives the note, the burst and the haptic together, so
        // the whole response escalates as one thing rather than three tuned
        // separately.
        final outcome = streak.register(
          grid: grid,
          tapped: result.coord!,
          dogCell: dog.cell,
          carved: true,
        );
        final intensity = streak.intensity;

        if (opened) {
          fieldVersion++;
          sinceProgress = 0;
          effects.shatter(centre, layout.size, boost: 1 + intensity * 0.9);
          juice.shake(0.9 + intensity * 1.3);
          if (outcome == StreakOutcome.advanced) {
            sfx.playTap(streak.streak - 1, gain: 0.75 + intensity * 0.25);
          } else {
            // Chain broken: back to the root of the scale, quietly. The drop is
            // the feedback — a duller note says "that went sideways" without a
            // word of UI.
            sfx.playTap(0, gain: 0.6);
          }
          if (intensity > 0.5) {
            Haptics.medium();
          } else {
            Haptics.light();
          }
        } else {
          // A heavy hex that cracked but held. It cost a tap all the same, so
          // it needs to feel like it did something.
          effects.shatter(centre, layout.size, boost: 0.45);
          juice.shake(1.2);
          sfx.play(Sound.crack);
          Haptics.medium();
        }
        tapRingFlash = 1;
        script?.onTapped(
          result.coord!,
          grid,
          dog,
          pickups,
          targetBeforeTap: targetBeforeTap,
        );

      case TapOutcome.anchor:
        // Reported honestly rather than redirected to a nearby plain hex, and
        // it costs no tap — probing a wall is paid for in time, not budget.
        grid.at(result.coord!)!
          ..rejectShake = 1
          ..revealed = true;
        streak.register(
          grid: grid,
          tapped: result.coord!,
          dogCell: dog.cell,
          carved: false,
        );
        juice.shake(1.8);
        sfx.play(Sound.thunk);
        Haptics.heavy();

      case TapOutcome.outOfRange:
      case TapOutcome.nothingToClear:
        // Flash the ring so the constraint teaches itself (§2.1, §12.5).
        tapRingFlash = 1;
        streak.register(
          grid: grid,
          tapped: dog.cell,
          dogCell: dog.cell,
          carved: false,
        );
    }
  }
}
