import 'package:flutter/material.dart';

/// Creates a scale animation controller for bounce-in effects
/// Used for modal appearances and UI transitions
AnimationController createScaleAnimation(
  TickerProvider vsync, {
  Duration duration = const Duration(milliseconds: 600),
  Curve curve = Curves.elasticOut,
}) {
  final controller = AnimationController(duration: duration, vsync: vsync);
  return controller;
}

/// Creates a shake animation controller for error/lose states
/// Used for lose modals and error feedback
AnimationController createShakeAnimation(
  TickerProvider vsync, {
  Duration duration = const Duration(milliseconds: 500),
  Curve curve = Curves.elasticOut,
}) {
  return AnimationController(duration: duration, vsync: vsync);
}

/// Creates a curved animation for scale effects
Animation<double> createScaleCurvedAnimation(
  AnimationController controller, {
  Curve curve = Curves.elasticOut,
}) {
  return CurvedAnimation(parent: controller, curve: curve);
}

/// Creates a tween animation for shake effects
Animation<double> createShakeTweenAnimation(
  AnimationController controller, {
  double begin = 0.0,
  double end = 1.0,
  Curve curve = Curves.elasticOut,
}) {
  return Tween<double>(begin: begin, end: end).animate(
    CurvedAnimation(parent: controller, curve: curve),
  );
}

/// Standard dispose pattern for animation controllers
void disposeAnimation(AnimationController controller) {
  controller.dispose();
}
