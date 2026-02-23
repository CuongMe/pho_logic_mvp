import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pho_logic/src/audio/sfx_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/app.dart';
import '../../app/routes.dart';
import '../../game/inventory/inventory_model.dart';
import '../../utils/app_logger.dart';
import '../../utils/free_boost_cooldown.dart';
import '../../widgets/styled_button.dart';

/// Pause screen widget - universal UI overlay
/// Shows a dimmed background with a scroll panel containing pause menu buttons
class PauseScreen extends StatefulWidget {
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onClose; // Callback to close the overlay/dialog
  final InventoryModel inventory;

  const PauseScreen({
    super.key,
    required this.onResume,
    required this.onRestart,
    required this.onClose,
    required this.inventory,
  });

  @override
  State<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends State<PauseScreen> {
  bool _isClaimingFreeBoost = false;
  static const String _desktopBoostPrefKey = 'has_claimed_desktop_free_boost';
  static const String _webBoostPrefKey = 'has_claimed_web_free_boost';

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dimmed background overlay (no tap-to-resume - prevent accidental resumes)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.7),
            ),
          ),

          // Scroll panel with buttons - centered
          Center(
            child: _buildScrollPanel(context, screenSize),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollPanel(BuildContext context, Size screenSize) {
    // Web/desktop responsive sizing with clamps to avoid oversized panels.
    final widthFactor = kIsWeb ? 0.42 : 0.92;
    final panelWidth =
        (screenSize.width * widthFactor).clamp(320.0, 720.0).toDouble();
    final panelHeight =
        (screenSize.height * 0.85).clamp(420.0, 920.0).toDouble();
    final panelPadding = (panelWidth * 0.1).clamp(26.0, 72.0).toDouble();

    final buttonWidth = panelWidth * 0.62;
    final buttonHeight = buttonWidth * 0.14;
    final buttonFontSize = panelWidth * 0.055;
    final buttonIconSize = panelWidth * 0.085;

    return Container(
      width: panelWidth,
      height: panelHeight,
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('assets/ui/menu/pause_scroll.png'),
          fit: BoxFit.fill,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(panelPadding), // Adaptive padding
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: panelHeight - (panelPadding * 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: panelHeight * 0.02),
                // Resume button
                StyledButton.brown(
                  label: 'Resume',
                  icon: Icons.play_arrow,
                  onPressed: widget.onResume,
                  width: buttonWidth,
                  height: buttonHeight,
                  fontSize: buttonFontSize,
                  iconSize: buttonIconSize,
                ),
                SizedBox(height: panelHeight * 0.025),

                // Free Boost button
                StyledButton.brown(
                  label: 'Free Boost',
                  icon: Icons.card_giftcard,
                  onPressed: () => _handleBoost(context),
                  width: buttonWidth,
                  height: buttonHeight,
                  fontSize: buttonFontSize,
                  iconSize: buttonIconSize,
                ),
                SizedBox(height: panelHeight * 0.025),

                // Restart button
                StyledButton.brown(
                  label: 'Restart',
                  icon: Icons.refresh,
                  onPressed: () => _handleRestart(context),
                  width: buttonWidth,
                  height: buttonHeight,
                  fontSize: buttonFontSize,
                  iconSize: buttonIconSize,
                ),
                SizedBox(height: panelHeight * 0.025),

                // Quit button
                StyledButton.brown(
                  label: 'Quit',
                  icon: Icons.exit_to_app,
                  onPressed: () => _handleQuit(context),
                  width: buttonWidth,
                  height: buttonHeight,
                  fontSize: buttonFontSize,
                  iconSize: buttonIconSize,
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }


  void _handleRestart(BuildContext context) {
    // Restart immediately without confirmation
    widget.onClose(); // Close pause screen using callback
    widget.onRestart(); // Restart the game
  }

  void _handleQuit(BuildContext context) {
    // Quit immediately without confirmation
    widget.onClose(); // Close pause screen using callback
    // Navigate back to menu
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil(
        Routes.menu,
        (route) => false,
      );
    }
  }

  void _handleBoost(BuildContext context) async {
    await _claimFreeBoostWithCooldown(context);
  }

  Future<void> _claimFreeBoostWithCooldown(BuildContext context) async {
    if (_isClaimingFreeBoost) return;

    _isClaimingFreeBoost = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final remainingSeconds = FreeBoostCooldown.remainingSeconds(prefs);
      if (remainingSeconds > 0) {
        if (!context.mounted) return;
        _showFreeBoostCooldownModal(context, remainingSeconds);
        return;
      }

      await _grantWebFreeBoost(context, prefs);
      await FreeBoostCooldown.start(prefs);
    } catch (e) {
      AppLogger.error('Error handling free boost: $e', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      _isClaimingFreeBoost = false;
    }
  }

  /// Native desktop: once-per-install free boost with all 5 power-ups.
  Future<void> _handleDesktopBoost(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasClaimedBoost = prefs.getBool(_desktopBoostPrefKey) ?? false;

      if (hasClaimedBoost) {
        // Already claimed - show modal
        if (!context.mounted) return;
        _showAlreadyClaimedModal(context);
      } else {
        // First time - grant all 5 power-ups
        await _grantDesktopFreeBoost(context, prefs);
      }
    } catch (e) {
      AppLogger.error('Error handling desktop boost: $e', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  /// Web: one-time free boost with 2x of every item, no ads.
  Future<void> _handleWebBoost(BuildContext context) async {
    try {
      await _claimFreeBoostWithCooldown(context);
    } catch (e) {
      AppLogger.error('Error handling web boost: $e', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  /// Grant all 5 power-ups for native desktop (once only).
  Future<void> _grantDesktopFreeBoost(
    BuildContext context,
    SharedPreferences prefs,
  ) async {
    AppLogger.ads('Granting desktop free boost (all 5 items)');

    // Play celebration sound
    SfxManager.instance.play(SfxType.yayCheer);

    // Grant all 5 power-ups (1x each)
    final powerUpIds = [101, 102, 103, 104, 105];
    for (final id in powerUpIds) {
      await widget.inventory.add(id, 1);
    }

    // Mark as claimed
    await prefs.setBool(_desktopBoostPrefKey, true);
    AppLogger.ads('Desktop free boost claimed and saved');

    // Show success modal
    if (!context.mounted) return;
    _showDesktopBoostSuccessModal(context);
  }

  /// Grant all 5 power-ups for web (2x each, once only).
  Future<void> _grantWebFreeBoost(
    BuildContext context,
    SharedPreferences prefs,
  ) async {
    AppLogger.ads('Granting web free boost (all 5 items x2)');

    SfxManager.instance.play(SfxType.yayCheer);

    final powerUpIds = [101, 102, 103, 104, 105];
    for (final id in powerUpIds) {
      await widget.inventory.add(id, 2);
    }

    await prefs.setBool(_webBoostPrefKey, true);
    AppLogger.ads('Web free boost claimed and saved');

    if (!context.mounted) return;
    _showWebBoostSuccessModal(context);
  }

  /// Show modal when web one-time boost has already been claimed.
  void _showWebAlreadyClaimedModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sorry You Have Claim your Boost'),
        content: const Text('This web free boost can only be claimed once.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show success modal for web one-time boost.
  void _showWebBoostSuccessModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.card_giftcard, color: Color(0xFF8B5E3C)),
            SizedBox(width: 8),
            Text('Boost Claimed'),
          ],
        ),
        content: const Text(
          'You received 2x for each booster item.\n'
          'Next free boost is available in 45 seconds.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Awesome'),
          ),
        ],
      ),
    );
  }

  void _showFreeBoostCooldownModal(BuildContext context, int remainingSeconds) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.hourglass_bottom, color: Color(0xFF8B5E3C)),
            SizedBox(width: 8),
            Text('Boost Cooldown'),
          ],
        ),
        content: Text(
          'Please wait $remainingSeconds second${remainingSeconds == 1 ? '' : 's'} '
          'before claiming Free Boost again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show modal for already claimed Windows desktop boost
  void _showAlreadyClaimedModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF6B6B), // Red
                Color(0xFFEE5A6F), // Medium red
                Color(0xFFDD3B49), // Deep red
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_clock, color: Colors.white, size: 30),
                  SizedBox(height: 8),
                  Text(
                    'One-Time Reward',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'This free boost is available only once on this device.\n\n'
                  'You already claimed the starter pack.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFDD3B49),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show success modal for Windows desktop boost
  void _showDesktopBoostSuccessModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2ECC71), // Vibrant green
                Color(0xFF27AE60), // Medium green
                Color(0xFF1E8449), // Deep green
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.card_giftcard, color: Colors.white, size: 30),
                  SizedBox(height: 8),
                  Text(
                    'Starter Pack Claimed!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'You received:\n'
                  '- 1x Party Popper (Horizontal)\n'
                  '- 1x Party Popper (Vertical)\n'
                  '- 1x Sticky Rice Bomb\n'
                  '- 1x Firecracker\n'
                  '- 1x Dragonfly\n\n'
                  'Good luck!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E8449),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Awesome!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

