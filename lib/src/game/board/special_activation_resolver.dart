import 'dart:collection';
import '../model/coord.dart';
import '../model/grid_model.dart';
import '../utils/debug_logger.dart';
import 'special_tile_spawner.dart';

/// Resolves special tile activation and expands clearing sets
/// Handles swap-based activation and chain reactions (BFS)
class SpecialActivationResolver {
  final SpecialTileSpawner spawner;
  final int rows;
  final int cols;
  
  SpecialActivationResolver({
    required this.spawner,
    required this.rows,
    required this.cols,
  });
  
  /// Get priority for a special tile type (higher = activates first)
  /// Priority order (descending) - also determines VFX playback order:
  /// - 105 (DragonFly): 4 (highest priority)
  /// - 103 (Sticky Rice Bomb): 3
  /// - 101/102 (Party Popper): 2
  /// - 104 (Firecracker): 1 (lowest priority)
  /// Returns 0 for non-special tiles
  int specialPriority(int tileTypeId) {
    if (tileTypeId == 105) return 4; // DragonFly - highest priority
    if (tileTypeId == 103) return 3; // Sticky Rice Bomb
    if (tileTypeId == 101 || tileTypeId == 102) return 2; // Party Popper (horizontal/vertical)
    if (tileTypeId == 104) return 1; // Firecracker - lowest priority
    return 0; // Not a special tile
  }
  
