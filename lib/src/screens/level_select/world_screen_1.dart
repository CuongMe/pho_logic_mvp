import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// Import app-level navigatorKey for global navigation
import '../../app/app.dart';
import '../../game/progress/stage_progress_repository.dart';
import '../../utils/json_helpers.dart';
import 'stage_progress_modal.dart';


class WorldScreen1 extends StatefulWidget {
  const WorldScreen1({super.key});

  @override
  State<WorldScreen1> createState() => _WorldScreen1State();
}

class _WorldScreen1State extends State<WorldScreen1> {
  _WorldScreenData? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final jsonString = await rootBundle.loadString('assets/json_design/world_screen_1.json');
      final jsonData = json.decode(jsonString);
      if (!mounted) return;
      setState(() {
        _data = _WorldScreenData.fromJson(jsonData);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load world screen data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text(_error!)),
      );
    }
    return Scaffold(
      body: _WorldScreenLayout(data: _data!),
    );
  }
}

class _WorldScreenData {
  final int schemaVersion;
  final String screen;
  final double designWidth;
  final double designHeight;
  final String background;
  final List<_WorldElement> elements;

  _WorldScreenData({
    required this.schemaVersion,
    required this.screen,
    required this.designWidth,
    required this.designHeight,
    required this.background,
    required this.elements,
  });

  factory _WorldScreenData.fromJson(Map<String, dynamic> json) {
    return _WorldScreenData(
      schemaVersion: json['schemaVersion'],
      screen: json['screen'],
      designWidth: json.getDouble('designWidth'),
      designHeight: json.getDouble('designHeight'),
      background: json['background'],
      elements: (json['elements'] as List)
          .map((e) => _WorldElement.fromJson(e))
          .toList(),
    );
  }
}

class _WorldElement {
  final String type;
  final String id;
  final String file;
  final Offset position;
  final Size size;
  final String anchor;

  _WorldElement({
    required this.type,
    required this.id,
    required this.file,
    required this.position,
    required this.size,
    required this.anchor,
  });

  factory _WorldElement.fromJson(Map<String, dynamic> json) {
    return _WorldElement(
      type: json['type'],
      id: json['id'],
      file: json['file'],
      position: Offset(
        json.getNestedDouble('position', 'x'),
        json.getNestedDouble('position', 'y'),
      ),
      size: Size(
        json.getNestedDouble('size', 'w'),
        json.getNestedDouble('size', 'h'),
      ),
      anchor: json['anchor'],
    );
  }
}

class _WorldScreenLayout extends StatefulWidget {
  final _WorldScreenData data;
  const _WorldScreenLayout({required this.data});

  @override
  State<_WorldScreenLayout> createState() => _WorldScreenLayoutState();
}

class _WorldScreenLayoutState extends State<_WorldScreenLayout> with TickerProviderStateMixin {
  late AnimationController _bambooController;
  late AnimationController _cloud1Controller;
  late AnimationController _cloud2Controller;
  late AnimationController _cloud3Controller;
  late AnimationController _lanternSlideController;
  final StageProgressRepository _stageProgressRepository =
      StageProgressRepository();
  
  late Animation<double> _bambooSwing;
  late Animation<Offset> _lanternSlide;
  
  // Lantern cycling state - switches in complete sets of 5
  // Set 1: 1-5, Set 2: 6-10, Set 3: 11-15, Set 4: 16-20, Set 5: 21-25
  int _currentLanternStart = 1; // Can be 1, 6, 11, 16, or 21
  int _nextLanternStart = 1; // The next set to display
  bool _isTransitioning = false;
  bool _isProgressLoading = true;
  Map<int, StageResult> _stageProgress = {};

