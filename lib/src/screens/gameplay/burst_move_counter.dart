import 'dart:math';
import 'package:flutter/material.dart';

/// Burst counter widget for displaying moves with animations
/// Features:
/// - Pop scale animation when value changes
/// - Small particle burst behind the number
/// - AnimatedSwitcher for smooth digit transitions
/// - Slow pulse when moves are low
class BurstMoveCounter extends StatefulWidget {
  final int moves;
  final double height;

  /// Optional: label like "Moves"
  final String? label;

  /// Threshold for low moves warning (triggers pulse animation)
  final int lowMovesThreshold;

  const BurstMoveCounter({
    super.key,
    required this.moves,
    this.height = 44,
    this.label,
    this.lowMovesThreshold = 5,
  });

  @override
  State<BurstMoveCounter> createState() => _BurstMoveCounterState();
}

class _BurstMoveCounterState extends State<BurstMoveCounter>
    with TickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _pop;
  late final Animation<double> _burst;
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  int _oldValue = 0;

  @override
  void initState() {
    super.initState();
    _oldValue = widget.moves;

    // Pop and burst animation controller
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _pop = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    _burst = CurvedAnimation(parent: _c, curve: Curves.easeOut);

    // Pulse animation controller for low moves
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initial idle state
    _c.value = 1.0;

    // Start pulse if moves are low
    if (widget.moves <= widget.lowMovesThreshold) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BurstMoveCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Trigger pop animation when value changes
    if (widget.moves != _oldValue) {
      _oldValue = widget.moves;
      _c
        ..stop()
        ..value = 0
        ..forward();
    }

    // Start/stop pulse based on moves threshold
    if (widget.moves <= widget.lowMovesThreshold) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController
          ..stop()
          ..reset();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final isLow = widget.moves <= widget.lowMovesThreshold;
    
    final numberStyle = TextStyle(
      fontSize: h * 0.5,
      fontWeight: FontWeight.w900,
      color: isLow 
          ? const Color(0xFFFF6B6B) // Red when low
          : const Color(0xFFFFE9B5), // Warm highlight when normal
      shadows: const [
        Shadow(blurRadius: 2, offset: Offset(0, 2), color: Colors.black26),
      ],
    );

    return SizedBox(
      height: h,
      child: AnimatedBuilder(
        animation: Listenable.merge([_c, _pulse]),
        builder: (context, child) {
          final popScale = 1.0 + (0.10 * _pop.value); // Pop animation
          final pulseScale = isLow ? _pulse.value : 1.0; // Pulse when low
          final scale = popScale * pulseScale;
          
          return Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Particles behind - moved into builder to rebuild on animation
                IgnorePointer(
                  child: CustomPaint(
                    painter: _BurstPainter(progress: _burst.value),
                    size: Size(h * 2.2, h * 1.2),
                  ),
                ),

                // Badge (wooden/engraved pill style)
                child ?? const SizedBox.shrink(),
              ],
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: h * 0.2, vertical: h * 0.1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(h * 0.35),
            color: const Color(0x55301A0A), // Subtle dark glaze (wooden)
            boxShadow: const [
              BoxShadow(
                blurRadius: 6,
                offset: Offset(0, 3),
                color: Colors.black26,
              ),
            ],
            border: Border.all(
              color: const Color(0x55FFD28A), // Warm wood border
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Label with same wooden theme
              Text(
                widget.label ?? 'Moves:',
                style: TextStyle(
                  fontSize: h * 0.22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFFD28A), // Warm wood color
                  shadows: const [
                    Shadow(blurRadius: 2, offset: Offset(0, 1), color: Colors.black26),
                  ],
                ),
              ),
              SizedBox(width: h * 0.1),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: child,
                ),
                child: Text(
                  '${widget.moves}',
                  key: ValueKey(widget.moves),
                  style: numberStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for burst particle effect
class _BurstPainter extends CustomPainter {
  final double progress;
  _BurstPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final rnd = Random(12345);

    final count = 14;
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * pi * 2 + (rnd.nextDouble() - 0.5) * 0.25;
      // Manual interpolation: start + (end - start) * t
      final radius = 0 + (size.height * 0.6 - 0) * progress;
      final p = center + Offset(cos(angle), sin(angle)) * radius;

      final alpha = (1.0 - progress).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = Colors.white.withAlpha((0.35 * alpha * 255).round())
        ..style = PaintingStyle.fill;

      // Manual interpolation: start + (end - start) * t
      final dotSize = size.height * 0.12 + (0 - size.height * 0.12) * progress;
      canvas.drawCircle(p, dotSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
