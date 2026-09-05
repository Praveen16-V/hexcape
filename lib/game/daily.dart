import 'level_rules.dart';

/// One board a day, the same board for everyone.
///
/// The game had nothing that asked a player to come back. The campaign is
/// finite, endless is behind the paywall, and once the free twenty were done
/// there was no second session to convert in — which matters more than it
/// sounds, because a premium game is mostly bought on a return visit rather
/// than a first sitting.
///
/// Three decisions carry the whole feature:
///
/// 1. **It is free, always, including the part that is not.** The board is
///    drawn from the *paid* bands, so a player who has not bought the game gets
///    a genuine run at Pressure or Mastery every day. That is a better argument
///    for buying than any sentence on the paywall, and it costs no new content.
/// 2. **It borrows a level's difficulty, not its board.** [DailyChallenge]
///    takes an authored level's rules and overrides only the seed, so the daily
///    is tuned by the same curve the campaign is — no separate balance to keep
///    in step — while never being a board anybody has already solved.
/// 3. **It writes to its own record and nothing else.** A daily clear never
///    touches stars, bests or the unlock chain. Borrowing level 34's rules must
///    not hand out level 34's star.
class DailyChallenge {
  const DailyChallenge({
    required this.date,
    required this.sourceLevel,
    required this.rules,
  });

  /// The UTC day this board belongs to, at midnight.
  final DateTime date;

  /// The authored level whose difficulty this borrows. Shown to the player as a
  /// band name rather than a number — "today is a Mastery board" is useful,
  /// "today is level 47" invites them to go and compare.
  final int sourceLevel;

  /// [sourceLevel]'s rules on the day's own seed.
  final LevelRules rules;

  CampaignBand get band => Campaign.bandOf(sourceLevel);

  /// `YYYY-MM-DD`. The storage key and the identity — sortable, unambiguous,
  /// and independent of the device's locale and time zone formatting.
  String get id => Daily.idFor(date);
}

class Daily {
  Daily._();

  /// Where the daily draws its difficulty from: the paid bands only.
  ///
  /// Starting at [Campaign.foundationEnd] + 1 is the point. A daily pulled from
  /// the free twenty would be a board the player could already reach, which
  /// makes it a chore rather than a look at what they do not have.
  static const firstSource = Campaign.foundationEnd + 1;
  static const lastSource = Campaign.masteryEnd;

  /// Two independent draws from one day number.
  ///
  /// Distinct offsets rather than two calls on the same value, so the level
  /// choice and the board layout cannot correlate — without this, consecutive
  /// days that happen to pick the same level would also get the same board.
  /// The ranges are far enough apart that no real date can collide: day numbers
  /// stay below ~84,000 through the year 2200.
  static const _levelSalt = 0x100000;
  static const _boardSalt = 0x200000;

  /// Midnight UTC on the day [now] falls in.
  ///
  /// UTC on purpose. A local-time daily changes at a different instant for
  /// every player, so "today's board" would not be one board, and a player
  /// crossing a time zone could skip or repeat a day.
  static DateTime today([DateTime? now]) {
    final t = (now ?? DateTime.now()).toUtc();
    return DateTime.utc(t.year, t.month, t.day);
  }

  static String idFor(DateTime date) {
    final d = date.toUtc();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// Whole days since the Unix epoch. The stable integer everything else keys
  /// off, so the same date yields the same board on every device forever.
  static int dayNumber(DateTime date) =>
      date.toUtc().difference(DateTime.utc(1970)).inDays;

  static DailyChallenge forDate(DateTime date) {
    final day = dayNumber(today(date));
    const span = lastSource - firstSource + 1;
    final sourceLevel = firstSource + Campaign.seedFor(_levelSalt + day) % span;
    return DailyChallenge(
      date: today(date),
      sourceLevel: sourceLevel,
      rules: Campaign.rulesFor(
        sourceLevel,
        seed: Campaign.seedFor(_boardSalt + day),
      ),
    );
  }

  /// Whether [a] is the calendar day immediately before [b]. What decides
  /// whether a streak continues or restarts.
  static bool isDayBefore(DateTime a, DateTime b) =>
      dayNumber(b) - dayNumber(a) == 1;
}
