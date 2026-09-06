import '../hex/hex_coord.dart';

/// Things worth leaving the straight line for (§6.2).
///
/// All of them are picked up in the field, never chosen from a menu, which is
/// what keeps the game in continuous motion.
///
/// The set is built on one rule: **every powerup answers a pressure the game
/// actually applies.** Taps are rationed, so [blast], [ration], [pairwork],
/// [maul] and [trowel]. The clock runs, so [sprint]. The fog hides the route,
/// so [scent], [lantern], [beacon], [nightEyes] and [waystone]. Anchors wall
/// you off, so [dig] — and so [seed] builds one where you want it. Regrowth
/// closes behind you, so [freeze], [stake] and [rewind]. Reach is short, so
/// [radiusPlus] and [mole]. Patrols wait for nobody, so [cloak], [slowbeat]
/// and [heel]. The detour is not always affordable, so [harvest]. She never
/// stops, so [whistle]. The ground itself gets a vote, so [surepaws] and
/// [ironpaw]. A powerup that answers nothing is scenery the player learns to
/// walk past.
enum PickupKind {
  /// Buys back time *and* taps. The taps matter as much as the seconds: the fog
  /// guarantees some are spent discovering walls, so a tight budget needs a way
  /// to earn them back or it is arbitrary rather than demanding.
  treat,

  /// Buys back taps only — the budget rescue for a board where time is fine
  /// and taps are bleeding. Distinct from [treat] so a tight-budget level can
  /// offer exactly the help it is squeezing.
  ration,

  /// Regrowth pauses.
  freeze,

  /// A wider reach, so more of the route can be carved from one spot.
  radiusPlus,

  /// She moves faster. The answer to the clock.
  sprint,

  /// Lights the cheapest remaining route through the fog for a few seconds.
  /// Buys knowledge rather than resources.
  scent,

  /// A stronger light held high: the fog is pushed further back for a while.
  /// SCENT answers being lost with one route; this answers it with a map.
  lantern,

  /// Patrol light passes through her for a while: she may cross lit ground,
  /// unbitten and unshoved.
  cloak,

  /// Every light on the board sweeps at half speed for a while. The shared
  /// rhythm, slowed.
  slowbeat,

  /// Taps land through sentry light for a while. The ward is a window, not
  /// a wall.
  wardown,

  /// For a while she ignores what moving ground does to her: no spring
  /// throws, no arrow pushes, no ice slide, no eddy or magnet drift.
  surepaws,

  /// For a while every tap strikes the same tile twice. Brambles fall in one
  /// tap; hardpan in two. One tap is still spent — the allowance is not
  /// halved, only the hits.
  pairwork,

  /// One tap that clears a whole cluster instead of a single hex.
  blast,

  /// One tap that breaks a rivet or an overgrowth heart, permanently. The
  /// only thing in the game that can.
  dig,

  /// One tap that pins an open tile open, permanently.
  ///
  /// One cell, never a ring. A ring would let a player build a safe highway
  /// across the board, and the whole decision here is the sharpest question
  /// the game can ask: **which single tile must never close?**
  stake,

  /// One tap that carves as normal *and* holds her still for a moment. It
  /// holds; it does not steer — "you do not move her" survives intact, and
  /// the enclosure timer keeps running while she waits, so being held in a
  /// closing pocket still kills.
  heel,

  /// One tap that clears the tapped tile and the two cells straight ahead of
  /// it, as she reads ahead of her. The line version of [blast]: corridors
  /// and hardpan seams answer to it.
  trowel,

  /// One tap that fully breaks *any* clearable tile — a hardpan in a single
  /// hit. The direct answer to deep tap-tax tiles.
  maul,

  /// One tap that also strikes the tile mirrored across her position, if it
  /// can be cleared. The tool the mirror lock exists to be answered by.
  echo,

