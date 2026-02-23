import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../app/app.dart';
import '../../app/routes.dart';
import '../../game/stages/stage_data.dart'; // For GridRect
import '../../game/stages/stage_loader.dart'; // For StageLoader
import '../../game/inventory/inventory_model.dart';
import '../../game/game_state_model.dart';
import '../../game/progress/stage_progress_repository.dart';
import '../../game/utils/debug_logger.dart';
import '../../utils/json_helpers.dart';
import '../../widgets/number_sprite.dart';
import '../../widgets/atlas_aware_image.dart';
import 'board_viewport.dart';
import 'burst_move_counter.dart';
import 'pause_screen.dart';
import 'no_moves_modal.dart';
import 'win_modal.dart';
import 'lose_modal.dart';

/// Gameplay UI design data loaded from JSON
/// This defines the UI layout, elements, and gridRect positioning
class GameplayUIData {
  final int schemaVersion;
  final String screen;
  final double designWidth;
  final double designHeight;
  final String background;
  final List<GameplayElement> elements;
  final GridRect? gridRect; // Board position and size (same for all stages)

  GameplayUIData({
    required this.schemaVersion,
    required this.screen,
    required this.designWidth,
    required this.designHeight,
    required this.background,
    required this.elements,
    this.gridRect,
  });

  factory GameplayUIData.fromJson(Map<String, dynamic> json) {
    final gridRectJson = json['gridRect'] as Map<String, dynamic>?;
    final gridRect =
        gridRectJson != null ? GridRect.fromJson(gridRectJson) : null;

    return GameplayUIData(
      schemaVersion: json['schemaVersion'],
      screen: json['screen'],
      designWidth: json.getDouble('designWidth'),
      designHeight: json.getDouble('designHeight'),
      background: json['background'],
      elements: (json['elements'] as List)
          .map((e) => GameplayElement.fromJson(e))
          .toList(),
      gridRect: gridRect,
    );
  }
}

/// Individual UI element in the gameplay screen
/// Supports: container, image, button, movesCounter, objective, powerUpSlot types
class GameplayElement {
  final String
      type; // 'container', 'image', 'button', 'movesCounter', 'objective', 'powerUpSlot'
  final String id;
  final String? file; // Optional for movesCounter type
  final Offset position;
  final Size size;
  final String anchor; // 'center' (only center anchoring supported)
  final int?
      objectiveIndex; // For objective type: which objective index to display (0-based)
  final int? tileTypeId; // For powerUpSlot type: which power-up type (101-105)
  final double? badgeDx; // For powerUpSlot type: badge X offset from center
  final double? badgeDy; // For powerUpSlot type: badge Y offset from center

  GameplayElement({
    required this.type,
    required this.id,
    this.file,
    required this.position,
    required this.size,
    required this.anchor,
    this.objectiveIndex,
    this.tileTypeId,
    this.badgeDx,
    this.badgeDy,
  });

  factory GameplayElement.fromJson(Map<String, dynamic> json) {
    // Note: innerOffset in JSON is decorative only (for frame art reference)
    // Board placement is controlled solely by gridRect, not innerOffset
    // innerOffset is ignored and not stored to avoid confusion

    return GameplayElement(
      type: json['type'],
      id: json['id'],
      file: json['file'] as String?,
      position: Offset(
        json.getNestedDouble('position', 'x'),
        json.getNestedDouble('position', 'y'),
      ),
      size: Size(
        json.getNestedDouble('size', 'w'),
        json.getNestedDouble('size', 'h'),
      ),
      anchor: json['anchor'] ?? 'center',
      objectiveIndex: json['objectiveIndex'] as int?,
      tileTypeId: json['tileTypeId'] as int?,
      badgeDx: json.getDoubleOrNull('badgeDx'),
      badgeDy: json.getDoubleOrNull('badgeDy'),
    );
  }
}

/// Main gameplay screen - renders UI from JSON design file
class GameplayScreen1 extends StatefulWidget {
  final int
      stageId; // Stage ID to load (e.g., 1 for stage_001, 2 for stage_002)

  const GameplayScreen1({
    super.key,
    this.stageId = 1, // Default to stage 1 for backward compatibility
  });

