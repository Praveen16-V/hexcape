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

  /// The one free look past the wall, not yet taken.
  ///
  /// Playable, but not [open]: the level detail sheet has to say this is a
  /// single try rather than an unlock, and the run has to end at the offer.
  /// Merging it into [open] would spend the trial silently.
  trial,
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

  /// The one level a free player may try without paying.
  ///
  /// Deliberately the first level of the Pressure band, which is also
  /// [Campaign.guardsFrom]. The offer's central claim is that what follows puts
  /// patrols in her way, and until this existed a player was asked to buy that
  /// claim having never seen a patrol — the mechanic being sold started exactly
  /// one level past the padlock. A trial makes the case by letting them play
  /// it, which is both more honest and more persuasive than a bullet point.
  static const trialLevel = freeThrough + 1;

  /// The most stars a player can hold without buying the game.
  ///
  /// Three per level across the free campaign. Worth stating as a number
  /// because two of the five pets sit above it and a third is one star short of
  /// it: without this, the pet picker quotes a requirement that no amount of
  /// play can reach and reads as a grind rather than as something for sale.
  static const freeStarCeiling = freeThrough * 3;

  static LevelAccess accessTo(
    int level, {
    required int unlocked,
    required bool owned,
    // Defaults to spent, so every caller that does not know about the trial
    // behaves exactly as it did before the trial existed.
    bool trialUsed = true,
  }) {
    // Checked before progress: a level that is both unreached *and* unpaid
    // reports the purchase, because that is the one the player can act on.
    if (level > freeThrough && !owned) {
      // Only once they have actually earned their way to it. Offering the free
      // look to someone still on level three would spend it before it can mean
      // anything, and skips the twenty levels that give it its weight.
      if (level == trialLevel && !trialUsed && level <= unlocked) {
        return LevelAccess.trial;
      }
      return LevelAccess.needsPurchase;
    }
    if (level > unlocked) {
      return LevelAccess.needsProgress;
    }
    return LevelAccess.open;
  }

  static bool canPlay(
    int level, {
    required int unlocked,
    required bool owned,
    bool trialUsed = true,
  }) {
    final access = accessTo(
      level,
      unlocked: unlocked,
      owned: owned,
      trialUsed: trialUsed,
    );
    return access == LevelAccess.open || access == LevelAccess.trial;
  }

  /// How far the reference sheet may reveal.
  ///
  /// It gates its entries on how far the player has got, which for someone
  /// sitting at the paywall would hand them the patrol entry for a mechanic
  /// they have not bought. Clamped to the free band until they have.
  ///
  /// Once the trial has been spent the ceiling rises by exactly that one level.
  /// A player who has just met a patrol has earned the entry explaining it, and
  /// withholding it would be the reference sheet pretending they had not seen
  /// what they plainly have.
  static int revealCeiling({
    required int unlocked,
    required bool owned,
    bool trialUsed = false,
  }) {
    if (owned) {
      return unlocked;
    }
    final ceiling = trialUsed ? trialLevel : freeThrough;
    return unlocked < ceiling ? unlocked : ceiling;
  }
}
