import 'package:flutter/foundation.dart';
import 'stages/stage_data.dart';
import 'utils/debug_logger.dart';
import 'model/coord.dart';

/// Model for tracking game state: moves remaining and objective progress
class GameStateModel extends ChangeNotifier {
  final StageData stageData;

  int _movesRemaining;
  final Map<int, int> _objectiveProgress = {}; // objectiveIndex -> current count

  final int _initialBlockers;
  int _blockersRemaining;

  GameStateModel({
    required this.stageData,
    int initialBlockersRemaining = 0,
  })  : _movesRemaining = stageData.moves,
        _initialBlockers = initialBlockersRemaining,
        _blockersRemaining = initialBlockersRemaining {
    // Initialize objective progress
    for (int i = 0; i < stageData.objectives.length; i++) {
      _objectiveProgress[i] = 0;
    }
  }

  /// Get remaining moves
  int get movesRemaining => _movesRemaining;

  /// Get remaining blockers (if any)
  int get blockersRemaining => _blockersRemaining;

  /// Whether this stage requires clearing blockers to win
  bool get requiresBlockerClear => _initialBlockers > 0;

  /// Check if all blockers are cleared
  bool get allBlockersCleared => _blockersRemaining <= 0;

  /// Get objective progress for a specific objective index
  int getObjectiveProgress(int index) {
    return _objectiveProgress[index] ?? 0;
  }

  /// Check if all objectives are completed
  bool get allObjectivesComplete {
    for (int i = 0; i < stageData.objectives.length; i++) {
      final objective = stageData.objectives[i];
      final progress = getObjectiveProgress(i);
      if (progress < objective.target) {
        return false;
      }
    }
    return true;
  }

  /// Check if game is won (all objectives complete and blockers cleared when present)
  bool get isWon =>
      allObjectivesComplete && (!requiresBlockerClear || allBlockersCleared);

  /// Check if game is lost (no moves remaining and win condition not met)
  bool get isLost => _movesRemaining <= 0 && !isWon;
  
  /// Decrement moves (called when a valid swap is made)
  void decrementMoves() {
    if (_movesRemaining > 0) {
      _movesRemaining--;
      DebugLogger.log('Moves decremented: $_movesRemaining remaining', category: 'GameState');
      notifyListeners();
    }
  }

  /// Decrement blockers remaining (called when a blocker is cleared)
  void decrementBlockersRemaining([int count = 1]) {
    if (_blockersRemaining <= 0 || count <= 0) return;
    final nextRemaining = _blockersRemaining - count;
    _blockersRemaining = nextRemaining < 0 ? 0 : nextRemaining;
    DebugLogger.log('Blockers remaining: $_blockersRemaining', category: 'GameState');
    notifyListeners();
  }
  
  /// Process cleared tiles to update objective progress
  /// Called when tiles are cleared (matches, specials, etc.)
  void processClearedTiles(Map<Coord, int> clearedCellsWithTypes) {
    if (clearedCellsWithTypes.isEmpty) {
      DebugLogger.log('processClearedTiles called with empty map', category: 'GameState');
      return;
    }
    
    DebugLogger.log('processClearedTiles: ${clearedCellsWithTypes.length} tiles cleared', category: 'GameState');
    DebugLogger.log('Tile types cleared: ${clearedCellsWithTypes.values.toSet()}', category: 'GameState');
    
    bool updated = false;
    
    for (int i = 0; i < stageData.objectives.length; i++) {
      final objective = stageData.objectives[i];
      
      // Only process "collect" type objectives
      if (objective.type == 'collect' && objective.tileId != null) {
        DebugLogger.log('Checking objective $i: type=collect, tileId=${objective.tileId}, target=${objective.target}', category: 'GameState');
        
        // Count how many of this tile type were cleared
        int count = 0;
        for (final entry in clearedCellsWithTypes.entries) {
          final coord = entry.key;
          final tileTypeId = entry.value;
          if (tileTypeId == objective.tileId) {
            count++;
            DebugLogger.log('Found matching tile at $coord: tileTypeId=$tileTypeId matches objective tileId=${objective.tileId}', category: 'GameState');
          }
        }
        
        if (count > 0) {
          final currentProgress = _objectiveProgress[i] ?? 0;
          final newProgress = (currentProgress + count).clamp(0, objective.target);
          _objectiveProgress[i] = newProgress;
          updated = true;
          DebugLogger.log('Objective $i progress: $currentProgress -> $newProgress (target: ${objective.target}, counted $count tiles)', category: 'GameState');
        } else {
          DebugLogger.log('Objective $i: no matching tiles found in this clear batch', category: 'GameState');
        }
      }
    }
    
    if (updated) {
      notifyListeners();
    } else {
      DebugLogger.log('processClearedTiles: no objectives updated', category: 'GameState');
    }
  }
}
