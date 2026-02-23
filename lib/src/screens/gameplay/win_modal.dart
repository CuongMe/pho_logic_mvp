import 'package:flutter/material.dart';
import '../../utils/animation_helpers.dart';

/// Win modal that displays when player completes all objectives
class WinModal extends StatefulWidget {
  final VoidCallback onRestart;
  final VoidCallback onNextLevel;
  final VoidCallback onHome;
  final int level;

  const WinModal({
    super.key,
    required this.onRestart,
    required this.onNextLevel,
    required this.onHome,
    required this.level,
  });

  @override
  State<WinModal> createState() => _WinModalState();
}

class _WinModalState extends State<WinModal> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = createScaleAnimation(this);
    _scaleAnimation = createScaleCurvedAnimation(_scaleController);
    _scaleController.forward();
  }

  @override
  void dispose() {
    disposeAnimation(_scaleController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Win board image
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: Image.asset(
                    'assets/win_lose/win_board.png',
                    fit: BoxFit.contain,
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Buttons row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _WinButton(
                      label: 'Home',
                      onTap: widget.onHome,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    _WinButton(
                      label: 'Restart',
                      onTap: widget.onRestart,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    _WinButton(
                      label: 'Next',
                      onTap: widget.onNextLevel,
                      color: Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _WinButton({
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
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
