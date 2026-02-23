import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/styled_button.dart';

/// Settings screen that displays in a modal
/// Shows language selection (EN/VI) and Rate Me option
class SettingsScreen extends StatefulWidget {
  final VoidCallback onClose;

  const SettingsScreen({
    super.key,
    required this.onClose,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _currentLanguage = 'vi'; // Default to Vietnamese
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLanguage = prefs.getString('language') ?? 'vi';
      _isLoading = false;
    });
  }

  Future<void> _setLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', language);
    setState(() {
      _currentLanguage = language;
    });
  }

  Future<void> _openFeedbackForm() async {
    // Google Form feedback link
    const String feedbackFormUrl = 'https://forms.gle/A3swBUk96i5us2pg8';

    if (await canLaunchUrl(Uri.parse(feedbackFormUrl))) {
      await launchUrl(
        Uri.parse(feedbackFormUrl),
        mode: LaunchMode.externalApplication,
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _currentLanguage == 'vi'
                  ? 'Không thể mở biểu mẫu phản hồi'
                  : 'Could not open feedback form',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dimmed background
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onClose,
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),

          // Settings panel - centered with SafeArea
          Center(
            child: SafeArea(
              child: _buildSettingsPanel(screenSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel(Size screenSize) {
    final panelWidth = (screenSize.width * 1.0).clamp(340.0, 700.0);
    final panelHeight = (screenSize.height * 0.9).clamp(500.0, 900.0);

    // Calculate frame insets to position content inside the scroll artwork
    final leftPadding = (panelWidth * 0.18).clamp(40.0, double.infinity);
    final rightPadding = (panelWidth * 0.18).clamp(40.0, double.infinity);
    final topPadding = (panelHeight * 0.24).clamp(84.0, double.infinity);
    final bottomPadding = (panelHeight * 0.07).clamp(20.0, double.infinity);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // Prevent tap-through to background
      child: Container(
        width: panelWidth,
        height: panelHeight,
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: AssetImage('assets/ui/menu/pause_scroll.png'),
            fit: BoxFit.fill,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            leftPadding,
            topPadding,
            rightPadding,
            bottomPadding,
          ),
          child: Column(
            children: [
              // Title - auto-fit to prevent overflow
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _currentLanguage == 'vi' ? 'Cài Đặt' : 'Settings',
                  style: TextStyle(
                    fontSize: (panelWidth * 0.062).clamp(20.0, 30.0),
                    fontWeight: FontWeight.bold,
                    color: Colors.brown.shade900,
                  ),
                ),
              ),
              SizedBox(height: (panelHeight * 0.015).clamp(6.0, 12.0)),

              // Content - scrollable to prevent overflow
              Flexible(
                fit: FlexFit.tight,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: (panelHeight * 0.02).clamp(6.0, 12.0),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildLanguageSection(panelWidth),
                                SizedBox(height: (panelHeight * 0.02).clamp(6.0, 12.0)),
                                _buildFeedbackButton(panelWidth),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),

              SizedBox(height: (panelHeight * 0.02).clamp(8.0, 16.0)),

              // Close button
              StyledButton.brown(
                label: _currentLanguage == 'vi' ? 'Đóng' : 'Close',
                onPressed: widget.onClose,
                width: panelWidth * 0.45,
                height: (panelWidth * 0.11).clamp(44.0, 56.0),
                fontSize: (panelWidth * 0.045).clamp(15.0, 20.0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSection(double panelWidth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _currentLanguage == 'vi' ? 'Ngôn ngữ' : 'Language',
          style: TextStyle(
            fontSize: (panelWidth * 0.055).clamp(18.0, 24.0),
            fontWeight: FontWeight.bold,
            color: Colors.brown.shade800,
          ),
        ),
        const SizedBox(height: 12),
        // Language toggle with flags on both sides
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Vietnamese Flag
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _currentLanguage == 'vi' ? 1.0 : 0.4,
                  child: const Text(
                    '🇻🇳',
                    style: TextStyle(
                      fontSize: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tiếng Việt',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _currentLanguage == 'vi' ? FontWeight.bold : FontWeight.normal,
                    color: _currentLanguage == 'vi'
                        ? Colors.brown.shade900
                        : Colors.brown.shade400,
                  ),
                ),
              ],
            ),
            
            const SizedBox(width: 20),
            
            // Toggle Switch
            Transform.scale(
              scale: 1.4,
              child: Switch(
                value: _currentLanguage == 'en',
                onChanged: (value) {
                  _setLanguage(value ? 'en' : 'vi');
                },
                activeThumbColor: Colors.brown.shade700,
                activeTrackColor: Colors.brown.shade300,
                inactiveThumbColor: Colors.brown.shade700,
                inactiveTrackColor: Colors.brown.shade300,
              ),
            ),
            
            const SizedBox(width: 20),
            
            // English Flag
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _currentLanguage == 'en' ? 1.0 : 0.4,
                  child: const Text(
                    '🇬🇧',
                    style: TextStyle(
                      fontSize: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'English',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _currentLanguage == 'en' ? FontWeight.bold : FontWeight.normal,
                    color: _currentLanguage == 'en'
                        ? Colors.brown.shade900
                        : Colors.brown.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeedbackButton(double panelWidth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _currentLanguage == 'vi' ? 'Phản Hồi' : 'Feedback',
          style: TextStyle(
            fontSize: (panelWidth * 0.055).clamp(18.0, 24.0),
            fontWeight: FontWeight.bold,
            color: Colors.brown.shade800,
          ),
        ),
        const SizedBox(height: 10),
        StyledButton.brown(
          label: _currentLanguage == 'vi' ? 'Gửi Phản Hồi' : 'Send Feedback',
          icon: Icons.mail_outline,
          onPressed: _openFeedbackForm,
          width: panelWidth * 0.65,
          height: (panelWidth * 0.11).clamp(44.0, 56.0),
          fontSize: (panelWidth * 0.045).clamp(15.0, 20.0),
          iconSize: (panelWidth * 0.05).clamp(18.0, 24.0),
        ),
      ],
    );
  }

}
