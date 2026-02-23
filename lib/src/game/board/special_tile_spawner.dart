import 'dart:math';
import '../model/coord.dart';
import '../model/match_result.dart';
import '../model/grid_model.dart';
import '../utils/debug_logger.dart';

/// Represents a candidate for special tile spawning
/// Contains pattern cells, spawn location, special tile type, and priority
class _SpecialTileCandidate {
  final Set<Coord> cells; // All cells in this pattern
  final Coord spawnCoord; // Where to spawn the special tile
  final int specialTypeId; // Special tile type ID (101-105)
  final int priority; // Higher priority = processed first (6 = highest, 1 = lowest)
  
  _SpecialTileCandidate({
    required this.cells,
    required this.spawnCoord,
    required this.specialTypeId,
    required this.priority,
  });
}

/// Handles special tile spawning logic based on match shapes
/// Implements rules:
/// - 5 in a straight line → StickyRice (103) [priority 5]
/// - T/L union 5-6 → Firecracker (104) [priority 4]
/// - 2x2 square around swap → DragonFly (105) [priority 3]
/// - 4 in a line → PartyPopper (101/102) oriented with the line [priority 2]
class SpecialTileSpawner {
  final Random rng;
  
  SpecialTileSpawner({
    required this.rng,
  });
  
  /// Check if a match is horizontal (all cells have the same row)
  bool _isHorizontalMatch(Match match) {
    if (match.cells.isEmpty) return false;
    final firstRow = match.cells.first.row;
    return match.cells.every((coord) => coord.row == firstRow);
  }
  
  /// Check if a match is vertical (all cells have the same column)
  bool _isVerticalMatch(Match match) {
    if (match.cells.isEmpty) return false;
    final firstCol = match.cells.first.col;
    return match.cells.every((coord) => coord.col == firstCol);
  }
  
  /// Find intersection cells between two matches (cells that belong to both)
  Set<Coord> _getIntersection(Match match1, Match match2) {
    final set1 = match1.cells.toSet();
    final set2 = match2.cells.toSet();
    return set1.intersection(set2);
  }
  
  /// Get center cell of a match (for straight lines)
  /// For horizontal: returns the middle column cell
  /// For vertical: returns the middle row cell
  Coord _getCenterCell(Match match) {
    if (match.cells.isEmpty) throw ArgumentError('Match has no cells');
    
    if (_isHorizontalMatch(match)) {
      // Horizontal: sort by column and get middle
      final sorted = List<Coord>.from(match.cells)..sort((a, b) => a.col.compareTo(b.col));
      return sorted[sorted.length ~/ 2];
    } else if (_isVerticalMatch(match)) {
      // Vertical: sort by row and get middle
      final sorted = List<Coord>.from(match.cells)..sort((a, b) => a.row.compareTo(b.row));
      return sorted[sorted.length ~/ 2];
    } else {
      // Fallback: just return first cell
      return match.cells.first;
    }
  }
  
  /// Detect ALL straight 5 in a line (horizontal or vertical run of exactly 5)
  /// Returns list of all matches found
  List<Match> _detectAllStraight5(List<Match> matches) {
    final result = <Match>[];
    for (final match in matches) {
      if (match.length == 5) {
        // Must be a straight line (all horizontal or all vertical)
        if (_isHorizontalMatch(match) || _isVerticalMatch(match)) {
          result.add(match);
        }
      }
    }
    return result;
  }
  
