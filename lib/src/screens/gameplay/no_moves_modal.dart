import 'package:flutter/material.dart';

/// Simple modal shown when no possible moves are detected and shuffle is about to happen
class NoMovesModal extends StatelessWidget {
  const NoMovesModal({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF2D1B3D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFFD700),
            width: 3,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shuffle,
              color: Color(0xFFFFD700),
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'No Possible Match',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Please Wait',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Color(0xFFFFD700),
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
