import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hexcape/components/glyphs.dart';
import 'package:hexcape/hex/hex_layout.dart';
import 'package:hexcape/theme/palette.dart';

/// Renders the launcher icon from the game's own drawing code.
///
/// The project ships no art at all — every visual is painted at runtime and
/// `assets/` holds nothing but audio — so there was no source image to make an
/// icon from, and the app was still wearing the stock Flutter "F". Rather than
/// draw a lookalike by hand in another tool, this paints the icon out of the
/// same palette and the same [bonePath] the game uses, which means it cannot
/// drift from what the game looks like.
///
/// Not a test. It lives here because `flutter test` is the shortest route to a
/// Flutter binding that can encode a PNG.
///
///     flutter test tool/render_icon.dart
///
/// Writes both the square icon and the adaptive foreground, at every density.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render launcher icons', () async {
    // Android's square/legacy icon, one file per density.
    const legacy = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final entry in legacy.entries) {
      await _write(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        entry.value,
        background: true,
        inset: 0.86,
      );
    }

    // The adaptive foreground is drawn on a 108dp canvas of which only the
    // middle 66dp is guaranteed visible — every launcher masks the rest to its
    // own shape. Hence the much smaller inset: anything bolder gets its corners
    // shaved off on a circular mask.
    const adaptive = {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };
    for (final entry in adaptive.entries) {
      await _write(
        'android/app/src/main/res/drawable-${entry.key}/ic_launcher_foreground.png',
        entry.value,
        background: false,
        inset: 0.56,
      );
    }

    // And a big one for a store listing, which wants 512 square.
    await _write('assets/icon/icon.png', 512, background: true, inset: 0.86);
  });
}

Future<void> _write(
  String path,
  int size, {
  required bool background,
  required double inset,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  _paint(canvas, size.toDouble(), background: background, inset: inset);
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path (${size}px, ${data.lengthInBytes} bytes)');
}

/// A hex tile with the bone on it: the board and the goal, which between them
/// are the whole game.
void _paint(
  ui.Canvas canvas,
  double size, {
  required bool background,
  required double inset,
}) {
  final centre = ui.Offset(size / 2, size / 2);
  final fill = ui.Paint()..style = ui.PaintingStyle.fill;
  final stroke = ui.Paint()..style = ui.PaintingStyle.stroke;

  if (background) {
    fill.color = Palette.background;
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size, size), fill);
  }

  final r = size * 0.5 * inset;
  final depth = ui.Offset(0, r * 0.13);

  // The same skirt-then-top the field draws, so the tile reads as a solid slab
  // rather than a flat outline.
  final hex = HexLayout.pathFromCorners(HexLayout.cornersAt(centre, r));
  fill.color = Palette.plainSide;
  canvas.drawPath(hex.shift(depth), fill);
  fill.color = Palette.plainTop;
  canvas.drawPath(hex, fill);
  stroke
    ..color = Palette.plainEdge
    ..strokeWidth = size * 0.014;
  canvas.drawPath(hex, stroke);

  // The bone, glowing the way the food does on the board.
  fill
    ..color = Palette.goalGlow.withValues(alpha: 0.45)
    ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, size * 0.055);
  canvas.drawCircle(centre, r * 0.52, fill);
  fill.maskFilter = null;

  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(-0.34);
  fill.color = Palette.goalBone;
  canvas.drawPath(bonePath(r * 1.62), fill);
  canvas.restore();
}
