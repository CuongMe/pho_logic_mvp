import 'dart:math';
import '../model/coord.dart';
import '../model/grid_model.dart';
import '../utils/debug_logger.dart';

/// Step type for combo resolution
enum ComboStepType {
  prehit,          // DragonFly pre-hit (105)
  lineRow,         // Party Popper horizontal (101)
  lineCol,         // Party Popper vertical (102)
  bomb3x3,         // Firecracker (104)
  colorAllOfType,  // StickyRice color bomb (103)
  clearAllRegular, // Clear all regular tiles
  cleanup,         // Cleanup step (clear specials)
}

/// A single step in a combo sequence
class ComboStep {
  final ComboStepType type;
  final Coord? center;            // where effect originates (special coord)
  final Coord? randomTargetCoord; // for 105 prehit
  final int? randomTileTypeId;    // for 103 random type selection or 105+103 derived type
  final Set<Coord> cells;         // cells to clear in THIS step (already filtered: in-bounds + playable + any skip rules)

  ComboStep({
    required this.type,
    this.center,
    this.randomTargetCoord,
    this.randomTileTypeId,
    required this.cells,
  });
}

/// Result of special combo resolution
class SpecialComboResult {
  final bool isCombo;                   // true only if BOTH swapped tiles are specials (101..105)
  final Coord? activatedCoord;          // chosenCoord if equals a or b, else default to a
  final int? activatedTypeId;           // tileTypeId at activatedCoord BEFORE swap
  final int? otherTypeId;               // type of the other swapped special BEFORE swap
  final List<ComboStep> steps;          // ordered steps, for VFX + sequential clear
  final Set<Coord> cellsToClear;        // union of all steps' cells + includes cleanup steps if they clear specials
  final Map<String, Object?> meta;      // simple metadata for VFX (e.g., {"combo":"101+102","prehitTarget":Coord,...})

  SpecialComboResult({
    required this.isCombo,
    this.activatedCoord,
    this.activatedTypeId,
    this.otherTypeId,
    required this.steps,
    required this.cellsToClear,
    required this.meta,
  });
}

/// Resolves special+special swap combos
/// Pure logic - no Flame components, no rendering
class SpecialComboResolver {
  final Random rng;

  SpecialComboResolver({required this.rng});

