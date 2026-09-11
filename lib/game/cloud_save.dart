import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';

import 'level_rules.dart';
import 'progress.dart';

/// The name of the one snapshot this game keeps.
///
/// Play Games allows many per player; one is the right number here. A second
/// would be a second answer to "what has this player done", and [Progress]
/// merges rather than chooses, so there is nothing for the extra slot to hold.
const kSaveName = 'hexcape.progress';

/// Carrying progress between devices, and back after a reinstall.
///
/// **The same three rules [Store] follows, and the first outranks the others:**
///
/// 1. **The game never depends on this.** Play Games is absent on some devices,
///    declined on others, and unreachable offline. Every screen must behave
///    exactly as it did before this file existed. Sync is additive; nothing
///    waits on it, and nothing is ever blocked by it.
/// 2. **It is opt-in and unprompted.** The game has always advertised no
///    accounts and no sign-up, and for anyone who never taps the row in
///    Settings that stays literally true — no sign-in is attempted, no player
///    id is fetched, nothing leaves the phone. That promise is worth more than
///    the fraction of players who would have been auto-signed-in.
/// 3. **The merge is additive, so sync can never cost anything.** Both
///    directions go through [Progress.mergeSnapshot], whose every field only
///    improves. There is no conflict dialog because there is no conflict: two
///    devices that both played offline end up with the union of what they did.
///
/// What this deliberately does *not* sync is the purchase. Play is the record
/// for that and re-queries on every launch; a copy of it in a save file would
/// only be a second answer that can disagree with the first.
class CloudSave extends ChangeNotifier {
  CloudSave(this._progress);

  final Progress _progress;

  bool _signedIn = false;
  bool _busy = false;
  String? _error;
  DateTime? _lastSyncedAt;

  /// Whether the player has connected this device to Play Games.
  bool get signedIn => _signedIn;

  /// A sign-in or a sync is in flight.
  bool get busy => _busy;

  /// The last thing that went wrong, for the settings row to show. Cleared on
  /// the next attempt.
  String? get error => _error;

  /// When the last successful sync finished, or null if none has.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Picks up a session Play Games already has, without starting one.
  ///
  /// Called at launch. `isSignedIn` asks whether the player is *already*
  /// connected — on a device where they have signed in before, Play Games
  /// restores the session itself and this simply notices. It never opens a
  /// sign-in sheet, which is what keeps rule 2 true for everyone else.
  Future<void> start() async {
    try {
      _signedIn = await GamesServices.isSignedIn;
    } catch (e) {
      // A device without Play Games throws here rather than returning false.
      // That is not an error the player needs to see: it is simply a phone
      // this feature does not exist on.
      _signedIn = false;
      notifyListeners();
      return;
    }
    notifyListeners();
    if (_signedIn) {
      await sync();
    }
  }

  /// Connects this device, then immediately reconciles both directions.
  ///
  /// The only path that can open Play Games' own sign-in sheet, and it is
  /// reachable from exactly one place: the row in Settings the player taps.
  Future<void> connect() async {
    if (_busy) {
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await GamesServices.signIn();
      _signedIn = await GamesServices.isSignedIn;
      if (!_signedIn) {
        // Declining is not a failure. Someone who changed their mind should
        // not be shown an error for it.
        _busy = false;
        notifyListeners();
        return;
      }
    } catch (e) {
      _fail('$e');
      return;
    }
    _busy = false;
    await sync();
  }

  /// Pull, merge, push.
  ///
  /// In that order, and all three every time. Pulling first means a device
  /// coming back from a reinstall takes everything the account knows before it
  /// writes anything; pushing afterwards means whatever *this* device did
  /// offline goes up in the same pass. Because the merge only improves fields,
  /// running this twice does nothing the first run did not.
  Future<void> sync() async {
    if (_busy || !_signedIn) {
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await GamesServices.loadGame(name: kSaveName);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          await _progress.mergeSnapshot(decoded);
        }
      }
      await _write();
      _lastSyncedAt = DateTime.now();
    } catch (e) {
      _fail('$e');
      return;
    }
    _busy = false;
    notifyListeners();
  }

  /// Writes the local save up, without reading first.
  ///
  /// For the end of a run, where the pull half is wasted work: nothing can have
  /// changed on another device in the ninety seconds since the last sync that
  /// this device needs before it can record a win. Silent — a failed background
  /// push must never interrupt a player who has just finished a level.
  Future<void> push() async {
    if (_busy || !_signedIn) {
      return;
    }
    try {
      await _write();
      _lastSyncedAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // Deliberately swallowed. The next sync will carry it.
    }
  }

  /// One writer, so the snapshot and the description it is labelled with can
  /// never be assembled two different ways.
  ///
  /// `SaveGame.saveGame` rather than the `GamesServices` facade: the facade
  /// drops the description, and a snapshot list where every entry reads the
  /// same is exactly what Play Games' own quality checklist asks you not to
  /// ship.
  Future<void> _write() => SaveGame.saveGame(
    name: kSaveName,
    data: jsonEncode(_progress.toSnapshot()),
    description:
        '${_progress.completedLevels} of ${Campaign.length} levels, '
        '${_progress.totalStars} stars',
  );

  void _fail(String message) {
    _busy = false;
    _error = message;
    notifyListeners();
  }
}
