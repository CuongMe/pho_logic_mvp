import 'package:flutter/foundation.dart';

/// Centralized debug logging utility
/// All game debug print statements should use this logger
/// Automatically gated - zero cost in release builds
class DebugLogger {
  /// Global flag to enable/disable all debug logging (only affects debug/profile builds)
  static bool enabled = true;
  
  /// Log a debug message with optional category/tag
  static void log(String message, {String? category}) {
    if (kReleaseMode) return; // No logs in release
    if (!enabled) return;
    
    final prefix = category != null ? '[$category]' : '[Debug]';
    // ignore: avoid_print
    print('$prefix $message');
  }
  
  /// Log a warning message
  static void warn(String message, {String? category}) {
    if (kReleaseMode) return; // No logs in release
    if (!enabled) return;
    
    final prefix = category != null ? '[$category]' : '[WARN]';
    // ignore: avoid_print
    print('$prefix $message');
  }
  
  /// Log an error message
  static void error(String message, {String? category}) {
    if (kReleaseMode) return; // No logs in release (errors too - use crash reporting in production)
    // Errors are always logged in debug/profile, even if debug is disabled
    final prefix = category != null ? '[$category]' : '[ERROR]';
    // ignore: avoid_print
    print('$prefix $message');
  }
  
  // Convenience methods for common categories
  static void boardController(String message) => log(message, category: 'BoardController');
  static void boardGame(String message) => log(message, category: 'BoardGame');
  static void specialActivation(String message) => log(message, category: 'SpecialActivation');
  static void specialVfx(String message) => log(message, category: 'SpecialVfxDispatcher');
  static void swap(String message) => log(message, category: 'Swap');
  static void cascade(String message) => log(message, category: 'Cascade');
  static void specialTile(String message) => log(message, category: 'SpecialTile');
  static void tileComponent(String message) => log(message, category: 'TileComponent');
  static void vfx(String message, {String? vfxType}) => log(message, category: vfxType != null ? 'VFX:$vfxType' : 'VFX');
  static void sequentialClear(String message) => log(message, category: 'SequentialClear');
  static void specialCombo(String message) => log(message, category: 'SpecialCombo');
  static void inventory(String message) => log(message, category: 'Inventory');
}