  /// Reopens the last few tiles the field closed, whoever closed them. The
  /// closing wave answered after the fact rather than before.
  ///
  /// Needs no target: armed, it is spent by the next tap anywhere.
  rewind,

  /// Clears any one *revealed*, non-wall tile, anywhere on the board — reach
  /// itself, once. The one deliberate exception to "you carve near her", and
  /// priced as a charge because of it.
  mole,

  /// Collects the nearest real pickup she could reasonably detour to, without
  /// the detour. Needs no target. Foxfire it ignores — the magnet takes only
  /// what is actually there.
  harvest,

  /// She backtracks three cells along her own trail — a rewind of her last
  /// stretch of drift, not steering. Needs no target. The undo for a bad
  /// spring, a wrong arrow lane, a magnet she leaned into.
  whistle,

  /// Tamps one solid plain tile into a permanent wall — the inverse of
  /// [dig]: it builds structure where the player decides. Refused, like the
  /// generator's anchors, the moment it would sever the route to the food.
  seed,

  /// Drops a lamp where she stands; it holds a bubble of revealed ground
  /// there for the rest of the run. Needs no target — the next tap spends it
  /// at whatever place she is standing on then.
  beacon,

  /// Luck, pocketed: the next treat pays double.
  pouch,

  /// Thorn pads and alarm bells no longer trigger when she crosses, for the
  /// rest of the run.
  ironpaw,

  /// She sees a little further for the rest of the run.
  nightEyes,

  /// The one mercy: the first time this run she would be crushed or starve,
  /// this is spent instead and she plays on.
  keepsake,

  /// Shows the bearing to the food for the rest of the run, without waiting
  /// for her to get stuck first.
  waystone;

  /// Whether the pickup system treats it as a powerup rather than a treat.
  /// Resources feed the economy; everything else grants an effect.
  bool get isPowerup =>
      this != PickupKind.treat && this != PickupKind.ration;

  /// Whether it pays taps back like a treat does (the recovery the soft-lock
  /// check may count on).
  bool get refundsTaps => this == PickupKind.treat || this == PickupKind.ration;

  /// Run-long keepsakes: granted once, never timed, shown on the HUD as
  /// charms rather than charge buttons.
  bool get isPassive =>
      this == PickupKind.pouch ||
      this == PickupKind.ironpaw ||
      this == PickupKind.nightEyes ||
      this == PickupKind.keepsake ||
      this == PickupKind.waystone;

  /// Whether this is spent as a single use rather than running for a while.
  ///
  /// One use is one decision: as timed effects these would scale with how fast
  /// the player can tap inside the window, which makes the strongest thing in
  /// the game a test of thumb speed.
  ///
  /// **Arming is what makes something a charge, not instantaneity.** They are
  /// spent by a deliberate second tap rather than simply happening.
  bool get isCharge =>
      this == PickupKind.blast ||
      this == PickupKind.dig ||
      this == PickupKind.stake ||
      this == PickupKind.heel ||
      this == PickupKind.trowel ||
      this == PickupKind.maul ||
      this == PickupKind.echo ||
      this == PickupKind.rewind ||
      this == PickupKind.mole ||
      this == PickupKind.harvest ||
      this == PickupKind.whistle ||
      this == PickupKind.seed ||
      this == PickupKind.beacon;

  /// Whether the charge needs a particular tile as its target. The rest —
  /// [rewind], [harvest], [whistle] and [beacon] — are spent by the next tap
  /// anywhere, because the decision they encode is *when*, not *where*.
  bool get needsTarget =>
      isCharge &&
      this != PickupKind.rewind &&
      this != PickupKind.harvest &&
      this != PickupKind.whistle &&
      this != PickupKind.beacon;

