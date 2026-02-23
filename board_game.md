# PhoLogic Board Game - Technical Deep Dive

## 🎮 Project Overview

**PhoLogic** is a match-3 puzzle game built with **Flutter** and **Flame** (a 2D game engine). Think of games like Candy Crush or Bejeweled - you swap tiles to make matches of 3 or more, which clears them and creates cascading combos. The Vietnamese food theme gives it unique visual character.

---

## 📁 Project Architecture

### **High-Level Structure**

```
lib/
├── main.dart                    # App entry point
├── ads/                         # Ad integration (Google AdMob)
└── src/
    ├── app/                     # App-level setup (MaterialApp, routes)
    ├── audio/                   # Sound effects & background music
    ├── game/                    # Core game logic (match-3 engine)
    │   ├── board/              # Visual rendering (Flame components)
    │   ├── model/              # Data structures (Grid, Cells, Coords)
    │   ├── stages/             # Level definitions & loading
    │   ├── inventory/          # Player's boosters/power-ups
    │   ├── vfx/                # Visual effects (particles, animations)
    │   └── utils/              # Helpers (logging, random picking)
    ├── screens/                # UI screens (menu, level select, gameplay)
    ├── widgets/                # Reusable UI components
    └── utils/                  # General utilities
```

---

## 🧠 Core Concepts Explained

### **1. Separation of Concerns (MVC Pattern)**

The code follows a **Model-View-Controller** pattern:

- **Model** (`GridModel`, `Cell`, `GameStateModel`): Stores the game data
- **View** (`BoardGame`, `TileComponent`, `BedComponent`): Renders the visuals
- **Controller** (`BoardController`): Handles game rules and logic

**Why this matters:** Separating these concerns makes the code modular. You can change how things look (View) without changing the game rules (Controller), or change the rules without breaking the visuals.

---

### **2. The Game Loop (main.dart)**

```dart
void main() async {
  // 1. Initialize Flutter bindings (CRITICAL - must be first!)
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Lock to portrait orientation only
  await SystemChrome.setPreferredOrientations([...]);
  
  // 3. Initialize ads, audio
  await MobileAds.instance.initialize();
  await SfxManager.instance.init();
  await BgmManager.instance.init();
  
  // 4. Launch the app
  runApp(const PhoLogicApp());
}
```

**Key Concepts:**
- **async/await**: Waits for tasks to complete (like loading audio files)
- **try/catch blocks**: Prevents crashes if something fails (defensive programming)
- **Singleton pattern** (`SfxManager.instance`): Only one instance exists globally

---

## 🎯 Core Game Components

### **GridModel - The Game Board Data**

Located in: `src/game/model/grid_model.dart`

```dart
class Cell {
  int? tileTypeId;      // What sprite to show (1 = banh mi, 2 = pho, etc.)
  int? tileInstanceId;  // Unique ID for THIS specific tile (persists during motion)
  int? bedId;           // What type of "bed" (background) this cell has
  bool exists;          // Can tiles exist here? (false = void/hole)
  BlockerType blocker;  // Is there a blocker (obstacle) on this cell?
  String? blockerFilePath;
}

class GridModel {
  final int rows;
  final int cols;
  final List<List<Cell>> cells;  // 2D grid of cells
}
```

**Why two IDs?**
- `tileTypeId`: The "species" (what it looks like)
- `tileInstanceId`: The "individual" (tracks THIS tile as it moves)

Think of it like people: everyone might have the same hair color (typeId), but each person is unique (instanceId).

**Technical Insight:**
- Uses **2D lists** (`List<List<Cell>>`) to represent the grid
- Rows go down (Y-axis), columns go right (X-axis)
- Access a cell: `cells[row][col]`

---

### **Coord - Position System**

Located in: `src/game/model/coord.dart`

```dart
class Coord {
  final int row;
  final int col;
  
  // Useful methods:
  bool isAdjacent(Coord other)  // Are they next to each other?
  List<Coord> adjacents()       // Get all 4 neighbors (up/down/left/right)
}
```

