import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// Centralized application logger for the entire project
/// Use this for all logging throughout the app
class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0, // Number of method calls to be displayed
      errorMethodCount: 5, // Number of method calls for errors
      lineLength: 80, // Width of the output
      colors: true, // Colorful log messages
      printEmojis: true, // Print an emoji for each log message
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: kReleaseMode ? Level.warning : Level.trace,
  );

  /// Log debug information
  static void debug(String message, {String? tag}) {
    final msg = tag != null ? '[$tag] $message' : message;
    _logger.d(msg);
  }

  /// Log informational messages
  static void info(String message, {String? tag}) {
    final msg = tag != null ? '[$tag] $message' : message;
    _logger.i(msg);
  }

  /// Log warnings
  static void warning(String message, {String? tag, dynamic error}) {
    final msg = tag != null ? '[$tag] $message' : message;
    _logger.w(msg, error: error);
  }

  /// Log errors
  static void error(String message, {String? tag, dynamic error, StackTrace? stackTrace}) {
    final msg = tag != null ? '[$tag] $message' : message;
    _logger.e(msg, error: error, stackTrace: stackTrace);
  }

  /// Log fatal/critical errors
  static void fatal(String message, {String? tag, dynamic error, StackTrace? stackTrace}) {
    final msg = tag != null ? '[$tag] $message' : message;
    _logger.f(msg, error: error, stackTrace: stackTrace);
  }

  /// Category-specific loggers for easy filtering
  
  // App Lifecycle
  static void lifecycle(String message) => info(message, tag: 'LIFECYCLE');
  
  // Initialization
  static void init(String message) => info(message, tag: 'INIT');
  static void initError(String message, {dynamic error, StackTrace? stackTrace}) => 
      AppLogger.error(message, tag: 'INIT', error: error, stackTrace: stackTrace);
  
  // AdMob
  static void ads(String message) => debug(message, tag: 'ADS');
  static void adsError(String message, {dynamic error, StackTrace? stackTrace}) => 
      AppLogger.error(message, tag: 'ADS', error: error, stackTrace: stackTrace);
  
  // Audio
  static void audio(String message) => debug(message, tag: 'AUDIO');
  static void audioError(String message, {dynamic error, StackTrace? stackTrace}) => 
      AppLogger.error(message, tag: 'AUDIO', error: error, stackTrace: stackTrace);
  
  // Navigation
  static void navigation(String message) => debug(message, tag: 'NAV');
  
  // Game State
  static void game(String message) => debug(message, tag: 'GAME');
  static void gameError(String message, {dynamic error, StackTrace? stackTrace}) => 
      AppLogger.error(message, tag: 'GAME', error: error, stackTrace: stackTrace);
  
  // UI
  static void ui(String message) => debug(message, tag: 'UI');
  
  // Performance
  static void perf(String message) => debug(message, tag: 'PERF');
}
