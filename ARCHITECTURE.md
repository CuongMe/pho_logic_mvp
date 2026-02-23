# Phở Logic - Architecture Documentation

## Project Overview

**Phở Logic** is a Vietnamese-themed match-3 puzzle game built with Flutter and the Flame game engine. Players swap adjacent tiles to create matches of three or more identical Vietnamese food items (phở, bánh mì, gỏi cuốn, etc.) to complete objectives across 25+ stages. The game features special power-up tiles, blockers, visual effects, background music, and a persistent inventory system.

The project is designed for cross-platform deployment (Android, iOS, Web, Windows, macOS, Linux) and emphasizes a **data-driven architecture** where UI layouts and stage configurations are defined in JSON files rather than hardcoded in Dart.

---

## Project Structure

### High-Level Folder Organization

```
pho_logic/
├── lib/
│   ├── main.dart              # App entry point
│   ├── ads/                   # AdMob rewarded ad integration
│   └── src/
│       ├── app/               # Application root and routing
│       ├── audio/             # Sound effects and background music managers
│       ├── game/              # Core game logic and systems
│       ├── screens/           # UI screens (menu, gameplay, level select, settings)
│       ├── widgets/           # Reusable UI components
│       ├── utils/             # Logging, JSON helpers
│       └── res/               # Static resources (currently minimal)
├── assets/                    # Game assets (sprites, audio, JSON configs)
│   ├── audio/                 # BGM and SFX files + tuning JSON
│   ├── backgrounds/           # Background images per screen type
│   ├── boards/                # Board frame and bed sprites
│   ├── sprites/               # Tile sprites, particles, power-ups
│   ├── stages/                # Stage definition JSONs (stage_001.json - stage_025.json)
│   ├── json_design/           # UI layout JSONs (gameplay, menu, world/level select)
│   └── ...                    # Icons, HUD elements, win/lose screens
├── android/                   # Android platform configuration
├── ios/                       # iOS platform configuration
├── web/                       # Web platform configuration
├── windows/                   # Windows platform configuration
├── linux/                     # Linux platform configuration
├── macos/                     # macOS platform configuration
└── pubspec.yaml               # Dependencies and asset manifest
```

### Core Module Breakdown (`lib/src/`)

#### `app/`
- **Purpose:** Application root widget and navigation infrastructure
- **Key Files:**
  - `app.dart`: Root `PhoLogicApp` widget, theme configuration
  - `routes.dart`: Named route constants and route-to-widget mapping

#### `audio/`
- **Purpose:** Audio playback and management
- **Key Files:**
  - `sfx_manager.dart`: Singleton for sound effects (uses Flame AudioPool)
  - `bgm_manager.dart`: Singleton for background music playback and looping

#### `game/`
- **Purpose:** Core match-3 game logic, data models, and rendering
- **Subdirectories:**
  - `board/`: Board controller, tile components, special tile logic, visual effects
  - `model/`: Core data structures (`Coord`, `GridModel`, `MatchResult`)
  - `stages/`: Stage loading, validation, and data models (`StageData`)
  - `inventory/`: Power-up inventory system and persistence
  - `utils/`: Weighted random picker, debug logging
  - `vfx/`: Visual effect systems for special tiles

#### `screens/`
- **Purpose:** UI screens rendered with Flutter widgets
- **Subdirectories:**
  - `menu/`: Main menu screen
  - `gameplay/`: Core gameplay screen, pause/win/lose/no-moves modals, board viewport
  - `level_select/`: World/stage selection screen
  - `settings/`: Settings screen (audio toggles, privacy policy, etc.)

#### `widgets/`
- **Purpose:** Reusable UI components
- **Key Files:**
  - `number_sprite.dart`: Custom widget for rendering numbers as sprite sequences
  - `styled_button.dart`: Common button styles

#### `utils/`
- **Purpose:** Cross-cutting utilities
- **Key Files:**
  - `app_logger.dart`: Structured logging utility
  - `json_helpers.dart`: JSON parsing extensions

---

## Core Architecture Patterns

### 1. **JSON-Driven Design**

The game embraces a **separation of content from code** philosophy:

- **UI Layouts:** Screens (menu, gameplay, level select) define their visual structure in JSON files (`assets/json_design/`). Each JSON specifies background images, element positions, sizes, and metadata.
- **Stage Data:** Each stage (level) is defined in `assets/stages/stage_XXX.json` with grid dimensions, tile types, objectives, move limits, and blocker placements.
- **Audio Tuning:** Sound effect parameters (pitch, volume) are stored in `sfx_tuning.json` for easy iteration without code changes.

