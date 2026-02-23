/// Coordinate on the game board
class Coord {
  final int row;
  final int col;

  const Coord(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coord && runtimeType == other.runtimeType && row == other.row && col == other.col;

  @override
  int get hashCode => row.hashCode ^ col.hashCode;

  @override
  String toString() => 'Coord($row, $col)';

  /// Get adjacent coordinates (up, down, left, right)
  List<Coord> getAdjacent(int maxRows, int maxCols) {
    final List<Coord> adjacent = [];
    if (row > 0) adjacent.add(Coord(row - 1, col));
    if (row < maxRows - 1) adjacent.add(Coord(row + 1, col));
    if (col > 0) adjacent.add(Coord(row, col - 1));
    if (col < maxCols - 1) adjacent.add(Coord(row, col + 1));
    return adjacent;
  }

  /// Check if this coordinate is adjacent to another
  bool isAdjacent(Coord other) {
    final rowDiff = (row - other.row).abs();
    final colDiff = (col - other.col).abs();
    return (rowDiff == 1 && colDiff == 0) || (rowDiff == 0 && colDiff == 1);
  }
}
