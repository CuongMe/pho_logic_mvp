import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../model/coord.dart';
import '../model/grid_model.dart';
import '../model/match_result.dart';
import '../stages/stage_data.dart';
import '../utils/weighted_picker.dart';
import '../utils/debug_logger.dart';
import 'special_tile_spawner.dart';
import 'special_activation_resolver.dart';
import 'special_combo_resolver.dart';
import 'board_solvability.dart';
import '../../audio/sfx_manager.dart';

/// Controller that manages match-3 game rules and mutates GridModel
/// Handles swap validation, match detection, clearing, gravity, refill, and cascades
class BoardController {
  final GridModel gridModel;
  final StageData stageData;
  final SfxManager sfxManager; // Injected SfxManager singleton

  final int rows;
  final int cols;

  // Instance ID counter for spawning new tiles
  int _nextInstanceId = 10000;

  // Weighted picker for random tile spawning (initialized lazily)
  WeightedPicker? _picker;
  Random? _rng;

  // Spawnable tiles list (excludes special tiles - see _isSpecial())
  // Special tiles should only spawn from matches, not from random refill
  List<TileDef> _spawnableTiles = [];

  // Special tile spawner for handling power-ups
  late final SpecialTileSpawner _tileSpawner;

  // Special activation resolver for handling special tile activations
  late final SpecialActivationResolver _activationResolver;

  // Special combo resolver for handling special+special swap combos
  late final SpecialComboResolver _comboResolver;

  // Pending match SFX: tileTypeId to play when tiles actually clear
  int? _pendingMatchSfxTypeId;

  BoardController({
    required this.gridModel,
    required this.stageData,
    required this.sfxManager, // Inject SfxManager instance
  })  : rows = gridModel.rows,
        cols = gridModel.cols {
    _rng = Random();
    _initializePicker();
    _tileSpawner = SpecialTileSpawner(
      rng: _rng!,
    );
    _activationResolver = SpecialActivationResolver(
      spawner: _tileSpawner,
      rows: rows,
      cols: cols,
    );
    _comboResolver = SpecialComboResolver(
      rng: _rng!,
    );
  }

  /// Play match sound using bloop for all tile matches
  void _playMatchSound() {
    // Use normal bloop sound (no pitch variation for regular matches)
    sfxManager.playTuned(SfxType.bloop);
  }

  /// Arm match SFX to play when tiles clear
  /// SFX will play when tiles actually clear in _emitCellsCleared
  void _armMatchSfx() {
    _pendingMatchSfxTypeId = 1; // Dummy value - we just play bloop regardless
    DebugLogger.boardController('Armed match SFX (will play on clear)');
  }

  void _initializePicker() {
    if (stageData.tiles.isEmpty) return;

    // Filter out special tiles from spawnable tiles
    // Special tiles should only spawn from matches, not from random refill
    _spawnableTiles = stageData.tiles.where((t) {
      return !_isSpecial(t.id); // Exclude special tiles
    }).toList();

    if (_spawnableTiles.isEmpty) {
      DebugLogger.warn('No spawnable tiles after filtering specials',
          category: 'BoardController');
      return;
    }

    final weights = _spawnableTiles.map((t) => t.weight).toList();
    _picker = WeightedPicker(weights, _rng!);
  }

  /// Get a random spawnable tile (excludes special tiles - see _isSpecial())
  TileDef? _getRandomSpawnableTile() {
    if (_picker == null || _spawnableTiles.isEmpty) return null;

    final tileIndex = _picker!.pickIndex();
    // Map picker index to spawnable tiles list (index directly corresponds to filtered list)
    if (tileIndex >= 0 && tileIndex < _spawnableTiles.length) {
      return _spawnableTiles[tileIndex];
    }
    return _spawnableTiles.first; // Fallback
  }

  /// Get next unique instance ID for spawning tiles
  int getNextInstanceId() {
    return _nextInstanceId++;
  }

