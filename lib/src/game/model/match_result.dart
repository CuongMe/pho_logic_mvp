import 'coord.dart';

/// Represents a match found on the board
class Match {
  final List<Coord> cells;
  final int tileTypeId; // Type of tile that matched (not instance ID)

  Match({required this.cells, required this.tileTypeId});

  int get length => cells.length;

  @override
  String toString() => 'Match(tileTypeId: $tileTypeId, cells: $cells)';
}

/// Result of match detection on the board
class MatchResult {
  final List<Match> matches;
  final Set<Coord> allMatchedCells;

  MatchResult({required this.matches})
      : allMatchedCells = matches.expand((m) => m.cells).toSet();

  bool get hasMatches => matches.isNotEmpty;

  /// Get all unique tile type IDs that were matched
  Set<int> get matchedTileIds => matches.map((m) => m.tileTypeId).toSet();
  
  /// Alias for allMatchedCells (for consistency with user's naming)
  Set<Coord> get toClear => allMatchedCells;

  @override
  String toString() => 'MatchResult(${matches.length} matches, ${allMatchedCells.length} cells)';
}