  /// Detect ALL T or L shapes (horizontal run ≥3 AND vertical run ≥3 that intersect, totaling 5+ cells)
  /// Returns list of records with the two matches, intersection cell, and union size
  /// Returns ALL T/L intersections - priority sorting + processedCells greedy pass will handle overlaps
  List<({Match horizontalMatch, Match verticalMatch, Coord intersection, int unionSize})> _detectAllTOrL(
    List<Match> matches, {
    Coord? swapA,
    Coord? swapB,
  }) {
    final result = <({Match horizontalMatch, Match verticalMatch, Coord intersection, int unionSize})>[];
    
    // Separate horizontal and vertical matches
    final horizontalMatches = matches.where((m) => _isHorizontalMatch(m) && m.length >= 3).toList();
    final verticalMatches = matches.where((m) => _isVerticalMatch(m) && m.length >= 3).toList();
    
    // Track processed T/L combinations using lightweight hash keys (for reliable duplicate detection)
    // Hash key: (tileTypeId, intersectionCoord.row, intersectionCoord.col, hLength, vLength)
    // Prevents same (horizontalMatch, verticalMatch) pair from being added multiple times
    final processedCombos = <(int, int, int, int, int)>{};
    
    // Helper to select intersection cell: prefer swapB, then swapA, else deterministic top-left
    Coord selectIntersectionCell(Set<Coord> intersection) {
      if (swapB != null && intersection.contains(swapB)) {
        return swapB;
      }
      if (swapA != null && intersection.contains(swapA)) {
        return swapA;
      }
      // Deterministic top-left selection
      final sorted = intersection.toList()
        ..sort((a, b) {
          if (a.row != b.row) return a.row.compareTo(b.row);
          return a.col.compareTo(b.col);
        });
      return sorted.first;
    }
    
    // Check all combinations of horizontal and vertical matches
    for (final hMatch in horizontalMatches) {
      for (final vMatch in verticalMatches) {
        // Check if they have the same tileTypeId (required for T/L)
        if (hMatch.tileTypeId != vMatch.tileTypeId) continue;
        
        // Find intersection (cells that belong to both matches)
        final intersection = _getIntersection(hMatch, vMatch);
        
        if (intersection.isEmpty) continue;
        
        // Select intersection cell: prefer swapB, then swapA, else deterministic top-left
        final intersectionCoord = selectIntersectionCell(intersection);
        
        // Create lightweight hash key: (tileTypeId, intersectionCoord.row, intersectionCoord.col, hLength, vLength)
        // Use deterministic top-left for hash key (to identify the same combo regardless of swap preference)
        final sortedForHash = intersection.toList()
          ..sort((a, b) {
            if (a.row != b.row) return a.row.compareTo(b.row);
            return a.col.compareTo(b.col);
          });
        final hashIntersection = sortedForHash.first;
        final comboKey = (hMatch.tileTypeId, hashIntersection.row, hashIntersection.col, hMatch.length, vMatch.length);
        
        // Skip if we've already processed this exact combination
        if (processedCombos.contains(comboKey)) continue;
        
        // Check if total cells is at least 5 (union of both matches)
        final union = hMatch.cells.toSet().union(vMatch.cells.toSet());
        final unionSize = union.length;
        if (unionSize >= 5) {
          // Found T or L shape! (can be 5+ cells)
          // Note: We no longer filter by intersection point - multiple T/L combos can share intersections
          // Priority sorting + processedCells greedy pass will choose the best non-overlapping special
          processedCombos.add(comboKey);
          result.add((
            horizontalMatch: hMatch,
            verticalMatch: vMatch,
            intersection: intersectionCoord,
            unionSize: unionSize,
          ));
        }
      }
    }
    
    return result;
  }
  
