import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Import the main app widget
import 'src/app/app.dart';
import 'src/audio/sfx_manager.dart';
import 'src/audio/bgm_manager.dart';

/// Entry point of the PhoLogic game application.
/// This function initializes and runs the Flutter app.
void main() async {
  // CRITICAL: Must be FIRST before any async operations or release build will crash!
  // This initializes Flutter bindings required for native platform channels
  WidgetsFlutterBinding.ensureInitialized();

  // Keep portrait lock for native mobile only; web/desktop should be responsive.
  final isNativeMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (isNativeMobile) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Wrap initialization in error handling to prevent crashes
  try {
    // Initialize SFX Manager (preload AudioPools)
    await SfxManager.instance.init();

    // Initialize BGM Manager (background music)
    await BgmManager.instance.init();
  } catch (e, st) {
    // Log error but continue - audio is not critical for app launch
    debugPrint('Audio initialization error: $e\n$st');
  }

  // Run the app with the main PhoLogicApp widget
  runApp(const PhoLogicApp());
}
