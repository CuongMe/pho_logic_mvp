import 'package:flutter/material.dart';

/// Reusable widget for rendering number sprites
/// Displays individual digits using sprite assets (number_0.png through number_9.png)
/// Can render single digits or multi-digit numbers
class NumberSprite extends StatelessWidget {
  /// The number to display (supports negative, will be clamped to 0)
  final int number;
  
  /// Height of each digit sprite
  final double height;
  
  /// Spacing between digits
  final double spacing;
  
  /// Whether to show animation when number changes
  final bool animated;
  
  const NumberSprite({
    super.key,
    required this.number,
    required this.height,
    this.spacing = 2.0,
    this.animated = false,
  });

  @override
  Widget build(BuildContext context) {
    // Clamp to >= 0
    final clampedNumber = number.clamp(0, double.infinity).toInt();
    final digitChars = clampedNumber.toString().split('');
    
    final digitWidgets = <Widget>[];
    for (int i = 0; i < digitChars.length; i++) {
      if (i > 0) {
        digitWidgets.add(SizedBox(width: spacing));
      }
      digitWidgets.add(_DigitSprite(
        digit: digitChars[i],
        height: height,
      ));
    }
    
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: digitWidgets,
    );
    
    if (animated) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut),
              ),
              child: child,
            ),
          );
        },
        child: row,
      );
    }
    
    return row;
  }
}

/// Internal widget for rendering a single digit sprite
class _DigitSprite extends StatelessWidget {
  final String digit;
  final double height;
  
  const _DigitSprite({
    required this.digit,
    required this.height,
  });
  
  @override
  Widget build(BuildContext context) {
    // Validate character is a digit (0-9)
    if (digit.length != 1) {
      return _buildFallback();
    }
    
    final charCode = digit.codeUnitAt(0);
    if (charCode < 48 || charCode > 57) { // '0' = 48, '9' = 57
      return _buildFallback();
    }
    
    final assetPath = 'assets/numbers/number_$digit.png';
    
    return Image.asset(
      assetPath,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return _buildFallback();
      },
    );
  }
  
  /// Fallback text when sprite is missing or invalid
  Widget _buildFallback() {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          digit,
          style: TextStyle(fontSize: height * 0.8),
        ),
      ),
    );
  }
}