  /// Resolve a special combo from two swap coordinates
  SpecialComboResult resolveCombo({
    required GridModel grid,
    required Coord a,
    required Coord b,
    Coord? chosenCoord,
  }) {
    // Read types BEFORE swap
    final typeA = _getTileType(grid, a);
    final typeB = _getTileType(grid, b);

    // Check if both are specials
    if (!isSpecial(typeA) || !isSpecial(typeB)) {
      DebugLogger.specialCombo('Not a combo: typeA=$typeA, typeB=$typeB');
      return SpecialComboResult(
        isCombo: false,
        steps: [],
        cellsToClear: {},
        meta: {},
      );
    }

    DebugLogger.specialCombo('Combo detected: typeA=$typeA, typeB=$typeB');

    // Determine activated coord
    final activatedCoord = _determineActivatedCoord(a, b, chosenCoord);
    final otherCoord = (activatedCoord == a) ? b : a;
    final activatedTypeId = (activatedCoord == a) ? typeA : typeB;
    final otherTypeId = (activatedCoord == a) ? typeB : typeA;

    DebugLogger.specialCombo('Activated coord: $activatedCoord (type=$activatedTypeId), other: $otherCoord (type=$otherTypeId)');

    // Build combo steps based on types
    final steps = <ComboStep>[];
    final allCellsToClear = <Coord>{};

    // Dispatch to combo rule handlers
    if (activatedTypeId == otherTypeId) {
      // SAME + SAME combos
      _buildSameSameCombo(
        grid: grid,
        typeId: activatedTypeId!,
        coordA: a,
        coordB: b,
        activatedCoord: activatedCoord,
        steps: steps,
        allCellsToClear: allCellsToClear,
      );
    } else {
      // CROSS combos
      _buildCrossCombo(
        grid: grid,
        activatedTypeId: activatedTypeId!,
        otherTypeId: otherTypeId!,
        activatedCoord: activatedCoord,
        otherCoord: otherCoord,
        steps: steps,
        allCellsToClear: allCellsToClear,
      );
    }

    // Always add cleanup step
    final cleanupCells = <Coord>{a, b};
    steps.add(ComboStep(
      type: ComboStepType.cleanup,
      center: null,
      cells: cleanupCells,
    ));
    allCellsToClear.addAll(cleanupCells);

    // Build metadata
    final meta = <String, Object?>{
      'combo': '$activatedTypeId+$otherTypeId',
    };
    if (steps.any((s) => s.randomTargetCoord != null)) {
      final prehitSteps = steps.where((s) => s.type == ComboStepType.prehit).toList();
      if (prehitSteps.isNotEmpty) {
        meta['prehitTargets'] = prehitSteps.map((s) => s.randomTargetCoord).toList();
      }
    }
    if (steps.any((s) => s.randomTileTypeId != null)) {
      final colorSteps = steps.where((s) => s.type == ComboStepType.colorAllOfType).toList();
      if (colorSteps.isNotEmpty) {
        meta['colorTypeId'] = colorSteps.first.randomTileTypeId;
      }
    }

    DebugLogger.specialCombo('Combo resolved: ${steps.length} steps, ${allCellsToClear.length} total cells to clear');

    return SpecialComboResult(
      isCombo: true,
      activatedCoord: activatedCoord,
      activatedTypeId: activatedTypeId,
      otherTypeId: otherTypeId,
      steps: steps,
      cellsToClear: allCellsToClear,
      meta: meta,
    );
  }

  // ===== Helper Functions =====

  /// Check if a coord is playable (in bounds and not void)
  bool isPlayable(GridModel grid, Coord c) {
    if (c.row < 0 || c.row >= grid.rows || c.col < 0 || c.col >= grid.cols) {
      return false;
    }
    final cell = grid.cells[c.row][c.col];
    return cell.bedId != null && cell.bedId! != -1;
  }

  /// Check if a tile type is special (101-105)
  bool isSpecial(int? id) {
    return id != null && id >= 101 && id <= 105;
  }

  /// Check if a tile type is regular (< 101)
  bool isRegular(int? id) {
    return id != null && id < 101;
  }

  /// Get tile type at coord (null if out of bounds or no tile)
  int? _getTileType(GridModel grid, Coord c) {
    if (!isPlayable(grid, c)) return null;
    return grid.cells[c.row][c.col].tileTypeId;
  }

  /// Get all cells in a row (playable only, optionally skip specials)
  Set<Coord> rowCells(GridModel grid, int row, {bool skipSpecials = true}) {
    final cells = <Coord>{};
    if (row < 0 || row >= grid.rows) return cells;

    for (int col = 0; col < grid.cols; col++) {
      final coord = Coord(row, col);
      if (!isPlayable(grid, coord)) continue;

      final cell = grid.cells[row][col];
      if (skipSpecials && isSpecial(cell.tileTypeId)) continue;

      cells.add(coord);
    }
    return cells;
  }

  /// Get all cells in a column (playable only, optionally skip specials)
  Set<Coord> colCells(GridModel grid, int col, {bool skipSpecials = true}) {
    final cells = <Coord>{};
    if (col < 0 || col >= grid.cols) return cells;

    for (int row = 0; row < grid.rows; row++) {
      final coord = Coord(row, col);
      if (!isPlayable(grid, coord)) continue;

      final cell = grid.cells[row][col];
      if (skipSpecials && isSpecial(cell.tileTypeId)) continue;

      cells.add(coord);
    }
    return cells;
  }

