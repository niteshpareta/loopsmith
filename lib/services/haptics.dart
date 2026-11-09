import 'package:flutter/services.dart';

/// Vibration feedback. Every call is a no-op when the player turns it off.
class Haptics {
  bool enabled = true;

  /// A ring turned one notch.
  void tick() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// An opening met a link.
  void bump() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// A ring slipped free.
  void release() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// A ring landed on its peg.
  void land() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// The level was cleared.
  Future<void> success() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await HapticFeedback.heavyImpact();
  }

  /// The tray filled up.
  void fail() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
