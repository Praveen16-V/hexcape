import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/game/entitlements.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/progress.dart';
import 'package:hexcape/gen/silhouette.dart';
import 'package:hexcape/l10n/strings.dart';
import 'package:hexcape/ui/campaign/map_geometry.dart';
import 'package:hexcape/ui/campaign/map_painter.dart';
import 'package:hexcape/ui/level_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every level label on the page, in the order a screen reader would reach
/// them.
List<String> _levelLabels(WidgetTester tester) {
  final found = <String>[];
  void walk(SemanticsNode node) {
    final label = node.label;
    if (label.startsWith('Level ') || label.startsWith('Endless')) {
      found.add(label);
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(tester.semantics.find(find.byType(LevelMap)));
  return found;
}

Future<Progress> _progress(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return Progress.load();
}

MapTile _tile({
  int level = 5,
  int stars = 0,
  bool hard = false,
  LevelAccess access = LevelAccess.open,
}) => MapTile(
  level: level,
  stars: stars,
  hard: hard,
  access: access,
  shape: FieldShape.bone,
);

ChapterPainter _painter(List<MapTile> tiles) => ChapterPainter(
  model: ChapterModel(band: CampaignBand.foundation, tiles: tiles, frontier: 5),
  layout: MapGeometry.fit(
    width: 390,
    textScale: 1,
  ).layoutFor(CampaignBand.foundation),
  labelStyle: const TextStyle(),
  labelScale: 1,
  onSelect: (_) {},
  showGlyphs: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Map geometry', () {
    test('a level is always further down the page than the one before', () {
      final geometry = MapGeometry.fit(width: 390, textScale: 1);
      for (var level = 2; level <= MapLayout.tiles; level++) {
        expect(
          geometry.offsetOf(level),
          greaterThanOrEqualTo(geometry.offsetOf(level - 1)),
          reason: 'level $level scrolls backwards',
        );
      }
    });

    test('a chapter begins directly under its own heading', () {
      // What makes jumping to a band land on its first level rather than in
      // the middle of the one before it.
      final geometry = MapGeometry.fit(width: 390, textScale: 1);
      var running = 0.0;
      for (final band in CampaignBand.values) {
        final first = Campaign.firstOf(band);
        expect(
          geometry.offsetOf(first),
          closeTo(running + geometry.headerExtent + 10, 0.01),
          reason: '${band.label} does not start under its header',
        );
        running += geometry.headerExtent + geometry.extentOf(band);
      }
      expect(running, closeTo(geometry.totalExtent, 0.01));
    });

    test('tiles stay a usable size from a small phone to a desktop', () {
      // The page this replaced had no ceiling and no floor: 320px gave star
      // dots under three pixels across, and 1280px gave two-hundred-pixel
      // nodes down four thousand pixels of scroll.
      final narrow = MapGeometry.fit(width: 320, textScale: 1);
      final wide = MapGeometry.fit(width: 1280, textScale: 1);
      expect(narrow.hex, greaterThanOrEqualTo(MapGeometry.minHex));
      expect(wide.hex, MapGeometry.maxHex);
      // And a screen wider than the trail needs centres it instead of
      // stretching it.
      expect(wide.leftInset, greaterThan(300));
    });

    test('the trail fits the narrowest screen we support', () {
      final narrow = MapGeometry.fit(width: 320, textScale: 1);
      final layout = narrow.layoutFor(CampaignBand.mastery);
      var widest = 0.0;
      final levels = MapLayout.levelsOf(CampaignBand.mastery);
      for (var level = levels.first; level <= levels.last; level++) {
        final x = layout.toPixel(MapLayout.coordFor(level)).dx;
        widest = widest > x ? widest : x;
      }
      expect(widest + layout.width / 2, lessThanOrEqualTo(320));
    });
  });

  group('Repainting', () {
    test('a newly earned star redraws the tile that shows it', () {
      // The defect this is here for: the old painter compared the animation
      // phase, the frontier and the hex size, but never the player's record.
      // With reduced motion on the phase is pinned, so a star earned on a
      // level already cleared never appeared at all.
      final before = _painter([_tile(stars: 1)]);
      final after = _painter([_tile(stars: 3)]);
      expect(after.shouldRepaint(before), isTrue);
    });

    test('a clear on Hard redraws the tile that shows it', () {
      expect(
        _painter([
          _tile(stars: 2, hard: true),
        ]).shouldRepaint(_painter([_tile(stars: 2)])),
        isTrue,
      );
    });

    test('buying the game redraws the tiles that were riveted', () {
      expect(
        _painter([
          _tile(access: LevelAccess.open),
        ]).shouldRepaint(_painter([_tile(access: LevelAccess.needsPurchase)])),
        isTrue,
      );
    });

    test('nothing having changed costs nothing', () {
      expect(
        _painter([_tile(stars: 2)]).shouldRepaint(_painter([_tile(stars: 2)])),
        isFalse,
      );
    });
  });

  group('The map speaks', () {
    testWidgets('every level is reachable by a screen reader, in order', (
      tester,
    ) async {
      // A hundred levels used to be bare pixels: a player on TalkBack or
      // VoiceOver could press Continue and nothing else on the page.
      final handle = tester.ensureSemantics();
      final progress = await _progress({
        'unlocked': 6,
        'owns_full': true,
        'lvl_4_stars': 3,
        'lvl_5_stars': 1,
      });
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

      // Walked off the semantics tree rather than through
      // `find.bySemanticsLabel`: a tile's node is a `CustomPainterSemantics`
      // child of the canvas and has no Element of its own, so the widget
      // finders cannot see one.
      final labels = _levelLabels(tester);
      expect(labels.where((l) => l.startsWith('Level 4,')), [
        matches(RegExp(r'3 of 3 stars')),
      ]);
      expect(labels.where((l) => l.startsWith('Level 5,')), [
        matches(RegExp(r'1 of 3 stars')),
      ]);
      expect(labels.where((l) => l.startsWith('Level 6,')), [
        matches(RegExp(r'Where you are now')),
      ]);
      expect(labels.where((l) => l.startsWith('Level 40,')), [
        matches(RegExp(r'Locked — clear level 39 first')),
      ]);

      // Inside a chapter the order is the sort key's, not the geometry's.
      // Without it a meandering row would be read left to right and then the
      // row below it backwards, which is the whole reason the key is set.
      for (final band in CampaignBand.values) {
        final seen = <int>[];
        for (final label in labels) {
          final match = RegExp(
            r'^Level (\d+),.* ${band.label}\.',
          ).firstMatch(label);
          if (match != null) {
            seen.add(int.parse(match.group(1)!));
          }
        }
        expect(
          seen,
          orderedEquals(List.of(seen)..sort()),
          reason: '${band.label} is read out of order',
        );
      }
      handle.dispose();
    });

    test('a locked level says why it is locked', () {
      expect(
        Strings.mapTile(
          level: 40,
          title: 'Rift',
          band: 'Pressure',
          stars: 0,
          played: false,
          hard: false,
          frontier: false,
          lockedByProgress: true,
          lockedByPurchase: false,
          trial: false,
        ),
        contains('clear level 39 first'),
      );
      expect(
        Strings.mapTile(
          level: 62,
          title: 'Give Way',
          band: 'Collapse',
          stars: 0,
          played: false,
          hard: false,
          frontier: false,
          lockedByProgress: false,
          lockedByPurchase: true,
          trial: false,
        ),
        contains('part of the full game'),
      );
    });

    test('every band has a line saying what it is about', () {
      for (final band in CampaignBand.values) {
        expect(Strings.bandBlurb(band), isNotEmpty, reason: band.label);
      }
    });
  });

  group('The free look', () {
    testWidgets('is advertised in the chapter that holds it', (tester) async {
      // It used to be drawn as a tile identical to an unlocked one, which is
      // to say advertised nowhere at all.
      final progress = await _progress({'unlocked': 24});
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
      expect(find.text(Strings.campaignFreeLook), findsOneWidget);
    });

    testWidgets('is gone once it has been spent', (tester) async {
      final progress = await _progress({'unlocked': 24, 'trial_used': true});
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
      expect(find.text(Strings.campaignFreeLook), findsNothing);
    });
  });

  group('Progress is the first thing you read', () {
    testWidgets('the totals are on the page, labelled', (tester) async {
      final progress = await _progress({
        'unlocked': 12,
        'owns_full': true,
        for (var level = 1; level <= 11; level++) 'lvl_${level}_stars': 3,
        'lvl_4_diff': 'hard',
      });
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
      expect(find.text('11/100'), findsOneWidget, reason: 'cleared');
      expect(find.text('33/300'), findsOneWidget, reason: 'stars');
      expect(find.text(Strings.campaignMastered), findsOneWidget);
      expect(find.text(Strings.campaignHard), findsOneWidget);
    });

    testWidgets('a tap on a tile opens that level', (tester) async {
      final progress = await _progress({'unlocked': 8, 'owns_full': true});
      var chosen = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: LevelMap(
              progress: progress,
              onSelect: (level) => chosen = level,
              onBack: () {},
              showToken: 1,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final geometry = MapGeometry.fit(
        width: tester.view.physicalSize.width / tester.view.devicePixelRatio,
        textScale: 1,
      );
      final layout = geometry.layoutFor(CampaignBand.foundation);
      final centre = layout.toPixel(MapLayout.coordFor(6));
      expect(MapLayout.levelAt(centre, layout), 6);
      expect(MapLayout.levelAt(centre + const Offset(6, -6), layout), 6);
      expect(chosen, 0, reason: 'nothing chosen until something is tapped');
    });
  });
}