  /// Detect 2x2 block around swap coordinates
  /// Checks for 2x2 blocks containing swapA or swapB
  /// Requires all 4 cells: bedId != -1, tileTypeId != null, tileTypeId < 101
  /// Returns the block cells if found, null otherwise
  Set<Coord>? detect2x2AroundSwap(
    GridModel gridModel,
    Coord? swapA,
    Coord? swapB,
  ) {
    // Try swapB first, then swapA
    final swapsToCheck = <Coord>[];
    if (swapB != null) swapsToCheck.add(swapB);
    if (swapA != null) swapsToCheck.add(swapA);
    
    for (final swap in swapsToCheck) {
      final r = swap.row;
      final c = swap.col;
      
      // Check all 4 possible 2x2 blocks that could contain this swap
      // Top-left positions: (r-1, c-1), (r-1, c), (r, c-1), (r, c)
      final possibleTopLefts = [
        Coord(r - 1, c - 1),
        Coord(r - 1, c),
        Coord(r, c - 1),
        Coord(r, c),
      ];
      
      for (final topLeft in possibleTopLefts) {
        final tr = topLeft.row;
        final tc = topLeft.col;
        
        // Check bounds - block needs (tr+1, tc+1) to be valid
        if (tr < 0 || tr + 1 >= gridModel.rows || tc < 0 || tc + 1 >= gridModel.cols) continue;
        
        // Get tileTypeId from top-left cell
        final topLeftCell = gridModel.cells[tr][tc];
        if (topLeftCell.tileTypeId == null) continue;
        
        // Hardened checks: bedId != -1, tileTypeId != null, tileTypeId < 101
        if (topLeftCell.bedId == null || topLeftCell.bedId! == -1) continue; // Must be playable (not void)
        if (topLeftCell.tileTypeId! >= 101) continue; // Must be regular tile (not special)
        
        final tileTypeId = topLeftCell.tileTypeId!;
        
        // Define the 2x2 block cells
        final blockCells = {
          Coord(tr, tc),
          Coord(tr, tc + 1),
          Coord(tr + 1, tc),
          Coord(tr + 1, tc + 1),
        };
        
        // Check if this block contains the swap coordinate
        if (!blockCells.contains(swap)) continue;
        
        // Check if all 4 cells meet requirements: bedId != -1, tileTypeId != null, tileTypeId < 101, and same tileTypeId
        bool isValidBlock = true;
        for (final cellCoord in blockCells) {
          final cell = gridModel.cells[cellCoord.row][cellCoord.col];
          
          // Hardened checks: bedId != -1, tileTypeId != null, tileTypeId < 101
          if (cell.bedId == null || cell.bedId! == -1) {
            isValidBlock = false;
            break;
          }
          if (cell.tileTypeId == null || cell.tileTypeId! >= 101) {
            isValidBlock = false;
            break;
          }
          if (cell.tileTypeId != tileTypeId) {
            isValidBlock = false;
            break;
          }
        }
        
        if (isValidBlock) {
          return blockCells;
        }
      }
    }
    
    return null;
  }
  
  /// Detect ALL 2x2 blocks on the board
  /// Scans the entire board for 2x2 blocks
  /// Requires all 4 cells: bedId != -1, tileTypeId != null, tileTypeId < 101, same tileTypeId
  /// Returns a list of 2x2 block cell sets (each set contains 4 coords)
  List<Set<Coord>> detectAll2x2Blocks(GridModel gridModel) {
    final blocks = <Set<Coord>>[];
    final processedBlocks = <String>{}; // Track processed blocks to avoid duplicates
    
    // Scan all possible top-left positions for 2x2 blocks
    for (int tr = 0; tr < gridModel.rows - 1; tr++) {
      for (int tc = 0; tc < gridModel.cols - 1; tc++) {
        // Get tileTypeId from top-left cell
        final topLeftCell = gridModel.cells[tr][tc];
        if (topLeftCell.tileTypeId == null) continue;
        
        // Hardened checks: bedId != -1, tileTypeId != null, tileTypeId < 101
        if (topLeftCell.bedId == null || topLeftCell.bedId! == -1) continue; // Must be playable (not void)
        if (topLeftCell.tileTypeId! >= 101) continue; // Must be regular tile (not special)
        
        final tileTypeId = topLeftCell.tileTypeId!;
        
        // Define the 2x2 block cells
        final blockCells = {
          Coord(tr, tc),
          Coord(tr, tc + 1),
          Coord(tr + 1, tc),
          Coord(tr + 1, tc + 1),
        };
        
        // Create a unique key for this block (sorted coords)
        final sortedCoords = blockCells.toList()..sort((a, b) {
          final rowCompare = a.row.compareTo(b.row);
          return rowCompare != 0 ? rowCompare : a.col.compareTo(b.col);
        });
        final blockKey = sortedCoords.map((c) => '${c.row},${c.col}').join('|');
        
        // Skip if we've already processed this block
        if (processedBlocks.contains(blockKey)) continue;
        
        // Check if all 4 cells meet requirements: bedId != -1, tileTypeId != null, tileTypeId < 101, and same tileTypeId
        bool isValidBlock = true;
        for (final cellCoord in blockCells) {
          final cell = gridModel.cells[cellCoord.row][cellCoord.col];
          
          // Hardened checks: bedId != -1, tileTypeId != null, tileTypeId < 101
          if (cell.bedId == null || cell.bedId! == -1) {
            isValidBlock = false;
            break;
          }
          if (cell.tileTypeId == null || cell.tileTypeId! >= 101) {
            isValidBlock = false;
            break;
          }
          if (cell.tileTypeId != tileTypeId) {
            isValidBlock = false;
            break;
          }
        }
        
        if (isValidBlock) {
          blocks.add(blockCells);
          processedBlocks.add(blockKey);
        }
      }
    }
    
    return blocks;
  }
  
