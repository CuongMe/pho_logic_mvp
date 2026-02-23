// Import Flutter material for WidgetBuilder type
import 'package:flutter/material.dart';

// Import screen widgets
import '../screens/menu/menu_screen.dart';
import '../screens/gameplay/gameplay_screen_1.dart';
import '../screens/level_select/world_screen_1.dart';
import '../utils/app_logger.dart';

/// Route constants for the PhoLogic app.
/// These define the navigation paths used throughout the app.
class Routes {
  // Main menu screen
  static const String menu = '/menu';

  // Gameplay screens (numbered for different stages/levels)
  static const String gameplay1 = '/gameplay/1';
  static const String gameplay2 = '/gameplay/2';
  static const String gameplay3 = '/gameplay/3';
  static const String gameplay4 = '/gameplay/4';

  // Level select screens (worlds)
  static const String world1 = '/world/1';

  /// Returns a map of all app routes to their corresponding screen widgets.
  /// This is used by MaterialApp to handle navigation.
  static Map<String, WidgetBuilder> getRoutes() {
    AppLogger.init('Setting up app routes...');
    final routes = <String, WidgetBuilder>{
      // Menu screen - entry point of the app
      menu: (context) {
        AppLogger.navigation('Navigating to MenuScreen');
        return const MenuScreen();
      },

      // World/level select screen for world 1
      world1: (context) {
        AppLogger.navigation('Navigating to WorldScreen1');
        return const WorldScreen1();
      },
    };

    // Generate gameplay routes for all 25 levels dynamically
    for (int i = 1; i <= 25; i++) {
      routes['/gameplay/$i'] = (context) {
        AppLogger.navigation('Navigating to GameplayScreen (Stage $i)');
        return GameplayScreen1(stageId: i);
      };
    }

    AppLogger.init('✅ Routes configured (${routes.length} routes)');
    return routes;
  }
}
