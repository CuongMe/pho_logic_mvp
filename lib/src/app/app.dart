
import 'dart:async';

import 'package:flutter/material.dart';
import 'routes.dart';
import '../audio/bgm_manager.dart';
import '../utils/app_logger.dart';

/// Global navigator key for app-wide navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Main application widget for PhoLogic
class PhoLogicApp extends StatelessWidget {
  const PhoLogicApp({super.key});

  @override
  Widget build(BuildContext context) {
    AppLogger.lifecycle('🏗️ Building PhoLogicApp widget');
    return MaterialApp(
      title: 'PhoLogic',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
      ),
      builder: (context, child) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            unawaited(BgmManager.instance.onUserInteraction());
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute: Routes.menu,
      routes: Routes.getRoutes(),
    );
  }
}
