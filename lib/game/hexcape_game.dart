import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
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
import 'board_camera.dart';
import 'daily.dart';
import 'difficulty.dart';
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

enum HudNoticeKind { proximity, pickup }

/// A typed, non-blocking message for the HUD's existing bottom safe area.
class HudNotice {
  const HudNotice.proximity({this.hex, this.pickup})
    : assert((hex == null) != (pickup == null)),
      kind = HudNoticeKind.proximity;

  const HudNotice.pickup(this.pickup)
    : assert(pickup != null),
      kind = HudNoticeKind.pickup,
      hex = null;

  final HudNoticeKind kind;
  final HexType? hex;
  final PickupKind? pickup;
}

class _NearbyNotice {
  const _NearbyNotice(
    this.notice,
    this.coord,
    this.key,
    this.priority,
    this.step,
  );

  final HudNotice notice;
  final HexCoord coord;
  final Object key;
  final int priority;

  /// How many cells along her route this sits. Kept rather than recomputed
  /// because a hint is about *when* she arrives, and the route is the only
  /// thing that knows that -- straight-line distance calls a thorn behind a
  /// wall close.
  final int step;
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

  /// How the board is framed. At [BoardCamera.minZoom] this changes nothing at
  /// all — see [_recomputeLayout].
  final BoardCamera boardCamera = BoardCamera();

  /// The silhouette's extent in unit space, cached per level.
  ///
  /// [_recomputeLayout] now runs every frame the camera moves rather than only
  /// on resize, and measuring three hundred cells to rediscover a number that
  /// changes once per level is the kind of thing that shows up in [frameMs].
  late UnitBounds _bounds;

  /// The hex size the whole board fits at. [BoardCamera.zoom] multiplies it.
  double fitHexSize = 1;

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

  /// Ground a patrol is lighting: she refuses to walk into it, and it bites.
  Set<HexCoord> guardedCells = const {};

  /// Ground a sentry is lighting: taps there do nothing.
  ///
  /// Deliberately a separate set from [guardedCells], not a flag on it. The two
  /// are read by different systems — the dog and the catch check take the
  /// first, tap resolution takes the second — and merging them would give a
  /// sentry a patrol's teeth and a patrol a sentry's reach.
  Set<HexCoord> wardedCells = const {};

  /// 1 -> 0 after a tap was refused by the light.
  double wardFlash = 0;

  /// The ring where a living overgrowth heart doubles the closing pace,
  /// computed once at level build from the board's hearts.
  Set<HexCoord> overgrowthAura = const {};

  /// Whether any heart still stands — the aura means nothing once they are dug.
  bool get heartsStand => _heartsStanding;
  bool _heartsStanding = false;
  List<HexCoord> _heartCells = const [];

  /// Lamps planted by the BEACON charge, as cells. They hold a bubble of
  /// revealed ground for the rest of the run.
  List<HexCoord> beaconsLit = const [];

  /// The tremor vents' shared countdown to the next surge, and the flash it
  /// leaves. Vents are all wired to the same rhythm so the board warns in one
  /// voice rather than as a scatter of asynchronous alarms.
  double tremorAt = double.infinity;
  double tremorFlash = 0;
  List<HexCoord> _tremorCells = const [];

  /// Seconds of alarm-speed sweeping left, after she steps on a bell.
  double alarmFor = 0;

  /// The tiles the field most recently closed, oldest last, capped — what
  /// REWIND reads. Regrowth, cracklines, braids and warden wakes all count;
  /// anything that closed counts once, whoever closed it.
  final List<HexCoord> recentlyClosed = [];

  /// Stops one thorn pad from billing her every frame she stands on it.
  double _thornCooldown = 0;

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

  /// When the nudge actually arrives for the current pet. Scout reads sooner;
  /// nothing makes it later — the perk axis moves one way by design, because
  /// a pet that punishes its player is not a pet.
  double get effectiveHintAfter =>
      math.max(2.0, hintAfter - pet.perk.hintBeforeBy);

  /// The coat she is wearing (§9.2). Purely cosmetic — see [Pet].
  Pet pet = Pets.scout;

  /// The drawn dog, per coat. Populated at [onLoad]; empty under tests, which
  /// is how the component knows to walk its procedural path instead. Keyed by
  /// pet id rather than by [Pet] so a coat change mid-menu needs no ceremony.
  final Map<String, ui.Image> petSprites = {};

  /// Four walk poses followed by four run poses, in fixed 320 px cells.
  /// Static coat art remains available for menus and as the loading fallback.
  final Map<String, ui.Image> petMoveSprites = {};

  /// Pet art lives beside the other app assets, not under Flame's default
  /// `assets/images/` directory. Keep a dedicated cache so loading the dog art
  /// cannot change the prefix used by any other Flame image.
  final Images _petImages = Images(prefix: 'assets/pets/');

  /// What the player is holding a finger on, for the inspector card.
  ///
  /// The game reports *what* was held, not what to say about it: the copy lives
  /// with the reference sheet, which is the one place a mechanic is described,
  /// and a second description here is how a legend starts lying about the
  /// board.
  ///
  /// [hex] is null for ground she has not been near yet. State is never hidden
  /// — a hole is obviously a hole — but type is, and an inspector that answered
  /// through the fog would hand the player the obstacle map the fog exists to
  /// withhold (see [HexCell.revealed]).
  ({HexCoord coord, PickupKind? pickup, HexType? hex})? inspecting;

  /// Seconds the inspector card has left. It fades on its own rather than
  /// needing to be dismissed: her clock is running, and a card that has to be
  /// closed is a card that costs the player time to have opened.
  double inspectFor = 0;

  /// How long the card stays up.
  static const inspectSeconds = 3.2;

  HudNotice? proximityNotice;
  double proximityNoticeFor = 0;
  HudNotice? pickupNotice;

  /// Seconds the pickup card has left before it fades out. Refreshed every
  /// frame the power-up behind it is still live, so the card lasts as long as
  /// the thing it describes rather than for a fixed flash.
  double pickupNoticeFor = 0;

  /// The part of that which outranks a proximity warning. A receipt is owed
  /// long enough to be read; past that, ground she is about to walk into
  /// matters more than a power-up she already has.
  double pickupNoticeReadFor = 0;
  final Set<Object> _encounteredNearby = {};
  _NearbyNotice? _pendingNearby;

  static const proximityNoticeSeconds = 2.5;

  /// How long a pickup card is guaranteed, whatever else wants the slot. One
  /// second was not long enough to find the card, let alone read it.
  static const pickupNoticeSeconds = 2.0;

  /// The tail a card fades over once the power-up behind it ends, so it goes
  /// out rather than vanishing on the frame the effect expires.
  static const pickupNoticeFadeSeconds = 0.25;

  /// A charge is an instruction, not a receipt -- it has to survive being read.
  /// It earns the longer slot because nothing else says what the tap is for.
  static const chargeNoticeSeconds = 2.5;

  /// The stretch of route a warning may look down, her own cell being step 0.
  ///
  /// Step 1 is excluded on purpose: by the time she is one hex out she is
  /// already committed, and naming the thorn she is about to stand in is a
  /// caption, not a hint.
  static const hintLookaheadFrom = 2;
  static const hintLookaheadTo = 5;

  /// The reaction window, in seconds of travel. Sooner than [hintLeadMin] and
  /// there is no time left to tap; later than [hintLeadMax] and it is noise
  /// about ground she may never cross, since one tap can redraw the route.
  ///
  /// The upper bound has to clear a full crawl across [hintLookaheadFrom]
  /// cells -- at [TuningConfig.driftMin] that is over two and a half seconds --
  /// or a tight corridor, where she is slowest and the warning is easiest to
  /// act on, would be the one place nothing is ever said.
  static const hintLeadMin = 0.5;
  static const hintLeadMax = 3.0;

  /// Below this, in hexes per second, she counts as standing still.
  static const _hintStillSpeed = 0.05;

  /// The floor between any two contextual hints. Two warnings back to back read
  /// as chatter, and the second one is not heard.
  static const hintGapSeconds = 4.0;

  /// Starts satisfied, so the first mechanic of a level teaches immediately.
  double _sinceHintShown = hintGapSeconds;

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
  double foodSecondsRefunded = 0;
  int foodTapsRefunded = 0;
  String? foodReceipt;
  double foodReceiptFor = 0;
  int seed = 0;