  @override
  void initState() {
    super.initState();
    
    // Bamboo swinging animation (gentle back and forth)
    _bambooController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    
    _bambooSwing = Tween<double>(
      begin: -0.05, // -5 degrees
      end: 0.05,    // +5 degrees
    ).animate(CurvedAnimation(
      parent: _bambooController,
      curve: Curves.easeInOut,
    ));
    
    // Cloud 1 moving animation (slow horizontal movement, wraps around)
    _cloud1Controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    
    // Cloud 2 moving animation (slower, wraps around in opposite direction)
    _cloud2Controller = AnimationController(
      duration: const Duration(seconds: 40),
      vsync: this,
    )..repeat();
    
    // Cloud 3 moving animation (slightly faster, wraps around)
    _cloud3Controller = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    )..repeat();
    
    // Lantern slide animation (slide out bottom, slide in from bottom)
    _lanternSlideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _lanternSlide = Tween<Offset>(
      begin: Offset.zero, // Start at original position
      end: const Offset(0.0, 8.0), // Slide down 8x widget height (far off bottom)
    ).animate(CurvedAnimation(
      parent: _lanternSlideController,
      curve: Curves.easeInOut,
    ));

    _loadStageProgress(markLoading: true);
  }

  @override
  void dispose() {
    _bambooController.dispose();
    _cloud1Controller.dispose();
    _cloud2Controller.dispose();
    _cloud3Controller.dispose();
    _lanternSlideController.dispose();
    super.dispose();
  }
  
  /// Animate lantern transition when switching sets (slide out bottom, slide in from bottom)
  void _switchLanternSet(int newStart) {
    if (_isTransitioning) return; // Prevent multiple transitions at once
    
    setState(() {
      _isTransitioning = true;
      _nextLanternStart = newStart;
    });
    
    // Slide current lanterns down and off screen
    _lanternSlideController.forward().then((_) {
      // Switch to new lantern set
      setState(() {
        _currentLanternStart = _nextLanternStart;
      });
      
      // Reset to start position (new lanterns start below screen)
      _lanternSlideController.value = 1.0; // Start at bottom
      
      // Slide new lanterns up into place
      _lanternSlideController.reverse().then((_) {
        setState(() {
          _isTransitioning = false;
        });
      });
    });
  }

  Future<void> _loadStageProgress({bool markLoading = false}) async {
    if (markLoading && mounted) {
      setState(() {
        _isProgressLoading = true;
      });
    }

    final progress = await _stageProgressRepository.loadProgress();
    if (!mounted) return;

    setState(() {
      _stageProgress = progress;
      _isProgressLoading = false;
    });
  }

  Future<void> _showProgressModal() async {
    await _loadStageProgress();
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StageProgressModal(
        progressByStage: _stageProgress,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildProgressAccessButton() {
    final completedCount = _stageProgress.length;
    final countText = completedCount > 99 ? '99+' : '$completedCount';

    return _AnimatedButton(
      onTap: _showProgressModal,
      child: SizedBox(
        width: 74,
        height: 74,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD38A3A), Color(0xFF8D4E1E)],
                  ),
                  border: Border.all(
                    color: const Color(0xFFE7B272),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFB66B2D), Color(0xFF6E3E1A)],
                    ),
                    border: Border.all(
                      color: const Color(0xFF7B461B),
                      width: 1.2,
                    ),
                  ),
                  child: Center(
                    child: _isProgressLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Color(0xFFFFE9C8),
                            ),
                          )
                        : const Icon(
                            Icons.fact_check_rounded,
                            size: 34,
                            color: Color(0xFFFFE9C8),
                          ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            if (!_isProgressLoading && completedCount > 0)
              Positioned(
                right: -7,
                top: -7,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC63D2B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFFE5BF),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    countText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final usableWidth = screenSize.width - padding.left - padding.right;
    // Use usable height (exclude top/bottom system UI) for vertical scaling/centering
    final usableHeight = screenSize.height - padding.top - padding.bottom;
    final scaleX = usableWidth / widget.data.designWidth;
    final scaleY = usableHeight / widget.data.designHeight;
    var scale = scaleX < scaleY ? scaleX : scaleY;
    if (kIsWeb && scale > 1.0) {
      scale = 1.0;
    }
    final xOffset =
        padding.left + (usableWidth - widget.data.designWidth * scale) / 2;
    // Center within the safe area vertically and keep top padding
    final yOffset =
        padding.top + (usableHeight - widget.data.designHeight * scale) / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Image.asset(
            widget.data.background,
            fit: BoxFit.cover,
          ),
        ),
        ...widget.data.elements.map((element) => _buildElement(element, scale, xOffset, yOffset, screenSize.width)),
      ],
    );
  }
  
  /// Build a cloud with wrap-around animation and vertical bob
  Widget _buildCloud({
    required AnimationController controller,
    required Widget child,
    required double screenW,
    required double baseLeft,
    required double cloudW,
    required bool reverse,
  }) {
    const margin = 80.0;
    final travel = screenW + cloudW + margin * 2; // total wrap distance

    // Calculate initial position offset so cloud starts at its JSON-defined position (baseLeft)
    // When controller.value = 0, we want x = baseLeft
    // The animation normally starts at x = -cloudW - margin
    // So we need: baseLeft = -cloudW - margin + initialPos
    // Therefore: initialPos = baseLeft + cloudW + margin
    // Wrap it to travel range: initialPos = (baseLeft + cloudW + margin) % travel
    final initialPos = (baseLeft + cloudW + margin) % travel;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // continuous pixel position from 0..travel
        final t = controller.value * travel;
        
        // Calculate position starting from initialPos
        // For forward: start at initialPos, add t
        // For reverse: start at initialPos, subtract t (which means add travel - t)
        // Both should result in x = baseLeft when t = 0
        final pos = reverse 
            ? (initialPos + travel - t) % travel
            : (initialPos + t) % travel;

        // Calculate absolute x position
        final x = (-cloudW - margin) + pos;

        // Add tiny vertical bob (1-4 px) so clouds aren't perfectly robotic
        final bob = math.sin(controller.value * math.pi * 2) * 2.0; // 2px bob

        // convert absolute-x into a translate relative to Positioned(left: baseLeft)
        // When controller.value = 0, x should equal baseLeft, so offset should be 0
        return Transform.translate(
          offset: Offset(x - baseLeft, bob),
          child: child,
        );
      },
    );
  }

  Widget _buildElement(_WorldElement element, double scale, double xOffset, double yOffset, double screenWidth) {
    Offset actualPosition = _calculatePosition(element, scale, xOffset, yOffset);
    // Clouds are already bigger in JSON, so just use normal scaling
    Size actualSize = Size(element.size.width * scale, element.size.height * scale);

    // JSON-driven progress access button (coordinates/size from world_screen_1.json)
    if (element.id == 'progress') {
      return Positioned(
        left: actualPosition.dx,
        top: actualPosition.dy,
        width: actualSize.width,
        height: actualSize.height,
        child: FittedBox(
          fit: BoxFit.contain,
          child: _buildProgressAccessButton(),
        ),
      );
    }
    
    // Dynamically change lantern files based on current lantern set
    String imageFile = element.file;
    if (element.id.startsWith('stage_')) {
      final stageNum = int.tryParse(element.id.split('_')[1]);
      if (stageNum != null) {
        final lanternNum = _currentLanternStart + (stageNum - 1);
        imageFile = 'assets/world/world_001/lanterns/lantern_$lanternNum.png';
      }
    }
    
    Widget child;
    if (element.type == 'image') {
      child = Image.asset(
        imageFile,
        fit: BoxFit.contain,
      );
    } else if (element.type == 'button') {
      child = _AnimatedButton(
        onTap: () => _handleButtonTap(element.id),
        child: Image.asset(
          imageFile,
          fit: BoxFit.contain,
        ),
      );
    } else {
      child = Container();
    }
    
    // Apply animations based on element ID
    Widget animatedChild = child;
    
    // Apply slide animation to lanterns when switching
    if (element.id.startsWith('stage_')) {
      animatedChild = SlideTransition(
        position: _lanternSlide,
        child: child,
      );
    } else if (element.id == 'bamboo') {
      // Gentle swinging animation for bamboo
      animatedChild = AnimatedBuilder(
        animation: _bambooSwing,
        builder: (context, child) {
          return Transform.rotate(
            angle: _bambooSwing.value,
            alignment: Alignment.bottomCenter, // Rotate around bottom (where it's planted)
            child: child!,
          );
        },
        child: child,
      );
    } else if (element.id == 'cloud_1') {
      // Moving animation for cloud 1 (wraps around screen)
      animatedChild = _buildCloud(
        controller: _cloud1Controller,
        child: child,
        screenW: screenWidth,
        baseLeft: actualPosition.dx,
        cloudW: actualSize.width,
        reverse: false,
      );
    } else if (element.id == 'cloud_2') {
      // Moving animation for cloud 2 (wraps around screen, opposite direction)
      animatedChild = _buildCloud(
        controller: _cloud2Controller,
        child: child,
        screenW: screenWidth,
        baseLeft: actualPosition.dx,
        cloudW: actualSize.width,
        reverse: true, // opposite direction
      );
    } else if (element.id == 'cloud_3') {
      // Moving animation for cloud 3 (wraps around screen)
      animatedChild = _buildCloud(
        controller: _cloud3Controller,
        child: child,
        screenW: screenWidth,
        baseLeft: actualPosition.dx,
        cloudW: actualSize.width,
        reverse: false,
      );
    }
    
    return Positioned(
      left: actualPosition.dx,
      top: actualPosition.dy,
      width: actualSize.width,
      height: actualSize.height,
      child: animatedChild,
    );
  }

  Offset _calculatePosition(_WorldElement element, double scale, double xOffset, double yOffset) {
    // Force center-only anchoring: treat element.position as center
    final x = xOffset + element.position.dx * scale - (element.size.width * scale) / 2;
    final y = yOffset + element.position.dy * scale - (element.size.height * scale) / 2;
    return Offset(x, y);
  }

  /// Handle button tap actions for navigation and stage selection
  void _handleButtonTap(String buttonId) {
    final context = navigatorKey.currentContext ?? _findContext();
    // Navigation logic for each button
    switch (buttonId) {
      case 'home':
        // Go back to menu
        if (context != null) {
          Navigator.of(context).pushNamedAndRemoveUntil('/menu', (route) => false);
        }
        break;
      case 'previous':
        // Cycle to previous set of 5 lanterns with animation
        int newStart = _currentLanternStart - 5;
        if (newStart < 1) {
          newStart = 21; // Wrap to last set (21-25)
        }
        _switchLanternSet(newStart);
        break;
      case 'next':
        // Cycle to next set of 5 lanterns with animation
        int newStart = _currentLanternStart + 5;
        if (newStart > 21) {
          newStart = 1; // Wrap to first set (1-5)
        }
        _switchLanternSet(newStart);
        break;
      case 'stage_1':
      case 'stage_2':
      case 'stage_3':
      case 'stage_4':
      case 'stage_5':
        // Calculate actual level number based on current lantern set
        final stageNum = int.tryParse(buttonId.split('_')[1]);
        if (stageNum != null && context != null) {
          final actualLevel = _currentLanternStart + (stageNum - 1);
          Navigator.of(context).pushNamed('/gameplay/$actualLevel').then((_) {
            if (mounted) {
              _loadStageProgress();
            }
          });
        }
        break;
      default:
        // Decorative or unknown button
        break;
    }
  }

  /// Helper to find a BuildContext if navigatorKey is not set
  BuildContext? _findContext() {
    // This is a fallback; in most apps, use a global navigatorKey
    return null;
  }
}

/// Animated button widget with tap scale animation
class _AnimatedButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _AnimatedButton({
    required this.onTap,
    required this.child,
  });

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        widget.onTap();
      }
    });
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
