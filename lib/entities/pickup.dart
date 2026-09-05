import '../hex/hex_coord.dart';

/// Things worth leaving the straight line for (§6.2).
///
/// All of them are picked up in the field, never chosen from a menu, which is
/// what keeps the game in continuous motion.
///
/// The set is built on one rule: **every powerup answers a pressure the game
/// actually applies.** Taps are rationed, so [blast]. The clock runs, so
/// [sprint]. The fog hides the route, so [scent]. Anchors wall you off, so
/// [dig]. Regrowth closes behind you, so [freeze]. Reach is short, so
/// [radiusPlus]. A powerup that answers nothing is scenery the player learns to
/// walk past.
///
/// `slowfall` used to live here and has been cut. It capped her drift speed,
/// which was a real cost in the version with no clock — but once hunger existed
/// it spent the one resource you are always short of in order to buy patience.
/// It was a trap wearing a reward's colours.
enum PickupKind {
  /// Buys back time *and* taps. The taps matter as much as the seconds: the fog
  /// guarantees some are spent discovering walls, so a tight budget needs a way
  /// to earn them back or it is arbitrary rather than demanding.
  treat,

  /// Regrowth pauses.
  freeze,

  /// A wider reach, so more of the route can be carved from one spot.
  radiusPlus,

  /// She moves faster. The answer to the clock, and the exact inverse of the
  /// powerup it replaces.
  sprint,

  /// Lights the cheapest remaining route through the fog for a few seconds.
  /// Buys knowledge rather than resources — the only one that does.
  scent,

  /// One tap that clears a whole cluster instead of a single hex.
  blast,

  /// One tap that breaks an anchor, permanently. The only thing in the game
  /// that can.
  dig,

  /// One tap that pins an open tile open, permanently. The exact inverse of
  /// [dig], and the answer to cracked ground.
  ///
  /// [freeze] already answers "the field is closing", but it answers it
  /// *temporally* — five seconds, everywhere. A fault does not care: it will
  /// still be there in six. Stake answers the same pressure *structurally* —
  /// forever, in one place — which makes the two complementary rather than
  /// redundant.
  ///
  /// One cell, never a ring. A ring would let a player build a safe highway
  /// across the board, and the whole decision here is the sharpest question the
  /// game can ask: **which single tile must never close?**
  stake;

  bool get isPowerup => this != PickupKind.treat;

  /// Whether this is spent as a single use rather than running for a while.
  ///
  /// [blast], [dig] and [stake] are charges on purpose. As timed effects their
  /// value would scale with how fast the player can tap inside the window,
  /// which makes the strongest thing in the game a test of thumb speed and
  /// hands the most help to whoever needs it least. One use is one decision.
  ///
  /// **Arming is what makes something a charge, not instantaneity.** All three
  /// are spent by a deliberate second tap rather than simply happening.
  bool get isCharge =>
      this == PickupKind.blast ||
      this == PickupKind.dig ||
      this == PickupKind.stake;

  /// How long the effect lasts. Treats and charges are instant, so zero.
  double get duration => switch (this) {
    PickupKind.treat => 0,
    PickupKind.blast => 0,
    PickupKind.dig => 0,
    PickupKind.stake => 0,
    PickupKind.freeze => 5.0,
    PickupKind.radiusPlus => 8.0,
    PickupKind.sprint => 6.0,
    PickupKind.scent => 5.0,
  };

  /// Shown on the HUD when it is picked up or held.
  String get label => switch (this) {
    PickupKind.treat => 'TREAT',
    PickupKind.freeze => 'FREEZE',
    PickupKind.radiusPlus => 'REACH',
    PickupKind.sprint => 'SPRINT',
    PickupKind.scent => 'SCENT',
    PickupKind.blast => 'BLAST',
    PickupKind.dig => 'DIG',
    PickupKind.stake => 'STAKE',
  };

  /// What the player has to do after explicitly arming a charge. Empty for the
  /// rest, which need no instruction because they simply happen.
  String get hint => switch (this) {
    PickupKind.blast => 'BLAST armed — tap a tile in reach',
    PickupKind.dig => 'DIG armed — tap a riveted tile',
    PickupKind.stake => 'STAKE armed — tap an open tile to pin it',
    _ => '',
  };

  /// Pickup copy for charges. A newly collected tool stays safely put away so
  /// an ordinary carving tap can never spend it by surprise.
  String get readyHint => switch (this) {
    PickupKind.blast => 'BLAST ready — tap it above to arm',
    PickupKind.dig => 'DIG ready — tap it above to arm',
    PickupKind.stake => 'STAKE ready — tap it above to arm',
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

/// Powerups currently running, and charges currently held.
///
/// Kept separate from [TuningConfig] on purpose: that holds the player's own
/// settings, and a temporary effect must never write into it — a powerup that
/// expired mid-edit would otherwise leave the tap radius permanently changed.
class ActiveEffects {
  final Map<PickupKind, double> _remaining = {};
  final Map<PickupKind, double> _total = {};
  final Map<PickupKind, int> _charges = {};
  PickupKind? _selectedCharge;

  static const radiusMultiplier = 1.6;

  /// Drift speed multiplier while sprint is running.
  static const sprintMultiplier = 1.65;

  /// How far a blast reaches from the tapped hex, in rings.
  static const blastRadius = 1;

  void grant(PickupKind kind) {
    if (!kind.isPowerup) {
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
    _selectedCharge = null;
  }

  bool isActive(PickupKind kind) => (_remaining[kind] ?? 0) > 0;

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

  double get tapRadiusMultiplier =>
      isActive(PickupKind.radiusPlus) ? radiusMultiplier : 1.0;

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
}