  /// Expand initial clearing set with special tile activations
  /// Returns: (cellsToClear, activatedSpecials, vfxMetadata)
  /// - cellsToClear: All cells that should be cleared (including special activations)
  /// - activatedSpecials: Map of coord -> tileTypeId for activated specials (for VFX)
  ///   Captures tileTypeId BEFORE clearing so VFX knows orientation (101 vs 102)
  ///   NOTE: Only includes specials that are ACTIVATED (from swap), not those being CLEARED
  /// - vfxMetadata: Map of coord -> metadata for VFX (e.g., targetCoord for DragonFly 105, activationCells for StickyRice 103)
  ({
    Set<Coord> cellsToClear,
    Map<Coord, int> activatedSpecials,
    Map<Coord, ({Coord? targetCoord, Set<Coord>? activationCells})> vfxMetadata,
  }) expandClearsWithSpecials({
    required GridModel gridModel,
    required Set<Coord> initialToClear,
    Coord? swapA,
    Coord? swapB,
    Coord? chosenCoord, // The coord the user started dragging from (dragStartCoord)
  }) {
    final cellsToClear = <Coord>{...initialToClear};
    final activatedSpecials = <Coord, int>{}; // Map: coord -> tileTypeId (captured BEFORE clearing)
    final vfxMetadata = <Coord, ({Coord? targetCoord, Set<Coord>? activationCells})>{}; // Map: coord -> VFX metadata
    final processedSpecials = <Coord>{}; // Track which specials have been processed (BFS visited)
    final queue = Queue<Coord>(); // BFS queue for special activations (O(1) operations)
    final specialsToClearOnly = <Coord>{}; // Track specials that should only be cleared, not activated
    
    // Helper to check if a coord is valid (in bounds and playable)
    bool isValidCoord(Coord coord) {
      if (coord.row < 0 || coord.row >= gridModel.rows || coord.col < 0 || coord.col >= gridModel.cols) {
        return false;
      }
      final cell = gridModel.cells[coord.row][coord.col];
      // Filter out void cells (bedId == -1)
      if (cell.bedId == null || cell.bedId! == -1) {
        return false;
      }
      return true;
    }
    
    // Helper to check if a coord has a special tile (101-105)
    bool isSpecialTile(Coord coord) {
      if (!isValidCoord(coord)) return false;
      final cell = gridModel.cells[coord.row][coord.col];
      if (cell.tileTypeId == null) return false;
      return cell.tileTypeId! >= 101 && cell.tileTypeId! <= 105;
    }
    
    // Step 1: Check swapA/swapB for immediate special activation
    // If BOTH are special, activate the one at chosenCoord (the tile user started dragging from)
    // If exactly ONE is special, activate that one
    final swapSpecials = <Coord>[];
    
    final swapAIsSpecial = swapA != null && isSpecialTile(swapA);
    final swapBIsSpecial = swapB != null && isSpecialTile(swapB);
    
    if (swapAIsSpecial && !swapBIsSpecial) {
      // Only swapA is special
      swapSpecials.add(swapA);
    } else if (swapBIsSpecial && !swapAIsSpecial) {
      // Only swapB is special
      swapSpecials.add(swapB);
    } else if (swapAIsSpecial && swapBIsSpecial) {
      // Both are special - activate the one at chosenCoord
      if (chosenCoord != null) {
        if (chosenCoord == swapA) {
          swapSpecials.add(swapA);
          DebugLogger.specialActivation('Both swap tiles are special: activating chosenCoord (swapA=$swapA)');
        } else if (chosenCoord == swapB) {
          swapSpecials.add(swapB);
          DebugLogger.specialActivation('Both swap tiles are special: activating chosenCoord (swapB=$swapB)');
        } else {
          // chosenCoord doesn't match either swap tile - default to swapA
          swapSpecials.add(swapA);
          DebugLogger.specialActivation('Both swap tiles are special but chosenCoord=$chosenCoord doesn\'t match either - defaulting to swapA=$swapA');
        }
      } else {
        // No chosenCoord provided - default to swapA
        swapSpecials.add(swapA);
        DebugLogger.specialActivation('Both swap tiles are special but no chosenCoord provided - defaulting to swapA=$swapA');
      }
    }
    
    // Add swap specials to queue
    for (final specialCoord in swapSpecials) {
      if (!processedSpecials.contains(specialCoord)) {
        queue.add(specialCoord);
        processedSpecials.add(specialCoord);
        final typeId = gridModel.cells[specialCoord.row][specialCoord.col].tileTypeId;
        DebugLogger.specialActivation('Special at $specialCoord (type $typeId) added to activation queue');
      }
    }
    
    // Step 2: Specials in initialToClear that are NOT swapA/swapB should NOT activate
    // They're being cleared by another special's activation, so just clear them without VFX
    // Only swapA/swapB specials should trigger activations to avoid overlapping animations
    for (final coord in initialToClear) {
      if (isSpecialTile(coord) && coord != swapA && coord != swapB) {
        // This special is being cleared by another special's activation
        // Mark it as processed so it won't be added to queue later
        // Don't add to queue - just ensure it's in cellsToClear (it already is from initialToClear)
        // It will be cleared but won't trigger its own VFX
        processedSpecials.add(coord);
        specialsToClearOnly.add(coord);
        DebugLogger.specialActivation('Special tile at $coord is being cleared (not activated) - skipping VFX');
      }
    }
    
    // Step 3: Process special activations in queue order (at most 1 activated special total)
    // Special+special swap activates chosenCoord only (not both)
    while (queue.isNotEmpty) {
      final specialCoord = queue.removeFirst(); // O(1) operation with Queue
      
      if (!isValidCoord(specialCoord)) continue;
      
      final cell = gridModel.cells[specialCoord.row][specialCoord.col];
      final specialTypeId = cell.tileTypeId;
      
      if (specialTypeId == null || specialTypeId < 101 || specialTypeId > 105) {
        continue; // Not a special tile (shouldn't happen, but safety check)
      }
      
      // Track swap-based specials separately
      // Swap-based specials (from swapA/swapB) activate ALL special types (including 103 and 105)
      // Explosion-based specials (chain reaction) skip 103 and 105 (they only activate on swap)
      final isSwapBased = (specialCoord == swapA || specialCoord == swapB);
      
      if (!isSwapBased && (specialTypeId == 103 || specialTypeId == 105)) {
        // Explosion-based: Just add the special coord itself to clear, but don't activate its effect
        // Don't add to activatedSpecials - it wasn't actually activated, just cleared
        cellsToClear.add(specialCoord);
        continue;
      }
      
      // This special actually triggers its effect - record it for VFX
      // Capture tileTypeId BEFORE clearing (needed for VFX to know orientation 101 vs 102)
      // Only allow one activation total (at most 1 activated special) to avoid overlapping animations
      if (activatedSpecials.isEmpty) {
        activatedSpecials[specialCoord] = specialTypeId;
      } else {
        // Already have one activated - mark this as clear-only (no VFX)
        processedSpecials.add(specialCoord);
        specialsToClearOnly.add(specialCoord);
        cellsToClear.add(specialCoord);
        DebugLogger.specialActivation('Special at $specialCoord skipped (already have 1 activated special)');
        continue;
      }
      
      // For DragonFly (105), immediately clear the source coord before processing other specials
      // This ensures the DragonFly source disappears before any other special can activate
      if (specialTypeId == 105) {
        cellsToClear.add(specialCoord);
        // Mark as processed immediately to prevent it from being used as an activation source
        processedSpecials.add(specialCoord);
        DebugLogger.specialActivation('DragonFly (105) at $specialCoord: immediately marking source for clearing before processing');
      }
      
      // Compute swapOther for swap-based specials (103 StickyRice and 105 DragonFly need this)
      Coord? swapOther;
      if (isSwapBased) {
        if (specialCoord == swapA) {
          swapOther = swapB;
        } else if (specialCoord == swapB) {
          swapOther = swapA;
        }
      }
      
      // Get activation cells for this special tile (returns affected coords to clear)
      // e.g., Firecracker (104) returns 3x3, PartyPopper returns row/col, etc.
      // For 103 StickyRice and 105 DragonFly, swapOther is passed for swap-based activation
      final result = spawner.getActivationCells(
        gridModel,
        specialCoord,
        specialTypeId,
        swapOther: swapOther,
      );
      final activationCells = result.affected;
      final returnedTargetCoord = result.targetCoord;
      
      // For DragonFly (105), use the deterministic targetCoord returned from getActivationCells
      if (specialTypeId == 105) {
        // Store metadata for VFX using the deterministic targetCoord
        if (returnedTargetCoord != null) {
          vfxMetadata[specialCoord] = (targetCoord: returnedTargetCoord, activationCells: null);
        }
        // Source coord already added to cellsToClear and marked as processed earlier
        DebugLogger.specialActivation('DragonFly (105) at $specialCoord: source coord already marked for clearing');
      }
      
      // For StickyRice (103), store activationCells for VFX
      if (specialTypeId == 103) {
        // If metadata already exists (shouldn't happen for sticky rice), update it
        // Otherwise create new entry
        final existingMeta = vfxMetadata[specialCoord];
        vfxMetadata[specialCoord] = (
          targetCoord: existingMeta?.targetCoord,
          activationCells: activationCells,
        );
      }
      
      // Debug logging: verify activation cells are being computed correctly
      DebugLogger.specialActivation('typeId=$specialTypeId coord=$specialCoord swapOther=$swapOther activationCells.length=${activationCells.length}');
      if (activationCells.isEmpty && specialTypeId != 103 && specialTypeId != 105) {
        DebugLogger.warn('Empty activation cells for typeId=$specialTypeId at $specialCoord', category: 'SpecialActivation');
      }
      
      // Add activation cells to clearing set - these cells WILL be cleared
      // Filter invalid coords (out of bounds, void cells) before adding
      int addedCount = 0;
      for (final coord in activationCells) {
        if (!isValidCoord(coord)) continue;
        cellsToClear.add(coord); // These cells will be cleared in clearMatchedCells()
        addedCount++;
        
        // If this cell contains another special tile, DON'T add it to queue (no chain reaction)
        // Specials cleared by other specials should just be cleared without activating
        // This prevents overlapping animations when one special clears another
        if (isSpecialTile(coord) && !processedSpecials.contains(coord)) {
          // Just mark it as processed so we don't try to activate it
          processedSpecials.add(coord);
          specialsToClearOnly.add(coord); // Track it so we can exclude from activatedSpecials
          // It's already in cellsToClear, so it will be cleared without VFX
          DebugLogger.specialActivation('Special tile at $coord found in activation cells - will be cleared (not activated)');
        }
      }
      if (addedCount > 0) {
        DebugLogger.specialActivation('Added $addedCount cells to clear for typeId=$specialTypeId at $specialCoord');
      }
      
      // Also add the special coord itself to clear (the activated special is removed)
      cellsToClear.add(specialCoord);
    }
    
    // Final safety check: Remove any specials from activatedSpecials that should only be cleared
    // This ensures that even if they somehow got added, they won't trigger VFX
    for (final coord in specialsToClearOnly) {
      activatedSpecials.remove(coord);
      vfxMetadata.remove(coord);
      DebugLogger.specialActivation('Removed $coord from activatedSpecials (should only be cleared, not activated)');
    }
    
    return (
      cellsToClear: cellsToClear,
      activatedSpecials: activatedSpecials,
      vfxMetadata: vfxMetadata,
    );
  }
}