  /// Which level of the campaign is being played. Past [Campaign.length] this
  /// is an endless run.
  int levelNumber = 1;

  late LevelRules rules;

  /// The scripted opening, on tutorial levels only.
  Tutorial? tutorial;

  bool get tutorialReading =>
      tutorial?.current?.advance == TutorialAdvance.onContinue;

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

  /// The screen area the board is framed in — everything the HUD has not
  /// claimed.
  ///
  /// One definition, because three things need to agree about it: the fit
  /// calculation, the camera's clamp, and the clip that keeps a magnified board
  /// out from under the HUD.
  Rect get boardViewport => Rect.fromLTRB(
    _hudInsets.left,
    _hudInsets.top,
    math.max(_hudInsets.left + 1, size.x - _hudInsets.right),
    math.max(_hudInsets.top + 1, size.y - _hudInsets.bottom),
  );

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
    // The dog's coats. Missing art is survivable: the component falls back to
    // drawing her procedurally, which is how tests keep running her without
    // an asset bundle.
    for (final pet in Pets.all) {
      try {
        petSprites[pet.id] = await _petImages.load('${pet.id}.png');
        petMoveSprites[pet.id] = await _petImages.load('${pet.id}_move.png');
      } catch (_) {
        // Leave the coat undelivered; she draws her fallback.
      }
    }
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