  /// Detect ALL 4 in a line (horizontal or vertical run of exactly 4)
  /// Returns list of all matches found
  List<Match> _detectAllStraight4(List<Match> matches) {
    final result = <Match>[];
    for (final match in matches) {
      if (match.length == 4) {
        // Must be a straight line (all horizontal or all vertical)
        if (_isHorizontalMatch(match) || _isVerticalMatch(match)) {
          result.add(match);
        }
      }
    }
    return result;
  }
  
  /// Determine spawn location for a straight line match
  /// Priority: swapB (if on the line) -> swapA (if on the line) -> center cell of the line
  Coord _getStraightLineSpawnLocation(Match match, Coord? swapA, Coord? swapB) {
    // Priority 1: swapB if it lies on the line
    if (swapB != null && match.cells.contains(swapB)) {
      return swapB;
    }
    
    // Priority 2: swapA if it lies on the line
    if (swapA != null && match.cells.contains(swapA)) {
      return swapA;
    }
    
    // Priority 3: center cell of the line
    return _getCenterCell(match);
  }
  
  /// Determine spawn location for a 2x2 block
  /// Priority: swapB (if in block) -> swapA (if in block) -> top-left cell of the block
  Coord _getBlockSpawnLocation(Set<Coord> blockCells, Coord? swapA, Coord? swapB) {
    // Priority 1: swapB if it's in the block
    if (swapB != null && blockCells.contains(swapB)) {
      return swapB;
    }
    
    // Priority 2: swapA if it's in the block
    if (swapA != null && blockCells.contains(swapA)) {
      return swapA;
    }
    
    // Priority 3: top-left cell (smallest row, then smallest col)
    final sorted = blockCells.toList()
      ..sort((a, b) {
        if (a.row != b.row) return a.row.compareTo(b.row);
        return a.col.compareTo(b.col);
      });
    return sorted.first;
  }
  
