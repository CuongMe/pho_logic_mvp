import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../../game/stages/stage_data.dart'; // For GridRect, StageData
import '../../game/stages/stage_builder.dart'; // For StageBuilder
import '../../game/board/board_game.dart'; // For BoardGame
import '../../game/inventory/inventory_model.dart'; // For InventoryModel
import '../../game/game_state_model.dart'; // For GameStateModel
import '../../game/model/coord.dart'; // For Coord
import '../../game/utils/debug_logger.dart'; // For DebugLogger

/// Board viewport widget - permanent slot where the Flame game board will be placed
/// This widget contains the GameWidget that renders the board using Flame
class BoardViewport extends StatefulWidget {
  /// Rectangle in screen pixels where the board should be rendered
  final Rect rect;
  
  /// GridRect in design coordinates (for debug display)
  final GridRect gridRect;
  
  /// Number of rows in the grid (from stage JSON)
  final int rows;
  
  /// Number of columns in the grid (from stage JSON)
  final int columns;
  
  /// Stage data containing tile definitions, bed types, etc.
  final StageData stageData;
  
  /// Inventory model for power-ups
  final InventoryModel inventory;
  
  /// Game state model for moves and objectives
  final GameStateModel gameState;
  
  /// Callback when no possible moves are detected (to show modal)
  final Future<void> Function()? onNoMovesDetected;

  const BoardViewport({
    super.key,
    required this.rect,
    required this.gridRect,
    required this.rows,
    required this.columns,
    required this.stageData,
    required this.inventory,
    required this.gameState,
    this.onNoMovesDetected,
  });

  @override
  State<BoardViewport> createState() => BoardViewportState();
}

class BoardViewportState extends State<BoardViewport> {
  BoardGame? _game;
  Coord? _hoveredCoord; // Track hovered coord for feedback

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  @override
  void didUpdateWidget(BoardViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Rebuild game if rect size, rows, columns, or stageData changed
    // This handles: stage changes, layout changes, device rotation, safe area changes
    final rectChanged = oldWidget.rect.width != widget.rect.width ||
        oldWidget.rect.height != widget.rect.height;
    final rowsChanged = oldWidget.rows != widget.rows;
    final columnsChanged = oldWidget.columns != widget.columns;
    final stageDataChanged = oldWidget.stageData != widget.stageData;
    
    if (rectChanged || rowsChanged || columnsChanged || stageDataChanged) {
      _initializeGame();
    }
  }

  void _initializeGame() {
    // Build grid model from stage data
    final gridModel = StageBuilder.buildGridModel(widget.stageData);

    // Create the Flame game
    // BoardGame now computes tileSize, gridLeft, gridTop internally from viewport size
    _game = BoardGame(
      rows: widget.rows,
      cols: widget.columns,
      gridModel: gridModel,
      stageData: widget.stageData,
      viewportWidth: widget.rect.width,
      viewportHeight: widget.rect.height,
    );
    
    // Hook up game state tracking
    _setupGameStateTracking();
  }
  
  void _setupGameStateTracking() {
    if (_game == null) return;
    
    // Store reference to game state for swap tracking and objective tracking
    // The callback in BoardGame.onLoad() will handle both particles and objectives
    _game!.setGameStateModel(widget.gameState);
    
    // Set callback for no-moves detection (to show modal)
    _game!.onNoMovesDetected = widget.onNoMovesDetected;
  }

  /// Pause the Flame game
  void pauseGame() {
    _game?.pauseEngine();
  }

  /// Resume the Flame game
  void resumeGame() {
    _game?.resumeEngine();
  }

  /// Convert screen position to board coordinate
  Coord? _screenToCoord(Offset screenPos) {
    if (_game == null) return null;
    
    // Convert screen position to local position within viewport
    final localPos = Offset(
      screenPos.dx - widget.rect.left,
      screenPos.dy - widget.rect.top,
    );
    
    // Convert to board coordinate using game's coord system
    // BoardGame has coordToWorld, we need the inverse
    final tileSize = _game!.tileSize;
    final gridLeft = _game!.gridLeft;
    final gridTop = _game!.gridTop;
    
    final col = ((localPos.dx - gridLeft) / tileSize).floor();
    final row = ((localPos.dy - gridTop) / tileSize).floor();
    
    if (row >= 0 && row < widget.rows && col >= 0 && col < widget.columns) {
      return Coord(row, col);
    }
    return null;
  }

  /// Validate if a coord is a valid drop target
  bool _isValidDropTarget(Coord coord) {
    if (_game == null) return false;
    
    final cell = _game!.gridModel.cells[coord.row][coord.col];
    
    // Must be playable (bedId != -1)
    if (cell.bedId == null || cell.bedId == -1) return false;
    
    // Must have an existing tile (tileTypeId != null)
    if (cell.tileTypeId == null) return false;
    
    // Can only replace regular tiles (tileTypeId < 101)
    if (cell.tileTypeId! >= 101) return false;
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_game == null) {
      return Positioned(
        left: widget.rect.left,
        top: widget.rect.top,
        width: widget.rect.width,
        height: widget.rect.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Positioned(
      left: widget.rect.left,
      top: widget.rect.top,
      width: widget.rect.width,
      height: widget.rect.height,
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) {
          return true; // Accept any power type
        },
        onMove: (details) {
          // Update hovered coord for feedback (use board's selection-style highlight)
          final coord = _screenToCoord(details.offset);
          final validCoord = (coord != null && _isValidDropTarget(coord)) ? coord : null;

          if (validCoord != _hoveredCoord) {
            _game?.setDragHoverCoord(validCoord);
            setState(() {
              _hoveredCoord = validCoord; // store only valid coords for drop
            });
          }
        },
        onLeave: (data) {
          _game?.setDragHoverCoord(null);
          setState(() {
            _hoveredCoord = null;
          });
        },
        onAcceptWithDetails: (details) async {
          if (_game == null) return;
          
          // Get drop position (use last hovered coord or center)
          final coord = _hoveredCoord;
          if (coord == null) {
            DebugLogger.warn('Drop accepted but no coord available', category: 'BoardViewport');
            return;
          }
          
          final powerTypeId = details.data;
          
          // Validate target
          if (!_isValidDropTarget(coord)) {
            DebugLogger.warn('Drop target $coord is invalid', category: 'BoardViewport');
            _game?.setDragHoverCoord(null);
            setState(() {
              _hoveredCoord = null;
            });
            return;
          }
          
          // Place special tile
          final success = _game!.controller.placeSpecialAt(coord, powerTypeId);
          
          if (success) {
            // Spend inventory
            final spent = await widget.inventory.spend(powerTypeId, 1);
            if (!spent) {
              DebugLogger.error('Failed to spend power $powerTypeId from inventory', category: 'BoardViewport');
              // Rollback placement
              // Note: In a production system, you might want to rollback here
            } else {
              DebugLogger.log('Placed power $powerTypeId at $coord and spent from inventory', category: 'BoardViewport');
            }
            
            // Sync to update TileComponent sprite
            await _game!.syncFromModel();
          } else {
            DebugLogger.warn('placeSpecialAt failed for coord $coord, powerTypeId $powerTypeId', category: 'BoardViewport');
          }
          
          setState(() {
            _hoveredCoord = null;
          });
          _game?.setDragHoverCoord(null);
        },
        builder: (context, candidateData, rejectedData) {
          return Stack(
            children: [
              ClipRect(
                child: GameWidget(game: _game!),
              ),
            ],
          );
        },
      ),
    );
  }
}

