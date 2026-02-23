# BoardGame.dart - Complete Technical Breakdown

## 📋 Table of Contents
1. [File Overview](#file-overview)
2. [Class Declaration & Inheritance](#class-declaration--inheritance)
3. [Data Structures](#data-structures)
4. [Constructor Deep Dive](#constructor-deep-dive)
5. [Coordinate System](#coordinate-system)
6. [Input Handling](#input-handling)
7. [Synchronization System](#synchronization-system)
8. [Visual Effects Integration](#visual-effects-integration)
9. [Lifecycle Methods](#lifecycle-methods)
10. [Advanced Patterns](#advanced-patterns)

---

## 📄 File Overview

**Location:** `lib/src/game/board/board_game.dart`  
**Lines of Code:** 1,039  
**Purpose:** The visual rendering engine for the match-3 board game

This file is the **view** layer of the game - it handles everything players see and interact with. It uses the **Flame** game engine (Flutter's 2D game framework) to render tiles, animate movements, handle touch input, and coordinate visual effects.

---

## 🎯 Class Declaration & Inheritance

```dart
class BoardGame extends FlameGame with TapCallbacks {
```

### Breaking This Down:

#### 1. **extends FlameGame**
```dart
extends FlameGame
```
- **What it means:** BoardGame **IS-A** FlameGame (inheritance relationship)
- **What you get:** Complete game engine with rendering loop, component management, camera system
- **Game Loop:** Flame automatically calls `update(dt)` and `render()` 60 times per second
- **Component System:** Can add/remove visual elements (tiles, particles, effects)

**Think of it like:** FlameGame is a car engine, BoardGame is the specific car model that uses that engine

#### 2. **with TapCallbacks** (Mixin)
```dart
with TapCallbacks
```
- **What it means:** Adds tap/touch detection abilities
- **What you get:** `onTapDown()`, `onTapUp()`, `onTapCancel()` methods
- **Why mixin not inheritance?** Dart doesn't support multiple inheritance, mixins let you "mix in" functionality

**Analogy:** Like adding power windows to a car - it's an extra feature, not a fundamental part

---

## 🗄️ Data Structures

The class uses **multiple lookup tables** (Maps) for performance. Let's understand each one:

### **1. The Tile Registries**

```dart
// Registry for tile components - keyed by instanceId for stable identity
final Map<int, TileComponent> tilesByInstanceId = {};

// Map from coord to instanceId for selection/hit testing/swap lookup
final Map<Coord, int> instanceAtCoord = {};

// Reverse map: instanceId -> coord for O(1) lookup and cleanup
final Map<int, Coord> coordByInstanceId = {};
```

#### Why THREE different maps for tiles?

**Problem:** Tiles move around during animations. How do you track them?

**Solution:** Two-ID system
- **`instanceId`**: The tile's permanent ID (like a social security number - never changes)
- **`coord`**: The tile's current location (like an address - changes when tile moves)

**Map Purposes:**

1. **`tilesByInstanceId`** - "Find the visual tile object by its permanent ID"
   - Key: `instanceId` (int)
   - Value: `TileComponent` (the visual sprite)
   - Usage: `tilesByInstanceId[12345]` → gets the actual tile object

2. **`instanceAtCoord`** - "What tile is at row 3, col 5?"
   - Key: `Coord(row, col)` (position)
   - Value: `instanceId` (which tile is there)
   - Usage: When user taps screen → convert pixel to coord → lookup which tile

3. **`coordByInstanceId`** - "Where is tile #12345 located?"
   - Key: `instanceId` 
   - Value: `Coord` (its location)
   - Usage: Fast cleanup, debugging, validation

**Real Example:**
```dart
// Tile #12345 is at position (row: 2, col: 3)
tilesByInstanceId[12345]  // → TileComponent object (the visual sprite)
instanceAtCoord[Coord(2, 3)]  // → 12345 (which tile is there)
coordByInstanceId[12345]  // → Coord(2, 3) (where is it)

// When tile moves to (row: 3, col: 3):
// - instanceId stays 12345 (identity preserved)
// - Update maps:
instanceAtCoord[Coord(3, 3)] = 12345  // New location
coordByInstanceId[12345] = Coord(3, 3)
instanceAtCoord.remove(Coord(2, 3))  // Old location cleared
```

**Why efficient?** All lookups are O(1) - constant time (hash map magic!)

### **2. Static Component Registries**

```dart
// Beds are static, so keep them keyed by Coord
final Map<Coord, BedComponent> bedComponents = {};

// Blockers are also keyed by Coord (they don't move)
final Map<Coord, BlockerComponent> blockerComponents = {};
```

**Why only one map each?**
- Beds never move (they're the background)
- Blockers never move (they're obstacles)
- No need for instanceId tracking - just use coord

### **3. Preloaded Assets**

```dart
// Prebuilt lookup maps for performance
late final Map<int, BedType> bedTypeById;
late final Map<int, TileDef> tileDefById;

// Preloaded particle sprites
final Map<int, Sprite> crumbParticleByTileId = {};
Sprite? sparkleSprite;
```

**`late final`** keyword explained:
- **`late`**: "I'll initialize this later (not in constructor)"
- **`final`**: "Once set, it never changes"
- **Why?** Data comes from `stageData` which isn't available until constructor runs

**Usage example:**
```dart
// Instead of looping through array every time:
// ❌ Slow O(n)
TileDef? findTileType(int id) {
  for (var tile in stageData.tiles) {
    if (tile.id == id) return tile;
  }
}

// ✅ Fast O(1)
final tileDef = tileDefById[id];  // Instant lookup
```

### **4. Visual Effect Tracking Sets**

```dart
// Track dragonfly target coords that should skip early bursts
final Set<Coord> _dragonflyTargetCoords = {};

// Track coords that should use enhanced burst
final Set<Coord> _specialClearCoords = {};

// Coords for which VFX will spawn bursts manually
final Set<Coord> _suppressAutoBurstCoords = {};
```

**Why Sets not Maps?**
- Only tracking "yes/no" (is this coord special?)
- Don't need associated values
- Set operations are clean: `add()`, `contains()`, `remove()`

**Prefix `_` means private** - only this class can access these

---

## 🏗️ Constructor Deep Dive

### **Constructor Signature**

```dart
BoardGame({
  required this.rows,
  required this.cols,
  required this.gridModel,
  required this.stageData,
  required double viewportWidth,
  required double viewportHeight,
}) : super(...) { ... }
```

**`required`** keyword:
- You MUST provide these parameters
- Compiler enforces it (prevents bugs)

**Named parameters** (curly braces `{}`):
- Call like: `BoardGame(rows: 8, cols: 8, ...)`
- Order doesn't matter
- More readable than positional params

### **Initializer List** (`: super(...)`)

```dart
) : super(
      camera: CameraComponent.withFixedResolution(
        width: Platform.isWindows ? viewportWidth * 0.75 : viewportWidth,
        height: Platform.isWindows ? viewportHeight * 0.75 : viewportHeight,
      ),
    )
```

**What's happening:**
1. Before `BoardGame` constructor body runs
2. Call parent class (`FlameGame`) constructor
3. Set up camera with specific resolution

**Platform-specific optimization:**
```dart
Platform.isWindows ? viewportWidth * 0.75 : viewportWidth
```
- **Ternary operator:** `condition ? ifTrue : ifFalse`
- **On Windows:** Render at 75% resolution (performance boost)
- **On mobile:** Full resolution (already optimized)
- **Result:** Same visual quality, faster Windows performance

### **Grid Layout Calculation**

```dart
// Compute grid layout from viewport size
tileSize = (viewportWidth / cols < viewportHeight / rows)
    ? viewportWidth / cols
    : viewportHeight / rows;
```

**Algorithm:** Fit grid into available space without stretching

**Step-by-step:**
1. Calculate tile size if we fit width: `viewportWidth / cols`
2. Calculate tile size if we fit height: `viewportHeight / rows`
3. Use the **smaller** one (ensures everything fits)

**Example:**
- Viewport: 800×1200 pixels
- Grid: 8 rows × 8 cols
- Width-based: 800 / 8 = 100px per tile
- Height-based: 1200 / 8 = 150px per tile
- **Choose:** 100px (smaller, fits both dimensions)

```dart
final gridWidth = tileSize * cols;   // 100 * 8 = 800
final gridHeight = tileSize * rows;  // 100 * 8 = 800

// Center the grid within the viewport
gridLeft = (viewportWidth - gridWidth) / 2;   // (800 - 800) / 2 = 0
gridTop = (viewportHeight - gridHeight) / 2;  // (1200 - 800) / 2 = 200
```

**Visual result:** 800×800 grid centered with 200px margin top/bottom

### **Lookup Map Construction**

```dart
bedTypeById = {
  for (final bedType in stageData.bedTypes) bedType.id: bedType,
};
```

**Collection `for` syntax** (modern Dart feature):
```dart
{
  for (item in collection) key: value,
}
```

**Equivalent to:**
```dart
final map = <int, BedType>{};
for (final bedType in stageData.bedTypes) {
  map[bedType.id] = bedType;
}
bedTypeById = map;
```

**Why the shorthand?** More concise, same result

### **Special Tile Definitions**

```dart
// Add special tile definitions (power-ups)
tileDefById[101] = TileDef(
  id: 101,
  file: 'assets/sprites/power-ups/party_popper_horizontal.png',
  weight: 0,  // Not used for spawning
);
// ... more special tiles (102, 103, 104, 105)
```

**Why add here, not in JSON?**
- Special tiles (power-ups) are hardcoded game mechanics
- Stage JSON defines normal tiles (food items)
- Separation of concerns: game rules vs level data

**IDs 101-105:** Reserved for special tiles
- 101: Party Popper (horizontal)
- 102: Party Popper (vertical)
- 103: Sticky Rice Bomb
- 104: Firecracker
- 105: Dragonfly

### **Controller Initialization**

```dart
controller = BoardController(
  gridModel: gridModel,
  stageData: stageData,
  sfxManager: SfxManager.instance,  // Dependency injection
);
```

**Dependency Injection Pattern:**
- Don't create `SfxManager` inside controller
- Pass it in from outside
- **Benefits:** Testable (can inject mock), flexible, clear dependencies

```dart
controller.initializeInstanceIds();
controller.stabilizeInitialBoard();
```

**Two-phase initialization:**
1. **Assign IDs:** Give every tile a unique `instanceId`
2. **Stabilize:** Reroll any existing matches (players expect clean start)

### **Callback Registration**

The constructor sets up **multiple callbacks** for coordination:

#### **1. Clear Callback** (handles ALL tile clears)

```dart
controller.setOnCellsClearedWithTypes((victims) async {
  // victims = Map<Coord, int> (coord → tileTypeId)
  
  // 1. Spawn particles for visual feedback
  if (victims.isNotEmpty) {
    // Filter out suppressed coords (VFX will handle them)
    final coordsToSpawnParticles = <Coord, int>{};
    for (final entry in victims.entries) {
      if (!_suppressAutoBurstCoords.contains(entry.key)) {
        coordsToSpawnParticles[entry.key] = entry.value;
      }
    }
    
    if (coordsToSpawnParticles.isNotEmpty) {
      spawnClearParticles(coordsToSpawnParticles);
    }
    
    // Cleanup suppression markers
    _suppressAutoBurstCoords.removeAll(victims.keys);
  }
  
  // 2. Update objectives (score, targets)
  _gameStateModel?.processClearedTiles(victims);
});
```

**Callback pattern explained:**
- Controller doesn't know about particles or UI
- When tiles clear, controller calls this function
- BoardGame handles visual/UI updates

**Why async?** Particles might trigger animations

#### **2. Blocker Break Callback**

```dart
controller.setOnBlockerBreak((coord) async {
  final blocker = blockerComponents[coord];
  if (blocker != null) {
    await BlockerBreakVfx.play(game: this, coord: coord, blocker: blocker);
  }
});
```

**When called:** Blocker is destroyed (obstacle cleared)  
**Action:** Play breaking animation

#### **3. Blocker Cleared Callback**

```dart
controller.setOnBlockerCleared((coord) {
  _gameStateModel?.decrementBlockersRemaining();
});
```

**Purpose:** Track win condition (some levels require clearing all blockers)

---

## 📐 Coordinate System

### **Two Coordinate Systems**

1. **Grid Coordinates** (logical): Row/col indices (0-based)
2. **World Coordinates** (visual): Pixel positions (x, y)

### **Grid → World Conversion**

```dart
Vector2 coordToWorld(Coord coord) {
  final x = gridLeft + coord.col * tileSize + tileSize / 2;
  final y = gridTop + coord.row * tileSize + tileSize / 2;
  return Vector2(x, y);
}
```

**Step-by-step:**
1. Start at grid's left edge: `gridLeft`
2. Move right by column: `+ coord.col * tileSize`
3. Center in tile: `+ tileSize / 2`
4. Same for Y-axis

**Example:**
- Grid at (100, 200) pixels
- Tile size: 80px
- Coord(2, 3) → Position?
  - x = 100 + 3 * 80 + 40 = 380px
  - y = 200 + 2 * 80 + 40 = 360px

**Visual:**
```
┌─────────────────┐
│  gridTop (200)  │
│┌───┬───┬───┬───┐│
││0,0│0,1│0,2│0,3││
│├───┼───┼───┼───┤│
││1,0│1,1│1,2│1,3││
│├───┼───┼───┼───┤│
││2,0│2,1│2,2│2,3││ ← Coord(2,3) is here
│└───┴───┴───┴───┘│
│  gridLeft (100)  │
└─────────────────┘
```

### **World → Grid Conversion**

```dart
Coord? worldToCoord(Vector2 worldPos) {
  final col = ((worldPos.x - gridLeft) / tileSize).floor();
  final row = ((worldPos.y - gridTop) / tileSize).floor();
  
  if (row >= 0 && row < rows && col >= 0 && col < cols) {
    final coord = Coord(row, col);
    if (isPlayableCell(coord)) {
      return coord;
    }
  }
  return null;  // Out of bounds or void cell
}
```

**Algorithm:**
1. Subtract grid offset
2. Divide by tile size
3. Floor to get integer indices
4. Validate bounds and playability

**Why `floor()`?** Rounds down (3.7 → 3, not 4)

**Example:**
- User taps at (380, 360) pixels
- col = (380 - 100) / 80 = 3.5 → floor → 3
- row = (360 - 200) / 80 = 2.0 → floor → 2
- Result: Coord(2, 3) ✓

**Why return `null`?**
- Tap outside grid
- Tap on void cell (hole in board)
- Graceful handling (no crash)

---

## 🖱️ Input Handling

### **Tap Detection Flow**

```dart
@override
void onTapDown(TapDownEvent event) {
  // 1. Race condition prevention
  if (_isBusy) {
    DebugLogger.boardGame('Ignoring tap - game is busy');
    return;
  }
  
  // 2. Convert pixel position to grid coordinate
  final worldPos = event.canvasPosition;
  final coord = worldToCoord(worldPos);
  
  // 3. Validate tap location
  if (coord == null) {
    _deselectTile();  // Tapped outside board
    return;
  }
  
  // 4. Check if tile exists
  final tile = tileAt(coord);
  if (tile == null) {
    _deselectTile();  // No tile here
    return;
  }
  
  // 5. Handle selection logic
  if (_selectedCoord == null) {
    // First tap - select tile
    _selectTile(coord, tile);
  } else if (_selectedCoord == coord) {
    // Same tile - deselect
    _deselectTile();
  } else if (!_selectedCoord!.isAdjacent(coord)) {
    // Not adjacent - select new tile
    _selectTile(coord, tile);
  } else {
    // Adjacent - attempt swap!
    _processSwap(_selectedCoord!, coord);
    _deselectTile();
  }
}
```

### **State Machine for Selection**

The code implements a **finite state machine** with 2 states:

**State 1: No Selection**
- `_selectedCoord == null`
- Action: First tap selects tile

**State 2: Tile Selected**
- `_selectedCoord != null`
- Actions depend on next tap:
  - Same tile → Deselect
  - Adjacent tile → Swap
  - Non-adjacent → Select new tile

**Visual State Diagram:**
```
     ┌─────────────┐
     │ No Selection│
     └──────┬──────┘
            │ tap tile
            ▼
     ┌─────────────┐      tap same tile
     │   Selected  │◄────────────┐
     └──────┬──────┘             │
            │                     │
            │ tap adjacent        │
            ▼                     │
     ┌─────────────┐             │
     │    Swap     ├─────────────┘
     └──────┬──────┘    deselect
            │
            ▼
     ┌─────────────┐
     │  Animating  │
     └─────────────┘
```

### **Tile Selection Implementation**

```dart
void _selectTile(Coord coord, TileComponent tile) {
  _deselectTile();  // Clear previous selection first
  _selectedCoord = coord;
  _selectedTileComponent = tile;
  tile.isSelected = true;  // Visual highlight
}

void _deselectTile() {
  if (_selectedTileComponent != null) {
    _selectedTileComponent!.isSelected = false;
    _selectedTileComponent = null;
  }
  _selectedCoord = null;
}
```

**Null-safety pattern:**
```dart
if (_selectedTileComponent != null) {
  _selectedTileComponent!.isSelected = false;
  //                      ↑ 
  //  Force unwrap (!) - we just checked it's not null
}
```

**Why deselect-then-select?** Ensures only one tile highlighted at a time

### **Swap Processing**

```dart
Future<void> _processSwap(Coord a, Coord b) async {
  // 1. Lock to prevent race conditions
  if (_isBusy) return;
  _isBusy = true;
  
  try {
    // 2. Attempt swap through controller
    final success = await controller.attemptSwap(
      a, b,
      chosenCoord: a,  // Which tile user selected first
      onSync: () async {
        await syncFromModel();  // Update visuals
        await validateBoardSync();  // Verify consistency
      },
      onNoMovesDetected: onNoMovesDetected,  // Show "no moves" modal
      onSpecialActivated: (specials, metadata) async {
        // Play visual effects
        await SpecialVfxDispatcher.playSpecialVfx(...);
      },
    );
    
    // 3. Update game state if successful
    if (success) {
      _gameStateModel?.decrementMoves();
    }
  } finally {
    // 4. Always unlock (even if error occurs)
    _isBusy = false;
  }
}
```

**try-finally pattern:**
- `try` block runs
- `finally` block **always** runs (even if exception)
- Guarantees unlock (prevents deadlock)

**Callbacks explained:**

1. **`onSync`**: Called after each stage (match clear, gravity, refill)
   - Updates visual components to match model
   - Allows animations to play

2. **`onNoMovesDetected`**: Board has no valid swaps left
   - Show modal to player
   - Offer shuffle or retry

3. **`onSpecialActivated`**: Special tile triggered
   - Coordinate visual effects
   - instanceId-based (stable during animations)

---

## 🔄 Synchronization System

### **The Core Problem**

**Model** (GridModel) and **View** (TileComponents) can get out of sync:
- Tiles move during animations
- Controller mutates model instantly
- Visual update must happen separately

**Solution:** `syncFromModel()` - rebuild view from model

### **Synchronization Algorithm**

```dart
Future<void> syncFromModel() async {
  final activeInstanceIds = <int>{};
  final asyncOperations = <Future<void>>[];
  
  // Build fresh coordinate maps
  final nextInstanceAtCoord = <Coord, int>{};
  final nextCoordByInstanceId = <int, Coord>{};
  
  // 1. Scan all playable cells in the model
  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      final coord = Coord(row, col);
      
      if (!isPlayableCell(coord)) continue;
      
      final cell = gridModel.cells[row][col];
      
      if (cell.tileInstanceId != null && cell.tileTypeId != null) {
        final instanceId = cell.tileInstanceId!;
        final tileTypeId = cell.tileTypeId!;
        activeInstanceIds.add(instanceId);
        
        // Record new mappings
        nextInstanceAtCoord[coord] = instanceId;
        nextCoordByInstanceId[instanceId] = coord;
        
        final component = tilesByInstanceId[instanceId];
        
        // Create component if missing
        if (component == null) {
          await spawnOrUpdateTileAt(coord, tileTypeId, 
            instanceId: instanceId);
          continue;
        }
        
        // Update existing component
        if (component.coord != coord) {
          // Tile moved - animate to new position
          asyncOperations.add(component.moveToCoord(coord));
        } else if (!component.isMoving) {
          // Ensure position is correct
          component.position = coordToWorld(coord);
        }
        
        if (component.tileTypeId != tileTypeId) {
          // Sprite changed
          asyncOperations.add(component.setType(tileTypeId));
        }
      }
    }
  }
  
  // 2. Await all animations in parallel
  if (asyncOperations.isNotEmpty) {
    await Future.wait(asyncOperations);
  }
  
  // 3. Replace maps atomically (prevents race conditions)
  instanceAtCoord
    ..clear()
    ..addAll(nextInstanceAtCoord);
  
  coordByInstanceId
    ..clear()
    ..addAll(nextCoordByInstanceId);
  
  // 4. Remove tiles that no longer exist
  final toRemove = <int>[];
  for (final id in tilesByInstanceId.keys) {
    if (!activeInstanceIds.contains(id)) {
      toRemove.add(id);
    }
  }
  for (final id in toRemove) {
    tilesByInstanceId[id]?.removeFromParent();
    tilesByInstanceId.remove(id);
  }
  
  // 5. Reset visual states
  for (final component in tilesByInstanceIds.values) {
    component.opacity = 1.0;  // Ensure visible
  }
  
  // 6. Sync blockers
  await _syncBlockersFromModel();
}
```

### **Key Techniques**

#### **1. Parallel Animations**

```dart
final asyncOperations = <Future<void>>[];

// Collect all animation futures
asyncOperations.add(component.moveToCoord(coord));
asyncOperations.add(component.setType(tileTypeId));

// Wait for ALL to complete
await Future.wait(asyncOperations);
```

**Without parallel:**
```dart
await component1.moveToCoord(coord1);  // 300ms
await component2.moveToCoord(coord2);  // 300ms
await component3.moveToCoord(coord3);  // 300ms
// Total: 900ms (sequential)
```

**With parallel:**
```dart
await Future.wait([
  component1.moveToCoord(coord1),  // All start at once
  component2.moveToCoord(coord2),
  component3.moveToCoord(coord3),
]);
// Total: 300ms (parallel) ✓
```

#### **2. Cascade Operator** (`..`)

```dart
instanceAtCoord
  ..clear()
  ..addAll(nextInstanceAtCoord);
```

**Equivalent to:**
```dart
instanceAtCoord.clear();
instanceAtCoord.addAll(nextInstanceAtCoord);
```

**Why use it?** More concise, same object

#### **3. Atomic Map Replacement**

**❌ Bug-prone approach:**
```dart
instanceAtCoord.clear();
// ← If error happens here, map is empty!
instanceAtCoord.addAll(nextInstanceAtCoord);
```

**✅ Safe approach:**
```dart
// Build new map completely
final nextInstanceAtCoord = <Coord, int>{};
// ... populate it ...

// Replace atomically (all or nothing)
instanceAtCoord
  ..clear()
  ..addAll(nextInstanceAtCoord);
```

**Why?** If error occurs during population, old map is untouched

### **Validation System**

```dart
Future<int> validateBoardSync() async {
  int fixCount = 0;
  
  // Check 1: Every grid cell with instanceId must have a component
  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      final coord = Coord(row, col);
      if (!isPlayableCell(coord)) continue;
      
      final cell = gridModel.cells[row][col];
      if (cell.tileInstanceId != null && cell.tileTypeId != null) {
        final component = tilesByInstanceId[cell.tileInstanceId];
        if (component == null) {
          // FIX: Spawn missing component
          await spawnOrUpdateTileAt(coord, cell.tileTypeId!,
            instanceId: cell.tileInstanceId, updateMaps: true);
          fixCount++;
        } else {
          // Check 2: Component coord must match model
          if (component.coord != coord) {
            // FIX: Correct position
            component.coord = coord;
            component.position = coordToWorld(coord);
            instanceAtCoord[coord] = cell.tileInstanceId!;
            coordByInstanceId[cell.tileInstanceId!] = coord;
            fixCount++;
          }
          
          // Check 3: Component type must match model
          if (component.tileTypeId != cell.tileTypeId) {
            // FIX: Update sprite
            component.setType(cell.tileTypeId!);
            fixCount++;
          }
        }
      }
    }
  }
  
  // Check 4: Remove orphaned components
  final orphanedComponents = <int>[];
  for (final entry in tilesByInstanceId.entries) {
    final instanceId = entry.key;
    final expectedCoord = coordByInstanceId[instanceId];
    
    if (expectedCoord == null) {
      orphanedComponents.add(instanceId);
      continue;
    }
    
    final cell = gridModel.cells[expectedCoord.row][expectedCoord.col];
    if (cell.tileInstanceId != instanceId) {
      orphanedComponents.add(instanceId);
    }
  }
  
  // Remove orphans
  for (final instanceId in orphanedComponents) {
    tilesByInstanceId[instanceId]?.removeFromParent();
    tilesByInstanceId.remove(instanceId);
    coordByInstanceId.remove(instanceId);
    instanceAtCoord.removeWhere((coord, id) => id == instanceId);
    fixCount++;
  }
  
  return fixCount;
}
```

**Validation checks:**
1. Missing components → spawn them
2. Wrong position → correct it
3. Wrong sprite → update it
4. Orphaned components → remove them

**When called:**
- After initial load
- After each sync
- After complex operations (swaps, cascades)

**Purpose:** Defensive programming - catch desyncs early

---

## ✨ Visual Effects Integration

### **Particle System**

```dart
void spawnClearParticles(Map<Coord, int> clearedCellsWithTypes) {
  final isBigClear = clearedCellsWithTypes.length > 8;
  
  for (final entry in clearedCellsWithTypes.entries) {
    final coord = entry.key;
    final tileTypeId = entry.value;
    
    // Skip dragonfly targets (VFX handles them)
    if (_dragonflyTargetCoords.contains(coord) &&
        !_specialClearCoords.contains(coord)) {
      continue;
    }
    
    // Only spawn for regular tiles (not specials)
    if (tileTypeId < 101) {
      final worldPos = coordToWorld(coord);
      final crumbSprite = crumbParticleByTileId[tileTypeId];
      
      spawnMatchBurst(
        game: this,
        center: worldPos,
        tileSize: tileSize,
        crumbSprite: crumbSprite,
        sparkleSprite: isBigClear ? null : sparkleSprite,
        isSpecialClear: true,
      );
    }
  }
}
```

**Optimization:** Big clears (>8 tiles) skip sparkles to reduce particle count

**Tile type filtering:**
- Regular tiles (1-100): Food sprites, spawn crumbs
- Special tiles (101-105): Power-ups, have custom VFX

### **VFX Suppression System**

```dart
// Mark coords to skip auto-bursts
void suppressAutoBurstForCoords(Iterable<Coord> coords) {
  _suppressAutoBurstCoords.addAll(coords);
}
```

**Why needed?**
- Some VFX spawn particles at specific timing
- Auto-burst would create duplicates
- Suppression prevents double-particles

**Example:** Party Popper shoots projectiles that spawn bursts on impact
- Suppress auto-burst for target coords
- VFX spawns burst when projectile arrives
- Cleanup suppression after clear

### **Special Activation Flow**

```dart
onSpecialActivated: (activatedSpecials, vfxMetadata) async {
  // Convert coord-based to instanceId-based
  final instanceIdSpecials = <int, int>{};
  final instanceIdMetadata = <int, SpecialVfxMetadata>{};
  
  for (final entry in activatedSpecials.entries) {
    final coord = entry.key;
    final typeId = entry.value;
    
    // Read instanceId from GridModel (source of truth)
    final cell = gridModel.cells[coord.row][coord.col];
    final instanceId = cell.tileInstanceId;
    
    if (instanceId == null) {
      DebugLogger.error('No instanceId at $coord! Skipping VFX.');
      continue;
    }
    
    instanceIdSpecials[instanceId] = typeId;
    
    // Convert metadata
    final metaEntry = vfxMetadata[coord];
    if (metaEntry != null) {
      instanceIdMetadata[instanceId] = SpecialVfxMetadata(
        targetCoord: metaEntry.targetCoord,
        activationCells: metaEntry.activationCells,
      );
    }
  }
  
  // Dispatch VFX immediately (don't queue)
  if (instanceIdSpecials.isNotEmpty) {
    await SpecialVfxDispatcher.playSpecialVfx(
      game: this,
      activatedSpecials: instanceIdSpecials,
      metadata: instanceIdMetadata,
    );
  }
}
```

**Why instanceId-based?**
- During animations, coords change
- instanceId is stable reference
- VFX can track moving tiles

**Metadata types:**
- **DragonFly (105)**: `targetCoord` - which tile to target
- **Sticky Rice (103)**: `activationCells` - which tiles to clear

---

## 🎬 Lifecycle Methods

### **onLoad() - Initialization**

```dart
@override
Future<void> onLoad() async {
  await super.onLoad();
  
  // 1. Initialize audio
  await SfxManager.instance.init();
  await BgmManager.instance.playGameplayBgm();
  
  // 2. Set asset prefix
  images.prefix = 'assets/';
  
  // 3. Preload particles
  await _loadParticleSprites();
  
  // 4. Build board: beds then tiles
  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      final coord = Coord(row, col);
      
      if (!isPlayableCell(coord)) continue;
      
      final cell = gridModel.cells[row][col];
      
      // Add bed (background layer)
      if (cell.bedId != null && cell.bedId! >= 0) {
        final bedType = bedTypeById[cell.bedId];
        final bedComponent = BedComponent(...);
        add(bedComponent);
        bedComponents[coord] = bedComponent;
      }
      
      // Add tile (foreground layer)
      if (cell.tileTypeId != null && cell.tileInstanceId != null) {
        await spawnOrUpdateTileAt(coord, cell.tileTypeId!,
          instanceId: cell.tileInstanceId, updateMaps: true);
      }
    }
  }
  
  // 5. Validate and sync
  await validateBoardSync();
  await _syncBlockersFromModel();
  
  // 6. Enable input
  _isBusy = false;
}
```

**Load order matters:**
1. Audio first (can play during loading)
2. Sprites next (needed for rendering)
3. Beds before tiles (layer order)
4. Validation last (ensure correctness)

**Why `await`?** Each step must complete before next starts

### **Background Color**

```dart
@override
Color backgroundColor() => const Color(0x00000000);
```

**`0x00000000`** breakdown:
- `0x`: Hex notation
- `00`: Alpha (fully transparent)
- `00`: Red
- `00`: Green
- `00`: Blue

**Purpose:** See through to Flutter UI background (wooden board frame)

---

## 🎓 Advanced Patterns

### **1. Singleton Pattern**

```dart
SfxManager.instance
BgmManager.instance
```

**What it is:** Only one instance exists globally

**Implementation:**
```dart
class SfxManager {
  static final instance = SfxManager._();  // Single instance
  SfxManager._();  // Private constructor (can't create new ones)
}
```

**Usage:** `SfxManager.instance.play(SfxType.bloop)`

### **2. Dependency Injection**

```dart
controller = BoardController(
  gridModel: gridModel,
  stageData: stageData,
  sfxManager: SfxManager.instance,  // Injected dependency
);
```

**Benefits:**
- Testable (inject mock SfxManager)
- Flexible (can swap implementations)
- Clear (dependencies visible in constructor)

### **3. Callback Pattern**

```dart
controller.setOnCellsClearedWithTypes((victims) async {
  spawnClearParticles(victims);
  _gameStateModel?.processClearedTiles(victims);
});
```

**Alternative to inheritance:**
- Controller doesn't know about BoardGame
- BoardGame provides callbacks
- **Loose coupling** (easier to maintain)

### **4. Late Initialization**

```dart
late final BoardController controller;
late final double tileSize;
late final Map<int, BedType> bedTypeById;
```

**`late`**: "I'll set this before using it"  
**`final`**: "Once set, never changes"

**Why?** Values computed in constructor, not at declaration

### **5. Null Safety**

```dart
Coord? _selectedCoord;  // Can be null
TileComponent? tile = tileAt(coord);  // Can be null

if (tile != null) {
  tile.isSelected = true;  // Safe: checked null
}

tile?.isSelected = true;  // Null-aware: only if not null
```

**`?` operator:** Safe navigation (no crash if null)

### **6. Async/Await**

```dart
Future<void> _processSwap(Coord a, Coord b) async {
  await controller.attemptSwap(a, b, ...);
  // ... continues after swap completes
}
```

**`Future<void>`**: Returns nothing, completes later  
**`async`**: Can use `await` inside  
**`await`**: Pause until operation completes

### **7. Extension Methods** (used on Coord)

```dart
extension CoordExtensions on Coord {
  bool isAdjacent(Coord other) {
    // Add method to existing class
  }
}
```

**Usage:** `coord1.isAdjacent(coord2)`

---

## 🔍 Key Takeaways

### **Architecture Principles**

1. **Separation of Concerns**
   - Model: GridModel (data)
   - View: BoardGame (rendering)
   - Controller: BoardController (rules)

2. **Performance Optimization**
   - Multiple Maps for O(1) lookups
   - Parallel async operations
   - Platform-specific rendering (Windows 75%)
   - Particle throttling for big clears

3. **State Management**
   - instanceId for stable identity
   - Coordinate maps rebuilt fresh
   - Validation after mutations
   - Busy flag prevents race conditions

4. **Visual Coordination**
   - Callbacks for loose coupling
   - Suppression sets prevent duplicates
   - instanceId-based VFX (stable references)
   - Sync after each mutation

### **Programming Techniques**

- **Maps for fast lookup** (O(1) vs O(n))
- **Sets for membership tests** (contains, add, remove)
- **Async/await for animations** (sequential timing)
- **Future.wait for parallelism** (simultaneous operations)
- **Null safety** (prevents crashes)
- **Dependency injection** (testable, flexible)
- **Defensive programming** (validation, try-finally)

### **Common Patterns**

- Singleton (global instances)
- Callback (event handling)
- State Machine (selection logic)
- Factory (lookup table construction)
- Atomic operations (map replacement)

---

## 🎯 Practical Application

### **To Add a New Feature:**

**1. New tile type:**
- Add to `tileDefById` in constructor
- Update particle sprites in `_loadParticleSprites()`
- Add VFX in `spawnClearParticles()` if custom

**2. New input gesture:**
- Add mixin: `with DragCallbacks`
- Override `onDragStart()`, `onDragUpdate()`, `onDragEnd()`
- Update selection state machine

**3. New visual effect:**
- Create effect class (extends Component)
- Trigger in appropriate callback
- Clean up in `removeFromParent()`

**4. Performance profiling:**
- Check sync frequency (too often?)
- Monitor particle count
- Profile map operations

---

## 📚 Further Reading

**Flame Engine:**
- [Flame Documentation](https://docs.flame-engine.org/)
- Components, Effects, Collisions

**Dart/Flutter:**
- Async programming
- Collection operators
- Null safety

**Game Programming:**
- Component Entity Systems
- State machines
- Performance optimization

---

## 💡 Questions to Explore

1. How would you add undo functionality?
2. What if tiles had different sizes?
3. How to implement replay system?
4. How to add networked multiplayer?
5. How to profile and optimize further?

---

**You now understand the visual rendering engine of a match-3 game!** This pattern scales to many game types - the core concepts apply broadly. Keep exploring! 🚀