  /// Initialize instanceIds for all existing tiles in the grid
  /// Should be called once after board is loaded to assign IDs to initial tiles
  void initializeInstanceIds() {
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final cell = gridModel.cells[row][col];
        // Skip blocked cells (blockers should never have tiles)
        if (cell.isBlocked) continue;
        // If cell has tileTypeId but no tileInstanceId, assign one
        if (cell.tileTypeId != null && cell.tileInstanceId == null) {
          cell.tileInstanceId = getNextInstanceId();
        }
      }
    }
  }

  /// Stabilize initial board: reroll matched cells until there are zero matches
  /// AND ensure at least 1 valid move exists
  /// Only rerolls normal tiles (not special tiles - see _isSpecial())
  /// Respects allowInitialMatches setting from stageData
  void stabilizeInitialBoard() {
    if (stageData.allowInitialMatches) {
      return; // Skip stabilization if initial matches are allowed
    }

    int rerollCount = 0;
    const maxRerolls = 50; // Safety cap to prevent infinite loops

    while (rerollCount < maxRerolls) {
      final matchResult = detectMatches();

      if (!matchResult.hasMatches) {
        // No matches found - check if board has valid moves
        if (hasPossibleMove()) {
          // Board is stable AND solvable
          if (rerollCount > 0) {
            DebugLogger.boardController(
                'Board stabilized after $rerollCount reroll(s) with valid moves');
          }
          return;
        }
        // No matches but also no valid moves - need to reroll to create solvability
        DebugLogger.boardController(
            'Board has no matches but also no valid moves - rerolling to create solvability');
      }

      // Reroll all matched cells with new normal tiles
      // OR reroll random cells if no matches but no valid moves
      if (matchResult.hasMatches) {
        // Reroll matched cells
        for (final match in matchResult.matches) {
          for (final coord in match.cells) {
            final cell = gridModel.cells[coord.row][coord.col];
            // Skip blocked cells (blockers should never have tiles)
            if (cell.isBlocked) continue;
            // Only reroll normal tiles (not special tiles)
            if (cell.tileTypeId != null && !_isSpecial(cell.tileTypeId)) {
              final tileDef = _getRandomSpawnableTile();
              if (tileDef != null) {
                cell.tileTypeId = tileDef.id;
                // Keep existing instanceId if present, otherwise assign new one
                cell.tileInstanceId ??= getNextInstanceId();
              }
            }
          }
        }
      } else {
        // No matches but no valid moves - reroll a few random cells to create opportunities
        final playableCells = <Coord>[];
        for (int row = 0; row < rows; row++) {
          for (int col = 0; col < cols; col++) {
            final cell = gridModel.cells[row][col];
            if (cell.bedId != null && cell.bedId != -1 && 
                cell.tileTypeId != null && !cell.isBlocked && !_isSpecial(cell.tileTypeId)) {
              playableCells.add(Coord(row, col));
            }
          }
        }
        
        if (playableCells.isNotEmpty) {
          // Reroll 20% of playable cells (or at least 3)
          final rerollAmount = (playableCells.length * 0.2).ceil().clamp(3, playableCells.length);
          playableCells.shuffle(_rng);
          
          for (int i = 0; i < rerollAmount; i++) {
            final coord = playableCells[i];
            final cell = gridModel.cells[coord.row][coord.col];
            final tileDef = _getRandomSpawnableTile();
            if (tileDef != null) {
              cell.tileTypeId = tileDef.id;
              cell.tileInstanceId ??= getNextInstanceId();
            }
          }
        }
      }

      rerollCount++;
    }

    if (rerollCount >= maxRerolls) {
      DebugLogger.warn('Board stabilization hit max rerolls ($maxRerolls)',
          category: 'BoardController');
    }
  }

  /// Check if two cells can be swapped
  /// Both must be playable, have tiles, and be adjacent (Manhattan distance 1)
  bool canSwap(Coord a, Coord b) {
    // Check bounds
    if (a.row < 0 || a.row >= rows || a.col < 0 || a.col >= cols) {
      DebugLogger.swap('CanSwap: out of bounds: $a (rows: $rows, cols: $cols)');
      return false;
    }
    if (b.row < 0 || b.row >= rows || b.col < 0 || b.col >= cols) {
      DebugLogger.swap('CanSwap: out of bounds: $b (rows: $rows, cols: $cols)');
      return false;
    }

    // Check if cells are playable (not void)
    final cellA = gridModel.cells[a.row][a.col];
    final cellB = gridModel.cells[b.row][b.col];
    if (cellA.bedId == null || cellA.bedId! == -1) {
      DebugLogger.swap('CanSwap: cellA at $a is void (bedId: ${cellA.bedId})');
      return false;
    }
    if (cellB.bedId == null || cellB.bedId! == -1) {
      DebugLogger.swap('CanSwap: cellB at $b is void (bedId: ${cellB.bedId})');
      return false;
    }

    // Check if both have tiles
    if (cellA.tileTypeId == null || cellA.tileInstanceId == null) {
      DebugLogger.swap(
          'CanSwap: cellA at $a has no tile (tileTypeId: ${cellA.tileTypeId}, tileInstanceId: ${cellA.tileInstanceId})');
      return false;
    }
    if (cellB.tileTypeId == null || cellB.tileInstanceId == null) {
      DebugLogger.swap(
          'CanSwap: cellB at $b has no tile (tileTypeId: ${cellB.tileTypeId}, tileInstanceId: ${cellB.tileInstanceId})');
      return false;
    }

    // Check if either cell is blocked
    if (cellA.isBlocked) {
      DebugLogger.swap(
          'CanSwap: cellA at $a is blocked (blocker: ${cellA.blocker})');
      return false;
    }
    if (cellB.isBlocked) {
      DebugLogger.swap(
          'CanSwap: cellB at $b is blocked (blocker: ${cellB.blocker})');
      return false;
    }

    // Check if adjacent (Manhattan distance 1)
    final rowDiff = (a.row - b.row).abs();
    final colDiff = (a.col - b.col).abs();
    if (rowDiff + colDiff != 1) {
      DebugLogger.swap(
          'CanSwap: not adjacent: $a vs $b (rowDiff: $rowDiff, colDiff: $colDiff)');
      return false;
    }

    DebugLogger.swap('CanSwap: valid swap $a <-> $b');
    return true;
  }

  /// Swap two cells (both tileTypeId and tileInstanceId)
  void swapCells(Coord a, Coord b) {
    if (!canSwap(a, b)) {
      throw ArgumentError('Cannot swap cells at $a and $b');
    }

    final cellA = gridModel.cells[a.row][a.col];
    final cellB = gridModel.cells[b.row][b.col];

    // Swap tileTypeId
    final tempTypeId = cellA.tileTypeId;
    cellA.tileTypeId = cellB.tileTypeId;
    cellB.tileTypeId = tempTypeId;

    // Swap tileInstanceId
    final tempInstanceId = cellA.tileInstanceId;
    cellA.tileInstanceId = cellB.tileInstanceId;
    cellB.tileInstanceId = tempInstanceId;
  }

  /// Detect all matches (horizontal and vertical runs of >=3 same tileTypeId)
  /// Ignores void cells (bedId == -1) and special tiles (see _isSpecial())
  /// Special tiles should not match to prevent infinite loops
  MatchResult detectMatches() {
    final matches = <Match>[];

    int? getTileTypeId(Coord coord) {
      if (coord.row < 0 ||
          coord.row >= rows ||
          coord.col < 0 ||
          coord.col >= cols) {
        return null;
      }
      final cell = gridModel.cells[coord.row][coord.col];
      if (cell.bedId == null || cell.bedId! == -1) return null; // Void cell
      if (cell.isBlocked) {
        return null; // Blocked cells cannot be part of matches
      }
      if (_isSpecial(cell.tileTypeId)) {
        return null; // Ignore special tiles in match detection
      }
      return cell.tileTypeId;
    }

    // Detect horizontal matches
    for (int row = 0; row < rows; row++) {
      int? currentTypeId;
      int runStart = -1;
      int runLength = 0;

      for (int col = 0; col < cols; col++) {
        final coord = Coord(row, col);
        final typeId = getTileTypeId(coord);

        if (typeId == currentTypeId && typeId != null) {
          // Continue run
          runLength++;
        } else {
          // End of run - check if it's a match (>=3)
          if (runLength >= 3 && currentTypeId != null) {
            final matchCells = <Coord>[];
            for (int c = runStart; c < runStart + runLength; c++) {
              matchCells.add(Coord(row, c));
            }
            matches.add(Match(cells: matchCells, tileTypeId: currentTypeId));
          }

          // Start new run
          currentTypeId = typeId;
          runStart = col;
          runLength = typeId != null ? 1 : 0;
        }
      }

      // Check final run at end of row
      if (runLength >= 3 && currentTypeId != null) {
        final matchCells = <Coord>[];
        for (int c = runStart; c < runStart + runLength; c++) {
          matchCells.add(Coord(row, c));
        }
        matches.add(Match(cells: matchCells, tileTypeId: currentTypeId));
      }
    }

    // Detect vertical matches
    for (int col = 0; col < cols; col++) {
      int? currentTypeId;
      int runStart = -1;
      int runLength = 0;

      for (int row = 0; row < rows; row++) {
        final coord = Coord(row, col);
        final typeId = getTileTypeId(coord);

        if (typeId == currentTypeId && typeId != null) {
          // Continue run
          runLength++;
        } else {
          // End of run - check if it's a match (>=3)
          if (runLength >= 3 && currentTypeId != null) {
            final matchCells = <Coord>[];
            for (int r = runStart; r < runStart + runLength; r++) {
              matchCells.add(Coord(r, col));
            }
            matches.add(Match(cells: matchCells, tileTypeId: currentTypeId));
          }

          // Start new run
          currentTypeId = typeId;
          runStart = row;
          runLength = typeId != null ? 1 : 0;
        }
      }

      // Check final run at end of column
      if (runLength >= 3 && currentTypeId != null) {
        final matchCells = <Coord>[];
        for (int r = runStart; r < runStart + runLength; r++) {
          matchCells.add(Coord(r, col));
        }
        matches.add(Match(cells: matchCells, tileTypeId: currentTypeId));
      }
    }

    return MatchResult(matches: matches);
  }

  /// Check if a tile type ID is a special tile
  /// Currently checks for range 101-105, but this is the single source of truth
  bool _isSpecial(int? tileTypeId) {
    if (tileTypeId == null) return false;
    return tileTypeId >= 101 && tileTypeId <= 105;
  }

  /// Check if a coord contains a special tile (uses _isSpecial())
  bool _coordHasSpecial(Coord coord) {
    if (coord.row < 0 ||
        coord.row >= rows ||
        coord.col < 0 ||
        coord.col >= cols) {
      return false;
    }
    final cell = gridModel.cells[coord.row][coord.col];
    return _isSpecial(cell.tileTypeId);
  }

  /// Play scooter blocker break animation
  /// Triggers VFX callback if available
  Future<void> _playScooterBreakAnimation(Coord coord) async {
    if (onBlockerBreak != null) {
      await onBlockerBreak!(coord);
    } else {
      // Fallback if no VFX callback registered
      DebugLogger.boardController('Playing scooter break animation at $coord (no VFX callback)');
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Helper to emit cleared cells callback and actually clear the cells
  /// Reads tileTypeId BEFORE clearing, filters out special tiles (only sends victim tile types)
  /// Public method for VFX to trigger clearing at exact visual timing.
  /// This ensures all clears go through the same path for objectives and particles.
  Future<void> clearTilesForVfx(Set<Coord> cellsToClear) async {
    await _emitCellsCleared(cellsToClear, isRegularClear: false);
  }

  /// Ensures all clearing paths go through the same callback mechanism
  /// isRegularClear: if true, adjacent blockers will be broken; if false, blockers are preserved
  /// Only regular tile matches should break adjacent blockers (not special VFX)
  Future<Map<Coord, int>> _emitCellsCleared(Set<Coord> cellsToClear, {bool isRegularClear = true}) async {
    if (cellsToClear.isEmpty) {
      return {};
    }

    if (_onCellsClearedWithTypes == null) {
      // If no callback, just clear silently and track what was cleared
      final clearedCellsWithTypes = <Coord, int>{};
      for (final coord in cellsToClear) {
        if (coord.row >= 0 &&
            coord.row < rows &&
            coord.col >= 0 &&
            coord.col < cols) {
          final cell = gridModel.cells[coord.row][coord.col];
          if (cell.bedId != null && cell.bedId! != -1) {
            final tileTypeId = cell.tileTypeId;
            if (tileTypeId != null) {
              clearedCellsWithTypes[coord] = tileTypeId;
            }
            cell.tileTypeId = null;
            cell.tileInstanceId = null;
          }
        }
      }
      return clearedCellsWithTypes;
    }

    // Build map of cleared cells with their tileTypeIds (BEFORE clearing)
    // Only include victim tiles (not special tiles 101-105)
    final clearedCellsWithTypes = <Coord, int>{};
    bool hasRegularTileCleared = false;

    // Track coords that will be cleared (for blocker neighbor checking)
    final coordsBeingCleared = <Coord>{};
    for (final coord in cellsToClear) {
      if (coord.row >= 0 &&
          coord.row < rows &&
          coord.col >= 0 &&
          coord.col < cols) {
        final cell = gridModel.cells[coord.row][coord.col];
        if (cell.bedId != null &&
            cell.bedId! != -1 &&
            cell.tileTypeId != null) {
          coordsBeingCleared.add(coord);
        }
      }
    }

    // Check for scooter blockers adjacent to cleared cells (BEFORE clearing)
    // Only regular matches clear blockers (special tile clears don't count)
    final scooterBlockersToBreak = <Coord>{};
    if (isRegularClear) {
      for (final clearedCoord in coordsBeingCleared) {
        // Get 4-direction neighbors
        final neighbors = [
          Coord(clearedCoord.row - 1, clearedCoord.col), // Up
          Coord(clearedCoord.row + 1, clearedCoord.col), // Down
          Coord(clearedCoord.row, clearedCoord.col - 1), // Left
          Coord(clearedCoord.row, clearedCoord.col + 1), // Right
        ];

        for (final neighbor in neighbors) {
          if (neighbor.row >= 0 &&
              neighbor.row < rows &&
              neighbor.col >= 0 &&
              neighbor.col < cols) {
            final neighborCell = gridModel.cells[neighbor.row][neighbor.col];
            if (neighborCell.blocker == BlockerType.scooterTileBlocker) {
              scooterBlockersToBreak.add(neighbor);
            }
          }
        }
      }
    }

    DebugLogger.boardController(
        '_emitCellsCleared: processing ${cellsToClear.length} cells');

    for (final coord in cellsToClear) {
      if (coord.row >= 0 &&
          coord.row < rows &&
          coord.col >= 0 &&
          coord.col < cols) {
        final cell = gridModel.cells[coord.row][coord.col];
        // Only clear playable cells (bedId != -1)
        if (cell.bedId != null && cell.bedId! != -1) {
          // Capture tileTypeId BEFORE clearing
          final tileTypeId = cell.tileTypeId;
          if (tileTypeId != null) {
            DebugLogger.boardController(
                '_emitCellsCleared: coord=$coord, tileTypeId=$tileTypeId, isSpecial=${_isSpecial(tileTypeId)}');
            // Only include victim tiles (not special tiles)
            // Special tiles (101-105) should not be counted as cleared for objectives
            if (!_isSpecial(tileTypeId)) {
              clearedCellsWithTypes[coord] = tileTypeId;
              hasRegularTileCleared = true;
              DebugLogger.boardController(
                  '_emitCellsCleared: added victim tile at $coord: $tileTypeId');
            } else {
              DebugLogger.boardController(
                  '_emitCellsCleared: filtered out special tile at $coord: $tileTypeId');
            }
          } else {
            DebugLogger.boardController(
                '_emitCellsCleared: coord=$coord has null tileTypeId (already cleared?)');
          }
          // Actually clear the cell
          cell.tileTypeId = null;
          cell.tileInstanceId = null;
        }
      }
    }

    // Play pending match SFX if we cleared any regular tiles (1-6)
    if (hasRegularTileCleared && _pendingMatchSfxTypeId != null) {
      _playMatchSound();
      DebugLogger.boardController('Played pending match SFX on actual clear');
      _pendingMatchSfxTypeId =
          null; // Clear pending flag - only play once per step
    }

    DebugLogger.boardController(
        '_emitCellsCleared: emitting ${clearedCellsWithTypes.length} victim tiles');

    // Always emit callback (even if empty) so listeners can react/debug
    // Empty maps can occur when special tiles clear only other special tiles
    // Note: Match SFX is now played separately based on MatchResult, not victim tiles
    await _onCellsClearedWithTypes!(clearedCellsWithTypes);

    // Queue scooter break animations AFTER tiles are cleared (batch playback later)
    if (isRegularClear && scooterBlockersToBreak.isNotEmpty) {
      _pendingBlockerBreaks.addAll(scooterBlockersToBreak);
    }

    return clearedCellsWithTypes;
  }

  /// Check if a coord has a specific special tile type
  bool _coordHasSpecialType(Coord coord, int expectedTypeId) {
    if (coord.row < 0 ||
        coord.row >= rows ||
        coord.col < 0 ||
        coord.col >= cols) {
      return false;
    }
    final cell = gridModel.cells[coord.row][coord.col];
    if (cell.bedId == null || cell.bedId == -1) {
      return false; // Not playable
    }
    return cell.tileTypeId == expectedTypeId;
  }

  /// Callback for generic cell clears with tileTypeId
  /// Fires for ALL clears (matches, special activations, combo clears)
  /// Map key: coord, value: tileTypeId (captured BEFORE clearing)
  Future<void> Function(Map<Coord, int>)? _onCellsClearedWithTypes;

  /// Set the generic clear callback (called from BoardGame)
  void setOnCellsClearedWithTypes(
      Future<void> Function(Map<Coord, int>)? callback) {
    _onCellsClearedWithTypes = callback;
  }

  // Callback for blocker break VFX
  /// Fires when a blocker is about to be removed (triggered by adjacent match)
  Future<void> Function(Coord)? onBlockerBreak;

  /// Callback when a blocker has been cleared (after removal)
  void Function(Coord)? onBlockerCleared;

  /// Pending blockers to break after clear sync (batch)
  final Set<Coord> _pendingBlockerBreaks = {};

  /// Set the blocker break callback (called from BoardGame)
  void setOnBlockerBreak(Future<void> Function(Coord)? callback) {
    onBlockerBreak = callback;
  }

  /// Set the blocker cleared callback (called from BoardGame)
  void setOnBlockerCleared(void Function(Coord)? callback) {
    onBlockerCleared = callback;
  }

  /// Play all pending blocker break animations (batched).
  /// Keep faster stagger on Windows desktop, standard pacing elsewhere.
  Future<void> _playPendingBlockerBreaks() async {
    if (_pendingBlockerBreaks.isEmpty) return;

    final blockers = _pendingBlockerBreaks.toList();
    _pendingBlockerBreaks.clear();

    final staggerMs =
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) ? 45 : 90;
    final futures = <Future<void>>[];
    for (int i = 0; i < blockers.length; i++) {
      final blockerCoord = blockers[i];
      futures.add(Future(() async {
        final delayMs = staggerMs * i;
        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
        await _playScooterBreakAnimation(blockerCoord);
        final cell = gridModel.cells[blockerCoord.row][blockerCoord.col];
        cell.blocker = BlockerType.none;
        onBlockerCleared?.call(blockerCoord);
        DebugLogger.boardController('Scooter blocker cleared at $blockerCoord');
      }));
    }

    await Future.wait(futures);
  }

  /// Clear matched cells, with special tile spawning for groups >= 4
  /// swapA and swapB are optional swap coordinates for spawn location preference
  /// chosenCoord is the coord the user started dragging from (for drag start tracking)
  /// Handles special tile activation and chain reactions
  /// Returns activatedSpecials map (coord -> tileTypeId)
  /// onSpecialActivated: Optional callback (receives activatedSpecials, vfxMetadata)
  /// onSync: Optional callback for syncing after sequential clears (required for Party Poppers)
  Future<Map<Coord, int>> clearMatchedCells(
    MatchResult matchResult, {
    Coord? swapA,
    Coord? swapB,
    Coord?
        chosenCoord, // The coord the user started dragging from (dragStartCoord)
    Future<void> Function(Map<Coord, int>,
            Map<Coord, ({Coord? targetCoord, Set<Coord>? activationCells})>)?
        onSpecialActivated,
    Future<void> Function()? onSync,
  }) async {
    // Process matches to get cells to clear and special tiles to spawn
    final result = _tileSpawner.processMatches(
      matchResult,
      gridModel,
      swapA: swapA,
      swapB: swapB,
    );
    final specialTileSpawns = result.specialTileSpawns;

    // Create initial clearing set, EXCLUDING spawn locations (spawn locations will become specials, not be cleared)
    // Remove spawn coords BEFORE passing to expandClearsWithSpecials to prevent spawned specials from being cleared
    final initialCellsToClear = <Coord>{...result.cellsToClear};
    initialCellsToClear.removeAll(result.specialTileSpawns.keys);

    // Check if this is a special+special combo swap
    // Note: swap has already happened, so we read current types at swapA/swapB
    final isSpecialCombo = swapA != null &&
        swapB != null &&
        _coordHasSpecial(swapA) &&
        _coordHasSpecial(swapB);

    Set<Coord> cellsToClear;
    Map<Coord, int> activatedSpecials;
    Map<Coord, ({Coord? targetCoord, Set<Coord>? activationCells})> vfxMetadata;

    if (isSpecialCombo) {
      // Use combo resolver for special+special swaps
      DebugLogger.specialCombo(
          'Detected special+special swap at $swapA and $swapB, using combo resolver');
      final comboResult = _comboResolver.resolveCombo(
        grid: gridModel,
        a: swapA,
        b: swapB,
        chosenCoord: chosenCoord,
      );

      if (comboResult.isCombo) {
        // Process combo steps sequentially - skip normal pipeline
        DebugLogger.specialCombo(
            'Combo detected: ${comboResult.steps.length} steps, ${comboResult.cellsToClear.length} cells to clear');
        return await _runComboSteps(
          comboResult: comboResult,
          swapA: swapA,
          swapB: swapB,
          onSpecialActivated: onSpecialActivated,
          onSync: onSync,
        );
      } else {
        // Not a combo - fall back to normal activation resolver
        final expanded = _activationResolver.expandClearsWithSpecials(
          gridModel: gridModel,
          initialToClear: initialCellsToClear,
          swapA: swapA,
          swapB: swapB,
          chosenCoord: chosenCoord,
        );
        cellsToClear = expanded.cellsToClear;
        activatedSpecials = expanded.activatedSpecials;
        vfxMetadata = expanded.vfxMetadata;

        // CRITICAL FIX: Remove spawn locations from cellsToClear to prevent newly spawned specials from being cleared
        final removedSpawns =
            cellsToClear.intersection(specialTileSpawns.keys.toSet());
        if (removedSpawns.isNotEmpty) {
          DebugLogger.boardController(
              'Preventing ${removedSpawns.length} spawn location(s) from being cleared: $removedSpawns');
        }
        cellsToClear.removeAll(specialTileSpawns.keys);
      }
    } else {
      // Normal special activation (not a combo)
      // Expand clearing set with special tile activations (swap-based + chain reactions)
      // Note: Chain reaction is computed BEFORE spawning specials (based on current board state)
      final expanded = _activationResolver.expandClearsWithSpecials(
        gridModel: gridModel,
        initialToClear: initialCellsToClear,
        swapA: swapA,
        swapB: swapB,
        chosenCoord: chosenCoord,
      );
      cellsToClear = expanded.cellsToClear;
      activatedSpecials = expanded.activatedSpecials;
      vfxMetadata = expanded.vfxMetadata;

      // CRITICAL FIX: Remove spawn locations from cellsToClear to prevent newly spawned specials from being cleared
      // This can happen when sticky rice bomb (103) activates and its activation cells include a spawn location
      final removedSpawns =
          cellsToClear.intersection(specialTileSpawns.keys.toSet());
      if (removedSpawns.isNotEmpty) {
        DebugLogger.boardController(
            'Preventing ${removedSpawns.length} spawn location(s) from being cleared: $removedSpawns');
      }
      cellsToClear.removeAll(specialTileSpawns.keys);
    }

    // Compute DragonFly targetCoord IMMEDIATELY after expandClearsWithSpecials
    // This must happen before Party Popper logic to prevent the target from being included in sequential clears
    Coord? dragonFlyTargetCoord;
    for (final entry in activatedSpecials.entries) {
      if (entry.value == 105) {
        // DragonFly
        final metadata = vfxMetadata[entry.key];
        if (metadata != null && metadata.targetCoord != null) {
          dragonFlyTargetCoord = metadata.targetCoord;
          DebugLogger.boardController(
              'DragonFly detected: excluding targetCoord $dragonFlyTargetCoord from all clearing logic');
          break;
        }
      }
    }

    // Spawn special tiles (after computing chain reaction, but before clearing)
    final spawnCoords = specialTileSpawns.keys.toSet();
    for (final entry in specialTileSpawns.entries) {
      final coord = entry.key;
      final specialTypeId = entry.value;

      if (coord.row >= 0 &&
          coord.row < rows &&
          coord.col >= 0 &&
          coord.col < cols) {
        final cell = gridModel.cells[coord.row][coord.col];
        // Keep tileInstanceId, only change tileTypeId
        // Note: spawn location should always have a tileInstanceId (it's from a matched cell)
        if (cell.tileInstanceId == null) {
          DebugLogger.warn(
              'spawn location $coord has no tileInstanceId, assigning new one',
              category: 'SpecialTile');
          cell.tileInstanceId = getNextInstanceId();
        }
        cell.tileTypeId = specialTypeId;
        DebugLogger.specialTile(
            'Spawned special tile type $specialTypeId at $coord (instanceId: ${cell.tileInstanceId})');
      }
    }

    // Separate VFX-controlled specials (Party Poppers 101/102, Firecracker 104)
    // These specials handle their own clearing timing via VFX
    // EXCLUDE DragonFly targetCoord from VFX-controlled cells
    final partyPopperCells =
        <Coord>{}; // All cells that should be cleared by Party Poppers
    final partyPoppersToClear =
        <Coord, int>{}; // coord -> tileTypeId (just the Party Popper coords)
    final partyPopperAllowedCells = <Coord,
        Set<Coord>>{}; // coord -> allowedCells (computed once per popper)
    final firecrackerCells =
        <Coord>{}; // All cells that should be cleared by Firecrackers
    final firecrackersToClear =
        <Coord, int>{}; // coord -> tileTypeId (just the Firecracker coords)

    for (final entry in activatedSpecials.entries) {
      final coord = entry.key;
      final typeId = entry.value;

      if (typeId == 101 || typeId == 102) {
        // This is a Party Popper activation
        partyPoppersToClear[coord] = typeId;

        // Get all cells that this Party Popper should clear (from getActivationCells)
        // Compute once and store for reuse
        final result = _tileSpawner.getActivationCells(
          gridModel,
          coord,
          typeId,
        );
        partyPopperAllowedCells[coord] = result.affected;

        for (final popperCell in result.affected) {
          // Exclude DragonFly targetCoord from Party Popper cells
          if (popperCell != dragonFlyTargetCoord) {
            partyPopperCells.add(popperCell);
          }
        }
        // Also include the Party Popper coord itself (if not DragonFly target)
        if (coord != dragonFlyTargetCoord) {
          partyPopperCells.add(coord);
        }
      } else if (typeId == 104) {
        // This is a Firecracker activation (3x3 explosion)
        firecrackersToClear[coord] = typeId;

        // Get all cells that this Firecracker should clear (3x3 area)
        final result = _tileSpawner.getActivationCells(
          gridModel,
          coord,
          typeId,
        );

        for (final firecrackerCell in result.affected) {
          // Exclude DragonFly targetCoord from Firecracker cells
          if (firecrackerCell != dragonFlyTargetCoord) {
            firecrackerCells.add(firecrackerCell);
          }
        }
        // Also include the Firecracker coord itself (if not DragonFly target)
        if (coord != dragonFlyTargetCoord) {
          firecrackerCells.add(coord);
        }
      }
    }

    // Separate cells: VFX-controlled cells vs other cells
    // Also track which cells came from special activations (103 Sticky Rice, 105 DragonFly)
    final otherCellsToClear = <Coord>{};
    final specialActivationCells = <Coord>{}; // Cells cleared by special activations (not VFX)
    
    // Get all cells that will be cleared by activated special types 103 and 105
    final cellsClearedBySpecials = <Coord>{};
    for (final entry in activatedSpecials.entries) {
      if (entry.value == 103 || entry.value == 105) {
        // These are special activations that clear cells
        final specialCoord = entry.key;
        final activationCells = vfxMetadata[specialCoord]?.activationCells;
        if (activationCells != null) {
          cellsClearedBySpecials.addAll(activationCells);
        }
        // Also include the special itself
        cellsClearedBySpecials.add(specialCoord);
      }
    }
    
    for (final coord in cellsToClear) {
      // Skip spawn coords - newly spawned specials should not be cleared immediately
      if (spawnCoords.contains(coord)) continue;

      // If this cell is part of a Party Popper activation, skip it (will be handled by VFX)
      if (partyPopperCells.contains(coord)) {
        continue;
      }

      // If this cell is part of a Firecracker activation, skip it (will be handled by VFX)
      if (firecrackerCells.contains(coord)) {
        continue;
      }

      // If this cell was cleared by special activation (103/105), track separately
      if (cellsClearedBySpecials.contains(coord)) {
        specialActivationCells.add(coord);
      } else {
        // Regular match cells
        otherCellsToClear.add(coord);
      }
    }

    // Play VFX for ALL specials in priority order (not just party poppers first)
    // This ensures DragonFly (priority 4) plays before Party Popper (priority 2)
    if (onSpecialActivated != null && activatedSpecials.isNotEmpty) {
      // Sort all activated specials by priority (descending) - highest priority first
      // Priority order: 105 (4) > 103 (3) > 101/102 (2) > 104 (1)
      int getPriority(int tileTypeId) {
        if (tileTypeId == 105) return 4; // DragonFly - highest priority
        if (tileTypeId == 103) return 3; // Sticky Rice Bomb
        if (tileTypeId == 101 || tileTypeId == 102) return 2; // Party Popper
        if (tileTypeId == 104) return 1; // Firecracker - lowest priority
        return 0;
      }

      final sortedSpecials = activatedSpecials.entries.toList()
        ..sort((a, b) {
          final priorityA = getPriority(a.value);
          final priorityB = getPriority(b.value);
          // Sort descending (higher priority first)
          return priorityB.compareTo(priorityA);
        });

      // Separate into party poppers and others for metadata handling
      final allSpecialsOrdered = <Coord, int>{};
      final allMetadataOrdered =
          <Coord, ({Coord? targetCoord, Set<Coord>? activationCells})>{};

      for (final entry in sortedSpecials) {
        allSpecialsOrdered[entry.key] = entry.value;
        // Get metadata for this special
        final meta = vfxMetadata[entry.key];
        if (meta != null) {
          allMetadataOrdered[entry.key] = meta;
        } else if (entry.value == 101 || entry.value == 102) {
          // Party poppers don't need targetCoord, but add empty metadata for consistency
          allMetadataOrdered[entry.key] =
              (targetCoord: null, activationCells: null);
        }
      }

      // Call VFX for all specials in priority order (sequential - each completes before next)
      await onSpecialActivated(allSpecialsOrdered, allMetadataOrdered);
    }

    if (partyPoppersToClear.isNotEmpty) {
      // NOTE: Party Popper clearing is now handled by VFX with exact projectile timing.
      // VFX calls game.clearTilesAtCoords() for each tile as projectile reaches it,
      // and clears the Party Popper tile itself after projectiles complete.
      // This ensures tiles disappear exactly when projectile touches them.
      // No sequential clear runner needed - VFX handles all clearing timing.
      DebugLogger.boardController(
          'Party Popper clearing handled by VFX (${partyPoppersToClear.length} poppers)');
    }

    if (firecrackersToClear.isNotEmpty) {
      // NOTE: Firecracker clearing is now handled by VFX with exact burst timing.
      // VFX calls game.clearTilesAtCoords() at the moment particles burst (60% through explosion),
      // ensuring tiles disappear synchronized with visual impact.
      DebugLogger.boardController(
          'Firecracker clearing handled by VFX (${firecrackersToClear.length} firecrackers)');
    }

    // Clear other cells (non-Party Popper) normally, EXCEPT DragonFly targetCoord
    // (dragonFlyTargetCoord was computed earlier, right after expandClearsWithSpecials)
    final otherCellsToClearFiltered = otherCellsToClear
        .where((coord) => coord != dragonFlyTargetCoord)
        .toSet();

    // Note: Match sound is now played BEFORE clearMatchedCells is called (in attemptSwap/runCascade)
    // to ensure immediate audio feedback before animations

    // Clear regular match cells with isRegularClear: true (can break adjacent blockers)
    if (otherCellsToClearFiltered.isNotEmpty) {
      await _emitCellsCleared(otherCellsToClearFiltered, isRegularClear: true);
    }

    // Clear special activation cells with isRegularClear: false (won't break adjacent blockers)
    final specialActivationCellsFiltered = specialActivationCells
        .where((coord) => coord != dragonFlyTargetCoord)
        .toSet();
    if (specialActivationCellsFiltered.isNotEmpty) {
      await _emitCellsCleared(specialActivationCellsFiltered, isRegularClear: false);
    }

    // Trigger special activation callback if provided
    // Pass metadata along with activatedSpecials
    // Note: All VFX (including party poppers) were already called earlier in priority order
    // This section is now empty - VFX handling moved above to ensure priority order

    // After VFX completes, clear DragonFly targetCoord if it exists
    if (dragonFlyTargetCoord != null) {
      DebugLogger.boardController(
          'DragonFly targetCoord $dragonFlyTargetCoord cleared after VFX');
      await _emitCellsCleared({dragonFlyTargetCoord});
    }

    return activatedSpecials;
  }

  /// Apply a clearing set with chain reaction support
  /// Uses the same pipeline as normal clears (SpecialActivationResolver)
  /// Handles special tile activations and chain reactions
  /// Returns: (clearedCells, activatedSpecials)
  // ignore: unused_element
  Future<
      ({
        Set<Coord> clearedCells,
        Map<Coord, int> activatedSpecials,
      })> _applyClearSetWithChain({
    required Set<Coord> initialToClear,
    required Future<void> Function() onSync,
    Future<void> Function(Set<Coord>)? onCellsCleared,
    Future<void> Function(Map<Coord, int>,
            Map<Coord, ({Coord? targetCoord, Set<Coord>? activationCells})>)?
        onSpecialActivated,
    Coord? swapA,
    Coord? swapB,
  }) async {
    // Expand clearing set with special tile activations (swap-based + chain reactions)
    final expanded = _activationResolver.expandClearsWithSpecials(
      gridModel: gridModel,
      initialToClear: initialToClear,
      swapA: swapA,
      swapB: swapB,
    );
    final cellsToClear = expanded.cellsToClear;
    final activatedSpecials = expanded.activatedSpecials;
    final vfxMetadata = expanded.vfxMetadata;

    // For DragonFly (105), identify targetCoord and exclude it from initial clear
    // The targetCoord will be cleared AFTER VFX completes
    Coord? dragonFlyTargetCoord;
    for (final entry in activatedSpecials.entries) {
      if (entry.value == 105) {
        // DragonFly
        final metadata = vfxMetadata[entry.key];
        if (metadata != null && metadata.targetCoord != null) {
          dragonFlyTargetCoord = metadata.targetCoord;
          DebugLogger.boardController(
              'DragonFly detected: excluding targetCoord $dragonFlyTargetCoord from initial clear');
          break;
        }
      }
    }

    // Clear all cells in the expanded clearing set, EXCEPT DragonFly targetCoord
    // Guard: only clear if coord in bounds AND bedId != -1 (not void)
    final cellsToClearFiltered =
        cellsToClear.where((coord) => coord != dragonFlyTargetCoord).toSet();
    final clearedCellsWithTypes = await _emitCellsCleared(cellsToClearFiltered);

    // Track which cells were actually cleared (from what _emitCellsCleared returned)
    final clearedCells = clearedCellsWithTypes.keys.toSet();

    // Trigger cells cleared callback (for combo particles) if provided
    if (onCellsCleared != null && clearedCells.isNotEmpty) {
      await onCellsCleared(clearedCells);
    }

    // Trigger special activation callback if provided
    // For DragonFly, this will play the VFX animation
    if (onSpecialActivated != null && activatedSpecials.isNotEmpty) {
      await onSpecialActivated(activatedSpecials, vfxMetadata);
    }

    // DragonFly targetCoord is cleared immediately after its VFX completes (in VFX dispatcher)
    // So we don't need to clear it here anymore

    await onSync(); // Sync to show tiles disappear
    await Future.wait([
      _playPendingBlockerBreaks(),
      Future.delayed(const Duration(milliseconds: 180)),
    ]); // Delay for clear animation

    // Apply gravity
    applyGravity();
    await onSync(); // Sync to show tiles fall
    await Future.delayed(
        const Duration(milliseconds: 300)); // Delay for fall animation

    // Refill
    refill();
    await onSync(); // Sync to show new tiles spawn
    await Future.delayed(
        const Duration(milliseconds: 150)); // Delay for spawn animation

    return (
      clearedCells: clearedCells,
      activatedSpecials: activatedSpecials,
    );
  }

  /// Apply gravity: drop tiles down into empty playable cells
  /// Moves both tileTypeId and tileInstanceId downward
  /// Skips void cells (bedId == -1) and treats blockers as solid barriers (no fall-through)
  void applyGravity() {
    // Process each column independently
    for (int col = 0; col < cols; col++) {
      // From bottom to top, find empty playable cells and fill them
      for (int row = rows - 1; row >= 0; row--) {
        final cell = gridModel.cells[row][col];

        // Skip void cells
        if (cell.bedId == null || cell.bedId! == -1) continue;

        // Skip blocked cells (blockers are solid, don't place tiles on them)
        if (cell.isBlocked) continue;

        // If this cell is empty, find the next tile above it
        if (cell.tileTypeId == null) {
          // Look upward for a tile to drop, but stop at blockers
          for (int r = row - 1; r >= 0; r--) {
            final aboveCell = gridModel.cells[r][col];

            // Skip void cells
            if (aboveCell.bedId == null || aboveCell.bedId! == -1) continue;

            // Hit a blocker - stop looking (tiles can't fall through blockers)
            if (aboveCell.isBlocked) break;

            // Found a tile above - move it down
            if (aboveCell.tileTypeId != null) {
              cell.tileTypeId = aboveCell.tileTypeId;
              cell.tileInstanceId = aboveCell.tileInstanceId;

              // Clear the source cell
              aboveCell.tileTypeId = null;
              aboveCell.tileInstanceId = null;
              break; // Move to next empty cell
            }
          }
        }
      }
    }
  }

  /// Refill empty playable cells at the top with random tiles
  /// Assigns new unique tileInstanceId for each spawned tile
  /// Only spawns regular tiles (excludes special tiles - see _isSpecial())
  /// Skips blocked cells (blockers prevent refill)
  void refill() {
    if (_picker == null || _spawnableTiles.isEmpty) return;

    // Process each column
    for (int col = 0; col < cols; col++) {
      // From top to bottom, find empty playable cells and fill them
      for (int row = 0; row < rows; row++) {
        final cell = gridModel.cells[row][col];

        // Skip void cells
        if (cell.bedId == null || cell.bedId! == -1) continue;

        // Skip blocked cells (blockers prevent refill)
        if (cell.isBlocked) continue;

        // If empty, spawn a new tile (only spawnable tiles, not special tiles)
        if (cell.tileTypeId == null) {
          // Get random spawnable tile (excludes special tiles 101-105)
          final tileDef = _getRandomSpawnableTile();
          if (tileDef != null) {
            cell.tileTypeId = tileDef.id;
            cell.tileInstanceId = getNextInstanceId();
          } else {
            DebugLogger.warn('No spawnable tile available for refill',
                category: 'Refill');
          }
        }
      }
    }
  }

  /// Check if any special tile (101-105) exists on the board
  bool hasAnySpecialTile() {
    return BoardSolvability.hasAnySpecialTile(gridModel);
  }

  /// Check if any possible move exists on the board
  /// Uses same validity rules as attemptSwap: line match, 2x2 block, or special tile
  bool hasPossibleMove() {
    return BoardSolvability.hasPossibleMove(
      gridModel: gridModel,
      tileSpawner: _tileSpawner,
      canSwap: canSwap,
      detectMatches: detectMatches,
    );
  }

  /// Ensure board is solvable, or shuffle if no moves exist
  /// ONLY shuffles if: (1) no special tiles AND (2) no possible moves
  /// onNoMovesDetected: optional callback invoked when no moves detected (for showing modal)
  Future<void> ensureSolvableOrShuffle({
    required Future<void> Function() onSync,
    Future<void> Function()? onNoMovesDetected,
  }) async {
    // Never shuffle if special tiles exist
    if (hasAnySpecialTile()) {
      DebugLogger.boardController('Shuffle skipped (special tile present)');
      return;
    }

    // Check if moves exist
    if (hasPossibleMove()) {
      return; // Board is solvable
    }

    DebugLogger.boardController('No moves detected → shuffle');

    // Notify caller that no moves were detected (for showing modal)
    if (onNoMovesDetected != null) {
      await onNoMovesDetected();
    }

    // Collect all playable cells with tiles (exclude blocked cells)
    // Blocked cells cannot be swapped, so shuffling them won't help
    final playableCells = <Coord>[];
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final cell = gridModel.cells[row][col];
        if (cell.bedId != null && cell.bedId != -1 && cell.tileTypeId != null && !cell.isBlocked) {
          playableCells.add(Coord(row, col));
        }
      }
    }

    if (playableCells.isEmpty) {
      DebugLogger.warn('No playable cells to shuffle', category: 'Shuffle');
      return;
    }

    // Extract current tiles (typeId, instanceId pairs)
    final tiles = playableCells.map((coord) {
      final cell = gridModel.cells[coord.row][coord.col];
      return (typeId: cell.tileTypeId!, instanceId: cell.tileInstanceId!);
    }).toList();

    // Try to shuffle up to 50 times
    const maxShuffleAttempts = 50;
    bool shuffleSuccess = false;

    for (int attempt = 1; attempt <= maxShuffleAttempts; attempt++) {
      // Shuffle tiles
      tiles.shuffle(_rng);

      // Apply shuffle to grid
      for (int i = 0; i < playableCells.length; i++) {
        final coord = playableCells[i];
        final cell = gridModel.cells[coord.row][coord.col];
        cell.tileTypeId = tiles[i].typeId;
        cell.tileInstanceId = tiles[i].instanceId;
      }

      // Check validity
      bool hasMatches = detectMatches().hasMatches;
      bool hasMove = hasPossibleMove();

      // Valid if: (allowInitialMatches OR no matches) AND has possible move
      bool isValid = (stageData.allowInitialMatches || !hasMatches) && hasMove;

      if (isValid) {
        DebugLogger.boardController(
            'Shuffle successful after $attempt attempt(s)');
        shuffleSuccess = true;
        break;
      }
    }

    // Fallback: reroll all tiles if shuffle failed
    if (!shuffleSuccess) {
      DebugLogger.warn(
          'Shuffle failed after $maxShuffleAttempts attempts, using reroll fallback',
          category: 'Shuffle');

      // Reroll until no matches (if needed)
      if (!stageData.allowInitialMatches) {
        int rerollCount = 0;
        const maxRerolls = 50;
        while (rerollCount < maxRerolls) {
          // Reroll all playable cells
          for (final coord in playableCells) {
            final cell = gridModel.cells[coord.row][coord.col];
            final tileDef = _getRandomSpawnableTile();
            if (tileDef != null) {
              cell.tileTypeId = tileDef.id;
              cell.tileInstanceId = getNextInstanceId();
            }
          }

          if (!detectMatches().hasMatches) break;
          rerollCount++;
        }
      } else {
        // Just reroll once if matches are allowed
        for (final coord in playableCells) {
          final cell = gridModel.cells[coord.row][coord.col];
          final tileDef = _getRandomSpawnableTile();
          if (tileDef != null) {
            cell.tileTypeId = tileDef.id;
            cell.tileInstanceId = getNextInstanceId();
          }
        }
      }

      // Ensure has possible move
      int moveCheckCount = 0;
      const maxMoveChecks = 50;
      while (!hasPossibleMove() && moveCheckCount < maxMoveChecks) {
        // Reroll one random cell and check again
        final randomCoord = playableCells[_rng!.nextInt(playableCells.length)];
        final cell = gridModel.cells[randomCoord.row][randomCoord.col];
        final tileDef = _getRandomSpawnableTile();
        if (tileDef != null) {
          cell.tileTypeId = tileDef.id;
          cell.tileInstanceId = getNextInstanceId();
        }
        moveCheckCount++;
      }

      DebugLogger.boardController('Reroll fallback complete');
    }

    // Sync UI once after shuffle/reroll
    await onSync();
  }

  /// Check if a swap would be valid (create line match, 2x2 block, or involve special tile)
  /// Does NOT mutate the grid - simulates the swap
  bool _willSwapBeValid(Coord a, Coord b) {
    // Check if either swapped cell contains a special tile (101-105)
    // Read current state (before swap)
    final hasSpecialTile = _coordHasSpecial(a) || _coordHasSpecial(b);
    if (hasSpecialTile) {
      return true; // Special tile swaps are always valid
    }

    // Create a simulated type getter that returns swapped types
    int? getSimulatedTypeId(Coord coord) {
      if (coord.row < 0 ||
          coord.row >= rows ||
          coord.col < 0 ||
          coord.col >= cols) {
        return null;
      }
      final cell = gridModel.cells[coord.row][coord.col];
      if (cell.bedId == null || cell.bedId! == -1) return null; // Void cell

      // Simulate swap: if coord is a or b, return the other's type
      if (coord == a) {
        return gridModel.cells[b.row][b.col].tileTypeId;
      } else if (coord == b) {
        return gridModel.cells[a.row][a.col].tileTypeId;
      } else {
        return cell.tileTypeId;
      }
    }

    // Check if swap would create line match at either swapped position
    if (_wouldMakeLineMatchAt(a, getSimulatedTypeId) ||
        _wouldMakeLineMatchAt(b, getSimulatedTypeId)) {
      return true;
    }

    // Check if swap would create 2x2 block around swap
    if (_wouldMake2x2AroundSwap(a, b, getSimulatedTypeId)) {
      return true;
    }

    return false; // No valid configuration found
  }

  /// Check if a coord would be part of a line match (>=3) using simulated types
  /// simTypeGetter: function that returns tileTypeId at a coord (simulating swap state)
  bool _wouldMakeLineMatchAt(Coord center, int? Function(Coord) simTypeGetter) {
    final centerType = simTypeGetter(center);
    if (centerType == null || _isSpecial(centerType)) {
      return false; // Ignore void/special
    }

    // Check horizontal line through center
    int hCount = 1; // Count center itself
    // Count left
    for (int c = center.col - 1; c >= 0; c--) {
      final coord = Coord(center.row, c);
      final typeId = simTypeGetter(coord);
      if (typeId == centerType && !_isSpecial(typeId)) {
        hCount++;
      } else {
        break;
      }
    }
    // Count right
    for (int c = center.col + 1; c < cols; c++) {
      final coord = Coord(center.row, c);
      final typeId = simTypeGetter(coord);
      if (typeId == centerType && !_isSpecial(typeId)) {
        hCount++;
      } else {
        break;
      }
    }
    if (hCount >= 3) return true;

    // Check vertical line through center
    int vCount = 1; // Count center itself
    // Count up
    for (int r = center.row - 1; r >= 0; r--) {
      final coord = Coord(r, center.col);
      final typeId = simTypeGetter(coord);
      if (typeId == centerType && !_isSpecial(typeId)) {
        vCount++;
      } else {
        break;
      }
    }
    // Count down
    for (int r = center.row + 1; r < rows; r++) {
      final coord = Coord(r, center.col);
      final typeId = simTypeGetter(coord);
      if (typeId == centerType && !_isSpecial(typeId)) {
        vCount++;
      } else {
        break;
      }
    }
    if (vCount >= 3) return true;

    return false;
  }

  /// Check if swap would create a 2x2 block around the swap
  /// simTypeGetter: function that returns tileTypeId at a coord (simulating swap state)
  bool _wouldMake2x2AroundSwap(
      Coord a, Coord b, int? Function(Coord) simTypeGetter) {
    // Get all 2x2 blocks that overlap with either swapped position
    final blocksToCheck = <Set<Coord>>[];

    // Helper to add 2x2 block if valid
    void tryAdd2x2(int topRow, int leftCol) {
      if (topRow < 0 ||
          topRow >= rows - 1 ||
          leftCol < 0 ||
          leftCol >= cols - 1) {
        return;
      }

      final block = {
        Coord(topRow, leftCol),
        Coord(topRow, leftCol + 1),
        Coord(topRow + 1, leftCol),
        Coord(topRow + 1, leftCol + 1),
      };

      // Only check blocks that include at least one swapped position
      if (block.contains(a) || block.contains(b)) {
        blocksToCheck.add(block);
      }
    }

    // Generate all 2x2 blocks around a
    for (int dr = -1; dr <= 0; dr++) {
      for (int dc = -1; dc <= 0; dc++) {
        tryAdd2x2(a.row + dr, a.col + dc);
      }
    }

    // Generate all 2x2 blocks around b (avoid duplicates)
    for (int dr = -1; dr <= 0; dr++) {
      for (int dc = -1; dc <= 0; dc++) {
        tryAdd2x2(b.row + dr, b.col + dc);
      }
    }

    // Check each block
    for (final block in blocksToCheck) {
      // Get type of first playable cell in block
      int? blockType;
      bool allSameType = true;
      bool allPlayable = true;

      for (final coord in block) {
        final typeId = simTypeGetter(coord);

        // Check if playable
        if (coord.row < 0 ||
            coord.row >= rows ||
            coord.col < 0 ||
            coord.col >= cols) {
          allPlayable = false;
          break;
        }
        final cell = gridModel.cells[coord.row][coord.col];
        if (cell.bedId == null || cell.bedId == -1) {
          allPlayable = false;
          break;
        }

        // Check type
        if (typeId == null || _isSpecial(typeId)) {
          allPlayable = false;
          break;
        }

        if (blockType == null) {
          blockType = typeId;
        } else if (blockType != typeId) {
          allSameType = false;
          break;
        }
      }

      if (allPlayable && allSameType && blockType != null) {
        return true; // Found valid 2x2 block
      }
    }

    return false;
  }

  /// Process a swap attempt: swap -> check matches -> swap back if invalid -> cascade if valid
  /// Returns true if swap was valid and cascades were triggered
  /// Note: Calls onSync callback after each stage for animations (can be async)
  /// onMatchCleared: Optional callback to spawn particles/effects when matches are cleared (receives MatchResult)
  /// onCellsCleared: Optional callback for combo clears to spawn particles (receives Set&lt;Coord&gt;)
  /// onSpecialActivated: Optional callback to trigger VFX for activated special tiles
  ///   Receives: (Map&lt;Coord, int&gt; coord -&gt; tileTypeId, Map&lt;Coord, ({Coord? targetCoord})&gt; metadata)
  Future<bool> attemptSwap(
    Coord a,
    Coord b, {
    Coord?
        chosenCoord, // The coord the user started dragging from (dragStartCoord)
    required Future<void> Function() onSync,
    Future<void> Function(MatchResult)? onMatchCleared,
    Future<void> Function(Set<Coord>)? onCellsCleared,
    Future<void> Function(Map<Coord, int>,
            Map<Coord, ({Coord? targetCoord, Set<Coord>? activationCells})>)?
        onSpecialActivated,
    Future<void> Function()? onNoMovesDetected,
  }) async {
    if (!canSwap(a, b)) {
      DebugLogger.swap('Invalid swap: cells at $a and $b cannot be swapped');
      return false;
    }

    DebugLogger.swap('Attempting swap: $a <-> $b');

    // Check if swap will be valid (WITHOUT mutating grid)
    final willBeValid = _willSwapBeValid(a, b);

    // ✅ Play swipe ONLY for invalid swaps (immediate feedback)
    if (!willBeValid) {
      sfxManager.playConfigured(SfxType.swipe);
    }

    // Perform swap (state change for renderer)
    swapCells(a, b);

    // Show swap animation
    await onSync(); // Sync to show swap animation (awaited to ensure moves complete)
    await Future.delayed(
        const Duration(milliseconds: 150)); // Delay for swap animation

    // Check for matches after swap
    final matchResult = detectMatches();

    // Check for 2x2 block around swap (compute once and reuse)
    final blockCellsSet = _tileSpawner.detect2x2AroundSwap(gridModel, a, b);

    // Check if either swapped cell contains a special tile (101-105)
    final hasSpecialTile = _coordHasSpecial(a) || _coordHasSpecial(b);

    // If no matches AND no 2x2 block AND no special tile, swap back to original state
    if (!matchResult.hasMatches && blockCellsSet == null && !hasSpecialTile) {
      DebugLogger.swap(
          'Invalid swap: no matches, no 2x2 block, and no special tile found, swapping back');

      swapCells(a, b); // Swap back to restore original positions

      await onSync(); // Sync to show swap-back animation (awaited to ensure moves complete)
      await Future.delayed(
          const Duration(milliseconds: 150)); // Delay for swap-back animation
      return false; // Swap was invalid, no cascades triggered
    }

    // Special tile swap: if special tile found but no matches/2x2, run special-only clear
    if (hasSpecialTile && !matchResult.hasMatches && blockCellsSet == null) {
      DebugLogger.swap(
          'Valid swap: special tile found (no matches, no 2x2 block)');

      // Run special-only clear with empty MatchResult
      final emptyMatchResult = MatchResult(matches: []);
      await clearMatchedCells(
        emptyMatchResult,
        swapA: a,
        swapB: b,
        chosenCoord: chosenCoord,
        onSpecialActivated: onSpecialActivated,
        onSync: onSync,
      );

      await onSync(); // Sync to show tiles disappear
      await Future.wait([
        _playPendingBlockerBreaks(),
        Future.delayed(const Duration(milliseconds: 180)),
      ]); // Delay for clear animation

      // Apply gravity
      applyGravity();
      await onSync(); // Sync to show tiles fall
      await Future.delayed(
          const Duration(milliseconds: 300)); // Delay for fall animation

      // Refill
      refill();
      await onSync(); // Sync to show new tiles spawn
      await Future.delayed(
          const Duration(milliseconds: 150)); // Delay for spawn animation

      // Check for solvability after refill (shuffle if no possible moves and no special tiles)
      await ensureSolvableOrShuffle(
        onSync: onSync,
        onNoMovesDetected: onNoMovesDetected,
      );

      // Continue with normal cascade loop for further line matches that may have formed
      await runCascade(
        onSync: onSync,
        onMatchCleared: onMatchCleared,
        onSpecialActivated: onSpecialActivated,
        swapA: null, // Don't use swap coords for subsequent cascades
        swapB: null,
        chosenCoord: null, // Don't use chosenCoord for subsequent cascades
      );

      return true;
    }

    // Valid swap - either matches found or 2x2 block found

    // If 2x2 block found but no line matches, handle 2x2 block first
    if (blockCellsSet != null && !matchResult.hasMatches) {
      DebugLogger.swap('Valid swap: 2x2 block found (no line matches)');

      sfxManager.playConfigured(SfxType.bloop); // Play bloop for valid swap

      // Get the 2x2 block cells and tileTypeId for creating a fake match (reuse blockCellsSet)
      final blockCells = blockCellsSet;
      // Get tileTypeId from first cell in block (all should have same type)
      final firstBlockCell = blockCells.first;
      final blockTileTypeId =
          gridModel.cells[firstBlockCell.row][firstBlockCell.col].tileTypeId!;

      // Create a fake match for the 2x2 block so particle callback gets the correct data
      final blockMatch =
          Match(cells: blockCells.toList(), tileTypeId: blockTileTypeId);
      final blockMatchResult = MatchResult(matches: [blockMatch]);

      // Arm match SFX from the 2x2 block match (will play on clear)
      _armMatchSfx();

      // Run one-time clear step for 2x2 block
      await clearMatchedCells(
        blockMatchResult,
        swapA: a,
        swapB: b,
        chosenCoord: chosenCoord,
        onSpecialActivated: onSpecialActivated,
        onSync: onSync,
      );

      // Spawn particles for cleared cells (if callback provided)
      if (onMatchCleared != null) {
        await onMatchCleared(blockMatchResult);
      }

      await onSync(); // Sync to show tiles disappear
      await Future.wait([
        _playPendingBlockerBreaks(),
        Future.delayed(const Duration(milliseconds: 180)),
      ]); // Delay for clear animation

      // Apply gravity
      applyGravity();
      await onSync(); // Sync to show tiles fall
      await Future.delayed(
          const Duration(milliseconds: 300)); // Delay for fall animation

      // Refill
      refill();
      await onSync(); // Sync to show new tiles spawn
      await Future.delayed(
          const Duration(milliseconds: 150)); // Delay for spawn animation

      // Continue with normal cascade loop for further line matches that may have formed
      await runCascade(
        onSync: onSync,
        onMatchCleared: onMatchCleared,
        onSpecialActivated: onSpecialActivated,
        swapA: null, // Don't use swap coords for subsequent cascades
        swapB: null,
        chosenCoord: null, // Don't use chosenCoord for subsequent cascades
      );

      return true;
    }

    // Valid swap - line matches found, proceed with normal cascade
    DebugLogger.swap('Valid swap: ${matchResult.matches.length} matches found');

    sfxManager.playConfigured(SfxType.bloop); // Play bloop for valid swap

    // Run cascade (will call onSync internally, and onMatchCleared for each match cleared)
    // Pass swap coordinates for special tile spawn location preference
    await runCascade(
      onSync: onSync,
      onMatchCleared: onMatchCleared,
      onSpecialActivated: onSpecialActivated,
      onNoMovesDetected: onNoMovesDetected,
      swapA: a,
      swapB: b,
      chosenCoord: chosenCoord, // Pass chosenCoord for first cascade
    );

    return true;
  }

  /// Run a full cascade: detect matches -> clear -> gravity -> refill
  /// Returns true if any matches were found and processed
  /// Safety cap: max 10 cascades to avoid infinite loops
  /// Note: Calls onSync after each stage for animation (can be async)
  /// onMatchCleared: Optional callback to spawn particles/effects when matches are cleared (receives MatchResult)
  /// onSpecialActivated: Optional callback to trigger VFX for activated special tiles
  ///   Receives: (Map&lt;Coord, int&gt; coord -&gt; tileTypeId, Map&lt;Coord, ({Coord? targetCoord})&gt; metadata)
  /// swapA, swapB: Optional swap coordinates for special tile spawn location preference (only used in first cascade)
  Future<bool> runCascade({
    required Future<void> Function() onSync,
    Future<void> Function(MatchResult)? onMatchCleared,
    Future<void> Function(Map<Coord, int>,
            Map<Coord, ({Coord? targetCoord, Set<Coord>? activationCells})>)?
        onSpecialActivated,
    Future<void> Function()? onNoMovesDetected,
    int maxCascades = 10,
    Coord? swapA,
    Coord? swapB,
    Coord?
        chosenCoord, // The coord the user started dragging from (dragStartCoord)
  }) async {
    int cascadeCount = 0;

    while (cascadeCount < maxCascades) {
      final matchResult = detectMatches();

      // Also check for 2x2 blocks that may have formed after gravity/refill
      final all2x2Blocks = _tileSpawner.detectAll2x2Blocks(gridModel);

      // If no line matches but 2x2 blocks found, handle them
      if (!matchResult.hasMatches && all2x2Blocks.isNotEmpty) {
        DebugLogger.cascade(
            'Cascade #${cascadeCount + 1}: ${all2x2Blocks.length} 2x2 block(s) found');
        cascadeCount++;

        // Process each 2x2 block
        for (final blockCells in all2x2Blocks) {
          // Get tileTypeId from first cell in block (all should have same type)
          final firstBlockCell = blockCells.first;
          final blockTileTypeId = gridModel
              .cells[firstBlockCell.row][firstBlockCell.col].tileTypeId!;

          // Create a fake match for the 2x2 block
          final blockMatch =
              Match(cells: blockCells.toList(), tileTypeId: blockTileTypeId);
          final blockMatchResult = MatchResult(matches: [blockMatch]);

          // Arm match SFX from the 2x2 block match (will play on clear)
          _armMatchSfx();

          // Clear the 2x2 block
          await clearMatchedCells(
            blockMatchResult,
            swapA: null, // No swap coords during cascade
            swapB: null,
            chosenCoord: null, // No chosen coord during cascade
            onSpecialActivated: onSpecialActivated,
            onSync: onSync,
          );

          // Spawn particles for cleared cells (if callback provided)
          if (onMatchCleared != null) {
            await onMatchCleared(blockMatchResult);
          }

          await onSync(); // Sync to show tiles disappear
          await Future.wait([
            _playPendingBlockerBreaks(),
            Future.delayed(const Duration(milliseconds: 180)),
          ]); // Delay for clear animation
        }

        // Apply gravity after clearing 2x2 blocks
        applyGravity();
        await onSync(); // Sync to show tiles fall
        await Future.delayed(
            const Duration(milliseconds: 300)); // Delay for fall animation

        // Refill
        refill();
        await onSync(); // Sync to show new tiles spawn
        await Future.delayed(
            const Duration(milliseconds: 150)); // Delay for spawn animation

        // Check for solvability after refill (shuffle if no possible moves and no special tiles)
        await ensureSolvableOrShuffle(
          onSync: onSync,
          onNoMovesDetected: onNoMovesDetected,
        );

        // Continue cascade loop to check for more matches/blocks
        continue;
      }

      if (!matchResult.hasMatches) {
        // No more matches or 2x2 blocks - cascade complete
        if (cascadeCount > 0) {
          DebugLogger.cascade('Completed after $cascadeCount cascade(s)');
        }
        return cascadeCount > 0;
      }

      cascadeCount++;
      DebugLogger.cascade(
          'Cascade #$cascadeCount: ${matchResult.matches.length} matches, ${matchResult.allMatchedCells.length} cells');

      // Arm match SFX (will play when tiles actually clear)
      _armMatchSfx();

      // Clear matched cells with special tile spawning
      // Only use swap coords for first cascade (from user swap), subsequent cascades use null
      // Note: clearMatchedCells handles sequential clearing for 101/102 internally
      await clearMatchedCells(
        matchResult,
        swapA: cascadeCount == 1 ? swapA : null,
        swapB: cascadeCount == 1 ? swapB : null,
        chosenCoord: cascadeCount == 1
            ? chosenCoord
            : null, // Only use chosenCoord on first cascade
        onSpecialActivated: onSpecialActivated,
        onSync: onSync,
      );

      // Note: onSync is called inside clearMatchedCells for sequential clears
      // For non-sequential clears, we need to call onSync here
      // But clearMatchedCells doesn't distinguish, so we'll call it after for consistency

      // Spawn particles for matched cells (if callback provided)
      if (onMatchCleared != null) {
        await onMatchCleared(matchResult);
      }

      await onSync(); // Sync to show tiles disappear (awaited to ensure removals complete)
      await Future.wait([
        _playPendingBlockerBreaks(),
        Future.delayed(const Duration(milliseconds: 180)),
      ]); // Delay for clear animation

      // Apply gravity
      applyGravity();
      await onSync(); // Sync to show tiles fall (awaited to ensure moves complete)
      await Future.delayed(const Duration(
          milliseconds: 300)); // Delay for fall animation (increased from 200)

      // Refill
      refill();
      await onSync(); // Sync to show new tiles spawn (awaited to ensure spawns complete)
      await Future.delayed(
          const Duration(milliseconds: 150)); // Delay for spawn animation

      // Check for solvability after refill (shuffle if no possible moves and no special tiles)
      await ensureSolvableOrShuffle(
        onSync: onSync,
        onNoMovesDetected: onNoMovesDetected,
      );
    }

    if (cascadeCount >= maxCascades) {
      DebugLogger.warn('Reached max cascade limit ($maxCascades)',
          category: 'Cascade');
    }

    return true;
  }

  /// Run combo steps sequentially, triggering VFX and clearing cells per step
  /// Returns activatedSpecials map (for compatibility with clearMatchedCells return type)
  Future<Map<Coord, int>> _runComboSteps({
    required SpecialComboResult comboResult,
    Coord? swapA,
    Coord? swapB,
    Future<void> Function(Map<Coord, int>,
            Map<Coord, ({Coord? targetCoord, Set<Coord>? activationCells})>)?
        onSpecialActivated,
    Future<void> Function()? onSync,
  }) async {
    final activatedSpecials = <Coord, int>{};

    // For 104+104 combo, track both centers to ensure neither is cleared until cleanup step
    Coord? step1CenterFor104Combo;
    Coord? step2CenterFor104Combo;
    if (comboResult.meta['combo'] == '104+104' &&
        swapA != null &&
        swapB != null) {
      // Find which coord will be Step 1's center and Step 2's center
      final activatedCoord = comboResult.activatedCoord;
      step1CenterFor104Combo = activatedCoord;
      step2CenterFor104Combo = (activatedCoord == swapA) ? swapB : swapA;
      DebugLogger.specialCombo(
          '104+104 combo detected: Step 1 center=$step1CenterFor104Combo, Step 2 center=$step2CenterFor104Combo');
    }

    // Iterate through combo steps in order with index
    for (int i = 0; i < comboResult.steps.length; i++) {
      final step = comboResult.steps[i];
      // Skip cleanup steps for VFX (they still clear cells)
      if (step.type != ComboStepType.cleanup && onSpecialActivated != null) {
        // For combo steps, bypass guards - use ComboStep as source of truth
        // This ensures VFX always plays even if tiles have been cleared/changed
        final bypassComboGuards = step.type != ComboStepType.cleanup;

        // Determine special type and metadata based on step type
        int specialTypeId;
        Coord? vfxCoord;
        Coord? targetCoord;
        Set<Coord>? activationCells;

        switch (step.type) {
          case ComboStepType.prehit:
            // DragonFly prehit (105)
            specialTypeId = 105;
            vfxCoord = step.center;
            targetCoord = step.randomTargetCoord;
            activationCells = null;
            break;

          case ComboStepType.lineRow:
            // Party Popper horizontal (101)
            specialTypeId = 101;
            vfxCoord = step.center;
            targetCoord = null;
            activationCells = step.cells;
            break;

          case ComboStepType.lineCol:
            // Party Popper vertical (102)
            specialTypeId = 102;
            vfxCoord = step.center;
            targetCoord = null;
            activationCells = step.cells;
            break;

          case ComboStepType.bomb3x3:
            // Firecracker (104)
            specialTypeId = 104;
            vfxCoord = step.center;
            targetCoord = null;
            activationCells = step.cells;
            DebugLogger.specialCombo(
                'bomb3x3 step: center=${step.center}, cells=${step.cells.length}, vfxCoord=$vfxCoord');
            break;

          case ComboStepType.colorAllOfType:
          case ComboStepType.clearAllRegular:
            // StickyRice color bomb (103) or clear all regular
            specialTypeId = 103;

            // Special case: 103+103 combo (clearAllRegular)
            // Check if this is a 103+103 combo by checking comboResult.meta
            bool duoVfxTriggered = false;
            if (comboResult.meta['combo'] == '103+103' &&
                swapA != null &&
                swapB != null) {
              // Trigger both tiles at once for duo VFX
              final coordA = swapA;
              final coordB = swapB;

              // Verify both coords have type 103
              if (_coordHasSpecialType(coordA, 103) &&
                  _coordHasSpecialType(coordB, 103)) {
                // Verify both have tileInstanceId
                final cellA = gridModel.cells[coordA.row][coordA.col];
                final cellB = gridModel.cells[coordB.row][coordB.col];

                if (cellA.tileInstanceId != null &&
                    cellB.tileInstanceId != null) {
                  // Trigger VFX with both coords
                  activatedSpecials[coordA] = 103;
                  activatedSpecials[coordB] = 103;
                  final stepMetadata = <Coord,
                      ({Coord? targetCoord, Set<Coord>? activationCells})>{
                    coordA: (
                      targetCoord: null,
                      activationCells: step.cells,
                    ),
                    coordB: (
                      targetCoord: null,
                      activationCells: step.cells,
                    ),
                  };
                  await onSpecialActivated(activatedSpecials, stepMetadata);
                  DebugLogger.specialCombo(
                      '103+103 combo: triggered duo VFX for both coords $coordA and $coordB');
                  duoVfxTriggered = true;
                  // Set vfxCoord to null to skip normal single-tile VFX path
                  vfxCoord = null;
                } else {
                  DebugLogger.warn(
                      '103+103 combo: missing tileInstanceId at $coordA or $coordB',
                      category: 'SpecialCombo');
                }
              } else {
                DebugLogger.warn(
                    '103+103 combo: coords $coordA or $coordB don\'t have type 103',
                    category: 'SpecialCombo');
              }
            }

            // Normal single-tile path (for colorAllOfType or if duo detection failed)
            if (!duoVfxTriggered) {
              // Select vfxCoord: step.center first, then swapA if it has 103, then swapB if it has 103
              if (step.center != null) {
                vfxCoord = step.center;
              } else if (swapA != null && _coordHasSpecialType(swapA, 103)) {
                vfxCoord = swapA;
              } else if (swapB != null && _coordHasSpecialType(swapB, 103)) {
                vfxCoord = swapB;
              } else {
                vfxCoord = null;
                DebugLogger.specialCombo(
                    'Skipping VFX for 103 step: no valid coord found (step.center=${step.center}, swapA=$swapA, swapB=$swapB)');
              }
            }
            targetCoord = null;
            activationCells = step.cells;
            break;

          case ComboStepType.cleanup:
            // Should not reach here due to check above, but handle for completeness
            continue;
        }

        // For combo steps, bypass guards and use step.center as source of truth
        // This ensures VFX always plays even if tiles have been cleared/changed
        Coord? validVfxCoord;
        if (bypassComboGuards) {
          // Bypass all guards - use step.center directly
          validVfxCoord = vfxCoord;
          if (validVfxCoord != null) {
            DebugLogger.specialCombo(
                'Bypassing guards for combo step: using vfxCoord=$validVfxCoord (type=$specialTypeId, step type=${step.type})');
          } else {
            DebugLogger.warn(
                'vfxCoord is null for combo step ${step.type}, skipping VFX',
                category: 'SpecialCombo');
          }
        } else {
          // Guard: Verify tile exists and matches expected type before triggering VFX
          // If vfxCoord doesn't have the expected tile, try the other swapped coord
          if (vfxCoord != null) {
            DebugLogger.specialCombo(
                'Checking VFX coord: $vfxCoord for type $specialTypeId (step type: ${step.type})');
            // Check if tile at vfxCoord exists and matches expected type
            if (_coordHasSpecialType(vfxCoord, specialTypeId)) {
              validVfxCoord = vfxCoord;
              DebugLogger.specialCombo(
                  'VFX coord $vfxCoord validated: has type $specialTypeId');
            } else if (swapA != null && swapB != null) {
              // Try the other swapped coord (one of them should be the real special)
              final otherCoord = (vfxCoord == swapA) ? swapB : swapA;
              DebugLogger.specialCombo(
                  'Tile at $vfxCoord doesn\'t match type $specialTypeId, trying other swap coord $otherCoord');
              if (_coordHasSpecialType(otherCoord, specialTypeId)) {
                validVfxCoord = otherCoord;
                DebugLogger.specialCombo(
                    'Using other swap coord $otherCoord instead (has type $specialTypeId)');
              } else {
                final cellAtVfx = gridModel.cells[vfxCoord.row][vfxCoord.col];
                final cellAtOther =
                    gridModel.cells[otherCoord.row][otherCoord.col];
                DebugLogger.warn(
                    'Neither swap coord has expected type: vfxCoord=$vfxCoord (type=${cellAtVfx.tileTypeId}, instanceId=${cellAtVfx.tileInstanceId}), otherCoord=$otherCoord (type=${cellAtOther.tileTypeId}, instanceId=${cellAtOther.tileInstanceId})',
                    category: 'SpecialCombo');
              }
            } else {
              final cellAtVfx = gridModel.cells[vfxCoord.row][vfxCoord.col];
              DebugLogger.warn(
                  'Tile at $vfxCoord doesn\'t match type $specialTypeId (actual type=${cellAtVfx.tileTypeId}, instanceId=${cellAtVfx.tileInstanceId}) and no swap coords available',
                  category: 'SpecialCombo');
            }
          } else {
            DebugLogger.warn(
                'vfxCoord is null for step type ${step.type}, skipping VFX',
                category: 'SpecialCombo');
          }

          // Verify tileInstanceId exists at validVfxCoord (required for VFX)
          if (validVfxCoord != null) {
            final cell = gridModel.cells[validVfxCoord.row][validVfxCoord.col];
            if (cell.tileInstanceId == null) {
              DebugLogger.warn(
                  'Tile at $validVfxCoord has no tileInstanceId, skipping VFX for step ${step.type}',
                  category: 'SpecialCombo');
              validVfxCoord = null;
            } else {
              DebugLogger.specialCombo(
                  'Valid VFX coord: $validVfxCoord, type=$specialTypeId, instanceId=${cell.tileInstanceId}');
            }
          }
        }

        // Trigger VFX callback if we have a valid coord
        if (validVfxCoord != null) {
          activatedSpecials[validVfxCoord] = specialTypeId;
          final stepMetadata =
              <Coord, ({Coord? targetCoord, Set<Coord>? activationCells})>{
            validVfxCoord: (
              targetCoord: targetCoord,
              activationCells: activationCells,
            ),
          };
          await onSpecialActivated(
              {validVfxCoord: specialTypeId}, stepMetadata);
          DebugLogger.specialCombo(
              'Triggered VFX for combo step: coord=$validVfxCoord, type=$specialTypeId');
        }
      }

      // Clear cells for this step
      // IMPORTANT: For 104+104 combo, do NOT clear either bomb center until cleanup step
      // Both bomb tiles must remain visible until BOTH VFX have finished
      final is104ComboBombStep = comboResult.meta['combo'] == '104+104' &&
          step.type == ComboStepType.bomb3x3;

      // Filter out bomb centers for 104+104 combo
      final cellsToClear = step.cells.where((coord) {
        if (is104ComboBombStep) {
          if ((step1CenterFor104Combo != null &&
                  coord == step1CenterFor104Combo) ||
              (step2CenterFor104Combo != null &&
                  coord == step2CenterFor104Combo)) {
            DebugLogger.specialCombo(
                'Skipping clearing of bomb center $coord in 104+104 combo (will clear in cleanup step)');
            return false; // Skip clearing this coord - preserve for VFX
          }
        }
        return true;
      }).toSet();

      // Emit cleared cells callback and clear them
      await _emitCellsCleared(cellsToClear);

      // Sync and delay for visuals
      if (onSync != null) {
        await onSync();
        await Future.delayed(
            const Duration(milliseconds: 90)); // 60-120ms range, using 90ms
      }
    }

    DebugLogger.specialCombo(
        'Combo steps completed: ${comboResult.steps.length} steps processed');
    return activatedSpecials;
  }

  /// Place a special tile at the specified coordinate
  /// Replaces the tileTypeId but keeps tileInstanceId unchanged
  /// Returns true if successful, false if validation fails
  bool placeSpecialAt(Coord coord, int powerTypeId) {
    // Validate coordinate bounds
    if (coord.row < 0 ||
        coord.row >= rows ||
        coord.col < 0 ||
        coord.col >= cols) {
      DebugLogger.warn('placeSpecialAt: coord $coord is out of bounds',
          category: 'BoardController');
      return false;
    }

    final cell = gridModel.cells[coord.row][coord.col];

    // Validate: must be playable (bedId != -1)
    if (cell.bedId == null || cell.bedId == -1) {
      DebugLogger.warn(
          'placeSpecialAt: coord $coord is not playable (bedId=${cell.bedId})',
          category: 'BoardController');
      return false;
    }

    // Validate: must have an existing tile (tileTypeId != null)
    if (cell.tileTypeId == null) {
      DebugLogger.warn(
          'placeSpecialAt: coord $coord has no tile (tileTypeId is null)',
          category: 'BoardController');
      return false;
    }

    // Validate: can only replace regular tiles (tileTypeId < 101)
    if (cell.tileTypeId! >= 101) {
      DebugLogger.warn(
          'placeSpecialAt: coord $coord already has special tile (typeId=${cell.tileTypeId})',
          category: 'BoardController');
      return false;
    }

    // Validate: powerTypeId must be a special tile (101-105)
    if (powerTypeId < 101 || powerTypeId > 105) {
      DebugLogger.warn(
          'placeSpecialAt: invalid powerTypeId $powerTypeId (must be 101-105)',
          category: 'BoardController');
      return false;
    }

    // Ensure tileInstanceId exists (should always exist for playable cells with tiles)
    if (cell.tileInstanceId == null) {
      DebugLogger.warn(
          'placeSpecialAt: coord $coord has no tileInstanceId, assigning new one',
          category: 'BoardController');
      cell.tileInstanceId = getNextInstanceId();
    }

    // Replace tileTypeId but keep tileInstanceId unchanged
    final oldTypeId = cell.tileTypeId;
    cell.tileTypeId = powerTypeId;

    DebugLogger.log(
        'placeSpecialAt: replaced tile at $coord from typeId=$oldTypeId to typeId=$powerTypeId (instanceId=${cell.tileInstanceId})',
        category: 'BoardController');
    return true;
  }
}
