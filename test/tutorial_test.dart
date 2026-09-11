import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/entities/dog.dart';
import 'package:hexcape/game/level_rules.dart';
import 'package:hexcape/game/tutorial.dart';
import 'package:hexcape/gen/level_generator.dart';
import 'package:hexcape/hex/hex_coord.dart';
import 'package:hexcape/hex/hex_layout.dart';

const _layout = HexLayout(size: 22, origin: Offset(400, 400));

({GeneratedLevel level, Dog dog}) _levelFor(int n) {
  final rules = Campaign.rulesFor(n);
  final generated = LevelGenerator.generate(
    LevelSpec(
      seed: rules.seed,
      columns: rules.columns,
      rows: rules.rows,
      anchorDensity: rules.anchorDensity,
      heavyDensity: rules.heavyDensity,
      treats: rules.treats,
      powerups: rules.powerups,
    ),
  );
  generated.grid.at(generated.grid.start)!.clear(0);
  return (
    level: generated,
    dog: Dog(
      position: _layout.toPixel(generated.grid.start),
      cell: generated.grid.start,
    ),
  );
}

void main() {
  group('Tutorial scripts', () {
    test('exist for exactly the tutorial band', () {
      for (var n = 1; n <= Campaign.tutorialBand; n++) {
        expect(Tutorial.forLevel(n), isNotNull, reason: 'level $n');
      }
      expect(Tutorial.forLevel(Campaign.tutorialBand + 1), isNull);
      expect(Tutorial.forLevel(30), isNull);
    });

    test('every step resolves a target on its own generated board', () {
      // Targets are named by rule rather than coordinate because the boards are
      // generated. A rule that finds nothing would leave a step pointing at
      // nowhere — or worse, gating on nothing.
      for (var n = 1; n <= Campaign.tutorialBand; n++) {
        final ctx = _levelFor(n);
        final script = Tutorial.forLevel(n)!;
        var guard = 0;
        while (!script.isDone && guard++ < 60 * 120) {
          final step = script.current!;
          if (step.target != TutorialTarget.none) {
            expect(
              script.targetCell(ctx.level.grid, ctx.dog, ctx.level.pickups),
              isNotNull,
              reason: 'level $n cannot resolve ${step.target.name}',
            );
          }
          switch (step.advance) {
            case TutorialAdvance.onContinue:
              script.continueLesson();
            case TutorialAdvance.onTap:
              final target = script.targetCell(
                ctx.level.grid,
                ctx.dog,
                ctx.level.pickups,
              )!;
              ctx.level.grid.at(target)!.clear(0);
              script.onTapped(
                target,
                ctx.level.grid,
                ctx.dog,
                ctx.level.pickups,
                targetBeforeTap: target,
              );
            case TutorialAdvance.onReach:
              ctx.dog.cell = script.targetCell(
                ctx.level.grid,
                ctx.dog,
                ctx.level.pickups,
              )!;
              script.update(0, ctx.level.grid, ctx.dog, ctx.level.pickups);
            case TutorialAdvance.onWatch:
              script.update(
                step.seconds,
                ctx.level.grid,
                ctx.dog,
                ctx.level.pickups,
              );
            case TutorialAdvance.onRegrow:
              script.noteRegrowth();
              script.update(0, ctx.level.grid, ctx.dog, ctx.level.pickups);
          }
        }
        expect(script.isDone, isTrue, reason: 'level $n never finished');
      }
    });

    test('a gate refuses other taps and opens on the right one', () {
      final ctx = _levelFor(1);
      final script = Tutorial.forLevel(1)!;
      expect(script.isGating, isTrue, reason: 'level 1 opens with a gate');

      final target = script.targetCell(
        ctx.level.grid,
        ctx.dog,
        ctx.level.pickups,
      );
      expect(target, isNotNull);

      const elsewhere = HexCoord(99, 99);
      expect(
        script.allowsTap(elsewhere, ctx.level.grid, ctx.dog, ctx.level.pickups),
        isFalse,
      );
      expect(
        script.allowsTap(target!, ctx.level.grid, ctx.dog, ctx.level.pickups),
        isTrue,
      );

      ctx.level.grid.at(target)!.clear(0);
      script.onTapped(
        target,
        ctx.level.grid,
        ctx.dog,
        ctx.level.pickups,
        targetBeforeTap: target,
      );
      expect(
        script.current!.prompt,
        'Open the next tile to make a narrow path',
      );
      expect(
        script.targetCell(ctx.level.grid, ctx.dog, ctx.level.pickups),
        isNot(target),
        reason: 'the next gate must ask for the next tile',
      );
    });

    test(
      'an action waits for the player and Skip always releases the gate',
      () {
        final ctx = _levelFor(1);
        final script = Tutorial.forLevel(1)!;
        script.update(120, ctx.level.grid, ctx.dog, ctx.level.pickups);
        script.continueLesson();
        expect(script.stepNumber, 1);
        expect(script.isGating, isTrue);
        script.skip();
        expect(script.isDone, isTrue);
        expect(
          script.allowsTap(
            const HexCoord(99, 99),
            ctx.level.grid,
            ctx.dog,
            ctx.level.pickups,
          ),
          isTrue,
        );
        expect(script.prompt, isNull);
      },
    );

    test('explanations wait for Continue and reset restores the lesson', () {
      // Level three, because it is the one that still opens on an explanation.
      // Level two now opens by asking the player to carve.
      final ctx = _levelFor(3);
      final script = Tutorial.forLevel(3)!;
      expect(script.current!.advance, TutorialAdvance.onContinue);
      script.update(120, ctx.level.grid, ctx.dog, ctx.level.pickups);
      expect(script.stepNumber, 1, reason: 'time alone never reads a card');
      script.continueLesson();
      expect(script.stepNumber, 2);
      script.skip();
      script.reset();
      expect(script.isDone, isFalse);
      expect(script.stepNumber, 1);
    });

    test('a lesson about motion never runs on a frozen board', () {
      // The defect this group exists to prevent from coming back. "Watch the
      // ground behind her" and "watch the bar" were both `onContinue`, which
      // stops the run — so the regrowth never happened and the clock never
      // moved, and the one thing each line asked for was the one thing it made
      // impossible. Only an explanation may freeze the game.
      for (var n = 1; n <= Campaign.tutorialBand; n++) {
        for (final step in Tutorial.forLevel(n)!.steps) {
          final watching = step.prompt.toLowerCase().contains('watch');
          if (watching) {
            expect(
              step.advance,
              isNot(TutorialAdvance.onContinue),
              reason: 'level $n asks the player to watch a stopped board',
            );
          }
        }
      }
    });

    test('no action beat can outlive the run it interrupts', () {
      // An action step whose target the board does not guarantee is reachable
      // has to give up eventually, or it sits there unsatisfiable while the
      // field closes in around the player it is talking to.
      for (var n = 1; n <= Campaign.tutorialBand; n++) {
        for (final step in Tutorial.forLevel(n)!.steps) {
          if (step.advance == TutorialAdvance.onReach) {
            expect(
              step.releaseAfter,
              isNotNull,
              reason: 'level $n waits forever for her to reach something',
            );
          }
        }
      }
    });
  });

  group('Treat value', () {
    test('falls as the campaign climbs and never rises', () {
      // The leak that made level 60 easy: a flat treat against a shrinking
      // budget gets proportionally stronger exactly where the game should bite.
      var seconds = 99.0;
      var taps = 99;
      for (
        var level = Campaign.tutorialBand + 1;
        level <= Campaign.length;
        level++
      ) {
        final r = Campaign.rulesFor(level);
        expect(
          r.treatSeconds,
          lessThanOrEqualTo(seconds + 1e-9),
          reason: 'treats got more generous at $level',
        );
        expect(
          r.treatTaps,
          lessThanOrEqualTo(taps),
          reason: 'treat taps went up at $level',
        );
        seconds = r.treatSeconds;
        taps = r.treatTaps;
      }
    });

    test('treats can no longer refund most of the late clock', () {
      final r = Campaign.rulesFor(Campaign.length);
      final generated = LevelGenerator.generate(
        LevelSpec(
          seed: r.seed,
          columns: r.columns,
          rows: r.rows,
          anchorDensity: r.anchorDensity,
          heavyDensity: r.heavyDensity,
          treats: r.treats,
          powerups: r.powerups,
        ),
      );
      final clock = generated.par * r.hungerSecondsPerCell;
      final refund = r.treats * r.treatSeconds;
      // It used to be twenty seconds against a thirty-second clock.
      expect(
        refund / clock,
        lessThan(0.35),
        reason:
            'treats still hand back ${(refund / clock * 100).round()}% '
            'of the clock at level ${Campaign.length}',
      );
    });
  });
}
