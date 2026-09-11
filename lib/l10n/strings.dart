import '../game/level_rules.dart';

/// Every user-facing string in one place (§13.6). Keeping this separate from
/// day one is trivial now and painful to retrofit later.
class Strings {
  Strings._();

  static const appTitle = 'Hexcape';

  // Home screen.
  static const tagline =
      'Carve a path through a hex field. She never stops walking.';
  static const campaign = 'Campaign';

  // HUD.
  static const taps = 'TAPS';
  static const tapsLeft = 'TAPS LEFT';
  static const hunger = 'HUNGER';
  static const time = 'TIME';

  // Results.
  static const levelComplete = 'Dinner!';
  static const tapsUsed = 'Taps used';
  static const par = 'Par';
  static const budget = 'Budget';
  static const bestChain = 'Best chain';
  static const timeTaken = 'Time';
  static const backToMap = 'BACK TO MAP';
  static const paused = 'Paused';
  static const resume = 'Resume';
  static const restart = 'Restart level';
  static const reference = 'How it works';
  static const leaveLevel = 'Leave level';
  static const retry = 'Retry';
  static const newLevel = 'New level';
  static const nextLevel = 'Next level';
  static const level = 'LEVEL';
  static const endless = 'ENDLESS';
  static const freeCampaignDone = 'Twenty levels, all of them cleared';
  static const freeCampaignDoneHint =
      'That is the whole free campaign. What follows gets faster, tighter, '
      'and starts putting patrols in her way.';
  static const seeWhatIsNext = 'See what is next';

  // The daily challenge.
  static const dailyCleared = 'Today\'s board, cleared';
  static const dailyTitle = 'Daily challenge';
  static const dailyDone = 'Cleared today';
  static const dailyPlay = 'PLAY TODAY\'S BOARD';
  static const dailyBlurb =
      'One board a day, the same for everyone, drawn from the full campaign. '
      'No stars — just the streak.';

  // The one free look past the paywall.
  static const trialCleared = 'You held the lane';
  static const trialClearedHint =
      'That was one level of Pressure, with one patrol. There are nineteen '
      'more like it, then twenty of Mastery, then Endless.';
  static const trialTitle = 'Try the first Pressure level';
  static const trialBlurb =
      'One free run at First Patrol — the level right after the free '
      'campaign ends. Play it as many times as you like; leaving for the map '
      'ends the trial.';
  static const trialPlay = 'TRY IT FREE';
  static const trialSpent = 'You have taken your free look at this one.';
  static const campaignDone = 'Every level cleared';
  static const campaignDoneHint =
      'A hundred levels, and she found the bone in all of them. '
      'Endless keeps going from here, and only gets deeper.';
  static const depth = 'DEPTH';
  static const runEnded = 'Run ended';
  static const newRun = 'New run';
  static const deepest = 'Deepest';
  static const reached = 'Reached';
  static const enterEndless = 'Endless';
  static const followCampaign = 'Follow campaign';
  static const resetProgress = 'Reset progress';

  // Failure states.
  static const crushed = 'Boxed in';
  static const crushedHint = 'The field closed in. Keep carving.';
  static const softLocked = 'No way through';
  static const softLockedHint = 'Nothing reaches the bone from here.';
  static const starved = 'Too hungry';
  static const starvedHint = 'She ran out of steam before the bone.';
  static const outOfTaps = 'Out of taps';
  static const outOfTapsHint = 'Not enough left to open a way to the bone.';

  // Onboarding (§12.5) — one idea at a time, shown in the field itself.
  static const hintTapToClear = 'Tap near the dog to clear a tile';
  static const hintDrift = 'She walks to whatever opens up';
  static const hintRegrowth = 'Cleared tiles grow back — keep moving';

  /// She has run out of pocket: standing on the best cell she can reach, with
  /// nothing left to walk to. Naming it is the whole point — without a line
  /// here a correct stop is indistinguishable from a hung game.
  static const hintNowhereToGo = 'She is waiting — open a way beside her';

  // The campaign map (§12.1).
  static const campaignTitle = 'THE LONG TRAIL';
  static const campaignChapters = 'CHAPTERS';
  static const campaignCleared = 'CLEARED';
  static const campaignMastered = 'MASTERED';
  static const campaignStars = 'STARS';
  static const campaignHard = 'ON HARD';
  static const campaignFreeLook = 'ONE FREE LOOK';

  /// What a chapter is *about*, in one line.
  ///
  /// Lives here rather than on [CampaignBand] because the band enum is campaign
  /// rules and this is copy — and because the rules file is the one place in
  /// the game where an edit can silently change what every level is.
  static String bandBlurb(CampaignBand band) => switch (band) {
    CampaignBand.tutorial =>
      'Three guided boards. Tap, drift, and learn what the ground does.',
    CampaignBand.foundation =>
      'The whole game at its own pace — springs, fog, and a tap budget.',
    CampaignBand.pressure =>
      'Patrol light arrives. Timing starts to matter as much as route.',
    CampaignBand.mastery =>
      'Everything taught so far, at full strength, with nothing wasted.',
    CampaignBand.collapse => 'Ground that will not stay where you put it.',
    CampaignBand.vigil => 'Sentries refuse your taps. Wait for the window.',
    CampaignBand.endless =>
      'No last level. The pressure climbs until you stop.',
  };

  /// What a screen reader says for one tile on the map.
  ///
  /// The hundred levels were bare pixels before this: a player using TalkBack
  /// or VoiceOver could reach the continue button and nothing else on the page.
  static String mapTile({
    required int level,
    required String title,
    required String band,
    required int stars,
    required bool played,
    required bool hard,
    required bool frontier,
    required bool lockedByProgress,
    required bool lockedByPurchase,
    required bool trial,
  }) {
    if (level > 100) {
      return 'Endless trail. No last level.';
    }
    final name = 'Level $level, $title. $band.';
    if (lockedByPurchase) {
      return '$name Locked — part of the full game.';
    }
    if (lockedByProgress) {
      return '$name Locked — clear level ${level - 1} first.';
    }
    if (trial) {
      return '$name One free look, not yet taken.';
    }
    if (frontier) {
      return '$name Where you are now.';
    }
    if (!played) {
      return '$name Not played yet.';
    }
    final score = '$stars of 3 stars';
    return hard ? '$name $score, cleared on Hard.' : '$name $score.';
  }

  // Debug panel.
  static const debug = 'DEBUG';
  static const tapRadius = 'Tap radius';
  static const driftMin = 'Drift min';
  static const driftMax = 'Drift max';
  static const momentum = 'Momentum';
  static const regrowDelay = 'Regrow delay';
  static const suffocate = 'Boxed-in grace';
  static const anchorDensity = 'Anchor density';
  static const heavyDensity = 'Heavy density';
  static const revealFactor = 'Sight radius';
  static const budgetMultiplier = 'Tap budget';
  static const hungerPerCell = 'Hunger per cell';
  static const treatSeconds = 'Treat seconds';
  static const treatTaps = 'Treat taps';
  static const treatCount = 'Treats';
  static const powerupCount = 'Powerups';
  static const volume = 'Volume';
  static const juiceScale = 'Shake';
  static const regrowthSound = 'Regrowth sound';
  static const regenerate = 'Regenerate';
  static const replay = 'Replay seed';
  static const zenMode = 'Zen (no regrowth)';
  static const showTruePath = 'Show carved path';
}