  /// How long the effect lasts. Resources, charges and passives are not
  /// timed, so zero.
  double get duration => switch (this) {
    PickupKind.freeze => 5.0,
    PickupKind.radiusPlus => 8.0,
    PickupKind.sprint => 6.0,
    PickupKind.scent => 5.0,
    PickupKind.lantern => 10.0,
    PickupKind.cloak => 7.0,
    PickupKind.slowbeat => 7.0,
    PickupKind.wardown => 7.0,
    PickupKind.surepaws => 10.0,
    PickupKind.pairwork => 8.0,
    _ => 0,
  };

  /// Shown on the HUD when it is picked up or held.
  String get label => switch (this) {
    PickupKind.treat => 'TREAT',
    PickupKind.ration => 'RATION',
    PickupKind.freeze => 'FREEZE',
    PickupKind.radiusPlus => 'REACH',
    PickupKind.sprint => 'SPRINT',
    PickupKind.scent => 'SCENT',
    PickupKind.lantern => 'LANTERN',
    PickupKind.cloak => 'CLOAK',
    PickupKind.slowbeat => 'SLOWBEAT',
    PickupKind.wardown => 'WARDOWN',
    PickupKind.surepaws => 'SUREPAWS',
    PickupKind.pairwork => 'PAIRWORK',
    PickupKind.blast => 'BLAST',
    PickupKind.dig => 'DIG',
    PickupKind.stake => 'STAKE',
    PickupKind.heel => 'HEEL',
    PickupKind.trowel => 'TROWEL',
    PickupKind.maul => 'MAUL',
    PickupKind.echo => 'ECHO',
    PickupKind.rewind => 'REWIND',
    PickupKind.mole => 'MOLE',
    PickupKind.harvest => 'HARVEST',
    PickupKind.whistle => 'WHISTLE',
    PickupKind.seed => 'SEED',
    PickupKind.beacon => 'BEACON',
    PickupKind.pouch => 'POUCH',
    PickupKind.ironpaw => 'IRONPAW',
    PickupKind.nightEyes => 'OWL EYES',
    PickupKind.keepsake => 'KEEPSAKE',
    PickupKind.waystone => 'WAYSTONE',
  };

  /// What the player has to do after explicitly arming a charge. Empty for the
  /// rest, which need no instruction because they simply happen.
  String get hint => switch (this) {
    PickupKind.blast => 'BLAST armed — tap a tile in reach',
    PickupKind.dig => 'DIG armed — tap a riveted tile or a heart',
    PickupKind.stake => 'STAKE armed — tap an open tile to pin it',
    PickupKind.heel => 'HEEL armed — your next tap also holds her still',
    PickupKind.trowel => 'TROWEL armed — tap a tile to clear three in a line',
    PickupKind.maul => 'MAUL armed — your next tap breaks any tile outright',
    PickupKind.echo => 'ECHO armed — your next tap strikes here and mirrored',
    PickupKind.rewind => 'REWIND armed — any tap reopens what just closed',
    PickupKind.mole => 'MOLE armed — tap any revealed tile, anywhere',
    PickupKind.harvest => 'HARVEST armed — any tap draws in the nearest prize',
    PickupKind.whistle => 'WHISTLE armed — any tap walks her back three',
    PickupKind.seed => 'SEED armed — tap a solid plain tile to wall it',
    PickupKind.beacon => 'BEACON armed — any tap plants a lamp where she stands',
    _ => '',
  };

  /// Pickup copy for charges. A newly collected tool stays safely put away so
  /// an ordinary carving tap can never spend it by surprise.
  String get readyHint => switch (this) {
    PickupKind.blast => 'BLAST ready — tap it above to arm',
    PickupKind.dig => 'DIG ready — tap it above to arm',
    PickupKind.stake => 'STAKE ready — tap it above to arm',
    PickupKind.heel => 'HEEL ready — tap it above to arm',
    PickupKind.trowel => 'TROWEL ready — tap it above to arm',
    PickupKind.maul => 'MAUL ready — tap it above to arm',
    PickupKind.echo => 'ECHO ready — tap it above to arm',
    PickupKind.rewind => 'REWIND ready — tap it above to arm',
    PickupKind.mole => 'MOLE ready — tap it above to arm',
    PickupKind.harvest => 'HARVEST ready — tap it above to arm',
    PickupKind.whistle => 'WHISTLE ready — tap it above to arm',
    PickupKind.seed => 'SEED ready — tap it above to arm',
    PickupKind.beacon => 'BEACON ready — tap it above to arm',
    _ => '',
  };
}