**Benefits:**
- Designers can modify layouts and stages without touching Dart code
- Rapid content iteration and A/B testing
- Clear separation of concerns

### 2. **Flutter + Flame Hybrid**

The project uses **Flutter for UI** and **Flame for game rendering**:

- **Flutter Widgets:** Handle screen navigation, HUD overlays, modals, menus
- **Flame GameWidget:** Renders the match-3 board as a `FlameGame` with sprite components
- **Integration:** `GameplayScreen1` embeds a `BoardViewport` (FlameGame widget) within a Flutter `Stack` alongside HUD elements

This hybrid approach leverages Flutter's UI toolkit for screens and Flame's optimized sprite rendering for the game board.

### 3. **State Management**

The project uses **Flutter's built-in `ChangeNotifier`** pattern for reactive state:

- **`GameStateModel`:** Tracks moves remaining, objective progress, blocker counts, win/lose conditions
- **`InventoryModel`:** Manages power-up counts and equipped belt slots
- **`GridModel`:** Represents the board grid state (tile positions, types, blockers, beds)

Screens listen to these models via `addListener()` and rebuild UI when state changes via `notifyListeners()`.

### 4. **Single Responsibility Principle**

The codebase follows domain-driven organization:

- **`BoardController`:** Handles game rules (swap validation, match detection, gravity, refill, cascades)
- **`SpecialTileSpawner`:** Determines which special tiles to spawn based on match patterns
- **`SpecialActivationResolver`:** Resolves special tile activation effects (which cells to clear)
- **`SpecialComboResolver`:** Handles special+special swap combinations
- **`StageLoader`:** Loads and validates stage JSON files
- **`InventoryRepository`:** Persists inventory data to SharedPreferences

Each class has a focused responsibility, making the system modular and testable.

---

## Data Flow and Game Loop

### Initialization Flow

```
main.dart
  ↓
Initialize Flutter bindings
  ↓
Initialize Google Mobile Ads SDK
  ↓
Initialize SfxManager and BgmManager
  ↓
Run PhoLogicApp (MaterialApp)
  ↓
Navigate to MenuScreen (initial route)
```

### Gameplay Flow

```
User selects stage from WorldScreen1
  ↓
Navigate to GameplayScreen1(stageId: N)
  ↓
GameplayScreen1 loads:
  - Stage JSON (grid, tiles, objectives)
  - UI design JSON (layout, elements)
  - Inventory model
  ↓
Build GridModel from stage data
  ↓
Create BoardController and GameStateModel
  ↓
Render board via BoardGame (Flame)
  ↓
User interacts with board (taps tiles to swap)
  ↓
BoardController validates swap → finds matches → spawns special tiles
  ↓
Clears matches → applies gravity → refills → cascade matches
  ↓
GameStateModel updates moves and objectives
  ↓
Check win/lose conditions → show modal
```

### Match-3 Core Loop

The `BoardController` orchestrates the match-3 mechanics:

1. **Swap Validation:** Check if two tiles are adjacent and swappable
2. **Match Detection:** Scan grid for 3+ consecutive identical tiles (horizontal/vertical)
3. **Special Tile Spawning:** Analyze match patterns (4-in-a-line, T-shapes, 5-in-a-line, 2x2 squares) to spawn power-ups
4. **Clear Phase:** Remove matched tiles, clear blockers, update objectives
5. **Gravity Phase:** Drop tiles to fill empty cells
6. **Refill Phase:** Spawn new tiles at the top
7. **Cascade Detection:** Recursively repeat if new matches form
8. **End Turn:** Decrement moves, check win/lose

All animations (tile movements, particle effects) are handled by Flame's `MoveEffect` and custom VFX components.

---

## Key Systems

### Stage System

**Data Model:**
- `StageData`: Represents a single stage/level
  - Grid dimensions (rows, columns)
  - Tile definitions (id, sprite path, weight, sound effect)
  - Bed types (destructible backgrounds)
  - Blocker types (obstacles on cells)
  - Tile map (initial tile placements)
  - Bed map (cell styles)
  - Objectives (collect X of tile Y, clear all blockers)
  - Move limit

**Loader:**
- `StageLoader.load(stageId)`: Reads `assets/stages/stage_XXX.json` and parses into `StageData`
- `StageValidator`: Validates JSON schema and required fields

**Objectives:**
- **Collect:** Gather N tiles of a specific type (e.g., 20 phở bowls)
- **Clear Blockers:** Remove all blocker overlays from the board

### Board System

