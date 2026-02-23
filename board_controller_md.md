# BoardController.dart - Complete Technical Breakdown

## 📋 Table of Contents
1. [File Overview](#file-overview)
2. [Class Structure & Dependencies](#class-structure--dependencies)
3. [Initialization System](#initialization-system)
4. [Core Algorithms](#core-algorithms)
5. [Swap System](#swap-system)
6. [Cascade Engine](#cascade-engine)
7. [Special Tiles System](#special-tiles-system)
8. [Combo System](#combo-system)
9. [Solvability & Shuffling](#solvability--shuffling)
10. [Callback Architecture](#callback-architecture)
11. [Data Flow](#data-flow)
12. [Advanced Patterns](#advanced-patterns)

---

## 📄 File Overview

**Location:** `lib/src/game/board/board_controller.dart`  
**Lines of Code:** 2,255  
**Purpose:** The game logic engine for the match-3 game

This is the **"brain"** of your game - the **Controller** in the MVC pattern. It:
- **Never touches visuals** (no rendering, no sprites)
- **Mutates GridModel** (the data)
- **Enforces game rules** (what's valid, what creates matches)
- **Orchestrates cascades** (matches → gravity → refill → repeat)
- **Manages special tiles** (power-ups, combos)

**Key Principle:** Pure logic, zero UI. You could swap out the entire rendering engine and this code wouldn't change.

---

## 🏗️ Class Structure & Dependencies

### **Class Declaration**

```dart
class BoardController {
  final GridModel gridModel;       // The game board data
  final StageData stageData;       // Level configuration
  final SfxManager sfxManager;     // Sound effects (injected)
  
  final int rows;
  final int cols;
```

**No inheritance** - This is a plain class (not extending anything). Why?
- Controllers don't need game engine features
- Keeps it testable (no dependencies on Flame/Flutter)
- Pure Dart code

### **Dependencies (Composition)**

```dart
// Instance ID counter for spawning new tiles
int _nextInstanceId = 10000;

// Weighted picker for random tile spawning
WeightedPicker? _picker;
Random? _rng;

// Spawnable tiles list (excludes special tiles)
List<TileDef> _spawnableTiles = [];

// Special tile spawner for handling power-ups
late final SpecialTileSpawner _tileSpawner;

// Special activation resolver for handling special tile activations
late final SpecialActivationResolver _activationResolver;

// Special combo resolver for handling special+special swap combos
late final SpecialComboResolver _comboResolver;
```

**Design Pattern: Composition over Inheritance**

Instead of being a god-class that does everything, BoardController **delegates** to specialized helpers:

1. **`SpecialTileSpawner`**: Pattern recognition (T-shapes, L-shapes, straight 5s)
2. **`SpecialActivationResolver`**: Chain reactions when specials activate
3. **`SpecialComboResolver`**: Special+special combos (bomb+bomb, etc.)
4. **`WeightedPicker`**: Random selection with probability weights

**Why?** Each class has **one responsibility** (Single Responsibility Principle). Easier to test, debug, and modify.

### **Constructor**

```dart
BoardController({
  required this.gridModel,
  required this.stageData,
  required this.sfxManager,  // Dependency injection
})  : rows = gridModel.rows,
      cols = gridModel.cols {
  _rng = Random();
  _initializePicker();
  _tileSpawner = SpecialTileSpawner(rng: _rng!);
  _activationResolver = SpecialActivationResolver(
    spawner: _tileSpawner,
    rows: rows,
    cols: cols,
  );
  _comboResolver = SpecialComboResolver(rng: _rng!);
}
```

**Initializer List** (`: rows = gridModel.rows`):
- Runs **before** constructor body
- Sets final fields that can't be changed later

**Lazy Initialization**:
- Create helper objects in constructor
- They're ready before any methods are called

---

## 🎬 Initialization System

### **1. Instance ID Assignment**

```dart
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

int getNextInstanceId() {
  return _nextInstanceId++;
}
```

**Why?** Tiles need unique IDs for tracking during animations.

**Starting at 10000:** Arbitrary large number to avoid conflicts with typeIds (1-105)

**Post-increment (`++`):**
```dart
_nextInstanceId++;  // Returns current, then increments
// If _nextInstanceId = 10000
// Returns 10000
// Then _nextInstanceId becomes 10001
```

### **2. Board Stabilization**

```dart
void stabilizeInitialBoard() {
  if (stageData.allowInitialMatches) {
    return;  // Skip if initial matches are OK
  }
  
  int rerollCount = 0;
  const maxRerolls = 50;
  
  while (rerollCount < maxRerolls) {
    final matchResult = detectMatches();
    
    if (!matchResult.hasMatches) {
      // No matches - check if board has valid moves
      if (hasPossibleMove()) {
        // Board is stable AND solvable ✓
        return;
      }
      // No matches but also no valid moves - reroll to create solvability
    }
    
    // Reroll matched cells with new random tiles
    if (matchResult.hasMatches) {
      for (final match in matchResult.matches) {
        for (final coord in match.cells) {
          final cell = gridModel.cells[coord.row][coord.col];
          if (cell.isBlocked) continue;
          
          // Only reroll normal tiles (not special tiles)
          if (cell.tileTypeId != null && !_isSpecial(cell.tileTypeId)) {
            final tileDef = _getRandomSpawnableTile();
            if (tileDef != null) {
              cell.tileTypeId = tileDef.id;
              cell.tileInstanceId ??= getNextInstanceId();
            }
          }
        }
      }
    } else {
      // No matches but no valid moves - reroll random cells
      final playableCells = <Coord>[];
      // ... collect playable cells ...
      
      // Reroll 20% of playable cells (or at least 3)
      final rerollAmount = (playableCells.length * 0.2).ceil().clamp(3, playableCells.length);
      playableCells.shuffle(_rng);
      
      for (int i = 0; i < rerollAmount; i++) {
        // ... reroll cell ...
      }
    }
    
    rerollCount++;
  }
}
```

**Algorithm Overview:**
1. Check for matches
2. If matches found → reroll matched tiles
3. If no matches but no valid moves → reroll 20% of board
4. Repeat until board is valid (max 50 attempts)

**Why stabilize?**
- Players expect a clean starting board
- Ensures at least one valid move exists
- Professional game feel

**Safety cap (50 iterations):** Prevents infinite loops on unsolvable configurations

### **3. Weighted Picker Initialization**

```dart
void _initializePicker() {
  if (stageData.tiles.isEmpty) return;
  
  // Filter out special tiles from spawnable tiles
  _spawnableTiles = stageData.tiles.where((t) {
    return !_isSpecial(t.id);  // Exclude 101-105
  }).toList();
  
  if (_spawnableTiles.isEmpty) {
    DebugLogger.warn('No spawnable tiles after filtering specials');
    return;
  }
  
  final weights = _spawnableTiles.map((t) => t.weight).toList();
  _picker = WeightedPicker(weights, _rng!);
}
```

**Why filter out specials?**
- Special tiles (101-105) only spawn from matches
- Regular refill should only use normal tiles (1-6)
- Prevents power-ups from appearing randomly

**WeightedPicker explained:**
```dart
// Stage has:
TileDef(id: 1, weight: 50)  // Banh mi: 50% chance
TileDef(id: 2, weight: 30)  // Pho: 30% chance
TileDef(id: 3, weight: 20)  // Spring roll: 20% chance

// Picker creates cumulative distribution:
// [0-50) → tile 1
// [50-80) → tile 2
// [80-100) → tile 3

// When spawning:
final random = rng.nextInt(100);  // 0-99
if (random < 50) return tile 1
else if (random < 80) return tile 2
else return tile 3
```

---

## 🧠 Core Algorithms

### **1. Match Detection**

```dart
MatchResult detectMatches() {
  final matches = <Match>[];
  
  int? getTileTypeId(Coord coord) {
    if (coord.row < 0 || coord.row >= rows || 
        coord.col < 0 || coord.col >= cols) return null;
    final cell = gridModel.cells[coord.row][coord.col];
    if (cell.bedId == null || cell.bedId! == -1) return null;  // Void cell
    if (cell.isBlocked) return null;  // Blocked cells can't match
    if (_isSpecial(cell.tileTypeId)) return null;  // Ignore special tiles
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
  
  // Detect vertical matches (same logic, swap row/col)
  // ... similar code for columns ...
  
  return MatchResult(matches: matches);
}
```

**Algorithm: Run-Length Encoding**

**Horizontal scan:**
```
Row 3: [1, 1, 1, 2, 2, 3, 3, 3, 3]
       |-------|       |-----------|
       Match!          Match!
```

**Step-by-step:** for row 3:
1. Col 0: tile=1, start run (runStart=0, runLength=1, currentTypeId=1)
2. Col 1: tile=1, same type → runLength=2
3. Col 2: tile=1, same type → runLength=3
4. Col 3: tile=2, different! → End run
   - runLength=3 ≥ 3 → **Match found!** (cols 0-2)
   - Start new run (runStart=3, runLength=1, currentTypeId=2)
5. Col 4: tile=2, runLength=2
6. Col 5: tile=3, different → End run
   - runLength=2 < 3 → No match
   - Start new run (runStart=5, runLength=1, currentTypeId=3)
7. Col 6-8: tile=3, runLength=2,3,4
8. End of row → check final run
   - runLength=4 ≥ 3 → **Match found!** (cols 5-8)

**Time Complexity:** O(rows × cols) - Single pass per row/column

**Why ignore special tiles?**
- Special tiles activate, not match
- Prevents infinite loops (special spawns from match, then matches again)

### **2. Gravity Algorithm**

```dart
void applyGravity() {
  // Process each column independently
  for (int col = 0; col < cols; col++) {
    // From bottom to top, find empty playable cells and fill them
    for (int row = rows - 1; row >= 0; row--) {
      final cell = gridModel.cells[row][col];
      
      // Skip void cells
      if (cell.bedId == null || cell.bedId! == -1) continue;
      
      // Skip blocked cells (blockers are solid barriers)
      if (cell.isBlocked) continue;
      
      // If this cell is empty, find the next tile above it
      if (cell.tileTypeId == null) {
        // Look upward for a tile to drop
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
            break;  // Move to next empty cell
          }
        }
      }
    }
  }
}
```

**Visual Example:**

```
Before gravity:        After gravity:
┌───┬───┬───┐         ┌───┬───┬───┐
│   │ 2 │   │         │   │   │   │  ← Empty (refilled later)
├───┼───┼───┤         ├───┼───┼───┤
│ 1 │   │ 3 │         │   │ 2 │   │  ← Tiles fell
├───┼───┼───┤         ├───┼───┼───┤
│   │ 4 │   │         │ 1 │ 4 │ 3 │  ← Tiles at bottom
└───┴───┴───┘         └───┴───┴───┘
```

**Algorithm Steps:** (for column 1)
1. Row 2 (bottom): Empty
   - Look up: row 1 has tile 4
   - Move 4 down to row 2
   - Clear row 1
2. Row 1: Now empty (just cleared)
   - Look up: row 0 has tile 2
   - Move 2 down to row 1
   - Clear row 0
3. Row 0: Empty
   - Look up: no tiles above
   - Stay empty (will be refilled later)

**Why scan bottom-to-top?**
- Ensures tiles settle properly
- Each tile only moves once
- No need for multiple passes

**Blockers as barriers:**
```
┌───┐
│ 1 │  ← Tile above blocker (stuck)
├───┤
│ X │  ← Blocker (solid)
├───┤
│   │  ← Empty below (won't be filled)
└───┘
```

### **3. Refill Algorithm**

```dart
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
      
      // If empty, spawn a new tile
      if (cell.tileTypeId == null) {
        // Get random spawnable tile (excludes special tiles 101-105)
        final tileDef = _getRandomSpawnableTile();
        if (tileDef != null) {
          cell.tileTypeId = tileDef.id;
          cell.tileInstanceId = getNextInstanceId();
        }
      }
    }
  }
}
```

**Why top-to-bottom?**
- Simulates tiles "falling in" from the top
- Consistent with most match-3 games

**Why new instanceId?**
- Each tile is a new instance (not recycled)
- Prevents animation glitches

**Visual:**
```
BEFORE refill:        AFTER refill:
┌───┬───┬───┐         ┌───┬───┬───┐
│   │   │   │  ← Empty   │ 2 │ 4 │ 1 │  ← New tiles
├───┼───┼───┤         ├───┼───┼───┤
│ 1 │ 5 │ 3 │         │ 1 │ 5 │ 3 │
└───┴───┴───┘         └───┴───┴───┘
```

---

## 🔄 Swap System

### **Swap Validation**

```dart
bool canSwap(Coord a, Coord b) {
  // 1. Check bounds
  if (a.row < 0 || a.row >= rows || a.col < 0 || a.col >= cols) return false;
  if (b.row < 0 || b.row >= rows || b.col < 0 || b.col >= cols) return false;
  
  // 2. Check if cells are playable (not void)
  final cellA = gridModel.cells[a.row][a.col];
  final cellB = gridModel.cells[b.row][b.col];
  if (cellA.bedId == null || cellA.bedId! == -1) return false;
  if (cellB.bedId == null || cellB.bedId! == -1) return false;
  
  // 3. Check if both have tiles
  if (cellA.tileTypeId == null || cellA.tileInstanceId == null) return false;
  if (cellB.tileTypeId == null || cellB.tileInstanceId == null) return false;
  
  // 4. Check if either cell is blocked
  if (cellA.isBlocked) return false;
  if (cellB.isBlocked) return false;
  
  // 5. Check if adjacent (Manhattan distance 1)
  final rowDiff = (a.row - b.row).abs();
  final colDiff = (a.col - b.col).abs();
  if (rowDiff + colDiff != 1) return false;
  
  return true;
}
```

**Manhattan Distance:**
```
Distance = |row1 - row2| + |col1 - col2|

Adjacent cells have distance = 1:
  (2,3) to (2,4) → |2-2| + |3-4| = 0 + 1 = 1 ✓
  (2,3) to (3,3) → |2-3| + |3-3| = 1 + 0 = 1 ✓

Diagonal cells have distance = 2:
  (2,3) to (3,4) → |2-3| + |3-4| = 1 + 1 = 2 ✗
```

### **Swap Execution**

```dart
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
```

**Why swap both IDs?**
- `tileTypeId`: What the tile looks like
- `tileInstanceId`: Identity for tracking during animations

**Temporary variable pattern:**
```dart
// Can't do this:
a = b;
b = a;  // Both are now b!

// Must use temp:
temp = a;
a = b;
b = temp;  // Correct swap ✓
```

### **Swap Validity Check (Simulated)**

```dart
bool _willSwapBeValid(Coord a, Coord b) {
  // Check if either cell contains a special tile
  final hasSpecialTile = _coordHasSpecial(a) || _coordHasSpecial(b);
  if (hasSpecialTile) {
    return true;  // Special tile swaps are always valid
  }
  
  // Create a simulated type getter that returns swapped types
  int? getSimulatedTypeId(Coord coord) {
    // ... get cell ...
    
    // Simulate swap: if coord is a or b, return the other's type
    if (coord == a) {
      return gridModel.cells[b.row][b.col].tileTypeId;
    } else if (coord == b) {
      return gridModel.cells[a.row][a.col].tileTypeId;
    } else {
      return cell.tileTypeId;
    }
  }
  
  // Check if swap would create line match at either position
  if (_wouldMakeLineMatchAt(a, getSimulatedTypeId) ||
      _wouldMakeLineMatchAt(b, getSimulatedTypeId)) {
    return true;
  }
  
  // Check if swap would create 2x2 block around swap
  if (_wouldMake2x2AroundSwap(a, b, getSimulatedTypeId)) {
    return true;
  }
  
  return false;  // No valid configuration found
}
```

**Why simulate?**
- Don't want to actually swap (mutate state)
- Just check **if** swap would be valid
- Used for "undo invalid swap" logic

**Closure pattern:**
```dart
int? getSimulatedTypeId(Coord coord) {
  // This function "closes over" variables a and b
  // It has access to them even though they're not parameters
}
```

### **Swap Processing Pipeline**

```dart
Future<bool> attemptSwap(
  Coord a, Coord b, {
  required Future<void> Function() onSync,
  // ... other callbacks ...
}) async {
  if (!canSwap(a, b)) return false;
  
  // 1. Check if swap will be valid (WITHOUT mutating)
  final willBeValid = _willSwapBeValid(a, b);
  
  // 2. Play sound ONLY for invalid swaps (immediate feedback)
  if (!willBeValid) {
    sfxManager.playConfigured(SfxType.swipe);
  }
  
  // 3. Perform swap (mutate state)
  swapCells(a, b);
  
  // 4. Show swap animation
  await onSync();
  await Future.delayed(const Duration(milliseconds: 150));
  
  // 5. Check for matches after swap
  final matchResult = detectMatches();
  final blockCellsSet = _tileSpawner.detect2x2AroundSwap(gridModel, a, b);
  final hasSpecialTile = _coordHasSpecial(a) || _coordHasSpecial(b);
  
  // 6. If no matches, no 2x2, and no special tile → swap back
  if (!matchResult.hasMatches && blockCellsSet == null && !hasSpecialTile) {
    swapCells(a, b);  // Undo swap
    await onSync();
    await Future.delayed(const Duration(milliseconds: 150));
    return false;
  }
  
  // 7. Valid swap - run cascade
  await runCascade(
    onSync: onSync,
    onMatchCleared: onMatchCleared,
    onSpecialActivated: onSpecialActivated,
    swapA: a,
    swapB: b,
    chosenCoord: chosenCoord,
  );
  
  return true;
}
```

**State Machine:**

```
User swaps A ↔ B
      ↓
  Validate (canSwap)
      ↓ yes
  Simulate (willBeValid)
      ↓
  ┌──────────┐
  │ Invalid? │
  └────┬─────┘
       │ yes
       ├─→ Play "swipe" sound
       │   Swap cells
       │   Animate swap
       │   Swap back
       │   Animate swap-back
       │   Return false
       │
       │ no
       ↓
  Play "bloop" sound
  Swap cells
  Animate swap
  Check matches
      ↓
  Run cascade
  Return true
```

---

## 🌊 Cascade Engine

### **Cascade Loop**

```dart
Future<bool> runCascade({
  required Future<void> Function() onSync,
  Future<void> Function(MatchResult)? onMatchCleared,
  Future<void> Function(Map<Coord, int>, ...)? onSpecialActivated,
  int maxCascades = 10,
  Coord? swapA,
  Coord? swapB,
  Coord? chosenCoord,
}) async {
  int cascadeCount = 0;
  
  while (cascadeCount < maxCascades) {
    // 1. Detect matches
    final matchResult = detectMatches();
    final all2x2Blocks = _tileSpawner.detectAll2x2Blocks(gridModel);
    
    // 2. If no matches and no 2x2 blocks → cascade complete
    if (!matchResult.hasMatches && all2x2Blocks.isEmpty) {
      if (cascadeCount > 0) {
        DebugLogger.cascade('Completed after $cascadeCount cascade(s)');
      }
      return cascadeCount > 0;
    }
    
    cascadeCount++;
    
    // 3. Arm match SFX (will play when tiles clear)
    _armMatchSfx();
    
    // 4. Clear matched cells with special tile spawning
    await clearMatchedCells(
      matchResult,
      swapA: cascadeCount == 1 ? swapA : null,  // Only first cascade
      swapB: cascadeCount == 1 ? swapB : null,
      chosenCoord: cascadeCount == 1 ? chosenCoord : null,
      onSpecialActivated: onSpecialActivated,
      onSync: onSync,
    );
    
    // 5. Spawn particles
    if (onMatchCleared != null) {
      await onMatchCleared(matchResult);
    }
    
    // 6. Sync and delay
    await onSync();
    await Future.wait([
      _playPendingBlockerBreaks(),
      Future.delayed(const Duration(milliseconds: 180)),
    ]);
    
    // 7. Apply gravity
    applyGravity();
    await onSync();
    await Future.delayed(const Duration(milliseconds: 300));
    
    // 8. Refill
    refill();
    await onSync();
    await Future.delayed(const Duration(milliseconds: 150));
    
    // 9. Check solvability (shuffle if needed)
    await ensureSolvableOrShuffle(
      onSync: onSync,
      onNoMovesDetected: onNoMovesDetected,
    );
  }
  
  // Safety cap reached
  if (cascadeCount >= maxCascades) {
    DebugLogger.warn('Reached max cascade limit ($maxCascades)');
  }
  
  return true;
}
```

**Cascade Flow:**

```
┌─────────────────┐
│ Detect Matches  │
└────────┬────────┘
         │
    ┌────▼─────┐
    │ Matches? │
    └────┬─────┘
         │ yes
         ▼
┌────────────────────┐
│ Clear Matched Cells│
│ (+ spawn specials) │
└────────┬───────────┘
         ▼
┌────────────────┐
│ Apply Gravity  │
└────────┬───────┘
         ▼
┌────────────────┐
│     Refill     │
└────────┬───────┘
         │
         └─────→ Loop (max 10 times)
```

**Why max 10 cascades?**
- Safety cap to prevent infinite loops
- In practice, rarely exceeds 5-6 cascades
- Protects against bugs in special tile logic

**Why swap coords only on first cascade?**
- Swap location matters for special tile spawn preference
- Subsequent cascades are chain reactions (no user intent)

### **Timing Breakdown**

```dart
// Clear animation
await onSync();                                    // Instant
await Future.wait([
  _playPendingBlockerBreaks(),                    // Variable (staggered)
  Future.delayed(const Duration(milliseconds: 180)),  // 180ms
]);

// Gravity animation
applyGravity();                                    // Instant (mutates model)
await onSync();                                    // Instant (triggers animation)
await Future.delayed(const Duration(milliseconds: 300));  // 300ms

// Refill animation
refill();                                          // Instant
await onSync();                                    // Instant
await Future.delayed(const Duration(milliseconds: 150));  // 150ms

// TOTAL per cascade: ~630ms + blocker animations
```

**Why these durations?**
- **180ms clear**: Quick enough to feel responsive
- **300ms gravity**: Smooth falling motion
- **150ms refill**: Brief "pop-in" effect
- Tuned for 60 FPS animations

**`Future.wait()` explained:**
```dart
// Run multiple async operations in parallel
await Future.wait([
  operation1(),  // Starts immediately
  operation2(),  // Starts immediately
]);
// Continues when BOTH complete
```

---

## 🎯 Special Tiles System

### **Special Tile Detection**

```dart
bool _isSpecial(int? tileTypeId) {
  if (tileTypeId == null) return false;
  return tileTypeId >= 101 && tileTypeId <= 105;
}
```

**Special Tile IDs:**
- **101**: Party Popper (horizontal)
- **102**: Party Popper (vertical)
- **103**: Sticky Rice Bomb
- **104**: Firecracker
- **105**: Dragonfly

**Why check in match detection?**
- Special tiles don't match
- They activate when matched/swapped
- Prevents infinite loops

### **Clear Callback System**

```dart
Future<Map<Coord, int>> _emitCellsCleared(
  Set<Coord> cellsToClear, 
  {bool isRegularClear = true}
) async {
  if (cellsToClear.isEmpty) return {};
  
  // 1. Build map of cleared cells with their tileTypeIds (BEFORE clearing)
  final clearedCellsWithTypes = <Coord, int>{};
  
  for (final coord in cellsToClear) {
    final cell = gridModel.cells[coord.row][coord.col];
    if (cell.bedId != null && cell.bedId! != -1) {
      final tileTypeId = cell.tileTypeId;
      if (tileTypeId != null) {
        // Only include victim tiles (not special tiles)
        if (!_isSpecial(tileTypeId)) {
          clearedCellsWithTypes[coord] = tileTypeId;
        }
      }
      // Actually clear the cell
      cell.tileTypeId = null;
      cell.tileInstanceId = null;
    }
  }
  
  // 2. Play pending match SFX
  if (hasRegularTileCleared && _pendingMatchSfxTypeId != null) {
    _playMatchSound();
    _pendingMatchSfxTypeId = null;
  }
  
  // 3. Emit callback
  await _onCellsClearedWithTypes!(clearedCellsWithTypes);
  
  // 4. Handle blocker breaks (if regular clear)
  if (isRegularClear) {
    // ... detect adjacent blockers ...
    _pendingBlockerBreaks.addAll(scooterBlockersToBreak);
  }
  
  return clearedCellsWithTypes;
}
```

**Key Insights:**

1. **Capture BEFORE clearing:** Need to know what was there for particles
2. **Filter specials:** Don't count power-ups as "collected"
3. **isRegularClear flag:**
   - `true`: Normal matches → break adjacent blockers
   - `false`: Special activations → don't break blockers
4. **Batch blocker breaks:** Store in set, play later (performance)

**Why return Map?**
- Caller knows exactly what was cleared
- Can spawn appropriate particle types
- Can update objectives (collect X of tile Y)

### **Special Activation Flow**

```dart
Future<Map<Coord, int>> clearMatchedCells(
  MatchResult matchResult, {
  Coord? swapA,
  Coord? swapB,
  Coord? chosenCoord,
  Future<void> Function(Map<Coord, int>, ...)? onSpecialActivated,
  Future<void> Function()? onSync,
}) async {
  // 1. Process matches to get cells to clear and special tiles to spawn
  final result = _tileSpawner.processMatches(
    matchResult,
    gridModel,
    swapA: swapA,
    swapB: swapB,
  );
  final specialTileSpawns = result.specialTileSpawns;
  
  // 2. Create initial clearing set, EXCLUDING spawn locations
  final initialCellsToClear = <Coord>{...result.cellsToClear};
  initialCellsToClear.removeAll(specialTileSpawns.keys);
  
  // 3. Check if this is a special+special combo swap
  final isSpecialCombo = swapA != null && swapB != null &&
      _coordHasSpecial(swapA) && _coordHasSpecial(swapB);
  
  if (isSpecialCombo) {
    final comboResult = _comboResolver.resolveCombo(
      grid: gridModel,
      a: swapA,
      b: swapB,
      chosenCoord: chosenCoord,
    );
    
    if (comboResult.isCombo) {
      // Run combo steps sequentially
      return await _runComboSteps(
        comboResult: comboResult,
        swapA: swapA,
        swapB: swapB,
        onSpecialActivated: onSpecialActivated,
        onSync: onSync,
      );
    }
  }
  
  // 4. Normal special activation (not a combo)
  final expanded = _activationResolver.expandClearsWithSpecials(
    gridModel: gridModel,
    initialToClear: initialCellsToClear,
    swapA: swapA,
    swapB: swapB,
    chosenCoord: chosenCoord,
  );
  
  Set<Coord> cellsToClear = expanded.cellsToClear;
  Map<Coord, int> activatedSpecials = expanded.activatedSpecials;
  Map<Coord, (...)> vfxMetadata = expanded.vfxMetadata;
  
  // 5. Spawn special tiles
  for (final entry in specialTileSpawns.entries) {
    final coord = entry.key;
    final specialTypeId = entry.value;
    final cell = gridModel.cells[coord.row][coord.col];
    cell.tileTypeId = specialTypeId;
    // Keep tileInstanceId unchanged (identity preserved)
  }
  
  // 6. Separate VFX-controlled specials from others
  final partyPopperCells = <Coord>{};
  final firecrackerCells = <Coord>{};
  
  for (final entry in activatedSpecials.entries) {
    if (entry.value == 101 || entry.value == 102) {
      // Party Poppers handle their own clearing
      partyPopperCells.add(...);
    } else if (entry.value == 104) {
      // Firecrackers handle their own clearing
      firecrackerCells.add(...);
    }
  }
  
  // 7. Remove VFX-controlled cells from main clearing set
  final otherCellsToClear = cellsToClear
      .difference(partyPopperCells)
      .difference(firecrackerCells);
  
  // 8. Play VFX in priority order
  if (onSpecialActivated != null && activatedSpecials.isNotEmpty) {
    await onSpecialActivated(activatedSpecials, vfxMetadata);
  }
  
  // 9. Clear non-VFX cells
  await _emitCellsCleared(otherCellsToClear, isRegularClear: true);
  
  return activatedSpecials;
}
```

**Priority System:**

```dart
int getPriority(int tileTypeId) {
  if (tileTypeId == 105) return 4;  // DragonFly (highest)
  if (tileTypeId == 103) return 3;  // Sticky Rice Bomb
  if (tileTypeId == 101 || tileTypeId == 102) return 2;  // Party Popper
  if (tileTypeId == 104) return 1;  // Firecracker (lowest)
  return 0;
}
```

**Why priority?**
- DragonFly targets specific tile → must identify target before clearing
- Sticky Rice clears area → needs to know what's available
- Party Popper and Firecracker → VFX handles timing

**VFX-controlled clearing:**
- Party Popper shoots projectiles → clears when projectile hits
- Firecracker explodes → clears at visual impact
- Controller doesn't clear these → VFX does via callback

---

## 💥 Combo System

### **Combo Detection**

```dart
// Check if this is a special+special combo swap
final isSpecialCombo = swapA != null && swapB != null &&
    _coordHasSpecial(swapA) && _coordHasSpecial(swapB);

if (isSpecialCombo) {
  final comboResult = _comboResolver.resolveCombo(
    grid: gridModel,
    a: swapA,
    b: swapB,
    chosenCoord: chosenCoord,
  );
  
  if (comboResult.isCombo) {
    // It's a combo! Run combo steps
    return await _runComboSteps(...);
  } else {
    // Not a recognized combo - use normal activation
  }
}
```

**Combo Types:**
- **101+101**: Horizontal + Horizontal → Clear all rows
- **102+102**: Vertical + Vertical → Clear all columns
- **101+102**: Horizontal + Vertical → Clear entire cross
- **103+103**: Bomb + Bomb → Clear ALL regular tiles
- **104+104**: Firecracker + Firecracker → Big explosion
- **105+X**: Dragonfly + Any → Color burst

### **Combo Step Execution**

```dart
Future<Map<Coord, int>> _runComboSteps({
  required SpecialComboResult comboResult,
  Coord? swapA,
  Coord? swapB,
  Future<void> Function(Map<Coord, int>, ...)? onSpecialActivated,
  Future<void> Function()? onSync,
}) async {
  final activatedSpecials = <Coord, int>{};
  
  // Iterate through combo steps in order
  for (int i = 0; i < comboResult.steps.length; i++) {
    final step = comboResult.steps[i];
    
    // Skip cleanup steps for VFX
    if (step.type != ComboStepType.cleanup && onSpecialActivated != null) {
      // Determine special type and metadata based on step type
      int specialTypeId;
      Coord? vfxCoord;
      Coord? targetCoord;
      Set<Coord>? activationCells;
      
      switch (step.type) {
        case ComboStepType.prehit:
          specialTypeId = 105;  // DragonFly
          vfxCoord = step.center;
          targetCoord = step.randomTargetCoord;
          break;
        
        case ComboStepType.lineRow:
          specialTypeId = 101;  // Party Popper horizontal
          vfxCoord = step.center;
          activationCells = step.cells;
          break;
        
        case ComboStepType.lineCol:
          specialTypeId = 102;  // Party Popper vertical
          vfxCoord = step.center;
          activationCells = step.cells;
          break;
        
        case ComboStepType.bomb3x3:
          specialTypeId = 104;  // Firecracker
          vfxCoord = step.center;
          activationCells = step.cells;
          break;
        
        case ComboStepType.colorAllOfType:
        case ComboStepType.clearAllRegular:
          specialTypeId = 103;  // Sticky Rice
          vfxCoord = step.center;
          activationCells = step.cells;
          break;
        
        case ComboStepType.cleanup:
          continue;
      }
      
      // Trigger VFX for this step
      if (vfxCoord != null) {
        activatedSpecials[vfxCoord] = specialTypeId;
        final stepMetadata = <Coord, (...)>{
          vfxCoord: (
            targetCoord: targetCoord,
            activationCells: activationCells,
          ),
        };
        await onSpecialActivated({vfxCoord: specialTypeId}, stepMetadata);
      }
    }
    
    // Clear cells for this step
    await _emitCellsCleared(step.cells);
    
    // Sync and delay for visuals
    if (onSync != null) {
      await onSync();
      await Future.delayed(const Duration(milliseconds: 90));
    }
  }
  
  return activatedSpecials;
}
```

**ComboStep types:**
- **prehit**: DragonFly targeting animation
- **lineRow**: Clear entire row
- **lineCol**: Clear entire column
- **bomb3x3**: 3×3 explosion
- **colorAllOfType**: Clear all of one color
- **clearAllRegular**: Clear all normal tiles
- **cleanup**: Final cleanup (remove special tiles themselves)

**Sequential execution:**
```
Step 1: DragonFly prehit
  ↓ (90ms delay)
Step 2: Clear horizontal line
  ↓ (90ms delay)
Step 3: Clear vertical line
  ↓ (90ms delay)
Step 4: Cleanup (remove special tiles)
```

**Why sequential?**
- Each step has its own visual effect
- Players can see each part of the combo
- More satisfying than instant clear

---

## 🔀 Solvability & Shuffling

### **Possible Move Detection**

```dart
bool hasPossibleMove() {
  return BoardSolvability.hasPossibleMove(
    gridModel: gridModel,
    tileSpawner: _tileSpawner,
    canSwap: canSwap,
    detectMatches: detectMatches,
  );
}
```

**Algorithm (in BoardSolvability):**

```dart
// Try every possible swap
for (int row = 0; row < rows; row++) {
  for (int col = 0; col < cols; col++) {
    final coord = Coord(row, col);
    
    // Try swapping with right neighbor
    final right = Coord(row, col + 1);
    if (canSwap(coord, right)) {
      if (_wouldSwapBeValid(coord, right)) {
        return true;  // Found a valid move!
      }
    }
    
    // Try swapping with bottom neighbor
    final bottom = Coord(row + 1, col);
    if (canSwap(coord, bottom)) {
      if (_wouldSwapBeValid(coord, bottom)) {
        return true;  // Found a valid move!
      }
    }
  }
}

return false;  // No valid moves found
```

**Time Complexity:** O(rows × cols)
- Each cell checks at most 2 swaps (right, down)
- Total swaps checked: ~(rows × cols × 2)

**Why only check right/down?**
- Avoid duplicate checks
- (A→B) is same as (B→A)
- Checking all 4 directions would test each swap twice

### **Shuffle Algorithm**

```dart
Future<void> ensureSolvableOrShuffle({
  required Future<void> Function() onSync,
  Future<void> Function()? onNoMovesDetected,
}) async {
  // 1. Never shuffle if special tiles exist
  if (hasAnySpecialTile()) {
    DebugLogger.boardController('Shuffle skipped (special tile present)');
    return;
  }
  
  // 2. Check if moves exist
  if (hasPossibleMove()) {
    return;  // Board is solvable
  }
  
  // 3. Notify caller (show modal)
  if (onNoMovesDetected != null) {
    await onNoMovesDetected();
  }
  
  // 4. Collect all playable cells with tiles
  final playableCells = <Coord>[];
  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      final cell = gridModel.cells[row][col];
      if (cell.bedId != null && cell.bedId != -1 && 
          cell.tileTypeId != null && !cell.isBlocked) {
        playableCells.add(Coord(row, col));
      }
    }
  }
  
  // 5. Extract current tiles (typeId, instanceId pairs)
  final tiles = playableCells.map((coord) {
    final cell = gridModel.cells[coord.row][coord.col];
    return (typeId: cell.tileTypeId!, instanceId: cell.tileInstanceId!);
  }).toList();
  
  // 6. Try to shuffle up to 50 times
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
      shuffleSuccess = true;
      break;
    }
  }
  
  // 7. Fallback: reroll all tiles if shuffle failed
  if (!shuffleSuccess) {
    // ... reroll all tiles ...
  }
  
  // 8. Sync UI once
  await onSync();
}
```

**Shuffle Strategy:**

1. **Extract tiles:** Get all tile (typeId, instanceId) pairs
2. **Shuffle:** Randomize order using Fisher-Yates algorithm
3. **Apply:** Redistribute to same positions (different tiles at each coord)
4. **Validate:** Check no matches + has valid move
5. **Retry:** Up to 50 attempts
6. **Fallback:** If all shuffles fail, reroll random tiles

**Why preserve instanceIds?**
- Smooth transitions (no tile "identity" change)
- Animations track the same object moving

**Why max 50 attempts?**
- Shuffle is random → might take many tries
- Safety cap prevents infinite loops
- Fallback ensures progress

**Fisher-Yates shuffle:**
```dart
tiles.shuffle(_rng);

// Internally does:
for (i = n-1; i > 0; i--) {
  j = random(0, i);
  swap tiles[i] and tiles[j]
}
```

---

## 🔌 Callback Architecture

### **Callback Registration**

```dart
// Generic clear callback
Future<void> Function(Map<Coord, int>)? _onCellsClearedWithTypes;

void setOnCellsClearedWithTypes(
  Future<void> Function(Map<Coord, int>)? callback
) {
  _onCellsClearedWithTypes = callback;
}

// Blocker callbacks
Future<void> Function(Coord)? onBlockerBreak;
void Function(Coord)? onBlockerCleared;

void setOnBlockerBreak(Future<void> Function(Coord)? callback) {
  onBlockerBreak = callback;
}

void setOnBlockerCleared(void Function(Coord)? callback) {
  onBlockerCleared = callback;
}
```

**Why callbacks?**
- **Loose coupling:** Controller doesn't know about BoardGame
- **Testability:** Can inject mock callbacks
- **Flexibility:** Different implementations (particles, UI updates, logging)

**Nullable callbacks (`?`):**
- Callbacks are optional
- Always check `if (callback != null)` before calling

### **Callback Invocation Patterns**

```dart
// Pattern 1: Simple synchronous callback
onBlockerCleared?.call(coord);

// Pattern 2: Async callback with await
if (onBlockerBreak != null) {
  await onBlockerBreak!(coord);
}

// Pattern 3: Async callback with error handling
if (_onCellsClearedWithTypes != null) {
  try {
    await _onCellsClearedWithTypes!(clearedCellsWithTypes);
  } catch (e, st) {
    DebugLogger.error('Clear callback error: $e\n$st');
  }
}
```

**Null-aware call (`?.call`):**
```dart
// Long form:
if (callback != null) {
  callback(arg);
}

// Short form:
callback?.call(arg);
```

**Force unwrap (`!`):**
```dart
// We know it's not null (just checked)
if (callback != null) {
  await callback!(arg);  // Safe - we verified above
}
```

### **Callback Data Flow**

```
BoardController                BoardGame
      │                             │
      │  setOnCellsClearedWithTypes │
      │────────────────────────────>│
      │                             │ Store callback
      │                             │
      │  (User swaps tiles)         │
      │                             │
      │  clearMatchedCells()        │
      │    ↓                        │
      │  _emitCellsCleared()        │
      │    ↓                        │
      │  _onCellsClearedWithTypes!  │
      │────────────────────────────>│
      │                             │ Spawn particles
      │                             │ Update objectives
      │                             │
      │<────────────────────────────│
      │  (callback complete)        │
```

---

## 📊 Data Flow

### **Complete Swap-to-Cascade Flow**

```
User Input (BoardGame)
      ↓
attemptSwap(a, b)
      ↓
┌──────────────────────────┐
│ 1. Validate: canSwap     │
│ 2. Simulate: willBeValid │
│ 3. Execute: swapCells    │
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│ 4. Sync: onSync()        │ ← BoardGame updates visuals
│ 5. Delay: 150ms          │
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│ 6. Detect: detectMatches │
└──────────┬───────────────┘
           ↓
    ┌──────▼───────┐
    │ Valid swap?  │
    └──────┬───────┘
           │ no → swap back, return false
           │ yes
           ↓
┌──────────────────────────┐
│ runCascade               │
└──────────┬───────────────┘
           ↓
    ┌────────────────────┐
    │ LOOP (max 10x):    │
    │                    │
    │ 1. detectMatches   │
    │      ↓ none?       │
    │      └→ exit loop  │
    │                    │
    │ 2. clearMatches    │
    │    • processMatches│
    │    • spawnSpecials │
    │    • expandClears  │
    │    • playVFX       │
    │    • emitCleared   │
    │      ↓             │
    │ 3. onSync          │
    │ 4. Delay 180ms     │
    │      ↓             │
    │ 5. applyGravity    │
    │ 6. onSync          │
    │ 7. Delay 300ms     │
    │      ↓             │
    │ 8. refill          │
    │ 9. onSync          │
    │ 10. Delay 150ms    │
    │      ↓             │
    │ 11. shuffle check  │
    │      ↓             │
    │      └─→ LOOP      │
    └────────────────────┘
           ↓
     return true
```

### **State Mutations During Cascade**

```
Initial State:
┌───┬───┬───┐
│ 1 │ 2 │ 3 │
│ 1 │ 2 │ 4 │
│ 1 │ 5 │ 6 │
└───┴───┴───┘

After detectMatches:
Found match: [(0,0), (1,0), (2,0)]  // Column of 1s

After clearMatches:
┌───┬───┬───┐
│   │ 2 │ 3 │  ← Cleared
│   │ 2 │ 4 │  ← Cleared
│   │ 5 │ 6 │  ← Cleared
└───┴───┴───┘

After applyGravity:
┌───┬───┬───┐
│   │   │   │  ← Empty (top)
│   │ 2 │ 3 │  ← Fell
│   │ 2 │ 4 │  ← Fell
│   │ 5 │ 6 │  ← Stayed
└───┴───┴───┘
  Wait, column 0 is glitched... Let me re-trace:
  
Actually correct trace:
Initial:
┌───┬───┬───┐
│ 1 │ 2 │ 3 │
│ 1 │ 2 │ 4 │
│ 1 │ 5 │ 6 │
└───┴───┴───┘

After clear (col 0 matched):
┌───┬───┬───┐
│   │ 2 │ 3 │
│   │ 2 │ 4 │
│   │ 5 │ 6 │
└───┴───┴───┘

After gravity (nothing falls - column 0 stays empty):
┌───┬───┬───┐
│   │ 2 │ 3 │
│   │ 2 │ 4 │
│   │ 5 │ 6 │
└───┴───┴───┘

After refill:
┌───┬───┬───┐
│ 7 │ 2 │ 3 │  ← New tile
│ 8 │ 2 │ 4 │  ← New tile
│ 9 │ 5 │ 6 │  ← New tile
└───┴───┴───┘

Check matches again → if found, loop continues
```

---

## 🎓 Advanced Patterns

### **1. Strategy Pattern (Delegation)**

```dart
// Instead of doing everything in BoardController:
class BoardController {
  late final SpecialTileSpawner _tileSpawner;
  late final SpecialActivationResolver _activationResolver;
  late final SpecialComboResolver _comboResolver;
  
  // Delegate to specialized helpers
  final result = _tileSpawner.processMatches(...);
  final expanded = _activationResolver.expandClearsWithSpecials(...);
  final combo = _comboResolver.resolveCombo(...);
}
```

**Benefits:**
- Each class has one job
- Easier to test individual components
- Can swap implementations

### **2. Builder Pattern (Incremental Construction)**

```dart
// Build clearing set incrementally
final cellsToClear = <Coord>{};
cellsToClear.addAll(matchResult.allMatchedCells);
cellsToClear.addAll(specialActivationCells);
cellsToClear.removeAll(spawnLocations);
cellsToClear.removeAll(vfxControlledCells);

// Final set is ready
await _emitCellsCleared(cellsToClear);
```

**Why?** Complex rules for what to clear:
- Start with matches
- Add special activations
- Remove spawn locations (don't clear newly spawned specials)
- Remove VFX-controlled (they handle their own timing)

### **3. Template Method Pattern (Cascade)**

```dart
// Cascade = template with fixed steps
Future<bool> runCascade(...) async {
  while (...) {
    // 1. Detect (varies)
    final matches = detectMatches();
    
    // 2. Clear (varies)
    await clearMatchedCells(matches, ...);
    
    // 3. Gravity (fixed algorithm)
    applyGravity();
    
    // 4. Refill (fixed algorithm)
    refill();
    
    // 5. Validate (varies)
    await ensureSolvableOrShuffle(...);
  }
}
```

**Template:** Steps are fixed, implementation varies

### **4. Callback Pattern (Observer)**

```dart
// Controller = Subject
// BoardGame = Observer

// Register observer
controller.setOnCellsClearedWithTypes((cells) async {
  // Observer reacts to event
  spawnParticles(cells);
  updateObjectives(cells);
});

// Subject notifies
await _onCellsClearedWithTypes!(clearedCells);
```

**Benefits:**
- Decoupling (Controller doesn't know Observer)
- Multiple observers possible
- Easy to add new reactions

### **5. Guard Pattern (Early Returns)**

```dart
void refill() {
  // Guards at the top
  if (_picker == null || _spawnableTiles.isEmpty) return;
  
  // Main logic below (only runs if guards pass)
  for (int col = 0; col < cols; col++) {
    // ...
  }
}
```

**Why?** Cleaner than nested ifs:

```dart
// ❌ Without guards (nested)
void refill() {
  if (_picker != null) {
    if (_spawnableTiles.isNotEmpty) {
      for (...) {
        // Main logic deep inside
      }
    }
  }
}

// ✅ With guards (flat)
void refill() {
  if (_picker == null) return;
  if (_spawnableTiles.isEmpty) return;
  
  for (...) {
    // Main logic at top level
  }
}
```

### **6. Flag Pattern (State Tracking)**

```dart
int? _pendingMatchSfxTypeId;

// Arm the flag
void _armMatchSfx() {
  _pendingMatchSfxTypeId = 1;
}

// Check and clear the flag
if (_pendingMatchSfxTypeId != null) {
  _playMatchSound();
  _pendingMatchSfxTypeId = null;  // Clear
}
```

**Why?** Defer action until later:
- Arm when match detected
- Play when tiles actually clear
- Ensures correct timing

### **7. Batch Processing Pattern**

```dart
// Collect items to process
final blockerCoords = <Coord>{};
for (final clearedCoord in coordsBeingCleared) {
  // ... find adjacent blockers ...
  blockerCoords.add(neighbor);
}

// Process batch later
Future<void> _playPendingBlockerBreaks() async {
  final futures = <Future<void>>[];
  for (int i = 0; i < blockers.length; i++) {
    futures.add(Future(() async {
      await Future.delayed(Duration(milliseconds: stagger * i));
      await _playScooterBreakAnimation(blockers[i]);
    }));
  }
  await Future.wait(futures);  // All in parallel with stagger
}
```

**Benefits:**
- Collect during scan (no extra loop)
- Process later (when convenient)
- Stagger timing (visual polish)

---

## 💡 Key Takeaways

### **Architecture Principles**

1. **Single Responsibility:** Each class/method does one thing well
2. **Separation of Concerns:** Logic separate from visuals
3. **Dependency Injection:** Pass dependencies, don't create them
4. **Callbacks for Communication:** Loose coupling between layers
5. **Immutable Configuration:** StageData never changes during game

### **Algorithm Insights**

1. **Run-Length Encoding:** Efficient match detection (single pass)
2. **Gravity by Column:** Independent columns, bottom-to-top scan
3. **Weighted Random:** Probability-based tile spawning
4. **Shuffle Validation:** Random permutation with constraints
5. **Cascade Loop:** Repeat until no matches (max 10 safety cap)

### **Performance Techniques**

1. **Early Returns:** Guards prevent unnecessary work
2. **Set Operations:** Fast membership tests (O(1))
3. **Batch Processing:** Group operations to reduce overhead
4. **Parallel Awaits:** `Future.wait()` for concurrent operations
5. **Lazy Initialization:** Create only when needed

### **Best Practices**

1. **Defensive Programming:** Null checks, bounds checks, safety caps
2. **Debug Logging:** Trace execution for troubleshooting
3. **Clear Naming:** Functions describe what they do
4. **Comments for Complex Logic:** Explain **why**, not **what**
5. **Consistent Patterns:** Same approach for similar problems

---

## 🎯 Practical Application

### **To Add a New Feature:**

**1. New tile type:**
- Add to `stageData.tiles` in JSON
- Update `_isSpecial()` if it's a power-up (101+)
- Add clearing logic in `clearMatchedCells()`

**2. New match rule:**
- Modify `detectMatches()` algorithm
- Update validation in `_willSwapBeValid()`
- Adjust `hasPossibleMove()` check

**3. New special combo:**
- Add to `SpecialComboResolver.resolveCombo()`
- Define combo steps in `ComboStep` enum
- Handle in `_runComboSteps()` switch

**4. New blocker type:**
- Add to `BlockerType` enum in `grid_model.dart`
- Add clearing logic in `_emitCellsCleared()`
- Create VFX in new file

### **Common Debugging Patterns**

**1. Tiles disappearing:**
```dart
// Check: Are they being cleared unexpectedly?
// Add logging in _emitCellsCleared
DebugLogger.log('Clearing: $coord, type: $tileTypeId');
```

**2. Infinite cascade:**
```dart
// Check: maxCascades reached?
// Add counter logging
DebugLogger.cascade('Cascade #$cascadeCount');
```

**3. Special not activating:**
```dart
// Check: Is it in activatedSpecials map?
DebugLogger.specialTile('Activated: $activatedSpecials');
```

**4. No valid moves:**
```dart
// Check: hasPossibleMove() logic
// Try manual swap simulation
final valid = _willSwapBeValid(coord1, coord2);
DebugLogger.log('Swap $coord1↔$coord2: $valid');
```

---

## 📚 Further Exploration

**Related Files:**
- [board_game.dart](board_game_md.md) - Visual rendering
- `special_tile_spawner.dart` - Pattern recognition
- `special_activation_resolver.dart` - Chain reactions
- `special_combo_resolver.dart` - Combo logic
- `board_solvability.dart` - Move detection

**Concepts to Study:**
- State machines (swap validation)
- Graph algorithms (match detection is pattern matching)
- Randomness with constraints (shuffle, weighted spawning)
- Event-driven architecture (callbacks)
- Async programming (cascades, animations)

---

## 🚀 Congratulations!

You now understand the **logic engine** of a production match-3 game! The patterns here apply to many game types:
- Turn-based games (chess, card games)
- Puzzle games (Tetris, 2048)
- Strategy games (tower defense)

**Key Insight:** Games are **state machines** with **rules**. The controller:
1. Stores state (GridModel)
2. Enforces rules (canSwap, detectMatches)
3. Mutates state (swapCells, applyGravity)
4. Notifies observers (callbacks)

Keep exploring and building! 🎮
