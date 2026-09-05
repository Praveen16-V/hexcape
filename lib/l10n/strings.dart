/// Every user-facing string in one place (§13.6). Keeping this separate from
/// day one is trivial now and painful to retrofit later.
class Strings {
  Strings._();

  static const appTitle = 'Hexcape';

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
      'Eighty levels, and she found the bone in all of them. '
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