**Why a class for coordinates?**
- **Type safety**: Can't accidentally swap row/col
- **Methods**: Built-in adjacency checking, distance calculations
- **Equality**: Two Coords with same row/col are considered equal

---

### **BoardController - The Game Brain**

Located in: `src/game/board/board_controller.dart` (2255 lines!)

This is where the **magic** happens. It handles:

1. **Swap Validation**
   ```dart
   bool canSwap(Coord a, Coord b) {
     // Check if adjacent, not blocked, would create a match
   }
   ```

2. **Match Detection**
   ```dart
   MatchResult detectMatches() {
     // Scan grid for 3+ in a row/column
     // Returns all matched cells
   }
   ```

3. **Gravity & Refill**
   ```dart
   Future<void> applyGravity() {
     // Tiles fall down into empty spaces
   }
   
   Future<void> refillEmptyCells() {
     // Spawn new random tiles at the top
   }
   ```

4. **Cascade Loop** (the satisfying chain reactions!)
   ```dart
   Future<void> runCascade() {
     // 1. Apply gravity
     // 2. Refill
     // 3. Check for new matches
     // 4. If matches found, clear them and repeat!
   }
   ```

**Technical Patterns:**

- **State Machine**: Tracks if the board is "busy" to prevent race conditions
- **Async/Await**: Uses `Future<void>` for animations to complete before next step
- **Weighted Random Picker**: Spawns tiles based on probability weights

```dart
// Example: 60% chance of banh mi, 30% pho, 10% spring roll
TileDef(id: 1, weight: 60)  // Banh mi
TileDef(id: 2, weight: 30)  // Pho
TileDef(id: 3, weight: 10)  // Spring roll
```

---

### **BoardGame - The Visual Renderer**

Located in: `src/game/board/board_game.dart`

Uses **Flame engine** to render the game:

```dart
class BoardGame extends FlameGame with TapCallbacks {
  // Component registries (lookup tables)
  final Map<int, TileComponent> tilesByInstanceId = {};
  final Map<Coord, int> instanceAtCoord = {};
  final Map<Coord, BedComponent> bedComponents = {};
  final Map<Coord, BlockerComponent> blockerComponents = {};
  
  // Game controller
  late final BoardController controller;
}
```

**Key Responsibilities:**
1. **Rendering**: Draws tiles, beds, blockers at correct positions
2. **Input Handling**: Detects taps and drags
3. **Animation**: Smoothly moves tiles when they fall or swap
4. **VFX Coordination**: Triggers particle effects and special animations

**Flame Concepts:**
- **Components**: Like widgets in Flutter, but for games
- **Sprites**: 2D images (tile graphics)
- **Vector2**: Represents (x, y) positions in world space
- **CameraComponent**: Handles viewport and resolution scaling

---

### **TileComponent - Individual Tile Rendering**

Located in: `src/game/board/tile_component.dart`

```dart
class TileComponent extends SpriteComponent {
  final int instanceId;    // Unique ID
  int tileTypeId;         // Current sprite type
  Coord coord;            // Current grid position
  
  bool isSelected = false;  // For highlight effect
  
  // Visual effects
  double _breathPhase = 0.0;  // Pulsing animation phase
  Paint _highlightPaint;      // Selection glow
}
```

**Technical Highlights:**

1. **Breathing Animation** (selection highlight)
   ```dart
   // Uses sine wave for smooth pulsing
   _cachedAlpha = _breathMinAlpha + 
     (_breathMaxAlpha - _breathMinAlpha) * 
     ((math.sin(_breathPhase) + 1) / 2);
   ```

2. **Smooth Movement** (with Flame effects)
   ```dart
   add(MoveEffect.to(
     targetPosition,
     EffectController(duration: 0.3),
   ));
   ```

3. **Sprite Scaling**
   ```dart
   static const double _spriteScale = 1.08;  // 8% larger for visual appeal
   ```

---

## 🎲 Advanced Features

### **Special Tiles (Power-Ups)**

Located in: `src/game/board/special_tile_spawner.dart`