  /// Get cells affected by special tile activation
  /// Returns set of coordinates that should be cleared
  /// Excludes void cells (bedId == -1) - caller should filter, but we also check here for safety
  /// swapOther: Optional coord of the tile swapped with the special (for 103 StickyRice and 105 DragonFly)
  /// Get activation cells for a special tile
  /// Returns: ({Set&lt;Coord&gt; affected, Coord? targetCoord})
  /// - affected: All cells that will be cleared by this special
  /// - targetCoord: For DragonFly (105), the deterministic target coord. null for other specials.
  ({
    Set<Coord> affected,
    Coord? targetCoord,
  }) getActivationCells(
    GridModel gridModel,
    Coord specialCoord,
    int specialTypeId, {
    Coord? swapOther,
  }) {
    final affected = <Coord>{};
    Coord? targetCoord;
    final r = specialCoord.row;
    final c = specialCoord.col;
    
    switch (specialTypeId) {
      case 101: // PartyPopper_H - clear whole row
        for (int col = 0; col < gridModel.cols; col++) {
          final coord = Coord(r, col);
          // Exclude void cells (bedId == -1)
          if (r >= 0 && r < gridModel.rows && col >= 0 && col < gridModel.cols) {
            final cell = gridModel.cells[r][col];
            if (cell.bedId != null && cell.bedId! != -1) {
              affected.add(coord);
            }
          }
        }
        break;
        
      case 102: // PartyPopper_V - clear whole column
        for (int row = 0; row < gridModel.rows; row++) {
          final coord = Coord(row, c);
          // Exclude void cells (bedId == -1)
          if (row >= 0 && row < gridModel.rows && c >= 0 && c < gridModel.cols) {
            final cell = gridModel.cells[row][c];
            if (cell.bedId != null && cell.bedId! != -1) {
              affected.add(coord);
            }
          }
        }
        break;
        
      case 103: // StickyRice - "color bomb": on swap, clear all tiles matching tileTypeId at swapOther
        if (swapOther != null) {
          // Get the tileTypeId from the swapped tile
          if (swapOther.row >= 0 && swapOther.row < gridModel.rows && 
              swapOther.col >= 0 && swapOther.col < gridModel.cols) {
            final swapCell = gridModel.cells[swapOther.row][swapOther.col];
            final targetTileTypeId = swapCell.tileTypeId;
            
            if (targetTileTypeId != null && targetTileTypeId < 101) {
              // Clear all tiles matching this tileTypeId (ignore void cells and specials)
              for (int row = 0; row < gridModel.rows; row++) {
                for (int col = 0; col < gridModel.cols; col++) {
                  final cell = gridModel.cells[row][col];
                  // Exclude void cells (bedId == -1) and special tiles (>= 101)
                  if (cell.bedId != null && cell.bedId! != -1 && 
                      cell.tileTypeId == targetTileTypeId && cell.tileTypeId! < 101) {
                    affected.add(Coord(row, col));
                  }
                }
              }
            }
          }
        }
        // Always clear the special itself
        affected.add(specialCoord);
        break;
        
      case 104: // Firecracker - clear 3x3 centered on coord
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            final row = r + dr;
            final col = c + dc;
            if (row >= 0 && row < gridModel.rows && col >= 0 && col < gridModel.cols) {
              // Exclude void cells (bedId == -1)
              final cell = gridModel.cells[row][col];
              if (cell.bedId != null && cell.bedId! != -1) {
                affected.add(Coord(row, col));
              }
            }
          }
        }
        break;
        