  @override
  State<GameplayScreen1> createState() => _GameplayScreen1State();
}

class _GameplayScreen1State extends State<GameplayScreen1> {
  GameplayUIData? _uiData;
  StageData? _stageData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Load gameplay UI design data and stage data from JSON files
  Future<void> _loadData() async {
    try {
      // Load UI data
      final uiJsonString =
          await rootBundle.loadString('assets/json_design/gameplay_1.json');
      final uiJsonData = json.decode(uiJsonString);

      // Load stage data
      final stagePath =
          'assets/stages/stage_${widget.stageId.toString().padLeft(3, '0')}.json';
      final stageData = await StageLoader.loadFromAsset(stagePath);

      if (!mounted) return;
      setState(() {
        _uiData = GameplayUIData.fromJson(uiJsonData);
        _stageData = stageData;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load data: $e';
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
      body: _GameplayLayout(
        uiData: _uiData!,
        stageData: _stageData,
        stageId: widget.stageId,
      ),
    );
  }
}

/// Layout widget that positions gameplay elements based on design coordinates
/// Uses "contain" scaling strategy: scales to fit design area entirely within screen
/// This ensures the entire UI is visible, with letterboxing if needed
class _GameplayLayout extends StatefulWidget {
  final GameplayUIData uiData;
  final StageData? stageData;
  final int stageId;

  const _GameplayLayout({
    required this.uiData,
    this.stageData,
    required this.stageId,
  });

  @override
  State<_GameplayLayout> createState() => _GameplayLayoutState();
}

class _GameplayLayoutState extends State<_GameplayLayout>
    with TickerProviderStateMixin {
  bool _isPaused = false;
  bool _dialogClosingFromButton =
      false; // Track if we're closing from a button action
  final GlobalKey<BoardViewportState> _boardViewportKey =
      GlobalKey<BoardViewportState>();

  // Animation controller for lotus shake
  late AnimationController _lotusShakeController;

  // Inventory model for power-ups
  late InventoryModel _inventory;

  // Game state model for moves and objectives
  GameStateModel? _gameState;
  final StageProgressRepository _stageProgressRepository =
      StageProgressRepository();

  bool _hasShownWinModal = false;
  bool _hasShownLoseModal = false;
  bool _hasRecordedStageResult = false;

  int _countInitialBlockers(StageData stageData) {
    var count = 0;
    for (final row in stageData.tileMap) {
      for (final v in row) {
        if (v == -2) {
          count++;
        }
      }
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    // Initialize shake animation (triggered on tap)
    _lotusShakeController = AnimationController(
      duration: const Duration(milliseconds: 300), // 300ms shake
      vsync: this,
    );

    // Initialize inventory from SharedPreferences or defaults
    _inventory = InventoryModel();
    _inventory.load();

    // Initialize game state if stageData is available
    if (widget.stageData != null) {
      final initialBlockers = _countInitialBlockers(widget.stageData!);
      _gameState = GameStateModel(
        stageData: widget.stageData!,
        initialBlockersRemaining: initialBlockers,
      );
      _gameState!.addListener(_checkGameEndConditions);
    }
  }

  void _checkGameEndConditions() {
    if (_gameState == null) return;

    // Check win condition
    if (_gameState!.isWon && !_hasShownWinModal) {
      _hasShownWinModal = true;
      _recordStageResult(StageResult.cleared);
      // Use addPostFrameCallback to avoid showing dialog during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _showWinModal();
          }
        });
      });
    }

    // Check lose condition
    if (_gameState!.isLost && !_hasShownLoseModal) {
      _hasShownLoseModal = true;
      _recordStageResult(StageResult.lose);
      // Use addPostFrameCallback to avoid showing dialog during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _showLoseModal();
          }
        });
      });
    }
  }

  void _recordStageResult(StageResult result) {
    if (_hasRecordedStageResult) return;
    _hasRecordedStageResult = true;
    unawaited(_stageProgressRepository.saveStageResult(widget.stageId, result));
  }

  void _showWinModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: WinModal(
          level: widget.stageId,
          onRestart: () {
            Navigator.of(context).pop();
            _restartGame();
          },
          onNextLevel: () {
            Navigator.of(context).pop();
            final nextStageId = widget.stageId + 1;
            if (nextStageId <= 20) {
              Navigator.of(context)
                  .pushReplacementNamed('/gameplay/$nextStageId');
            } else {
              // Last level completed, go to world select
              Navigator.of(context).pushReplacementNamed(Routes.world1);
            }
          },
          onHome: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushReplacementNamed(Routes.menu);
          },
        ),
      ),
    );
  }

  void _showLoseModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: LoseModal(
          inventory: _inventory,
          onRestart: () {
            Navigator.of(context).pop();
            _restartGame();
          },
          onHome: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushReplacementNamed(Routes.menu);
          },
        ),
      ),
    );
  }

  /// Show "No Possible Match" modal during shuffle (auto-dismisses after delay)
  Future<void> _showNoMovesModal() async {
    // Show modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: NoMovesModal(),
      ),
    );

    // Wait for shuffle animation (1.5 seconds)
    await Future.delayed(const Duration(milliseconds: 1500));

    // Dismiss modal
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void didUpdateWidget(_GameplayLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Initialize game state if stageData becomes available
    if (_gameState == null && widget.stageData != null) {
      _gameState = GameStateModel(stageData: widget.stageData!);
      _gameState!.addListener(_checkGameEndConditions);
    }
  }

  @override
  void dispose() {
    _gameState?.removeListener(_checkGameEndConditions);
    _lotusShakeController.dispose();
    _inventory.dispose();
    _gameState?.dispose();
    super.dispose();
  }

  void _showPauseScreen() {
    if (_isPaused) {
      DebugLogger.log('Game already paused, ignoring pause button tap',
          category: 'PauseButton');
      return; // Already paused, don't show again
    }

    DebugLogger.log('Pause button tapped - showing pause screen',
        category: 'PauseButton');
    setState(() {
      _isPaused = true;
      _dialogClosingFromButton = false;
    });
    _boardViewportKey.currentState?.pauseGame();

    showDialog(
      context: context,
      barrierDismissible:
          false, // Don't allow tapping outside to dismiss (prevent accidental resumes)
      barrierColor: Colors
          .transparent, // Transparent barrier (we handle dimming in PauseScreen)
      builder: (context) => PopScope(
        canPop:
            false, // Prevent back button from closing (must use resume button)
        child: PauseScreen(
          inventory: _inventory,
          onResume: () {
            _dialogClosingFromButton = true;
            Navigator.of(context).pop(); // Close the dialog/overlay
            _resumeGameInternal();
          },
          onRestart: _restartGame,
          onClose: () {
            _dialogClosingFromButton = true;
            Navigator.of(context).pop(); // Close the dialog/overlay
          },
        ),
      ),
    ).then((_) {
      // When dialog closes, only resume if it wasn't closed by a button action
      // (button actions already handle resuming/closing appropriately)
      if (!_dialogClosingFromButton) {
        _resumeGameInternal();
      }
    });
  }

  void _resumeGameInternal() {
    if (_isPaused) {
      setState(() {
        _isPaused = false;
      });
      _boardViewportKey.currentState?.resumeGame();
    }
  }

  void _restartGame() {
    // Note: Can be called from PauseScreen or Win/Lose modals
    // Navigate to the same stage again (restarts the game)
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      // Use dynamic route for all stages 1-20
      navigator.pushReplacementNamed('/gameplay/${widget.stageId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final usableWidth = screenSize.width - padding.left - padding.right;
    final usableHeight = screenSize.height - padding.top - padding.bottom;

    // SCALING STRATEGY: "contain" - fit entire design area within screen
    // This ensures all UI elements are visible, with letterboxing if aspect ratios differ
    // Scale is the minimum of X and Y scales to maintain aspect ratio
    final scaleX = usableWidth / widget.uiData.designWidth;
    final scaleY = usableHeight / widget.uiData.designHeight;
    var scale = scaleX < scaleY ? scaleX : scaleY;
    if (kIsWeb && scale > 1.0) {
      scale = 1.0;
    }

    // Calculate offsets to center the scaled design area
    final xOffset =
        padding.left + (usableWidth - widget.uiData.designWidth * scale) / 2;
    final yOffset =
        padding.top + (usableHeight - widget.uiData.designHeight * scale) / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Background fills the full screen to avoid visible borders
        Positioned.fill(
          child: Image.asset(widget.uiData.background, fit: BoxFit.cover),
        ),

        // Elements positioned relative to the centered design area
        ...widget.uiData.elements
            .map((e) => _buildElement(e, scale, xOffset, yOffset)),

        // Board viewport: permanent slot where Flame board will be placed
        // Contains GameWidget that renders the board
        if (widget.uiData.gridRect != null && widget.stageData != null)
          if (_gameState != null)
            BoardViewport(
              key: _boardViewportKey,
              rect: getBoardViewportRect(
                  widget.uiData.gridRect!, scale, xOffset, yOffset),
              gridRect: widget.uiData.gridRect!,
              rows: widget.stageData!.rows,
              columns: widget.stageData!.columns,
              stageData: widget.stageData!,
              inventory: _inventory,
              gameState: _gameState!,
              onNoMovesDetected: _showNoMovesModal,
            ),
      ],
    );
  }

  /// Get board viewport rectangle in screen pixels
  /// Converts gridRect from design coordinates to screen coordinates
  /// This is the single source of truth for board positioning
  Rect getBoardViewportRect(
      GridRect gridRect, double scale, double xOffset, double yOffset) {
    final left = xOffset + gridRect.x * scale;
    final top = yOffset + gridRect.y * scale;
    final width = gridRect.w * scale;
    final height = gridRect.h * scale;
    return Rect.fromLTWH(left, top, width, height);
  }

  /// Calculate actual screen position from design coordinates
  /// Uses center-only anchoring (all elements are anchored at center)
  Offset _calculatePosition(
      GameplayElement element, double scale, double xOffset, double yOffset) {
    // Center-only anchoring
    final x = xOffset +
        element.position.dx * scale -
        (element.size.width * scale) / 2;
    final y = yOffset +
        element.position.dy * scale -
        (element.size.height * scale) / 2;
    return Offset(x, y);
  }

  /// Build a single UI element (container, image, button, movesCounter, or objective)
  Widget _buildElement(
      GameplayElement element, double scale, double xOffset, double yOffset) {
    final actualPos = _calculatePosition(element, scale, xOffset, yOffset);
    final actualSize =
        Size(element.size.width * scale, element.size.height * scale);

    Widget child;
    if (element.id == 'lotus') {
      // Special handling for lotus: add wiggle and shake animations
      child = _buildLotusWidget(element, actualSize);
    } else if (element.type == 'image' || element.type == 'container') {
      // Container images should fill their box; other UI images use contain
      if (element.file == null) {
        child = Container();
      } else {
        child = Image.asset(
          element.file!,
          fit: element.type == 'container' ? BoxFit.fill : BoxFit.contain,
        );
      }
    } else if (element.type == 'button') {
      if (element.file == null) {
        child = Container();
      } else {
        child = GestureDetector(
          behavior:
              HitTestBehavior.opaque, // Ensure entire button area is tappable
          onTap: () => _handleTap(element.id),
          child: Image.asset(element.file!, fit: BoxFit.contain),
        );
      }
    } else if (element.type == 'movesCounter') {
      // Burst move counter with animations - reactive to game state
      final gameState = _gameState;
      if (gameState != null) {
        child = ListenableBuilder(
          listenable: gameState,
          builder: (context, _) {
            return BurstMoveCounter(
              moves: gameState.movesRemaining,
              height: actualSize.height,
            );
          },
        );
      } else {
        // Fallback if game state not initialized yet
        child = BurstMoveCounter(
          moves: widget.stageData?.moves ?? 0,
          height: actualSize.height,
        );
      }
    } else if (element.type == 'objective') {
      // Objective display with tile sprite icons
      // If objectiveIndex specified, show single objective; otherwise show all
      if (element.objectiveIndex != null) {
        child = _buildObjectiveWidget(actualSize, element.objectiveIndex!);
      } else {
        child = _buildAllObjectivesWidget(actualSize);
      }
    } else if (element.type == 'powerUpSlot') {
      // Power-up slot with icon, count badge, and drag functionality
      child = _buildPowerUpSlot(element, actualSize, scale);
    } else {
      child = Container();
    }

    return Positioned(
      left: actualPos.dx,
      top: actualPos.dy,
      width: actualSize.width,
      height: actualSize.height,
      child: ClipRect(
        child: child, // Clip any overflow to prevent rendering outside bounds
      ),
    );
  }

  /// Build all objectives widget - displays ALL objectives from stage data
  /// Dynamically creates objective displays for each objective in the stage
  Widget _buildAllObjectivesWidget(Size size) {
    if (widget.stageData == null || widget.stageData!.objectives.isEmpty) {
      return Container();
    }

    final gameState = _gameState;
    if (gameState == null) {
      return Container();
    }

    final objectiveCount = widget.stageData!.objectives.length;

    return ListenableBuilder(
      listenable: gameState,
      builder: (context, _) {
        return Container(
          width: size.width,
          height: size.height,
          padding: EdgeInsets.only(
            left: size.width * 0.27,
            right: size.width * 0.03,
            top: size.height * 0.05,
            bottom: size.height * 0.05,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: List.generate(objectiveCount, (index) {
                final objective = widget.stageData!.objectives[index];

                // Find the tile definition for this objective
                TileDef? tileDef;
                if (objective.tileId != null) {
                  tileDef = widget.stageData!.tiles.firstWhere(
                    (t) => t.id == objective.tileId,
                    orElse: () => widget.stageData!.tiles.first,
                  );
                }

                // Calculate sizes based on number of objectives
                final iconSize = size.height * 0.7;
                final digitHeight = size.height * 0.6;

                // Get progress
                final collected = gameState.getObjectiveProgress(index);
                final remaining =
                    (objective.target - collected).clamp(0, objective.target);
                final remainingString = remaining.toString();
                final digitChars = remainingString.split('');

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tile sprite icon
                    if (tileDef != null)
                      Container(
                        width: iconSize,
                        height: iconSize,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: AtlasAwareImage(
                            assetPath: tileDef.file,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    if (tileDef != null) SizedBox(width: size.width * 0.01),
                    // X prefix sprite
                    SizedBox(
                      width: digitHeight * 0.7,
                      height: digitHeight * 0.7,
                      child: Image.asset(
                        'assets/numbers/x.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(width: size.width * 0.005),
                    // Number sprites
                    ...digitChars.map((char) {
                      return SizedBox(
                        width: digitHeight * 0.6,
                        height: digitHeight,
                        child: Image.asset(
                          'assets/numbers/number_$char.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                char,
                                style: TextStyle(fontSize: digitHeight * 0.6),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ],
                );
              }),
            ),
          ),
        );
      },
    );
  }

  /// Build objective widget with tile sprite icon and sprite-based number counter
  /// Shows objectives from stage data with tile sprites and x.png + number sprites
  /// [index] specifies which objective to display (0-based)
  Widget _buildObjectiveWidget(Size size, int index) {
    if (widget.stageData == null || widget.stageData!.objectives.isEmpty) {
      return Container();
    }

    // Validate index bounds
    if (index < 0 || index >= widget.stageData!.objectives.length) {
      return Container();
    }

    // Get the objective at the specified index
    final objective = widget.stageData!.objectives[index];

    // Find the tile definition for this objective
    TileDef? tileDef;
    if (objective.tileId != null) {
      tileDef = widget.stageData!.tiles.firstWhere(
        (t) => t.id == objective.tileId,
        orElse: () => widget.stageData!.tiles.first,
      );
    }

    // Icon size - use a portion of the height
    final iconSize = size.height * 0.7;
    // Digit height for sprite numbers
    final digitHeight = size.height * 0.6;

    // Use ListenableBuilder to react to game state changes
    final gameState = _gameState;
    if (gameState == null) {
      // Fallback if game state not initialized yet
      return Container();
    }

    return ListenableBuilder(
      listenable: gameState,
      builder: (context, _) {
        // Countdown: show remaining (target - collected), not collected so far
        final collected = gameState.getObjectiveProgress(index);
        final remaining =
            (objective.target - collected).clamp(0, objective.target);

        return Container(
          width: size.width,
          height: size.height,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Tile sprite icon
              if (tileDef != null)
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: AtlasAwareImage(
                      assetPath: tileDef.file,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey,
                          child: const Icon(Icons.image, color: Colors.white),
                        );
                      },
                    ),
                  ),
                ),
              if (tileDef != null) const SizedBox(width: 8),
              // X prefix sprite
              SizedBox(
                width: digitHeight * 0.8,
                height: digitHeight * 0.8,
                child: Image.asset(
                  'assets/numbers/x.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Text(
                        'x',
                        style: TextStyle(fontSize: digitHeight * 0.8 * 0.8),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 4),
              // Number sprites using reusable NumberSprite widget
              NumberSprite(
                key: ValueKey(remaining),
                number: remaining,
                height: digitHeight,
                spacing: 2.0,
                animated: true,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build power-up slot with icon, count badge, and drag functionality
  Widget _buildPowerUpSlot(GameplayElement element, Size size, double scale) {
    if (element.file == null || element.tileTypeId == null) {
      return Container();
    }

    final powerTypeId = element.tileTypeId!;

    // Use ListenableBuilder to react to inventory changes
    return ListenableBuilder(
      listenable: _inventory,
      builder: (context, _) {
        final count = _inventory.getCount(powerTypeId);
        final canUse = _inventory.canUse(powerTypeId);

        // Build sprite icon with shape-following dark tint when count == 0
        // Use ColorFiltered to tint the sprite while preserving transparency
        Widget iconWidget = Image.asset(
          element.file!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: size.width,
              height: size.height,
              color: Colors.grey,
              child: const Icon(Icons.error, color: Colors.red),
            );
          },
        );

        // Apply dark tint that follows sprite silhouette (preserves transparency)
        if (!canUse) {
          iconWidget = ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.55),
              BlendMode
                  .srcATop, // srcATop preserves sprite shape and applies dark tint
            ),
            child: iconWidget,
          );
        }

        // Always show count badge (including "x0") - positioned at bottom right
        final countBadge = Positioned(
          right: 4, // Small offset from right edge
          bottom: -6, // Nudge lower so it doesn't cover the sprite
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: Text(
              'x$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

        Widget slotContent = Stack(
          clipBehavior:
              Clip.none, // allow badge to extend slightly below icon bounds
          children: [
            iconWidget,
            countBadge,
          ],
        );

        // Make draggable if count > 0
        if (canUse) {
          return Draggable<int>(
            data: powerTypeId,
            dragAnchorStrategy: childDragAnchorStrategy,
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.8,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Image.asset(
                    element.file!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: slotContent,
            ),
            child: slotContent,
          );
        } else {
          return slotContent;
        }
      },
    );
  }

  /// Build lotus widget with shake animation
  Widget _buildLotusWidget(GameplayElement element, Size size) {
    if (element.file == null) {
      return Container();
    }

    // Shake animation: quick horizontal movement
    final shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: -8.0, end: 8.0), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 8.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: -8.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(
        parent: _lotusShakeController,
        curve: Curves.easeInOut,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Trigger shake animation on tap
        _lotusShakeController.reset();
        _lotusShakeController.forward();
        DebugLogger.log('Lotus tapped - shake animation triggered',
            category: 'Lotus');
        // Action consequence will be implemented later
      },
      child: AnimatedBuilder(
        animation: _lotusShakeController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(shakeAnimation.value, 0),
            child: Image.asset(
              element.file!,
              fit: BoxFit.contain,
            ),
          );
        },
      ),
    );
  }

  /// Handle tap events for buttons
  void _handleTap(String id) {
    DebugLogger.log('Button tapped: id=$id, isPaused=$_isPaused',
        category: 'Button');
    switch (id) {
      case 'pause':
        // Pause button: show pause screen if game is not already paused
        if (!_isPaused) {
          _showPauseScreen();
        } else {
          DebugLogger.log('Game is already paused, pause button tap ignored',
              category: 'PauseButton');
        }
        // Note: If already paused, do nothing (pause screen is already showing)
        // Player must use the resume button in the pause screen to resume
        break;
      default:
        // Unknown button ID - ignore
        DebugLogger.warn('Unknown button ID: $id', category: 'Button');
        break;
    }
  }
}