The game rewards special patterns:

| Pattern | Special Tile | Effect |
|---------|-------------|--------|
| 4 in a line | **Party Popper** (101/102) | Clears entire row/column |
| 5 in a line | **Sticky Rice** (103) | Clears 3x3 area around target |
| T or L shape | **Firecracker** (104) | Clears + pattern |
| 2×2 square | **Dragonfly** (105) | Targets and clears specific tile |

**Technical Implementation:**

1. **Pattern Recognition** (geometry logic)
   ```dart
   bool _isHorizontalMatch(Match match) {
     final firstRow = match.cells.first.row;
     return match.cells.every((coord) => coord.row == firstRow);
   }
   ```

2. **Priority System** (to handle overlapping patterns)
   ```dart
   // Higher priority = processed first
   _SpecialTileCandidate(
     cells: matchCells,
     priority: 5,  // Straight 5 = highest priority
     specialTypeId: 103,
   );
   ```

3. **Greedy Selection Algorithm**
   ```dart
   // Process highest priority first
   // Mark cells as "used" to avoid double-counting
   Set<Coord> processedCells = {};
   for (candidate in sortedByPriority) {
     if (!candidate.cells.any((c) => processedCells.contains(c))) {
       // Award this special tile
       processedCells.addAll(candidate.cells);
     }
   }
   ```

**Why this approach?**
- Prevents overlapping patterns from creating multiple specials
- Rewards most impressive matches first
- Deterministic behavior (no randomness in special spawning)

---

### **Visual Effects System**

Located in: `src/game/vfx/`

**Dispatcher Pattern:**
```dart
class SpecialVfxDispatcher {
  static Future<void> playSpecialVfx({
    required BoardGame game,
    required Map<int, int> activatedSpecials,
    Map<int, SpecialVfxMetadata>? metadata,
  }) async {
    // Determine which VFX to play based on special type
    switch (specialTypeId) {
      case 101:
      case 102:
        await playPartyPopperVfx(...);
      case 103:
        await playStickyRiceVfx(...);
      // etc.
    }
  }
}
```

**Why separate VFX from logic?**
- **Separation of concerns**: Game rules don't care about sparkles
- **Easy to modify**: Change visuals without touching game code
- **Performance**: Can disable VFX on low-end devices
- **Reusability**: VFX can be triggered from multiple sources

---

### **Stage System (Level Management)**

Located in: `src/game/stages/`

Levels are defined in **JSON files** (e.g., `stage_001.json`):

```json
{
  "stageId": 1,
  "rows": 8,
  "cols": 8,
  "moves": 20,
  "objectives": [
    {
      "type": "collect",
      "tileId": 1,
      "target": 30
    }
  ],
  "tiles": [
    { "id": 1, "file": "banh_mi.png", "weight": 50 },
    { "id": 2, "file": "pho.png", "weight": 30 }
  ],
  "tileMap": [ [1, 2, 0, ...], ... ],
  "bedMap": [ [0, 0, -1, ...], ... ]
}
```

**What each means:**
- `tileMap[r][c] = 0`: Random spawn (weighted by tiles list)
- `tileMap[r][c] = 1+`: Specific tile type
- `bedMap[r][c] = -1`: Void (hole in the board)
- `bedMap[r][c] = 0+`: Bed type (background)

**Loading Process:**

```dart
// 1. Load JSON from assets
StageData stage = await StageLoader.loadFromAsset('assets/stages/stage_001.json');

// 2. Convert to GridModel
GridModel gridModel = GridModel.fromBoardState(
  BoardState(...),
  stageData: stage,
);

// 3. Stabilize board (remove initial matches)
controller.stabilizeInitialBoard();
```

**Stabilization Algorithm:**
```dart
void stabilizeInitialBoard() {
  int rerollCount = 0;
  while (rerollCount < 50) {
    var matches = detectMatches();
    if (!matches.hasMatches && hasPossibleMove()) {
      break;  // Board is valid!
    }
    // Reroll matched cells
    for (coord in matches.allMatchedCells) {
      cells[coord.row][coord.col].tileTypeId = randomTileType();
    }
    rerollCount++;
  }
}
```

