import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../game/inventory/inventory_model.dart';
import '../../utils/animation_helpers.dart';

/// Lose modal that displays when player runs out of moves
class LoseModal extends StatefulWidget {
  final VoidCallback onRestart;
  final VoidCallback onHome;
  final InventoryModel inventory;

  const LoseModal({
    super.key,
    required this.onRestart,
    required this.onHome,
    required this.inventory,
  });

  @override
  State<LoseModal> createState() => _LoseModalState();
}

class _LoseModalState extends State<LoseModal> with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = createShakeAnimation(this);
    _shakeAnimation = createShakeTweenAnimation(_shakeController);
    _shakeController.forward();
  }

  @override
  void dispose() {
    disposeAnimation(_shakeController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            final shake = math.sin(_shakeAnimation.value * math.pi * 3) * 10 * (1 - _shakeAnimation.value);
            
            return Transform.translate(
              offset: Offset(shake, 0),
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lose board image with fade in
              FadeTransition(
                opacity: _shakeAnimation,
                child: Image.asset(
                  'assets/win_lose/lose_board.png',
                  width: 400,
                  height: 500,
                  fit: BoxFit.contain,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Buttons row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LoseButton(
                    label: 'Home',
                    onTap: widget.onHome,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  _LoseButton(
                    label: 'Retry',
                    onTap: widget.onRestart,
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoseButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _LoseButton({
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  State<_LoseButton> createState() => _LoseButtonState();
}

class _LoseButtonState extends State<_LoseButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