class Pickup {
  Pickup(this.kind, this.coord);

  final PickupKind kind;
  final HexCoord coord;

  bool collected = false;

  /// 1 -> 0 burst when taken.
  double collectFlash = 0;
}

/// Powerups currently running, charges currently held, and run-long charms.
///
/// Kept separate from [TuningConfig] on purpose: that holds the player's own
/// settings, and a temporary effect must never write into it — a powerup that
/// expired mid-edit would otherwise leave the tap radius permanently changed.
class ActiveEffects {
  final Map<PickupKind, double> _remaining = {};
  final Map<PickupKind, double> _total = {};
  final Map<PickupKind, int> _charges = {};
  final Set<PickupKind> _passives = {};
  PickupKind? _selectedCharge;

  static const radiusMultiplier = 1.6;

  /// Drift speed multiplier while sprint is running.
  static const sprintMultiplier = 1.65;

  /// How far a blast reaches from the tapped hex, in rings.
  static const blastRadius = 1;

  /// How many cells a trowel clears straight ahead of the tapped one, beyond
  /// the tapped cell itself.
  static const trowelLength = 2;

  /// How long HEEL holds her. Long enough to open the corridor ahead without
  /// her drifting into it; short enough that it buys one decision, not a rest.
  static const heelSeconds = 2.5;

  /// How many lapses of the field one rewind undoes.
  static const rewindCount = 6;

  /// How many cells a whistle walks her back along her own trail.
  static const whistleSteps = 3;

  /// How far a harvest reaches for a real pickup, in rings.
  static const harvestRadius = 5;

  /// The light a planted beacon holds open around itself, in hex widths.
  static const beaconRadius = 2.4;

  /// The clock a keepsake hands back when it plays its one mercy.
  static const keepsakeSeconds = 10.0;

  /// Lantern reach, and owl eyes' permanent fraction of it.
  static const lanternMultiplier = 1.8;
  static const nightEyesMultiplier = 1.25;

  /// How much the lights slow for a slowbeat, and how much an alarm hurries
  /// them.
  static const slowbeatFactor = 0.5;
  static const alarmFactor = 1.5;
  static const alarmSeconds = 6.0;

  /// What a ration pays back: taps without seconds, the pure budget rescue.
  static const rationTaps = 3;

  void grant(PickupKind kind) {
    if (!kind.isPowerup) {
      return;
    }
    if (kind.isPassive) {
      _passives.add(kind);
      return;
    }
    if (kind.isCharge) {
      _charges[kind] = (_charges[kind] ?? 0) + 1;
      return;
    }
    _remaining[kind] = kind.duration;
    _total[kind] = kind.duration;
  }

  void update(double dt) {
    for (final kind in _remaining.keys.toList()) {
      final left = _remaining[kind]! - dt;
      if (left <= 0) {
        _remaining.remove(kind);
        _total.remove(kind);
      } else {
        _remaining[kind] = left;
      }
    }
  }

  void clear() {
    _remaining.clear();
    _total.clear();
    _charges.clear();
    _passives.clear();
    _selectedCharge = null;
  }

  bool isActive(PickupKind kind) => (_remaining[kind] ?? 0) > 0;

  bool hasPassive(PickupKind kind) => _passives.contains(kind);

  /// Plays a passive's one-time mercy, if it has one. Returns whether the
  /// passive was there to spend. Pouch is consumed this way after doubling a
  /// treat; keepsake after saving the run.
  bool consumePassive(PickupKind kind) {
    if (!_passives.contains(kind)) {
      return false;
    }
    _passives.remove(kind);
    return true;
  }

