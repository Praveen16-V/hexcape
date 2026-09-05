import 'level_rules.dart';

/// Why a level cannot be played, when it cannot.
///
/// There used to be one question — `Progress.isUnlocked` — and one answer. With
/// a purchase in the game there are two, and they must not be merged: telling a
/// paying player to finish a level they have already finished, or telling a free
/// player to buy something they have not earned yet, are both worse than saying
/// nothing.
enum LevelAccess {
  open,

  /// Reachable, but the player has not got there yet.
  needsProgress,

  /// Past the free campaign, and not bought.
  needsPurchase,
}

/// What the player is allowed to play.
///
/// Pure on purpose. Billing is asynchronous, fails on some devices and is absent
/// entirely when offline, so the *rule* has to be something that can be reasoned
/// about and tested without any of that — the store's only job is to work out
/// the value of [owned].
class Entitlements {
  const Entitlements._();

  /// The last free level.
  ///
  /// A band boundary rather than a round number. Level 21 opens the Pressure
  /// band and is where patrols arrive, so the free game stops exactly one level
  /// before the game changes character — which is the most honest place to ask,
  /// and the least arbitrary place to stop.
  static const freeThrough = Campaign.foundationEnd;

  static LevelAccess accessTo(
    int level, {
    required int unlocked,
    required bool owned,
  }) {
    // Checked before progress: a level that is both unreached *and* unpaid
    // reports the purchase, because that is the one the player can act on.
    if (level > freeThrough && !owned) {
      return LevelAccess.needsPurchase;
    }
    if (level > unlocked) {
      return LevelAccess.needsProgress;
    }
    return LevelAccess.open;
  }

  static bool canPlay(int level, {required int unlocked, required bool owned}) =>
      accessTo(level, unlocked: unlocked, owned: owned) == LevelAccess.open;

  /// How far the reference sheet may reveal.
  ///
  /// It gates its entries on how far the player has got, which for someone
  /// sitting at the paywall would hand them the patrol entry for a mechanic
  /// they have not bought. Clamped to the free band until they have.
  static int revealCeiling({required int unlocked, required bool owned}) =>
      owned ? unlocked : (unlocked < freeThrough ? unlocked : freeThrough);
}
