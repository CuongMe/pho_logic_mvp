import 'dart:math';

import '../utils/weighted_picker.dart';
import 'stage_data.dart';
import '../model/grid_model.dart';

class StageBuilder {
  /// Build a BoardState from a StageData by resolving weighted spawn entries using weights.
  /// tileMap values (standardized):
  ///   0 = weighted random spawn
  ///   -1 = no tile (void/empty)
  ///   >=1 = fixed tile id
  static BoardState buildBoardState(StageData stage) {
    final rows = stage.rows;
    final cols = stage.columns;

    final tileMatrix = List.generate(rows, (_) => List<int>.filled(cols, 0));
    final bedMatrix = List.generate(rows, (_) => List<int>.filled(cols, 0));
    final blockerMatrix = List.generate(
        rows, (_) => List<int>.filled(cols, 0)); // Track blocker markers

    final tileIds = stage.tiles.map((t) => t.id).toList();
    final weights = stage.tiles.map((t) => t.weight).toList();

    // Validate: if any 0 or -2 cells exist (weighted spawn or blockers), tiles must be provided and weights must be > 0
    bool hasWeightedSpawn = false;
    bool hasBlockers = false;
    for (var row in stage.tileMap) {
      for (var v in row) {
        if (v == 0) {
          hasWeightedSpawn = true;
        }
        if (v == -2) {
          hasBlockers = true;
        }
      }
    }

    // Need picker if we have weighted spawns OR blockers (blockers need random tiles)
    final needsPicker = hasWeightedSpawn || hasBlockers;

    if (needsPicker) {
      if (tileIds.isEmpty) {
        throw ArgumentError(
            'Stage contains weighted spawn or blocker cells but `tiles` is empty. Provide tile definitions.');
      }
      if (weights.any((w) => w <= 0)) {
        throw ArgumentError(
            'All tile weights must be > 0 when using weighted spawn or blockers.');
      }
    }

    final rng = Random();
    final picker = needsPicker ? WeightedPicker(weights, rng) : null;
    final allowInitialMatches = stage.allowInitialMatches;

    int pickWeightedIndex(List<int> allowedIndices) {
      if (allowedIndices.isEmpty) {
        return picker!.pickIndex();
      }
      int total = 0;
      for (final idx in allowedIndices) {
        total += weights[idx];
      }
      if (total <= 0) {
        return allowedIndices[rng.nextInt(allowedIndices.length)];
      }
      final r = rng.nextInt(total);
      int acc = 0;
      for (final idx in allowedIndices) {
        acc += weights[idx];
        if (r < acc) return idx;
      }
      return allowedIndices.last;
    }

    int pickTileId(int row, int col) {
      if (picker == null) {
        throw ArgumentError(
            'Weighted spawn requested but no picker available.');
      }
      if (allowInitialMatches) {
        return tileIds[picker.pickIndex()];
      }
      final allowedIndices = <int>[];
      for (int i = 0; i < tileIds.length; i++) {
        final candidate = tileIds[i];
        if (!_wouldCreateMatch(tileMatrix, row, col, candidate)) {
          allowedIndices.add(i);
        }
      }
      final idx = pickWeightedIndex(allowedIndices);
      return tileIds[idx];
    }

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // tile map handling (standardized):
        // 0 = weighted random spawn
        // -1 = no tile (void/empty)
        // -2 = blocker marker (scooter_tile_blocker)
        // >=1 = fixed tile id
        int val = 0;
        try {
          val = stage.tileMap[r][c];
        } catch (_) {
          val = 0;
        }

        if (val == 0) {
          // Weighted random spawn
          tileMatrix[r][c] = pickTileId(r, c);
        } else if (val == -1) {
          // No tile (void/empty)
          tileMatrix[r][c] = 0; // Use 0 as the internal empty value
        } else if (val == -2) {
          // Blocker marker - no tile underneath (blocker occupies the cell alone)
          tileMatrix[r][c] = 0; // No tile for blocker cells
          blockerMatrix[r][c] = -2; // Mark as scooter blocker
        } else if (val >= 1) {
          // Fixed tile id
          tileMatrix[r][c] = val;
        } else {
          // Unknown negative value - treat as no tile
          tileMatrix[r][c] = 0;
        }

        // bed map
        int b = 0;
        try {
          b = stage.bedMap[r][c];
        } catch (_) {
          b = 0;
        }
        bedMatrix[r][c] = b;
      }
    }

    return BoardState(
        rows: rows,
        cols: cols,
        tileIds: tileMatrix,
        bedIds: bedMatrix,
        blockerIds: blockerMatrix);
  }

  /// Convenience: build a filled GridModel directly.
  static GridModel buildGridModel(StageData stage) {
    final state = buildBoardState(stage);
    return GridModel.fromBoardState(state, stageData: stage);
  }

  static bool _wouldCreateMatch(
      List<List<int>> tileMatrix, int row, int col, int tileId) {
    if (tileId <= 0) return false;
    if (col >= 2 &&
        tileMatrix[row][col - 1] == tileId &&
        tileMatrix[row][col - 2] == tileId) {
      return true;
    }
    if (row >= 2 &&
        tileMatrix[row - 1][col] == tileId &&
        tileMatrix[row - 2][col] == tileId) {
      return true;
    }
    return false;
  }
}
