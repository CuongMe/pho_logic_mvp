import '../stages/stage_data.dart';

/// Blocker types that can occupy a cell and prevent interactions
enum BlockerType {
  none,
  scooterTileBlocker,
}

class Cell {
  int? tileTypeId; // Which sprite/type to draw (replaces tileId)
  int? tileInstanceId; // Unique id per tile instance that persists as it moves
  int? bedId;
  bool exists;
  BlockerType blocker; // Blocker overlay (default: none)
  String? blockerFilePath; // Path to blocker sprite (from JSON)

  Cell(
      {this.tileTypeId,
      this.tileInstanceId,
      this.bedId,
      this.exists = true,
      this.blocker = BlockerType.none,
      this.blockerFilePath});

  /// Check if this cell is blocked (has a blocker)
  bool get isBlocked => blocker != BlockerType.none;

  // Legacy support: if tileId is set, treat it as tileTypeId
  // This allows gradual migration
  int? get tileId => tileTypeId;
  set tileId(int? value) => tileTypeId = value;
}

/// Lightweight board state: raw integer matrices for tiles and beds.
class BoardState {
  final int rows;
  final int cols;
  final List<List<int>> tileIds; // -1 = EMPTY (cleared), >=1 = tile id
  final List<List<int>> bedIds; // -1 = void bed (masked), >=0 = bed type id
  final List<List<int>>?
      blockerIds; // Optional: blocker type ids (-2 = scooter_tile_blocker, 0 = none)

  BoardState(
      {required this.rows,
      required this.cols,
      required this.tileIds,
      required this.bedIds,
      this.blockerIds}) {
    if (tileIds.length != rows) throw ArgumentError('tileIds rows mismatch');
    if (bedIds.length != rows) throw ArgumentError('bedIds rows mismatch');
    if (blockerIds != null && blockerIds!.length != rows) {
      throw ArgumentError('blockerIds rows mismatch');
    }
  }

  factory BoardState.empty(int rows, int cols) {
    // EMPTY sentinel = -1
    return BoardState(
        rows: rows,
        cols: cols,
        tileIds: List.generate(rows, (_) => List.filled(cols, -1)),
        bedIds: List.generate(rows, (_) => List.filled(cols, 0)));
  }
}

class GridModel {
  final int rows;
  final int cols;
  final List<List<Cell>> cells;

  GridModel({required this.rows, required this.cols, required this.cells}) {
    if (cells.length != rows) throw ArgumentError('cells rows mismatch');
  }

  factory GridModel.fromBoardState(BoardState state,
      {required StageData stageData}) {
    // Build blocker lookup map: blockerId -> file path
    final blockerFileById = <int, String>{};
    for (final blockerDef in stageData.blockerTypes) {
      blockerFileById[blockerDef.id] = blockerDef.file;
    }

    final List<List<Cell>> cells = List.generate(state.rows, (r) {
      return List.generate(state.cols, (c) {
        final tileVal = state.tileIds[r][c];
        final bedVal = state.bedIds[r][c];
        final blockerVal = state.blockerIds?[r][c] ?? 0;

        // Determine blocker type and file path
        BlockerType blockerType = BlockerType.none;
        String? blockerFilePath;
        if (blockerVal == -2) {
          blockerType = BlockerType.scooterTileBlocker;
          blockerFilePath = blockerFileById[-2]; // Lookup from JSON
        }

        return Cell(
          // EMPTY = -1, valid tiles are > 0
          // Use tileTypeId instead of tileId (legacy support via getter/setter)
          tileTypeId: (tileVal == -1 || tileVal == 0)
              ? null
              : tileVal, // Support both -1 and legacy 0
          // Note: tileInstanceId is not set from BoardState - it should be assigned during spawning
          tileInstanceId: null,
          // Preserve bed id exactly as provided; do not treat 0 as null.
          bedId: bedVal,
          exists: true,
          blocker: blockerType,
          blockerFilePath: blockerFilePath,
        );
      });
    });
    return GridModel(rows: state.rows, cols: state.cols, cells: cells);
  }
}
// Grid model
