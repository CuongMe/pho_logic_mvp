import 'package:flutter/material.dart';
import '../../widgets/number_sprite.dart';

/// Sprite-based move counter widget
/// Displays move count using number sprite assets (number_0.png through number_9.png)
/// Shows "X" prefix before the number using x.png asset (e.g., "x20")
/// 
/// Example usage:
/// ```dart
/// SpriteMoveCounter(
///   moves: 22, // Displays "x22"
/// )
/// ```
class SpriteMoveCounter extends StatelessWidget {
  /// Current number of moves remaining
  /// Negative values are clamped to 0
  final int moves;
  
  /// Height of each digit sprite (width will be calculated to maintain aspect ratio)
  final double? digitHeight;
  
  /// Spacing between digits
  final double digitSpacing;
  
  /// Scale factor for X prefix relative to digit height (default: 0.8 = 80% of digit size)
  final double xScale;

  const SpriteMoveCounter({
    super.key,
    required this.moves,
    this.digitHeight,
    this.digitSpacing = 2.0,
    this.xScale = 0.8,
  });

  @override
  Widget build(BuildContext context) {
    // Clamp moves to >= 0 to handle negative values safely
    final clampedMoves = moves.clamp(0, double.infinity).toInt();

    // DESIGN: Let Row take natural width (no FittedBox, no width constraints)
    // Size is controlled purely via digitHeight parameter
    // The parent Positioned widget will clip overflow if needed
    return Row(
      mainAxisSize: MainAxisSize.min, // Natural width based on content
      crossAxisAlignment: CrossAxisAlignment.end, // Align to bottom so X sits lower
      children: [
        _buildXPrefix(),
        if (digitHeight != null)
          NumberSprite(
            number: clampedMoves,
            height: digitHeight!,
            spacing: digitSpacing,
          )
        else
          NumberSprite(
            number: clampedMoves,
            height: 24.0, // Default height
            spacing: digitSpacing,
          ),
      ],
    );
  }

  /// Build the "X" prefix sprite widget
  /// Renders x.png in a square box matching digit height to ensure consistent visual box
  /// Even if x.png is not square, it will be contained within the same visual space as digits
  Widget _buildXPrefix() {
    const assetPath = 'assets/numbers/x.png';

    if (digitHeight != null) {
      // Use a square box matching digit height to ensure consistent visual box
      // This ensures x.png (even if not square) fits within the same space as digits
      // BoxFit.contain will fit the image within this square box
      return SizedBox(
        width: digitHeight! * xScale, // Square box, scaled down
        height: digitHeight! * xScale,
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain, // Fit within the square box, maintaining aspect ratio
          errorBuilder: (context, error, stackTrace) {
            // Fallback if sprite is missing
            return Center(
              child: Text(
                'x',
                style: TextStyle(fontSize: digitHeight! * xScale * 0.8),
              ),
            );
          },
        ),
      );
    } else {
      // Use intrinsic size (will be scaled down in layout if needed)
      return Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback if sprite is missing
          return const Text(
            'x',
            style: TextStyle(fontSize: 20),
          );
        },
      );
    }
  }
}