**Why stabilize?**
- Players expect a "clean" starting board
- Ensures at least one valid move exists
- Prevents instant cascades at game start

---

### **Game State Management**

Located in: `src/game/game_state_model.dart`

Uses **ChangeNotifier** pattern (Flutter's built-in state management):

```dart
class GameStateModel extends ChangeNotifier {
  int _movesRemaining;
  Map<int, int> _objectiveProgress = {};  // objectiveIndex -> count
  int _blockersRemaining;
  
  // When data changes, notify listeners (UI updates automatically)
  void decrementMoves() {
    _movesRemaining--;
    notifyListeners();  // 🔔 UI updates!
  }
  
  void processClearedTiles(Map<Coord, int> clearedCells) {
    // Count how many of each tile type were cleared
    // Update objective progress
    // Check win/loss conditions
    notifyListeners();
  }
}
```

**How it works:**
1. UI widgets **listen** to GameStateModel
2. When model changes, it calls `notifyListeners()`
3. Widgets **automatically rebuild** with new data

This is **reactive programming** - the UI reacts to data changes.

---

## 🔊 Audio System

Located in: `src/audio/`

### **Sound Effects (SfxManager)**

Uses **AudioPool** for fast playback:

```dart
class SfxManager {
  static final instance = SfxManager._();  // Singleton
  
  final Map<SfxType, AudioPool> _pools = {};
  
  // Preload sounds into memory
  Future<void> init() async {
    for (var sfxType in SfxType.values) {
      _pools[sfxType] = await AudioPool.create(
        'audio/sfx/${sfxType.filename}',
        maxPlayers: 4,  // Can play up to 4 instances simultaneously
      );
    }
  }
  
  // Play sound instantly (no loading delay)
  void play(SfxType type) {
    _pools[type]?.start();
  }
}
```

**Why AudioPool?**
- **Low latency**: Sounds are preloaded in RAM
- **Overlapping sounds**: Multiple "bloop" sounds can play at once
- **Mobile-friendly**: Optimized for Android/iOS

### **Background Music (BgmManager)**

Uses **AudioPlayer** for looping music:

```dart
class BgmManager {
  late final AudioPlayer _player;
  
  Future<void> playLoop(String assetPath) async {
    await _player.setSource(AssetSource(assetPath));
    await _player.setReleaseMode(ReleaseMode.loop);  // Loop forever
    await _player.resume();
  }
}
```

---

## 🎨 Technical Patterns & Best Practices

### **1. Dependency Injection**

Instead of creating instances everywhere:
```dart
// ❌ Bad
class BoardController {
  final sfx = SfxManager.instance;  // Tightly coupled
}

// ✅ Good
class BoardController {
  final SfxManager sfxManager;  // Injected
  
  BoardController({required this.sfxManager});
}
```

**Benefits:**
- Easier testing (can inject mock objects)
- More flexible (can swap implementations)
- Clearer dependencies (you see what's needed)

### **2. Immutability Where Possible**

```dart
class Coord {
  final int row;  // Can't be changed after creation
  final int col;
  
  const Coord(this.row, this.col);  // Compile-time constant
}
```

**Why?**
- Prevents bugs (can't accidentally modify)
- Performance (compiler optimizations)
- Thread-safe (safe to share between isolates)

### **3. Null Safety**

Dart's modern null safety system:

```dart
int? tileTypeId;  // Can be null
int bedId;        // Can NEVER be null

// Null-aware operators
final value = tileTypeId ?? -1;  // Use -1 if null
final length = list?.length;     // null if list is null
```

### **4. Async Programming**

```dart
Future<void> playAnimation() async {
  await controller.clearMatches();   // Wait for clearing
  await controller.applyGravity();   // Then apply gravity
  await controller.refillBoard();    // Then refill
  // All sequential, in order
}
```

**Why async?**
- Animations take time (can't block the UI)
- Prevents jank (smooth 60 FPS)
- Allows proper sequencing of visual effects

### **5. Error Handling**

```dart
try {
  await MobileAds.instance.initialize();
} catch (e, st) {
  debugPrint('⚠️ AdMob error: $e\n$st');
  // Continue anyway - ads aren't critical
}
```

**Defensive programming:**
- Assume things can fail
- Log errors for debugging
- Graceful degradation (continue without ads)

---

## 📊 Data Flow Diagram

```
User Taps Screen
       ↓
BoardGame.onTapDown()
       ↓
Detect which tile was tapped
       ↓
Select tile / Attempt swap
       ↓
BoardController.performSwap()
       ↓
┌─────────────────────────┐
│ 1. Validate swap        │
│ 2. Apply swap to model  │
│ 3. Detect matches       │
│ 4. Clear matched tiles  │
│ 5. Spawn special tiles  │
│ 6. Apply gravity        │
│ 7. Refill empty cells   │
│ 8. Check new matches    │
│ 9. Repeat 4-8 if needed │
└─────────────────────────┘
       ↓
BoardGame.syncFromModel()
       ↓
Update TileComponents positions
       ↓
Trigger visual effects
       ↓
GameStateModel.decrementMoves()
       ↓
UI rebuilds (moves counter, objectives)
       ↓
Check win/loss conditions
```

---

## 🧪 Key Algorithms Explained

### **Match Detection Algorithm**

```dart
MatchResult detectMatches() {
  List<Match> allMatches = [];
  
  // 1. Check horizontal matches
  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols - 2; col++) {
      List<Coord> run = [Coord(row, col)];
      int currentType = cells[row][col].tileTypeId;
      
      // Extend run while tiles match
      for (int c = col + 1; c < cols; c++) {
        if (cells[row][c].tileTypeId == currentType) {
          run.add(Coord(row, c));
        } else {
          break;
        }
      }
      
      // If 3+ tiles, it's a match!
      if (run.length >= 3) {
        allMatches.add(Match(cells: run, tileTypeId: currentType));
      }
    }
  }
  
  // 2. Check vertical matches (same logic, swap row/col)
  // ... (similar code)
  
  return MatchResult(matches: allMatches);
}
```

**Time Complexity:** O(rows × cols)  
**Space Complexity:** O(matches found)

---

### **Gravity Algorithm**

```dart
Future<void> applyGravity() async {
  bool anyMovement = true;
  
  while (anyMovement) {
    anyMovement = false;
    
    // Scan from bottom to top
    for (int col = 0; col < cols; col++) {
      for (int row = rows - 1; row >= 0; row--) {
        // If cell is empty, check above for tiles to fall
        if (cells[row][col].tileTypeId == null) {
          // Find first tile above
          for (int r = row - 1; r >= 0; r--) {
            if (cells[r][col].tileTypeId != null) {
              // Move tile down
              cells[row][col].tileTypeId = cells[r][col].tileTypeId;
              cells[r][col].tileTypeId = null;
              anyMovement = true;
              break;
            }
          }
        }
      }
    }
  }
}
```

**How it works:**
1. Scan bottom-to-top, left-to-right
2. For each empty cell, find tile above it
3. Move tile down one step
4. Repeat until no more movement

**Why a loop?** Tiles might need to fall multiple rows.

---

## 🎯 Performance Optimizations

### **1. Object Pooling**

Instead of creating/destroying particles constantly:
```dart
// Reuse particle objects
final particlePool = <Particle>[];

Particle getParticle() {
  return particlePool.isNotEmpty 
    ? particlePool.removeLast()
    : Particle();  // Create only if pool empty
}

void returnParticle(Particle p) {
  particlePool.add(p);  // Recycle
}
```

### **2. Batch Operations**

```dart
// ❌ Bad: Clear tiles one at a time
for (coord in coordsToClear) {
  await clearTile(coord);  // 100ms animation × 10 tiles = 1 second!
}

// ✅ Good: Clear all at once
await clearTiles(coordsToClear);  // 100ms total
```

### **3. Lookup Tables (Maps)**

```dart
// ❌ Bad: Linear search O(n)
TileComponent? findTile(int instanceId) {
  for (var tile in allTiles) {
    if (tile.instanceId == instanceId) return tile;
  }
}

// ✅ Good: Hash lookup O(1)
final Map<int, TileComponent> tilesByInstanceId = {};
TileComponent? findTile(int instanceId) {
  return tilesByInstanceId[instanceId];
}
```

### **4. Reduced Resolution on Windows**

```dart
camera: CameraComponent.withFixedResolution(
  width: Platform.isWindows ? viewportWidth * 0.75 : viewportWidth,
  height: Platform.isWindows ? viewportHeight * 0.75 : viewportHeight,
);
```

Renders at 75% resolution on desktop, then scales up (looks the same, but faster).

---

## 🚀 Learning Path

### **If you're new to programming:**
1. Start with **main.dart** - understand the app lifecycle
2. Read **grid_model.dart** - learn data structures
3. Study **coord.dart** - see how objects can have methods
4. Look at **game_state_model.dart** - understand state management

### **If you know basics:**
1. Dive into **board_controller.dart** - see complex algorithms
2. Explore **special_tile_spawner.dart** - pattern recognition
3. Study **tile_component.dart** - animations and rendering
4. Analyze **special_vfx_dispatcher.dart** - architectural patterns

### **Advanced topics:**
1. **Flame engine integration** - how game engines work
2. **Async programming** - coordinating animations
3. **Algorithm optimization** - performance tuning
4. **Architecture patterns** - MVC, singleton, dependency injection

---

## 📝 Common Code Patterns You'll See

### **Factory Constructors**

```dart
factory Coord.fromJson(Map<String, dynamic> json) {
  return Coord(
    json['row'] as int,
    json['col'] as int,
  );
}
```

Creates objects from JSON data (for loading levels).

### **Extension Methods**

```dart
extension CoordUtils on Coord {
  bool isAdjacent(Coord other) {
    // Add methods to existing classes
  }
}
```

### **Enums**

```dart
enum BlockerType {
  none,
  scooterTileBlocker,
}
```

Type-safe constants (can't misspell, compiler checks).

### **Getters**

```dart
class GameStateModel {
  int _movesRemaining;  // Private (underscore)
  
  int get movesRemaining => _movesRemaining;  // Public read-only access
}
```

Controlled access to internal data.

---

## 🎓 Key Takeaways

1. **Separation is key**: Models, Views, and Controllers should be distinct
2. **Data structures matter**: Right choice makes algorithms simpler
3. **Performance needs planning**: Pooling, batching, caching
4. **Error handling is critical**: Mobile apps must be robust
5. **Async is powerful**: Enables smooth animations and UX
6. **Code organization scales**: Clear structure = easy maintenance

---

## 🔍 Where to Explore Next

Want to modify the game? Here's where to look:

- **Add new tile types**: `stage_data.dart` + `tile_component.dart`
- **Change match rules**: `board_controller.dart` (detectMatches)
- **Add new power-ups**: `special_tile_spawner.dart` + new VFX file
- **Create new levels**: JSON files in `assets/stages/`
- **Modify UI**: `screens/` folder
- **Change sounds**: `audio/` folder + `sfx_manager.dart`

---

## 💡 Pro Tips

1. **Use the debugger**: Set breakpoints in VS Code to step through code
2. **Read error messages**: They tell you exactly what's wrong
3. **Start small**: Change one thing at a time
4. **Test frequently**: Run after each change
5. **Use version control**: Git saves your history (undo anytime!)

---

## 🎉 Congratulations!

You now understand the architecture of a production-quality match-3 game. The patterns here apply to many types of apps - not just games. Keep exploring, experimenting, and building!

---

**Questions to ponder:**
- How would you add multiplayer support?
- What if the board wasn't rectangular?
- How would you implement an undo feature?
- Could this run on the web? (Hint: Flutter supports it!)

Happy coding! 🚀