      case 105: // DragonFly - on swap, pick ONE deterministic tile matching swapOther's tileTypeId
        if (swapOther != null) {
          // Get the tileTypeId from the swapped tile
          if (swapOther.row >= 0 && swapOther.row < gridModel.rows && 
              swapOther.col >= 0 && swapOther.col < gridModel.cols) {
            final swapCell = gridModel.cells[swapOther.row][swapOther.col];
            final targetTileTypeId = swapCell.tileTypeId;
            
            // Always clear the tile it swapped with (swapOther)
            affected.add(swapOther);
            
            if (targetTileTypeId != null && targetTileTypeId < 101) {
              // Find all playable cells matching this tileTypeId (ignore void cells and specials)
              // Exclude swapOther from candidates (already added to affected)
              final candidates = <Coord>[];
              for (int row = 0; row < gridModel.rows; row++) {
                for (int col = 0; col < gridModel.cols; col++) {
                  final coord = Coord(row, col);
                  // Skip swapOther (already added to affected)
                  if (coord == swapOther) continue;
                  
                  final cell = gridModel.cells[row][col];
                  // Exclude void cells (bedId == -1) and special tiles (>= 101)
                  if (cell.bedId != null && cell.bedId! != -1 && 
                      cell.tileTypeId == targetTileTypeId && cell.tileTypeId! < 101) {
                    candidates.add(coord);
                  }
                }
              }
              
              if (candidates.isEmpty) {
                // No matching candidates found - pick ONE deterministic playable tile instead
                final allPlayableTiles = <Coord>[];
                for (int row = 0; row < gridModel.rows; row++) {
                  for (int col = 0; col < gridModel.cols; col++) {
                    final coord = Coord(row, col);
                    // Skip swapOther (already added to affected)
                    if (coord == swapOther) continue;
                    
                    final cell = gridModel.cells[row][col];
                    // Exclude void cells (bedId == -1) and special tiles (>= 101)
                    if (cell.bedId != null && cell.bedId! != -1 && 
                        cell.tileTypeId != null && cell.tileTypeId! < 101) {
                      allPlayableTiles.add(coord);
                    }
                  }
                }
                
                if (allPlayableTiles.isNotEmpty) {
                  // Pick ONE deterministic playable tile (sort by row, then col, pick first)
                  allPlayableTiles.sort((a, b) {
                    final rowCmp = a.row.compareTo(b.row);
                    if (rowCmp != 0) return rowCmp;
                    return a.col.compareTo(b.col);
                  });
                  targetCoord = allPlayableTiles.first;
                  affected.add(targetCoord);
                }
                // Also clear the DragonFly itself
                affected.add(specialCoord);
              } else {
                // Pick ONE deterministic candidate (sort by row, then col, pick first)
                candidates.sort((a, b) {
                  final rowCmp = a.row.compareTo(b.row);
                  if (rowCmp != 0) return rowCmp;
                  return a.col.compareTo(b.col);
                });
                targetCoord = candidates.first;
                affected.add(targetCoord);
                // Also clear the DragonFly itself
                affected.add(specialCoord);
              }
            } else {
              // Invalid target tileTypeId - still clear swapOther and DragonFly itself
              affected.add(specialCoord);
            }
          } else {
            // Invalid swapOther coord - just clear the DragonFly itself
            affected.add(specialCoord);
          }
        } else {
          // No swapOther (shouldn't happen for swap-based activation) - just clear the DragonFly itself
          affected.add(specialCoord);
        }
        break;
    }
    
    return (affected: affected, targetCoord: targetCoord);
  }
  
  /// Process match result and return both cells to clear and special tiles to spawn
  /// Returns a record: (cellsToClear, specialTileSpawns)
  /// - cellsToClear: Set of coords that should be cleared (excluding spawn locations)
  /// - specialTileSpawns: Map of spawnCoord -> specialTileTypeId
  /// 
  /// Rules (priority order, higher priority processed first):
  /// 1. 5 in a straight line → StickyRice (103) [priority 5]
  /// 2. T/L union 5-6 → Firecracker (104) [priority 4]
  /// 3. 2x2 square around swap → DragonFly (105) [priority 3]
  /// 4. 4 in a line → PartyPopper (101/102) oriented with the line [priority 2]
  ({Set<Coord> cellsToClear, Map<Coord, int> specialTileSpawns}) processMatches(
    MatchResult matchResult,
    GridModel gridModel, {
    Coord? swapA,
    Coord? swapB,
  }) {
    // Track all cells to clear and special tiles to spawn
    final cellsToClear = <Coord>{};
    final specialTileSpawns = <Coord, int>{}; // Map: spawnCoord -> specialTileTypeId
    final processedCells = <Coord>{}; // Track which cells have been processed
    
    final matches = matchResult.matches;
    
    // Collect all candidates from all pattern types
    final candidates = <_SpecialTileCandidate>[];
    
    // Detect ALL patterns (not just the first one)
    // Rule 1: 5 in a straight line → StickyRice (103) [priority 5]
    final straight5s = _detectAllStraight5(matches);
    for (final match in straight5s) {
      final spawnCoord = _getStraightLineSpawnLocation(match, swapA, swapB);
      candidates.add(_SpecialTileCandidate(
        cells: match.cells.toSet(),
        spawnCoord: spawnCoord,
        specialTypeId: 103, // StickyRice
        priority: 5,
      ));
    }
    
    // Rule 2: T/L union 5-6 → Firecracker (104) [priority 4]
    final tOrLs = _detectAllTOrL(matches, swapA: swapA, swapB: swapB);
    for (final tOrL in tOrLs) {
      if (tOrL.unionSize >= 5 && tOrL.unionSize <= 6) {
        final union = tOrL.horizontalMatch.cells.toSet().union(tOrL.verticalMatch.cells.toSet());
        
        // Determine spawn location: prefer swapB, then swapA, then intersection
        Coord spawnCoord = tOrL.intersection;
        if (swapB != null && union.contains(swapB)) {
          spawnCoord = swapB;
        } else if (swapA != null && union.contains(swapA)) {
          spawnCoord = swapA;
        }
        
        candidates.add(_SpecialTileCandidate(
          cells: union,
          spawnCoord: spawnCoord,
          specialTypeId: 104, // Firecracker
          priority: 4,
        ));
      }
    }
    
    // Rule 3: 2x2 square around swap → DragonFly (105) [priority 3]
    final blockAroundSwap = detect2x2AroundSwap(gridModel, swapA, swapB);
    if (blockAroundSwap != null) {
      final spawnCoord = _getBlockSpawnLocation(blockAroundSwap, swapA, swapB);
      candidates.add(_SpecialTileCandidate(
        cells: blockAroundSwap,
        spawnCoord: spawnCoord,
        specialTypeId: 105, // DragonFly
        priority: 3,
      ));
    }
    
    // Rule 4: 4 in a line → PartyPopper (101/102) oriented with the line [priority 2]
    final straight4s = _detectAllStraight4(matches);
    for (final match in straight4s) {
      // Determine orientation based on whether it's horizontal or vertical
      final isHorizontal = _isHorizontalMatch(match);
      final partyPopperTypeId = isHorizontal ? 101 : 102; // 101 = horizontal, 102 = vertical
      
      final spawnCoord = _getStraightLineSpawnLocation(match, swapA, swapB);
      candidates.add(_SpecialTileCandidate(
        cells: match.cells.toSet(),
        spawnCoord: spawnCoord,
        specialTypeId: partyPopperTypeId,
        priority: 2,
      ));
    }
    
    // Sort candidates by priority (higher priority first), then by deterministic ordering for tie-breaking
    // Deterministic ordering: priority (desc), then spawn row (asc), then spawn col (asc)
    candidates.sort((a, b) {
      // First sort by priority (descending - higher priority first)
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) return priorityCompare;
      
      // For same priority, sort by spawn row (ascending)
      final rowCompare = a.spawnCoord.row.compareTo(b.spawnCoord.row);
      if (rowCompare != 0) return rowCompare;
      
      // For same priority and row, sort by spawn col (ascending)
      return a.spawnCoord.col.compareTo(b.spawnCoord.col);
    });
    
    // Greedily process candidates (non-overlapping patterns spawn special tiles)
    for (final candidate in candidates) {
      // Check if this candidate overlaps with already processed cells
      final overlaps = candidate.cells.any((coord) => processedCells.contains(coord));
      if (!overlaps) {
        // Process this candidate - spawn special tile
        // Clear all cells in the pattern EXCEPT spawn location
        for (final coord in candidate.cells) {
          if (coord != candidate.spawnCoord) {
            cellsToClear.add(coord);
          }
          processedCells.add(coord);
        }
        
        specialTileSpawns[candidate.spawnCoord] = candidate.specialTypeId;
        DebugLogger.specialTile('Pattern detected (priority ${candidate.priority}) → Special tile ${candidate.specialTypeId} at ${candidate.spawnCoord}');
      }
    }
    
    // Clear all remaining matched cells that weren't processed as special tiles
    for (final match in matches) {
      for (final coord in match.cells) {
        if (!processedCells.contains(coord)) {
          cellsToClear.add(coord);
        }
      }
    }
    
    return (
      cellsToClear: cellsToClear,
      specialTileSpawns: specialTileSpawns,
    );
  }
}
