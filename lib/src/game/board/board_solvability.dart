import '../model/coord.dart';
import '../model/grid_model.dart';
import '../model/match_result.dart';
import 'special_tile_spawner.dart';

/// Utility class for checking if a match-3 board has possible moves
/// Used by BoardController to detect "no moves" situations
class BoardSolvability {
  /// Check if board has any special tiles (101-105)
  /// Special tiles always provide a valid move (can swap with any adjacent tile)
  static bool hasAnySpecialTile(GridModel gridModel) {
    final rows = gridModel.cells.length;
    final cols = gridModel.cells.isEmpty ? 0 : gridModel.cells[0].length;
    
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final cell = gridModel.cells[row][col];
        if (cell.tileTypeId != null && _isSpecial(cell.tileTypeId!)) {
          return true;
        }
      }
    }
    return false;
  }
  
  /// Check if board has any possible move (line match, 2x2 block, or special tile)
  /// Returns true if at least one valid swap exists
  static bool hasPossibleMove({
    required GridModel gridModel,
    required SpecialTileSpawner tileSpawner,
    required bool Function(Coord, Coord) canSwap,
    required MatchResult Function() detectMatches,
  }) {
    final rows = gridModel.cells.length;
    final cols = gridModel.cells.isEmpty ? 0 : gridModel.cells[0].length;
    
    // Check all adjacent pairs
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final coord = Coord(row, col);
        
        // Skip void cells
        final cell = gridModel.cells[row][col];
        if (cell.bedId == null || cell.bedId == -1) continue;
        
        // Skip if no tile
        if (cell.tileTypeId == null || cell.tileInstanceId == null) continue;
        
        // Check right neighbor
        if (col + 1 < cols) {
          final rightCoord = Coord(row, col + 1);
          if (_canSwapAndIsValid(
            a: coord,
            b: rightCoord,
            gridModel: gridModel,
            tileSpawner: tileSpawner,
            canSwap: canSwap,
            detectMatches: detectMatches,
          )) {
            return true;
          }
        }
        
        // Check down neighbor
        if (row + 1 < rows) {
          final downCoord = Coord(row + 1, col);
          if (_canSwapAndIsValid(
            a: coord,
            b: downCoord,
            gridModel: gridModel,
            tileSpawner: tileSpawner,
            canSwap: canSwap,
            detectMatches: detectMatches,
          )) {
            return true;
          }
        }
      }
    }
    return false;
  }
  
  /// Helper: Check if a swap would be valid (without permanently mutating grid)
  static bool _canSwapAndIsValid({
    required Coord a,
    required Coord b,
    required GridModel gridModel,
    required SpecialTileSpawner tileSpawner,
    required bool Function(Coord, Coord) canSwap,
    required MatchResult Function() detectMatches,
  }) {
    // Check basic swap validity
    if (!canSwap(a, b)) return false;
    
    final cellA = gridModel.cells[a.row][a.col];
    final cellB = gridModel.cells[b.row][b.col];
    
    // If either has special tile, it's a valid move
    if (_isSpecial(cellA.tileTypeId) || _isSpecial(cellB.tileTypeId)) {
      return true;
    }
    
    // Simulate swap (swap tiles temporarily)
    final tempTypeIdA = cellA.tileTypeId;
    final tempInstanceIdA = cellA.tileInstanceId;
    cellA.tileTypeId = cellB.tileTypeId;
    cellA.tileInstanceId = cellB.tileInstanceId;
    cellB.tileTypeId = tempTypeIdA;
    cellB.tileInstanceId = tempInstanceIdA;
    
    // Check if this creates a line match
    bool isValid = detectMatches().hasMatches;
    
    // Check if this creates a 2x2 block
    if (!isValid) {
      final block2x2 = tileSpawner.detect2x2AroundSwap(gridModel, a, b);
      isValid = block2x2 != null;
    }
    
    // Swap back to restore original state
    cellB.tileTypeId = cellA.tileTypeId;
    cellB.tileInstanceId = cellA.tileInstanceId;
    cellA.tileTypeId = tempTypeIdA;
    cellA.tileInstanceId = tempInstanceIdA;
    
    return isValid;
  }
  
  /// Check if a tileTypeId is a special tile (101-105)
  static bool _isSpecial(int? tileTypeId) {
    if (tileTypeId == null) return false;
    return tileTypeId >= 101 && tileTypeId <= 105;
  }
}
