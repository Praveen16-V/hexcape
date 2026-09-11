import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/entitlements.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/pets.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/l10n/strings.dart';
import 'package:hexcape/ui/home_screen.dart';
import 'package:hexcape/ui/level_detail.dart';
import 'package:hexcape/ui/level_map.dart';
import 'package:hexcape/ui/pet_picker.dart';
import 'package:hexcape/ui/settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every phrase that exists to sell the game.
///
/// Matched case-insensitively as substrings, so a button reading "UNLOCK FULL
/// GAME" is caught by the same entry as the sentence form. The list is the
/// point of the file: when a new line of sales copy is written, it belongs here
/// too, and if it cannot be added without failing a test then it is being shown
/// to someone who has already paid.
const _upsell = [
  'unlock full game',
  'see what is next',
  'one free look',
  'free look',
  'try it free',
  'part of the full game',
  'part of the full campaign',
  'needs the full campaign',
  'twenty levels, all of them cleared',
  'that is the whole free campaign',
  'try the first pressure level',
  'you held the lane',
  // Not sales copy, but purchase copy, and the same rule applies: the launch
  // query already restores the entitlement, so to an owner this is a control
  // that cannot change anything, worded like a transaction.
  'restore purchase',
];

/// Every string the widget tree renders, including semantics labels — a tile
/// painted on a canvas has no Text widget, so the label is the only place its
/// copy exists.
Set<String> _visibleText(WidgetTester tester) {
  final out = <String>{};
  for (final widget in tester.allWidgets) {
    if (widget is Text) {
      final data = widget.data ?? widget.textSpan?.toPlainText();
      if (data != null) out.add(data);
    }
    if (widget is Semantics) {
      final label = widget.properties.label;
      if (label != null) out.add(label);
    }
  }
  void walk(SemanticsNode node) {
    if (node.label.isNotEmpty) out.add(node.label);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // Walked off the semantics tree as well as the widget tree: a map tile is
  // painted on a canvas and has no Text widget of its own, so its label is the
  // only place that copy exists.
  walk(tester.semantics.find(find.byType(MaterialApp)));
  return out;
}

void _expectNoUpsell(WidgetTester tester, String where) {
  final text = _visibleText(tester);
  for (final phrase in _upsell) {
    final offenders = text.where((t) => t.toLowerCase().contains(phrase));
    expect(
      offenders,
      isEmpty,
      reason:
          '$where sells "$phrase" to someone who already bought: '
          '${offenders.join(" | ")}',
    );
  }
}

Future<Progress> _ownedSave([Map<String, Object> extra = const {}]) async {
  SharedPreferences.setMockInitialValues({
    'unlocked': Campaign.length,
    'owns_full': true,
    // Unspent on purpose. The trial is the offer most likely to leak: it is
    // gated on `trialUsed` as well as on ownership, so a save that owns the
    // game *and* still has its free look is the state where a missing
    // ownership check would show.
    'trial_used': false,
    ...extra,
  });
  return Progress.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A player who has bought the game is never sold it again', () {
    testWidgets('the home screen', (tester) async {
      final handle = tester.ensureSemantics();
      final progress = await _ownedSave();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            progress: progress,
            pet: Pets.scout,
            onPlay: () {},
            onCampaign: () {},
            onDaily: () {},
            onPets: () {},
            onSettings: () {},
            onReference: () {},
            onUnlock: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      _expectNoUpsell(tester, 'the home screen');
      handle.dispose();
    });

    testWidgets('the campaign map, every chapter', (tester) async {
      final handle = tester.ensureSemantics();
      final progress = await _ownedSave();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: LevelMap(
              progress: progress,
              onSelect: (_) {},
              onBack: () {},
              showToken: 1,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      _expectNoUpsell(tester, 'the campaign map');
      handle.dispose();
    });

    testWidgets('the level sheet, on both sides of the old paywall', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final progress = await _ownedSave();
      // The last free level, the trial level, and one well past both.
      for (final level in [
        Entitlements.freeThrough,
        Entitlements.trialLevel,
        Campaign.length,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LevelDetail(
                level: level,
                progress: progress,
                inProgress: false,
                onPlay:
                    ({required zen, required difficulty, required restart}) {},
                onUnlock: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        _expectNoUpsell(tester, 'the level $level sheet');
      }
      handle.dispose();
    });

    testWidgets('the pet picker, with pets still unearned', (tester) async {
      final handle = tester.ensureSemantics();
      // Below the free star ceiling, so the pets past it are locked. Locked is
      // correct — they are earned with stars. Telling an owner they "need the
      // full campaign" for one is not.
      final progress = await _ownedSave();
      // A phone, because the picker is a bottom sheet authored for one and
      // overflows the 800x600 the test binding defaults to.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PetPicker(
                stars: 0,
                owned: progress.ownsFullGame,
                selected: Pets.scout.id,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      _expectNoUpsell(tester, 'the pet picker');
      handle.dispose();
    });

    testWidgets('the settings sheet, with billing available', (tester) async {
      final handle = tester.ensureSemantics();
      final progress = await _ownedSave();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsSheet(
                progress: progress,
                onChanged: () {},
                // Non-null: billing works on this device, which is the only
                // state in which the row could be shown at all.
                onRestore: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      _expectNoUpsell(tester, 'the settings sheet');
      handle.dispose();
    });

    testWidgets('but an unowned player can still restore', (tester) async {
      // The other half of the gate, and the more important one: hiding the row
      // from an owner must not hide it from the player it exists for — someone
      // who paid on another device, or whose launch-time restore failed.
      SharedPreferences.setMockInitialValues({
        'unlocked': Entitlements.freeThrough,
        'owns_full': false,
      });
      final progress = await Progress.load();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsSheet(
                progress: progress,
                onChanged: () {},
                onRestore: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Restore purchase'), findsOneWidget);
    });

    testWidgets('and it stays hidden where billing cannot work', (
      tester,
    ) async {
      // Null onRestore means no Play services. Offering a restore that cannot
      // run is worse than not offering one.
      SharedPreferences.setMockInitialValues({'owns_full': false});
      final progress = await Progress.load();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsSheet(
                progress: progress,
                onChanged: () {},
                onRestore: null,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Restore purchase'), findsNothing);
    });

    test('no level ever reports as purchasable to an owner', () {
      // The rule the screens above all read from. Checked directly too, so a
      // failure says whether the bug is in the gate or in one widget that
      // forgot to ask it.
      for (var level = 1; level <= Campaign.length + 5; level++) {
        for (final unlocked in [1, Entitlements.freeThrough, Campaign.length]) {
          for (final trialUsed in [true, false]) {
            final access = Entitlements.accessTo(
              level,
              unlocked: unlocked,
              owned: true,
              trialUsed: trialUsed,
            );
            expect(
              access,
              isNot(LevelAccess.needsPurchase),
              reason: 'level $level offered for sale to an owner',
            );
            expect(
              access,
              isNot(LevelAccess.trial),
              reason: 'level $level offered a free look to an owner',
            );
          }
        }
      }
    });

    test('the result panel copy is reachable only while unowned', () {
      // These four strings are the whole of the post-run sales pitch. They are
      // chosen in `ResultOverlay` behind `!owned`, which a widget test cannot
      // reach without a live game; naming them here is what makes the list in
      // this file complete rather than a sample.
      for (final line in [
        Strings.seeWhatIsNext,
        Strings.freeCampaignDone,
        Strings.freeCampaignDoneHint,
        Strings.trialCleared,
      ]) {
        expect(
          _upsell.any((phrase) => line.toLowerCase().contains(phrase)),
          isTrue,
          reason: '"$line" is sales copy this file does not know about',
        );
      }
    });
  });
}