**Components:**
- **`GridModel`:** 2D array of `Cell` objects
  - Each `Cell` contains: `tileTypeId`, `tileInstanceId`, `bedId`, `blocker`, `exists` flag
- **`BoardController`:** Mutates `GridModel` based on game rules
- **`BoardGame`:** Flame game that renders tiles as `TileComponent` sprites
- **`TileComponent`:** Flame sprite component for individual tiles
  - Handles move animations, selection highlighting, breathing effects
- **`BedComponent`:** Renders bed backgrounds per cell
- **`BlockerComponent`:** Renders blocker overlays on cells

**Coordinate System:**
- `Coord(row, col)`: Logical grid position
- `coordToWorld(Coord)`: Converts logical coord to screen pixels
- Grid placement configurable via JSON (anchor, offset, cell size)

### Special Tile System

**Special Tiles (Power-Ups):**
- **101/102 - Party Popper:** Clears a line (horizontal or vertical)
- **103 - Sticky Rice Bomb:** Clears 3x3 area
- **104 - Firecracker:** Clears X-pattern (diagonals)
- **105 - DragonFly:** Clears all tiles of two types

**Spawning Rules:**
- **4-in-a-line:** Spawns Party Popper (oriented with match direction)
- **5-in-a-line:** Spawns Sticky Rice Bomb
- **T/L-shape (5-6 tiles):** Spawns Firecracker
- **2x2 square around swap:** Spawns DragonFly

**Activation:**
- **Single Activation:** Tap or swap a special tile → `SpecialActivationResolver` determines affected cells → clear
- **Combo Activation:** Swap two special tiles → `SpecialComboResolver` combines effects

**Visual Effects:**
- Each special tile has a dedicated VFX dispatcher in `vfx/` (e.g., `party_popper_vfx.dart`)
- Renders particle bursts, animations, and audio cues on activation

### Inventory System

**Purpose:** Persistent power-up storage across sessions

**Data Model:**
- **`Inventory`:** PODO with `boosters` map (typeId → count)
- **`InventoryModel`:** ChangeNotifier wrapper for UI reactivity
- **`InventoryRepository`:** Handles SharedPreferences persistence

**Belt Slots:**
- UI displays 5 power-up slots (typeIds 101-105)
- Players can spend boosters to place special tiles on the board before making a move

**Rewarded Ads:**
- Players watch ads to earn power-ups (managed by `RewardedAdManager`)

### Audio System

**SfxManager:**
- Preloads sound effects into Flame `AudioPool` for low-latency playback
- Supports pitch variation and tuning via `sfx_tuning.json`
- Sound types: match bloops, tile pops, button clicks, win/lose stingers

**BgmManager:**
- Plays looping background music tracks
- Supports play, pause, stop, volume control
- Respects user settings (stored in SharedPreferences)

### UI System

**Screen Architecture:**
- Each screen is a `StatefulWidget` loaded via named routes
- Screens consume JSON design files to build their layouts
- **Example (GameplayScreen1):**
  - Loads `gameplay_1.json` for UI element positions
  - Renders background, HUD (moves counter, objectives), board viewport, pause button
  - Overlays modals (pause, win, lose, no moves) as needed

**Modals:**
- Pause, Win, Lose, No Moves modals are separate widgets shown via `showDialog()`
- Modals handle navigation (retry, next stage, return to menu)

---

## Information Architecture

### Screen Hierarchy

```
MenuScreen
  ├─ Navigate to WorldScreen1 (level select)
  ├─ Navigate to SettingsScreen
  └─ Navigate to HelpScreen

WorldScreen1
  ├─ Navigate to GameplayScreen1(stageId: 1..25)
  └─ Navigate back to MenuScreen

GameplayScreen1
  ├─ Display board, HUD, objectives
  ├─ Show PauseModal (navigate to menu or resume)
  ├─ Show WinModal → next stage or return to menu
  ├─ Show LoseModal → retry or return to menu
  └─ Show NoMovesModal → watch ad for 5 moves or return to menu
```

### State Ownership

- **Global State:**
  - `InventoryModel`: Shared across gameplay sessions (loaded once at app start)
  - `SfxManager` / `BgmManager`: Singletons for audio playback
  - `RewardedAdManager`: Singleton for ad lifecycle

- **Screen-Local State:**
  - `GameStateModel`: Created per gameplay session (tracks moves, objectives for that stage)
  - `GridModel`: Board state for current stage
  - `BoardController`: Game logic for current stage

- **Navigation:**
  - `navigatorKey`: Global key for programmatic navigation (e.g., from modals)

