import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android shell, which is easy to leave on the Flutter template and never
/// notice — right up until an upload is rejected or a store listing shows a
/// blue "F".
void main() {
  group('Android shell', () {
    test('the launcher icon is ours, at every density', () {
      // The template icons are tiny — the largest is 1443 bytes. Anything we
      // render is several times that, so a size floor catches a revert to the
      // stock Flutter logo without needing to compare pixels.
      const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      for (final density in densities) {
        final icon = File(
          'android/app/src/main/res/mipmap-$density/ic_launcher.png',
        );
        expect(icon.existsSync(), isTrue, reason: '$density icon is missing');
        expect(
          icon.lengthSync(),
          greaterThan(2000),
          reason: '$density icon looks like the stock Flutter one',
        );
      }
    });

    test('there is an adaptive icon, with a foreground at every density', () {
      // Without this pair Android 8+ stamps a white plate behind the icon,
      // which on a dark icon reads as a mistake rather than a design.
      final adaptive = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      );
      expect(adaptive.existsSync(), isTrue);
      final xml = adaptive.readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      expect(xml, contains('ic_launcher_foreground'));

      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(
          File(
            'android/app/src/main/res/drawable-$density/'
            'ic_launcher_foreground.png',
          ).existsSync(),
          isTrue,
          reason: '$density adaptive foreground is missing',
        );
      }
    });

    test('the launch window is the game\'s own dark, not white', () {
      // A dark game on a light-mode device flashed white on every cold start.
      for (final path in [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final xml = File(path).readAsStringSync();
        expect(xml, contains('@color/hexcapeBackground'), reason: path);
        expect(xml, isNot(contains('@android:color/white')), reason: path);
      }
      final colours = File(
        'android/app/src/main/res/values/colors.xml',
      ).readAsStringSync();
      // Palette.background, which the Dart side paints everything else with.
      expect(colours.toUpperCase(), contains('#FF0A0E1A'));
    });

    test('the app is called Hexcape, the way it calls itself', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:label="Hexcape"'));
    });

    test('release signing reads a real keystore when one is provided', () {
      // The template signed release builds with the debug keystore, which Play
      // rejects outright. It still falls back to that so local release builds
      // work, but only when android/key.properties is genuinely absent — and it
      // says so in the build log rather than failing silently at upload time.
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('key.properties'));
      expect(gradle, contains('signingConfigs'));
      expect(
        gradle,
        isNot(contains('TODO: Add your own signing config')),
        reason: 'the template signing block is still in place',
      );
    });

    test('the keystore can never be committed', () {
      final ignore = File('android/.gitignore').readAsStringSync();
      expect(ignore, contains('key.properties'));
      expect(ignore, contains('*.jks'));
      expect(
        File('android/key.properties').existsSync(),
        isFalse,
        reason: 'a file holding a signing password is in the working tree',
      );
    });
  });
}