  int chargesOf(PickupKind kind) => _charges[kind] ?? 0;

  bool has(PickupKind kind) => chargesOf(kind) > 0;

  /// The tool the player has deliberately armed. Collecting a charge never
  /// selects it; selection is a separate HUD action.
  PickupKind? get selectedCharge => _selectedCharge;

  /// Arms [kind], or puts it away when it is already armed. Arming one tool
  /// puts the other away, leaving exactly one predictable meaning for a tap.
  bool toggleCharge(PickupKind kind) {
    if (!kind.isCharge || !has(kind)) {
      return false;
    }
    if (_selectedCharge == kind) {
      _selectedCharge = null;
      return false;
    }
    _selectedCharge = kind;
    return true;
  }

  /// Spends one charge. Returns false when there was none, so callers can use
  /// this as the whole decision rather than checking and then spending.
  bool spend(PickupKind kind) {
    final held = _charges[kind] ?? 0;
    if (held <= 0) {
      return false;
    }
    if (held == 1) {
      _charges.remove(kind);
      if (_selectedCharge == kind) {
        _selectedCharge = null;
      }
    } else {
      _charges[kind] = held - 1;
    }
    return true;
  }

  /// Spends [kind] only when the player armed that exact tool.
  bool spendSelected(PickupKind kind) {
    if (_selectedCharge != kind) {
      return false;
    }
    return spend(kind);
  }

  bool get regrowthPaused => isActive(PickupKind.freeze);

  bool get scentActive => isActive(PickupKind.scent);

  /// Carpenter's taps: every hit lands twice while pairwork runs.
  bool get pairworkActive => isActive(PickupKind.pairwork);

  bool get cloakActive => isActive(PickupKind.cloak);

  bool get slowbeatActive => isActive(PickupKind.slowbeat);

  bool get wardownActive => isActive(PickupKind.wardown);

  bool get surepawsActive => isActive(PickupKind.surepaws);

  double get tapRadiusMultiplier =>
      isActive(PickupKind.radiusPlus) ? radiusMultiplier : 1.0;

  /// Multiplies how far the fog is pushed back: lantern first, then the
  /// permanent nudge of owl eyes underneath it.
  double get revealMultiplier =>
      (isActive(PickupKind.lantern) ? lanternMultiplier : 1.0) *
      (hasPassive(PickupKind.nightEyes) ? nightEyesMultiplier : 1.0);

  /// Multiplies her drift speed. One, unless sprint is running.
  double get speedMultiplier =>
      isActive(PickupKind.sprint) ? sprintMultiplier : 1.0;

  /// The effect with the most time left, and how much of it remains, for the
  /// shrinking ring drawn around the dog (§6.2). Null when nothing is running.
  ///
  /// Charges are deliberately not eligible: the ring shows time draining away,
  /// and a charge has no time to drain. Those are shown on the HUD instead.
  ({PickupKind kind, double fraction})? get leading {
    PickupKind? best;
    var bestLeft = 0.0;
    for (final entry in _remaining.entries) {
      if (entry.value > bestLeft) {
        bestLeft = entry.value;
        best = entry.key;
      }
    }
    if (best == null) {
      return null;
    }
    final total = _total[best] ?? 1;
    return (kind: best, fraction: (bestLeft / total).clamp(0.0, 1.0));
  }

  /// Charges held, in a stable order, for the HUD.
  List<({PickupKind kind, int count})> get heldCharges => [
    for (final kind in PickupKind.values)
      if (kind.isCharge && chargesOf(kind) > 0)
        (kind: kind, count: chargesOf(kind)),
  ];

  /// Charms in effect, in a stable order, for the HUD.
  List<PickupKind> get heldPassives => [
    for (final kind in PickupKind.values)
      if (kind.isPassive && hasPassive(kind)) kind,
  ];
}