---

## Design Decisions

### Why JSON-Driven Design?

**Problem:** Hardcoding UI layouts in Dart makes iteration slow and tightly couples content to code.

**Solution:** Define layouts in JSON files that can be edited by designers without rebuilding the app.

**Trade-offs:**
- **Pros:** Fast iteration, designer-friendly, easy A/B testing
- **Cons:** No compile-time validation, runtime parsing overhead (mitigated by caching)

### Why Flame for Board Rendering?

**Problem:** Flutter's widget system is optimized for UI, not sprite-based game rendering.

**Solution:** Use Flame (a Flutter game engine) for efficient sprite batching and animation.

**Trade-offs:**
- **Pros:** 60 FPS sprite rendering, built-in effects system, component-based architecture
- **Cons:** Learning curve, separate rendering paradigm from Flutter widgets

### Why ChangeNotifier Over Provider/Riverpod?

**Problem:** Need simple reactive state without complex dependency injection.

**Solution:** Use Flutter's built-in `ChangeNotifier` with manual listener setup.

**Trade-offs:**
- **Pros:** No third-party dependencies, straightforward, sufficient for this scope
- **Cons:** Manual listener management (prone to leaks if not disposed), less ergonomic than Provider

### Why Singleton Managers for Audio/Ads?

**Problem:** Audio and ads are global concerns accessed from many parts of the app.

**Solution:** Implement singleton pattern with `instance` getter.

**Trade-offs:**
- **Pros:** Simple global access, no DI framework needed
- **Cons:** Hard to test, tight coupling (acceptable for utility systems)

---

## Extension Points

### Adding New Stages

1. Create `assets/stages/stage_XXX.json` with grid, tiles, objectives
2. Update route generation in `routes.dart` if needed (currently auto-generates 1-25)
3. Add stage button to `WorldScreen1` UI JSON

### Adding New Special Tiles

1. Define tile sprite and typeId (e.g., 106) in stage JSON
2. Implement spawning logic in `SpecialTileSpawner`
3. Implement activation logic in `SpecialActivationResolver`
4. Create VFX dispatcher in `vfx/` folder
5. Register in `SpecialVfxDispatcher` and `BoardGame`

### Adding New Screens

1. Create screen widget in `screens/`
2. Add route constant in `routes.dart`
3. Optionally create JSON design file in `assets/json_design/`
4. Implement navigation from existing screens

---

## Technology Stack

- **Framework:** Flutter 3.0+ (Dart SDK >=3.0.0)
- **Game Engine:** Flame 1.22.1
- **Audio:** Flame Audio 2.11.3, AudioPlayers 6.1.0
- **Storage:** SharedPreferences 2.3.5
- **Monetization:** Google Mobile Ads 5.2.0
- **Logging:** Logger 2.5.0
- **Utilities:** URL Launcher 6.3.2 (for external links)

---

## Performance Considerations

### Asset Loading

- **Preloading:** Audio files are preloaded at app start in `main.dart` to avoid lag during gameplay
- **Lazy Loading:** Stage JSONs are loaded on-demand when entering a stage
- **Caching:** Flame caches loaded sprites automatically

### Rendering Optimization

- **Sprite Batching:** Flame batches identical sprites into single draw calls
- **Component Pooling:** Particle effects use Flame's pooling system to reduce allocations
- **Selective Repaints:** ChangeNotifier ensures only affected widgets rebuild

### Memory Management

- **Dispose Patterns:** All `ChangeNotifier` instances are disposed when screens unmount
- **Flame Components:** Use `onRemove()` lifecycle method to clean up effects and listeners

---

## Testing Strategy

**Current State:** The project is in active development with minimal test coverage.

**Recommended Areas for Testing:**
- **Unit Tests:**
  - `BoardController` match detection logic
  - `SpecialTileSpawner` pattern recognition
  - `StageLoader` JSON parsing
- **Widget Tests:**
  - Screen rendering from JSON
  - Modal interactions
- **Integration Tests:**
  - Full gameplay flow (swap → match → win)
  - Inventory persistence

---

## Future Enhancements

- **Daily Challenges:** Procedurally generated stages with leaderboards
- **Multiplayer:** Real-time head-to-head matches
- **Social Features:** Share scores, gift power-ups
- **Animation Polish:** More sophisticated particle systems, victory sequences
- **Accessibility:** Colorblind mode, haptic feedback toggles

---

## Contributing

This is a portfolio/commercial project. For questions or collaboration inquiries, contact the developer through the repository.

---

## License

Proprietary. All rights reserved.