  /// Get 3x3 bomb cells centered on coord (playable only, can include specials)
  Set<Coord> bomb3x3(GridModel grid, Coord center) {
    final cells = <Coord>{};
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        final row = center.row + dr;
        final col = center.col + dc;
        final coord = Coord(row, col);
        if (isPlayable(grid, coord)) {
          cells.add(coord);
        }
      }
    }
    return cells;
  }

  /// Get all regular tile coords in row-major order
  List<Coord> allRegularCoords(GridModel grid) {
    final coords = <Coord>[];
    for (int row = 0; row < grid.rows; row++) {
      for (int col = 0; col < grid.cols; col++) {
        final coord = Coord(row, col);
        if (!isPlayable(grid, coord)) continue;
        final cell = grid.cells[row][col];
        if (isRegular(cell.tileTypeId)) {
          coords.add(coord);
        }
      }
    }
    return coords;
  }

  /// Pick a random regular tileTypeId from the board (row-major list then rng)
  int? pickRandomRegularTypeId(GridModel grid) {
    final typeIds = <int>{};
    for (int row = 0; row < grid.rows; row++) {
      for (int col = 0; col < grid.cols; col++) {
        final coord = Coord(row, col);
        if (!isPlayable(grid, coord)) continue;
        final cell = grid.cells[row][col];
        if (isRegular(cell.tileTypeId)) {
          typeIds.add(cell.tileTypeId!);
        }
      }
    }
    if (typeIds.isEmpty) return null;
    final sortedTypes = typeIds.toList()..sort();
    return sortedTypes[rng.nextInt(sortedTypes.length)];
  }

  /// Pick a random regular coord (row-major list then rng), excluding specified coords
  Coord? pickRandomRegularCoord(GridModel grid, {Set<Coord> exclude = const <Coord>{}}) {
    final candidates = allRegularCoords(grid)
        .where((c) => !exclude.contains(c))
        .toList();
    if (candidates.isEmpty) return null;
    return candidates[rng.nextInt(candidates.length)];
  }

  /// Determine which coord is activated (chosenCoord if matches a or b, else default to a)
  Coord _determineActivatedCoord(Coord a, Coord b, Coord? chosenCoord) {
    if (chosenCoord == a) return a;
    if (chosenCoord == b) return b;
    return a; // default
  }

  // ===== Combo Rule Builders =====

  /// Build SAME + SAME combo steps
  void _buildSameSameCombo({
    required GridModel grid,
    required int typeId,
    required Coord coordA,
    required Coord coordB,
    required Coord activatedCoord,
    required List<ComboStep> steps,
    required Set<Coord> allCellsToClear,
  }) {
    switch (typeId) {
      case 101: // 101+101
        // step1: lineRow at first 101 coord
        final step1Cells = rowCells(grid, activatedCoord.row, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineRow,
          center: activatedCoord,
          cells: step1Cells,
        ));
        allCellsToClear.addAll(step1Cells);
        DebugLogger.specialCombo('Step 1 (101+101): lineRow at $activatedCoord, ${step1Cells.length} cells');

        // step2: lineRow at other 101 coord
        final otherCoord = (activatedCoord == coordA) ? coordB : coordA;
        final step2Cells = rowCells(grid, otherCoord.row, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineRow,
          center: otherCoord,
          cells: step2Cells,
        ));
        allCellsToClear.addAll(step2Cells);
        DebugLogger.specialCombo('Step 2 (101+101): lineRow at $otherCoord, ${step2Cells.length} cells');
        break;

      case 102: // 102+102
        // step1: lineCol at first 102 coord
        final step1Cells = colCells(grid, activatedCoord.col, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineCol,
          center: activatedCoord,
          cells: step1Cells,
        ));
        allCellsToClear.addAll(step1Cells);
        DebugLogger.specialCombo('Step 1 (102+102): lineCol at $activatedCoord, ${step1Cells.length} cells');

        // step2: lineCol at other 102 coord
        final otherCoord = (activatedCoord == coordA) ? coordB : coordA;
        final step2Cells = colCells(grid, otherCoord.col, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineCol,
          center: otherCoord,
          cells: step2Cells,
        ));
        allCellsToClear.addAll(step2Cells);
        DebugLogger.specialCombo('Step 2 (102+102): lineCol at $otherCoord, ${step2Cells.length} cells');
        break;

      case 104: // 104+104
        // Only activate the chosen/activated bomb - clear its 3x3 area
        final stepCells = bomb3x3(grid, activatedCoord);
        steps.add(ComboStep(
          type: ComboStepType.bomb3x3,
          center: activatedCoord,
          cells: stepCells,
        ));
        allCellsToClear.addAll(stepCells);
        DebugLogger.specialCombo('104+104: bomb3x3 at $activatedCoord only, ${stepCells.length} cells');
        break;

      case 103: // 103+103
        // step: clearAllRegular
        final stepCells = allRegularCoords(grid).toSet();
        steps.add(ComboStep(
          type: ComboStepType.clearAllRegular,
          center: null,
          cells: stepCells,
        ));
        allCellsToClear.addAll(stepCells);
        DebugLogger.specialCombo('Step (103+103): clearAllRegular, ${stepCells.length} cells');
        break;

      case 105: // 105+105
        // step: prehit two DISTINCT random regular coords
        // Each dragonfly should animate to its own target
        final exclude = {coordA, coordB};
        final candidates = allRegularCoords(grid)
            .where((c) => !exclude.contains(c))
            .toList();
        
        if (candidates.isEmpty) {
          DebugLogger.specialCombo('Step (105+105): no regular tiles available for prehit');
        } else {
          // Pick 2 distinct coords (or 1 if only 1 exists)
          final numPicks = candidates.length >= 2 ? 2 : 1;
          final picked = <Coord>[];
          final available = List<Coord>.from(candidates);
          
          for (int i = 0; i < numPicks && available.isNotEmpty; i++) {
            final index = rng.nextInt(available.length);
            final pickedCoord = available.removeAt(index);
            picked.add(pickedCoord);
          }

          // Determine the other coord (the one that's not activatedCoord)
          final otherCoord = (activatedCoord == coordA) ? coordB : coordA;
          
          // Create steps: alternate between activatedCoord and otherCoord for VFX
          for (int i = 0; i < picked.length; i++) {
            final targetCoord = picked[i];
            // First step uses activatedCoord, second step uses otherCoord
            final dragonFlyCoord = (i == 0) ? activatedCoord : otherCoord;
            final stepCells = {dragonFlyCoord, targetCoord};
            steps.add(ComboStep(
              type: ComboStepType.prehit,
              center: dragonFlyCoord, // DragonFly coord for VFX (alternates between both)
              randomTargetCoord: targetCoord,
              cells: stepCells,
            ));
            allCellsToClear.addAll(stepCells);
            DebugLogger.specialCombo('Step ${i + 1} (105+105): prehit at $targetCoord using dragonFlyCoord $dragonFlyCoord');
          }
        }
        break;
    }
  }

  /// Build CROSS combo steps
  void _buildCrossCombo({
    required GridModel grid,
    required int activatedTypeId,
    required int otherTypeId,
    required Coord activatedCoord,
    required Coord otherCoord,
    required List<ComboStep> steps,
    required Set<Coord> allCellsToClear,
  }) {
    // Normalize: ensure we handle both orderings (e.g., 101+102 and 102+101)
    final type1 = activatedTypeId;
    final type2 = otherTypeId;
    final coord1 = activatedCoord;
    final coord2 = otherCoord;

    // 101+102 or 102+101: Check if vertical swap (same column)
    if ((type1 == 101 && type2 == 102) || (type1 == 102 && type2 == 101)) {
      final colCoord = (type1 == 102) ? coord1 : coord2;
      final rowCoord = (type1 == 101) ? coord1 : coord2;
      
      // Check if this is a vertical swap (101 and 102 are in the same column, one above/below the other)
      final isVerticalSwap = (coord1.col == coord2.col);
      
      if (isVerticalSwap) {
        // Special rule for vertical swap: horizontal first, then vertical
        // This prevents the vertical from clearing the horizontal before it activates
        DebugLogger.specialCombo('Vertical swap detected (101+102): activating horizontal first');
        
        // Step 1: row at 101 coord (horizontal party popper FIRST)
        final step1Cells = rowCells(grid, rowCoord.row, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineRow,
          center: rowCoord,
          cells: step1Cells,
        ));
        allCellsToClear.addAll(step1Cells);
        DebugLogger.specialCombo('Step 1 (101+102 vertical swap): lineRow at $rowCoord, ${step1Cells.length} cells');

        // Step 2: col at 102 coord (vertical party popper SECOND)
        final step2Cells = colCells(grid, colCoord.col, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineCol,
          center: colCoord,
          cells: step2Cells,
        ));
        allCellsToClear.addAll(step2Cells);
        DebugLogger.specialCombo('Step 2 (101+102 vertical swap): lineCol at $colCoord, ${step2Cells.length} cells');
      } else {
        // Default rule for horizontal swap: col first, then row
        // Step 1: col at 102 coord
        final step1Cells = colCells(grid, colCoord.col, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineCol,
          center: colCoord,
          cells: step1Cells,
        ));
        allCellsToClear.addAll(step1Cells);
        DebugLogger.specialCombo('Step 1 (101+102): lineCol at $colCoord, ${step1Cells.length} cells');

        // Step 2: row at 101 coord
        final step2Cells = rowCells(grid, rowCoord.row, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineRow,
          center: rowCoord,
          cells: step2Cells,
        ));
        allCellsToClear.addAll(step2Cells);
        DebugLogger.specialCombo('Step 2 (101+102): lineRow at $rowCoord, ${step2Cells.length} cells');
      }
      return;
    }

    // 104+101: bomb3x3 at 104 only (no line clear)
    if ((type1 == 104 && type2 == 101) || (type1 == 101 && type2 == 104)) {
      final bombCoord = (type1 == 104) ? coord1 : coord2;

      // Only bomb3x3 triggers
      final stepCells = bomb3x3(grid, bombCoord);
      steps.add(ComboStep(
        type: ComboStepType.bomb3x3,
        center: bombCoord,
        cells: stepCells,
      ));
      allCellsToClear.addAll(stepCells);
      DebugLogger.specialCombo('(104+101): bomb3x3 at $bombCoord, ${stepCells.length} cells');
      return;
    }

    // 104+102: bomb3x3 at 104 only (no line clear)
    if ((type1 == 104 && type2 == 102) || (type1 == 102 && type2 == 104)) {
      final bombCoord = (type1 == 104) ? coord1 : coord2;

      // Only bomb3x3 triggers
      final stepCells = bomb3x3(grid, bombCoord);
      steps.add(ComboStep(
        type: ComboStepType.bomb3x3,
        center: bombCoord,
        cells: stepCells,
      ));
      allCellsToClear.addAll(stepCells);
      DebugLogger.specialCombo('(104+102): bomb3x3 at $bombCoord, ${stepCells.length} cells');
      return;
    }

    // 103+101: pick random typeId, colorAllOfType, then row at 101
    if ((type1 == 103 && type2 == 101) || (type1 == 101 && type2 == 103)) {
      final rowCoord = (type1 == 101) ? coord1 : coord2;

      // Step 1: colorAllOfType
      final randomTypeId = pickRandomRegularTypeId(grid);
      if (randomTypeId != null) {
        final step1Cells = _getAllRegularOfType(grid, randomTypeId);
        steps.add(ComboStep(
          type: ComboStepType.colorAllOfType,
          center: null,
          randomTileTypeId: randomTypeId,
          cells: step1Cells,
        ));
        allCellsToClear.addAll(step1Cells);
        DebugLogger.specialCombo('Step 1 (103+101): colorAllOfType typeId=$randomTypeId, ${step1Cells.length} cells');
      }

      // Step 2: row
      final step2Cells = rowCells(grid, rowCoord.row, skipSpecials: true);
      steps.add(ComboStep(
        type: ComboStepType.lineRow,
        center: rowCoord,
        cells: step2Cells,
      ));
      allCellsToClear.addAll(step2Cells);
      DebugLogger.specialCombo('Step 2 (103+101): lineRow at $rowCoord, ${step2Cells.length} cells');
      return;
    }

    // 103+102: pick random typeId, colorAllOfType, then col at 102
    if ((type1 == 103 && type2 == 102) || (type1 == 102 && type2 == 103)) {
      final colCoord = (type1 == 102) ? coord1 : coord2;

      // Step 1: colorAllOfType
      final randomTypeId = pickRandomRegularTypeId(grid);
      if (randomTypeId != null) {
        final step1Cells = _getAllRegularOfType(grid, randomTypeId);
        steps.add(ComboStep(
          type: ComboStepType.colorAllOfType,
          center: null,
          randomTileTypeId: randomTypeId,
          cells: step1Cells,
        ));
        allCellsToClear.addAll(step1Cells);
        DebugLogger.specialCombo('Step 1 (103+102): colorAllOfType typeId=$randomTypeId, ${step1Cells.length} cells');
      }

      // Step 2: col
      final step2Cells = colCells(grid, colCoord.col, skipSpecials: true);
      steps.add(ComboStep(
        type: ComboStepType.lineCol,
        center: colCoord,
        cells: step2Cells,
      ));
      allCellsToClear.addAll(step2Cells);
      DebugLogger.specialCombo('Step 2 (103+102): lineCol at $colCoord, ${step2Cells.length} cells');
      return;
    }

    // 103+104: pick random typeId, colorAllOfType, then bomb3x3 at 104
    if ((type1 == 103 && type2 == 104) || (type1 == 104 && type2 == 103)) {
      final bombCoord = (type1 == 104) ? coord1 : coord2;

      // Step 1: colorAllOfType
      final randomTypeId = pickRandomRegularTypeId(grid);
      if (randomTypeId != null) {
        final step1Cells = _getAllRegularOfType(grid, randomTypeId);
        steps.add(ComboStep(
          type: ComboStepType.colorAllOfType,
          center: null,
          randomTileTypeId: randomTypeId,
          cells: step1Cells,
        ));
        allCellsToClear.addAll(step1Cells);
        DebugLogger.specialCombo('Step 1 (103+104): colorAllOfType typeId=$randomTypeId, ${step1Cells.length} cells');
      }

      // Step 2: bomb3x3
      final step2Cells = bomb3x3(grid, bombCoord);
      steps.add(ComboStep(
        type: ComboStepType.bomb3x3,
        center: bombCoord,
        cells: step2Cells,
      ));
      allCellsToClear.addAll(step2Cells);
      DebugLogger.specialCombo('Step 2 (103+104): bomb3x3 at $bombCoord, ${step2Cells.length} cells');
      return;
    }

    // 105 + ANY (ANY is 101, 102, 103, or 104)
    if (type1 == 105 || type2 == 105) {
      final dragonFlyCoord = (type1 == 105) ? coord1 : coord2;
      final otherType = (type1 == 105) ? type2 : type1;
      final otherCoord = (type1 == 105) ? coord2 : coord1;

      // Step 1: prehit ONE random regular coord
      final exclude = {coord1, coord2};
      final prehitTarget = pickRandomRegularCoord(grid, exclude: exclude);
      
      if (prehitTarget != null) {
        final step1Cells = {dragonFlyCoord, prehitTarget};
        final prehitTileTypeId = _getTileType(grid, prehitTarget);
        steps.add(ComboStep(
          type: ComboStepType.prehit,
          center: dragonFlyCoord, // DragonFly coord for VFX
          randomTargetCoord: prehitTarget,
          cells: step1Cells,
        ));
        allCellsToClear.addAll(step1Cells);
        DebugLogger.specialCombo('Step 1 (105+$otherType): prehit at $prehitTarget (including dragonFlyCoord $dragonFlyCoord)');

        // Step 2: activate OTHER special's effect
        _addOtherSpecialStep(
          grid: grid,
          otherType: otherType,
          otherCoord: otherCoord,
          prehitTileTypeId: prehitTileTypeId,
          steps: steps,
          allCellsToClear: allCellsToClear,
        );
      } else {
        // No regular tiles for prehit, skip prehit but still do step2
        DebugLogger.specialCombo('Step 1 (105+$otherType): no regular tiles for prehit, skipping');
        _addOtherSpecialStep(
          grid: grid,
          otherType: otherType,
          otherCoord: otherCoord,
          prehitTileTypeId: null,
          steps: steps,
          allCellsToClear: allCellsToClear,
        );
      }
      return;
    }

    // Unknown combo - log warning
    DebugLogger.warn('Unknown cross combo: $type1+$type2', category: 'SpecialCombo');
  }

  /// Add step for the "other" special in 105+ANY combo
  void _addOtherSpecialStep({
    required GridModel grid,
    required int otherType,
    required Coord otherCoord,
    int? prehitTileTypeId,
    required List<ComboStep> steps,
    required Set<Coord> allCellsToClear,
  }) {
    switch (otherType) {
      case 101: // row
        final stepCells = rowCells(grid, otherCoord.row, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineRow,
          center: otherCoord,
          cells: stepCells,
        ));
        allCellsToClear.addAll(stepCells);
        DebugLogger.specialCombo('Step 2 (105+101): lineRow at $otherCoord, ${stepCells.length} cells');
        break;

      case 102: // col
        final stepCells = colCells(grid, otherCoord.col, skipSpecials: true);
        steps.add(ComboStep(
          type: ComboStepType.lineCol,
          center: otherCoord,
          cells: stepCells,
        ));
        allCellsToClear.addAll(stepCells);
        DebugLogger.specialCombo('Step 2 (105+102): lineCol at $otherCoord, ${stepCells.length} cells');
        break;

      case 104: // bomb3x3
        final stepCells = bomb3x3(grid, otherCoord);
        steps.add(ComboStep(
          type: ComboStepType.bomb3x3,
          center: otherCoord,
          cells: stepCells,
        ));
        allCellsToClear.addAll(stepCells);
        DebugLogger.specialCombo('Step 2 (105+104): bomb3x3 at $otherCoord, ${stepCells.length} cells');
        break;

      case 103: // colorAllOfType
        // Use prehit target's tileTypeId if it's regular, else pick random
        int? typeIdToUse = isRegular(prehitTileTypeId) ? prehitTileTypeId : pickRandomRegularTypeId(grid);
        if (typeIdToUse != null) {
          final stepCells = _getAllRegularOfType(grid, typeIdToUse);
          steps.add(ComboStep(
            type: ComboStepType.colorAllOfType,
            center: null,
            randomTileTypeId: typeIdToUse,
            cells: stepCells,
          ));
          allCellsToClear.addAll(stepCells);
          DebugLogger.specialCombo('Step 2 (105+103): colorAllOfType typeId=$typeIdToUse, ${stepCells.length} cells');
        }
        break;
    }
  }

  /// Get all regular tiles of a specific type
  Set<Coord> _getAllRegularOfType(GridModel grid, int tileTypeId) {
    final cells = <Coord>{};
    for (int row = 0; row < grid.rows; row++) {
      for (int col = 0; col < grid.cols; col++) {
        final coord = Coord(row, col);
        if (!isPlayable(grid, coord)) continue;
        final cell = grid.cells[row][col];
        if (cell.tileTypeId == tileTypeId && isRegular(cell.tileTypeId)) {
          cells.add(coord);
        }
      }
    }
    return cells;
  }
}
