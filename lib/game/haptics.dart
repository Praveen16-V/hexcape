import 'package:flutter/services.dart';

/// Every buzz the game makes, behind one switch.
///
/// The calls used to go straight to [HapticFeedback] from wherever they
/// happened, which meant "turn off vibration" had nowhere to live — a player
/// who wants a silent, still game could reach the volume through the debug
/// panel and nothing at all for the buzzing. A gate is only useful if
/// everything goes through it, so nothing in the game may call
/// [HapticFeedback] directly.
///
/// Deliberately static. Haptics are a device-wide fact rather than a property
/// of a level or a run, and threading a setting through the render tree to
/// reach a platform channel would be ceremony around a boolean.
class Haptics {
  Haptics._();

  static bool enabled = true;

  static void light() {
    if (enabled) {
      HapticFeedback.lightImpact();
    }
  }

  static void medium() {
    if (enabled) {
      HapticFeedback.mediumImpact();
    }
  }

  static void heavy() {
    if (enabled) {
      HapticFeedback.heavyImpact();
    }
  }

  static void selection() {
    if (enabled) {
      HapticFeedback.selectionClick();
    }
  }
}
