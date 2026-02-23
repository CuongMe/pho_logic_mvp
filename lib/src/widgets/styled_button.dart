import 'package:flutter/material.dart';

/// Reusable styled button widget with consistent theming
/// Eliminates duplication of ElevatedButton styling across the app
class StyledButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final double width;
  final double height;
  final Color backgroundColor;
  final Color foregroundColor;
  final double borderRadius;
  final double elevation;
  final double? fontSize;
  final double? iconSize;

  const StyledButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    required this.width,
    required this.height,
    this.backgroundColor = const Color(0xFF5D4037),
    this.foregroundColor = Colors.white,
    this.borderRadius = 14,
    this.elevation = 4,
    this.fontSize,
    this.iconSize,
  });

  /// Brown style button (default - used in pause/settings)
  factory StyledButton.brown({
    required String label,
    IconData? icon,
    required VoidCallback onPressed,
    required double width,
    required double height,
    double? fontSize,
    double? iconSize,
  }) {
    return StyledButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      width: width,
      height: height,
      backgroundColor: Colors.brown.shade700,
      foregroundColor: Colors.white,
      fontSize: fontSize,
      iconSize: iconSize,
    );
  }

  /// Green style button
  factory StyledButton.green({
    required String label,
    IconData? icon,
    required VoidCallback onPressed,
    required double width,
    required double height,
    double? fontSize,
    double? iconSize,
  }) {
    return StyledButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      width: width,
      height: height,
      backgroundColor: Colors.green.shade600,
      foregroundColor: Colors.white,
      fontSize: fontSize,
      iconSize: iconSize,
    );
  }

  /// Red style button
  factory StyledButton.red({
    required String label,
    IconData? icon,
    required VoidCallback onPressed,
    required double width,
    required double height,
    double? fontSize,
    double? iconSize,
  }) {
    return StyledButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      width: width,
      height: height,
      backgroundColor: const Color(0xFFDD3B49),
      foregroundColor: Colors.white,
      fontSize: fontSize,
      iconSize: iconSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: icon != null
          ? ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: iconSize),
              label: Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                elevation: elevation,
              ),
            )
          : ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                elevation: elevation,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}