  /// The setting this run is actually being played on.
  ///
  /// Fixed when the board is built, not read live from [tuning]. The tuning
  /// object is the *next* run's setting — `_applySettings` rewrites it from
  /// preferences every time the player touches the settings sheet — so reading
  /// it here would let someone change the volume mid-level and have the run
  /// they are playing get recorded under a difficulty they were not playing.
  ///
  /// Always [Difficulty.normal] for the daily, whatever the player has chosen
  /// elsewhere. One board for everyone is what makes a streak worth comparing,
  /// and that has to cover the fog and the hints as much as the rules.
  Difficulty difficultyForRun = Difficulty.normal;

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
    // The daily is difficulty-less by construction: its rules are precomputed
    // for the day, and one board for everyone is the whole promise.
    difficultyForRun = isDaily ? Difficulty.normal : tuning.difficulty;
    rules =
        daily?.rules ??
        Campaign.rulesFor(levelNumber, difficulty: difficultyForRun);
    if (tuning.followCampaign) {
      _applyRules(rules);
      // Fog is the one difficulty lever with no authored per-level value, so it
      // is scaled here rather than through the rules. Both modes leave the
      // tutorial's fog exactly as scripted — the lesson reads first.
      tuning.revealFactor =
          tuning.revealBase * difficultyForRun.revealMultiplierFor(levelNumber);
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
        slopeDensity: tuning.slopeDensity,
        sunkenDensity: tuning.sunkenDensity,
        hardpanDensity: tuning.hardpanDensity,
        thatchDensity: tuning.thatchDensity,
        overgrowthDensity: tuning.overgrowthDensity,
        tremorDensity: tuning.tremorDensity,
        iceDensity: tuning.iceDensity,
        mireDensity: tuning.mireDensity,
        eddyDensity: tuning.eddyDensity,
        magnetDensity: tuning.magnetDensity,
        thicketDensity: tuning.thicketDensity,
        sleeperDensity: tuning.sleeperDensity,
        foxfireDensity: tuning.foxfireDensity,
        scaffoldDensity: tuning.scaffoldDensity,
        thornDensity: tuning.thornDensity,
        alarmDensity: tuning.alarmDensity,
        gatePairs: tuning.gatePairCount,
        mirrorPairs: tuning.mirrorPairCount,
        gloom: tuning.gloomEnabled,
        guards: tuning.guardCount,
        sentries: tuning.sentryCount,
        beacons: tuning.beaconCount,
        spinners: tuning.spinnerCount,
        runners: tuning.runnerCount,
        blinkers: tuning.blinkerCount,
        wardens: tuning.wardenCount,
        guardSpeed: tuning.guardSpeed,
        treats: tuning.treatCount.round() + pet.perk.extraTreats,
        powerups: tuning.powerupCount.round(),
        treatSeconds: tuning.treatSeconds,
        treatTaps: tuning.treatTaps.round(),
        offeredPowerups: rules.offeredPowerups,
        powerupRotation: rules.powerupRotation,
        shape: rules.shape,
      ),
    );
    grid = this.level.grid;
    _bounds = unitBounds(grid.cells.keys);
    levelVersion++;
    fieldVersion++;

    // The zoom carries across levels — it is a comfort setting, and a player
    // who needs the board bigger needs it bigger on the next one too — but the
    // focus does not, because it points at a board that no longer exists.
    boardCamera.focus = BoardCamera.centreOf(_bounds);
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
    wardedCells = const {};
    wardFlash = 0;
    _heartCells = [
      for (final cell in grid.all)
        if (cell.type == HexType.overgrowth) cell.coord,
    ];
    _heartsStanding = _heartCells.isNotEmpty;
    overgrowthAura = _heartsStanding
        ? {for (final h in _heartCells) ...h.disc(2)}
        : const {};
    beaconsLit = const [];
    _tremorCells = [
      for (final cell in grid.all)
        if (cell.type == HexType.tremor) cell.coord,
    ];
    tremorAt = _tremorCells.isEmpty
        ? double.infinity
        : tuning.tremorPeriod * 0.6; // first surge comes early enough to teach
    tremorFlash = 0;
    alarmFor = 0;
    recentlyClosed.clear();
    _thornCooldown = 0;
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
    foodSecondsRefunded = 0;
    foodTapsRefunded = 0;
    foodReceipt = null;
    foodReceiptFor = 0;
    proximityNotice = null;
    proximityNoticeFor = 0;
    pickupNotice = null;
    pickupNoticeFor = 0;
    pickupNoticeReadFor = 0;
    _encounteredNearby.clear();
    _pendingNearby = null;
    _sinceHintShown = hintGapSeconds;
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

  /// Step the board magnification, wrapping back to fit.
  ///
  /// The HUD control is the *only* way to change this, and that is a decision
  /// rather than an omission. Pinch-to-zoom cannot work here: carving happens
  /// on tap-*down*, and Flutter delivers a tap-down the instant a finger lands,
  /// before the gesture arena has decided whether a second finger is coming.
  /// The first finger of a pinch would clear a tile and spend a tap from a
  /// rationed budget every time. A tap that costs the player a resource they
  /// are short of is not a gesture worth having, and moving the carve to
  /// tap-up to make room for one would put latency on the only action in the
  /// game.
  void cycleZoom() {
    boardCamera.cycle();
    if (!boardCamera.isFit && _ready) {
      // Open framed on her rather than gliding in from wherever the last zoom
      // left the view. Her unit position is the same at every zoom, so this is
      // read off the layout that is about to be replaced.
      boardCamera.focus = Offset(
        (dog.position.dx - layout.origin.dx) / layout.size,
        (dog.position.dy - layout.origin.dy) / layout.size,
      );
    }
    if (_ready) _recomputeLayout();
    progress?.setZoom(boardCamera.zoom);
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
      ..slopeDensity = r.slopeDensity
      ..sunkenDensity = r.sunkenDensity
      ..hardpanDensity = r.hardpanDensity
      ..thatchDensity = r.thatchDensity
      ..overgrowthDensity = r.overgrowthDensity
      ..tremorDensity = r.tremorDensity
      ..iceDensity = r.iceDensity
      ..mireDensity = r.mireDensity
      ..eddyDensity = r.eddyDensity
      ..magnetDensity = r.magnetDensity
      ..thicketDensity = r.thicketDensity
      ..sleeperDensity = r.sleeperDensity
      ..foxfireDensity = r.foxfireDensity
      ..scaffoldDensity = r.scaffoldDensity
      ..thornDensity = r.thornDensity
      ..alarmDensity = r.alarmDensity
      ..gatePairCount = r.gatePairs
      ..mirrorPairCount = r.mirrorPairs
      ..gloomEnabled = r.gloom
      ..guardCount = r.guards
      ..sentryCount = r.sentries
      ..beaconCount = r.beacons
      ..spinnerCount = r.spinners
      ..runnerCount = r.runners
      ..blinkerCount = r.blinkers
      ..wardenCount = r.wardens
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
    final bounds = _bounds;

    // Cell positions are centres, so allow half a hex of bleed on every side.
    final unitWidth = (bounds.maxX - bounds.minX) + _sqrt3;
    final unitHeight = (bounds.maxY - bounds.minY) + 2.0;

    final viewport = boardViewport;
    final availableWidth = viewport.width;
    final availableHeight = viewport.height;
    // The zoom the whole board fits at. Everything the game did before there
    // was a camera is this number with a multiplier of one.
    fitHexSize = math.min(
      availableWidth / unitWidth,
      availableHeight / unitHeight,
    );
    final hexSize = fitHexSize * boardCamera.zoom;

    // At fit the board is pinned to its own centre rather than merely clamped
    // there. The clamp would land on the same point, but 'merely' is doing a
    // lot of work in a game that asserts every hex corner sits inside the HUD
    // insets: an exact equality is worth more than a value that rounds to it.
    if (boardCamera.isFit) {
      boardCamera.focus = BoardCamera.centreOf(bounds);
    } else {
      boardCamera.focus = boardCamera.clampedFocus(
        bounds: bounds,
        hexSize: hexSize,
        viewport: viewport.size,
      );
    }

    final screenCentre = viewport.center;

    layout = HexLayout(
      size: hexSize,
      origin:
          screenCentre -
          Offset(
            boardCamera.focus.dx * hexSize,
            boardCamera.focus.dy * hexSize,
          ),
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
    // Magnified, the board is larger than the area it is framed in, so without
    // this it would slide under the HUD and the level number would be read
    // against moving hexes. At fit the board already sits inside the insets and
    // the clip touches nothing, which is why it is only paid for when zoomed.
    final clip = boardCamera.isFit ? null : boardViewport;
    if (shake == Offset.zero && clip == null) {
      super.renderTree(canvas);
      return;
    }
    canvas.save();
    if (clip != null) {
      canvas.clipRect(clip);
    }
    if (shake != Offset.zero) {
      canvas.translate(shake.dx, shake.dy);
    }
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

    if (!isOver && tutorialReading) {
      tutorialTarget = tutorial?.targetCell(grid, dog, pickups);
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
    foodReceiptFor = math.max(0, foodReceiptFor - dt);
    if (foodReceiptFor == 0) foodReceipt = null;
    tapRingFlash = math.max(0, tapRingFlash - dt * 3.2);
    wardFlash = math.max(0, wardFlash - dt * 3.0);
    barkFlash = math.max(0, barkFlash - dt * 1.6);
    wagBoost = math.max(0, wagBoost - dt * 0.9);
    startleFlash = math.max(0, startleFlash - dt * 4.0);
    if (bannerFor > 0) {
      bannerFor -= dt;
      if (bannerFor <= 0) {
        banner = null;
      }
    }
    if (inspectFor > 0) {
      inspectFor -= dt;
      if (inspectFor <= 0) {
        inspecting = null;
      }
    }
    _updateHudNotices(dt);
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

    _updateCamera(dt);
  }

  /// Keep the dog framed while the board is magnified.
  ///
  /// Nothing here runs at fit, where the whole board is on screen and there is
  /// by definition nothing to follow.
  void _updateCamera(double dt) {
    if (boardCamera.isFit || dt <= 0) {
      return;
    }
    final viewport = boardViewport;
    final hexSize = layout.size;

    // Her position and heading in unit space, which is the space the camera
    // thinks in — pixels move under it every time the zoom changes.
    final dogUnit = Offset(
      (dog.position.dx - layout.origin.dx) / hexSize,
      (dog.position.dy - layout.origin.dy) / hexSize,
    );
    final heading = Offset(
      dog.velocity.dx / hexSize,
      dog.velocity.dy / hexSize,
    );

    boardCamera.follow(
      boardCamera.targetFor(dogUnit, heading),
      Offset(viewport.width / (2 * hexSize), viewport.height / (2 * hexSize)),
      dt,
      // Reduced motion means no easing anywhere else in the game; a gliding
      // viewport is the largest moving thing on screen, so it honours that too.
      instant: tuning.reducedMotion,
    );
    _recomputeLayout();
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
    _thornCooldown = math.max(0, _thornCooldown - dt);
    alarmFor = math.max(0, alarmFor - dt);

    // Patrols step before she does, so the ground she is refusing to enter is
    // where the light is *now* rather than where it was last frame. The other
    // order leaves her walking into a cell the light has already reached.
    //
    // One pace for every light on the board: SLOWBEAT halves it, an alarm
    // bell whips it. Both act on the *shared* rhythm because that is what the
    // player learns to read — a board whose lights each ran their own tempo
    // would have no beat to catch.
    final lightPace =
        (powerups.slowbeatActive ? ActiveEffects.slowbeatFactor : 1.0) *
        (alarmFor > 0 ? ActiveEffects.alarmFactor : 1.0);
    if (guards.isNotEmpty) {
      if (playing) {
        for (final guard in guards) {
          guard.update(dt * lightPace);
        }
      }
      // The two rule-sets stay separate sets, now split by what each kind
      // does rather than by an isSentry flag: red light for her body, pale
      // light for your hands, and never one borrowed throne for both.
      guardedCells = {
        for (final guard in guards)
          if (guard.blocksDog)
            for (final c in guard.lit)
              if (grid.contains(c)) c,
      };
      wardedCells = {
        for (final guard in guards)
          if (guard.wardsTaps)
            for (final c in guard.lit)
              if (grid.contains(c)) c,
      };
      // A warden closes whatever open ground it is standing over. The closing
      // still runs the warning animation — it starts partway in, which is the
      // light itself making the threat legible — so the fairness contract
      // (warned, never sudden) survives a moving mechanic.
      for (final guard in guards) {
        if (guard.kind == GuardKind.warden && phase == GamePhase.playing) {
          for (final c in guard.lit) {
            final cell = grid.at(c);
            if (cell == null ||
                cell.state != CellState.open ||
                cell.pinned ||
                c == dog.cell) {
              continue;
            }
            cell.state = CellState.regrowing;
            cell.regrowT = math.max(cell.regrowT, 0.30);
          }
        }
      }
    }

    // Tremor vents: one shared rhythm while any vent stands. The surge pulls
    // pending closures forward — it never starts a close that was not already
    // gradually coming, which is what keeps a board-wide event fair.
    if (playing && elapsed >= tremorAt) {
      final standing = _tremorCells.where((c) => grid.at(c)?.isSolid ?? false);
      if (standing.isEmpty) {
        tremorAt = double.infinity;
      } else {
        tremorAt = elapsed + tuning.tremorPeriod + tuning.tremorPeriod * 0.6;
        RegrowthSystem.surge(grid, tuning.tremorJump);
        tremorFlash = 1;
        fieldVersion++;
        juice.shake(3.0);
        if (sfx.play(Sound.warn, gain: 0.7, minInterval: 0.9)) {
          Haptics.medium();
        }
      }
    }
    tremorFlash = math.max(0, tremorFlash - dt * 1.4);

    // Captured before she moves, not after: taken afterwards it can only ever
    // equal her current cell, and the hint would never see her make progress.
    final wasIn = dog.cell;

    // The dog moves first, so regrowth sees the cell she is in *now*. Running
    // it the other way round leaves a one-frame window in which she can step
    // into a cell that is already past its snap threshold and get sealed inside
    // a wall.
    //
    // What the ground under her does this frame: ice mutes her steering, mire
    // halves her stride, and both go silent while SUREPAWS is running — that
    // immunity being the whole point of the pickup.
    final under = grid.at(dog.cell);
    final surepaw = powerups.surepawsActive;
    final onIce =
        !surepaw &&
        under != null &&
        under.type == HexType.ice &&
        under.isPassable;
    final onMire =
        !surepaw &&
        under != null &&
        under.type == HexType.mire &&
        under.isPassable;
    dog.update(
      dt: dt,
      grid: grid,
      layout: layout,
      tuning: tuning,
      fieldVersion: fieldVersion,
      regrowthActive: playing && tuning.regrowthEnabled && !tuning.zenMode,
      // A pet's pace rides the same slot as a sprint's: one multiplier, one
      // place, and no second speed channel to mis-balance.
      speedMultiplier: powerups.speedMultiplier * pet.perk.speedScale,
      // A cloak parts the patrol light: the refusal and the bite both go quiet.
      blocked: powerups.cloakActive ? const {} : guardedCells,
      controlScale: onIce ? 0.22 : 1.0,
      groundSpeedScale: onMire ? 0.5 : 1.0,
    );

    // Eddy and magnet are *continuous* forces, unlike the throws: they lean on
    // her velocity for as long as she stands on them, which is what makes them
    // readable instead of startling.
    if (!surepaw && under != null && under.type.pushesContinuously) {
      final centre = layout.toPixel(dog.cell);
      final away = dog.position - centre;
      if (away.distance > 1e-4) {
        final push = layout.width * 1.35 * dt / away.distance;
        dog.velocity += under.type == HexType.eddy ? away * push : -away * push;
      }
    }

    _updateScent();
    _collectPickups();
    if (!surepaw) {
      _checkSpring();
      _checkSlope();
    }
    if (playing) {
      _checkCaught();
      _checkContacts();
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
        dogOccupiedCells: dog.occupiedCells(layout),
        overgrowthAura: _heartsStanding ? overgrowthAura : const {},
        thatchDelay: tuning.thatchDelay,
        extraDelay: pet.perk.regrowDelta,
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
          // REWIND's ledger. Capped rather than compounding: the field only
          // owes recent history, and an unbounded list of every tile that ever
          // closed would make REWIND a map-size rewind.
          recentlyClosed.add(coord);
          if (recentlyClosed.length > 12) {
            recentlyClosed.removeAt(0);
          }
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
    _discoverNearbyNotice();

    if (dog.hasReachedExit(grid)) {
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
      // The keepsake is the one mercy in the game, and this is the sharper of
      // the two deaths it answers: the ground letting go, not the clock.
      if (powerups.consumePassive(PickupKind.keepsake)) {
        var freed = 0;
        for (final n in [dog.cell, ...dog.cell.disc(1)]) {
          final c = grid.at(n);
          if (c == null || !c.isSolid || c.type == HexType.anchor) {
            continue;
          }
          c
            ..revealed = true
            ..clear(elapsed);
          effects.shatter(layout.toPixel(n), layout.size, boost: 1.3);
          freed++;
        }
        dog.enclosedFor = 0;
        if (freed > 0) {
          fieldVersion++;
          juice.freeze(0.05);
          sfx.play(Sound.powerup);
          Haptics.heavy();
          announce('The keepsake bursts the field open', seconds: 3);
          return;
        }
        // Nothing around her would break — anchors hold. The mercy refunds.
        powerups.grant(PickupKind.keepsake);
      }
      _crush();
      return;
    }

    if (playing && tuning.hungerEnabled && hunger.isStarved) {
      if (powerups.consumePassive(PickupKind.keepsake)) {
        hunger.feed(ActiveEffects.keepsakeSeconds);
        startleFlash = 1;
        sfx.play(Sound.powerup);
        Haptics.heavy();
        announce('The keepsake feeds her once more', seconds: 3);
        return;
      }
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
          // A maul spends like a one-ring blast, so it counts toward the same
          // recovery maths — a run holding one may end nowhere the checker
          // could not have reached. The count folds into blast's allowance
          // rather than getting a column of its own, because the cheque is
          // "one tap, several hexes open" either way, maul simply narrower.
          blastCharges:
              powerups.chargesOf(PickupKind.blast) +
              powerups.chargesOf(PickupKind.maul),
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
  /// Withheld on Hard by reading the setting here rather than by writing
  /// `tuning.hintsEnabled`, which mirrors the player's own persisted toggle —
  /// overwriting that would make their switch appear to flip itself.
  bool get hintVisible =>
      tuning.hintsEnabled &&
      phase == GamePhase.playing &&
      !isOver &&
      (tutorial?.isDone ?? true) &&
      // The waystone is the one key the fog answers by itself: a quiet bow in
      // the exit's direction, asking nothing of the clock or the setting.
      (powerups.hasPassive(PickupKind.waystone) ||
          (!difficultyForRun.suppressesHints &&
              tuning.fogEnabled &&
              sinceProgress >= effectiveHintAfter));

  bool get _proximityHintsBlocked =>
      !tuning.hintsEnabled ||
      phase != GamePhase.playing ||
      isOver ||
      !(tutorial?.isDone ?? true) ||
      inspecting != null ||
      banner != null ||
      pickupNoticeReadFor > 0;

  void _updateHudNotices(double dt) {
    if (pickupNoticeReadFor > 0) {
      pickupNoticeReadFor = math.max(0, pickupNoticeReadFor - dt);
    }
    if (pickupNoticeFor > 0) {
      pickupNoticeFor = math.max(0, pickupNoticeFor - dt);
    }
    if (pickupNotice != null) {
      if (_pickupNoticeLive) {
        // Held just clear of zero rather than pinned high, so the moment the
        // power-up ends the card is already a fade away from gone.
        pickupNoticeFor = math.max(pickupNoticeFor, pickupNoticeFadeSeconds);
      } else if (pickupNoticeFor == 0) {
        pickupNotice = null;
      }
    }
    // Ages even while something else owns the slot. A notice held at full
    // duration through a banner comes back later to describe ground she left
    // long ago, which is worse than never having said it.
    if (proximityNoticeFor > 0) {
      proximityNoticeFor = math.max(0, proximityNoticeFor - dt);
      if (proximityNoticeFor == 0) proximityNotice = null;
    }
    _sinceHintShown += dt;
  }

  /// Whether the power-up the card describes is still doing something.
  ///
  /// A charge is live until it is spent, which is the whole point of its card:
  /// it names the tap the player still owes. A timed effect is live until it
  /// runs out. A passive is never live in this sense -- it is held for the rest
  /// of the run, and the charms row is where that belongs; a card that never
  /// left would own the slot for the whole level.
  bool get _pickupNoticeLive {
    final kind = pickupNotice?.pickup;
    if (kind == null || kind.isPassive) return false;
    return kind.isCharge ? powerups.has(kind) : powerups.isActive(kind);
  }

  void _discoverNearbyNotice() {
    if (_proximityHintsBlocked) return;
    if (proximityNotice != null) {
      _pendingNearby ??= _bestNearbyNotice();
      return;
    }
    if (_sinceHintShown < hintGapSeconds) return;
    final candidate =
        _pendingNearby != null && _nearbyStillValid(_pendingNearby!)
        ? _pendingNearby
        : _bestNearbyNotice();
    _pendingNearby = null;
    if (candidate == null) return;
    proximityNotice = candidate.notice;
    proximityNoticeFor = proximityNoticeSeconds;
    _encounteredNearby.add(candidate.key);
    _sinceHintShown = 0;
  }

  @visibleForTesting
  void debugRefreshNearbyNotice() => _discoverNearbyNotice();

  /// Pretend the gap between hints has passed, so a test can ask for the next
  /// one without running four seconds of frames to get it.
  @visibleForTesting
  void debugElapseHintGap() => _sinceHintShown = hintGapSeconds;

  /// Runs [seconds] of message and power-up clocks, in frames, without the rest
  /// of the game loop. A card's life is measured against the effect behind it,
  /// so the two have to be aged together.
  @visibleForTesting
  void debugElapseNotices(double seconds) {
    const dt = 1 / 60;
    for (var left = seconds; left > 0; left -= dt) {
      final step = math.min(dt, left);
      powerups.update(step);
      _updateHudNotices(step);
    }
  }

  @visibleForTesting
  void debugTakePickup(Pickup pickup) => _takePickup(pickup);

  /// The next mechanic she is walking into, or null.
  ///
  /// Read down her own route rather than out of a disc around her: a warning is
  /// only a warning if it is about ground she has not reached. A ring scan
  /// cannot tell the thorn ahead from the thorn she is standing in, which is
  /// how this came to caption arrivals instead of preceding them.
  ///
  /// Power-ups are deliberately absent. There is nothing to react to in walking
  /// into something good, and the card she gets on collecting it already says
  /// what it does -- an approach hint only spent the slot twice.
  _NearbyNotice? _bestNearbyNotice() {
    // Standing still, or barely moving: she is approaching nothing, so there is
    // nothing to warn about. This is also what keeps the lead time below out of
    // a divide by zero before the player's first tap.
    final hexesPerSecond = dog.speed / layout.width;
    if (hexesPerSecond < _hintStillSpeed) return null;

    final route = dog.route;
    final candidates = <_NearbyNotice>[];
    final last = math.min(hintLookaheadTo, route.length - 1);
    for (var step = hintLookaheadFrom; step <= last; step++) {
      final lead = step / hexesPerSecond;
      if (lead < hintLeadMin) continue;
      if (lead > hintLeadMax) break;
      final coord = route[step];
      final cell = grid.at(coord);
      if (cell == null ||
          !cell.revealed ||
          cell.type == HexType.plain ||
          _encounteredNearby.contains(cell.type) ||
          // Ground she has already crossed taught whatever it was going to.
          dog.trail.contains(coord)) {
        continue;
      }
      candidates.add(
        _NearbyNotice(
          HudNotice.proximity(hex: cell.type),
          coord,
          cell.type,
          _nearbyPriority(cell.type),
          step,
        ),
      );
    }
    if (candidates.isEmpty) return null;
    // Soonest wins, and dangerous ground only breaks the tie. The old ordering
    // was the other way round, which was right for a ring scan -- everything in
    // one is equally imminent -- and wrong here, where the whole list is ahead
    // of her and the one she reaches first is the one she can still avoid.
    candidates.sort((a, b) {
      final step = a.step.compareTo(b.step);
      return step != 0 ? step : a.priority.compareTo(b.priority);
    });
    return candidates.first;
  }

  bool _nearbyStillValid(_NearbyNotice candidate) {
    if (_encounteredNearby.contains(candidate.key)) return false;
    final hexesPerSecond = dog.speed / layout.width;
    if (hexesPerSecond < _hintStillSpeed) return false;
    final step = dog.route.indexOf(candidate.coord);
    if (step < hintLookaheadFrom ||
        step > hintLookaheadTo ||
        step / hexesPerSecond > hintLeadMax) {
      return false;
    }
    final cell = grid.at(candidate.coord);
    return cell != null && cell.revealed && cell.type == candidate.notice.hex;
  }

  static int _nearbyPriority(HexType type) => switch (type) {
    HexType.thorn ||
    HexType.alarm ||
    HexType.spring ||
    HexType.slope ||
    HexType.ice ||
    HexType.mire ||
    HexType.eddy ||
    HexType.magnet ||
    HexType.fault ||
    HexType.thatch => 0,
    _ => 1,
  };

  double get hintStrength =>
      ((sinceProgress - effectiveHintAfter) / 1.2).clamp(0.0, 1.0);

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
    RevealSystem.radiusFor(baseTapRadius, tuning.revealFactor) *
        powerups.revealMultiplier *
        pet.perk.revealScale,
    effectiveTapRadius * 1.2,
  );

  void _revealAround() {
    RevealSystem.reveal(
      grid: grid,
      layout: layout,
      dogPosition: dog.position,
      dogCell: dog.cell,
      radius: revealRadius,
    );
    // Planted beacons hold their own bubble of sight for the rest of the run:
    // the whole point is a place staying known after she leaves it.
    for (final lamp in beaconsLit) {
      RevealSystem.reveal(
        grid: grid,
        layout: layout,
        dogPosition: layout.toPixel(lamp),
        dogCell: lamp,
        radius: ActiveEffects.beaconRadius * layout.width,
      );
    }
  }

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
        progress?.recordEndlessClear(
          level: levelNumber,
          difficulty: difficultyForRun,
        );
      } else {
        progress?.recordWin(
          level: levelNumber,
          stars: stars,
          taps: taps,
          time: levelTime,
          difficulty: difficultyForRun,
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
    effects.boneShower(
      layout.toPixel(grid.exit),
      layout.size,
      reducedMotion: tuning.reducedMotion,
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
    _takePickup(taken);
  }

  /// One pickup arriving, by whatever route — her paws, or a HARVEST.
  ///
  /// Split from [_collectPickups] because the magnet's whole trick is that the
  /// pickup never moves. The economy logic (what a treat pays, what a charge
  /// announces) must live in exactly one place or the two paths will disagree
  /// about what a pouch doubles.
  void _takePickup(Pickup taken) {
    switch (taken.kind) {
      case PickupKind.treat:
        wagBoost = 1;
        sfx.play(Sound.treat);
        // A pouch is the one merchant on the board, and it deals only in
        // treats — spend it the moment it doubles one.
        final doubled = powerups.consumePassive(PickupKind.pouch) ? 2 : 1;
        final beforeFood = hunger.remaining;
        hunger.feed(tuning.treatSeconds * doubled);
        final secondsAdded = hunger.remaining - beforeFood;
        final tapsAdded = tuning.treatTaps.round() * doubled;
        tapBudget += tapsAdded;
        foodSecondsRefunded += secondsAdded;
        foodTapsRefunded += tapsAdded;
        final receipt = <String>[
          if (tuning.hungerEnabled) '+${secondsAdded.toStringAsFixed(1)}s',
          if (budgetLimited) '+$tapsAdded ${tapsAdded == 1 ? 'tap' : 'taps'}',
          if (doubled > 1) 'pouch',
        ];
        foodReceipt = receipt.isEmpty ? 'Bone collected' : receipt.join(' · ');
        foodReceiptFor = 2.5;
      case PickupKind.ration:
        // Taps, nothing else: the budget rescue, priced like a treat minus
        // the seconds.
        wagBoost = 1;
        sfx.play(Sound.treat);
        final tapsAdded = ActiveEffects.rationTaps;
        tapBudget += tapsAdded;
        foodTapsRefunded += tapsAdded;
        foodReceipt = '+$tapsAdded taps';
        foodReceiptFor = 2.5;
      default:
        sfx.play(Sound.powerup);
        powerups.grant(taken.kind);
        pickupNotice = HudNotice.pickup(taken.kind);
        // Charges wait for a tap, so they need to say so -- and the card
        // already renders `readyHint` for them, so a banner saying it again was
        // the same sentence twice. Worse, a banner suppresses contextual hints
        // for its whole life, so collecting a charge went quiet for four
        // seconds. One channel, held long enough to read.
        pickupNoticeReadFor = taken.kind.isCharge
            ? chargeNoticeSeconds
            : pickupNoticeSeconds;
        pickupNoticeFor = pickupNoticeReadFor;
        // Timed effects show themselves as the ring closing round her; passives
        // say once what they are, then quietly stay.
        if (taken.kind.isPassive) {
          announce(
            taken.kind == PickupKind.keepsake
                ? 'KEEPSAKE — one mercy, carried now'
                : '${taken.kind.label} — yours for the rest of the run',
          );
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
          grid.remainingCost,
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

  void _checkSlope() {
    if (_springCooldown > 0 || dog.isLaunched) {
      return;
    }
    final cell = grid.at(dog.cell);
    if (cell == null || cell.type != HexType.slope) {
      return;
    }
    // The tile's own direction, never hers. That is the entire difference
    // between this and a spring, and it is what makes a slope something a
    // player can route through on purpose.
    final away =
        layout.toPixel(dog.cell + HexCoord.directions[cell.slopeDirection]) -
        layout.toPixel(dog.cell);
    if (away.distance < 1e-6) {
      return;
    }
    // Shares the spring's cooldown deliberately: it exists to stop two throws
    // volleying her about with no input in between, and it does not care which
    // kind of tile did the throwing.
    _springCooldown = 0.5;
    dog.launch(away, layout.width * _slopeHexesPerSecond, duration: 0.26);
    juice.shake(1.6);
    sfx.play(Sound.powerup, gain: 0.45);
    Haptics.light();
  }

  /// How fast a slope pushes her, in hex widths per second.
  ///
  /// Well under the spring's, and short with it. A spring is a throw you set up
  /// and spend; a slope is a lane you either use or stay out of, so it has to
  /// move her far enough to matter and not so far that reading the arrow stops
  /// being enough to predict where she lands.
  static const _slopeHexesPerSecond = 5.0;

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
    if (powerups.cloakActive) {
      return;
    }
    if (_caughtCooldown > 0 || !guardedCells.contains(dog.cell)) {
      return;
    }
    _caughtCooldown = 1.6;
    if (tuning.hungerEnabled) {
      hunger.bite(guardBiteSeconds * difficultyForRun.biteScale);
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

  /// What standing on a tile does to her, once she is actually on it.
  ///
  /// One check for all three contact ideas, because they share an ordering
  /// rule: they fire on the tile she *arrived* at, never under the one she is
  /// leaving, and never at all while IRONPAW is worn.
  void _checkContacts() {
    final cell = grid.at(dog.cell);
    if (cell == null || !cell.isPassable) {
      return;
    }
    // Crossing a braid marks it: its closing clock only starts when she
    // leaves, and it only closes because she came.
    if (cell.type == HexType.thatch && !cell.crossed) {
      cell.crossed = true;
    }
    if (powerups.hasPassive(PickupKind.ironpaw)) {
      return;
    }
    if (cell.type == HexType.thorn && _thornCooldown <= 0) {
      _thornCooldown = 1.2;
      if (tuning.hungerEnabled) {
        hunger.bite(tuning.thornSeconds * difficultyForRun.biteScale);
      }
      startleFlash = 1;
      juice.shake(2.6);
      sfx.play(Sound.crack, gain: 0.7);
      Haptics.medium();
    }
    // An alarm re-arms only once the hurry has run out — standing on the bell
    // cannot keep the lights whipped forever.
    if (cell.type == HexType.alarm && alarmFor <= 0) {
      alarmFor = ActiveEffects.alarmSeconds * difficultyForRun.rhythmScale;
      wardFlash = 1;
      juice.shake(3.4);
      sfx.play(Sound.warn, gain: 0.9);
      Haptics.heavy();
      announce('Alarm — the lights hurry');
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
  ///
  /// One tool is armed at a time, so the checks below never race — their order
  /// is just reading order, from the most surprising target (a wall becoming
  /// ground, ground becoming a wall) to the plainest one (a bigger carve).
  bool _spendCharge(TapOutcome outcome, HexCoord coord) {
    // DIG answers both kinds of wall: rivets and overgrowth hearts both
    // report the anchor outcome, by deliberate sharing of the refusal.
    if (outcome == TapOutcome.anchor &&
        powerups.spendSelected(PickupKind.dig)) {
      _dig(coord);
      return true;
    }
    // Checked before blast, which also accepts `nothingToClear`.
    if (outcome == TapOutcome.nothingToClear &&
        (grid.at(coord)?.isSolid ?? true) == false &&
        powerups.spendSelected(PickupKind.stake)) {
      _stake(coord);
      return true;
    }
    if (outcome == TapOutcome.hit) {
      // SEED builds rather than opens — the exact inverse of DIG. Only plain
      // ground may be taken; spending a wall-making tool on a mechanic's tile
      // would quietly erase it.
      if (powerups.selectedCharge == PickupKind.seed) {
        final cell = grid.at(coord)!;
        if (cell.type != HexType.plain) {
          announce('Seed takes plain ground only', seconds: 2.5);
          return false; // stays armed; the tap then falls through and carves
        }
        if (!powerups.spendSelected(PickupKind.seed)) {
          return false;
        }
        final ok = _seed(coord);
        if (!ok) {
          // The field refused: hand the charge back. A tool that fails must
          // never cost the player its bullet.
          powerups.grant(PickupKind.seed);
          announce('Walling that would seal her in', seconds: 2.5);
          return false;
        }
        return true;
      }
      // MAUL: one tap, any clearable tile, fully open — hardpan included, and
      // a mirror answered alone, which is the one way around its pairing.
      if (powerups.selectedCharge == PickupKind.maul &&
          powerups.spendSelected(PickupKind.maul)) {
        _maul(coord);
        return true;
      }
      // TROWEL: the line carve. The tapped tile and the two straight ahead.
      if (powerups.selectedCharge == PickupKind.trowel &&
          powerups.spendSelected(PickupKind.trowel)) {
        _trowel(coord);
        return true;
      }
    }
    if ((outcome == TapOutcome.hit || outcome == TapOutcome.nothingToClear) &&
        powerups.spendSelected(PickupKind.blast)) {
      _blast(coord);
      return true;
    }
    return false;
  }

  /// Spends an armed charge that needs no particular tile — REWIND, HARVEST,
  /// WHISTLE and BEACON encode *when*, not *where*, so any tap discharges
  /// them. Returns true when the tap was the discharge.
  bool _spendTargetFree() {
    final armed = powerups.selectedCharge;
    if (armed == null || armed.needsTarget) {
      return false;
    }
    if (armed == PickupKind.rewind) {
      if (!_rewind()) {
        return false; // nothing has closed yet; stays armed
      }
      powerups.spendSelected(armed);
      return true;
    }
    if (armed == PickupKind.whistle) {
      if (!_whistle()) {
        return false; // no trail yet; stays armed
      }
      powerups.spendSelected(armed);
      return true;
    }
    if (armed == PickupKind.harvest && powerups.spendSelected(armed)) {
      _harvest();
      return true;
    }
    if (armed == PickupKind.beacon && powerups.spendSelected(armed)) {
      _plantBeacon();
      return true;
    }
    return false;
  }

  /// One tap, one tile that never closes again.
  void _stake(HexCoord coord) {
    final cell = grid.at(coord);
    if (cell == null) {
      return;
    }
    cell
      ..pinned = true
      // Anything already mid-close is pulled back open. Staking a tile whose
      // warning pulses had started must save it, or the tool would fail in the
      // exact moment a player reaches for it.
      ..state = CellState.open
      ..regrowT = 0
      ..eligibleSince = null
      ..clearBurst = 1;
    fieldVersion++;
    sfx.play(Sound.thunk);
    Haptics.medium();
    effects.shatter(layout.toPixel(coord), layout.size, colour: Palette.stake);
    announce('Pinned open');
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
      _tripSwitchFor(cell);
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

  /// The only thing in the game that removes an anchor — or a heart. DIG
  /// converts the tile to plain ground first, which both opens it and, for
  /// overgrowth, cuts the aura: whatever the tile *was* stops being true.
  void _dig(HexCoord coord) {
    if (phase == GamePhase.idle) {
      phase = GamePhase.playing;
    }
    taps++;
    final cell = grid.at(coord)!;
    final wasHeart = cell.type == HexType.overgrowth;
    cell
      ..type = HexType.plain
      ..revealed = true
      ..clear(elapsed);
    if (wasHeart) {
      _refreshHearts();
    }
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

  /// Whether any heart still stands, recomputed when one is dug out.
  void _refreshHearts() {
    _heartsStanding = _heartCells.any(
      (c) => grid.at(c)?.type == HexType.overgrowth,
    );
    if (!_heartsStanding) {
      announce('The overgrowth’s grip lets go', seconds: 3);
    }
  }

  /// MAUL: one tile answers one strike, whatever it was. Even a mirror, which
  /// otherwise insists on being answered twice — the pair rule reads the open
  /// half and opens the other when it next charges.
  void _maul(HexCoord coord) {
    if (phase == GamePhase.idle) {
      phase = GamePhase.playing;
    }
    taps++;
    final cell = grid.at(coord)!;
    cell
      ..revealed = true
      ..clear(elapsed);
    _tripSwitchFor(cell);
    if (cell.type == HexType.overgrowth) {
      _refreshHearts();
    }
    fieldVersion++;
    effects.shatter(layout.toPixel(coord), layout.size, boost: 1.5);
    juice.shake(4.5);
    sfx.play(Sound.crush, gain: 0.9);
    Haptics.heavy();
    tapRingFlash = 1;
    streak.register(
      grid: grid,
      tapped: coord,
      dogCell: dog.cell,
      carved: false,
    );
  }

  /// TROWEL: the tapped tile and the two cells straight ahead of it, from her.
  /// The direction is from her position rather than along screen axes, so the
  /// trail runs *away from her* — the only heading the game means anything by.
  void _trowel(HexCoord coord) {
    if (phase == GamePhase.idle) {
      phase = GamePhase.playing;
    }
    taps++;
    final centre = layout.toPixel(coord);
    final away = centre - dog.position;
    var direction = 0;
    if (away.distance > 1e-6) {
      // Rank the six hex directions by how closely their vector from the
      // tapped cell continues the line she → the tap.
      var best = -1.0;
      for (var i = 0; i < HexCoord.directions.length; i++) {
        final v = layout.toPixel(coord + HexCoord.directions[i]) - centre;
        if (v.distance < 1e-6) {
          continue;
        }
        final cos =
            (away.dx * v.dx + away.dy * v.dy) / (away.distance * v.distance);
        if (cos > best) {
          best = cos;
          direction = i;
        }
      }
    }
    var opened = 0;
    var cursor = coord;
    for (var i = 0; i < 3; i++) {
      final cell = grid.at(cursor);
      if (cell == null || !cell.isClearable) {
        break; // the trail stops at the first tile it cannot carry to
      }
      cell
        ..revealed = true
        ..clear(elapsed);
      _tripSwitchFor(cell);
      effects.shatter(layout.toPixel(cursor), layout.size, boost: 1.2);
      opened++;
      cursor += HexCoord.directions[direction];
    }
    if (opened > 0) {
      fieldVersion++;
    }
    juice.shake(3.4);
    sfx.play(Sound.snap, gain: 0.85);
    Haptics.medium();
    tapRingFlash = 1;
    streak.register(
      grid: grid,
      tapped: coord,
      dogCell: dog.cell,
      carved: opened > 0,
    );
  }

  /// SEED: plain ground becomes a wall — *if* the field still answers. This is
  /// the one player action that makes ground worse, so it is the one action
  /// that gets the generator's own solvability check before it commits.
  bool _seed(HexCoord coord) {
    final cell = grid.at(coord)!;
    cell.type = HexType.anchor;
    cell.state = CellState.solid;
    if (Pathfinder.reachable(
      dog.cell,
      grid.exit,
      grid.isTraversableInPrinciple,
    )) {
      if (phase == GamePhase.idle) {
        phase = GamePhase.playing;
      }
      taps++;
      grid.invalidateTopology();
      fieldVersion++;
      effects.ripple(layout.toPixel(coord), layout.size);
      sfx.play(Sound.thunk);
      Haptics.medium();
      announce('Wall raised');
      return true;
    }
    cell
      ..type = HexType.plain
      ..state = CellState.solid;
    return false;
  }

  /// ECHO's mirrored strike, the opposite bank of her. Uses the same carve
  /// rules as a tap — hit costs and pairwork included — otherwise the echo
  /// would secretly be a weaker maul. Skips over what a tap cannot touch.
  void _echoStrike(HexCoord tapped) {
    if (phase == GamePhase.idle) {
      phase = GamePhase.playing;
    }
    final mirrored = HexCoord(
      2 * dog.cell.q - tapped.q,
      2 * dog.cell.r - tapped.r,
    );
    final cell = grid.at(mirrored);
    if (cell == null || !cell.isClearable) {
      announce('Nothing mirrored to strike', seconds: 2.5);
      return;
    }
    // Costs no tap of its own: the pair of carves is the one decision.
    if (cell.type == HexType.mirror) {
      _carveMirror(mirrored);
    } else {
      var opened = cell.hit(elapsed);
      if (!opened && powerups.pairworkActive && cell.isSolid) {
        opened = cell.hit(elapsed);
      }
      if (opened) {
        _tripSwitchFor(cell);
        if (cell.type == HexType.overgrowth) {
          _refreshHearts();
        }
      }
      effects.shatter(
        layout.toPixel(mirrored),
        layout.size,
        boost: opened ? 1.2 : 0.5,
      );
      sfx.play(Sound.crack, gain: 0.8);
    }
    fieldVersion++;
    tapRingFlash = 1;
  }

  /// One charge of a mirror pair, shared by the tap path and the echo's bank.
  /// Returns whether the pair gave way. Opening reads: both halves charged (or
  /// one already open, courtesy of a blast, maul or mole) → both stand open.
  bool _carveMirror(HexCoord coord) {
    final cell = grid.at(coord);
    if (cell == null || cell.isPassable) {
      return false;
    }
    cell.charge();
    final partner = cell.partner == null ? null : grid.at(cell.partner!);
    final partnerGives =
        partner != null && (partner.charged || partner.isPassable);
    if (!partnerGives) {
      effects.shatter(layout.toPixel(coord), layout.size, boost: 0.7);
      sfx.play(Sound.crack, gain: 0.7);
      Haptics.light();
      return false;
    }
    if (partner.isSolid && !partner.isPassable) {
      partner
        ..revealed = true
        ..clear(elapsed);
      _tripSwitchFor(partner);
      effects.shatter(layout.toPixel(partner.coord), layout.size, boost: 1.2);
    }
    cell
      ..revealed = true
      ..clear(elapsed);
    _tripSwitchFor(cell);
    effects.shatter(layout.toPixel(coord), layout.size, boost: 1.4);
    sfx.play(Sound.powerup, gain: 0.8);
    Haptics.medium();
    announce('The pair gives', seconds: 2.5);
    return true;
  }

  /// MOLE: reaches past the tap ring to open any one revealed clearable tile —
  /// the tunnel-mouse picks up the route three streets away.
  void _moleOpen(HexCoord coord) {
    if (phase == GamePhase.idle) {
      phase = GamePhase.playing;
    }
    taps++;
    final cell = grid.at(coord)!;
    cell
      ..revealed = true
      ..clear(elapsed);
    _tripSwitchFor(cell);
    if (cell.type == HexType.overgrowth) {
      _refreshHearts();
    }
    fieldVersion++;
    effects.shatter(layout.toPixel(coord), layout.size, boost: 1.3);
    juice.shake(2.6);
    sfx.play(Sound.snap, gain: 0.8);
    Haptics.medium();
    tapRingFlash = 1;
    streak.register(
      grid: grid,
      tapped: coord,
      dogCell: dog.cell,
      carved: false,
    );
  }

  /// REWIND: the field hands back the last few tiles it closed.
  bool _rewind() {
    if (recentlyClosed.isEmpty) {
      announce('Nothing has closed yet', seconds: 2.5);
      return false;
    }
    var reopened = 0;
    final seen = <HexCoord>{};
    for (var i = recentlyClosed.length - 1; i >= 0 && reopened < 6; i--) {
      final coord = recentlyClosed[i];
      if (!seen.add(coord)) {
        continue;
      }
      final cell = grid.at(coord);
      if (cell == null || !cell.isSolid) {
        continue;
      }
      cell
        ..revealed = true
        ..clear(elapsed);
      effects.ripple(layout.toPixel(coord), layout.size);
      reopened++;
    }
    if (reopened == 0) {
      announce('What closed is already gone', seconds: 2.5);
      return false;
    }
    fieldVersion++;
    sinceProgress = 0;
    juice.shake(2.8);
    sfx.play(Sound.powerup, gain: 0.8);
    Haptics.medium();
    announce(
      'The field gives back $reopened ${reopened == 1 ? 'tile' : 'tiles'}',
    );
    return true;
  }

  /// WHISTLE: she walks three cells back along the trail she actually walked
  /// — her memory, never a line of sight.
  bool _whistle() {
    final back = dog.trailCellBack(ActiveEffects.whistleSteps);
    if (back == null) {
      announce('No trail to walk back', seconds: 2.5);
      return false;
    }
    dog
      ..position = layout.toPixel(back)
      ..cell = back
      ..velocity = Offset.zero;
    barkFlash = 0.8;
    sfx.play(Sound.bark, gain: 0.7);
    Haptics.light();
    effects.shatter(dog.position, layout.size, boost: 0.9);
    fieldVersion++;
    announce('Back she goes');
    return true;
  }

  /// HARVEST: the nearest unclaimed thing worth walking to walks to *us*.
  /// The magnet that never moves the tile, so the board around it stays true.
  void _harvest() {
    Pickup? nearest;
    var bestDistance = 1 << 20;
    for (final p in pickups) {
      if (p.collected) {
        continue;
      }
      final d = p.coord.distanceTo(dog.cell);
      if (d <= ActiveEffects.harvestRadius && d < bestDistance) {
        bestDistance = d;
        nearest = p;
      }
    }
    if (nearest == null) {
      announce('Nothing in reach to fetch', seconds: 2.5);
      return;
    }
    nearest
      ..collected = true
      ..collectFlash = 1;
    _takePickup(nearest);
  }

  /// BEACON: plant a lamp on the cell she stands in; the ground there stays
  /// known for the rest of the run.
  void _plantBeacon() {
    if (beaconsLit.contains(dog.cell)) {
      return; // already lit; charge already spent, as the tap said "here"
    }
    beaconsLit = [...beaconsLit, dog.cell];
    effects.ripple(layout.toPixel(dog.cell), layout.size);
    juice.shake(1.8);
    sfx.play(Sound.powerup, gain: 0.7);
    Haptics.light();
    announce('Lamp planted');
  }

  /// A switch has been opened: whatever lockbar shares its link lifts now.
  /// Lifting counts as the field changing — walls of light still have to play
  /// by the one rule every closing does (announced, and reachable when lit).
  void _tripSwitchFor(HexCell cell) {
    if (cell.type != HexType.switchTile || cell.link < 0) {
      return;
    }
    var lifted = 0;
    for (final c in grid.all) {
      if (c.type == HexType.gate && c.link == cell.link && !c.gateOpen) {
        c
          ..gateOpen = true
          ..revealed = true; // the lock tells you what answering bought
        effects.ripple(layout.toPixel(c.coord), layout.size);
        lifted++;
      }
    }
    if (lifted > 0) {
      fieldVersion++;
      sfx.play(Sound.thunk, gain: 0.8);
      Haptics.medium();
      announce('A lockbar lifts, somewhere');
    }
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

  /// Hold a finger on a tile to be told what it is.
  ///
  /// Flame delivers this *after* [onTapDown], never instead of it, because
  /// Flutter hands over a tap-down the moment a finger lands and only later
  /// decides the gesture was a hold. That ordering is what makes the feature
  /// affordable rather than awkward: the tiles a player actually wants to ask
  /// about are the ones a tap cannot do anything with — a riveted wall, ground
  /// out of reach, a tile already open — and those all cost nothing to tap. A
  /// hold on a wall is free. A hold on a tile in reach carves it, but that is
  /// the tap the player already spent by touching it.
  @override
  void onLongTapDown(TapDownEvent event) {
    if (!_ready || isOver || tutorialReading || !tuning.hintsEnabled) {
      return;
    }
    final point = Offset(event.canvasPosition.x, event.canvasPosition.y);
    final coord = layout.toHex(point);
    final cell = grid.at(coord);
    if (cell == null) {
      return;
    }

    // A pickup lying on the ground answers a different question than the
    // ground does — "is that detour worth it?" — and it is the one the player
    // has to answer before walking, so it wins the card.
    PickupKind? pickup;
    for (final p in pickups) {
      if (!p.collected && p.coord == coord) {
        pickup = p.kind;
        break;
      }
    }

    inspecting = (
      coord: coord,
      pickup: pickup,
      hex: cell.revealed ? cell.type : null,
    );
    inspectFor = inspectSeconds;
  }

  /// Show what a held charge does, from the HUD button rather than the board.
  ///
  /// A charge is the one thing on screen with no board tile to hold: it sits in
  /// the HUD until it is spent, which is exactly why it needed a place there in
  /// the first place, and "what does STAKE actually do" is the question a
  /// player holding one is most likely to have.
  void inspectPickup(PickupKind kind) {
    if (!tuning.hintsEnabled) {
      return;
    }
    inspecting = (coord: dog.cell, pickup: kind, hex: null);
    inspectFor = inspectSeconds;
  }

  @override
  void onTapDown(TapDownEvent event) {
    handleBoardTapAt(Offset(event.canvasPosition.x, event.canvasPosition.y));
  }

  /// A tap on the board, in screen pixels.
  ///
  /// Split out from [onTapDown] so the whole of tap handling can be exercised
  /// without a Flame lifecycle — a `GameWidget` needs async asset loading that
  /// no other test in this suite pays for, which is why the rules of tapping
  /// were the one part of the game with no direct test.
  void handleBoardTapAt(Offset point) {
    if (!_ready || isOver || tutorialReading) {
      return;
    }

    // MOLE reaches past the tap ring, so it is resolved straight against the
    // board before the ring's rules apply. What it may take is still honest —
    // revealed, clearable, no walls, no mines — told in words when it is not.
    if (powerups.selectedCharge == PickupKind.mole &&
        tapsLeft > 0 &&
        !tutorialReading) {
      final coord = layout.toHex(point);
      final cell = grid.at(coord);
      if (cell == null || !grid.contains(coord)) {
        tapRingFlash = 1;
        return;
      }
      if (!cell.isClearable || !cell.revealed) {
        announce(
          cell.revealed
              ? 'The mouse cannot get through that'
              : 'Send the mouse only where you know',
          seconds: 2.5,
        );
        final c2 = grid.at(coord);
        if (c2 != null) c2.rejectShake = 1;
        return;
      }
      if (powerups.spendSelected(PickupKind.mole)) {
        _moleOpen(coord);
      }
      return;
    }

    final result = InputSystem.resolve(
      point: point,
      grid: grid,
      layout: layout,
      dogPosition: dog.position,
      tapRadius: effectiveTapRadius,
      // WARDOWN parts the pale light the way CLOAK parts the red.
      warded: powerups.wardownActive ? const {} : wardedCells,
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

    // A charge that needs no target encodes *when*, so any tap discharges it.
    if (tapsLeft > 0 && powerups.selectedCharge != null && _spendTargetFree()) {
      return;
    }

    // HEEL is spent *outside* _spendCharge, which exists to finish a tap. This
    // one rides along with it: the whole point is to open the corridor ahead
    // and not have her walk into it while you do, so the carve still has to
    // happen.
    if (result.outcome == TapOutcome.hit &&
        tapsLeft > 0 &&
        powerups.spendSelected(PickupKind.heel)) {
      dog.holdFor = ActiveEffects.heelSeconds;
      sfx.play(Sound.snap);
      Haptics.medium();
      announce('Held');
    }

    // ECHO rides the same carve: the tap lands, and its mirror answers on the
    // opposite bank of her. One decision, two carves.
    final echoArmed =
        result.outcome == TapOutcome.hit &&
        tapsLeft > 0 &&
        powerups.selectedCharge == PickupKind.echo;

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
        var opened = false;
        if (cell.type == HexType.mirror && !cell.isPassable) {
          opened = _carveMirror(result.coord!);
          fieldVersion++;
          sinceProgress = 0;
        } else {
          opened = cell.hit(elapsed);
          // PAIRWORK is the one place a tap is worth two strikes: the second
          // arrives free, and only where the first left work to do.
          if (!opened && powerups.pairworkActive && cell.isSolid) {
            opened = cell.hit(elapsed);
          }
          if (opened) {
            _tripSwitchFor(cell);
            if (cell.type == HexType.overgrowth) {
              _refreshHearts();
            }
          }
        }

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

        if (echoArmed && powerups.spendSelected(PickupKind.echo)) {
          _echoStrike(result.coord!);
        }

      case TapOutcome.locked:
        // A lockbar is not a wall — it tells you *how* it opens. The inspector
        // answers where its switch is soon enough; the shake says not by hand.
        grid.at(result.coord!)!
          ..rejectShake = 1
          ..revealed = true;
        sfx.play(Sound.thunk);
        Haptics.heavy();
        announce(
          'Locked — the crest that matches is somewhere near',
          seconds: 3,
        );

      case TapOutcome.tooClose:
        grid.at(result.coord!)!.rejectShake = 1;
        sfx.play(Sound.thunk);
        Haptics.light();
        announce('A mine in reach of her dares not be tapped', seconds: 3);

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

      case TapOutcome.warded:
        // Costs nothing and breaks nothing. A sentry rations *when* you may
        // tap, not how many taps you have — charging a tap for it would make
        // it a second budget, and breaking the chain would make waiting out a
        // sweep punish the player twice for one obstacle.
        grid.at(result.coord!)!.rejectShake = 1;
        wardFlash = 1;
        sfx.play(Sound.thunk);
        Haptics.light();

      case TapOutcome.noFooting:
        // Costs nothing, for the reason a warded tap does: sunken ground
        // rations *where* you may carve from, not how many taps you hold. The
        // shake is on the tile rather than the ring because the ring is not
        // what refused — the tile is within reach and the player can see that.
        grid.at(result.coord!)!.rejectShake = 1;
        sfx.play(Sound.thunk);
        Haptics.light();
        announce('Sunken — carve up to it first');

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
